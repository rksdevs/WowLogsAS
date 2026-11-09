-- Records one run at a time from the game's addon API. Reads only: it never sends messages,
-- changes settings, or reads level-up, lair or cache card offers. Every list here is bounded.
--
-- Scope: the combat report a player should get with no other addon. Stat sampling, pick history
-- and item tooltips are left to Azeroth Stats on purpose. The loadout is a plain end-of-run list.

local A = WowLogsAS

A.limits = {
    runs = 20,
    saveBytes = 8388608,
    positions = 3600,
    snapshots = 240,
    anchors = 400,
    sources = 128,
    missSources = 64,
    hitSamples = 24,
    syncLines = 120,
    incomingLines = 40,
    encounters = 32,
    ledgerRows = 200,
    descriptors = 400,
    actors = 200,
    units = 64,
    unitSources = 32,
    unitTrack = 240,
    levels = 200,
    banners = 200,
}

--- AZS_RUN fields kept with every reading, in the order `state` rows hold them.
A.stateFields = {
    "lvl", "xp", "xpn", "hp", "hpm", "sh", "gold", "ge", "kills", "dealt", "taken",
    "en", "el", "bu", "gu", "ga", "ek", "gk", "bk", "ck", "lives", "rr", "owed", "sl",
}

-- Every credit in the game's ledger. Received and performed healing are the same heals seen
-- twice, so a report must show them apart and never add them.
local SELF_LEDGERS = {
    { name = "damage", metric = "damage", scope = "self" },
    { name = "healingReceived", metric = "healing", perspective = "received", scope = "self" },
    { name = "healingPerformed", metric = "healing", perspective = "performed", scope = "self" },
}
local PARTY_LEDGERS = {
    { name = "partyDamage", metric = "damage", scope = "party" },
    { name = "partyHealing", metric = "healing", perspective = "performed", scope = "party" },
}

local SOURCE_FIELDS = { "kind", "attribution", "name", "rank", "abilityKey", "talentKey", "itemKey", "itemId", "variantKey" }
local ACTOR_FIELDS = {
    "kind", "name", "state", "classKey", "parentActorId", "currentOwnerId",
    "creatureEntry", "petFamilyKey", "summonKey", "totemKey",
}

-- A cache's how-to-buy banner is left out: it says nothing about the fight.
local BANNERS = {
    boss = true, finalboss = true, bossdown = true, guardian = true, achievement = true,
    unlocked = true, magnet = true, rune = true, downed = true, frienddown = true, revived = true,
}
local TRACKED_UNITS = { final = true, boss = true, guardian = true }

local SNAPSHOT_EVERY = 15 -- run seconds
local FEED_EVERY = 0.5 -- the feed keeps events for 5 seconds
local UNIT_TRACK_EVERY = 5 -- run seconds between saved boss health points
local LIVE = { playing = true, choosing = true, paused = true }
local TERMINAL = { dead = true, victory = true }

local feedClock, sampleClock = 0, 0

local function runTime()
    local t = A.Native("AZS_GetRunTime", 0)
    return type(t) == "number" and t or nil
end

local function push(list, value, limit, run)
    if table.getn(list) >= limit then
        run.truncated = true
        return false
    end
    table.insert(list, value)
    return true
end

local function pick(source, fields)
    local out = {}
    for i = 1, table.getn(fields) do
        local value = source[fields[i]]
        if value ~= nil then
            out[fields[i]] = A.Copy(value)
        end
    end
    return out
end

local function hasItems(list)
    return type(list) == "table" and list[1] ~= nil
end

local function rememberSource(run, sources, key)
    if not key or run.sources[key] or type(sources) ~= "table" or type(sources[key]) ~= "table" then
        return
    end
    if A.Count(run.sources) >= A.limits.descriptors then
        run.truncated = true
        return
    end
    local d = sources[key]
    local slot = pick(d, SOURCE_FIELDS)
    slot.icon = type(d.icon) == "table" and A.Copy(d.icon.path) or nil
    slot.spellIds = hasItems(d.spellIds) and A.Copy(d.spellIds, 2) or nil
    slot.origins = hasItems(d.originSourceKeys) and A.Copy(d.originSourceKeys, 2) or nil
    slot.related = hasItems(d.relatedSourceKeys) and A.Copy(d.relatedSourceKeys, 2) or nil
    run.sources[key] = slot
    if slot.origins then
        for i = 1, table.getn(slot.origins) do
            rememberSource(run, sources, slot.origins[i])
        end
    end
