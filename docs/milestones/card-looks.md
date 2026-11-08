# Card looks: every carrier's look in its own folder

**Status: plan (2026-11-08), reviewed by the owner the same day: one field, `look_shader` (question 1: yes), and the bolt gets a look of its own in phase 1 (question 2: "let's try yes"). Revised the same day after a design review: a body is a shader and a mesh, and a shot whose motion draws another mesh falls back to its motion's batch (phase 1); one material per beam and trail, not per shader (phase 2); one way to ask for a card's look, `Spells.look_shader_of` (phases 2 and 3). Then, on the owner's ask ("the Atom should not emit as much light as the bolt"): a card's light, `FormBase.look_light` (phase 1b).** The owner, on the pool's look first being a branch of the rune shader: "if a card needs a shader, a new shader is added in its folder", then "ideally each shot should have its own", and "this should also make it easier to change the look of eg. Bolt in the future". PR #632 did it for still shots: the rune, the wall's stones and the pool's puddle are shaders in their card folders (`FormBase.shot_shader`), the projectile manager makes a pair of batches for each card's shader as it is numbered (no fixed number, in the native kernel too), and a plain fallback (`core/projectiles/shot_still.gdshader`) draws a still shot whose card names none. This plan takes the same idea to every other carrier with a look of its own.

## Where every carrier's look is now

