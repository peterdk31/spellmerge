# content/cues: moments' looks and weight

A cue is one moment's look and feel as data: the flashes Feel draws, and its shake, camera punch, holds and sound. One `CueBase` file per cue (`core/base/cue_base.gd` documents every key), named `<id>.tres`; the registry finds it by its `id` under `cues`, so a new moment is a new file and no list is edited.

Something plays a cue by name: Feel's `play_cue(id, caster, at, dir, size, tint, look, target)`, or the `cue_shown` event from another area. `size` is in pixels (an explosion's radius, a ground strike's reach); a part with `reach` is that many times it.

| Cue | Played by | What it is |
|---|---|---|
| `blast` | core/spells, wherever a `blast` goes off | the ragged shell, fragments and rubble past the radius, a scorch; shake and a punch away from the caster |
| `fireball` | an exploding barrel (not built yet) | the rising fireball, fragments, a scorch; shake and a punch |
| `quake` | Feel, for a slam's impact and a carrier whose impact look says `quake` | cracks in the floor, stone chips, the caster held, a shake and a punch down the screen |
| `parry` | Feel, for a swing's block (`shot_blocked` while the blocking carrier is a swing) | a big four-point star in exactly Spark gold, the parrying actor held alone |
| `deflect` | Feel, for `shot_deflected`, aimed the way the shot now flies | a big white-hot cross in the deflecting actor's colours |
| `enemy_death` | Feel, for `enemy_died` | a white-hot ring, the killer and the shot held, a shake (Feel adds the ghost and the puff) |
| `boss_death` | Feel, for `enemy_died` of an enemy whose data says `boss` | the same as `enemy_death`, and the game-wide stop |
| `player_downed` | Feel, for `player_downed` (it names no position, so this cue draws nothing) | the game-wide stop and a big shake |
| `self_hit` | Feel, for a hit of an actor by its own spell | a ring in exactly pink, so it is never taken for an enemy's hit |
| `heal` | Feel, for `heal_dealt` | a soft ring in exactly green, no stop and no shake |

To add one: copy `quake.tres`, give it a new `id` and file name, pick its parts from `CueBase.EFFECTS`, and play it by name. `tests/content/test_cues.gd` checks every cue file (`CueBase.problems()`). Moments with a life of their own (beams, swing trails, statuses, ghosts) are not cues.
