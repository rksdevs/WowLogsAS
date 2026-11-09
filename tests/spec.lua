-- Offline test of the recorder against a fake game API. Run with tests/run.js.

local failures, checks = 0, 0
local function check(ok, label)
    checks = checks + 1
    if not ok then
        failures = failures + 1
        print("FAIL: " .. label)
    end
end

-- Fake client.
local now = 100
GetTime = function() return now end
time = function() return 1793896552 + math.floor(now) end
GetLocale = function() return "enUS" end
UnitName = function() return "Inno" end
UnitClass = function() return "Mage", "MAGE" end
getglobal = function(name) return _G[name] end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
UIParent = {}
SlashCmdList = {}
local handlers = {}
CreateFrame = function()
    local f = {}
    function f:RegisterEvent() end
    function f:SetScript(name, fn) handlers[name] = fn end
    return f
end

local phase, runT = "playing", 0
local calls = { extraArgs = 0, feed = 0 }
local pending = {}
AZS_ZONE = { run = "run-1", id = "elwynn", heroic = 3, affixes = "sanguine", class = "hunter", hero = "Innohunt", race = "Orc" }
AZS_RUN = { hp = 200, hpm = 400, sh = 15, lvl = 1, kills = 0, dealt = 75.26 }
AZS_END, AZS_TAKEN = {}, { { source = "mob melee", dmg = 12 }, { source = "area", dmg = 3 } }
AZS_SCHEDULE = { { index = 1, at = 180, name = "Hogger", final = 0, state = "due" } }
AZS_UNITS = {}
-- An old banner from the run before must not reach this run.
AZS_BANNERS = { { id = 5, kind = "bossdown", name = "Old Boss", time = 1 } }
GetBuildInfo = function() return "1.12.1", "5875", "Sep 19 2006", 11200 end
AZS_GetPhase = function() return phase end
AZS_GetRunTime = function() return runT end
AZS_GetPlayerPosition = function() return { x = 1.25, y = 2.5, spaceId = "s1", mapId = 5 } end
local context = { runId = "run-1", authorityId = "auth", localOwnerId = "me", partyState = "solo", languageCode = "en" }
-- Mirrors the real API, which rejects any argument, even nil, on a no-argument call.
AZS_GetMeterContext = function(...)
    if select("#", ...) ~= 0 then calls.extraArgs = calls.extraArgs + 1; return nil, { code = "INVALID_ARGUMENT" } end
    return context
end
AZS_GetMeterCapabilities = function() return { apiVersion = 1 } end
AZS_GetCombatTextCapabilities = function() return { apiVersion = 1 } end
AZS_GetWorldAnchorCapabilities = function() return { apiVersion = 1 } end
AZS_GetWorldAnchors = function() return nil, { code = "NOT_READY" } end
local loadoutRevision, loadoutReads = "rev1", 0
AZS_GetMeterLoadout = function(q)
    loadoutReads = loadoutReads + 1
    return {
        loadoutRevision = loadoutRevision,
        sources = {
            ["ability:fireball:r1"] = { kind = "ability", name = "Fireball", rank = 1 },
            ["talent:mage.ignite:r2"] = { kind = "talent", name = "Ignite" },
            ["item:109000"] = { kind = "item", name = "Novice's Circlet", itemId = 109000 },
            ["jewel:spell_power:r1"] = { kind = "item", name = "Ring of Spell Power" },
        },
        abilities = { { sourceKey = "ability:fireball:r1", learned = true, selected = true, passive = false, rank = 1, slotId = 1 } },
        talents = { { sourceKey = "talent:mage.ignite:r2", rank = 2, treeKey = "tree:mage.1" } },
        equipment = { { slotId = 0, supported = false, occupied = false }, { slotId = 1, occupied = true, sourceKey = "item:109000", itemInstanceKey = "inv:1:109000" } },
        runJewelry = { { sourceKey = "jewel:spell_power:r1", category = "ring", itemInstanceKey = "j1" } },
    }
