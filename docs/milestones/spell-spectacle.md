# Spell spectacle: motes, floor marks and spell light

**Status: approved by the owner on 2026-11-03** (an exception to the milestone order, recorded in [ROADMAP.md](../ROADMAP.md); this is polish, which ROADMAP places in M4). The tasks are in the owner lane of [NEXT.md](../NEXT.md). The open questions under P3 are still the owner's to answer before P3b. The plan changes no damage, hit, rule or card behaviour: everything below is drawn and nothing is simulated. Making the terrain react to spells (burning ground, breakable walls) is a gameplay change and stays out of scope; [DESIGN.md](../DESIGN.md) would need the owner's direction first.

## Why

At 6,000 projectiles on desktop and 1,000 on the web, the shot cap is not what makes spells look small. Every shot costs its hits: Combat, Spells and Feel run GDScript handlers on each one, at roughly 40–70 µs a hit in the sandbox storm (DECISIONS, 2026-11-02). What is missing is everything drawn around the shots:

- **A density of cheap particles.** Today's visual budgets are small: `PARTICLE_CAP` is 1,024 sparks shared by all shots, and Feel's `effect_slots` default to 256 (64–1,024 on the slider). A GPU can draw tens of thousands of single-pixel quads in one call, and it only reaches that when particles carry no game logic.
- **A world that remembers.** Scorch and debris already exist (`KIND_SCORCH`, `KIND_DEBRIS`), but they fade within a second or so, and after a fight the room looks untouched.
- **Light.** Shots glow additively (STYLE.md, "The exception: spell shots glow"), but the floor, the walls and the bodies around them never catch that light.

The plan has three parts, one for each of these gaps, in this order: each part pays off on its own, and each later part builds on the one before.

| # | Part | Area | Pays off |
|---|---|---|---|
| P1 | **Motes**: up to tens of thousands of single-pixel particles with no game logic | `gameplay/feel/` (+ `core/settings/`) | The most density for the least cost |
| P2 | **Floor marks**: scorch, frost, cracks and settled debris that stay for the room | `gameplay/feel/`, `content/cues/` | After a fight, the room shows it happened |
| P3 | **Spell light**: shots and blasts light the floor, walls and bodies around them | `gameplay/feel/`, `content/rooms/` | Spells light up the room around them |

All three run on the web build (`gl_compatibility`), each part has a quality switch, and each one's cost is measured before it merges.

---

## P1: Motes

### The idea

A **mote** is one pixel (or a 2×2 chunk) thrown from a point. It has a velocity, a fake height with its own vertical velocity, drag, a lifetime and a colour ramp. The vertex shader computes its whole motion from its **birth row and the time since birth**: it flies, falls, lands, bounces once, lies still, and then cools out step by step through its ramp's shades (no partial alpha; STYLE.md). The CPU never touches a mote again after writing it, so there is no per-frame simulation and no native kernel is needed.

### Pool and upload

