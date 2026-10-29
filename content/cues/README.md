# content/cues: moments' looks and weight

A cue is one moment's look and feel as data: the flashes Feel draws, and its shake, camera punch, holds and sound. One `CueBase` file per cue (`core/base/cue_base.gd` documents every key), named `<id>.tres`; the registry finds it by its `id` under `cues`, so a new moment is a new file and no list is edited.

Something plays a cue by name: Feel's `play_cue(id, caster, at, dir, size, tint, look, target)`, or the `cue_shown` event from another area. `size` is in pixels (an explosion's radius, a ground strike's reach); a part with `reach` is that many times it.

| Cue | Played by | What it is |
|---|---|---|
| `blast` | core/spells, wherever a `blast` goes off | the ragged shell, fragments and rubble past the radius, a scorch; shake and a punch away from the caster |
| `fireball` | an exploding barrel (not built yet) | the rising fireball, fragments, a scorch; shake and a punch |
| `quake` | Feel, for a slam's impact and a carrier whose impact look says `quake` | cracks in the floor, stone chips, the caster held, a shake and a punch down the screen |

To add one: copy `quake.tres`, give it a new `id` and file name, pick its parts from `CueBase.EFFECTS`, and play it by name. `tests/content/test_cues.gd` checks every cue file (`CueBase.problems()`). Moments with a life of their own (beams, swing trails, statuses, ghosts) are not cues.