end
local summaryOnEnd
AZS_GetRunSummary = function() return summaryOnEnd end
local badQueries = 0
local extraRows = 0
AZS_GetMeterSnapshot = function(q)
    -- Mirrors the real API, which refuses a healing view on a damage query.
    if q.metric == "damage" and q.healingPerspective ~= nil then badQueries = badQueries + 1 end
    if q.scope == "party" and context.partyState == "solo" then return nil, { code = "NO_PARTY" } end
    local base = { context = { asOfRunSeconds = runT }, query = q,
        sources = {
            ["ability:fireball:r1"] = { kind = "ability", name = "Fireball", rank = 1, spellIds = { 133 },
                icon = { status = "ready", path = "Interface\\Icons\\Fire" }, originSourceKeys = { "talent:mage.ignite:r2" } },
            ["talent:mage.ignite:r2"] = { kind = "talent", name = "Ignite" },
            ["leech"] = { kind = "system", name = "Leech" },
        },
        actors = {
            H1 = { kind = "hero", name = "Innohunt", state = "present", classKey = "hunter" },
            P1 = { kind = "pet", name = "Wolf", state = "present", parentActorId = "H1", petFamilyKey = "wolf" },
            E1 = { kind = "enemy", name = "Hogger" },
        } }
    if q.groupBy == "detail" then
        base.totals = { periodAmount = q.metric == "damage" and 300.5 or 40 }
        base.rows = {
            { sourceKey = q.metric == "damage" and "ability:fireball:r1" or "leech", actorId = "P1", ownerId = "H1", periodAmount = 300.126,
              nativeProc = true, periodicity = "periodic", reflection = "not_reflected", schoolState = "known", schoolMask = 4,
              creditKind = "absorb_consumed", sourceOwnerState = "known", recipientActorId = q.metric == "healing" and "H1" or nil,
              originSourceKeys = { "talent:mage.ignite:r2" } },
        }
        for i = 1, extraRows do
            table.insert(base.rows, { sourceKey = "x" .. i, actorId = "H1", ownerId = "H1", periodAmount = 1, schoolState = "unknown", sourceOwnerState = "unowned" })
        end
    else
        base.totals = { displayAmount = 100 }
        base.rows = { { sourceKey = "ability:fireball:r1", displayAmount = 100.4 } }
    end
    return base
end
AZS_GetCombatTextEvents = function(cursor, limit)
    calls.feed = calls.feed + 1
    local batch = { cursor = "c" .. calls.feed, streamId = "st", events = pending, droppedCount = 0, hasMore = false }
    pending = {}
    return batch
end

dofile("Util.lua"); dofile("Recorder.lua"); dofile("Export.lua"); dofile("Core.lua")
local A = WowLogsAS

event = "VARIABLES_LOADED"; handlers.OnEvent()
check(WowLogsASDB.schema == 2, "db created")
check(WowLogsASDB.environment.apis.AZS_GetMeterSnapshot == true, "api presence recorded")
check(WowLogsASDB.environment.client.version == "1.12.1" and WowLogsASDB.environment.client.build == "5875", "client version recorded")

-- A run saved by 0.1.x, still open when the player updates: left alone, not resumed.
local oldRun = { schema = nil, status = "active", gameRunId = "run-1", hits = { total = 1 }, snapshots = {}, encounters = {}, anchors = {}, lastT = 12 }
table.insert(WowLogsASDB.runs, oldRun)

local function tick(seconds)
    for _ = 1, seconds do
        now = now + 1
        if phase == "playing" then runT = runT + 1 end
        arg1 = 1
        handlers.OnUpdate()
    end
end

pending = { { kind = "damage", amount = 50, sourceKind = "self", meterSourceKey = "ability:fireball:r1", critical = true, spellId = 133, schoolMask = 4, damageType = "spell", targetName = "Kobold" },
    { kind = "damage", amount = 25, sourceKind = "summon", meterSourceKey = "demon:melee" },
    { kind = "damage", amount = 7, sourceKind = "self", reflected = true, targetName = "Kobold" },
    { kind = "miss", sourceKind = "self", spellId = 133, abilityName = "Fireball", result = { key = "resist", text = "Resist" } },
    { kind = "miss", sourceKind = "pet", result = { key = "dodge" } } }
