# Feel

## Purpose

Hit-stop's look, screen shake, juice presets, and everything drawn or heard only: motes, floor marks, spell light, mist, cues, sounds, cameras, the split screen, markers and the biome's looks.

Feel only reacts: it never changes damage or outcomes. Hit-stop is the game's (`gameplay/combat/hit_stop.gd`, `HitStop`): Feel holds nothing, never touches `Engine.time_scale`, and draws what the holds do. A cue's `hold`, `hold_target`, `hold_shot` and `stop_game` are read by `HitStop`, not Feel.

## Contract

- **Public entry script:** `gameplay/feel/feel.gd`, the autoload `Feel`. Other code uses only it and its events; nothing else in the folder is public. Settings: `Feel.shake_enabled`, `set_spell_light`, `set_shadows`, `set_fog`, `set_ambient_particles`, `set_environment_interaction`, `set_split_mode`, `set_gpu_effects`; limit `Feel.PARTICLE_LIMIT`. Tests reach parts through accessors (`spectacle()`, `motes()`, `marks()`, `light()`, `cover()`, ...).
- **Dependency direction:** `core` ← `gameplay` ← `content`. Feel may use `core/` and the registry; `core/` never depends on it, content never reaches into it. Areas never call each other directly; they talk through events ([gameplay/README.md](../README.md)).
- **Events:** sends none. Listens to the events `core/events/events.gd` defines for it (the table in [gameplay/README.md](../README.md) matches): hits and deaths (`projectile_impact`, `hit_landed`, `damage_dealt`, `enemy_died`, `player_downed`, `heal_dealt`, ...), casts and carriers, cues (`cue_shown`), statuses and reactions, rooms (`room_entered`, `room_built`, `cover_changed`, `rooms_cleared`, ...), the biome's doors, runes, rewards and items, and the settings' `*_changed`. Caster-keyed events carry the actor id; Feel reads ramp, seat and budget from the actor table.
- **Everything is data:** a moment is a cue (`play_cue(...)`, one `CueBase` `.tres` in `content/cues/`); a flash kind is a `FlashKind` (`content/flashes/`), a mote kind a `MoteKind` (`content/motes/`), a mark a `MarkKind` (`content/marks/`), a spawn style a `SpawnStyle` (`content/spawn_styles/`). A new look is a new file, never code. A card names cues (`CarrierCard.cast_cue`, `impact_cue`, `shown_cue`, `end_cue`), never a flash of its own.
- **No colour of its own:** ramps are the projectile manager's (`RAMP_COLORS`, `ramp_light`); other colours are rows of the ramp table.
- **New drawn-only systems** go in the spectacle (`spectacle.gd`: made in its `_ready`, its setting through its own event, its cue parts in `cue_parts`) or a child node of their own; never more of `feel.gd` or its jobs ("Feel's jobs" below).
- **Rules:** no per-frame allocations (pools and slots sized once); a batch is `Batches.multimesh()`; every shader is warmed before play; every texture Feel writes goes through its own `TextureUpload` (never `update` on a texture itself); view only, so the simulation reads nothing Feel draws; draw from the actor's state alone (a joiner or a restored snapshot draws the same); smooth by whole pixels (docs/STYLE.md, "Smooth"; the mist alone may be soft); its own clocks and dice (`rng`) are never the game's; sounds are asked from Audio (`Feel.audio`; Feel has no player) and stay silent when missing.
- **Native twins:** the motes' births (`MoteKernel`), the light grid (`LightKernel`) and the ground drawing (`GroundKernel`) mirror their GDScript to the byte; the GDScript stays the reference and the fallback ([native/README.md](../../native/README.md)).

### Feel's jobs

`feel.gd` is the wiring: its constants, every member, `_ready` (what it makes and the events it hears), `step` (the order of a frame), the settings and the accessors other areas and tests call (a moved function keeps a one-line wrapper there, so no caller changes). Its code is split by effect family, each an `Object` Feel makes, links and frees (`_job_<name>`; not `feel_jobs.gd`, which runs pieces on threads):

