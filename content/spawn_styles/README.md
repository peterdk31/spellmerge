# content/spawn_styles: how enemies spawn in

A spawn style is the look of an enemy coming into a room (spawn styles, [docs/milestones/spawn-styles.md](../../docs/milestones/spawn-styles.md)): a mark on the floor, then the body coming out of it. One folder a style, `content/spawn_styles/<id>/`, found by the registry's folder `spawn_styles`: its `.tres` on `SpawnStyle` (core/base/spawn_style.gd documents every field), its art if it has any, and an `assets.json` listing that art. Deleting a style is deleting its folder.

## Contract

- **A style is numbers; a motion is code.** A style names its `motion`, one of `SpawnStyle.MOTIONS` (today `rise`: out of the floor), and Feel draws it (gameplay/feel/spawn_motions/). A new style is a new folder; a new kind of motion is engine work in Feel, written once and used by any style, as a card names its behaviour.
- **Its fields:** `id` (its folder's name), `motion`, `seconds` (0.3 to 2 s: the body can't be hurt and can't act for so long), `mark_end` and `close_from` (where the mark stage ends and where the mark starts to close, as shares of the spawn), `mark_frames` and `close_frames` (the frames the mark grows and closes in), `mark_strip` (art for the mark, AS4: until then none), `colours` (`floor`, the room's floor's, or a palette material, docs/STYLE.md), `cue` (content/cues: played as the body starts to move, its dust and sound) and `biomes` (the biomes it is the spawn of). A field left out takes `rise`'s number (`SpawnStyle.DEFAULT`).
- **Smooth** (docs/STYLE.md, "Smooth"): each stage is drawn in 3 frames at least, and each stage must last long enough at 60 fps to show its frames (`SpawnStyle.CHECK_FPS`). Today's close is (1 - 0.92) x 0.8 s = 64 ms, about 3.8 frames: a shorter spawn must close earlier.
- **One style a biome:** no two styles name the same biome (`SpawnStyle.all_problems`), so none wins by the order they are read in. A biome no style names spawns in as `rise`.
- **Today every enemy spawns in as `rise`.** Picking a style by the enemy's own (`EnemyBase.spawn_style`) or its room's biome is spawn styles AS2, to come; until then a style's `biomes` are checked but not yet played.
- `tests/core/test_spawn_style.gd` checks every style file (`problems()`, the cue it names) and the set (`all_problems`), and holds `rise` to `SpawnStyle.DEFAULT`.

| Style | Motion | Seconds | Mark | Cue | Biomes |
|---|---|---|---|---|---|
| `rise` | rise: the body comes up out of the mark, cut at its feet's line, by whole pixels | 0.8 | a ring in the floor's colours: grows in 4 frames to 0.4, closes in 3 from 0.92 | `enemy_spawn` (dust off the mark, a soft sound) | none: the default for every biome |

## Allowed files

`.tres`, `assets.json`, `.png` or `.svg` art (with its `.import`), `.uid` and `.license` files. Limits: 1 MB per image, 1 MB for anything else.

## Steps

- **A new style:** copy `rise/`, rename the folder and the `.tres` to its new id, set `id`, change the numbers, name your biome in `biomes`, and give it a cue of its own in content/cues if it wants its own dust and sound. Run `tests/core/test_spawn_style.gd`.
- **A new kind of motion** is engine work: a name in `SpawnStyle.MOTIONS` and its code in gameplay/feel/spawn_motions/ (gameplay/feel/README.md, "Spawns").

## Example to copy

`rise/`: today's look, every number written out.
