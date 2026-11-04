# content/cues: moments' looks and weight

A cue is one moment's look and feel as data: the flashes Feel draws, and its shake, camera punch, holds and sound. One `CueBase` file per cue (`core/base/cue_base.gd` documents every key), named `<id>.tres`; the registry finds it by its `id` under `cues`, so a new moment is a new file and no list is edited.

A part may also be a floor mark (`{"part": &"mark", "mark": &"scorch", "reach": 0.9}`; docs/milestones/spell-spectacle.md, P2a): stamped once into the room's mark layer, it stays until the room ends. The mark is a kind in `content/marks/`; with `"cards": true` the cue's cards' marks take its place when they have one (a frost blast leaves frost).

Something plays a cue by name: Feel's `play_cue(id, caster, at, dir, size, tint, look, target)`, or the `cue_shown` event from another area. `size` is in pixels (an explosion's radius, a ground strike's reach); a part with `reach` is that many times it. A telegraph's `size` is seconds instead: a part with `lasts_size` lasts that long.

A part can throw motes instead of drawing a flash (docs/milestones/spell-spectacle.md, P1b; Feel's single-pixel particles, `content/motes/`): `{"part": &"motes", "kind": &"spell", "count": 60, "reach": 1.0, "spread": 360.0}`. Its `kind` is `spell` (the default: the kinds of the cue's cards, its look's layers, in its caster's ramp and colour, so a fire blast throws embers and a frost one flecks), `surface` (the surface kinds, in the colours of what broke: the room's walls, or the art of a body that died) or one kind's id. `count` is how many in all (split between the kinds), `reach` flies them out to the cue's size times it, and `spread`, `up` (times the kind's own), `ring` and `way` shape the throw (`CueBase` documents each key). Every count is times the "Particle amount" setting; with "Particles" off there are none.

Cards name the cues they play: a carrier's `cast_look` `cue` (`FormBase`; played where the carrier shows itself, `form_shown`) and its `impact_look` `cue` (played where its shot ends on no body, as big as its `radius`, and where a carrier with no shot ends, `carrier_ended`: a slam's impact, as big as its ring, a teleport's landing, a rain's fall) and a modifier's `cue` (`ModifierBase`; played when its behaviour goes off, as `blast` does).

| Cue | Played by | What it is |
|---|---|---|
| `blast` | the blast card's `cue`: core/spells, wherever a `blast` goes off | the ragged shell, fragments and rubble past the radius, a scorch flash and a scorch mark (frost for a frost card), its cards' motes and the ground's chips out to its radius; shake and a punch away from the caster |
| `fireball` | an exploding barrel (not built yet) | the rising fireball, fragments, a scorch flash and mark, its cards' motes and the ground's chips; shake and a punch |
| `quake` | a carrier whose impact look's `cue` names it (none yet) | cracks in the floor (a flash and a crack mark that stays), stone chips and the ground's chip motes, the caster held, a shake and a punch down the screen |
| `slam` | the slam card's impact look `cue`, at the slam's impact (`carrier_ended` `slam`) | a white-hot star, then the quake's cracks and crack mark, chips (and chip motes, with a few of its cards' motes), hold, shake and punch |
| `parry` | Feel, for a swing's block (`shot_blocked` while the blocking carrier is a swing) | a big four-point star in exactly Spark gold, the parrying actor held alone |
| `deflect` | Feel, for `shot_deflected`, aimed the way the shot now flies | a big white-hot cross in the deflecting actor's colours |
| `enemy_death` | Feel, for `enemy_died` | a white-hot ring, the killing shot's cards' motes and chips in the colours of the body's own art, ichor in those colours on the floor, the killer and the shot held, a shake (Feel adds the ghost and the puff) |
| `boss_death` | Feel, for `enemy_died` of an enemy whose data says `boss` | the same as `enemy_death` with many more motes and a bigger pool of ichor, and the game-wide stop |
| `player_downed` | Feel, for `player_downed` (it names no position, so this cue draws nothing) | the game-wide stop and a big shake |
| `self_hit` | Feel, for a hit of an actor by its own spell | a ring in exactly pink, so it is never taken for an enemy's hit |
| `heal` | Feel, for `heal_dealt` | a soft ring in exactly green, no stop and no shake |
| `nova` | the nova card's cast look `cue`, at `form_shown` `nova` | the ring leaving the caster, 120 px across, a ring of its cards' motes, and a burn ring on the floor round the caster |
| `rune_burst` | the rune card's impact look `cue`, where a rune goes off (on a body or not: a rune lies on the floor) | a rune's scar on the floor, as big as the rune |
| `telegraph` | the rain card's cast look `cue`, at `form_shown` `rain` | a ring closing on where a rain falls, for the seconds until then (`size`) |
| `rainfall` | the rain card's impact look `cue`, at `carrier_ended` where it falls | a column of light struck down (`fall`) and a spray |
| `vanish` | the teleport card's cast look `cue`, where it leaves | a column of light pulled up off the spot (`rise`) |
| `appear` | the teleport card's impact look `cue`, at `carrier_ended` where it lands | a column struck down (`fall`), a spray, a small shake and punch |
| `trade` | the swap card's cast look `cue`, at each end of its trade | a column struck down and a small one pulled up, their rings crossing |
| `conjure` | the decoy's and familiar's cast look `cue`, where one appears | a column struck down and a puff |
| `dismiss` | the decoy's and familiar's impact look `cue`, at `carrier_ended` where one goes | a column pulled up and a puff |

To add one: copy `quake.tres`, give it a new `id` and file name, pick its parts from `CueBase.EFFECTS`, and play it by name. Each part is played by its type (`part`: `effect` when it has none, `motes`, `mark`; `CueBase.PART_TYPES`); a new kind of part is code, a row there and a player in Feel (`Feel.add_cue_part`, docs/milestones/spell-spectacle-2.md, S1), and then every cue can use it by data. `tests/content/test_cues.gd` checks every cue file (`CueBase.problems()`). Moments with a life of their own (beams, dashes, swing trails, statuses, ghosts) are not cues.
