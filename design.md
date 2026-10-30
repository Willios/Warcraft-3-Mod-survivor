# Warcraft Survivors - Design

## Vision

A Warcraft III solo survival map inspired by the run structure and presentation of Azeroth Survivors. The player chooses a Warcraft hero, moves through a zone while attacks and spells cast themselves, gathers experience, picks cards, and survives escalating waves and timed bosses.

The reference is a design guide, not an asset source. Everything is built at runtime from Warcraft III's own textures, icons, models and frames; the map needs no imports.

## Run

- **Length:** bosses at 2:00, 4:00, 6:00 and 8:00; the zone's final boss arrives at 10:00. Killing the final boss wins the run; the hero dying loses it.
- **Movement:** WASD or the arrow keys. The script moves the hero itself (`SetUnitX/Y` with a pathing probe) and the native Move and Attack abilities are removed, so the hero attacks while walking.
- **Basic attack:** every hero attacks the nearest enemy on its own. Ranged heroes fire their real Warcraft projectile, read from the unit's weapon data; melee heroes swing and cleave.
- **Spells:** each hero starts with one spell and has a pool of eight. About 100 spells share 11 behaviours: bolt, nova, zone, chain, line, orbit, aura, summon, heal, buff and passive. Up to 6 spell slots, ranks 1 to 5.
- **Pickups:** experience gems, gold, healing runes, magnets, and chests from elites and bosses.
- **Level-up:** the run pauses and deals 3 cards (4 with perks): new spells, spell ranks, and blessings (stat cards that take no slot). Rarity follows WoW item quality and adds power. Keys 1-4 pick; R rerolls; Banish and Skip come from perks.

### Scaling (from the creator's rebuild)

Taken from `crates/benilla-app/src/survivors/data.rs` and `enemies.rs` in [azeroth-survivors-re](https://github.com/OutThisLife/azeroth-survivors-re):

| Rule | Value here |
| --- | --- |
| Run progress `p` | 0 at the start, 1 when the final boss arrives |
| Enemy health | roster tier ladder (x1.12 per tier) x `(1 + 0.75p)` |
| Enemy damage | `(1 + 0.9p)` |
| Wave pool | three neighbouring roster tiers, walking up the roster in 30 steps |
| Spawner | tops up to `14 + 160p` alive (capped at 150 units for Warcraft III) every 0.12 s, at most 4 at a time |
| Encircling rings | half way between bosses, `28 + 60p` of the weakest tier |
| Experience | Vampire Survivors curve: `5 + 10(l-1)` below 20, `195 + 13(l-20)` below 40, then `455 + 16(l-40)`; gems are worth x2 |

## Difficulty (World of Warcraft model)

Difficulties open zone by zone: win Normal to open Heroic, Heroic to open Mythic, Mythic to open Mythic+.

| Difficulty | Health | Damage | Rewards | Loot item level |
| --- | --- | --- | --- | --- |
| Normal | x1.0 | x1.0 | x1.0 | base |
| Heroic | x1.6 | x1.4 | x1.5 | +10 |
| Mythic | x2.6 | x1.9 | x2.2 | +20 |
| Mythic +N | Mythic x 1.10^(N-1) | Mythic x 1.08^(N-1) | 2.2 + 0.15(N-1) | +20 + 2N, capped at +10 |

Keystones have no upper level. Affixes join as the key rises:

| Key | Affix | Effect |
| --- | --- | --- |
| +2 | Fortified | Non-boss enemies +20% health, +10% damage |
| +4 | Bursting | Slain enemies within 220 deal 0.6% max health to the hero, at most 8 bursts a second |
| +7 | Tyrannical | Bosses +40% health, +20% damage |
| +10 | Raging | Enemies below 30% health deal +50% damage |
| +12 | Xal'atath's Guile | No extra lives; dodge halved |

**Keystone timer:** killing the final boss within 45 s of its arrival upgrades the key by +3, within 80 s by +2, and within 120 s by +1. A timed key opens higher keys for that zone; a late kill still wins the run but the key is depleted. The **Mythic+ rating** adds `100 + 15 x level` for each zone's best timed key.

## Gear and upgrades

- 9 slots: Head, Shoulder, Chest, Waist, Legs, Feet, Wrist, Hands, Main Hand. Each slot gives one stat.
- Every boss drops a fixed piece (50% chance, 65% in Mythic+, +25% for the final boss, plus Keen Eye). Its item level is `100 + 10 x (zone tier - 1)` plus the difficulty bonus.
- A drop above the item level you own replaces it; a duplicate is salvaged for gold.
- **Upgrade track:** 6 steps of +3 item levels, paid in gold in the Armory tab.
- The highest item level piece in each slot is worn (marked **E**) and counts for every hero. A stat scales by `1 + (ilvl - 100) / 40`.

## Lobby

| Tab | Contents |
| --- | --- |
| Character | Faction filter (race emblems), hero grid, hero stats and spell pool, the real hero model in the world as a showcase, zone list with difficulty records, difficulty and keystone selector |
| Armory | Gear by zone and boss, item levels, upgrade track, equipped list and average item level |
| Codex | Every spell and blessing a run has offered |
| Talents | Permanent upgrades bought with gold |
| Achievements | 34 achievements, including keystone and gear ones |
| Rewards | Perks bought with achievement points (rerolls, banish, skip, opening hand, keen eye, lucky star, wide hand, second wind) |

Six zones re-theme the same arena with their own enemies, bosses, fog and time of day: Ashenvale, Westfall, The Barrens, Plaguelands, Felwood and Northrend. Winning a zone opens the next.

Progress is saved with Preload files to `Documents\Warcraft III\CustomMapData\WarcraftSurvivors\profile.pld`.

## Editor setup

1. Set the map script language to **Lua**.
2. Paste the full contents of [`src/ashenvale_survivor.lua`](src/ashenvale_survivor.lua) into the map-level **Custom Script Code** area.
3. Keep one Map Initialization trigger with the single custom script action `Survivor_Start()`.
4. Disable the default **Melee Initialization** trigger so its stock victory/defeat logic does not end the solo run.
5. Use an Ashenvale tileset, a medium or large map, and leave the playable area open. Player 12 (`CFG.ENEMY_PLAYER`, index 11) owns the enemies; leave that slot empty.

The previous prototype is kept in [`src/archive/ashenvale_survivor_v1.lua`](src/archive/ashenvale_survivor_v1.lua).

## Status and constraints

- The script was smoke-tested outside the game against a mock of the Warcraft III natives: lobby tabs, a Normal win, a timed Mythic +12, defeat, Play Again, save and load, an Armory upgrade, and all 25 heroes with full spell pools. It has not yet been run in a live Warcraft III session. Re-run it after changes with `pip install lupa` and `python tools/smoketest/run.py`.
- Things to check in game first: text fonts and sizes, the invisible click areas over buttons, the moved portrait and minimap, the lobby showcase camera (`CFG.PREVIEW_*`), and saving.
- Single player only: the save system and some unordered table walks would desync in multiplayer.
- Enemy and summon rawcodes that do not exist in the client fall back to a valid unit; icons come from the game data by rawcode, with a fallback name.