| Job | Script | What |
|---|---|---|
| flashes | `feel_flashes.gd` | the five flash batches, the flash kinds' table, `show_flash`, a cue's flash part, a frame's flashes |
| cues | `feel_cues.gd` | `play_cue`, the part players, the cues and plans, the events that only play a cue |
| hits | `feel_hits.gd` | a hit's look, shake and sound, impacts on bodies and walls, the squash, a death's break and remnant |
| statuses | `feel_statuses.gd` | a status shown on its body, a reaction's cue and name, a discharge's arc, a downed note |
| beams | `feel_beams.gd` | live and shown beams, their motes and sounds, the beam and swing meshes, the cards' own looks |
| casts | `feel_casts.gd` | a cast's cue, a wind-up's telegraph, a cast's sounds, `lane` and `held` parts, a barrier's shell |
| view | `feel_view.gd` | shake and kick, the picture and views, the "Effects" row, the HUD's corners, a biome's rooms (`_step_rooms`) |

A job reads Feel's containers (packed arrays, arrays, dictionaries, helpers made with Feel) through members of its own of the same names, aliases of Feel's (`link`, the names in its `LINKED`), so its code reads as Feel's did and loops as fast; everything Feel assigns later (its nodes, the services, the scalars) and its constants go through `feel` and `FeelScript`. Feel only ever changes a linked container in place, and no test puts its own in one's place (`tests/gameplay/feel/test_feel_job_links.gd`); a function reading a scalar or a service of Feel's often reads it into a local once (a read through `feel` is a lookup by name). The jobs' class names (`FeelFlashes`, ...) are for Feel and its tests alone: other areas still use only `Feel`.

### Motes, marks and light

Motes (`mote.gd`): single-pixel particles in a ring of `mote_cap` rows, one writer (`burst`), flight worked out in `mote.gdshader` and `Motes.flight` alike; a hit's motes are shared by staff (`hit_shares.gd`); chunks boxed per room (`mote_regions.gd`). Floor marks: `marks.gd`, a layer a place, at the art's detail (its texels 2 a world pixel each way, `mark.gdshader` working each shape out at art pixels; ART3). Spell light: `spell_light.gd` on a grid of world cells (`light_grid.gd`), applied in one pass (`light_apply.gdshader`), blocked by `light_blockers.gd`; carried lights, room air (`air_motes.gd`), stirs (`stirs.gd`), mist (`mist.gd`). Cost is one table (`effects_quality.gd`), chosen by the "Effects" setting or `effects_auto.gd`. Per-frame pieces may run on threads through `feel_jobs.gd` only; a piece touches no node, texture or RenderingServer.

### The light grid on the GPU

On a real GPU with compute (`GpuCompute.available`) the grid is worked out by `light_grid.glsl` (`light_grid_gpu.gd`, `LightGridGpu`); nothing is read back or made a frame. The CPU grid stays the reference and the fallback (web, OpenGL, headless, `Feel.set_gpu_effects(false)`).

### Spawns

`spawn_look.gd` (`SpawnLook`) draws a spawning enemy from `Actor.spawn_share` by its `SpawnStyle`; what the body does is a motion in `spawn_motions/` (`spawn_motion.gd`: `apply`, `put_back`), keyed by `SpawnStyle.MOTIONS` (a test holds the two lists together). Unknown style or motion draws as `rise`; a body is never drawn whole mid-spawn.

### The ground, drawn as a room is laid out

`ground/` draws a room's ground from its `<room>.shape.json` as `tools/ground_shape.py` bakes it, mirrored, never flipped. `ground_drawing.gd` is the tool's `Drawing` line by line and `GroundKernel.draw` its twin: **a change to `tools/ground_shape.py`, `ground_materials.py` or `ground_walls.py` is made here and in the C++ too, in the same PR.** **At 2x** (ArtDetail; ART3): the floor, the rock face and the walls' art are drawn again on the same outline at 2 art pixels a world pixel (`GroundDrawing._fine`, the tool's `Drawing._fine`, `GroundKernel`'s `draw_fine`); the floor keeps its 1x texture, which the room's readers measure and sample, under its `Detail` child (the 2x art at half size); the rock face and walls are 2x only. A floor is baked into one texture (`ground/floor_bake.gd`); decal art goes on one page (`decal_pages.gd`).

