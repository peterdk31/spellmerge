# Horde: a mode for testing the mechanics on a lot of enemies

The owner, 2026-10-30: a separate game mode where the players hold out against a growing horde, to try the spell rules, the carriers and the engine on hundreds of enemies at once. It is **separate on purpose and easy to remove**: its own folders, and a short, listed set of hooks outside them (see "Removing it"). It is an exception to the strict milestone order, like the four in [ROADMAP.md](../ROADMAP.md); it builds nothing of M3's run structure (rewards, run, difficulty stay unbuilt).

Called **Horde** in code, files, commits and the game (owner, 2026-10-30), never after another game.

## Owner decisions (2026-10-30)

1. The name is Horde.
2. A walled arena of 1280×720 to start: at the co-op camera's widest zoom (0.5 at 640×360) it shows the whole arena, so four players always fit on one screen.
3. **500+ enemies at once.** The actor table grows from 512 to 1024 (H1), and the stress run gets a horde scenario that must hold it.
4. **Level-up card picks and time to build.** The party starts with a small bag; kills drop experience; each level-up offers every player their own pick of three cards, then a build break while the horde stands frozen.
5. **In every build** (`dev`, `preview`, `nightly`, `stable`): a "Horde" button on the main menu.

## The run

- **Start:** the main menu's Horde button sends `horde_requested(player)`. Flow loads like Play (`play_tasks`, the loading screen; no intro), builds the world in room `horde` (`content/rooms/horde/`) with a wizard per joined player, no waves and no dummies, sends `room_entered(&"horde")` and then `horde_started(world)`.
- **Staffs:** the four starter staffs in every build (not the `dev` staff, so it plays the same everywhere) with the usual start cards. **Bag:** the start cards only (`dash`, `fire`, `bolt`): the director sends `bag_set_requested(seat, bag)` for every wizard on `horde_started` and for a joiner on `player_joined`. The player keeps a set bag instead of filling it with every card (a set bag is never overwritten by the first fill).
- **The director** (`gameplay/horde/horde.gd`, autoload `Horde`) runs on the world from `horde_started` until `horde_ended` or the next `horde_started` (a restart: it forgets the old world and starts over). All its timing is in `step(delta)`, so tests drive it with fixed deltas.
- **Spawning:** enemies appear on a ring just outside the camera's view around the party's middle, clamped inside the arena's walls (the room's floor rect, a wall margin in), never closer than SPAWN_MIN_DISTANCE to a wizard. Who and how many comes from the curve, `gameplay/horde/horde_curve.tres` (a `HordeCurve` resource in the same folder): points of (seconds, spawns per second, cap alive, weights by enemy id). Between points it interpolates. At most SPAWN_PER_FRAME enemies per frame, so a burst never hitches. Missing enemy ids are skipped with one warning. Starting numbers: 1 per second and 30 alive at 0 s, 600 alive by 8 minutes. These are a first guess, tuned by playing.
- **The enemies** are ordinary enemy actors from `content/enemies/` (the registry), added under one `Horde` node in the world, so the director can find, count and freeze them. Mostly cheap swarmers (touch only, no staff; H4), with a growing share of the staff enemies (imps, crooks and the rest) so the horde also shoots. The director counts its own kills from `enemy_died` (only enemies under its node).
- **Experience:** each horde kill drops a gem where it died (one draw node for every gem, no node per gem; in the glow style). A wizard walking within PICKUP_RADIUS pulls it in, and it counts for the whole party: one shared level, so nobody falls behind. Next level: `xp_next(level)`, a slow curve.
- **Level-up:** every joined player gets their own `horde_picks_offered(seat, three card ids)`, drawn from the spell cards (`spells` in the registry, `SpellComponent`) that are not yet in their bag. The HUD shows them; `horde_pick_requested(seat, choice)` puts the card in that seat's bag (`bag_set_requested`) and sends `horde_pick_taken`. An open offer stays until picked. A level-up while one is open waits behind it, one offer per seat at a time. With every card owned, no offer.
- **Build break:** a level-up starts a fixed BUILD_BREAK (8 s, a first guess) for everyone: `horde_break_changed(seconds)`, the `Horde` node's processing is off (the horde stands frozen), no spawns, the enemies' shots in flight are cleared, and the builder is open as always (B). It ends on time, whoever is still picking or building (nobody waits for anyone); `horde_break_changed(0)`. A level-up during a break adds its offers but does not lengthen it.
- **Status:** `horde_status(seconds, kills, alive, level, xp, xp_next)` four times a second.
- **The end:** when every wizard is down (`player_downed`, `player_revived`, `player_joined`, `player_left`), the director sends `horde_over(seconds, kills, level)` and stops spawning. Flow restarts the run after HORDE_RESTART_DELAY (5 s, so the summary can be read) with a fresh world and `horde_started` again. Downed wizards are revived by teammates as in any run.
- **Leaving:** the pause menu works as in any run. Flow sends `horde_ended()` whenever a horde run stops or another run starts.

