-- Startup, events and slash commands.

local A = WowLogsAS

local COMBAT_EVENTS = {
    "CHAT_MSG_COMBAT_SELF_HITS",
    "CHAT_MSG_SPELL_SELF_DAMAGE",
    "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE",
    "CHAT_MSG_COMBAT_PET_HITS",
    "CHAT_MSG_SPELL_PET_DAMAGE",
    "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS",
    "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE",
    "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE",
    "CHAT_MSG_SPELL_SELF_BUFF",
    "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS",
}

local API_NAMES = {
    "AZS_GetMeterCapabilities",
    "AZS_GetMeterContext",
    "AZS_GetMeterSnapshot",
    "AZS_GetMeterLoadout",
    "AZS_GetCombatTextCapabilities",
    "AZS_GetCombatTextEvents",
    "AZS_GetWorldAnchorCapabilities",
    "AZS_GetWorldAnchors",
    "AZS_GetPlayerPosition",
    "AZS_GetRunSummary",
    "AZS_GetRunTime",
    "AZS_GetPhase",
}

function A.Init()
    WowLogsASDB = WowLogsASDB or {}
    local db = WowLogsASDB
    db.schema = A.schema
    db.version = A.version
    db.sequence = db.sequence or 0
    db.runs = db.runs or {}
    local env = { apis = {}, locale = GetLocale and GetLocale() or nil, checkedAt = A.Wall() }
    for i = 1, table.getn(API_NAMES) do
        env.apis[API_NAMES[i]] = type(getglobal(API_NAMES[i])) == "function"
    end
    env.meter = A.Copy(A.Native("AZS_GetMeterCapabilities", 0))
    env.combatText = A.Copy(A.Native("AZS_GetCombatTextCapabilities", 0))
    env.worldAnchors = A.Copy(A.Native("AZS_GetWorldAnchorCapabilities", 0))
    local version, build = A.Native("GetBuildInfo", 0)
    if type(version) == "string" then
        env.client = { version = version, build = type(build) == "string" and build or nil }
    end
    db.environment = env
end

local function lastRun()
    local runs = WowLogsASDB.runs
    return runs[table.getn(runs)]
end

local function rowCount(ledger)
    return ledger and table.getn(ledger.rows) or 0
end

local function status()
    local run = A.run
    if WowLogsASDB.lastError then
        A.Say("Last error: " .. WowLogsASDB.lastError)
    end
    A.Say(string.format("%s, %d saved runs.", run and "Recording" or "Waiting for a run", table.getn(WowLogsASDB.runs)))
    if run then
        local ledgers = run.ledgers
        A.Say(string.format(
            "Run %s: %d hits, %d misses, %d positions, %d readings, %d dropped.",
            tostring(run.gameRunId),
            run.hits.total,
            run.hits.kinds.miss or 0,
            table.getn(run.positions),
            table.getn(run.snapshots),
            run.hits.dropped
        ))
        A.Say(string.format(
            "Ledger rows: %d damage, %d healing received, %d healing performed. Loadout: %s.",
            rowCount(ledgers.damage),
            rowCount(ledgers.healingReceived),
            rowCount(ledgers.healingPerformed),
            run.loadout and "yes" or "no"
        ))
        A.Say(string.format(
            "%d bosses and guardians, %d banners, %d levels, about %d KB.",
            A.Count(run.units),
            table.getn(run.banners),
            table.getn(run.levels),
            math.ceil(A.Size(run) / 1024)
        ))
        if A.Count(run.apiErrors) > 0 then
            local names = {}
            for name in pairs(run.apiErrors) do
                table.insert(names, name)
            end
            table.sort(names)
            A.Say("Reads that failed at least once: " .. table.concat(names, ", ") .. ".")
        end
    end
end

local function command(message)
    local _, _, verb, rest = string.find(message or "", "^(%S*)%s*(.-)$")
    verb = string.lower(verb or "")
    if verb == "export" then
        local run = lastRun()
        if run then
            A.ShowText("Copy this run into WoW Logs", A.BuildCode(run))
        else
            A.Say("No run recorded yet.")
        end
    elseif verb == "test" then
        local size = math.max(1, math.min(1024, math.floor(tonumber(rest) or 64)))
        A.ShowText("Copy test: " .. size .. " KB", A.TestCode(size))
    elseif verb == "reset" then
        if rest == "confirm" then
            WowLogsASDB.runs = {}
            A.run = nil
            A.Say("Saved runs cleared.")
        else
            A.Say("Type /wlas reset confirm to delete all saved runs.")
        end
    elseif verb == "" or verb == "status" then
        status()
    else
        A.Say("/wlas status, /wlas export, /wlas test <KB>, /wlas reset confirm")
    end
end

local frame = CreateFrame("Frame", "WowLogsASFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
for i = 1, table.getn(COMBAT_EVENTS) do
    frame:RegisterEvent(COMBAT_EVENTS[i])
end
frame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" or (event == "ADDON_LOADED" and arg1 == "WowLogsAS") then
        if not A.ready then
            A.ready = true
            A.Init()
        end
    elseif event == "PLAYER_LOGOUT" then
        if A.run then
            -- The world may already be gone at logout, so a finished run closes on what it holds.
            if A.run.summary then
                A.run.status = "ended"
                A.run.closeReason = "logout"
                A.run.endedWall = A.Wall()
                A.run.endedT = A.run.summary.t
            end
            A.Anchor(A.run, "logout")
        end
    elseif event ~= "ADDON_LOADED" then
        A.OnCombatLine(event, arg1)
    end
end)
frame:SetScript("OnUpdate", function()
    -- One bad read must not raise an error every frame: stop recording and keep the reason.
    if A.failed then
        return
    end
    local ok, err = pcall(A.Update, arg1 or 0)
    if not ok then
        A.failed = true
        if WowLogsASDB then
            WowLogsASDB.lastError = tostring(err)
        end
        A.Say("Recording stopped after an error. /wlas status shows it.")
    end
end)

SLASH_WOWLOGSAS1 = "/wlas"
SlashCmdList["WOWLOGSAS"] = command
