# content/spawn_styles: how enemies spawn in

A spawn style is the look of an enemy coming into a room (spawn styles, [docs/milestones/spawn-styles.md](../../docs/milestones/spawn-styles.md)): a mark on the floor, then the body coming out of it. One folder a style, `content/spawn_styles/<id>/`, found by the registry's folder `spawn_styles`: its `.tres` on `SpawnStyle` (core/base/spawn_style.gd documents every field), its art if it has any, and an `assets.json` listing that art. Deleting a style is deleting its folder.

## Contract

- **A style is numbers; a motion is code.** A style names its `motion`, one of `SpawnStyle.MOTIONS`, and Feel draws it (gameplay/feel/spawn_motions/). A new style is a new folder; a new kind of motion is engine work in Feel, written once and used by any style, as a card names its behaviour. The motions:
  - `rise`: the body comes up out of the mark, cut at its feet's line, by whole pixels.
  - `materialize` (AS3): the body is built out of light. A pad (the mark, ringed in the style's colours, its rim running round as it grows), then a 1-pixel scan line sweeps up from the feet. Behind it the rows show interlaced: every 4th, then every 2nd, then all, at least 4 frames each. They are lit in the colours' light shade, then the base shade, then the body's own colours. The body glitches sideways by whole pixels until it is nearly whole. The line goes out in 3 looks, and the cue plays as the body is whole. Its motion's stage (`mark_end` to the end) must last 17 frames at 60 fps (`SpawnStyle.MOTION_FRAMES`).
- **Its fields:** `id` (its folder's name), `motion`, `seconds` (0.3 to 2 s: the body can't be hurt and can't act for so long), `mark_end` and `close_from` (where the mark stage ends and where the mark starts to close, as shares of the spawn), `mark_frames` and `close_frames` (the frames the mark grows and closes in), `mark_strip` (art for the mark, AS4: until then none), `colours` (`floor`, the room's floor's, or a palette material, docs/STYLE.md: the mark's rim, and `materialize`'s scan line and lit rows, take its shades; the mark's inside is always a hole in the floor), `cue` (content/cues: played as the body starts to move, its dust and sound) and `biomes` (the biomes it is the spawn of). A field left out takes `rise`'s number (`SpawnStyle.DEFAULT`).
- **Smooth** (docs/STYLE.md, "Smooth"): each stage is drawn in 3 frames at least, and each stage must last long enough at 60 fps to show its frames (`SpawnStyle.CHECK_FPS`). Today's close is (1 - 0.92) x 0.8 s = 64 ms, about 3.8 frames: a shorter spawn must close earlier.
- **One style a biome:** no two styles name the same biome (`SpawnStyle.all_problems`), so none wins by the order they are read in. A biome no style names spawns in as `rise`.
- **Which style an enemy spawns in** (spawn styles AS2, `SpawnStyle.pick`): the enemy's own (`EnemyBase.spawn_style`, a style's id), else the first style by id that names its room's biome, else `rise`. An id that names no style is passed over (a test names it). Today the storm fork names `materialize` (content/enemies/storm_fork/storm_fork.tres); every other enemy spawns in as `rise`.
- **Tests:**
  - `tests/core/test_spawn_style.gd` checks every style file (`problems()`, the cue it names) and the set (`all_problems`), and holds `rise` to `SpawnStyle.DEFAULT`.
  - `tests/gameplay/feel/test_spawn_styles_everywhere.gd` plays every style on every enemy that spawns in (and every boss's adds). Each must land on time, draw each stage in 3 looks at least by whole pixels, be drawn alike by a fresh look, and be put back once it stands. A new style is checked by itself.

| Style | Motion | Seconds | Mark | Cue | Biomes |
|---|---|---|---|---|---|
| `rise` | rise: the body comes up out of the mark, cut at its feet's line, by whole pixels | 0.8 | a ring in the floor's colours: grows in 4 frames to 0.4, closes in 3 from 0.92 | `enemy_spawn` (dust off the mark, a soft sound) | none: the default for every biome |
| `materialize` | materialize: built out of light behind a scan line, row by row | 1.0 | a hole ringed in Arc's light shade (`colours` `arc`), its rim running round: grows in 6 frames to 0.3, closes in 3 from 0.92 | `enemy_materialize` (square `bit` sparks off the body, the sound `enemy_materialize`) | none: the storm fork names it |

## Allowed files

`.tres`, `assets.json`, `.png` or `.svg` art (with its `.import`), `.uid` and `.license` files. Limits: 1 MB per image, 1 MB for anything else.

## Steps

- **A new style:**
  1. Copy `rise/` (or `materialize/`), and rename the folder and the `.tres` to its new id. Set `id` to the same.
  2. Change what you want: the `motion`, the `seconds` and the stages, the `colours` (a palette material such as `ice` or `void`, never a player's nor Blight).
  3. Give it a cue of its own in content/cues if it wants its own dust and sound (copy `enemy_spawn.tres` or `enemy_materialize.tres`).
  4. Say who spawns in it: a biome, by naming it in `biomes` (one style a biome), or one enemy, by setting `spawn_style = &"<id>"` in that enemy's `.tres` (as the storm fork's `materialize`). The enemy's own wins over its biome's.
  5. Run `tests/core/test_spawn_style.gd` and `tests/gameplay/feel/test_spawn_styles_everywhere.gd`.
- **A new kind of motion** is engine work: a name in `SpawnStyle.MOTIONS` and its code in gameplay/feel/spawn_motions/ (gameplay/feel/README.md, "Spawns").

## Example to copy

`rise/`: the default look, every number written out. `materialize/`: a style in a palette material of its own, with a cue of its own.
