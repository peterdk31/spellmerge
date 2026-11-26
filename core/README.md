# Core

## Purpose

The shared services every other area stands on.

## Contract

- **Dependency direction:** `core` ← `gameplay` ← `content`; core depends on none of `gameplay/`, `hud/`, `content/` and finds content by folder through `Registry`.
- Areas talk only through `Events`. Services that act per caster take an actor id (`core/actors`); only the HUD's, input's and co-op's take a seat 0–3. Nothing assumes a single player.
- Only `core/registry` loads from a computed path; everyone else writes `load("res://...")` or `preload(...)`.
- Only `core/base/`, `core/spells/` and `content/spells/` read card fields (`tests/core/test_spell_field_reads.gd`). Fire a spell only through `Spells.cast_staff(player, staff, origin, direction, mana)`.
- The simulation never reads a device: input reaches it only as a seat's `InputFrame` (`sim/`).
- A HUD request the simulation hears is a command: listed in `InputFrame.COMMAND_NAMES`, heard with `Events.listen(name, callable)`, never by connecting the signal.
- No per-frame allocations. Projectiles are packed-array rows, never nodes or pools.
- Change a projectile hot loop and you change its native twin (`ShotKernel`, [native/README.md](../native/README.md)); the GDScript is the reference; `tests/core/test_native_kernel.gd` compares them to the bit. Never keep a copy of the manager's arrays across a kernel call.
- `tests/core/test_projectiles_step_exact.gd` must pass unchanged: a new behaviour changes nothing for shots without it.

## Services (one folder each)

- `events/`: `Events` autoload, a typed signal per event; core owns the definitions, each area's README lists what it sends and hears.
- `registry/`: `Registry` autoload: `get_resource(folder, id)`, `get_ids`, `get_all`, `get_sound(id)` (null plays nothing), `validate_spells()`; `scan_folder` for the editor.
- `input/`: `PlayerInput` autoload, asked by player index (`get_move`, `get_aim`, `is_action_just_pressed`, `get_press_count`, `set_captured`, `menu_move`, `glyph_kind`); `LocalInput`; `InputGlyphs`. The d-pad never walks. Menus and the HUD never read `Input` themselves.
- `actors/`: `Actors` autoload, ids 0–1023. See `actors/README.md`.
- `items/`: `ItemKinds.RULES`, `ItemStack`. See `items/README.md`.
- `sim/`: `InputFrame`, the `Frames` autoload, `Replay`, `StateWalk`, `SimHash`, `Desync`, `SimSeed`. See [sim/README.md](sim/README.md).
- `ui_focus/`: `UIFocus` autoload, per-player panels (`open`, `focus`, `set_navigator`). Never `grab_focus`, never pauses.
- `settings/`: machine settings more than one area reads (`ShotCap`, `MoteCap`, `AudioVolumes`, ...); a stepped one uses `SettingStops.nearest`. Never a run's rules.
- `audio/`: `Audio` autoload, view only, the only code that makes an `AudioStreamPlayer` (`play`, `hold`/`release`, `play_track`, `play_over`). Tests: `tests/core/audio/`.
- `loading/`: `Loading` autoload: `run(tasks, done)` runs `LoadTask`s one unit a frame behind the loading screen. To load more before playing, write a LoadTask and add it to `Flow.play_tasks()`.
- `display/`: `Display`, `ScreenViews` (split views, view only), `PictureGrid` (the 1280×720 picture), `ArtDetail` (`@2x` art).
- `save/`: `SaveFile`, `user://save.cfg` only. `story/`: `StoryValidator`.
- `base/`: data resources and shared readers: the card kinds (`CarrierCard`, `ElementBase`, `ModifierBase`, `TriggerBase`, `MulticastBase`), `StaffBase`, `EnemyBase`, `PropBase`, `RoomBase`, `RunDefinition`, `MoteKind`, `Palette`, ...; each has `problems()` for the content checks.
- `spells/`: `Spells` autoload (`SpellRuntime`): `compile_staff`, `staff_view`, `install_staff`, `cast_staff`, `cast_ready`, `next_cast_sense`, `component_*`, `hit_profile(tag)`, `look_of`. Carriers live in `spells/carriers/` and answer `traits()`; they reach the runtime only through `CarrierKit`, and `spells.gd` names no carrier (docs/CARRIERS.md; `tests/core/test_card_rules.gd`). `SpellValidator` (`tests/content/spells/test_validators.gd`), `SpellTag`, `SpellLimits` (pacing only), `CastSense`.
- `projectiles/`: `Projectiles` autoload (below), `RoomGrid` (`grid()`: walls, holes, footprints; `walk_body`), `HitBatch`, `Batches`, `ShaderWarmup`.
- `pools/`: `pool.gd`, fixed size, never grows; for nodes and effects only.