**The room's looks drawn by code or shaders are at 2x too** (ART3 part 4): a shader works its shapes out at the middle of each art pixel (`art_centre`, `core/display/art_detail.gdshaderinc`: the marks, the mist, the light's apply rect and the rooms' tints, the bodies' shadows); a `_draw` draws in art pixels, each a rect 1 / `ArtDetail.DETAIL` a side (the secret runes) or under `draw_set_transform` at 1 / `ArtDetail.DETAIL` (the mouths' shimmer, flares and seals, the key doors' bars; a stone bar is `stone_bars.gd`'s, the caller setting and restoring the transform).

### Damage numbers

One child, `damage_number_drawer.gd`: a pool of `SLOTS` numbers drawn in one `_draw` from a glyph sheet a size (`number_glyphs.gd`); no object or node per hit.

### The split screen

`split_camera.gd` works the views out (Voronoi cells, `voronoi_cells.gd`), `split_screen.gd` draws them, after the party camera (`party_camera.gd`). One picture while everyone fits; only this machine's seats (`Frames.seats_here`); wizards only move a view; cells never jump. Readers take views as `ScreenViews`.

### Equal panes

`SplitScreenSetting` Equal: the same groups, split and merge as Dynamic; only where views go changes (`equal_panes.gd`, pure, `lay`). This machine's view only.

### The dark of unvisited rooms

`unseen_dark.gd`: a room the party's map (`rooms_seen`) has not entered is the void; it opens by shrinking blocks. What unseen places hold is switched off (`unseen_rooms.gd`) or hidden one by one (`unseen_mask.gd`'s `hides(point)`, `unseen_standing.gd`).

## Allowed files

`.gd`, `.tres`, `.gdshader`, `.gdshaderinc`, `.glsl` (the light grid's compute shader, drawing only), plus `.uid`, `.import` and `.license` files. Limit: 1 MB per file. Typed GDScript only; no banned APIs.

## Steps

Follow the steps and test layout in [gameplay/README.md](../README.md).

## Example to copy

`gameplay/feel/presets/punchy.tres`, a `FeelPreset` (`presets/feel_preset.gd`): shake strength and decay, flash sizes and seconds, sound ids. Copy it, change the numbers and set it as `Feel.preset` before Feel's `_ready`. A preset only tunes reactions; it has no field that touches damage. A re-skin (`bolt_texture`) is a preset, never an edit to `feel.gd`. A moment's look is its cue's (`content/cues/`), not the preset's.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

Tests: `tests/gameplay/feel/` (one `test_<file>.gd` a part: `test_feel.gd`, `test_feel_job_links.gd`, `test_motes.gd`, `test_native_motes.gd`, `test_light_grid.gd`, `test_light_grid_gpu.gd`, `test_ground_drawing.gd`, `test_mirrored_art.gd`, `test_spawn_look.gd`, `test_spawn_styles_everywhere.gd`, `test_split_screen.gd`, `test_split_equal.gd`, `test_biome_sound_and_look.gd`, `test_feel_jobs.gd`, ...), `tests/core/test_texture_upload.gd`, `tests/core/test_spawn_style.gd`; looks in `tests/screenshots/shot_*.gd`.

## Review questions

A good PR adds or tunes one look or preset, stays readable with four players hitting at once, and never changes damage or outcomes.

- Is the flash readable with 4 players on screen? Does it avoid per-frame allocations and go through the flash batch, never a node of its own?
- Does it keep to the dependency direction, without calling another area directly?

History and reasons: [docs/history/gameplay-feel-README.md](../../docs/history/gameplay-feel-README.md).