tick(1)
AZS_BANNERS = { { id = 5, kind = "bossdown", name = "Old Boss" }, { id = 6, kind = "cache", name = "" }, { id = 7, kind = "guardian", name = "Stonetusk" } }
AZS_RUN.lvl = 2
tick(69)
local run = A.run
check(run ~= nil and run.gameRunId == "run-1", "run started from game run id")
check(run ~= oldRun and oldRun.status == "abandoned", "a 0.1.x run is closed, not resumed")
check(run.hero == "Innohunt" and run.class == "hunter" and run.race == "Orc", "identity comes from the run, not UnitClass")
check(run.zone.heroic == 3 and run.zone.affixes == "sanguine", "heroic level and affixes kept")
check(run.client.version == "1.12.1", "run carries the client version")
check(run.authorityId == "auth", "authority id")
check(table.getn(run.positions) > 60, "positions sampled")
check(string.find(run.positions[1], ",200,400,15$") ~= nil, "position carries hp and shield")
check(table.getn(run.snapshots) >= 4, "snapshots every 15 run seconds")
check(string.find(run.snapshots[1].rows, "ability:fireball:r1=100", 1, true) ~= nil, "compact rows")
check(string.find(run.snapshots[1].heal, "ability:fireball:r1=100", 1, true) ~= nil, "healing kept over time")
check(run.snapshots[1].taken == "mob melee=12;area=3", "damage taken kept over time, all groups")
check(string.find(run.snapshots[1].state, "^1,,,200,400,15,", 1) ~= nil, "state row follows stateFields")
check(string.find(run.stateFields, "lvl,xp,xpn,hp", 1, true) == 1, "state row names its fields")
check(run.rawFirstSnapshot == nil and run.rawLastSnapshot == nil, "raw meter tables are gone")
check(run.levels[1] == "1,1" and run.levels[2] == "2,2", "level changes keep their run time")
check(table.getn(run.banners) == 1 and run.banners[1].name == "Stonetusk", "only this run's useful banners are kept")
check(run.schedule[1].name == "Hogger", "boss schedule kept")

-- Ledgers.
local dmg = run.ledgers.damage
check(dmg ~= nil and dmg.total == 300.5, "damage ledger keeps the game's total")
local credit = dmg.rows[1]
check(credit.source == "ability:fireball:r1" and credit.actor == "P1" and credit.owner == "H1", "credit says who dealt it")
check(credit.amount == 300.13, "credit amount rounded to two places")
check(credit.proc == true and credit.periodic == true and credit.reflected == nil, "credit flags")
check(credit.school == 4 and credit.absorb == true and credit.sourceOwner == nil, "credit school and kind")
check(credit.origins[1] == "talent:mage.ignite:r2", "credit says what triggered it")
check(run.ledgers.healingReceived.rows[1].recipient == "H1", "healing says who was healed")
check(run.ledgers.healingPerformed ~= nil, "both healing views read")
check(run.ledgers.partyDamage == nil and run.apiErrors["ledger:partyDamage"] == nil, "no party read in a solo run")
check(badQueries == 0, "damage queries never name a healing view")
check(run.sources["ability:fireball:r1"].name == "Fireball" and run.sources["ability:fireball:r1"].spellIds[1] == 133, "source names and spell ids kept")
check(run.sources["ability:fireball:r1"].icon == "Interface\\Icons\\Fire", "source icon path kept")
check(run.sources["talent:mage.ignite:r2"].name == "Ignite", "origin sources are described too")
check(run.actors.P1.petFamilyKey == "wolf" and run.actors.H1.classKey == "hunter", "pet parent is described too")

-- Loadout: a plain list, read again only when it changes.
check(run.loadout.revision == "rev1", "loadout read")
check(run.loadout.abilities[1].source == "ability:fireball:r1" and run.loadout.abilities[1].selected == true, "abilities listed")
check(run.loadout.talents[1].rank == 2 and run.loadout.talents[1].tree == "tree:mage.1", "talents listed")
check(table.getn(run.loadout.equipment) == 1 and run.loadout.equipment[1].slot == 1, "only worn slots listed")
check(run.loadout.jewelry[1].category == "ring", "jewelry listed")
check(run.sources["item:109000"].name == "Novice's Circlet", "item names kept")
local firstLoadout = run.loadout
AZS_RUN.kills = 42
tick(31)
check(run.loadout == firstLoadout, "same revision keeps the same record")
loadoutRevision = "rev2"
tick(31)
check(run.loadout.revision == "rev2", "a new pick is seen before the run ends")