end

--- An actor's state moves on (a summon despawns), so a later read refreshes it.
local function rememberActor(run, actors, id)
    if not id or type(actors) ~= "table" or type(actors[id]) ~= "table" then
        return
    end
    local slot = run.actors[id]
    if slot then
        slot.state = A.Copy(actors[id].state) or slot.state
        return
    end
    if A.Count(run.actors) >= A.limits.actors then
        run.truncated = true
        return
    end
    run.actors[id] = pick(actors[id], ACTOR_FIELDS)
    rememberActor(run, actors, actors[id].parentActorId)
end

--- Compact `sourceKey=amount` rows, for the readings taken every few seconds.
local function compactRows(run, snapshot)
    local parts = {}
    if type(snapshot) ~= "table" or type(snapshot.rows) ~= "table" then
        return ""
    end
    for i = 1, table.getn(snapshot.rows) do
        local row = snapshot.rows[i]
        local key = row.sourceKey or row.rowId or row.name or "?"
        local amount = row.displayAmount or row.amount or 0
        rememberSource(run, snapshot.sources, row.sourceKey)
        table.insert(parts, tostring(key) .. "=" .. tostring(A.Round(amount, 0) or 0))
    end
    return table.concat(parts, ";")
end

local function compactTaken(taken)
    local parts = {}
    if type(taken) ~= "table" then
        return ""
    end
    for i = 1, table.getn(taken) do
        local row = taken[i]
        table.insert(parts, tostring(row.source or "?") .. "=" .. tostring(A.Round(row.dmg, 0) or 0))
    end
    return table.concat(parts, ";")
end

local function stateRow()
    local parts = {}
    local fields = A.stateFields
    local now = AZS_RUN or {}
    for i = 1, table.getn(fields) do
        local value = now[fields[i]]
        parts[i] = type(value) == "number" and tostring(A.Round(value, 1)) or ""
    end
    return table.concat(parts, ",")
end

local function query(runId, metric, scope, period, groupBy, perspective)
    return {
        apiVersion = 1,
        runId = runId,
        metric = metric,
        healingPerspective = perspective,
        scope = scope,
        period = period,
        groupBy = groupBy,
        windowSeconds = 0,
    }
end

local function note(run, key, err)
    if type(err) == "table" and err.code then
        run.apiErrors[key] = run.apiErrors[key] or {}
        local slot = run.apiErrors[key]
        slot[err.code] = (slot[err.code] or 0) + 1
    end
end

local function newestBanner()
    local list = AZS_BANNERS
    local newest = 0
    if type(list) == "table" then
        for i = 1, table.getn(list) do
            local id = list[i].id
            if type(id) == "number" and id > newest then
                newest = id
            end
        end
    end
    return newest
end

--- Oldest runs go first when the file would grow too large. Nothing here touches `keep`.
function A.TrimRuns(keep)
    local runs = WowLogsASDB.runs
    while table.getn(runs) > A.limits.runs do
        table.remove(runs, 1)
    end
    local total = 0
    for i = 1, table.getn(runs) do
        local old = runs[i]
        if old ~= keep then
            old.size = old.size or A.Size(old)
            total = total + old.size
        end
    end
    while total > A.limits.saveBytes and runs[1] and runs[1] ~= keep do
        total = total - runs[1].size
        table.remove(runs, 1)
    end
end

