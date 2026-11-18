# Spawn styles: each biome (or enemy) names how its enemies spawn in

**Status (2026-11-18): approved; the owner answered its questions (the end of this document) and asked for it to be built now. AS1 done (the data, with no change on screen; "As built (AS1)" below); AS2 done (a style picked per body; "As built (AS2)"); AS3 and AS4 to come.** The owner asked whether it is easy to change the spawn animation or add new ones in other biomes, then asked for this plan.

Today (enemy spawning EA1–EA5, docs/milestones/enemy-spawning.md) the spawn has one look. A mark grows on the floor, then the body rises out of it. The look is written in `gameplay/feel/spawn_look.gd`:
- its timing is constants there (`MARK_END`, `CLOSE_FROM`, the frame counts);
- its length is `Actor.SPAWN_SECONDS`;
- its dust and sound are the one cue `enemy_spawn`.

Its colours already follow each room's floor, and its pacing is per-biome data (`SpawnRules`). A different animation for a biome or an enemy, though, means editing that file.

This plan makes the look **data a biome or an enemy names**, as cards name their behaviour. A new biome's spawn becomes a `.tres` (and art, if it wants), and a new kind of motion becomes a small piece of code in Feel, written once and used by any style.

## What a style is

`SpawnStyle` (`core/base/spawn_style.gd`, a `Resource`) is one folder per style, `content/spawn_styles/<id>/`: the `.tres`, its art if any, and an `assets.json`. Styles are found by folder, so there is no central list.