| Carrier (cards) | Drawn by | Shader today | In its folder after |
| --- | --- | --- | --- |
| rune, wall, pool | the projectile manager, still batches | `forms/<card>/*.gdshader` | done (#632) |
| atom (atom, bolt, nova), swap, orbit's shots | the projectile manager, head batches (`head_mesh`) | `core/projectiles/shot_head.gdshader`, one for all | phase 1 |
| beam | Feel, one beam mesh per live beam (`Feel._make_beam`) | `core/projectiles/shot_beam.gdshader` | phase 2 |
| swing | Feel's swing trails (`swing_trails.gd`) | `core/projectiles/shot_swing.gdshader` | phase 2 |
| familiar (its orb) | Entities (`entities.gd`), one MultiMesh for every familiar | `core/projectiles/shot_orbit.gdshader` | phase 3 |
| dash, teleport, rain, slam, portal | cues only (`content/cues/`, flashes in `content/flashes/`) | none of their own | already data in content: nothing to move |
| decoy | the actor look (a copy of its caster) | `shot_sprite.gdshader`, shared by every sprite | stays: it is not a look of the card |

Effects stay in `core/projectiles/` (flashes, blasts, arcs, statuses, sprites, motes): they belong to no card, and cues already pick them as data.

## The rule, one field

`FormBase.shot_shader` becomes `FormBase.look_shader` (one rename, phase 1): **the shader that draws this card's carrier**, whichever area draws it. Null means the area's plain fallback, which stays in `core/` because something with no card is drawn the same way (a chain's jump and a zap are drawn as beams with no beam card; a test or a payload may spawn a plain shot). Each area keeps today's shader as that fallback, so nothing looks different until a card names its own.

**One way to ask for it.** No area reads the card: each asks Spells, `Spells.look_shader_of(form_id: StringName) -> Shader` (null for no card, or a card that names none). Spells fills it once at start, in the walk over the carrier cards it already makes in `register_bodies`, so a call allocates nothing. Feel (phase 2) and Entities (phase 3) both hold Spells already (`Feel.spells`, `Spells.familiar_at`), and the projectile manager keeps getting its shader with the compiled spell (`CompiledSpell.look_shader`). `look_cues()` is not widened with a shader: it stays cues and a radius (and its doc comment in `Feel._form_cues_of` is fixed to list its six entries).

**The rename must not lose a look in silence.** Godot drops a property it does not know when it loads a `.tres`, so a card (or a contributor's branch) still writing `shot_shader = ...` would load clean and draw plain. Phase 1 renames it everywhere (the three `.tres`, `compiled_spell.gd`, `staff_compiler.gd`, `spells.gd`, the field the validator names in `validator.gd`, the wall's and pool's tests), and the validator reads the card's file text for a `shot_shader =` line and names it ("renamed `look_shader`"), with a test that a card carrying it fails.

What every card shader keeps, as today's shot shaders do (core/README.md, "The shot shaders"): small and branch-light (a big fragment stage once took ~90 s to compile in a Windows browser), the particle rule of the area that draws it (below, phase 4), the instance encoding of that area, and a warm-up before the first room (each area hands its card shaders to `ShaderWarmup.want` when Spells numbers them at start, as #632 does).

## Phase 1: flying shots (the bolt's look)

**Yes, this is what makes the bolt's look easy to change.** Today the bolt, the atom, the nova, the swap and the orbit's shots all draw with one shared shader in core. After this phase, giving the bolt a look of its own is a `forms/bolt/bolt.gdshader` and one line in `bolt.tres`, with no engine change.

- **A body is a shader and a mesh.** The writing picks a shot's mesh by its motion (a quad for a still shot, `_write_stones`; a head for any other, `_write_head`; the same in the kernel's `draw_shots`), and a batch draws one mesh, so a body's batches must be the mesh its shots are written as. The manager therefore numbers a body by the pair (shader, mesh), not by the shader alone: `register_body(shader, mesh)` with `mesh` `MESH_QUAD` or `MESH_HEAD`, the same shader under two meshes being two bodies. Spells numbers a carrier card's shader for the mesh of its shots' motion, which it knows from the carrier (still carriers spawn `MOTION_STILL`); the carrier's traits are not asked.
- **A shot whose motion draws another mesh falls back.** `_batch_of` sends a shot to its body's pair only when the mesh of its motion (`mesh_of_motion`, the rule the writing uses) is the body's mesh; otherwise to its motion's own batch (`BATCH_BOLT`, `BATCH_STILL`, `BATCH_ORBIT`, the enemy ones), drawn plain. So the routing and the writing can never disagree, whether two cards name one shader for different carriers or a shot changes motion after it is spawned (`deflect_shot` already turns an orbit shot straight). A test spawns shots of one card in both motions and checks each lands in a batch of its own mesh.
- **The drawn cache sees motion.** `_remember_drawn` (and the kernel's copy in `count_draw`) refreshes a slot's batch when its seq, radius or look change, not its motion; with motion in the batch rule, `_drawn_motion` joins that key, or a deflected shot keeps a batch of the wrong mesh.
- **Native kernel:** the same rule in `count_draw` (`body_mesh` handed to the kernel with the bodies, compared to the motion's mesh), byte for byte with the GDScript; `test_native_kernel` gives some flying and some still shots card bodies of each mesh, and one shot a body of the other mesh.
- **How many bodies.** A slot's body and its batch stay a byte each, and a body is still a pair of batches, so the limit is unchanged: `MOST_BODIES = 125`, `5 + 2 x 125` batches. A body past it is drawn by its motion's plain batch (an error names it), as today. The rule makes only the bodies a card asks for, so a shader is never given batches of a mesh nobody draws.
- **Spell light:** a body batch of heads is lit as shots (`ROWS_SHOT`), one of quads as runes (`ROWS_RUNE`). `batch_mesh(batch)` answers from the body's mesh, so it stops being `static`: `spell_light.gd` asks the manager it lights (not `ProjectileManagerScript`), and a light test covers a head body's batch.
- **Contract for a flying card shader:** copy `shot_head.gdshader` (its vertex stage places the head's quads from the instance; tails stay Feel's motes and are not the shader's). Warmed as a batch (`ShaderWarmup.want(shader, BATCH)`), as the head shader is.
- **Cards:** the bolt gets a look of its own (owner, 2026-11-08: "let's try yes"): `forms/bolt/bolt.gdshader`, a copy of the head shader made distinct, shown beside the plain head in `shot_looks.gd` for the owner to judge. The atom, nova and swap keep the shared head (no `look_shader`) until someone wants one of them to look different: a shader per card costs a draw call and a compile each, so sharing stays the default.

## Phase 1b: a card's light (the atom lit less than the bolt)

The owner, 2026-11-08: "the Atom should not emit as much light as the bolt". Today every shot lights the room equally bright: one strength per light batch (`shot_strength` 0.9 for heads, `rune_strength` 0.55 for quads, uniforms of `gameplay/feel/light.gdshader`), its reach set only by its size (an atom's 1.5 radius is already a speck's smaller reach, as bright as a bolt's). How bright is a card's to say, beside its shader.

- **One field:** `FormBase.look_light: float = 1.0`, how bright its carrier lights the room, times the area's light (0 lights nothing). A plain number in the card's `.tres`, like the speed curve. The validator keeps it in 0 to 2, so no card can blind the room. Compiled into `CompiledSpell.look_light` with the shader. Changing the atom's light is one line in `atom.tres`, with no engine change.
- **Per shot, not per batch.** The atom shares its head batch with the bolt, nova and swap, so a light per batch would give it a body (a pair of batches) only to be dimmer. Instead the light goes with each shot: `set_looks` keeps it per slot (`_look_light`, listed in the manager's `VIEW`: drawn only, never hashed), and `_write_head`, `_write_quad` and `_write_stones` write it in the row's free float `MODEL_MATRIX[2].y` (buffer index 6, 0 today). That is the same float a flash row already gives its light in (`room_light`), so `light.gdshader` reads it the same way: `shot_strength` and `rune_strength` times it. No draw call is added, and a card that never sets it lights as today.
- **Native kernel:** `draw_shots` writes the same float from the same array, byte for byte; `test_native_kernel` gives some shots a light other than 1.
- **The shot shaders do not read it** (the head's, the plain still's, every card's): float 6 stays theirs to ignore, and the phase-4 test checks no card shader reads `MODEL_MATRIX[2]`.
- **The atom:** `look_light = 0.5` to start, shown beside a bolt in the spell-light screenshot (`tests/screenshots/shot_spell_light.gd`) for the owner to judge.
- **Beyond shots:** the beam's light (phase 2) honours it too: Feel hands `light_beam` the beam's strength, `BEAM_STRENGTH` times `Spells.look_light_of(form)` (the same lookup as the shader's, filled at the same time). A familiar's orb gives no light today, so nothing changes there.

It does not need phase 1's bodies, so it can go before or after it; it comes right after, since both change the same row writers and kernel loop.

## Phase 2: beam and swing (Feel)

- Feel asks for a carrier's shader by its form id, `spells.look_shader_of(form)`, once per form id and kept (as `_form_cues_of` keeps cues); it reads no card field.
- **One material per node, not per shader.** Each live beam sets its own uniforms on its own material (`beam_path`, `beam_start`, `beam_end`, `beam_length`, ...: `Feel._on_form_shown`), and each swing trail its own (`swing_origin`, `sim_time`), so a material is never shared between nodes. A beam's node keeps its `ShaderMaterial`; when it is shown for a beam, its `material.shader` is set to the card's (or core's) only when it differs from the one it has, so nothing is allocated or recompiled per cast. A test shows two beams of different cards at once and checks each node keeps its own path and shader.
- **Beam:** `shot_beam.gdshader` stays in core as the fallback for rays with no beam card (chain jumps, zaps, arcs: `RAY_FORM`), and the beam card names a copy of it: `forms/beam/beam.gdshader`.
- **Swing:** the same in `swing_trails.gd`: `forms/swing/swing.gdshader`, with core's as the fallback; a trail's shader is set when it is shown for a swing.
- **Light:** the beam light (`light_beam.gdshader`) reads the beam mesh, not its shader, so a beam shader needs nothing for it; how bright it is comes from the card's `look_light` (phase 1b).
- **Warm-up:** drawn as MESH (`ShaderWarmup.want(shader, MESH)`), handed over when Spells fills `look_shader_of`.

## Phase 3: the familiar's orb (Entities)

Entities draws every familiar in one MultiMesh with one material (`_familiar_node`, `shot_orbit.gdshader`). The familiar card names its own (`forms/familiar/familiar.gdshader`). With one familiar card, Entities asks once, when it makes that node, `Spells.look_shader_of(&"familiar")`, and sets the node's shader (core's when it is null); nothing is asked per spawn. The shader Entities keeps is listed in its `VIEW` (Entities is in a simulation folder, `gameplay/ai`). If a second card ever makes familiars with a look of its own, that is one MultiMesh per shader (made with `Batches.multimesh()`), chosen by the spawn's form: work for that card's PR, not this one. Core's stays the fallback.

## Phase 4: docs and checks

- core/README.md "The shot shaders" and content/spells/README.md: one paragraph on card looks (which area draws which carrier, what a card shader must keep, where to copy one from, `Spells.look_shader_of`; how bright a card lights, `look_light`).
- One test over the registry: every card's `look_shader` is a canvas-item shader, keeps the particle rule **of the area that draws its carrier**, and is warmed before the first room (extending `test_carrier_looks` and `test_shader_warmup`); and no card shader reads `MODEL_MATRIX[2]`, the row float the light reads (phase 1b). The rule is the area's: a manager batch shader (head, still, orbit) keeps `4 + 2 per kind` (`test_projectile_looks`); a beam or swing shader draws its particles as geometry (`shot_beam.gdshader`, "PARTICLES ARE GEOMETRY") and keeps that mesh's quad count instead. The test finds each card's drawer from its carrier (the manager, Feel's beam, Feel's swing, Entities) and checks the card against that drawer's rule.
- `test_spell_field_reads` keeps passing: the areas get a card's shader through `Spells.look_shader_of`, never by reading the card.

## Order, size, risk

| Phase | Size | Native | Risk |
| --- | --- | --- | --- |
| 1 flying shots | medium | yes (`count_draw`) | the hot path: compared byte for byte by `test_native_kernel`; a body's mesh against its shots' motion (the fallback rule and its test); the drawn cache's key; light rows of a head body's batch; draw calls grow only when a card names its own shader (the bolt's own look is one more pair) |
| 1b a card's light | small | yes (`draw_shots`) | the row writers and the kernel's, compared byte for byte; the spell-light screenshots (`shot_spell_light*`) and `test_light` show every card but the atom unchanged |
| 2 beam, swing | small | no | Feel's beam and trail code, a material per node; the screenshots `shot_beam*`, `shot_swing*` show it unchanged |
| 3 familiar | small | no | Entities' orb node |
| 4 docs, checks | small | no | none |

One PR each, phase 1 first: it is the one the bolt question needs, and phases 2 and 3 copy its pattern into simpler drawers. Phase 1b follows it (the same writers), and phase 2's beam light needs it.

## The owner's answers (2026-11-08)

1. **One field:** `shot_shader` is renamed `look_shader` in phase 1, "the shader that draws this carrier", whoever draws it.
2. **The bolt gets its own look** in phase 1 (`forms/bolt/bolt.gdshader`), to try it.
