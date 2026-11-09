# WoW Logs AS

Records run data for [Azeroth Survivors](https://wow.aethus.pl/) so a run can be analysed on WoW Logs. This is a test build, so its saved format may still change.

It works alongside Azeroth Stats and other addons, and needs nothing else installed. It records the combat report a player should get with no other addon. Stat history, pick history and item tooltips are left to Azeroth Stats on purpose.

## What it records

For each run, using the game run ID as the key:

- Hero, class, race, zone, Heroic level, affixes, language, party state, client version and the game's run ID.
- The game's full damage and healing ledgers: every credit, who dealt it, who it healed, its school, whether it was periodic, reflected or a proc, and what triggered it. Healing is kept both as received and as performed. A party's ledgers are kept too.
- Names, icons and spell IDs for every source, and who each pet, summon and totem belongs to.
- A reading every 15 run seconds: damage and healing by source, damage taken by group, and level, health, shield, gold, kills and enemies alive.
- A sample once a second: run time, position, health and shield.
- The time of each level reached.
- Boss and guardian health over time, enrage, and hits, crits and misses on each one.
- Damage and healing per boss fight, the boss schedule, and banners such as a boss slain or a friend down.
- Every hit from the game's combat text feed, counted by source: hits, crits, periodic ticks, biggest hit and biggest crit, plus misses by spell and result. One raw event of each kind is kept.
- A plain list of the abilities, talents, gear and jewelry the hero ended with.
- Each phase change with real time, game clock and run time, so a combat log can be lined up with the run.
- Counts of combat lines by type, and a few lines kept word for word.

The game gives no per-heal or per-hit data for hits on you, so healing is totals over time and boss spells are not named.

## What it never does

- It never sends anything. Addons cannot make web requests. Your data stays in your SavedVariables file until you choose to upload it.
- It never reads level-up, lair or cache card offers, or gives advice on picks.
- It never changes settings, keybinds, the game's saves or other addons.

Co-op recordings can include your companions' names. Check before sharing a file.

## Install

Download the release zip and unzip it so the path ends in `AddOns/WowLogsAS/WowLogsAS.toc`.

- **Windows / Linux:** Options, AddOns, Open AddOns Folder.
- **Browser:** Options, AddOns, Install AddOns, then pick the zip. Browser install is untested so far.

## Commands

| Command | What it does |
|---|---|
| `/wlas` | Shows recording status, what has been read so far, any reads that failed, and the last error |
| `/wlas export` | Shows the last run as a paste code, for players with no file to upload |
| `/wlas test 64` | Shows a test text of that many KB, to measure how much can be copied |
| `/wlas reset confirm` | Deletes all saved runs |

Data is written when you return to the main menu or close the game. On desktop it is usually at `benilla-config/saved/WowLogsAS.lua`.

## Limits

Everything saved is bounded: 20 runs and about 8 MB in all, oldest first, then 3,600 position samples and 240 readings per run. Each ledger keeps its 200 largest credits and counts what it left out. When a list fills up, the run is marked `truncated`.

Full ledgers and the loadout are read every 30 run seconds, whenever you pause, and when a run ends. Quit game gives no official summary, so a run closed that way has no recorded result.

## Development

Plain Lua 5.0, interface 11200: no `#`, no `%` operator, no `select`, no `string.gmatch`. Game calls go through `A.Native`, which passes an exact argument count because some calls reject extra arguments, even `nil`.

Tests run the recorder against a fake game API, and refuse syntax Lua 5.0 does not have. They run on a newer Lua VM, so they do not replace testing in game:

```sh
npm install --prefix /some/folder fengari
NODE_PATH=/some/folder/node_modules node tests/run.js
```

Releases follow the `## Version:` line in `WowLogsAS.toc`: bump it, update `CHANGELOG.md` and `RELEASE_NOTES.md`, and push to `main`.
