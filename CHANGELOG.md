# Changelog

## 0.2.2

- Pausing now takes a full reading. Quit game and End Run are only reached from the pause menu, so a run closed that way keeps its final numbers instead of losing up to 30 seconds.

## 0.2.1

First fixes after an in-game test.

- A hit landing the moment a boss appears now counts on that boss.
- Positions are no longer saved again while the run clock stands still during a pick or a pause.

## 0.2.0

Full combat records, built from the game's addon API documentation. Saved format is now schema 2. Runs saved by 0.1.x stay as they are, and a run left open by 0.1.x is not resumed.

- Keeps the full damage and healing ledgers, with healing both received and performed, replacing the raw meter copies.
- Keeps names, icons and spell IDs for sources, and who owns each pet, summon and totem.
- Readings now include healing, damage taken, level, shield, gold, kills and enemies alive.
- Records when each level was reached.
- Follows boss and guardian health, enrage, and hits, crits and misses on each one.
- Boss fights are read while they run and include healing, so a fight replaced by the next or cut short keeps its numbers.
- Keeps the boss schedule and banners such as a boss slain or a friend down.
- Counts misses by spell and result, and keeps the biggest hit and biggest crit.
- The ability, talent, gear and jewelry list is read through the run, not once at 60 seconds.
- Records the client version, and tries once more for the game's summary when a run is left.
- Keeps the save under about 8 MB by dropping the oldest runs first.
- `/wlas` now shows what has been read, and which reads have failed.
- The paste code is now `WLAS2:` and adds healing, damage taken, affixes and the loadout.

## 0.1.5

- Run counters and damage taken stay fresh during a run, because Quit game leaves no official summary.

## 0.1.4

- Long text now scrolls inside the export window instead of spilling out of it.

## 0.1.3

- Hero, class and race now come from the game's run data. A Hunter run had been saved with the previous hero's class.

## 0.1.2

- A run closed by starting the next one keeps its own end time, instead of reading the new run's clock.
- The full meter table is kept fresh during a run, so a quit run still has it.
- A finished run left open by an older version counts as ended, not abandoned.

## 0.1.1

First fixes after an in-game test.

- Retries the world anchor read, whose first call only starts tracking.
- A finished run now closes at logout, so its export has an end time.
- Keeps far fewer raw hit samples, which were a third of the saved run.

## 0.1.0

First test build. Not yet tested in game.

- Records run identity, position, HP, meter by source, boss encounters, hit feed totals, phase anchors and combat line counts.
- Adds `/wlas`, `/wlas export`, `/wlas test` and `/wlas reset confirm`.
