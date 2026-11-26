# content/cues: moments' looks and weight

A cue is one moment's look and feel as data: flashes, motes, floor marks, lights, streams, held sounds, and its shake, camera punch, holds and sound. One `CueBase` file per cue (`core/base/cue_base.gd` documents every key), named `<id>.tres`; the registry finds it by `id` under `cues`. A new moment is a new file; no list is edited.

## Playing a cue

- By name: Feel's `play_cue(id, caster, at, dir, size, tint, look, target)` (with `follow` to move with a body), or the `cue_shown` event from another area.
- `size` is pixels (an explosion's radius, a strike's reach); a part's `reach` is times it. A telegraph's `size` is seconds (`lasts_size`).
- Cards name their cues: a carrier's `cast_cue` (default `cast`), `shown_cue` (`carrier_shown`), `impact_cue` (default `impact`), `end_cue` (`carrier_ended`); a modifier's `cue`. A staff names `wind_cue`, `move_cue`, `cast_cue`, `wall_cue` (`StaffBase`); a boss phase `PhaseLook.cue`; a spawn style its `cue`; a prop state `PropStateLook.cue`.
- A kick `back` or along `aim` needs the cue to have a direction.

## Parts

Each part is played by its type (`part`; none is `flash`; `CueBase.PART_TYPES`):

- **flash**: a kind of `content/flashes/` (`{"flash": &"burst", "reach": 1.0}`); `floor: true` draws it under the bodies; `if_cards`, `if_layer`, `if_size_over`, `if_size_upto` limit when it plays. A flash draws its shape and light only; its sparks and rubble are the cue's motes parts.
- **mark**: stamped once into the room's mark layer (`{"part": &"mark", "mark": &"scorch", "reach": 0.9}`, a kind in `content/marks/`); `"cards": true` uses the cards' marks.
- **motes**: Feel's single-pixel particles (`content/motes/`): `kind` (`spell`, `surface` or a kind id), `colours`, `count`, `reach` or `radius`, `spread`, `up`, `ring`, `way`, `often` (a moment of many a frame), `share` (shedding), `line`, `life`, `gather`, `for` (a jet, `gameplay/feel/jets.gd`). Counts are times the "Particle amount" setting.
- **light**: a soft light while "Dynamic lighting" is on (`radius`, `strength`, `seconds`, `color`); a cue with a light part lights by it alone.
- **stream**: motes given off from the moving caster until its carrier ends (`kind` `dash_path` or `spell`, `rate`, `side`, `ahead`; `gameplay/feel/streams.gd`).
- **held**: a sound looping from the caster while its moment lasts (`sound`, `seconds`, `volume`; `gameplay/feel/held_sounds.gd`).

Where on the cue's line a part plays: `along` (0 its point, 1 its end).

## Cue-wide keys

- `color` (exact colour of parts that name none) and `power` (one rule in `Feel.play_cue`: sizes, counts, holds, shake, punch; never seconds).
- `body` on a flash: the body's own colour; `plain`, `bare`: without ramp/cards.
- `duck`: decibels the music lowers while its sound plays (0 to -24).
- `size_ref`: the size it was made at; played at another, it grows by `gameplay/feel/cue_size.gd`'s one rule (0.5 to 3 times).
- `every`: least seconds between two plays for the same actor.
- Weight: `hold`, `hold_target`, `hold_shot`, `stop_game`, `shake`, `kick`, `sound`.

## Cue families

Casts (`cast`, `cast_*`, `cast_self`, `orbit`); strikes (`impact`, `impact_ring`, `hit`, `hit_puff`, `expire`, `parry`, `deflect`, `slam`, `quake`, `rune_burst`); explosions (`fireball`, the blast card's; `blast` kept to compare); deaths and downs (`enemy_death`, `boss_death`, `player_downed`, `self_hit`, `heal`); reactions (`reaction_<id>` per reaction id in `content/spells/reactions.tres`, `reaction` the plain fallback, `discharge_arc`); possession (`possess_start`, `possess_end`); staffs (`staff_swap`, `staff_swap_b`, `staff_swap_c`); carriers' moments (`zap`, `nova`, `telegraph`, `vanish`, `appear`, `trade`, `conjure`, `dismiss`, `portal_open`, `portal_through`, `portal_close`, `field_open`, `field_through`, `field_burst`, `dash_start`, `dash_land`, `pool_throw`, `spray_jet`, `siphon_drain`); the world (`enemy_spawn`, `enemy_materialize`, `stone_lit`, `pillar_crack`, `pillar_break`, `dust_scatter`); bosses (`boss_intro`; a boss's own cues carry its prefix, e.g. `broom_*`, and go with it; an enemy's, e.g. `spitter_acid`). Each file says what it is.

## Rules

- A cue is data only. A new kind of part is code: a row in `CueBase.PART_TYPES` (its own checks in `CueBase._type_problems`) and a player in Feel (`Feel.add_cue_part`); then every cue can use it.
- Moments with a life of their own (beams, swing trails, statuses, ghosts) are not cues.
- A strike's card motes are its shot's own shed (`Spectacle.shed_hit`, `shed_on_wall`), so a strike cue throws none of its cards' motes.
- Every reaction id needs its `reaction_<id>.tres` with a `color` (`tests/gameplay/feel/test_feel_reactions.gd`).

## To add one

Copy `quake.tres` (a reaction: `reaction_thaw.tres`; a spawn: `enemy_spawn.tres`), give it a new `id` and file name, pick its parts (a new flash look is a new file in `content/flashes/`), and play it by name.

Tests: `tests/content/test_cues.gd` (every cue file: `CueBase.problems()`, `kind_problems`), `tests/gameplay/feel/test_feel_reactions.gd`, `tests/gameplay/feel/test_feel_sounds.gd`.

History and reasons: [docs/history/content-cues-README.md](../../docs/history/content-cues-README.md).