function A.NewRun(runId, context)
    local db = WowLogsASDB
    db.sequence = (db.sequence or 0) + 1
    -- The game's own zone line names the hero. UnitClass kept an earlier hero's class in testing.
    local zone = AZS_ZONE or {}
    local _, classToken = UnitClass("player")
    local run = {
        id = "wlas-" .. tostring(db.sequence),
        schema = A.schema,
        gameRunId = runId,
        authorityId = context and context.authorityId,
        uiSessionId = context and context.uiSessionId,
        partyState = context and context.partyState,
        partyId = context and context.partyId,
        language = context and context.languageCode,
        client = db.environment and A.Copy(db.environment.client),
        hero = zone.hero or UnitName("player"),
        class = zone.class or classToken,
        race = zone.race,
        zone = A.Scalars(AZS_ZONE),
        startedWall = A.Wall(),
        startedClock = GetTime(),
        addonVersion = A.version,
        status = "active",
        reloads = 0,
        readings = 0,
        stateFields = table.concat(A.stateFields, ","),
        lastBannerId = newestBanner(),
        anchors = {},
        positions = {},
        snapshots = {},
        encounters = {},
        ledgers = {},
        sources = {},
        actors = {},
        units = {},
        levels = {},
        banners = {},
        hits = {
            sources = {}, kinds = {}, misses = {}, results = {}, sample = {}, sampled = {},
            total = 0, amount = 0, dropped = 0, reads = 0, overflow = 0, seen = 0,
        },
        chat = { counts = {}, sync = {}, incoming = {} },
        apiErrors = {},
    }
    for i = 1, table.getn(db.runs) do
        local old = db.runs[i]
        if old.status == "active" then
            -- A run with an official summary finished; one without was cut off.
            old.status = old.summary and "ended" or "abandoned"
            old.endedT = old.endedT or (old.summary and old.summary.t) or old.lastT
        end
    end
    table.insert(db.runs, run)
    A.TrimRuns(run)
    return run
end

function A.Anchor(run, phase)
    push(run.anchors, {
        phase = phase or "none",
        wall = A.Wall(),
        clock = A.Round(GetTime(), 3),
        t = A.Round(runTime(), 2),
    }, A.limits.anchors, run)
end

--- One meter ledger, every credit with who dealt it, to whom and how. Rows come largest first, so
--- a cap only loses the smallest, and what it loses is counted.
function A.ReadLedger(run, spec)
    local snap, err = A.Native("AZS_GetMeterSnapshot", 1, query(run.gameRunId, spec.metric, spec.scope, "run", "detail", spec.perspective))
    note(run, "ledger:" .. spec.name, err)
    if not snap then
        return
    end
    local rows = type(snap.rows) == "table" and snap.rows or {}
    local kept, omitted, omittedAmount = {}, 0, 0
    for i = 1, table.getn(rows) do
        local row = rows[i]
        local amount = row.periodAmount or row.displayAmount or 0
        if i > A.limits.ledgerRows then
            omitted = omitted + 1
            omittedAmount = omittedAmount + amount
        else
            local out = {
                source = row.sourceKey,
                actor = row.actorId,
                owner = row.ownerId,
                amount = A.Round(amount, 2),
                proc = row.nativeProc and true or nil,
                periodic = row.periodicity == "periodic" and true or nil,
                reflected = row.reflection == "reflected" and true or nil,
                school = row.schoolState == "known" and row.schoolMask or nil,
                absorb = row.creditKind == "absorb_consumed" and true or nil,
                sourceOwner = row.sourceOwnerState ~= "known" and row.sourceOwnerState or nil,
                recipient = row.recipientActorId,
                origins = hasItems(row.originSourceKeys) and A.Copy(row.originSourceKeys, 2) or nil,
            }
            table.insert(kept, out)
            rememberSource(run, snap.sources, row.sourceKey)
            rememberActor(run, snap.actors, row.actorId)
            rememberActor(run, snap.actors, row.recipientActorId)
            if out.origins then
                for j = 1, table.getn(out.origins) do
                    rememberSource(run, snap.sources, out.origins[j])
                end
            end
        end
    end
    local context = snap.context or {}
    local totals = snap.totals or {}
    run.ledgers[spec.name] = {
        t = A.Round(context.asOfRunSeconds, 2),
        total = A.Round(totals.periodAmount or totals.displayAmount, 2),
        rows = kept,
        omitted = omitted > 0 and omitted or nil,
        omittedAmount = omitted > 0 and A.Round(omittedAmount, 2) or nil,
    }
end

