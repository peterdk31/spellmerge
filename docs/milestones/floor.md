# The floor's first slice: water, ice and lightning on bare floor

**Status (2026-11-25): built (this PR).** Part 1's first slice of [foundations.md](foundations.md) ("a floor that answers"), with the owner's answers to its open points (2026-11-25). Oil, Spill and the oiled, burning and scorched states are the next PR (Part 2's first one), not this one.

## What the players see

- **Water on bare floor is a puddle.** A water blast, Nova, pool, fountain, bolt or spray leaves the floor wet where it lands and **along the way it flies** (every shot, dash and swing touches the floor as it passes: the owner's answer 2). A puddle soaks whoever stands in it and dries in a while.
- **The lake (build 1).** One lightning atom into a puddle and the water is live: the lightning runs through every wet cell joined to it within a few ticks, and everybody standing in it is zapped (a small lightning hit, which on a soaked body sets off Current). A lake is live once: it is spent for a moment after, then wet again, and lightning does not light a spent cell.
- **Ice bridge (build 4).** Frost on a puddle freezes it: whoever stands on ice is chilled (never frozen by the ice alone). Fire cannot cross it, and thaws it back to water, for the lake. Fire on a puddle is steam, and the floor is dry again.
- **It is somebody's.** A cell remembers who lit it (the owner's answer 3): the lake's zaps are its caster's hits, so its kills count for `on kill`, a Siphon on the spell refunds on them, and the run's numbers name the caster.
- **The AI walks through a puddle and ice, and out of a live lake.** Only states that hurt count as danger.

## The states of `floor`

`content/cover/floor/` (a `CoverKind` that fills every open cell no other kind took, `fills_floor`; drawn flat, `look = FLAT`). The changes of look are states of their own, so each plays its frames through (docs/STYLE.md, "Smooth": 4 frames, whole pixels).

| State | Look | Gives who stands in it | Moves on |
| --- | --- | --- | --- |
| `dry` (rest) | nothing | nothing | water: `wetting` |
| `wetting` | water grows in from the puddle's edge, 4 frames, 0.25 s | soak 25 for 1 s, every 0.5 s | after 0.25 s: `wet` |
| `wet` | water, still | soak | water: `wet` again (its time from 0); frost: `freezing`; lightning: `live`; fire: `steam`; after 12 s: `drying` |
| `drying` | water shrinks to its middle, 4 frames, 0.5 s | nothing | after 0.5 s: `dry` |
| `live` | water with Arc sparks, a 4-frame loop at 12 fps, sparks given off | soak, and struck: lightning, 4 damage, every 0.5 s | spreads lightning to wet neighbours, 25 a second (about 0.4 a tick); after 0.8 s: `spent` |
| `spent` | water, still | soak | water: `wet`; frost: `freezing`; fire: `steam`; after 1.5 s: `wet` (lightning moves it nowhere) |
| `freezing` | ice grows over the water, 4 frames, 0.34 s | chill | after 0.34 s: `ice` |
| `ice` | ice, still, light glints | chill 30 for 0.45 s, every 0.5 s (wears off between two: ice never freezes a body by itself) | fire: `thawing`; after 20 s: `thawing` |
| `thawing` | the ice shrinks off the water, 4 frames, 0.34 s | soak | after 0.34 s: `wet` |
| `steam` | the water shrinks away, steam given off, 4 frames, 0.5 s | nothing | after 0.5 s: `dry` |

The transitional states take no element (0.25 to 0.5 s): water or lightning on a freezing puddle does nothing until it is ice. A state that gives a status but hurts nobody (soak, chill) is `harmless`, so the AI's look passes it by; `live` is danger.

## The engine work

### Cover (core/base, gameplay/cover)

- **`CoverKind.fills_floor`**: the layout's last pass (`CoverLayout._lay_floor`) gives the first such kind (in id order) every cell no source took that is not under a wall or a hole: a door's, a spawn's and a placement's cell too, and in every room, filled or not. Still worked out from the room: no new state for where it lies. A cell of grass or cobweb is still grass or cobweb (a hole in a lake).
- **`CoverKind.look`**: `TUFTS` (today's) or `FLAT` (no sheet; Feel draws it as one joined surface).
- **A state that strikes** (`CoverState.strike_element`, `strike_damage`): a body standing in it is struck as by a hit of that element (`floor_strike_requested`, Combat's: a spell's hit with that element and damage, no card's status), on the same timer as its status (`status_every`); its status first, so `live` soaks, then strikes, and Current goes off.
- **Faster spreads**: `spread_chance` up to 60 a second (today at most 1), rolled as today, `spread_chance × delta` a tick.
- **`CoverState.harmless`**: gives its status, but the AI's look (`cover_danger_looked`) does not mark it. The count of cells that give something (`_harming`, which decides whether bodies are looked at) and the count of cells that are danger (`_danger`, for the look) are kept apart.
- **A row naming its own state renews it**: an element row whose `then` is the state the cell is in puts its seconds back to 0 (water on a wet cell keeps it wet), but moves nothing and costs no roll in a spread. No kind there is has such a row, so grass and cobwebs play as they did.
- **Who lit it** (state, hashed and snapshotted): beside the active cells (`_active`), each one's lighter, its actor and its spell's tag (`_active_actor`, `_active_tag`): set by the touch that moved it (or renewed it), handed on by a spread, kept by an `after` move, dropped when it comes to rest. A cell at rest costs nothing; a room at rest hashes as today. The cover's statuses and strikes are sent as the lighter's (`status_requested`'s caster; the strike's actor and tag); a cell lit by a prop (a fountain) or by nobody is NO_PLAYER's, as today.
- **`floor_touched` carries the spell's tag** (`floor_touched(caster, element, at, radius, tag)`; 0 for none: a prop's touch, a test's).

### What passes touches (core/projectiles, core/spells; the owner's answer 2)

- **Every live shot of an element touches the floor along its step each time it enters a new cell** (16 px, the cover's cell; Spells touches its step's way every 16 px, so a fast shot leaves no gap along its line; a cell it only clips at a corner may be passed by. The pass counts cells from the world's origin, the cover from its room's corner: a room laid off the 16 px grid touches at most a cell late). The projectile manager keeps, a shot, whether it trails (`set_trail`: Spells sets it on a shot whose hit has an element, and on a shot an infusion gives one) and the cell it last touched (`_trail_x`, `_trail_y`, state); a new pass after the step's others (`_pass_trail`, timed with the passes after the hits, `PROF_AFTER`) hands back the shots that entered a new cell (`trail_count`, `trail_slot`), in slot order. A falling shot (Skyfall) in the air touches nothing; it touches where it lands, as today. **The native kernel runs the pass** (`ShotKernel.trail_pass`), mirrored to the bit: `tests/core/test_native_kernel.gd` compares the two.
- **A beam's end, a dash and a swing touch as they go**: each step a beam touches the cell of its end; a dash the cells along its step's way (one every cell's side), a swing the cells along its tip's way.
- **One event a tick for all of it:** Spells gathers the touches of the tick (the shots', in slot order, then the carriers', in their steps' order) and sends `floor_passed(casters, tags, elements, at)` once, after its step (packed arrays, written in place: no allocation in the game). One entry an element of the spell (or of the infusion a shot took). Heard by the cover alone: the element locks, the secret rocks and their looks hear only `floor_touched` (where a spell ends, lands or pours), so a stray shot in flight does not open a lock (foundations.md, "More touches reach the other listeners").
- **The cover applies a passing touch to the one cell under it** (its room by `room_at`, no circle), in the order heard, after the tick's `floor_touched` touches.

### The look (gameplay/feel)

A `FLAT` kind is drawn by one sprite a room (`cover_flat.gdshader`, warmed by `ShaderWarmup.want`), its texture the room's grid (a texel a cell: the state shown and when it began to show, Feel's clock), on the floor marks' layer under the tufts. A drawn cell fills its 16 px and joins its drawn neighbours (while it grows or shrinks it is its own square, inset from every side, so a whole puddle changing at once steps cell by cell); on an edge toward an undrawn cell it has a 1 px edge of its material's shadow and a stepped corner, so a puddle is one shape. Its material's base, with its light as glints placed by a hash of the pixel (whole pixels, no blur, no fade). A state's look is data (`CoverState.flat_material`, `flat_motion`: still, grow, shrink or crackle, `flat_under`: what shows beneath while it grows or shrinks), its frames `animation_frames` at `animation_fps` from when the cell began to show it. The art is the palette's (Water, Ice, Arc, Bone): no sheet. It is its own layer (ART0, the 64-px art pipeline, reworks the grounds: nothing here touches them).

## Numbers

| What | Number | Why |
| --- | --- | --- |
| A puddle dries | 12 s, then 0.5 s drying | long enough to bring lightning or frost; gone before the next room |
| Soak from a puddle | 25 for 1 s, every 0.5 s | as wet grass |
| Live | 0.8 s, spreads 25 a second | runs through a Nova's puddle (about 6 cells across) in under 0.3 s |
| The zap | lightning, 4 damage, every 0.5 s | a bolt's is 8; Current (5 within 80 px) does the rest on the soaked |
| Spent | 1.5 s | a lake is live once a cast |
| Ice | chill 30 for 0.45 s every 0.5 s; 20 s | as the cobwebs: slows, never freezes |

## Tests

- `content/cover/floor/test_floor.gd`: the kind's data, and every row of the table through the real area (`cover_kit.gd`): water wets and renews, a wet cell dries, lightning runs through a lake and not past its edge, a lake is live once, frost freezes and fire thaws, fire on water is steam, ice chills without freezing, the zap strikes who stands in it and is its lighter's.
- `tests/core/test_cover_layout.gd`: the floor fills every open cell no other kind took (a door's and a spawn's too), never a wall's or a hole's, after the fill and the fields.
- `tests/gameplay/cover/test_cover_lit.gd`: who lit a cell, kept, handed on by a spread, dropped at rest; the status and the strike sent as theirs; a renewal; snapshotted and hashed (a restore plays on the same).
- `tests/core/test_floor_passed.gd`: a water bolt touches every cell along its straight way, none skipped (a fast shot's step is walked every 16 px); a shot of no element touches nothing; a Skyfall shot touches only where it lands; a portal's infusion makes a shot trail; a beam's end, a dash and a swing touch as they go; locks hear none of it.
- `tests/core/test_native_kernel.gd`: the trail pass, native against GDScript, byte for byte.
- **Build 1** (`tests/gameplay/cover/test_floor_builds.gd`): a crowd of dummies in a ring; a water Nova with Blast (`water · blast · nova · bolt`) soaks the floor round them; a lightning atom into the water; every dummy standing in it is struck, the soaked ones by Current; the kills are the caster's (`kill_landed` with the bolt's tag).
- **Build 4** (same file): a fountain's puddle; a frost bolt freezes it; a body on it is chilled and never frozen; a fire bolt over it thaws it to water; then lightning makes it live.
- The determinism, snapshot and card-rules tests, unchanged, play every card on the new floor (`test_content_determinism.gd`, `test_snapshot_game.gd`, `test_card_rules.gd`).
- **The budget test** (`tests/gameplay/cover/test_floor_budget.gd`): 2048 shots of an element in flight, the trail pass hands back at most one crossing a shot a step, allocates nothing, and the cover applies a tick of them within its budget (below); run in the build, the numbers printed.

## Measures

- **The cost of every shot touching** (measured 2026-11-25, docs/DECISIONS.md): the trail pass natively 8 to 10 us a step at 2048 shots (GDScript 357 us); the cover applying 2048 passing touches in one tick 1.3 to 1.8 ms (a burst; a stress tick's share is far less). `stress.gd` (web, 1000 shots): Cover 0.57 → 0.75 ms a tick, Spells 0.63 → 0.72. `play_frames.gd` ("1p far"): the tick 2.07 → 2.14 ms, the frame 7.11 → 7.22 ms. Budgets (`test_floor_budget.gd`): the native pass under 0.4 ms, a 2048-touch tick under 4 ms on a CI machine.
- **The cost of every room having cover:** a crypt biome's start (`test_cover_biome.gd` prints the work-out and draw of a room) and `tests/benchmark/cover_cost.gd`.

## The owner's answers (2026-11-25)

- **Ice and fire:** fire thaws ice (ice to water; fire on that water is then steam), as built. "Fire cannot cross it" because the fire is spent on the thaw; a shot that stops at ice would be new work.
- **Steam does nothing to bodies yet:** it is a look for now (hiding or scalding can be a later card).
