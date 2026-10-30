# content/cues: moments' looks and weight

A cue is one moment's look and feel as data: the flashes Feel draws, and its shake, camera punch, holds and sound. One `CueBase` file per cue (`core/base/cue_base.gd` documents every key), named `<id>.tres`; the registry finds it by its `id` under `cues`, so a new moment is a new file and no list is edited.

Something plays a cue by name: Feel's `play_cue(id, caster, at, dir, size, tint, look, target)`, or the `cue_shown` event from another area. `size` is in pixels (an explosion's radius, a ground strike's reach); a part with `reach` is that many times it. A telegraph's `size` is seconds instead: a part with `lasts_size` lasts that long.

Cards name the cues they play: a carrier's `impact_look` `cue` (`FormBase`; played where its shot ends on no body, as big as its `radius`, and at a slam's impact, as big as its ring) and a modifier's `cue` (`ModifierBase`; played when its behaviour goes off, as `blast` does).

| Cue | Played by | What it is |
|---|---|---|
| `blast` | the blast card's `cue`: core/spells, wherever a `blast` goes off | the ragged shell, fragments and rubble past the radius, a scorch; shake and a punch away from the caster |
| `fireball` | an exploding barrel (not built yet) | the rising fireball, fragments, a scorch; shake and a punch |
| `quake` | a carrier whose impact look's `cue` names it (none yet) | cracks in the floor, stone chips, the caster held, a shake and a punch down the screen |
| `slam` | the slam card's impact look `cue`, at the slam's impact (Feel's `form_shown` `slam`) | a white-hot star, then the quake's cracks, chips, hold, shake and punch |
| `parry` | Feel, for a swing's block (`shot_blocked` while the blocking carrier is a swing) | a big four-point star in exactly Spark gold, the parrying actor held alone |
| `deflect` | Feel, for `shot_deflected`, aimed the way the shot now flies | a big white-hot cross in the deflecting actor's colours |
| `enemy_death` | Feel, for `enemy_died` | a white-hot ring, the killer and the shot held, a shake (Feel adds the ghost and the puff) |
| `boss_death` | Feel, for `enemy_died` of an enemy whose data says `boss` | the same as `enemy_death`, and the game-wide stop |
| `player_downed` | Feel, for `player_downed` (it names no position, so this cue draws nothing) | the game-wide stop and a big shake |
| `self_hit` | Feel, for a hit of an actor by its own spell | a ring in exactly pink, so it is never taken for an enemy's hit |
| `heal` | Feel, for `heal_dealt` | a soft ring in exactly green, no stop and no shake |
| `nova` | Feel, for `form_shown` `nova` (`FORM_CUES`) | the ring leaving the caster, 120 px across |
| `telegraph` | Feel, for `form_shown` `rain` (`FORM_CUES`) | a ring closing on where a rain falls, for the seconds until then (`size`) |

To add one: copy `quake.tres`, give it a new `id` and file name, pick its parts from `CueBase.EFFECTS`, and play it by name. `tests/content/test_cues.gd` checks every cue file (`CueBase.problems()`). Moments with a life of their own (beams, dashes, swing trails, statuses, ghosts) are not cues.