- A ring buffer of `MOTE_CAP` rows (a setting: desktop 32,768 by default, web 8,192; 0 turns motes off). A new mote takes the next row and overwrites the oldest. Nothing is allocated per frame.
- **Chunks:** the ring is split into 1,024-row chunks, one `MultiMeshInstance2D` per chunk, each made by `Batches.multimesh()` (its box is the world, so it is never culled). Only the chunks written this frame are uploaded with `multimesh_set_buffer`. A burst of 300 motes uploads one or two chunks (about 64 KB), never the whole ring. A chunk whose newest mote is past `MOTE_LIFE_MAX` is hidden, so it costs no vertices.
- Row layout (16 floats, `DRAW_STRIDE`): transform (born x, born y, vx, vy packed into the transform's free slots), colour (ramp id, kind, shade start), custom (born time, height velocity, drag, life).
- One shader, `gameplay/feel/mote.gdshader` (the `shot_particle.gdshaderinc` helpers where they fit), registered with `ShaderWarmup.want()` at the point where Feel first uses it.

### Kinds (data, not code)

A `MoteBurst` dictionary in a cue's `parts` (`"part": "motes"`), so a card or cue adds motes by data:

```
{"part": "motes", "kind": "ember", "count": 40, "speed": [60, 180], "spread": 360, "up": [20, 80], "life": [0.4, 1.2], "ramp": "caster"}
```

- Kinds to begin with: `ember` (rises, glows, cools), `spark` (fast, short, glows), `chip` (stone, falls and lies, no glow), `shard` (ice, falls and glints), `ash` (slow, drifts and sinks), `splinter` (wood, for staff bodies).
- Kinds are rows in a table in `mote.gd`, mirrored in the shader's constants, and a test compares the two.

### Where motes come from (Feel listens; nothing new is sent)

| Event | Motes |
|---|---|
| `projectile_impact` on a body | sparks back along the shot's path, in the shot's ramp (adds to today's spray) |
| `projectile_impact` on a wall | stone chips plus a few sparks |
| `projectile_expired` | a puff of the shot's own kind (an ember for fire, shards for frost) |
| `enemy_died` | splinters and embers, more for a boss |
| `reaction_triggered` | a ring of the reaction's colour |
| cues `blast`, `fireball`, `slam`, `quake` | the dense layer: hundreds of chips, embers and ash |

### Budget and degradation

- The cap is a ring, so a flood overwrites the oldest motes and the frame time does not grow.
- On top of that, each event's count is scaled by `mote_density` (a setting: 0, 0.5, 1 or 2).
- Co-op readability: motes are drawn under shots and telegraphs (`FLOOR_Z` for landed motes, `FORM_Z - 2` for flying ones), never over a telegraph.

### Tests (`tests/gameplay/feel/test_motes.gd`)

- The ring wraps with no allocation (`Performance` object count stable across 10,000 spawns), and writing past the cap overwrites the oldest row.
- Only dirty chunks upload: a counter of `multimesh_set_buffer` calls per frame equals the number of chunks written.
- `mote_land(row)` (a GDScript reference of the shader's flight) matches the shader's constants and is used by P2. A test checks that the reference and the shader table agree, so a change to one fails until the other changes too.
- Every event in the table above makes motes. With `MOTE_CAP` at 0, none are made and no nodes exist.
- Every kind named in `content/cues/` exists (a test fails for an unknown kind).

### Measurement (merge gate)

- `tests/benchmark/sandbox_storm.gd --motes`: the frame time and the physics step's scripts with motes on and off. The CPU cost of the spawns must stay under 0.5 ms a frame in the storm.
- `tests/benchmark/trail_gpu.gd` gains a mote scene: 32k motes in flight on llvmpipe, with the vertex cost recorded in DECISIONS. A real-GPU figure goes to the owner, as with the trails.
- The web stress run with motes at the web default: the physics step still within its 12 ms.

### PRs

1. **P1a: the pool, the shader and the setting.** `mote.gd` (child of Feel, like `swing_trails.gd`), `mote.gdshader`, `core/settings/mote_cap.gd` and the pause menu's "Particles" slider, the tests above. Only the wall chips are wired up, as the first source.
2. **P1b: sources.** The events table, the `motes` cue part in `core/base/cue_base.gd`, motes added to the existing cues' `.tres`, and a screenshot sheet of each kind. Built (DECISIONS, 2026-11-04): the kinds stay the cards' (`kind: spell`) and the surfaces' (`kind: surface`; a dying body's chips in its own art's colours) instead of new ash and splinter kinds; `tests/screenshots/shot_mote_sources.gd` draws each source and each cue.
3. **P1c: measure and tune.** The benchmarks above, the defaults set from them, and a DECISIONS entry.
4. **P1d: the trails' shed particles as motes (an experiment, measured).** The trail shader keeps the tail line, which has to follow a path that bends after the shot is fired. The sparks and card particles a trail leaves behind no longer depend on the shot once they are dropped, which is what a mote is. Spawning them as motes lets the trail mesh drop those particle slots (DECISIONS, 2026-11-02: the mesh's vertex count is the cost, drawn or folded), but each dropped particle becomes a CPU write: about 30 a second per shot, or about 180,000 rows a second at 6,000 shots. So try it only below a live-shot threshold, with the trail shader keeping its own particles above it. Measure both sides: the trail GPU benchmark (`tests/benchmark/trail_gpu.gd`) at 60, 400 and 3,000 shots, and the storm's CPU time. Merge only if the GPU time saved is larger than the CPU time added, and the look is the same (screenshot sheet before and after). Either way, record the result in DECISIONS. After P1b.

---

## P2: Floor marks

### The idea

Each room gets a **mark layer**: a texture over the floor, under every body, that is painted into and never cleared until the room ends. Scorch, frost, cracks, burn rings, rune circles and settled motes are **stamped** into it once and then cost nothing.

### How it draws

- A `SubViewport` the size of the room's floor at one texel per world pixel (for example, a 40×23-tile room is 1,280×736, about 3.8 MB RGBA8), with `render_target_clear_mode = CLEAR_MODE_NEVER` and `render_target_update_mode = UPDATE_DISABLED`, set to `UPDATE_ONCE` on a frame a stamp lands. A frame with no new stamps renders nothing.
- Stamps for a frame are one `Batches.multimesh()` batch inside the viewport, drawn by `gameplay/feel/mark.gdshader` (a stamp's shape, from an atlas row or computed). It is emptied after the frame renders.
- The viewport's texture is shown by one `Sprite2D` at `FLOOR_Z - 1`, above the floor tiles and below the existing `FLOOR_Z` effects. The room's `TileMapLayer` is untouched.
- Style: only palette colours, at most the shadow and base shades of their material plus Stone shadow, so marks never compete with a shot or a telegraph. Stamps are hard pixels with no partial alpha (STYLE.md). Marks stay off the walls: the stamp shader is clipped by a floor mask built once per room from the projectile manager's wall grid (`set_walls`), at one bit per wall cell.

### Stamps (data)

A cue part `"part": "mark"`:

```
{"part": "mark", "mark": "scorch", "reach": 1.0, "rot": "random"}
```

- Marks to begin with: `scorch` (blast, fireball), `frost` (frost impacts and freeze), `crack` (slam, quake), `burn_ring` (nova), `rune_scar` (rune burst), `ichor` (enemy death; a dull sap, not blood), and `char` (a lightning strike).
- **Settled motes:** when a `chip`, `shard`, `ash` or `splinter` mote lands, P1's `mote_land(row)` gives where and when. Feel queues a 1-pixel stamp for that time, so debris that has stopped stays on the floor. These are capped at `SETTLED_PER_FRAME` (512) stamps a frame, and the rest just fade.

### Life

- Marks last for the room. A new room or `clear()` wipes the texture (one clear-colour render).
- Optional slow fading (a setting, off by default; owner's choice): a per-frame alpha-free fade is not possible within the palette rules, so a fade would be a stamp of the floor colour over the oldest marks. This is only worth building if the owner wants it.
- The horde arena (long fights) gets the same layer. It saturates by overwriting itself, at no extra cost.

### Tests (`tests/gameplay/feel/test_marks.gd`)

- The stamp queue: each mark cue part queues one stamp at the right place and scale, and the queue empties after the frame renders.
- A frame with no stamps does not render the viewport (its update mode reads `UPDATE_DISABLED`).
- Settled motes: the stamp is queued at `mote_land(row)`'s point and time, and the per-frame cap holds.
- Room end clears the layer.
- Every mark named in `content/cues/` exists in the atlas.
- The look: a screenshot sheet with each mark on the crypt floor at 1× and 4×, for the owner's eyes. Headless runs have no renderer, so pixels are only checked in the screenshot pass.

### Measurement

- The GPU cost of a frame with 300 stamps, and of a frame with none (it should be zero), on llvmpipe and in the web export.
- Memory: the texture size per room, recorded in DECISIONS.

### PRs

1. **P2a: the layer and the stamp batch.** The viewport, the sprite, `mark.gdshader`, the `mark` cue part, three marks (`scorch`, `crack`, `frost`) added to the blast, slam and frost cues, and the tests.
2. **P2b: settled motes and the rest of the marks.** After P1a.

---

## P3: Spell light

### The idea

Shots, blasts, flares and beams also draw into a **light buffer**, a low-resolution screen-sized texture that is cleared every frame. The world under the shots (floor, walls, marks and bodies) is lit by it. The shots themselves are not lit, because they are the light.

### How it draws

- **The light buffer:** a `SubViewport` at a quarter of the screen's resolution (480×270 at 1080p), cleared to black each frame, following the camera.
- **No new CPU writes for shots.** A second `MultiMeshInstance2D` in the light viewport shares each shot batch's `MultiMesh` resource (the same buffer the manager already uploads) and draws it with `gameplay/feel/light.gdshader`: one soft quad per shot, sized by its radius, in its ramp's light shade. The same goes for Feel's effect batch (flares, blasts, rings) and the live beams (a beam's light is its mesh with a wide falloff).
- **Applying it:** one full-screen `ColorRect` with `blend_mul`, placed above bodies and walls and below every shot, effect and telegraph (between the body layers and `DRAW_Z`/`EFFECT_Z` 50; the exact z is checked in P3a). Its shader reads the light buffer and outputs `ambient + light`, **posterised to three steps** (dim, lit, bright), so a lit floor changes by whole bands, like a shade step, and never by a smooth gradient.
- **Ambient:** a property of the room (`RoomBase.ambient`, by default 1.0, which means no darkening and only added light). With ambient at 1.0, light can only brighten, so a room looks as it does today until spells light it. A darker crypt is an art direction choice for the owner.
- **Torches:** the crypt's torch decals draw into the same buffer (one quad each), so rooms have light sources of their own.

**As built in P3a** (DECISIONS, 2026-11-04, "Spell light"): two changes to the above. (1) The light batches do not share the shot batches' `MultiMesh`: a MultiMesh holds its mesh, and the trails' mesh is hundreds of vertices a shot, each run drawn or folded. Instead the manager hands each light batch the very buffer its shot batch uploads (`mirror_batch`), drawn with a quad: no row is written twice, four vertices a shot. (2) The rect does not blend with `blend_mul`: a multiply blend is clamped to 1 in an 8-bit target (checked on the compatibility renderer), so it can only darken. It reads the screen under it (`hint_screen_texture`) and draws it times `ambient + light`. It sits at `Feel.LIGHT_Z` (15): the bodies and the room's art are at 6 or below, and the motes (16), floor flashes (17), beams (18), flashes (20), entities (40), shots and effects (50) are above it.

### Open questions for the owner

1. STYLE.md allows soft glow only on shots ("never baked into an asset"). Spell light would be the world taking light from shots, and STYLE.md needs a line saying so, with the three-step banding as the rule.
2. Should rooms be darker (ambient below 1.0) so spells read as light sources? This is a big change to the look, and readability with four players matters more than mood.
3. Do enemy shots light the room too? Yes by default (one rule for every spell), but a dark room with many enemy shots could tell the player too much or too little.

### Tests (`tests/gameplay/feel/test_light.gd`)

- The light batches share their shot batch's `MultiMesh` (the same RID), so no second upload exists.
- The z-order: the multiply rect is above every body layer and below `DRAW_Z`, `EFFECT_Z` and the telegraph cues (a test walks the tree).
- With light off (the setting) the viewport and the rect do not exist.
- Both new shaders are in the warmup (the existing shader-warmup test fails otherwise).
- The look: a screenshot sheet with a bolt, a blast and a beam in a room at ambient 1.0 and at 0.7.

### Measurement

- The viewport pass at 6,000 shots on llvmpipe, and at 1,000 shots in the web export. The light quads are small and the buffer is a sixteenth of the screen's pixels, so the estimate is under 1 ms on a real GPU. It is measured, not assumed.
- If the web cannot hold it, light is off by default on the web and on by default on desktop.

### PRs

1. **P3a: the buffer, shot light and the multiply.** With ambient fixed at 1.0, the room looks the same until something glows.
2. **P3b: effects, beams and torches.** Also the room's `ambient`, after the owner answers question 2.

---

## Settings

One "Effects" group in the pause menu holds what is there (`effect_slots`) and the new settings: **Particles** (`mote_cap`: off, low, medium, high), **Floor marks** (on or off) and **Spell light** (on or off). Each setting is a small script in `core/settings/` like `effect_slots.gd`, with an event when it changes, and a "Low / High" preset that sets them all. Web defaults are lower, and each is set from that part's measurements.

## Order and dependencies

```
P1a ─┬─ P1b ─┬─ P1c
     │       └─ P1d
     └─ P2b
P2a ─── P2b
P3a ─── P3b
```

P1a, P2a and P3a touch different files and can be built at the same time. P2b needs P1a (`mote_land`). Each PR is one session, with tests, a screenshot sheet for the owner, and `tools/check.sh` plus `ci/build/build.sh --quick --tests` passing.

## What this does not do

- No gameplay: no burning ground, no terrain that breaks, and no mark or light that a rule reads.
- No new projectiles, no change to the shot caps, and no merged shots (DECISIONS, 2026-11-02: what shots cost is their hits).
- No new art files: every stamp and mote is drawn from the palette by its shader. If a mark later needs an atlas, it is a `.png` listed in an `assets.json` beside it.
