# Card looks: every carrier's look in its own folder

**Status: plan (2026-11-08), for the owner's review.** The owner, on the pool's look first being a branch of the rune shader: "if a card needs a shader, a new shader is added in its folder", then "ideally each shot should have its own", and "this should also make it easier to change the look of eg. Bolt in the future". PR #632 did it for still shots: the rune, the wall's stones and the pool's puddle are shaders in their card folders (`FormBase.shot_shader`), the projectile manager makes a pair of batches for each card's shader as it is numbered (no fixed number, in the native kernel too), and a plain fallback (`core/projectiles/shot_still.gdshader`) draws a still shot whose card names none. This plan takes the same idea to every other carrier with a look of its own.

## Where every carrier's look is now

| Carrier (cards) | Drawn by | Shader today | In its folder after |
| --- | --- | --- | --- |
| rune, wall, pool | the projectile manager, still batches | `forms/<card>/*.gdshader` | done (#632) |
| atom (atom, bolt, nova), swap, orbit's shots | the projectile manager, head batches (`head_mesh`) | `core/projectiles/shot_head.gdshader`, one for all | phase 1 |
| beam | Feel, one beam mesh per live beam (`Feel._make_beam`) | `core/projectiles/shot_beam.gdshader` | phase 2 |
| swing | Feel's swing trails (`swing_trails.gd`) | `core/projectiles/shot_swing.gdshader` | phase 2 |
| familiar (its orb) | Entities (`entities.gd`) | `core/projectiles/shot_orbit.gdshader` | phase 3 |
| dash, teleport, rain, slam, portal | cues only (`content/cues/`, flashes in `content/flashes/`) | none of their own | already data in content: nothing to move |
| decoy | the actor look (a copy of its caster) | `shot_sprite.gdshader`, shared by every sprite | stays: it is not a look of the card |

Effects stay in `core/projectiles/` (flashes, blasts, arcs, statuses, sprites, motes): they belong to no card, and cues already pick them as data.

## The rule, one field

`FormBase.shot_shader` becomes `FormBase.look_shader` (one rename, phase 1): **the shader that draws this card's carrier**, whichever area draws it. Null means the area's plain fallback, which stays in `core/` because something with no card is drawn the same way (a chain's jump and a zap are drawn as beams with no beam card; a test or a payload may spawn a plain shot). Each area keeps today's shader as that fallback, so nothing looks different until a card names its own.

What every card shader keeps, as today's shot shaders do (core/README.md, "The shot shaders"): small and branch-light (a big fragment stage once took ~90 s to compile in a Windows browser), the particle rule (`4 + 2 per kind`, checked by `test_projectile_looks`), the instance encoding of the area that draws it, and a warm-up before the first room (each area hands its card shaders to `ShaderWarmup.want` when Spells numbers them at start, as #632 does).

## Phase 1: flying shots (the bolt's look)

**Yes, this is what makes the bolt's look easy to change.** Today the bolt, the atom, the nova, the swap and the orbit's shots all draw with one shared shader in core. After this phase, giving the bolt a look of its own is a `forms/bolt/bolt.gdshader` and one line in `bolt.tres`, with no engine change.

- **Manager:** a card body works for any motion, not only still shots. `register_body(shader, mesh)` takes the mesh its batches draw: one quad a shot for a still carrier, the head mesh (`head_mesh`) for one that flies or orbits. Spells picks it from the carrier's traits (`FLIES`/`MOVES`). `_batch_of` sends a shot of a card body to its body's pair whatever its motion. The writing already picks a head or a quad by motion.
- **Native kernel:** the same batch rule (`count_draw`), with the body no longer tied to `MOTION_STILL`. `draw_shots` already writes a head for a moving shot and a quad for a still one. `test_native_kernel` gives some flying shots a card body.
- **Spell light:** a body batch of heads is lit as shots (`ROWS_SHOT`), one of quads as runes (`ROWS_RUNE`): `batch_mesh()` answers per batch, not per index.
- **Contract for a flying card shader:** copy `shot_head.gdshader` (its vertex stage places the head's quads from the instance; tails stay Feel's motes and are not the shader's).
- **Cards:** none is given a new look in this phase. The bolt, atom, nova and swap keep the shared head (no `look_shader`) until someone wants one of them to look different. A shader per card costs a draw call and a compile each, so sharing stays the default.

## Phase 2: beam and swing (Feel)

- Feel already finds a carrier card by its id for its cues (`Feel._form_cues_of`, `FormBase.look_cues`). The card's `look_shader` joins what it reads there (Feel still reads no card field itself).
- **Beam:** each live beam is its own `MeshInstance2D`, so a card shader is just its material (one `ShaderMaterial` per shader, made once and shared). `shot_beam.gdshader` stays in core as the fallback for rays with no beam card (chain jumps, zaps, arcs: `RAY_FORM`), and the beam card names a copy of it: `forms/beam/beam.gdshader`.
- **Swing:** the same in `swing_trails.gd`: `forms/swing/swing.gdshader`, with core's as the fallback.
- **Light:** the beam light (`light_beam.gdshader`) reads the beam mesh, not its shader, so it needs nothing.
- **Warm-up:** drawn as MESH (`ShaderWarmup.want(shader, MESH)`).

## Phase 3: the familiar's orb (Entities)

Entities draws a familiar's orb with `shot_orbit.gdshader`. The familiar card names its own (`forms/familiar/familiar.gdshader`). The entity request already carries the spell's tag (`entity_spawn_requested`), so Entities asks Spells for that card's look by it, as Feel asks by a form id; it never reads the card. Core's stays the fallback.

## Phase 4: docs and checks

- core/README.md "The shot shaders" and content/spells/README.md: one paragraph on card looks (which area draws which carrier, what a card shader must keep, where to copy one from).
- One test over the registry: every card's `look_shader` is a canvas-item shader, keeps the particle rule, and is warmed before the first room (extending `test_carrier_looks` and `test_shader_warmup`).
- `test_spell_field_reads` keeps passing: the areas get a card's shader through Spells or `look_cues`, never by reading the card.

## Order, size, risk

| Phase | Size | Native | Risk |
| --- | --- | --- | --- |
| 1 flying shots | medium | yes (`count_draw`) | the hot path: compared byte for byte by `test_native_kernel`; draw calls grow only when a card names its own shader |
| 2 beam, swing | small | no | Feel's beam and trail code; the screenshots `shot_beam*`, `shot_swing*` show it unchanged |
| 3 familiar | small | no | Entities' orb |
| 4 docs, checks | small | no | none |

One PR each, phase 1 first: it is the one the bolt question needs, and phases 2 and 3 copy its pattern into simpler drawers.

## Questions for the owner

1. The rename `shot_shader` → `look_shader` (one field for "the shader that draws this carrier", whoever draws it), or keep a field per kind of drawer?
2. Phase 1 gives no card a new look. Should the bolt get one now (a distinct `forms/bolt/bolt.gdshader`), or only when its art is reworked?