check(run.runFields.kills == 42, "run counters stay fresh between full reads")
check(run.hits.amount == 82 and run.hits.total == 3, "hits counted")
check(run.hits.kinds.miss == 2, "misses counted apart")
check(run.hits.results.resist == 1 and run.hits.results.dodge == 1, "miss results counted")
check(run.hits.misses["self|spell:133"].resist == 1 and run.hits.misses["self|spell:133"].name == "Fireball", "misses kept by spell")
check(run.hits.misses["pet|melee"].dodge == 1, "pet swings that miss kept")
check(run.hits.sources["summon|demon:melee"].amount == 25, "summon source kept apart")
local fireball = run.hits.sources["self|ability:fireball:r1"]
check(fireball.maxCrit == 50 and fireball.critAmount == 50 and fireball.spell == 133 and fireball.school == 4, "crit detail and spell kept")
check(run.hits.best.amount == 50 and run.hits.best.target == "Kobold", "biggest hit kept")
check(run.hits.bestCrit.key == "self|ability:fireball:r1", "biggest crit kept")
check(run.hits.sources["self|?"].unmetered == 1 and run.hits.sources["self|?"].reflected == 1, "a hit the meter skips is marked")
check(table.getn(run.hits.sample) == 5, "one raw sample per shape of event")
check(calls.extraArgs == 0, "no-argument calls pass no arguments")

-- Bosses and guardians, by the id the hit feed names.
AZS_UNITS = { { kind = "boss", id = 900, name = "Hogger", hp = 1000, hpm = 1000, state = 0 },
    { kind = "elite", id = 901, name = "Brute", hp = 50, hpm = 50, state = 0 } }
tick(1)
check(run.units["900"] ~= nil and run.units["901"] == nil, "bosses followed, elites not")
pending = { { kind = "damage", amount = 40, sourceKind = "self", meterSourceKey = "ability:fireball:r1", critical = true, targetUnitId = 900 },
    { kind = "miss", sourceKind = "self", targetUnitId = 900, result = { key = "resist" } } }
AZS_UNITS[1].hp, AZS_UNITS[1].state = 600, 1
tick(6)
local hogger = run.units["900"]
check(hogger.amount == 40 and hogger.crits == 1 and hogger.misses == 1, "hit stats per boss")
check(hogger.sources["self|ability:fireball:r1"].max == 40, "sources per boss")
check(hogger.activeAt ~= nil and hogger.hp == 600 and hogger.hpm == 1000, "boss health and enrage")
check(table.getn(hogger.track) == 2, "boss health points follow changes, not every second")
-- A boss hit in the same moment it appears: the hit must still count on it.
AZS_UNITS = { { kind = "boss", id = 902, name = "Mother Fang", hp = 500, hpm = 500, state = 0 } }
pending = { { kind = "damage", amount = 11, sourceKind = "player", meterSourceKey = "ability:fireball:r1", targetUnitId = 902 } }
tick(1)
check(run.units["902"].amount == 11, "first hit on a new boss counts")
AZS_UNITS = {}

-- The run clock stands still during a pick, so no position is saved twice.
local positionsBefore = table.getn(run.positions)
phase = "choosing"; tick(5); phase = "playing"
check(table.getn(run.positions) == positionsBefore, "no repeat positions during a pick")
tick(1)
check(table.getn(run.positions) == positionsBefore + 1, "positions resume after a pick")

local fightStart = runT
context.encounter = { encounterId = "run-1:e1", startRunSeconds = fightStart, bossActorIds = { "E1" }, state = "active" }
tick(16)
check(run.encounters["run-1:e1"].partial == true and run.encounters["run-1:e1"].final ~= nil, "a live boss fight is read as it goes")
context.encounter = { encounterId = "run-1:e1", startRunSeconds = fightStart, endRunSeconds = 72, bossActorIds = { "E1" }, state = "completed" }
tick(2)
check(run.encounters["run-1:e1"].final ~= nil and run.encounters["run-1:e1"].partial == nil, "encounter total read when completed")
check(run.encounters["run-1:e1"].healing ~= nil, "encounter healing read")
check(run.encounters["run-1:e1"].stop == 72, "encounter end kept")
check(run.actors.E1.name == "Hogger", "boss actor described")

-- A fight never seen to complete keeps its last reading when the next fight replaces it.
context.encounter = { encounterId = "run-1:e2", startRunSeconds = runT, bossActorIds = { "E1" }, state = "active" }
tick(16)
context.encounter = { encounterId = "run-1:e3", startRunSeconds = runT, bossActorIds = { "E1" }, state = "active" }
tick(1)
check(run.encounters["run-1:e2"].final ~= nil and run.encounters["run-1:e2"].partial == true, "replaced fight keeps its numbers, marked partial")