--- A plain list of what the hero ended with. No tooltips, no history of when it was picked.
function A.ReadLoadout(run)
    local loadout, err = A.Native("AZS_GetMeterLoadout", 1, { apiVersion = 1, runId = run.gameRunId, ownerId = run.ownerId })
    note(run, "loadout", err)
    if not loadout or (run.loadout and run.loadout.revision == loadout.loadoutRevision) then
        return
    end
    local out = { revision = loadout.loadoutRevision, t = A.Round(runTime(), 1), abilities = {}, talents = {}, equipment = {}, jewelry = {} }
    local function add(list, entry)
        table.insert(list, entry)
        rememberSource(run, loadout.sources, entry.source)
    end
    local abilities = loadout.abilities or {}
    for i = 1, table.getn(abilities) do
        local a = abilities[i]
        add(out.abilities, {
            source = a.sourceKey, rank = a.rank, slot = a.slotId,
            selected = a.selected and true or nil, passive = a.passive and true or nil, learned = a.learned and true or nil,
        })
    end
    local talents = loadout.talents or {}
    for i = 1, table.getn(talents) do
        local a = talents[i]
        add(out.talents, { source = a.sourceKey, rank = a.rank, tree = a.treeKey })
    end
    local equipment = loadout.equipment or {}
    for i = 1, table.getn(equipment) do
        local a = equipment[i]
        if a.occupied then
            add(out.equipment, { source = a.sourceKey, slot = a.slotId, item = a.itemInstanceKey })
        end
    end
    local jewelry = loadout.runJewelry or {}
    for i = 1, table.getn(jewelry) do
        local a = jewelry[i]
        add(out.jewelry, { source = a.sourceKey, category = a.category, item = a.itemInstanceKey })
    end
    run.loadout = out
end

function A.TakeSnapshot(run, full)
    local damage, err = A.Native("AZS_GetMeterSnapshot", 1, query(run.gameRunId, "damage", "self", "run", "source"))
    note(run, "damage", err)
    local healing, healErr = A.Native("AZS_GetMeterSnapshot", 1, query(run.gameRunId, "healing", "self", "run", "source", "received"))
    note(run, "healing", healErr)
    push(run.snapshots, {
        t = A.Round(runTime(), 1),
        rows = compactRows(run, damage),
        heal = compactRows(run, healing),
        taken = compactTaken(AZS_TAKEN),
        state = stateRow(),
    }, A.limits.snapshots, run)
    run.readings = run.readings + 1
    -- Kept fresh every reading: a run closed with Quit game gets no official summary.
    run.taken = A.Copy(AZS_TAKEN)
    run.runFields = A.Scalars(AZS_RUN)
    run.schedule = A.Copy(AZS_SCHEDULE, 3)
    if full then
        for i = 1, table.getn(SELF_LEDGERS) do
            A.ReadLedger(run, SELF_LEDGERS[i])
        end
        if run.partyState and run.partyState ~= "solo" then
            for i = 1, table.getn(PARTY_LEDGERS) do
                A.ReadLedger(run, PARTY_LEDGERS[i])
            end
        end
        A.ReadLoadout(run)
    end
end

local function readEncounter(run, slot, enc)
    local snap, err = A.Native("AZS_GetMeterSnapshot", 1, query(run.gameRunId, "damage", "self", "encounter", "source"))
    note(run, "encounter", err)
    if snap then
        slot.final = compactRows(run, snap)
        slot.total = snap.totals and snap.totals.displayAmount
        slot.partial = enc.state ~= "completed" and true or nil
        local bosses = enc.bossActorIds or {}
        for i = 1, table.getn(bosses) do
            rememberActor(run, snap.actors, bosses[i])
        end
    end
    local healing, healErr = A.Native("AZS_GetMeterSnapshot", 1, query(run.gameRunId, "healing", "self", "encounter", "source", "received"))
    note(run, "encounterHealing", healErr)
    if healing then
        slot.healing = compactRows(run, healing)
    end
end

--- The game answers only for the current or last boss fight. A live fight is read as it goes, so
--- a fight replaced by the next one, or cut off by a quit, still has its numbers.
function A.TrackEncounter(run, context, closing)
    local enc = context and context.encounter
    if type(enc) ~= "table" or not enc.encounterId then
        return
    end
    local slot = run.encounters[enc.encounterId]
    if not slot then
        if A.Count(run.encounters) >= A.limits.encounters then
            run.truncated = true
            return
        end
        slot = { start = enc.startRunSeconds, bosses = A.Copy(enc.bossActorIds) }
        run.encounters[enc.encounterId] = slot
    end
    slot.state, slot.stop = enc.state, enc.endRunSeconds
    local t = runTime()
    local due
    if enc.state == "completed" then
        due = slot.partial or not slot.final
    elseif closing then
        due = true
    else
        due = t and t >= (slot.readT or slot.start or 0) + SNAPSHOT_EVERY
    end
    if due then
        slot.readT = t
        readEncounter(run, slot, enc)
    end
