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
- `registry/`: `Registry` autoload: `get_resource(folder, id)`, `get_ids`, `get_all`, `get_sound(id)` (null plays nothing), `validate_spells()`; `scan_folder` for the editor. A scan lists the files; a folder loads when it is first asked for (#972).
- `input/`: `PlayerInput` autoload, asked by player index (`get_move`, `get_aim`, `is_action_just_pressed`, `get_press_count`, `set_captured`, `menu_move`, `glyph_kind`); `LocalInput`; `InputGlyphs`. The d-pad never walks. Menus and the HUD never read `Input` themselves.
- `actors/`: `Actors` autoload, ids 0–1023. See `actors/README.md`.
- `items/`: `ItemKinds.RULES`, `ItemStack`. See `items/README.md`.
- `sim/`: `InputFrame`, the `Frames` autoload, `Replay`, `StateWalk`, `SimHash`, `Desync`, `SimSeed`. See [sim/README.md](sim/README.md).
- `ui_focus/`: `UIFocus` autoload, per-player panels (`open`, `focus`, `set_navigator`). Never `grab_focus`, never pauses.
- `settings/`: machine settings more than one area reads (`ShotCap`, `MoteCap`, `AudioVolumes`, ...); a stepped one uses `SettingStops.nearest`. Never a run's rules.
- `audio/`: `Audio` autoload, view only, the only code that makes an `AudioStreamPlayer` (`play`, `hold`/`release`, `play_track`, `play_over`). Tests: `tests/core/audio/`.
- `loading/`: `Loading` autoload: `run(tasks, done)` runs `LoadTask`s one unit a frame behind the loading screen. To load more before playing, write a LoadTask and add it to `Flow.play_tasks()`.
- `display/`: `Display`, `ScreenViews` (split views, view only), `PictureGrid` (the 1280×720 picture), `ArtDetail` (`@2x` art), `PixelShape` (a small shape at the art's detail baked once into runs, its Outline and light worked out from its mask: the HUD's glyphs and Feel's markers; `tests/core/test_pixel_shape.gd`).
- `save/`: `SaveFile`, `user://save.cfg` only. `story/`: `StoryValidator`.
- `base/`: data resources and shared readers: the card kinds (`CarrierCard`, `ElementBase`, `ModifierBase`, `TriggerBase`, `MulticastBase`), `StaffBase`, `EnemyBase`, `PropBase`, `RoomBase`, `RunDefinition`, `MoteKind`, `Palette`, ...; each has `problems()` for the content checks.
- `spells/`: `Spells` autoload (`SpellRuntime`): `compile_staff`, `staff_view`, `install_staff`, `cast_staff`, `cast_ready`, `next_cast_sense`, `component_*`, `hit_profile(tag)`, `look_of`. Carriers live in `spells/carriers/` and answer `traits()`; they reach the runtime only through `CarrierKit`, and `spells.gd` names no carrier (docs/CARRIERS.md; `tests/core/test_card_rules.gd`). `SpellValidator` (`tests/content/spells/test_validators.gd`), `SpellTag`, `SpellLimits` (pacing only), `CastSense`.
- `projectiles/`: `Projectiles` autoload (below) and its jobs, `RoomGrid` (`grid()`: walls, holes, footprints; `walk_body`), `HitBatch`, `HitTable`, `Batches`, `ShaderWarmup`.
- `pools/`: `pool.gd`, fixed size, never grows; for nodes and effects only.

## The spell runtime

Its code is split by job, as the projectile manager's is; its state is not. `spells.gd` (`SpellRuntime`) holds every member (state, DERIVED, REFS, SPARES, BY_ACTOR, in their order), every constant, `PendingLaunch`, the public API (a moved function keeps a one-line wrapper there, as does a private one the kit or a test calls), the lifecycle (`_init`, `bind`, `clear`, `begin_run`, `rebuild_derived`, the hash's `actor_part*`), `step`, the static helpers others call, and the small readers. Each job is a script of its own, an `Object` the runtime makes and frees (`_job_<name>`, DERIVED):

| Job | Script | What |
|---|---|---|
| views | `spell_views.gd` | `compile_staff`, `staff_view`, `cast_tree`, `component_*`, `cards_of`, the card looks and a launch's body |
| generations | `spell_generations.gd` | `begin_generation`, `install_staff`, live shots, `hit_profile`, holds and reserved mana |
| casts | `spell_casts.gd` | `cast_staff`, `press_staff`, `recast_staff`, wind-ups, the next cast and `next_cast_*`, casters opened and closed |
| launches | `spell_launches.gd` | a group fired, fan, nova, Penta, scatter, `_launch`, shots landed, travel, records, who casts a payload |
| fires | `spell_fires.gd` | waiting launches, a trigger's fires and their pacing, an event's payloads, the jump ring |
| strikes | `spell_strikes.gd` | the ray hit path, strikes, blasts, `_shoot_ray` and its guard, floor and passed elements |
| lasting | `spell_lasting.gd` | the carriers that last (`_lc_*`) and their timers |
| zaps | `spell_zaps.gd` | zaps, sparks and magnets |
| hits | `spell_hits.gd` | the event handlers (`_on_hit`, `_on_expired`, ...), a hit's cards, relay and infusion |

A job reads the runtime's arrays and dictionaries through members of its own of the same names, aliases of the runtime's (`link`), so its code reads as the runtime's did and loops as fast; scalars, objects and the runtime's own functions go through `rt` (a public one always, so a subclass may override it), another job's through that job. The runtime links its jobs again whenever its arrays may have been replaced (`_link_jobs`: after a snapshot's restore and a run's renew); its own code only ever resizes them. A member the runtime replaces whole (the jump ring `_jq_*`, grown by `_grow_jumps`) is never aliased: `rt._jq_spell`. `tests/core/test_spell_jobs.gd` checks the links.

## The projectile manager

Rows in packed arrays, stepped by the Tick (`step`). `spawn`, `add_target`, `ray`, `sweep`, `strike`, `threat`, `nearest_target`, `targets_in`, `set_cap`. Events (`projectile_hit`, `projectile_expired`, `shot_ended`, ...) name the shot's slot last. Every hit it sends on a body is a row of its hit table (`hit_table`, `HitTable`: the hits since its step began, in the order sent; perf plan H1): `projectile_hit` goes out from the row, then the table's applier (Combat's `apply_hit_row`) applies it, after every listener. The hit-work budget is work units, never time. Tests: `tests/core/test_projectiles_kit.gd`, `test_hit_budget.gd`, `test_draw_regions.gd`, `test_body_walk.gd`.

Its code is split by job; its state is not. `projectile_manager.gd` holds every member (the state, DERIVED, REFS, VIEW, in their order), every constant the native kernels check, the public API (a moved function keeps a one-line wrapper there, so no caller changes), the lifecycle (`set_cap`, `clear`, `begin_run`, `rebuild_derived`), `step`, and a shot's end and its events (`_kill`, `_expire`, `_send_hit`). Each job is a script of its own, an `Object` the manager makes and frees (`_job_<name>`, DERIVED):

| Job | Script | What |
|---|---|---|
| rows | `projectile_rows.gd` | a shot's row written at spawn, the batch spawn, the cap's drop |
| targets | `projectile_targets.gd` | registered bodies, their grid, `nearest_target`, `targets_in` |
| moves | `projectile_moves.gd` | the common and trail passes, behaviour lists and passes, orbits, homing |
| hits | `projectile_hits.gd` | the hit pass, the hit test, the targets a shot remembers, the merged hits (sent as rows of the hit table) |
| walls | `projectile_walls.gd` | wall bodies, solid shots, what a shot does at a wall |
| guards | `projectile_guards.gd` | deflect, block, shots in a wedge, `threat`, shields |
| places | `projectile_places.gd` | portal gates, fields, `shot_places`, `pass_shot` |
| rays | `projectile_rays.gd` | `ray`, `sweep`, `strike`, a beam's path, and many beams' rays between their hits walked in one call (`ray_walks`, natively `ShotKernel.ray_walks`) |
| batches | `projectile_batches.gd` | the MultiMesh batches, card bodies, the heads' mesh |
| draw | `projectile_draw.gd` | `update_draw`, motes and tails, the row codes |

A job reads the manager's arrays through members of its own of the same names, aliases of the manager's (`link`: a packed array shared, never a copy), so its code reads as the manager's did and loops as fast; scalars and calls go through `pm`. The manager links its jobs again whenever its arrays may have been replaced (`_link_jobs`: after a snapshot's restore and a run's renew); its own code only ever resizes them. A member something outside the manager replaces whole (`step_profile`, the benchmarks') is never aliased: `pm.step_profile`.

### How to add a shot behaviour

(1) Its numbers per slot: a packed array in `projectile_manager.gd`, sized in `set_cap`, reset in `ProjectileRows._write_row`, and named in `ProjectileMoves`' members and DERIVED where its pass reads it; (2) `set_<name>(slot, ...)` in the manager calls `_job_moves._join(slot, B_<NAME>)` (`_leave` to switch off); (3) `B_<NAME>` in the order (renumber, raise `BEHAVIOURS`, and `AFTER_HITS` if before the hits), its pass at that index of `BEHAVIOUR_PASSES`, a line in the order comment; (4) `_pass_<name>(list, first, count, delta)` in `projectile_moves.gd`, copied from `_pass_spiral` or `_pass_homing`: never sends an event, ends a shot (mark `S_EXPIRE`/`S_GONE`) or changes a list; calls `_wait(slot, B_<NAME>)` before reading what a hit handler may change. Add a test like `_test_spiral_weaves_round_its_line` and the setter's call in `Spells._apply_travel`.

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

## The game's font

Every text but the boss names' title type is drawn in one original pixel font at art-pixel detail (two art pixels a layout pixel), `PixelFont` (`display/pixel_font.gd`): a bitmap FontFile made at boot from the glyph sheet `art/ui/fonts/text.png` and its metrics `text.json` (drawn by `tools/font_art.py`), with a cache for every size from `FIRST_SIZE` to `LAST_SIZE` and outline up to `MAX_OUTLINE`, and made every theme's default by `Display` as it enters the tree. A size is drawn by the largest face at or under it (only a size past twice the last face by a face scaled); its line (ascent, descent) is the old default font's, so layouts are unchanged; advances are whole layout pixels. An outline of any size is the glyph's one-art-pixel outline, from `HEAVY` (3) up with a pixel's hard shadow down-right. Nothing is rasterized in play, so nothing races the render thread. A size or outline outside the lists draws nothing, and `GlyphWarmup.drawn_since_warm` names it; a character the font lacks draws nothing either (no system font), so a new one goes in `tools/font_art.py` and `GlyphWarmup.EXTRA`. Glyphs are placed on half layout pixels (art pixels), so text must be drawn on a canvas at the picture's scale: text drawn into a texture of its own must draw it `ArtDetail.DETAIL` times (the damage numbers' sheet, `gameplay/feel/number_glyphs.gd`), or half its art pixels are lost. `tests/core/test_pixel_font.gd`.

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