## The projectile manager

Rows in packed arrays, stepped by the Tick (`step`). `spawn`, `add_target`, `ray`, `sweep`, `strike`, `threat`, `nearest_target`, `targets_in`, `set_cap`. Events (`projectile_hit`, `projectile_expired`, `shot_ended`, ...) name the shot's slot last. The hit-work budget is work units, never time. Tests: `tests/core/test_projectiles_kit.gd`, `test_hit_budget.gd`, `test_draw_regions.gd`, `test_body_walk.gd`.

### How to add a shot behaviour

All in `projectile_manager.gd`: (1) its numbers per slot, a packed array sized in `set_cap`, reset in `_spawn_row`; (2) `set_<name>(slot, ...)` calls `_join(slot, B_<NAME>)` (`_leave` to switch off); (3) `B_<NAME>` in the order (renumber, raise `BEHAVIOURS`, and `AFTER_HITS` if before the hits), its pass at that index of `BEHAVIOUR_PASSES`, a line in the order comment; (4) `_pass_<name>(list, first, count, delta)`, copied from `_pass_spiral` or `_pass_homing`: never sends an event, ends a shot (mark `S_EXPIRE`/`S_GONE`) or changes a list; calls `_wait(slot, B_<NAME>)` before reading what a hit handler may change. Add a test like `_test_spiral_weaves_round_its_line` and the setter's call in `Spells._apply_travel`.

## The shot shaders

- One shader per kind of thing drawn, each with its own batch or node; no mode switches between unrelated looks.
- Shared code is in includes (`shot_palette`, `shot_look`, `shot_head`, ... `.gdshaderinc`) that card shaders start from.
- A card's own look is `CarrierCard.look_shader` in its folder (copy `carriers/bolt/bolt.gdshader`); areas get it through `Spells.look_of`, never by reading the card.
- No per-pixel loop over anything that grows; a pixel loops only over a small fixed number. Keep fragment stages small and branch-light; per-instance work in `vertex()`.
- Both renderers: every shader compiles and draws the same on Mobile and Compatibility: at most 32 varyings (pack small ones in a vector), no `return` from inside a loop in the fragment stage. `tests/smoke/renderer_shaders.gd` checks.
- Every shader is compiled before the first room: list a shot shader in `projectiles/shader_warmup.gd`, or call `ShaderWarmup.want(shader, how)` where an area first uses it. `tests/core/test_shader_warmup.gd` fails for any left out.
- To add a draw kind: a `.gdshader` in `projectiles/` including the palette, warmed, with its own batch or node.
- A shader change that grows a stage is checked on a real Windows GPU.

## Batches are never culled

Every 2D MultiMesh is made by `Batches.multimesh()` (box `Batches.WORLD`), never `MultiMesh.new()`. A batch may set its own box only if it can never be stale (`Batches.box_of`), never one worked out from where its instances are now. `tests/core/test_batches.gd` fails otherwise and for a scene MultiMesh with no `custom_aabb`.

## The render thread

Desktop builds draw on a separate render thread (`tests/core/test_render_thread.gd`). So: a picture the game keeps writing goes through `TextureUpload.hand(image)`, never `ImageTexture.update`/`set_image` (`tests/core/test_texture_upload.gd`); RenderingServer calls only from the main thread; no `get_image()` or viewport read back during play; every font size and outline the HUD or Feel draws is in `GlyphWarmup`'s list (`tests/core/test_glyph_warmup.gd`).

## Compute effects

`GpuCompute` (`base/gpu_compute.gd`) alone says whether an effect may run as a compute shader (`available()`), reaches the device (`device()`, render thread only) and compiles (`compile`). A `.glsl` lives in `core/` or `gameplay/feel/`, is loaded with a literal `load()` only behind `available()`, never preloaded, compiled when the effect is made, never in play. It keeps its CPU path as the reference and fallback.

## Allowed files

Claude only. Typed GDScript, `.gdshader`, `.gdshaderinc`, `.glsl` (compute, drawing only), with their `.uid`; no banned APIs; file access only in `user://`. Tests go in `tests/core/`.

## Example to copy

None: follow the service you change and its tests.

## Validate

```sh
tools/check.sh
ci/build/build.sh --quick
```

## Review questions

Is it needed by more than one area, does it keep the dependency direction, and does it stay inside the performance budgets?

History and reasons: [docs/history/core-README.md](../docs/history/core-README.md).