-- Ledger cap: the smallest credits go, and what went is counted.
extraRows = A.limits.ledgerRows + 5
A.ReadLedger(run, { name = "damage", metric = "damage", scope = "self" })
check(table.getn(run.ledgers.damage.rows) == A.limits.ledgerRows, "ledger rows are capped")
check(run.ledgers.damage.omitted == 6 and run.ledgers.damage.omittedAmount == 6, "omitted credits are counted")
check(run.ledgers.damage.rows[2].school == nil and run.ledgers.damage.rows[2].sourceOwner == "unowned", "unknown school and owner stay honest")
extraRows = 0
A.ReadLedger(run, { name = "damage", metric = "damage", scope = "self" })
check(run.ledgers.damage.omitted == nil, "a later read clears the omitted count")

-- Party reads run only in a party.
context.partyState, context.partyId = "active", "party-1"
tick(31)
check(run.ledgers.partyDamage ~= nil and run.ledgers.partyHealing ~= nil, "party ledgers read in a party")
context.partyState, context.partyId = "solo", nil
run.partyState = "solo"

event = "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE"; arg1 = "Hogger's Bash hits you for 9."; handlers.OnEvent()
check(run.chat.counts[event] == 1, "combat line counted")
check(run.chat.incoming[1] == "Hogger's Bash hits you for 9.", "incoming spell line kept")
check(run.chat.sync[1].clock ~= nil and run.chat.sync[1].wall ~= nil, "sync line has both clocks")

-- Quit game is only reached from the pause menu, so a pause takes a full reading, once.
do
    local readings = table.getn(run.snapshots)
    run.ledgers.damage.t = -1
    context.encounter = { encounterId = "run-1:e5", startRunSeconds = runT, bossActorIds = { "E1" }, state = "active" }
    phase = "paused"; tick(3)
    check(table.getn(run.snapshots) == readings + 1, "a pause takes one reading")
    check(run.ledgers.damage.t == runT, "a pause refreshes the ledgers")
    check(run.encounters["run-1:e5"].final ~= nil, "a pause reads the boss fight")
    phase = "playing"; tick(1)
    local again = table.getn(run.snapshots)
    run.encounters["run-1:e5"].final = nil
    phase = "paused"; tick(2); phase = "playing"
    check(table.getn(run.snapshots) == again + 1 and run.encounters["run-1:e5"].final ~= nil, "every pause reads again")
end

phase = "choosing"; tick(3)
summaryOnEnd = { result = "defeat", kills = 7 }
local readingsBefore = table.getn(run.snapshots)
-- A fight begun moments before death has had no timed reading yet.
context.encounter = { encounterId = "run-1:e4", startRunSeconds = runT, bossActorIds = { "E1" }, state = "active" }
loadoutRevision = "rev3"
phase = "dead"; tick(2)
check(run.summary.result == "defeat", "summary kept at death")
check(table.getn(run.snapshots) == readingsBefore + 1, "death takes a closing reading")
check(run.loadout.revision == "rev3", "death reads the final loadout")
check(run.encounters["run-1:e4"].final ~= nil and run.encounters["run-1:e4"].partial == true, "death reads the fight it ended")
local phases = {}
for i = 1, table.getn(run.anchors) do phases[run.anchors[i].phase] = true end
check(phases.playing and phases.choosing and phases.dead, "phase anchors")

-- A /reload rebuilds addon state: the same game run must carry on in the same record.
A.run = nil
phase = "playing"; tick(2)
check(A.run == run and run.reloads == 1, "reload resumes the same run")
check(table.getn(WowLogsASDB.runs) == 2, "no duplicate run after reload")

AZS_ZONE = { run = "run-2", id = "elwynn" }; context.runId = "run-2"; summaryOnEnd = nil
context.encounter = nil
AZS_BANNERS = { { id = 8, kind = "bossdown", name = "Hogger" } }
tick(2)
check(run.status == "ended" and run.closeReason == "new run", "new run id closes the old run")
check(run.endedT ~= nil and run.endedT > 0, "old run keeps its own end time")
check(run.ledgers.damage ~= nil and run.loadout ~= nil, "ledgers survive without a terminal read")
check(A.run ~= run and A.run.gameRunId == "run-2", "new run opens")
check(table.getn(A.run.banners) == 0, "a new run starts past the banners already shown")

-- Leaving a run fills the summary after the last live second.
local leaving = A.run
leaving.summary = nil
summaryOnEnd = { result = "left", t = 3 }
AZS_GetPhase = function() return nil end
tick(2)
check(leaving.status == "ended" and leaving.summary.result == "left", "a run left keeps the game's summary")
summaryOnEnd = nil
AZS_GetPhase = function() return phase end
AZS_ZONE = { run = "run-2b", id = "elwynn" }
tick(2)
check(A.run.gameRunId == "run-2b", "the next run opens after leaving")