end

--- Bosses and guardians by the game's own id, which the hit feed names too. Elites are too many
--- to follow one by one, and the run's counters already count them.
function A.TrackUnits(run, t)
    local units = AZS_UNITS
    if not t or type(units) ~= "table" then
        return
    end
    for i = 1, table.getn(units) do
        local u = units[i]
        if TRACKED_UNITS[u.kind] and u.id then
            local key = tostring(u.id)
            local slot = run.units[key]
            if not slot then
                if A.Count(run.units) >= A.limits.units then
                    run.truncated = true
                else
                    slot = {
                        kind = u.kind, name = A.Copy(u.name), first = A.Round(t, 1),
                        hits = 0, amount = 0, crits = 0, max = 0, misses = 0, sources = {}, track = {},
                    }
                    run.units[key] = slot
                end
            end
            if slot then
                slot.last = A.Round(t, 1)
                slot.hp, slot.hpm = u.hp, u.hpm or slot.hpm
                if u.state == 1 and not slot.activeAt then
                    slot.activeAt = A.Round(t, 1)
                end
                if u.hp ~= slot.trackHp and t >= (slot.trackT or -UNIT_TRACK_EVERY) + UNIT_TRACK_EVERY then
                    slot.trackHp, slot.trackT = u.hp, t
                    if table.getn(slot.track) < A.limits.unitTrack then
                        table.insert(slot.track, tostring(A.Round(t, 1)) .. "," .. tostring(A.Round(u.hp, 0)))
                    end
                end
            end
        end
    end
end

--- Banners name what the meter cannot: bosses and guardians slain, and falls and revives in a party.
function A.ReadBanners(run, t)
    local list = AZS_BANNERS
    if type(list) ~= "table" then
        return
    end
    for i = 1, table.getn(list) do
        local b = list[i]
        if type(b.id) == "number" and b.id > (run.lastBannerId or 0) then
            run.lastBannerId = b.id
            if BANNERS[b.kind] then
                push(run.banners, { t = A.Round(t, 1), kind = b.kind, name = A.Copy(b.name) }, A.limits.banners, run)
            end
        end
    end
end

function A.ReadFeed(run)
    local hits = run.hits
    for _ = 1, 8 do
        local batch, err = A.Native("AZS_GetCombatTextEvents", 2, A.cursor, 256)
        if not batch then
            if type(err) == "table" and err.code == "STREAM_CHANGED" then
                A.cursor = nil
            end
            note(run, "feed", err)
            return
        end
        hits.reads = hits.reads + 1
        A.cursor = batch.cursor or A.cursor
        hits.dropped = hits.dropped + (tonumber(batch.droppedCount) or 0)
        hits.streamId = batch.streamId or hits.streamId
        local events = batch.events or {}
        for i = 1, table.getn(events) do
            A.CountHit(run, events[i])
        end
        if not batch.hasMore then
            return
        end
    end
end

--- A miss has no meter key, so misses are kept by spell. A report joins them to a source through
--- that source's `spellIds`.
local function countMiss(run, e, unit)
    local hits = run.hits
    local result = type(e.result) == "table" and tostring(e.result.key or "?") or "?"
    hits.results[result] = (hits.results[result] or 0) + 1
    if unit then
        unit.misses = unit.misses + 1
    end
    local key = tostring(e.sourceKind or "?") .. "|" .. (e.spellId and ("spell:" .. tostring(e.spellId)) or "melee")
    local row = hits.misses[key]
    if not row then
        if A.Count(hits.misses) >= A.limits.missSources then
            hits.overflow = hits.overflow + 1
            return
        end
        row = { name = A.Copy(e.abilityName) }
        hits.misses[key] = row
    end
    row[result] = (row[result] or 0) + 1
end

local function countOnUnit(unit, key, amount, critical)
    unit.hits = unit.hits + 1
    unit.amount = unit.amount + amount
    unit.max = math.max(unit.max, amount)
    if critical then
        unit.crits = unit.crits + 1
    end
    local row = unit.sources[key]
    if not row then
        if A.Count(unit.sources) >= A.limits.unitSources then
            return
        end
        row = { hits = 0, amount = 0, crits = 0, max = 0 }
        unit.sources[key] = row
    end
    row.hits = row.hits + 1
    row.amount = row.amount + amount
    row.max = math.max(row.max, amount)
    if critical then
        row.crits = row.crits + 1
    end