## Events (in `core/events/events.gd` since the foundation commit)

| Event | Sender | Listeners |
| --- | --- | --- |
| `horde_requested(player)` | HUD (main menu) | flow |
| `horde_started(world)`, `horde_ended()` | flow | horde, hud |
| `horde_status(seconds, kills, alive, level, xp, xp_next)` | horde | hud |
| `horde_picks_offered(player, card_ids)`, `horde_pick_taken(player, card_id)` | horde | hud |
| `horde_break_changed(seconds)` | horde | hud |
| `horde_over(seconds, kills, level)` | horde | hud |
| `horde_pick_requested(player, choice)` | HUD (the pick panel) | horde |
| `bag_set_requested(player, bag)` | horde | player |

## Scale: 500+ enemies

- **Actor table:** `Actors.ACTORS` 512 → 1024. `SpellTag` packs the caster in 9 bits (14-22, `FLAG` at 23), so the caster gets 10 bits (14-23), `FLAG` moves to bit 24, and every tag stays below `LIMIT` (1 << 29). Everything sized by `ACTORS` grows with it; the tests that name 512 follow.
- **The stress run** gets a `horde` scenario: 500 swarm enemies (touch only) plus a share of staff enemies, against four bots, in the horde arena; on desktop and on web. It reports the frame times like the others. The pass line is set after the first measurement, and the session writes down what costs the most.
- **Spawning and dying** must not hitch: a few spawns a frame, and enemies freed as today. If the measurement shows instantiating or freeing as a cost, recycling the director's enemies is the follow-up (H6), not a guess now.

### H1: what was built and the first numbers (2026-10-30)

