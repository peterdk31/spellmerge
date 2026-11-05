# content/flashes: kinds of flash

A flash is one shaped glow that a cue's `flash` part shows: a shot's end, a cast at the staff tip, a ring flashing out, a column of light, gone in a moment (docs/milestones/flash-kinds.md). A kind is one `FlashKind` file (`core/base/flash_kind.gd` documents every field), named `<id>.tres`; the registry finds it by its `id` under `flashes`, and a cue names it (`{"flash": &"burst", "reach": 1.0}`), so a new look is a new file and no list is edited.

## Contract

- **How it is drawn (`draw`).** A `shape` is drawn from its curves by Feel's flash shader (`core/projectiles/shot_flash.gdshader`), which reads every kind from a table (`gameplay/feel/flash_table.gd`), so a new shape needs no shader edit. A curve a kind does not give costs nothing to draw (the shader skips it), and each part is drawn only as big as it reaches. `clouds` (a staff's poof) and `cracks` (the ground struck, drawn on the floor) are drawn by code in the same shader, their glow from their curves. `shell`, `fireball` (an explosion's parts, `shot_blast.gdshader`) and `arc` (lightning along a length, `shot_arc.gdshader`) are drawn by shaders of their own and have no curves: their file gives their seconds, step and light.
- **A shape's parts:** a cross (`arm`), a dotted disc (`disc`), a ring fraying with its age (`ring`; round, a diamond or flat on the floor, `metric`), a column of light (`column_width`, `column_top`, `column_foot`, `column_length`, `column_dotted`), and since F4 a star (`star`, `star_points`), rays (`rays`, `rays_inner`, `ray_count`), a ring of dots (`dots`, `dot_count`) and a spiral (`spiral`, `spiral_turn`, `spiral_arms`, `spiral_gap`). A part with no curve is not drawn; a kind may draw several (a ring and rays).
- **Its glow:** `glow` (how bright), a soft light round its ring or column (`glow_ring`, `glow_ring_reach`) and round its middle (`glow_middle`, `glow_middle_reach`).
- **No colours here.** A flash is in the ramp of the shot or caster it comes from (or the cue's own colour, `CueBase`); its `first` and `second` curves pick which shade of that ramp: `hot`, `hi`, `mid`, `lo`.
- **A curve** is up to 4 segments over the flash's life (0 to 1), the first at 0: each from `at`, from a value to a value (`from`, `to` in pixels; `from_z`, `to_z` in steps of the flash's zoom, added), its `way` (`linear`, `out`, `in`, `hold`), reaching `to` at `over` (the next segment's `at`, or 1), or `off`. A curve is cut where the next segment starts, so a ring may ease over the whole life and stop at 0.7.
- **Its numbers:** `seconds` (when its cue part gives none), `step` (the pixels a zoom step is: a cue part's `reach` is the cue's size in steps), `room_light` (how much it lights the room while "Spell light" is on; 0 for none; a cue with a `light` part lights by that instead), `on_floor` (the cracks: under the bodies).
- `tests/content/test_flashes.gd` checks every file (`problems()`), and that the kinds ported from the shader's code (2026-11-05) draw as it did; `tests/content/test_cues.gd` checks that every cue names kinds there are (`CueBase.kind_problems`). `tests/screenshots/shot_flashes.gd` draws the flares at their ages, `shot_flash_drawings.gd` F4's kinds.

| Kind | Draw | What it is |
|---|---|---|
| `burst` | shape | where a shot lands: a white-hot cross that shrinks |
| `cast` | shape | the staff tip on a cast: a small cross |
| `spray` | shape | a hit on a character: a small white-hot cross where it struck |
| `puff` | shape | a dotted white-hot puff (a kill, a reaction, a hit with no way) |
| `ring_out` | shape | a ring that flashes out (a nova's cast) |
| `ring_in` | shape | a ring that gathers in (a rune's or orbit's cast) |
| `rune_burst` | shape | a rune going off: a dotted flash over the diamond, a diamond ring widening to twice its size |
| `rise` | shape | light pulled up off a spot (where a teleport leaves): a column that thins to a line and lifts off the top, a flat ring gathering in |
| `fall` | shape | light struck down onto a spot (where a teleport lands, a rain falls): a streak falling to the floor, then the column flashing and thinning away, a cross, a flat ring thrown out |
| `poof` | clouds | a staff's personality swap: bone clouds along the staff, biggest at 35% of it |
| `quake` | cracks | the ground struck (a slam): cracks out from the impact, cooling from white-hot to dark stone |
| `shell` | shell | a blast's ragged shell |
| `fireball` | fireball | a rising fireball (an exploding barrel) |
| `arc` | arc | lightning along the cue's size (a zap, a discharge) |
| `star` | shape | a four-point star that flares out and shrinks away (F4; no cue names it yet) |
| `star_six` | shape | a bigger six-point star (F4; no cue names it yet) |
| `rays_out` | shape | twelve rays thrown out from the middle (F4; no cue names it yet) |
| `rays_in` | shape | eight rays drawn in, brightening as they arrive (F4; no cue names it yet) |
| `dot_ring` | shape | a ring of sixteen dots flying out (F4; no cue names it yet) |
| `spiral` | shape | a two-armed spiral winding in as it turns (F4; no cue names it yet) |

## Allowed files

`.tres` and `.uid` files. Limit: 1 MB per file.

## Example to copy

`burst.tres`: copy it, give it a new `id` and file name, and change its curves. Name it in a cue's `flash` part to show it.