| Field | Meaning |
| --- | --- |
| `id` | the style's id, which the registry keys it by; it must match the folder's name (the validator checks) |
| `motion` | the kind of motion: `rise` (out of the floor, today's look) or `materialize` (out of nothing, AS3); one of `SpawnStyle.MOTIONS`, a list of names in core (Feel maps each name to its code, and a test checks the two match, as `ModifierBase.RULES` is split) |
| `seconds` | how long the spawn lasts (simulation: the body can't be hurt and can't act for this long), 0.3 to 2 s |
| `mark_end`, `close_from` | where the mark stage ends and where the mark starts to close, as shares of the spawn (today's 0.4 and 0.92) |
| `mark_frames`, `close_frames` | the frames the mark grows in and closes in (today's 4 and 3) |
| `mark_strip` | the mark's look: empty for the ring drawn from the floor's colours (today's look), or an art strip played over the mark stage (AS4) |
| `colours` | where the mark's (and `materialize`'s scan line's) colours come from, as a floor mark's: `floor` (the room's floor, today's ring) or a fixed colour of the game palette |
| `cue` | the cue played as the body starts to move (today's `enemy_spawn`); a biome's own dust and sound |
| `biomes` | the biomes it is the spawn of (as an enemy names its `biomes`) |

`problems()` checks it, as `SpawnRules` and `EnemyAdds` do:
- an id that isn't its folder's name;
- a motion `MOTIONS` doesn't have;
- `seconds` outside 0.3 to 2 s. The length decides how long a body can't be hurt, and content/ is open to contributors, so it has an upper bound too;
- the shares out of order;
- a stage too short for its frames at 60 fps (`SpawnStyle.CHECK_FPS`), with at least 3 frames a stage (docs/STYLE.md, "Smooth"). Today's close stage is (1 - 0.92) × 0.8 s = 64 ms, about 3.8 frames, so a shorter `rise` must close earlier;
- a cue or art that doesn't exist.

Across all styles, no two may name the same biome (`SpawnStyle.all_problems`, as `run_problems` does across runs), so no style wins silently by sort order. A test checks every style file and the set. No registration is needed: the registry's scan finds `content/spawn_styles/`.

**Which style an enemy gets** (`SpawnStyle.pick(registry, enemy, biome)`, a pure static function):
1. the enemy's own (`EnemyBase.spawn_style`, a style id, empty by default: the storm fork that always materializes, AS3);
2. else the first style by id that names the room's biome (`RoomBase.biome`);
3. else `rise`, the default.

`pick` lives in core/base, is pure and never names Feel, so Flow picking a style doesn't couple Flow to Feel. Today's look moves into `content/spawn_styles/rise/`, with the same numbers, so nothing changes on screen. `Actor.SPAWN_SECONDS` goes, and the length is always the style's.

## How it is built

- **The simulation knows only the length and the id.** Flow picks the style as it stands a body (it has the registry, the room and the enemy's data) and calls `Actor.spawn(style.seconds, style.id)`. `Actor.spawn_style: StringName` becomes state next to `spawn_seconds`, so every machine, a snapshot and a player who joins mid-spawn all draw the same style. Nothing in the simulation branches on the id. If no style is found at all (the `rise` folder deleted), Flow uses `rise`'s numbers kept as `SpawnStyle.DEFAULT`, and a test pins them to `content/spawn_styles/rise/`.
- **Feel draws from the id.** `SpawnLook` keeps what every style shares: walking the spawning bodies, the marks, the cue's spacing and the put-back. It hands each body to its style's motion:
  - `gameplay/feel/spawn_motions/`, one small `RefCounted` per motion, keyed in a `MOTIONS` table (motion is engine work, like a card's behaviour: `ModifierBase.RULES`);
  - each motion answers `apply(body, share, style)` and `put_back(body)`. `apply` runs in `cut()`, at `frame_pre_draw`, where today's cut already runs; `step()` only lays the marks and plays the cue;
  - **an id it doesn't know** (a style missing on another machine, an old snapshot, a deleted folder) draws as `rise`, so a body is never drawn whole mid-spawn;
  - Feel hands `SpawnLook` a style lookup (the registry, or a Callable), and `play_cue` takes the cue's id: `play_cue(cue, at, weighted)`. Today feel.gd plays the fixed `SpawnLook.CUE`;
  - the mark's colours (`_fill`, `_rim`, one pair today) become per style before AS4.
  - **`rise`** is today's code moved, unchanged: the clip parent and the shifted parts.
  - **`materialize`** (the owner, 2026-11-18: "materialize in from nothing, a cool sci-fi look"): the body is built up out of light, row by row, inside the game's palette and the Smooth rule (whole pixels, no fade, no blur, no glow gradients). It uses the same one clip per body as `rise`, but its mask is rows instead of one rect:
    - **The pad (the mark stage):** a ring in the style's colour (its `colours` source, as a mark's: the room's `floor` or a fixed colour of the game palette, docs/STYLE.md) draws in, with a 1-pixel rim that runs round it in 4 or more frames.
    - **The scan:** a bright 1-pixel line sweeps up from the feet to the top of the art. Behind it, the body's rows show **interlaced**: every 4th row first, then every 2nd, then all, each set over at least 3 frames. So the body is a striped ghost that fills in, never a fade.
    - **The glitch:** while the rows fill, the body's parts are shifted sideways by whole pixels, 1 or 2 now and then, settling to 0 in the last frames. The shift is rolled from Feel's own dice, view only.
    - **The landing:** the line reaches the top and goes out over 3 frames, the pad closes, and a few square `spark` motes come off the body's outline, through the cue.

    Its mask is up to the body's height in rows, one rect a row band, so it adds no render pass beyond `rise`'s.
- **The mark** is the ring drawn from the floor's colours by default. A style may instead give an art strip, played frame by frame over the mark stage and closed in its last frames, so a forest biome can have roots or a frost biome rime, as art.
- **Tests:**
  - every style file (`problems()`);
  - every style on every enemy and the boss's adds, in the way `test_card_rules.gd` plays every card on every carrier: each spawns in, lands on time, draws at least 3 frames a stage by whole pixels, and is drawn from state alone after a snapshot;
  - the picker's order;
  - determinism with two styles in one room.

## Steps

| Step | What | Areas |
| --- | --- | --- |
| AS1 | **The data, with no change on screen:** `SpawnStyle`, `MOTIONS`, `DEFAULT`, `content/spawn_styles/rise/` with today's numbers, `SpawnLook` reading the style's timings and cue instead of its constants, the `rise` motion moved into `spawn_motions/`, the validator and its test. The look's static helpers (`rise_shift`, `mark_radius`) take the style's numbers, so the 21 references in test_spawn_look.gd, test_spawn.gd, test_flow.gd and test_bot.gd are updated | core/base, content/spawn_styles, gameplay/feel, tests |
| AS2 | **Picked per body:** `SpawnStyle.pick`, `EnemyBase.spawn_style`, `Actor.spawn(seconds, style)` and `spawn_style` as state, Flow picking as it stands a body; tests for the picker, snapshots and determinism | core/base, gameplay/actor, gameplay/flow, tests |
| AS3 | **A second motion, to prove it:** `materialize`, with its own style `content/spawn_styles/materialize/`, its cue (sparks and a sound id) and `EnemyBase.spawn_style = &"materialize"` on the storm fork, so it shows in the crypt today (one line to move it to another enemy or a biome); the every-style-on-every-enemy test | gameplay/feel, content/spawn_styles, content/cues, tests |
| AS4 | **Art strips for the mark** (question 2) | gameplay/feel, content/spawn_styles, tests |

**As built (AS1):**
- `SpawnStyle` (core/base/spawn_style.gd) has the fields above. `DEFAULT` is a constant dictionary of `rise`'s numbers, since a constant can't be a Resource. Every field's default is read from it, so a style file only writes what it changes. `from_default()` makes a style of those numbers, which the look draws when it finds no style. `MOTIONS` is `[rise]` until AS3 adds `materialize`. `CHECK_FPS` is 60 and `MIN_FRAMES` 3.
- `problems(known_cue)` takes a cue lookup, as `BossIntro.problems` does. Three things differ from the plan's list:
  - An empty cue is no problem: none plays.
  - There is no separate check of the motion's stage. It holds the close's stage, so a close long enough is a motion long enough.
  - A `mark_strip` is reported as not drawn until AS4, so no style names art it doesn't show. AS4 replaces that line with the strip's real checks.
- `all_problems(styles, known_cue)` adds the one-style-a-biome check. The look doesn't read `colours` yet: every style is `floor`'s until AS3 draws the first that isn't.
- `content/spawn_styles/rise/rise.tres` writes every number out. It has no art, so no `assets.json`. `content/spawn_styles/README.md` is the guide.
- **`Actor.SPAWN_SECONDS` went in AS1, not AS2.** Flow's `spawn_seconds()` is the `rise` style's `seconds` from the registry, or `DEFAULT`'s with none. Every body still spawns in as `rise`, and AS2 replaces it with `pick`. `Actor.spawn(seconds)` is unchanged; `spawn_style` is AS2's.
- The registry's folder is `SpawnStyle.FOLDER` (`spawn_styles`), named once in core for Flow, Feel and the tests.
- **Feel.**
  - The motions are `SpawnLook.MOTIONS`, a constant table from each name to its script in `gameplay/feel/spawn_motions/`, and the look holds one object of each. There is no separate table file.
  - The base class `spawn_motion.gd` holds the measures every motion needs, moved from the look: `body_height`, `size_top`, `body_bottom`, the margin, and each body's kept `size_top`.
  - A motion answers `apply(body, share, style)` and `put_back(key, body)`, where `body` is null when it is gone, so the motion can still forget it.
  - `rise.gd` is EA2's cut, moved unchanged. `rise_shift` became `rise.gd`'s `shift(height, share, style)`, and `SpawnLook.mark_radius(radius, share, style)` takes the style.
  - The look's `style_of` is the lookup: Feel's `_spawn_style`, the registry's `spawn_styles`. Each id is looked up once and kept, and forgotten when Feel's registry changes. `style_for(body)` is `rise` for every body until AS2 reads `spawn_style`.
  - `play_cue(cue, at, weighted)` plays the style's cue. Its sound is spaced across every style.
- **Tests.**
  - `tests/core/test_spawn_style.gd` covers every style file and the set, holds `rise` to `DEFAULT`, and names each problem.
  - `tests/gameplay/feel/test_spawn_look.gd` adds three tests: Feel's motions are `SpawnStyle.MOTIONS`, the look draws by the style its lookup gives (marks, motion and cue, looked up once, and the default when none is found), and a motion it lacks is drawn as `rise`.
  - The helpers' references in test_spawn_look.gd, test_spawn.gd, test_flow.gd and test_bot.gd now take the style, its numbers or `Flow.spawn_seconds()`.
- **"Spawn", not "arrival"** (the owner, 2026-11-18, while AS1 was built: "Can we please call it spawn instead of arrival?"; everything, in this PR). This plan was `arrival-styles.md`, and enemy-spawning.md was `enemy-arrivals.md`. The names are now: `SpawnStyle` (`core/base/spawn_style.gd`), the folder `content/spawn_styles/` (the registry's `spawn_styles`, `SpawnStyle.FOLDER`), `SpawnLook` (`gameplay/feel/spawn_look.gd`) and `gameplay/feel/spawn_motions/`. The shipped system is renamed too:
  - the actor's `spawn(seconds)`, `spawn_left`, `spawn_seconds`, `is_spawning()` and `spawn_share()` (state members, so snapshots and the state hash read the new names);
  - Flow's `spawn_seconds()`, its `spawn_queue` (`RoomSpawning`, `room_spawning.gd`) and `_call_spawning`;
  - `SpawnRules` (`spawn_rules.gd`) and `MapRules.spawning` (content/runs/crypt.tres);
  - the cue and sound id `enemy_spawn`;
  - the tests' helper `tests/support/spawning.gd` (`Spawning.land`), and the tests and the screenshot (`shot_spawning.gd`) named after them.

  The step ids (EA1 to EA6, AS1 to AS4) and `run_room_paced` stay. A body's spawn points are still "spawns" (`enemy_spawns`); the act is "spawning".
- **No change on screen.** `tests/screenshots/shot_spawning.gd`'s strip was compared before and after, with the global seed pinned and particles off: identical to the pixel. The dust motes follow Feel's real clock and the run's enemies its random seed, so an unpinned strip differs between any two runs, on main too.

**As built (AS2):**
- `SpawnStyle.pick(registry, enemy, biome)` (core/base) is pure and never names Feel. Its order is the plan's, with two choices the code needed:
  - an id the registry lacks (the enemy's own misnamed, or deleted) is passed over to the next step, never an error. `tests/core/test_spawn_style.gd` checks that every style an enemy or boss names is one of the registry's, so a typo is not silent;
  - with no `rise` (or no registry) it returns `from_default()`, a style made of `DEFAULT`'s numbers.
- `EnemyBase.spawn_style` (empty by default). No content sets it yet: AS3 gives the storm fork `materialize`.
- `Actor.spawn(seconds, style)`: `spawn_style` is state next to `spawn_seconds`, and like it is kept once the body lands. A spawn of 0 seconds (or not a number) clears it. Nothing in the simulation reads it.
- Flow picks in `_stand_enemy`, for a room's enemies and a phase's adds alike, through `spawn_style_for(data)`: `pick` with the registry, the enemy and the room's biome. It replaces AS1's `Flow.spawn_seconds()`. The bot test now waits for the longest `Actor.spawn_seconds` of the room's enemies.
- `SpawnLook.style_for(body)` reads `body.spawn_style`. An id the lookup does not find is drawn as the lookup's `rise` (the registry's), and only with no `rise` as `DEFAULT`, so an unknown id always draws as the game's rise.
- `Registry.remove(folder, id)` undoes a test's `add` on the game's registry, so a fixture style does not leak into the next suite.
- **Tests.**
  - test_spawn_style.gd: the picker's order, two styles naming one biome (first by id, and a problem of the set), an enemy override, a missing style, no rise and no registry, and every enemy's style a style.
  - test_spawn.gd: a snapshot mid-spawn restores the style, a look drawing from the restored state draws its own style's mark and motion, and the state hash holds the style.
  - test_spawn_look.gd: each body is drawn by its own style, with an unknown id as the lookup's rise, and `cut()` hands a body from one motion to another when its style's motion changes mid-spawn (a recording fixture motion; AS1 left that path untested).
  - test_flow.gd and test_flow_adds.gd: room enemies and adds spawn in the style Flow picks, for its seconds.
  - tests/core/test_snapshot_spawn_styles.gd: the arena with two fixture styles (the biome's, and the bone husk's own, of other lengths; `ReplayRun.spawn_styles` adds them to every fresh game's registry), played with a snapshot mid-spawn and resumed in a fresh game, agrees tick for tick.

Each step updates the README of the areas it touches, and `content/spawn_styles/README.md` (new) is the guide: copy `rise/`, change the numbers, name your biome.

## The owner's answers (2026-11-18)

1. **The second motion:** "Materialize in from nothing. A cool sci-fi look": `materialize`, above (AS3), instead of the `drop` first proposed.
2. **The mark:** art strips are allowed (AS4); the drawn ring stays the default.
3. **When:** build it now, step by step in new sessions, each merged automatically.
