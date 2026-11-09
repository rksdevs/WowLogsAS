-- A paste code for players with no file to upload, such as the browser edition. The window only
-- shows text: the player copies it by hand, and nothing is sent anywhere.

local A = WowLogsAS

local function quote(text)
    text = string.gsub(tostring(text), "\\", "\\\\")
    text = string.gsub(text, "\"", "\\\"")
    text = string.gsub(text, "[%z\1-\31]", " ")
    return "\"" .. text .. "\""
end

--- JSON for the plain values this file builds: a table with [1] is an array, otherwise an object.
function A.Json(value)
    local kind = type(value)
    if kind == "number" or kind == "boolean" then
        return tostring(value)
    end
    if kind == "string" then
        return quote(value)
    end
    if kind ~= "table" then
        return "null"
    end
    local parts = {}
    if value[1] ~= nil then
        for i = 1, table.getn(value) do
            table.insert(parts, A.Json(value[i]))
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(value) do
        table.insert(keys, tostring(k))
    end
    table.sort(keys)
    for i = 1, table.getn(keys) do
        table.insert(parts, quote(keys[i]) .. ":" .. A.Json(value[keys[i]]))
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

--- Summary only: no positions, hit samples, co-op companions or raw API tables.
function A.BuildCode(run)
    local last = run.snapshots[table.getn(run.snapshots)]
    local encounters = {}
    for id, e in pairs(run.encounters) do
        table.insert(encounters, { id = id, start = e.start, stop = e.stop, state = e.state, total = e.total })
    end
    local ledgers = run.ledgers or {}
    local totals = {}
    for _, name in ipairs({ "damage", "healingReceived", "healingPerformed" }) do
        totals[name] = ledgers[name] and ledgers[name].total
    end
    local body = {
        v = A.exportVersion,
        addon = run.addonVersion,
        runId = run.gameRunId,
        hero = run.hero,
        class = run.class,
        race = run.race,
        zone = run.zone and (run.zone.id or run.zone.zone or run.zone.name),
        heroic = run.zone and run.zone.heroic,
        affixes = run.zone and run.zone.affixes,
        started = run.startedWall,
        ended = run.endedWall,
        duration = run.endedT or (run.summary and run.summary.t),
        close = run.closeReason,
        summary = run.summary,
        sources = last and last.rows,
        healing = last and last.heal,
        taken = last and last.taken,
        totals = totals,
        loadout = run.loadout,
        encounters = encounters,
    }
    return "WLAS" .. tostring(A.exportVersion) .. ":" .. A.Json(body)
end

local function window()
    if A.frame then
        return A.frame
    end
    local f = CreateFrame("Frame", "WowLogsASExportFrame", UIParent)
    f:SetWidth(520)
    f:SetHeight(300)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    local label = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOP", f, "TOP", 0, -18)
    f.label = label
    -- A scroll frame clips the text to the window. A long code would otherwise spill past it.
    local scroll = CreateFrame("ScrollFrame", "WowLogsASExportScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -40, 20)
    local box = CreateFrame("EditBox", "WowLogsASExportBox", scroll)
    box:SetWidth(455)
    box:SetHeight(230)
    box:SetMultiLine(true)
    box:SetMaxLetters(0)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetScript("OnEscapePressed", function()
        f:Hide()
    end)
    scroll:SetScrollChild(box)
    f.box = box
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    A.frame = f
    return f
end

function A.ShowText(title, text)
    local f = window()
    f.label:SetText(title)
    f.box:SetText(text)
    f:Show()
    f.box:SetFocus()
    f.box:HighlightText()
    A.Say(string.format("%d characters ready. Press Ctrl+C to copy, Esc to close.", string.len(text)))
end

--- Fills the window with a known text, to measure how much the game lets a player copy.
function A.TestCode(size)
    local unit = "0123456789abcdef"
    local parts = {}
    local chunks = math.ceil(size * 1024 / string.len(unit))
    for i = 1, chunks do
        parts[i] = unit
    end
    return "WLASTEST:" .. tostring(size) .. ":" .. table.concat(parts, "") .. ":END"
end