end

local function best(hits, field, key, e, amount)
    if amount > ((hits[field] and hits[field].amount) or 0) then
        hits[field] = { amount = amount, key = key, target = A.Copy(e.targetName), t = A.Round(runTime(), 1) }
    end
end

function A.CountHit(run, e)
    local hits = run.hits
    local kind = tostring(e.kind or "?")
    local sourceKind = tostring(e.sourceKind or "?")
    hits.kinds[kind] = (hits.kinds[kind] or 0) + 1
    hits.seen = hits.seen + 1
    -- One raw event of each shape, so a new kind of hit can be read in full.
    local shape = kind .. "|" .. sourceKind .. (e.reflected and "|reflected" or "")
    if not hits.sampled[shape] and table.getn(hits.sample) < A.limits.hitSamples then
        hits.sampled[shape] = true
        table.insert(hits.sample, A.Copy(e, 3, { left = 60 }))
    end
    local unit = e.targetUnitId and run.units[tostring(e.targetUnitId)]
    if kind == "miss" then
        countMiss(run, e, unit)
        return
    end
    local amount = tonumber(e.amount) or 0
    if kind ~= "damage" or amount <= 0 then
        return
    end
    hits.total = hits.total + 1
    hits.amount = hits.amount + amount
    local name = e.meterSourceKey or (e.spellId and ("spell:" .. tostring(e.spellId))) or e.abilityName or "?"
    local key = sourceKind .. "|" .. tostring(name)
    best(hits, "best", key, e, amount)
    if e.critical then
        best(hits, "bestCrit", key, e, amount)
    end
    if unit then
        countOnUnit(unit, key, amount, e.critical)
    end
    local row = hits.sources[key]
    if not row then
        if A.Count(hits.sources) >= A.limits.sources then
            hits.overflow = hits.overflow + 1
            return
        end
        row = { hits = 0, amount = 0, crits = 0, critAmount = 0, periodic = 0, max = 0, maxCrit = 0, spell = e.spellId, school = e.schoolMask, type = e.damageType }
        hits.sources[key] = row
    end
    row.hits = row.hits + 1
    row.amount = row.amount + amount
    row.max = math.max(row.max, amount)
    if e.critical then
        row.crits = row.crits + 1
        row.critAmount = row.critAmount + amount
        row.maxCrit = math.max(row.maxCrit, amount)
    end
    if e.periodic then
        row.periodic = row.periodic + 1
    end
    if e.reflected then
        row.reflected = (row.reflected or 0) + 1
    end
    -- Damage shields and the like float a number the meter never counts.
    if not e.meterSourceKey then
        row.unmetered = (row.unmetered or 0) + 1
    end
end

local function readSummary(run)
    local summary = A.Native("AZS_GetRunSummary", 0)
    if type(summary) == "table" and A.Count(summary) > 0 then
        run.summary = A.Scalars(summary)
    elseif A.Count(AZS_END or {}) > 0 then
        run.summary = A.Scalars(AZS_END)
    end
end

function A.Sample(run, phase, closing)
    local t = runTime()
    run.lastWall, run.lastClock = A.Wall(), A.Round(GetTime(), 3)
    local now = AZS_RUN or {}
    if t then
        run.lastT = A.Round(t, 2)
        -- The run clock stands still during a pick or a pause, so those seconds add no new position.
        local p = t > (run.lastPositionT or -1) and A.Native("AZS_GetPlayerPosition", 0)
        if p then
            run.lastPositionT = t
            push(run.positions,string.format("%.1f,%.1f,%.1f,%s,%s,%s", t, p.x or 0, p.y or 0, tostring(now.hp or ""), tostring(now.hpm or ""), tostring(now.sh or "")), A.limits.positions, run)
            run.spaceId = run.spaceId or p.spaceId
            run.mapId = run.mapId or p.mapId
        end
        if now.lvl and now.lvl ~= run.lastLevel then
            run.lastLevel = now.lvl
            push(run.levels, tostring(A.Round(t, 1)) .. "," .. tostring(now.lvl), A.limits.levels, run)
        end
        A.ReadBanners(run, t)
    end
    local context, err = A.Native("AZS_GetMeterContext", 0)
    note(run, "context", err)
    if context then
        run.ownerId = run.ownerId or context.localOwnerId
        run.authorityId = run.authorityId or context.authorityId
        run.partyState = context.partyState or run.partyState
        run.partyId = context.partyId or run.partyId
        run.language = run.language or context.languageCode
        A.TrackEncounter(run, context, closing)
    end
    if t and t >= (run.lastSnapshotT or -SNAPSHOT_EVERY) + SNAPSHOT_EVERY then
        run.lastSnapshotT = t
        local count = run.readings
        A.TakeSnapshot(run, count - math.floor(count / 2) * 2 == 0)
    end
    if TERMINAL[phase] then
        readSummary(run)
    end