-- Bounds.
for i = 1, 200 do
    A.CountHit(A.run, { kind = "damage", amount = 1, sourceKind = "self", meterSourceKey = "k" .. i })
end
check(A.Count(A.run.hits.sources) == A.limits.sources, "source rows are capped")
check(A.run.hits.overflow > 0, "overflow is counted, not lost silently")
for _ = 1, 25 do A.NewRun("x", nil) end
check(table.getn(WowLogsASDB.runs) == A.limits.runs, "run history is capped")

-- Save size: the oldest runs go first, and the newest run always stays.
do
    local saved, savedLimit = WowLogsASDB.runs, A.limits.saveBytes
    local big = string.rep("x", 400)
    local first, second = { status = "ended", note = big }, { status = "ended", note = big }
    WowLogsASDB.runs = { first, second }
    A.limits.saveBytes = A.Size(second) + 10
    local fresh = A.NewRun("size-test", nil)
    check(WowLogsASDB.runs[1] == second and table.getn(WowLogsASDB.runs) == 2, "save limit drops the oldest run")
    A.limits.saveBytes = 1
    local newest = A.NewRun("size-test-2", nil)
    check(table.getn(WowLogsASDB.runs) == 1 and WowLogsASDB.runs[1] == newest, "the newest run survives any limit")
    check(fresh.status == "abandoned", "older runs are closed before trimming")
    WowLogsASDB.runs, A.limits.saveBytes = saved, savedLimit
end

-- Export.
local code = A.BuildCode(run)
check(string.sub(code, 1, 6) == "WLAS2:", "code prefix")
check(string.find(code, "\"runId\":\"run-1\"", 1, true) ~= nil, "code has the run id")
check(string.find(code, "positions", 1, true) == nil, "code leaves out positions")
check(string.find(code, "\"affixes\":\"sanguine\"", 1, true) ~= nil, "code has the affixes")
check(string.find(code, "\"healingReceived\":40", 1, true) ~= nil, "code has the healing total")
check(string.find(code, "talent:mage.ignite:r2", 1, true) ~= nil, "code has the plain loadout")
check(string.find(A.BuildCode(oldRun), "WLAS2:", 1, true) == 1, "a 0.1.x run still exports")
check(string.find(A.Json({ a = "x\"y\\z\n" }), "x\\\"y\\\\z ", 1, true) ~= nil, "json escapes text")
check(string.len(A.TestCode(1)) > 1024, "test code reaches the size asked for")

-- A finished run closes at logout, even when the world has gone.
local open = A.run
open.summary = { t = 42, result = "victory" }
event = "PLAYER_LOGOUT"; handlers.OnEvent()
check(open.status == "ended" and open.endedT == 42, "finished run closes at logout")
check(string.find(A.BuildCode(open), "\"duration\":42", 1, true) ~= nil, "export carries the duration")
open.status = "active"

-- /wlas prints without raising, on a live run and with failed reads to list.
A.run.apiErrors.loadout = { NOT_READY = 1 }
local said = {}
DEFAULT_CHAT_FRAME.AddMessage = function(_, text) table.insert(said, text) end
SlashCmdList.WOWLOGSAS("status")
DEFAULT_CHAT_FRAME.AddMessage = function() end
check(string.find(table.concat(said, "\n"), "Reads that failed at least once: loadout.", 1, true) ~= nil, "status lists failed reads")
A.run.apiErrors.loadout = nil

-- An abandoned run must not stay active for ever.
check(WowLogsASDB.runs[1].status == "abandoned", "cut-off run is marked abandoned")
local finished = A.NewRun("y", nil); finished.summary = { t = 9 }
A.NewRun("z", nil)
check(finished.status == "ended" and finished.endedT == 9, "finished run left open counts as ended")

-- An error in the recorder stops it once, and keeps the reason.
local goodUpdate = A.Update
A.Update = function() error("boom") end
arg1 = 1; handlers.OnUpdate(); handlers.OnUpdate()
check(A.failed == true and string.find(WowLogsASDB.lastError, "boom", 1, true) ~= nil, "errors stop recording once")
A.Update, A.failed = goodUpdate, nil

-- A missing API must not break anything.
local kept = AZS_GetMeterSnapshot
AZS_GetMeterSnapshot = nil
tick(20)
AZS_GetMeterSnapshot = kept
check(A.run.apiErrors.damage.MISSING ~= nil, "missing API recorded")

print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then error("tests failed") end
