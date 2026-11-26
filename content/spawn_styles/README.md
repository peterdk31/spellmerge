# content/spawn_styles: how enemies spawn in

A spawn style is the look of an enemy coming into a room ([docs/milestones/spawn-styles.md](../../docs/milestones/spawn-styles.md)): a mark on the floor, then the body coming out of it. One folder a style, `content/spawn_styles/<id>/`, found by the registry's folder `spawn_styles`: its `.tres` on `SpawnStyle` (core/base/spawn_style.gd documents every field), its art if any, and an `assets.json` listing that art. Deleting a style is deleting its folder.

## Contract

- **A style is numbers; a motion is code.** A style names its `motion`, one of `SpawnStyle.MOTIONS`, drawn by Feel (gameplay/feel/spawn_motions/). A new kind of motion is engine work there.
  - `rise`: the body comes up out of the mark, cut at its feet's line, by whole pixels.
  - `materialize`: the body built out of light behind a 1-pixel scan line, rows interlaced, lit in the colours' shades; its motion stage (`mark_end` to the end) must last `SpawnStyle.MOTION_FRAMES` frames at 60 fps.
- **Its fields:** `id` (its folder's name), `motion`, `seconds` (0.3 to 2 s: the body can't be hurt or act meanwhile), `mark_end`, `close_from` (shares of the spawn), `mark_frames`, `close_frames`, `mark_strip`, `colours` (`floor` or a palette material, never a player's nor Blight), `cue` (content/cues) and `biomes`. A field left out takes `rise`'s number (`SpawnStyle.DEFAULT`).
- **Smooth** (docs/STYLE.md, "Smooth"): each stage is drawn in 3 frames at least and lasts long enough at 60 fps to show them (`SpawnStyle.CHECK_FPS`); a shorter spawn must close earlier.
- **A mark strip** (`mark_strip`): one `.png` or `.svg` in the style's folder, a row of square frames, smallest look first, whole mark last; played over the mark stage, held to `close_from`, then `close_frames` of them backwards. Drawn in its own palette colours (`colours` not read), at whole pixels, centred on the feet. `problems()` checks: square frames; at least 3 and more than `close_frames`; at most 64 px; a mark stage long enough at 60 fps; the file in the folder and listed in `assets.json`.
- **One style a biome:** no two styles name the same biome (`SpawnStyle.all_problems`). A biome no style names spawns in as `rise`.
- **Which style an enemy spawns in** (`SpawnStyle.pick`): the enemy's own (`EnemyBase.spawn_style`), else the first style by id naming its room's biome, else `rise`.
- **Tests:**
  - `tests/core/test_spawn_style.gd` checks every style file (`problems()`, the cue it names) and the set (`all_problems`), and holds `rise` to `SpawnStyle.DEFAULT`.
  - `tests/gameplay/feel/test_spawn_styles_everywhere.gd` plays every style on every enemy that spawns in (and every boss's adds): on time, each stage in 3 looks by whole pixels, drawn alike by a fresh look, put back once it stands. A new style is checked by itself.

The styles now: `rise` (the default) and `materialize` (Arc colours, named by `content/enemies/storm_fork/storm_fork.tres`).

## Allowed files

`.tres`, `assets.json`, `.png` or `.svg` art (a mark strip, with its `.import`), `.uid` and `.license` files. Limits: 1 MB per image, 1 MB for anything else.

## Steps

- **A new style:**
  1. Copy `rise/` (or `materialize/`), and rename the folder and the `.tres` to its new id. Set `id` to the same.
  2. Change the `motion`, the `seconds` and the stages, the `colours` (a palette material such as `ice` or `void`, never a player's nor Blight).
  3. Give it its own cue in content/cues if it wants its own dust and sound (copy `enemy_spawn.tres` or `enemy_materialize.tres`).
  4. Say who spawns in it: a biome in `biomes` (one style a biome), or one enemy by `spawn_style = &"<id>"` in its `.tres`.
  5. For a mark of art: draw its strip (below) and name it in `mark_strip`.
  6. Run `tests/core/test_spawn_style.gd` and `tests/gameplay/feel/test_spawn_styles_everywhere.gd`.
- **A mark strip** (e.g. roots for a forest biome): draw `<id>/mark.png` (e.g. 4 to 8 frames of 16 x 16), palette colours only, whole pixels, a 1 px dark outline (docs/STYLE.md); open the project once so Godot writes its `.import`; add it as an `ext_resource` in the `.tres` (raise `load_steps`) and set `mark_strip = ExtResource(...)`; list it in the folder's `assets.json` (art/README.md, "The origin manifest").
- **A new kind of motion** is engine work: a name in `SpawnStyle.MOTIONS` and its code in gameplay/feel/spawn_motions/ (gameplay/feel/README.md, "Spawns").

## Example to copy

`rise/`: the default look, every number written out. `materialize/`: a style in a palette material of its own, with a cue of its own.

History and reasons: [docs/history/content-spawn_styles-README.md](../../docs/history/content-spawn_styles-README.md).
