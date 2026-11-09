# WoW Logs AS: notes for reviewers

WoW Logs AS records each Azeroth Survivors run into its own saved variables, so the player can upload the run to [WoW Logs](https://wow-logs.co.in/as-faq) for a run report. Current version: see `## Version:` in `WowLogsAS.toc`.

The addon only reads and stores. Uploading is done outside the game, by the player, with the WoW Logs website or the separate WoW Logs desktop uploader. The addon has no part in that.

## Files

| File | What it does |
|---|---|
| `WowLogsAS.toc` | Interface 11200, one saved variable: `WowLogsASDB` |
| `Util.lua` | Helpers: copying tables, rounding, size limits, JSON for the export code, chat output |
| `Recorder.lua` | Reads the game APIs on a timer and from combat chat events, and builds the run record |
| `Export.lua` | The `/wlas export` window: a read-only text box with the run as a paste code |
| `Core.lua` | Startup, events and the `/wlas` command |

Plain Lua 5.0. No libraries, no XML, no other addons needed.

## What it reads

Game APIs, all read-only. Each call goes through `A.Native`, which passes an exact argument count and catches errors:

- `AZS_GetMeterCapabilities`, `AZS_GetMeterContext`, `AZS_GetMeterSnapshot`, `AZS_GetMeterLoadout`: the damage meter's ledgers, readings and the hero's loadout.
- `AZS_GetCombatTextCapabilities`, `AZS_GetCombatTextEvents`: the combat text feed (hits, crits, misses).
- `AZS_GetWorldAnchorCapabilities`: whether world anchors exist. `AZS_GetWorldAnchors` is only checked for presence, never called.
- `AZS_GetPlayerPosition`, `AZS_GetRunSummary`, `AZS_GetRunTime`, `AZS_GetPhase`.
- The `AZS_ZONE` table: hero, class, race, zone and run fields. Copied, never changed.
- `UnitName("player")` and `UnitClass("player")`, used only when `AZS_ZONE` has no hero or class.
- `GetTime`, `time`, `GetLocale`, `GetBuildInfo`.

Events: `ADDON_LOADED`, `VARIABLES_LOADED`, `PLAYER_LOGOUT`, and these combat chat events, whose text is counted by type: `CHAT_MSG_COMBAT_SELF_HITS`, `CHAT_MSG_SPELL_SELF_DAMAGE`, `CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE`, `CHAT_MSG_COMBAT_PET_HITS`, `CHAT_MSG_SPELL_PET_DAMAGE`, `CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS`, `CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE`, `CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE`, `CHAT_MSG_SPELL_SELF_BUFF`, `CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS`.

## What it writes

- Only `WowLogsASDB`, saved by the game to `benilla-config/saved/WowLogsAS.lua` on desktop.
- Frames it creates: one event frame, and the export window (`WowLogsASExportFrame` with a scroll frame, an edit box and a close button), built only when `/wlas export` or `/wlas test` is typed.
- Messages to the default chat frame, for `/wlas` and when recording stops after an error.

It never changes settings, keybinds, CVars, the game's saves or other addons. It hooks no functions and replaces no globals except its own (`WowLogsAS`, `WowLogsASDB`, the `/wlas` slash command). It never reads level-up, lair or cache card offers, and never gives advice on picks.

## Network

None. It calls no `SendChatMessage`, `SendAddonMessage` or any other function that sends data, and uses no `loadstring` or `RunScript`. Data leaves the game only when the player uploads the saved file or pastes the export code on the WoW Logs website themselves.

## Privacy

- Each run stores the hero's name, class and race, the game's run ID, zone, client version and language.
- Co-op runs store the party's ledgers, which name the companions. The README tells players to check before sharing a file.
- Position samples are the hero's position in the run's map, once a second.
- No account name, realm, chat text or other players' messages are stored. Combat chat lines are counted, and a few are kept word for word as samples; those only ever hold combat text.

## Limits and safety

- Storage is bounded: 20 runs and about 8 MB in all (oldest dropped first), 3,600 position samples and 240 readings per run, and 200 rows per ledger. A run that hits a limit is marked `truncated`.
- The per-frame update runs inside `pcall`. After one error the addon stops recording for the session, keeps the message in `WowLogsASDB.lastError` and says so once in chat, so a failed read cannot raise an error every frame.
- `/wlas reset confirm` deletes all saved runs. Nothing else deletes data.

## Tests

`tests/spec.lua` runs the recorder against a fake game API and rejects syntax Lua 5.0 lacks. See the README for how to run it. The tests run on a newer Lua VM, so they don't replace testing in game.

## Releases

Release zips are built by `.github/workflows/release.yml` from the pushed commit when the toc version changes. Each zip holds one `WowLogsAS/` folder: the toc, the four Lua files, `README.md` and `CHANGELOG.md`. The addon is also listed on SurvivorsForge (`wowlogs-as`), which scans every release.