end

function A.Finish(run, reason)
    if not run or run.status ~= "active" then
        return
    end
    -- The game has already moved on here, so this closes on what the run holds, not on live reads.
    -- Only the summary is worth one last try: leaving a run fills it, and a new run empties it.
    if not run.summary then
        readSummary(run)
    end
    run.status = "ended"
    run.closeReason = reason
    run.endedWall = run.lastWall or A.Wall()
    run.endedClock = run.lastClock
    run.endedT = (run.summary and run.summary.t) or run.lastT
    A.Anchor(run, "closed:" .. reason)
    if A.run == run then
        A.run = nil
    end
end

local function currentRunId()
    local id = AZS_ZONE and AZS_ZONE.run
    if id ~= nil and tostring(id) ~= "" then
        return tostring(id)
    end
    return nil
end

--- A run left open by /reload keeps its record, as long as the game's run ID still matches. One
--- saved by an older version has a different shape, so it stays as it is and a new record starts.
local function resumable(runId)
    local runs = WowLogsASDB.runs
    local last = runs[table.getn(runs)]
    if last and last.status == "active" and last.gameRunId == runId and last.schema == A.schema then
        last.reloads = (last.reloads or 0) + 1
        return last
    end
    return nil
end

function A.Update(elapsed)
    if not WowLogsASDB then
        return
    end
    feedClock, sampleClock = feedClock + elapsed, sampleClock + elapsed
    if A.run and feedClock >= FEED_EVERY then
        feedClock = 0
        -- Units first: a hit on a boss that has just appeared needs its slot to count against.
        A.TrackUnits(A.run, runTime())
        A.ReadFeed(A.run)
    end
    if sampleClock < 1 then
        return
    end
    sampleClock = 0
    local phase = A.Native("AZS_GetPhase", 0)
    local runId = currentRunId()
    local run = A.run
    if run and (not phase or runId ~= run.gameRunId) then
        A.Finish(run, phase and "new run" or "left run")
        run = nil
    end
    if not run and runId and LIVE[phase] then
        local context = A.Native("AZS_GetMeterContext", 0)
        run = resumable(runId) or A.NewRun(runId, context)
        A.run = run
        A.lastPhase = nil
        A.cursor = nil
    end
    if not run then
        return
    end
    local closing = false
    if phase ~= A.lastPhase then
        A.Anchor(run, phase)
        A.lastPhase = phase
        -- Quit game and End Run are only reached from the pause menu, and nothing can be read after
        -- them. The run clock has stopped by then, so a reading at the pause is the run's last word.
        closing = TERMINAL[phase] or phase == "paused"
        if closing then
            A.TakeSnapshot(run, true)
        end
    end
    A.Sample(run, phase, closing)
end

local INCOMING = { CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE = true, CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE = true }

--- Combat lines are counted, and a few are kept with both clocks so a log can be lined up exactly.
function A.OnCombatLine(eventName, text)
    local run = A.run
    if not run or not text then
        return
    end
    local chat = run.chat
    chat.counts[eventName] = (chat.counts[eventName] or 0) + 1
    if INCOMING[eventName] and table.getn(chat.incoming) < A.limits.incomingLines then
        table.insert(chat.incoming, A.Copy(text))
    end
    local now = GetTime()
    if now - (A.lastSync or 0) >= 15 and table.getn(chat.sync) < A.limits.syncLines then
        A.lastSync = now
        table.insert(chat.sync, { text = A.Copy(text), wall = A.Wall(), clock = A.Round(now, 3), t = A.Round(runTime(), 2) })
    end
end