- **Built:** `Actors.ACTORS` is 1024; `SpellTag` packs the caster in bits 14-23 (`CASTER_MASK` 1023) under `FLAG` at bit 24, so the largest tag is below 1 << 25 (`LIMIT` stays 1 << 29). The per-actor arrays grow with it (the spell runtime's per-staff rows are 4,096: a few hundred KB, allocated once). `Spells.step` counted down all 4,096 staff cooldowns every physics step (about 0.3 ms in GDScript); it now counts only up to the highest row that ever cast. Found by the horde run and fixed: `Projectiles.set_cap` to a smaller cap with shots alive past it read past its shrunk arrays (now it clears first).
- **The scenarios** (`tests/benchmark/stress_runner.gd`): `horde` (600 enemies, desktop only) and `horde, web` (500), each 10% staff enemies (the imp with 120 health) and 90% swarmers (the imp's body with no staff, 55 px/s, 3 touch damage; built in the runner, so it does not wait for H4), against the four bots, at the web cap of 500 shots, in the usual 640×360 room (the arena is H2's). They are not in the default run (they take longer than the rest together, and the exported runs have fixed timeouts): `godot --headless --path . --script res://tests/benchmark/stress.gd -- --horde`, or an exported test build with `--stress --horde`. They pass like the others (enemies and shots at 90% of the targets, every bot casts, spell hits, no errors) plus a provisional frame line: p95 under 600 ms headless (not checked on web).
- **Measured** (headless Linux, 24 threads under WSL, shared with other builds; game logic only, no rendering):

| Scenario | Enemies (mean) | Frame avg | p95 | Physics steps a frame |
| --- | --- | --- | --- | --- |
| `web` (100 enemies, 500 shots), for comparison | 100 | 8.7-17 ms | 16.5-31 ms | 0.5-1 |
| `horde` sweep, 300 enemies, 500 shots | 295 | 146 ms | 166 ms | 8 (the limit) |
| `horde` (600) | 556 | 271 ms | 319 ms | 8 |
| `horde, web` (500) | 490 | 232 ms | 267 ms | 8 |

  Past about 250 enemies a physics step costs more than its 16.7 ms, so the engine runs the most steps it may (8) every frame and the game falls behind real time (10 game seconds took about 20). At 600 a physics step costs about 31 ms: the enemies' own step 15 ms (their looks, `CreatureLook` and `Face`, 6.5 ms; the AI's `think` 6 ms; the mover 1.5 ms; caster and hurtbox under 1 ms), `move_and_slide` 1.7 ms, the projectile manager 5 ms (600 hurt circles in its target grid), Combat 1.7 ms, Spells 1.2 ms, and the rest (wizards, the run's own top-ups) about 6 ms. The per-enemy cost is about 50 µs a physics step all in. Instantiating and freeing did not show (at most 10 spawns a frame).
- **For the director (H3) and tuning (H6):** with one node-based actor per enemy, the realistic cap at 60 FPS is about **200-250 alive on desktop** and about **80-100 on web** (WASM GDScript is several times slower; the `web` scenario at 100 enemies is already at the budget there). The curve's 600 alive by 8 minutes holds only as a slow-motion game today. Reaching 500+ at 60 FPS needs a swarm without a node per swarmer (rows in packed arrays like the projectiles and `Entities`, drawn by one MultiMesh, a shared step for chase and touch, hurt circles in the target grid): the looks and the AI are two thirds of the enemy cost, and they would be one loop. Cheaper steps first, if a smaller win is wanted: step the looks of off-screen or idle enemies less often, and run the swarmers' AI retarget less often. Recycling instead of instantiating is not needed by these numbers.

## Parts

Built in parallel from the foundation commit (the events, this document, the ROADMAP line); each part is one branch and one PR, and touches only its own paths.

| # | Part | Paths | Delivers |
| --- | --- | --- | --- |
| H0 | **Foundation** | `core/events/events.gd`, `tests/core/test_events.gd`, `gameplay/README.md`, this file, `docs/ROADMAP.md` | The events and the contract above |
| H1 | **Scale** | `core/actors/`, `core/spells/spell_tag.gd`, what is sized by `ACTORS`, `tests/benchmark/`, their tests | 1024 actors, the tag's bits, the horde stress scenario and its first numbers |
| H2 | **Flow mode, arena and menu** | `gameplay/flow/`, `gameplay/player/` (the set bag), `content/rooms/horde/`, `hud/menus/main_menu/`, their tests | Flow's `mode` (`waves`, `sandbox`, `horde`; replaces `sandbox: bool`), the horde run as above, the 1280×720 arena, the Horde button, `bag_set_requested` in the player |
| H3 | **The director** | `gameplay/horde/`, `project.godot` (the autoload), `tests/gameplay/horde/` | Spawning, the curve, kills, gems, levels, offers, picks, the build break, status, the end |
| H4 | **Swarm enemies** | `content/enemies/<two new folders>` | Two cheap touch-only swarmers (art, data, scene, `assets.json`) |
| H5 | **The horde HUD** | `hud/panels/horde/`, `hud/panels/panels.tscn`, `hud/README.md` | The status line and experience bar, the per-seat pick cards, the break countdown, the end summary |
| H6 | **Tuning and recycling** | after H1-H5 merge | The curve's numbers by playing, enemy recycling if H1's numbers ask for it |

## Removing it

Delete `gameplay/horde/`, `content/rooms/horde/`, the swarm enemies' folders, `hud/panels/horde/`, `tests/gameplay/horde/` and this file. Then take out: the `Horde` autoload line in `project.godot`, the Horde button in `hud/menus/main_menu/`, the horde panel's node in `hud/panels/panels.tscn`, the `horde` mode in `gameplay/flow/flow.gd`, `bag_set_requested` in `gameplay/player/player.gd`, the horde events (in `events.gd`, `test_events.gd`, the table in `gameplay/README.md`), the horde stress scenario, and the ROADMAP line. The 1024-actor table stays (it costs little).
