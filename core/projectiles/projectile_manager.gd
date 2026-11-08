extends Node2D
## The projectile manager: one autoload ("Projectiles") that simulates every
## spell projectile in bulk and draws them all in one batch. Projectiles are
## rows in packed arrays, never nodes, so thousands cost little (caps: 1,000 on
## the web, 6,000 on desktop; DEFAULT_CAP_WEB, DEFAULT_CAP_DESKTOP).
##
##     Projectiles.add_target(enemy, 10.0, Projectiles.LAYER_ENEMY, actor_id)
##     Projectiles.spawn(caster, origin, direction * 300.0, 1.5, 4.0, Projectiles.ACTOR_LAYERS)
##
## Targets are Node2Ds registered with a radius, a layer and their owner actor. A projectile
## hits the targets on the layers in its `hit_layers` mask and on both actor layers
## (ACTOR_LAYERS: everything hurts everything, actors G3c). A hit sends
## `Events.projectile_hit(caster, target, position, tag)`; the projectile then
## ends, unless it has `pierce` left, and `combat` turns the event into damage.
## The `tag` is the opaque int given to `spawn()`: the manager stores it and
## sends it back unread, so whoever spawned the shot (a spell) can look up its
## damage and effects from it. The manager knows nothing about damage, spells
## or gameplay.
##
## Hits are found with a spatial grid of the targets (cells of GRID_CELL
## pixels, each target in the cell of its centre). The path a projectile covered
## this step is checked as a segment, and the cells searched are those the
## segment touches, widened by the projectile's radius and the largest target
## radius registered. So fast shots and big targets (bosses) are both found, at
## any speed; the cost only grows with the length of the step. When a segment
## touches several targets, the one nearest the start of the path is hit first,
## and the event carries the point on the path closest to it. A piercing
## projectile hits every target its path passes through in one step (a fast shot
## through a crowd), nearest first, as its pierce allows. It hits a target once
## while it touches it, and again only after it has left it (owner, 2026-10-29:
## an orbit ring hits a target each time it comes round): it remembers the targets
## it is touching, as many as they are, and forgets one its path no longer touches.
##
## The hit work of one step is bounded (WORK_PER_STEP), so a burst of hits in a
## crowd is spread over a few steps instead of stalling one frame. When the
## budget runs out, the projectiles not yet tested still move, but are not
## hit-tested this step; the next step starts with them, so nobody is starved.
## No damage is lost to it (shot scale H2): a deferred shot keeps the start of
## the path it was not tested on (`_untested`), and its next test sweeps the
## whole path since then, so a fast shot skips no target, and a shot that ends
## (its life out, a wall, out of bounds) is tested first whatever the budget.
## The budget is fixed work, never measured time, so every machine defers the
## same shots (online-ready, rule T1). It is per `step` call, not per frame: if
## the engine runs several physics steps in one frame to catch up, each has its own.
##
## Drawing: a shot is built by the shot shaders on a pixel grid (staffs B6a; the glow look,
## 2026-10-27): a small white-hot core in the ramp of its first infusion's colour (`set_core`;
## its caster's ramp for a plain shot), a soft glow round it, and particles given off in the styles
## of all its cards (`set_look`), mixed at random. Its tail and particles are motes left in the
## world where the shot was (see SPARK_TAIL and SPARK_BIRTH_STRIDE; the owner, 2026-10-28, and
## tails as motes, 2026-11-05), so they bend with any path and cool where it ended (a dash's streaks
## are Feel's, a `stream` cue part). It is drawn about its hit size (`look_size`). Shots in
## the enemy ramp (`Actors.RAMP_ENEMY`, and a shot of no actor) are drawn by the same shaders
## (`ramp_look`), one layer above, so a dangerous shot never hides under a friendly one (staffs
## F9b: the old enemy shot's own texture is gone). One shader per kind of thing drawn, each in a
## batch of its own (the owner, 2026-10-29; core/README.md, "The shot shaders"): a flying shot
## (its core and the core's light; the tail is motes) by `shot_head.gdshader`, as small quads its
## vertex stage places (`head_mesh`, so the fragment stage stays small), a still shot by its card's
## own shader (`register_body`: a rune's, a wall's stones, a pool's puddle) or, when its card names
## none, the plain `shot_still.gdshader`.
##
## Casters (actors G3a, docs/milestones/M2-actors.md): a shot's caster is an actor id (0 to
## ACTORS - 1, `core/actors`) or NO_PLAYER (`Actors.NONE`, a shot of no actor). Nothing here
## asks whether a caster is a wizard or an enemy; the actor table answers four questions, read
## once when a shot is spawned and kept with it (a shot keeps the caster it was cast by):
## - **team** (`team_of`), only for aim: homing and `nearest_target`'s team skip pick other
##   teams, and a shield stops other teams' shots. Never for whether a hit lands: every shot and
##   beam hits both actor layers (ACTOR_LAYERS, actors G3c, owner 2026-10-28: "Everything should
##   be able to damage everything."), its own caster's body too: a shot spares only the body it
##   started on, until it has left it (`exclude`; owner, 2026-11-06: "a players own spells should
##   hurt the player"), a ray the same along its path, and a sweep spares the body it is cast from
##   (their `exclude`).
## - **ramp** (`ramp_of`): which batch draws it and in which colours (`look_color`, `tint_of`).
## - **budget** (`budget_of`): whose share of the pool the cap drops from first: one bucket per
##   seat and one that every actor no seat drives shares (`Actors.SHARED`).
## - **body**: targets name their owner actor (`add_target`, `set_target_owner`).
## The table is `actors` (tests set their own), else the `Actors` autoload; with none, every
## caster is no actor (no team, the enemy ramp, the shared budget).
##
## Walls: `set_walls(rects)` (or `add_wall_body(body)` for a room's static body) gives
## the solid parts of the room. They are rasterised into a grid of WALL_CELL
## pixel cells, so a wall check is a walk over the cells the step's path crosses
## (a few for a normal shot; at most MAX_WALL_VISITS for a huge step, and a path
## not fully walked then counts as a wall hit) and needs no physics query. A
## projectile whose path enters a solid cell ends there, even a piercing one,
## unless `set_bounce` gave it bounces (then it turns back). It is checked as a
## point, not a circle. The step is cut at the wall first, so a target in front of the wall is still hit by a fast
## shot, and one behind it is not. The wall walk is not charged to the work
## budget above (its length is capped instead). `wall_hits` counts these ends.
## `clip_to_walls(from, to)` shortens a segment to the first wall. `spawn` refuses
## (-1, counted in `wall_hits`) a shot that starts inside a wall, so it takes no
## pool slot and evicts nobody at the cap. Each wall end, and each hit on a
## target, also sends `Events.projectile_impact(caster, target, position,
## direction)` (target `null` for a wall), so a listener can show dust or a spray
## without asking the manager anything; it changes nothing here.
## A solid shot (`set_solid`, the Wall card, rules R4 F6) is a wall too while it lives: a
## segment across it that lies in the wall grid (shots end on it or bounce off it, a ghost passes)
## and a static body on WALL_LAYER that bodies cannot walk through. It hits along that segment.
##
## The global cap (`get_cap()`, set by platform: DEFAULT_CAP_WEB or
## DEFAULT_CAP_DESKTOP) degrades gracefully. When it is full, a new projectile
## is never refused: the oldest projectile of the budget that owns the most of them
## is dropped (in constant time: each budget's projectiles are a list in spawn
## order). The budgets are one per seat and one every actor no seat drives shares
## (`Actors.budget_of`), so nobody is starved, a seat that floods the screen only
## loses its own old shots, and a crowd of enemies only its own. `dropped` counts
## these. Spell limits (projectiles per cast, trigger depth) keep the cap from
## being reached often.
##
## Expiry: a shot that ends because its life ran out, or on a wall, sends
## `Events.projectile_expired(caster, position, tag)` once, after it is removed (so a
## handler may spawn at that spot). A shot that ends on a hit (`projectile_hit`), that
## leaves the bounds, or that the cap drops sends nothing: those did not run out.
##
## Motion: `MOTION_STRAIGHT` (default) flies on its velocity; `MOTION_STILL` (the
## rune) does not fly: its velocity is ignored and it waits for a target to enter its
## circle (homing creeps it toward one). It still ends by life or by a hit, as any shot does.
##
## Queries: `nearest_target(point, radius, layers, exclude)` and `targets_in(point,
## radius, layers, out)` use the same grid as hits, so chain, homing and area effects
## never loop over every enemy. A target counts when its hit circle overlaps the
## circle (point, radius). They see the target positions of the start of the latest
## step (a query after `add_target` and before the next step refreshes the grid
## first), so inside a hit handler they are exact for that step.
##
## Orbit: `spawn_orbit` starts a shot that circles its caster's body (or a shot or a point, see
## "Casters" below). The body's position comes from a per-actor anchor that `set_anchor(caster,
## position)` is given every physics step (by the body), so the manager never looks up a node. The shot's place is the anchor plus
## a turning offset, so it follows a walking wizard; its velocity is the tangent, for the
## drawing. An orbit shot ignores walls (it is held by its caster, who is never inside one)
## and ends quietly, with no event, when its owner's anchor is cleared (`clear_anchor`:
## the wizard left or fell). A step in which the anchor jumped far makes a long path, which
## the hit-work budget bounds as it does for any fast shot.
##
## Homing: `set_homing(slot, turn_rate, within)` makes a straight shot turn toward a
## target no further than `within` pixels from it (picked at random and kept while it can), at most `turn_rate` radians a
## second at its speed then (`set_homing_curve(slot, curve, within)`: on a curve of that radius),
## keeping its speed and its curve whatever its speed later; a still shot creeps toward it at SpellLimits.HOMING_DRIFT. The caller says how far (`CompiledSpell.homing_range`); there
## is no default here, so a new caller cannot quietly get another form's reach.
## The search runs on the grid and only every HOMING_PERIOD-th step of a shot (slots take
## turns, so the cost is spread); in between the shot keeps turning toward the point it
## found. It never homes on its shooter's own body, on a body of its shooter's team or on
## targets it just hit. The search
## is charged to the step's hit-work budget (1 per target examined); when the budget is
## spent the search waits for the shot's next turn. `homing_aim` does the same for a ray.
##
## An orbit shot is an ordinary piercing shot: `pierce` is how many hits it survives, and it
## hits a target again each time it comes round to it (after leaving it), however big the
## crowd; the orbit form (part 10) picks `pierce` for what it wants.
##
## The projectile kit (staffs B1): behaviours a card gives a flying shot, set with `set_*`
## right after `spawn` (the spell runtime does it from the compiled card numbers). A plain
## shot has none and is in no behaviour's list, so no behaviour pass looks at it (see "The step").
##   bounce (`set_bounce`)  reflects off the wall face it met, `times` times; `expired_on_wall`
##                          is true while a wall end's `projectile_expired` is sent
##   ghost                  ignores walls
##   spiral (`set_spiral`)  a sine wave of the given width round the straight path
##   return                 out for half its life, then back to its owner's anchor (an
##                          expiry there); it can hit again on the way back
##   linger                 hangs still for N seconds at half its life, without using it up
##   growth                 radius x factor per second, up to the room's size; `get_growth_of`
##   sticky                 the first hit keeps it on the target for N seconds, then it expires
##   shield                 stops N shots of other teams that touch it (`shot_blocked`)
##   deflect                turns every shot of another team that touches it and makes it its
##                          caster's, 1.7x faster (`deflect_shot`, `shot_deflected`); before a shield
## No shot spares its caster (owner, 2026-11-06): it spares the body it started on until it has
## left it (`exclude`, which the spell runtime gives every launch), then hits it as any other.
##
## Rays: `ray(...)` is an instant beam, `ray_curve(...)` a bent one, `ray_points(...)` one along
## any path of points (a live beam, which a homing one bends from target to target). They hold
## no row; see their comments. The spell runtime keeps a live beam on by casting one every step.
##
## Casters: every shot has a caster, its actor's anchor unless `set_caster_shot` (a payload's
## shot, cast by the shot whose trigger fired it) or `set_caster_point` says otherwise. An orbit
## circles its caster and a returning shot flies back to it; a caster shot that ends leaves the
## point where it was last. `move_shot` moves a shot by a card (a payload's dash, pull, recoil).
##
## Ends: `shot_ended(tag)`, a signal of the manager itself (not on the event bus), is sent
## once for every shot with a non-zero tag when it ends for any reason: a hit that spends it,
## its life, a wall, the bounds, the cap dropping it, a cleared anchor, `clear()`. It is sent
## after that shot's `projectile_hit` or `projectile_expired` handlers have run, so a handler
## can spawn children first. `remove_by_tag` is the exception: it is silent, because its
## caller is the one that revoked the tag. Every event of a shot (`projectile_hit`,
## `projectile_expired`, `shot_blocked`, `shot_deflected`, `wall_met`) names its slot as `shot`
## (-1 for a ray), so a listener can read per-shot state with `get_seq_of` and `get_velocity_of`
## while it is sent; a slot that just ended is not reused until the next spawn. `exclude(slot, node, seconds)`
## keeps one shot from hitting one target for a while.
##
## The step (shots stepped by behaviour, 2026-10-28): every shot moves on in one short common
## pass, then each behaviour's pass steps only the shots that have it, then one hit pass tests
## every shot in turn and sends the events, in the order they were always sent; see `step` and
## "Shot behaviours, stepped in passes" below, and core/README.md for how to add a behaviour.
## A hit handler sees every shot already moved for this step, also those whose turn in the hit
## pass has not come yet (the caster of an orbit or returning shot is the exception: it is read
## as it was before its turn). So a handler's change to another shot (a pull moving its carrier,
## a blink) takes effect from that shot's next step whatever the slot order, where it used to
## take effect in this step for a shot in a later slot.
##
## Nothing here allocates per frame: the arrays are sized when the cap is set,
## and the grid is reused. Coordinates are world coordinates (the manager sits
## at the origin). A handler of `projectile_hit` may spawn more projectiles;
## those start moving on the next step. Tests call `step()` directly.

const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const BatchesScript := preload("res://core/projectiles/batches.gd")
const NativeScript := preload("res://core/native/native.gd")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")

## A shot with a non-zero tag ended; see "Ends" above.
signal shot_ended(tag: int)
## Something met a wall and was not over (for `on wall`, which also fires on a shot's last wall
## through `projectile_expired` and `expired_on_wall`): a shot bounced off one, or a ray (sent
## with `hit`) turned at one or ended on one. `position` is just out of the wall and `heading`
## the way it goes on (at a ray's end, the way it came). `shot` is the shot's slot; a ray's is -1.
signal wall_met(caster: int, position: Vector2, heading: Vector2, tag: int, shot: int)

## Every caster number there is: the actor ids (see "Casters").
const ACTORS: int = ActorsScript.ACTORS
## The drop buckets (`_owned`): one per seat and the shared one (`Actors.budget_of`).
const BUDGETS: int = ActorsScript.SHARED + 1
## Motion modes of a shot (see the class doc).
const MOTION_STRAIGHT: int = 0
const MOTION_STILL: int = 1
## Only `spawn_orbit` makes this one.
const MOTION_ORBIT: int = 2
## `_caster_slot` values that are no slot: the casting actor's own body (its anchor; any actor, a
## player's or an enemy's), or a fixed point.
const CASTER_BODY: int = -1
const CASTER_POINT: int = -2
## Per-shot flags (`_flags`), set by the `set_*` calls below.
## Bits 1 and 2 were F_SELF and F_SELF_LIVE (a shot that may hit its caster once it has left it),
## gone 2026-11-06: every shot does, by `exclude`.
## Bit 4 was F_ALLY (a mend shot that hits teammates), gone in actors G3c: every shot does.
const F_GHOST: int = 8
const F_STUCK: int = 16
const F_RETURN: int = 32
const F_TURNED: int = 64
const F_WAVE: int = 128
## Passed over by the hit-work budget (WORK_PER_STEP): its path from `_untested` on is still to test.
const F_DEFERRED: int = 256

## Seconds one sine wave of a spiral shot takes.
const SPIRAL_PERIOD: float = 0.5

## Default global caps on live projectiles for each platform. The web cap was 1,000 (the PLAN
## budget) until the first web stress run: a physics step of 14 to 20 ms made the engine
## catch up with up to 8 steps per frame (docs/DECISIONS.md, 2026-10-23), so it went to 500,
## and desktop's was 3,000. With the native kernel (native/, 2026-11-02) the manager at 6,000
## shots costs less than its GDScript did at 3,000, so both doubled: what more shots cost now is
## the hits they make (the handlers in Combat, Spells and Feel are GDScript), which is what holds
## the web at 1,000 (docs/DECISIONS.md, 2026-11-02, "Projectile caps doubled"). The GDScript
## fallback is not sized for them; every build has the module.
const DEFAULT_CAP_WEB: int = 1000
const DEFAULT_CAP_DESKTOP: int = 6000
## How many recently hit targets a piercing projectile remembers; also the most
## hits one projectile can register in a single step.
## Remembered hits (see `_remember`) made room for at first; more are made when needed.
const HIT_MEMORY_START: int = 1024
## Moves under way (see `move_shot`) made room for at first; more are made when needed.
const MOVES_START: int = 64
## The most hit-test work one step does, in units: each target examined costs 1,
## each hit costs HIT_WORK. Once it is spent, the remaining projectiles are tested
## in a later step, losing no damage (see the class doc). A fixed number, never
## measured at run time (rule T1). Sized once (shot scale H2, 2026-11-05) for a
## full crowd at the desktop cap: it asks about 93,500 a step (some 200 hits) in
## the median step and more in a busy one, and at 150,000 no shot there waits more
## than one step (tests/core/test_hit_budget.gd; at 120,000 thousands do). Normal
## play uses a tiny part of it. No lost damage means the hits a step average what
## the shots make whatever the budget, so the budget only spreads a burst of them:
## the caps bound the cost.
const WORK_PER_STEP: int = 150000
## The parts of `step_profile` (shot scale H0): microseconds of `step()`'s passes in its order, the
## native kernel's own share of the hit pass, the hand-backs to GDScript (native `hits` calls) and
## the shots the hit-work budget left for a later step.
const PROF_REFRESH: int = 0
const PROF_COMMON: int = 1
const PROF_BEFORE: int = 2
const PROF_HITS: int = 3
const PROF_KERNEL: int = 4
const PROF_HANDBACKS: int = 5
const PROF_PAST_BUDGET: int = 6
const PROF_AFTER: int = 7
const PROF_PARTS: int = 8

## The most wall cells one shot walks in one step (see `_wall_hit`).
const MAX_WALL_VISITS: int = 64
## The work one hit counts for: the event, its handlers and the bookkeeping. A unit is one target
## examined by the native hit pass (about 0.13 us); a hit's listeners cost about 400 of them (about
## 50 us; shot scale H2, measured with H0's crowd, docs/DECISIONS.md 2026-11-05).
const HIT_WORK: int = 400
## The most a returning homing shot's way home bends off the line to its caster (radians): under
## a right angle, so it always closes in (`_pass_return`).
const RETURN_BEND: float = PI / 3.0
## A homing shot looks for a target one step in this many (slots take turns).
const HOMING_PERIOD: int = 4
## The most a speed curve multiplies a shot's speed by (`set_speed_curve`), however many cards.
const SPEED_START_MOST: float = 4.0
## The threat grid (see `threat`): built from this many live shots (below, one pass is cheaper),
## its cells at least THREAT_CELL pixels and at most THREAT_GRID_MAX a side, and a shot whose path
## covers more than THREAT_SPAN_MAX cells is tried by every query instead of filed.
const THREAT_GRID_FROM: int = 256
const THREAT_CELL: float = 128.0
const THREAT_GRID_MAX: int = 64
const THREAT_SPAN_MAX: int = 16
## The grid pays from about this many asks in a step (its build is about two passes'): fewer asks
## in this step and the last, and each is one pass.
const THREAT_GRID_ASKS: int = 3
## The straight pieces a bent beam (`ray_curve`) is walked as.
const RAY_SEGMENTS: int = 8
## The most points of its last step a swing's or beam's guard tests a shot at (`_guard_samples`).
const GUARD_PATH_SAMPLES: int = 16
## Rows `sweep`'s results hold at first; they grow when a sweep finds more.
const SWEEP_START: int = 32
## Points a ray's path holds at first; it grows when a path is longer (a homing beam bending on
## from target to target, a beam turning at many walls), so nothing limits a ray (owner,
## 2026-10-29: a beam hits every target its pierce gives, is as long as its card says, turns at
## every wall its bounces give, and nests as deep as its payloads go). Rays are not charged to
## the hit-work budget.
const RAY_PATH_START: int = 80
## Floats per projectile in the MultiMesh buffer: 8 transform, 4 colour, 4 custom data
## (the colour of the shot's core, read by the shot shaders).
const DRAW_STRIDE: int = 16
## The floats of a shot's row (its transform's free ones, `MODEL_MATRIX[2].x` and `.y` to a shader)
## that carry how far and how bright it lights the room (`_look_light_reach`,
## `_look_light_intensity`; Feel's `light.gdshader`). No shot shader reads them.
const LIGHT_REACH_FLOAT: int = 2
const LIGHT_INTENSITY_FLOAT: int = 6
## The bounds of a shot's light multipliers (`set_light`; a card's `look_light_intensity` and
## `look_light_reach`, which the validator keeps in the same): 0 lights nothing, a reach never shrinks
## below a quarter (so the light buffer's rows stay a few pixels), and neither passes 2.
const LIGHT_INTENSITY_MIN: float = 0.0
const LIGHT_REACH_MIN: float = 0.25
const LIGHT_MAX: float = 2.0
## The smallest a batch's MultiMesh buffer gets, in shots. A batch holds as many shots
## as the busiest recent frame needed, rounded up to a power of two (never above the
## cap), so a quiet batch uploads a few KB a frame rather than cap x 16 floats.
const MIN_BATCH: int = 64
## The draw batches by ramp: bolts, runes (still) and orbit shots in the four hat ramps, and the
## shots in the enemy ramp (`Actors.RAMP_ENEMY`, and a shot of no actor), flying ones and runes
## apart (each batch has one shader), drawn above the others. (Lightning's shots and the dashes had
## batches of their own while trails drew a jagged line and streaks; since tails are motes,
## 2026-11-05, every shot draws the same mesh, and a dash draws nothing.) Their nodes are made in
## BATCH_ORDER, so at one z the bolts draw before the runes and the orbits.
##
## After them come the card bodies' batches, as many as the cards ask for (`register_body`): a
## shot whose card names a shader of its own (`FormBase.look_shader`, in the card's folder: a
## wall's stones, a pool's puddle, a bolt's head) is drawn by it, in a pair of batches made with that
## shader and the mesh its shots are written as (MESH_QUAD, one quad a shot as a rune is, for a still
## carrier; MESH_HEAD, the shots' `head_mesh`, for one that flies or orbits): the hat ramps', then
## the enemy ramp's one layer up. Body `n` draws in BATCH_BODY_FIRST + 2 (n - 1), and + 1 for the
## enemy ramp. A body is a shader and a mesh: the same shader under both meshes is two bodies. A
## shot is drawn in its body's pair only while its motion is written as the body's mesh
## (`mesh_of_motion`); otherwise in its motion's own batch, plainly (`_batch_of`). A body's nodes
## keep the first batches' draw order (`_place_body_node`): a head body's after the bolts', a quad
## body's after the runes'. `batch_count()` says how many there are now; `batches_grown` tells when
## there are more.
const BATCH_BOLT: int = 0
const BATCH_STILL: int = 1
const BATCH_ORBIT: int = 2
const BATCH_ENEMY: int = 3
const BATCH_ENEMY_STILL: int = 4
const BATCH_BODY_FIRST: int = 5
## The meshes a batch draws (`batch_mesh`): the shots' head (`head_mesh`, placed by the shader's
## vertex stage), or one quad a shot (a rune's, a stone's, a card's still body).
const MESH_HEAD: int = 0
const MESH_QUAD: int = -1
## The most card bodies: a slot's body and its batch are a byte each, so 2 x MOST_BODIES + 5 batches
## at most. A shader past them is drawn by its shots' motion's plain batch (an error names it).
const MOST_BODIES: int = 125
## The order the first batches' nodes are made in (their draw order at one z); a body's pair is made
## after them, when it is numbered.
const BATCH_ORDER: Array[int] = [BATCH_BOLT, BATCH_STILL, BATCH_ORBIT, BATCH_ENEMY, BATCH_ENEMY_STILL]
## `_draw_out`: the totals of a drawing first (the particles asked for, 0 (was the trails' cost), the
## shots drawn, the enemy shots drawn, the tail births laid, the tail asked for), then each batch's
## instances written from DRAW_OUT_FIRST on, so the totals stay put as batches are added.
const DRAW_ASKED: int = 0
const DRAW_SHOTS: int = 2
const DRAW_ENEMY: int = 3
const DRAW_BIRTHS: int = 4
const DRAW_TAIL: int = 5
const DRAW_OUT_FIRST: int = 6
## The bodies a shot is drawn as (the shot shaders build them on a pixel grid; staffs B6a): a
## bolt's head (`shot_head.gdshader`; its tail is motes), a still shot (its card's shader, or the
## plain `shot_still.gdshader`), an orbit shot drawn whole with its tail bent round its circle
## (`shot_orbit.gdshader`, Entities' familiars; the manager's orbit shots are drawn as bolts are).
## Kind 0 is no body. A still shot is KIND_RUNE to the world (`impact_body`) whatever draws it: a
## card's own body is its batch's shader and mesh (`register_body`), not a kind.
const KIND_BOLT: int = 1
const KIND_RUNE: int = 2
const KIND_ORBIT: int = 3
## The kind travels in the alpha of the custom data as 1 - (kind + bend) / KIND_STEPS, so it
## has room for kinds 0 to KIND_MAX, and the bend code (below 0.5) rounds away when it is read.
const KIND_STEPS: float = 16.0
const KIND_MAX: int = 15
## The bend of a bolt or orbit shot: how its path curves (1 / the radius of the curve, signed:
## positive turns the way the screen's +x turns to +y), so `shot_orbit.gdshader` bends its tail
## along it. It travels as a code beside the kind: BEND_ZERO for a straight path, BEND_SPAN
## either side for the tightest curve (radius BEND_RADIUS; tighter ones draw as that). The
## shader holds the same numbers. A shot that turned more than BEND_CORNER radians in its last
## step (a bounce) met a corner, not a curve, and draws straight.
const BEND_ZERO: float = 0.225
const BEND_SPAN: float = 0.2
const BEND_RADIUS: float = 16.0
const BEND_CORNER: float = 0.5
## A rune traces itself onto the floor over its first RUNE_TRACE seconds; while it does, the code
## beside its kind is TRACE_FROM + TRACE_SPAN x how much is drawn (0 once it is whole).
const RUNE_TRACE: float = 0.25
const TRACE_FROM: float = 0.02
const TRACE_SPAN: float = 0.42
## The look kinds a card can give a shot (`look_layer` on infusions and modifiers; see
## `set_look`). The body stays plain; each kind is a style of particle the shot gives off along
## its path (births for Feel's motes, `_give_off_sparks`), and a shot shows every kind its cards
## bring, mixed at random: the look is a set, one bit per kind. WEAVE and STREAKS also change the
## head (a weave, a longer core; `shot_head.gdshader`). A new kind of effect is a new number here
## (up to LOOK_MAX_KINDS), its rate in SPARK_RATES and a branch in `particle`
## (`shot_particle.gdshaderinc`, for runes and familiars); a new card with an old kind needs none.
const LOOK_NONE: int = 0
const LOOK_EMBERS: int = 1
const LOOK_FLECKS: int = 2
const LOOK_GUSTS: int = 3
const LOOK_PULL: int = 4
const LOOK_SPARKS: int = 5
const LOOK_MOTES: int = 6
const LOOK_GLINTS: int = 7
const LOOK_STREAKS: int = 8
const LOOK_BURST: int = 9
const LOOK_ORBITERS: int = 10
const LOOK_WEAVE: int = 11
const LOOK_GLITTER: int = 12
const LOOK_HOPS: int = 13
const LOOK_WAKE: int = 14
const LOOK_WEIGHT: int = 15
const LOOK_RIPPLE: int = 16
const LOOK_CURL: int = 17
const LOOK_ZIG: int = 18
const LOOK_DOUBLE: int = 19
const LOOK_CONVERGE: int = 20
const LOOK_DRIFT: int = 21
## Kind 22 is free (Feel's poof flag until the poof became a flash kind of its own: flash kinds
## F2), 23 the enemy ramp and 24 the exact colour: not kinds.
const LOOK_COUNT: int = 22
## The most kinds the instance data has room for: three bytes of bits (`_look_color`).
const LOOK_MAX_KINDS: int = 24
## A flag in the look, not a kind (kind 23 of the shader): drawn in the enemy ramp (Blight
## ochre, docs/STYLE.md) wherever a hat colour would show (staffs F2). Set by `ramp_look` for
## any ramp that is not a hat ramp (0-3): the shader's ramp field is two bits and this flag;
## kind 24 is Feel's EXACT.
const LOOK_ENEMY_RAMP: int = 1 << 22
## A shot is drawn in a quad of LOOK_GRID x zoom screen pixels across: a rune's is
## square round its centre, a bolt's or orbit shot's LOOK_LENGTH x zoom long with the shot
## LOOK_GRID / 2 x zoom from its front, for its tail (48 px at zoom 1), the particles it gives off
## and its glow. Its core is about 3 x zoom pixels across, and every line stays one pixel. The
## zoom is this many per pixel of hit radius, rounded and at least one (at most LOOK_ZOOM_MAX),
## so a bolt (radius 5) has zoom 1, a bigger one 2 and a rune 4: a shot is drawn smaller than
## its hit size and hits wider than it looks.
const LOOK_GRID: int = 24
const LOOK_LENGTH: int = 72
const LOOK_CELL_PER_RADIUS: float = 0.25
const LOOK_ZOOM_MAX: int = 15
## A bolt-like shot of hit radius below this is a speck (an atom): its core is one pixel, no
## cross. It travels as zoom 0 in the look (`look_core_zoom`); every other shape of it, and every
## shader but the head's core, reads zoom 1 (`look_from_color` never goes below 1).
const SPECK_RADIUS: float = 2.0
## The spark pool (staffs B6b): the sparks, embers and the rest that all the shots give off come
## from one pool with a global count, `tailless_particle_cap` (a visual budget; never a build
## rule). A shot with `n` emitting kinds asks for `particles_of(look)` of them (4 + 2n, at most 12).
## Under the count everything is given off; over it the births thin by group (GROUPS): every
## caster's staff gets a fair share, and the shots of one staff thin alike within it.
## The pool's count (S5: the tails' budget went to the motes when the tails went): the births a
## frame thin only past this many particles asked, so a fight of thousands of shots keeps more of
## the look of a fight of tens. Set from the shot benchmark (`tests/benchmark/shot_gpu.gd`; DECISIONS, 2026-11-04, "Do shots need
## tails?"); the "Tailless motes" dev slider sets it (`set_tailless_pool`).
const TAILLESS_PARTICLE_CAP: int = 2048
## A teleport: a shot that moves more than this many pixels between two frames lays no tail across
## the gap (`_lay_tail`).
const TAIL_JUMP: float = 96.0
## A shot's flags in its instance (the shader's HF_*): its shot is alive (the core is drawn), an
## orbit shot.
const HEAD_LIVE: int = 1
const HEAD_ORBIT: int = 2
## The quad kinds of a shot's mesh (`head_mesh`; the shader's Q_*): the core's light, the core.
const HEAD_Q_LIGHT: int = 0
const HEAD_Q_CORE: int = 1
## Vertices a quad of a shot's mesh has (one triangle round its box; see `head_mesh`).
const HEAD_QUAD_VERTICES: int = 3
## The quads of a shot's mesh in draw order: the light first (void's dark heart dims what is under
## it), then the core.
const HEAD_QUAD_KINDS: Array[int] = [HEAD_Q_LIGHT, HEAD_Q_CORE]
## A shot's particles are motes (spell spectacle P1d, and since S3 the only way they are drawn;
## docs/milestones/spell-spectacle-2.md): a shot's mesh has no particle slots, and the
## particles a shot gives off are handed out as births (`spark_births`) for Feel's motes
## to throw, while something takes them (`spark_motes`). A birth is SPARK_BIRTH_STRIDE floats:
## where (x, y), the way back along the shot (x, y), the look kind it is of (LOOK_*; 0 a plain
## shot's twinkle), the caster's ramp, the shot's look, its core colour (r, g, b) and its tag (so
## the motes can take its spell's cards' kinds; spell-spectacle-2.md, S2).
## The pool's share thins them, so the births a frame stay about as many as the pool's particles
## live (TAILLESS_PARTICLE_CAP over their life), whatever the shot count. Measured (DECISIONS, 2026-11-04,
## "Trail particles as motes"): cheaper than the shader's at 60, 400 and 3,000 shots.
const SPARK_BIRTH_STRIDE: int = 12
## Where a birth's numbers are: where (x, y), the way back (x, y), the look kind, the caster's
## ramp, the shot's look, the core colour (r, g, b from SPARK_CORE), and the shot's tag in two
## floats (SPARK_TAG its low SPARK_TAG_BITS bits, SPARK_TAG + 1 the rest: a float holds every
## integer only up to 2^24, and a spell's tag is above it; `spark_tag` reads it back).
const SPARK_X: int = 0
const SPARK_Y: int = 1
const SPARK_BACK_X: int = 2
const SPARK_BACK_Y: int = 3
const SPARK_KIND: int = 4
const SPARK_RAMP: int = 5
const SPARK_LOOK: int = 6
const SPARK_CORE: int = 7
const SPARK_TAG: int = 10
const SPARK_TAG_BITS: int = 12
## The births a frame holds at most (more moments than this a frame are a stall: they are dropped).
const SPARK_BIRTHS_MAX: int = 1024
## How often each look kind gives off a particle at a moment (by look kind; 0 the plain shot's
## twinkle, 11 the weave none).
const SPARK_RATES: PackedFloat32Array = [0.18, 0.45, 0.32, 0.4, 0.55, 0.45, 0.25, 0.25, 0.25, 0.25, 0.25, 0.0, 0.25, 1.0, 0.7, 0.4, 1.0, 1.0, 0.5, 0.5, 1.0, 0.4]
## A dash's speed streak: a birth of this look kind is one of the motes' dash path kinds
## (`MoteKind.dash_path`). The manager lays none: a dash's streaks are a `stream` part of its cue,
## which Feel gives off in this format (gameplay/feel/streams.gd; spell-spectacle-2.md, S5).
const SPARK_STREAK: int = -1
## Tails as motes (spell-spectacle-2.md, S5 step 4; the owner, 2026-11-05: "if only the motes could
## look more like a tail"): with the tails off, every flying shot lays its tail as births of the
## look kinds SPARK_TAIL on (the motes' kinds that are a shot's tail, `MoteKind.tail`), by distance,
## not by moment: one every TAIL_SPACING pixels of the path it was drawn along since the last
## frame on average, each gap a random 0.5 to 1.5 of the spacing, from a phase of its own
## (`_lay_tail`), so a fast shot's tail is as whole as a slow one's and a held stream of shots
## never lines its motes up. TAIL_BIRTHS a frame at most with the default births' pool (the
## "Tailless motes" slider scales it, `tail_births_cap`): past that the tails are shared out by
## group (GROUPS: a caster's staff), and the spacing of each group's tails grows by its ask over its
## share (`_group_spacing`, planned from the last frame's ask), so a fight of thousands of shots
## keeps a thinner tail on every shot of a crowded staff, never a whole tail on some of them.
## TAIL_PLAYER_SHARE of an infused shot's tail is its caster's colours, as the tail shader's
## quarter was. Its numbers: a birth's (SPARK_BIRTH_STRIDE), the way back along the shot.
##
## **Each shot its own tail kind** (the owner, 2026-11-05: "keep all three and make the shots randomly
## pick one"): a shot's births are SPARK_TAIL + one of TAIL_KINDS codes (60, 61, 62), picked once from
## its sequence (`tail_code`: the same die every frame, and in the native kernel), and the mote pool
## lays each code in its own tail kind (`MoteKind.tail`, in id order: A, B, C), so every tail is all
## of a piece and the shots of a fight vary.
const SPARK_TAIL: int = 60
const TAIL_KINDS: int = 3
const TAIL_SPACING: float = 2.0
const TAIL_BIRTHS: int = 256
const TAIL_PLAYER_SHARE: float = 0.25
## **The births are shared by staff** (the owner, 2026-11-05: a Storm that keeps splitting took
## every tail, so a Fireball cast through it had none, while the Storm's own tails were too dense
## to tell apart): every shot is in a group, its caster's staff (`group_of`: the spell tag's staff,
## the caster's first for a shot of no spell; a payload's shots are its staff's too), and the
## frame's tail births (`tail_births_cap`) and particles (`tailless_particle_cap`) are shared out
## fairly among the groups that ask (`fair_level`): a group that asks for less than an even share
## gets all it asks for, and the rest share what is left alike. So a lone Fireball keeps its whole
## tail and its embers beside a Storm of thousands of shots, which thins as before, and two Storms
## thin alike. A group is a staff, not a cast: a held Storm's many casts are one group.
## The tails are shared out of TAIL_FRESH less than `tail_births_cap`, so a cast new since the last
## frame (whose ask is not known yet) always finds room for its first frame's tail; the thinned
## groups stop at what they were given together (`tail_thin_most`; past it their tails are cut, in
## slot order), and the groups given their whole tails stop only at `tail_births_cap`. So a frame
## never lays more than the most, and a Fireball drawn after a Storm that laid past its share is
## not cut for it.
const TAIL_FRESH: float = 0.125
const GROUP_STAFFS: int = 4
const GROUPS: int = ACTORS * GROUP_STAFFS
## Particle moments a second.
const SPARK_MOMENTS: float = 60.0
## An orbit shot spirals out from its caster to its circle over this many seconds.
const ORBIT_GROW: float = 0.25
## Particles a shot keeps in the air at most (the same number as `shot_particle.gdshaderinc`'s).
const PARTICLES_PER_SHOT_MAX: int = 12
## The look bits of the kinds that give off particles: all of them but the weave.
const EMITTING_MASK: int = ((1 << (LOOK_COUNT - 1)) - 1) & ~(1 << (LOOK_WEAVE - 1))
## Build the shots from their looks (see "Drawing" above): flying shots' heads, runes.
const HEAD_SHADER: Shader = preload("res://core/projectiles/shot_head.gdshader")
const STILL_SHADER: Shader = preload("res://core/projectiles/shot_still.gdshader")
## Draw order of the shots: above the room and the wizards. The autoload is drawn
## before the current scene, so at z_index 0 the room's floor hid every shot.
const DRAW_Z: int = 50
## A shot is drawn this many times wider than its hit circle (the art has empty
## margins and a pixel-art bolt is small on a 640x360 view).
const DRAW_SCALE: float = 3.0
## How much of the caster's ramp colour tints the art (the rest stays white): a full
## multiply turned the orange bolt of a blue wizard nearly black.
const TINT_STRENGTH: float = 0.45
## Wall grid cell size in pixels. Walls are rounded out to whole cells, so they are
## exact when their edges are multiples of it (room tiles are 32 px).
const WALL_CELL: float = 8.0
## A room wall's mark in the wall grid; the bits below it count the solid shots on a cell.
const ROOM_CELL: int = 128
## The physics layer of the room's walls (the actors' `LAYER_WALLS`): a solid shot's body is on it.
const WALL_LAYER: int = 1
## Spatial grid cell size in pixels.
const GRID_CELL: float = 64.0
## Projectiles that leave the bounds by more than this are removed.
const BOUNDS_MARGIN: float = 128.0
## Target layers (bit mask): the hurtboxes of wizards' and enemies' bodies, kept apart for now
## (actors G3a); every spell hits both (ACTOR_LAYERS). They say nothing about aim: teams do.
const LAYER_ENEMY: int = 1
const LAYER_PLAYER: int = 2
## What every shot and beam hits, added to the layers it was given (actors G3c).
const ACTOR_LAYERS: int = LAYER_ENEMY | LAYER_PLAYER
## The base colour of each ramp (docs/STYLE.md), by `Actors.ramp_of`: the four hat colours, then
## the enemy ramp (Blight ochre, `Actors.RAMP_ENEMY`). The one home of these colours.
const RAMP_COLORS: Array[Color] = [
	Color("#3b73c9"), Color("#d9477a"), Color("#3f8f4f"), Color("#8a4fc4"), Color("#a68a2a"),
]
## The light shade of each ramp (docs/STYLE.md), in the same order: a wizard's reticle, staff gem
## and rings (`StaffLook`), Feel's flashes in a player's colours.
const RAMP_LIGHT_COLORS: Array[Color] = [
	Color("#7fc0f0"), Color("#f59ab8"), Color("#8fd46a"), Color("#c99af0"), Color("#e3cf6b"),
]

## There are more draw batches now (`register_body` numbered a card body): `count` in all. Whoever
## mirrors the batches (Feel's spell light) adds theirs for the new ones.
signal batches_grown(count: int)

## Not state: services, caches and scratch, set up again (core/sim/README.md); the native switch,
## which gives the same game either way (native/README.md), and the hit test's scratch, which only
## the native pass sizes ahead (both found by N2b's platform runs); `_target_id`, each target's
## node by instance id, a lookup from the node (equality only: a target's identity is its key, N5);
## a ray's scratch per nesting level (`_ray_level`) and a sweep's results (`sweep`), refilled by
## each, which a run's start must keep whole: they grow together, by the size of the first (found by
## N3c's stress runs).
const DERIVED: Array[StringName] = [&"events", &"actors", &"_auto_actors", &"_passes", &"_targets", &"_spare_bodies", &"_ray_nodes", &"_ray_along", &"_ray_points", &"_ray_heads", &"_ray_walks", &"_ray_turns", &"sweep_nodes", &"sweep_points", &"sweep_heads", &"_kernel", &"native", &"_target_mark", &"_target_entry", &"_cand_target", &"_cand_along", &"_cand_point", &"_cand_found", &"_target_id", &"_head_mesh", &"step_profile", &"profile_clock", &"native_threads"]
## State as who they point at: other bodies, never entered (core/sim/README.md).
const REFS: Array[StringName] = [&"_stuck_to"]
## Not state: what only the drawing reads and writes (core/sim/README.md).
const VIEW: Array[StringName] = [&"texture", &"_look_light_intensity", &"_look_light_reach", &"_body_shaders", &"_body_meshes", &"_batch_total", &"_nodes", &"_buffers", &"_mirrors", &"_draw_node", &"_still_node", &"_orbit_node", &"_enemy_node", &"_enemy_still_node", &"_rooms", &"_batch_counts", &"_draw_out", &"drawn", &"particle_demand", &"particle_share", &"drawn_enemy", &"_drawn_seq", &"_drawn_radius", &"_drawn_look", &"_drawn_batch", &"_drawn_color", &"_drawn_size", &"_drawn_particles", &"spark_births", &"spark_birth_count", &"tail_births_on", &"tail_thin_most", &"tail_spacing", &"tail_births", &"tail_demand", &"_tail_from", &"_tail_carry", &"_tail_n", &"_tail_wanted", &"_tail_thin", &"_end_births", &"_end_count", &"_end_wanted", &"_spark_moment", &"_spark_rng", &"_by_group", &"_group_start", &"_group_end", &"_group_tail", &"_group_ask", &"_group_spacing", &"_group_share", &"_group_want", &"_group_frame", &"_group_seen", &"_group_sort", &"_draw_frame", &"tailless_particle_cap", &"tail_births_cap", &"spark_motes"]
## The run's rules a new run keeps (`begin_run`): the cap and the hit-test work a step may do, set
## from the session's rules just before (`take_rules`, online-ready N11). The tailless motes' pool,
## its tail births and whether something takes the births are this machine's look (VIEW): they
## only write what is drawn.
const RUN_KEEPS: Array[StringName] = [&"_cap", &"work_per_step"]

## The art of the hat-ramp batches. Since staffs B6a the shader builds every shot (runes
## and orbit shots too) and never reads it; only the sprite path of Feel's lone flashes does.
var texture: Texture2D = null:
	set(value):
		texture = value
		_apply_textures()
var events: EventsScript = null
## How many projectiles were dropped because the cap was full, since start.
var dropped: int = 0
## The slot of the shot whose event is being sent, else -1: inside the manager only (a shot that
## just ended still answers its own event's handlers). Listeners get it as the event's `shot`.
var _event_slot: int = -1
## The form of the shot whose `projectile_impact` is being sent: its card's id (`set_form`; `&"bolt"`,
## `&"rune"` or `&"orbit"` by its body for a shot no card set), `&"beam"` or a strike's card, and
## the carrier's while `block_shot` sends `shot_blocked` (a swing's: a parry) (any time outside
## these: `&""`). For looks only.
var impact_form: StringName = &""
## The body (KIND_*) of the shot whose `projectile_impact` or `projectile_expired` is being sent, 0
## for none (a ray, a strike) and outside them: a still body goes off in its own way. For looks only.
var impact_body: int = 0
## The core colour and the look (`set_core`, `set_look`) of the shot whose `projectile_impact`
## is being sent, so its flare can take the shot's colours and card effects (white and 0 for a
## beam and outside an impact). For looks only.
var impact_core: Color = Color.WHITE
var impact_look: int = 0
## The tag of that shot (0 for a beam, a strike and outside an impact), so its motes and marks can
## be its spell's cards' (spell-spectacle-2.md, S2). For looks only.
var impact_tag: int = 0
## The way the shot was flying, while a `projectile_expired` is sent (with `impact_form`,
## `impact_core` and `impact_look`, so Feel can show where its life ran out).
var impact_heading: Vector2 = Vector2.ZERO
## How many projectiles ended on a wall, since start.
var wall_hits: int = 0
## Projectiles written into the batch by the last update_draw().
var drawn: int = 0
## What the drawn shots asked of the pool in the last update_draw(): particles.
var particle_demand: int = 0
## The share of the particles the pool gave off in the last update_draw() (1.0 is all of them).
var particle_share: float = 1.0
## Shots in the enemy ramp written into their batch by the last update_draw().
var drawn_enemy: int = 0
## The actor table (see "Casters"); tests set their own. Null uses the `Actors` autoload.
var actors: ActorsScript = null
var _auto_actors: ActorsScript = null

var _cap: int = 0
var _count: int = 0
## Seconds of simulation stepped so far; shots animate from it (not from the
## engine's clock), so a hand-stepped run draws the same frames every time.
var sim_time: float = 0.0
## One past the highest slot in use.
var _high: int = 0
var _next_seq: int = 0
var _bounds: Rect2 = Rect2(-1024.0, -1024.0, 2048.0, 2048.0)

# One row per slot.
var _pos: PackedVector2Array = PackedVector2Array()
var _prev: PackedVector2Array = PackedVector2Array()
## Where the path of a shot the hit-work budget passed over starts (read only with F_DEFERRED).
var _untested: PackedVector2Array = PackedVector2Array()
var _vel: PackedVector2Array = PackedVector2Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _radius: PackedFloat32Array = PackedFloat32Array()
## The caster's actor id, and its team, ramp and budget when the shot was spawned.
var _actor: PackedInt32Array = PackedInt32Array()
var _team: PackedInt32Array = PackedInt32Array()
var _ramp: PackedInt32Array = PackedInt32Array()
var _budget: PackedByteArray = PackedByteArray()
var _layers: PackedInt32Array = PackedInt32Array()
var _pierce: PackedInt32Array = PackedInt32Array()
## The opaque value given to spawn(), sent with every hit.
var _tag: PackedInt64Array = PackedInt64Array()
## MOTION_STRAIGHT or MOTION_STILL per slot.
var _motion: PackedByteArray = PackedByteArray()
## The body a card asked for per slot (`set_form`: a shader `register_body`
## numbered, drawn when the shot is still; 0 for its motion's own), and the id of the card it is
## (`&""` for none), for its looks.
var _body: PackedByteArray = PackedByteArray()
## How bright and how far each shot lights the room, times the shot light's own (its card's
## `look_light_intensity` and `look_light_reach`, `set_looks`, `set_light`; 1 for a plain shot):
## written into its row's free floats (`MODEL_MATRIX[2].y` and `.x`, LIGHT_INTENSITY_FLOAT and
## LIGHT_REACH_FLOAT), which Feel's spell light reads (`light.gdshader`). Drawn only (VIEW).
var _look_light_intensity: PackedFloat32Array = PackedFloat32Array()
var _look_light_reach: PackedFloat32Array = PackedFloat32Array()
var _form_id: Array[StringName] = []
## Orbit shots: radius from the anchor, current angle and angular speed (rad/s).
var _orbit_radius: PackedFloat32Array = PackedFloat32Array()
var _orbit_angle: PackedFloat32Array = PackedFloat32Array()
var _orbit_speed: PackedFloat32Array = PackedFloat32Array()
## Where an orbit shot's caster was at its last step (INF before its first), for `_drawn_at`.
var _orbit_centre: PackedVector2Array = PackedVector2Array()
## Homing: how far it turns in radians a pixel flown (the same curve at any speed; 0 for none)
## and the point last found (INF for none).
var _turn: PackedFloat32Array = PackedFloat32Array()
var _home_at: PackedVector2Array = PackedVector2Array()
var _home_range: PackedFloat32Array = PackedFloat32Array()
## The key (`_target_key`) of the target each homing shot keeps, 0 for none.
var _home_target: PackedInt64Array = PackedInt64Array()
## Spawn order, so "oldest" is the lowest.
var _seq: PackedInt64Array = PackedInt64Array()
## What `update_draw` worked out for the shot in each slot (its batch, look colour, quad size and
## particles), kept with the spawn (`_seq`), radius and look it was worked out for: those change
## seldom (a new shot, growth, `set_look`), and working them out for every shot every frame was
## a dozen calls each (performance pass, 2026-10-28).
var _drawn_seq: PackedInt64Array = PackedInt64Array()
var _drawn_radius: PackedFloat32Array = PackedFloat32Array()
var _drawn_look: PackedInt32Array = PackedInt32Array()
var _drawn_batch: PackedByteArray = PackedByteArray()
var _drawn_color: PackedColorArray = PackedColorArray()
var _drawn_size: PackedFloat32Array = PackedFloat32Array()
var _drawn_particles: PackedInt32Array = PackedInt32Array()
# Behaviours of the projectile kit (B1), all reset in `_spawn_row`; a plain shot has flags 0.
var _flags: PackedInt32Array = PackedInt32Array()
var _bounce: PackedInt32Array = PackedInt32Array()
var _shield: PackedInt32Array = PackedInt32Array()
## 1 for a shot that deflects the shots of other teams it touches (`set_deflect`).
var _deflect: PackedByteArray = PackedByteArray()
var _span: PackedFloat32Array = PackedFloat32Array()
var _radius0: PackedFloat32Array = PackedFloat32Array()
var _growth: PackedFloat32Array = PackedFloat32Array()
## Speed over life (`set_speed_curve`): the factors on its speed when it leaves and as its life runs
## out, the power of the ease between them, and the speed they are factors of.
var _curve_from: PackedFloat32Array = PackedFloat32Array()
var _curve_to: PackedFloat32Array = PackedFloat32Array()
var _curve_ease: PackedFloat32Array = PackedFloat32Array()
var _curve_speed: PackedFloat32Array = PackedFloat32Array()
var _wave: PackedFloat32Array = PackedFloat32Array()
var _wave_age: PackedFloat32Array = PackedFloat32Array()
var _base: PackedVector2Array = PackedVector2Array()
var _linger: PackedFloat32Array = PackedFloat32Array()
var _hold: PackedFloat32Array = PackedFloat32Array()
## Seconds a shot is held by a local stop (`freeze_shot`); 0 for a shot that flies on.
var _freeze: PackedFloat32Array = PackedFloat32Array()
var _stick: PackedFloat32Array = PackedFloat32Array()
var _stuck_to: Array = []
var _stuck_off: PackedVector2Array = PackedVector2Array()
var _speed: PackedFloat32Array = PackedFloat32Array()
## The shot's caster, which an orbit circles and a returning shot flies back to: its actor's
## anchor (CASTER_BODY), a fixed point in `_caster_at` (CASTER_POINT), or the shot in that slot
## while it is the one with `_caster_seq` (a payload's carrier); once that shot is gone, the
## point where it was last seen.
var _caster_slot: PackedInt32Array = PackedInt32Array()
var _caster_seq: PackedInt64Array = PackedInt64Array()
var _caster_at: PackedVector2Array = PackedVector2Array()
## The moves cards asked for (`move_shot`) that are still under way: a list per slot
## (`_move_head`, -1 for none) through one growing pool, as the hit memory. Each has its seconds
## left, the velocity it adds meanwhile, a homing move's turn rate, reach and the target it keeps
## (0 for none), and the link (`_move_free` heads the free entries). The moves of a shot add up.
var _move_head: PackedInt32Array = PackedInt32Array()
var _move_left: PackedFloat32Array = PackedFloat32Array()
var _move_vel: PackedVector2Array = PackedVector2Array()
var _move_turn: PackedFloat32Array = PackedFloat32Array()
var _move_range: PackedFloat32Array = PackedFloat32Array()
var _move_home: PackedInt64Array = PackedInt64Array()
var _move_next: PackedInt32Array = PackedInt32Array()
var _move_free: int = -1
## Shot behaviours (see "Shot behaviours, stepped in passes"): each behaviour's list of the shots
## that have it (BEHAVIOURS lists of up to `_cap` slots, one after the other), how many each has,
## where each shot is in each list, and per shot a bit per behaviour it has.
var _members: PackedInt32Array = PackedInt32Array()
var _member_count: PackedInt32Array = PackedInt32Array()
var _member_at: PackedInt32Array = PackedInt32Array()
var _kinds: PackedInt32Array = PackedInt32Array()
## Each behaviour's pass, by B_* (from BEHAVIOUR_PASSES).
var _passes: Array[Callable] = []
## What each shot is doing in this step (S_*), and for a waiting one what it was doing and from
## which pass it goes on (see `_wait`).
var _state: PackedByteArray = PackedByteArray()
var _wait_state: PackedByteArray = PackedByteArray()
var _wait_from: PackedByteArray = PackedByteArray()
## The one-shot list `_catch_up` hands the passes, and `_pass_shield`'s list in slot order.
var _one: PackedInt32Array = PackedInt32Array([0])
var _shield_order: PackedInt32Array = PackedInt32Array()
## True while `_catch_up` runs a waiting shot's passes (they do not make it wait again).
var _catching_up: bool = false
## The live shots on the target grid's cells, made once a step the first time a shield needs
## them (see `_shield_block`): the first shot in each cell (-1 for none), the next in its chain
## (slot order), and the most any of them reaches from where it is (its radius and its step's
## path).
var _shot_head: PackedInt32Array = PackedInt32Array()
var _shot_next: PackedInt32Array = PackedInt32Array()
var _shot_reach: float = 0.0
var _scan_step: int = -1
## True while a `projectile_expired` is sent for a shot that ended on a wall (the `on wall`
## trigger reads it); false for every other end.
var expired_on_wall: bool = false
## The targets each shot is touching and has hit, so it hits them once until it leaves them: a
## list per slot (`_mem_head`, -1 for none) through one growing pool (`_mem_id` the target's
## key, `_target_key`, `_mem_seen` the step its path last touched it, `_mem_next` the link; `_mem_free`
## heads the free entries). `_mem_step` counts the steps.
var _mem_head: PackedInt32Array = PackedInt32Array()
var _mem_id: PackedInt64Array = PackedInt64Array()
## The target's index when it was hit: a hint, checked against its key (`_mark_memory`).
var _mem_target: PackedInt32Array = PackedInt32Array()
var _mem_seen: PackedInt32Array = PackedInt32Array()
var _mem_next: PackedInt32Array = PackedInt32Array()
var _mem_free: int = -1
var _mem_step: int = 0
## Per target, set by `_mark_memory`: the stamp of the last marking that found it remembered, and
## its memory entry then.
var _target_mark: PackedInt32Array = PackedInt32Array()
var _target_entry: PackedInt32Array = PackedInt32Array()
var _mark_stamp: int = 0
## The hit test's candidates, nearest first (`_keep_candidate`).
var _cand_target: PackedInt32Array = PackedInt32Array()
var _cand_along: PackedFloat32Array = PackedFloat32Array()
var _cand_point: PackedVector2Array = PackedVector2Array()
## Per-budget list of live slots in spawn order (oldest at the head), indexed
## like _owned: head and tail slot per budget (-1 for none), and the links.
var _own_head: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1, -1])
var _own_tail: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1, -1])
var _own_prev: PackedInt32Array = PackedInt32Array()
var _own_next: PackedInt32Array = PackedInt32Array()
var _alive: PackedByteArray = PackedByteArray()
## Stack of free slots.
var _free_slots: PackedInt32Array = PackedInt32Array()
var _free_count: int = 0
## Live projectiles per budget (`Actors.budget_of` of the caster when the shot was spawned):
## 0-3 the seats', SHARED every other actor's and a shot of no actor's.
var _owned: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])

# Targets, one row each.
var _targets: Array = []
var _target_radius: PackedFloat32Array = PackedFloat32Array()
var _target_layer: PackedInt32Array = PackedInt32Array()
var _target_pos: PackedVector2Array = PackedVector2Array()
## Where each target's hit circle sits, relative to its node (the body, not the feet).
var _target_offset: PackedVector2Array = PackedVector2Array()
var _target_id: PackedInt64Array = PackedInt64Array()
## Each target's identity (online-ready N5): its actor's key (`Actors.key_of`, handed over by Combat),
## else one the manager gives it (`_minted_keys`, below 0). What a shot keeps of a target (its homing
## target, what it hit, the body it spares) is this key, the same on every machine; never 0.
var _target_key: PackedInt64Array = PackedInt64Array()
## Keys given to targets registered without one (tests' plain nodes): -1, -2, ...
var _minted_keys: int = 0
var _target_owner: PackedInt32Array = PackedInt32Array()
## Each target's team, read from its owner actor when the grid is filled (see `_team_of_target`).
var _target_team: PackedInt32Array = PackedInt32Array()
## The grid: first target in each cell (-1 for none), and the next in its chain; where it starts
## (the bounds' corner, kept as two numbers for the hit test).
var _grid_x: float = 0.0
var _grid_y: float = 0.0
var _grid_w: int = 1
var _grid_h: int = 1
var _cell_head: PackedInt32Array = PackedInt32Array()
## How many targets each cell holds, and the box round their hit circles (min x, min y, max x,
## max y), so a hit test passes a cell its path cannot touch without a look at each target. Taken
## for a cell only when a hit test first reaches it after a filling (`_cell_info`; most cells of a
## big room are never tested in a step): valid while `_cell_filled` holds `_grid_fill`.
var _cell_count: PackedInt32Array = PackedInt32Array()
var _cell_box: PackedVector4Array = PackedVector4Array()
var _cell_filled: PackedInt32Array = PackedInt32Array()
## Counts the grid's fillings (`_refresh_targets`).
var _grid_fill: int = 0
var _target_next: PackedInt32Array = PackedInt32Array()
## The largest radius of any registered target; sets how far hits are searched.
var _max_target_radius: float = 0.0
## True when targets were added since the grid was filled (a query refreshes it).
var _grid_stale: bool = false

## The wall grid over the bounds: one byte per WALL_CELL cell, 0 for open: ROOM_CELL for a room
## wall, plus one for every solid shot lying on it (`set_solid`).
var _wall_w: int = 1
var _wall_h: int = 1
var _wall_cells: PackedByteArray = PackedByteArray()
var _has_walls: bool = false
## The solid shots (`set_solid`) by slot, and whether there are any (a field: the hot loops ask
## it for every shot).
var _solids: Dictionary = {}
var _any_solid: bool = false
## The shot that cast the next ray (`ray_cast_by`), and its number then; -1 for none.
var _ray_caster: int = -1
var _ray_caster_seq: int = -1
## Static bodies of solid shots that ended, kept for the next one.
var _spare_bodies: Array[StaticBody2D] = []


## A solid shot's wall (`set_solid`): `stones` stones `gap` radii apart across `across`, laid at
## `at` with `radius` (where it lay last: it is laid again when the shot moves or grows).
class Solid:
	## Not state: the static body, laid again by `_lay_solid` (core/sim/README.md).
	const DERIVED: Array[StringName] = [&"body"]
	var across: Vector2 = Vector2.RIGHT
	var stones: int = 1
	var gap: float = 0.0
	var at: Vector2 = Vector2.INF
	var radius: float = 0.0
	var cells: PackedInt32Array = PackedInt32Array()
	var body: StaticBody2D = null

## The colour of each shot's core (white for a plain shot), see `set_core`.
var _core: PackedColorArray = PackedColorArray()
## The packed look layers of each shot (0 none), see `set_look`.
var _look: PackedInt32Array = PackedInt32Array()
## The simulation time each shot was born at (`sim_time`), for the rune's trace.
var _born: PackedFloat32Array = PackedFloat32Array()
## The batches (BATCH_*): each one's node, the shots its MultiMesh and buffer have room for now
## (see `_fit_batch`) and its buffer (the GDScript's; the native kernel writes its own).
var _nodes: Array[MultiMeshInstance2D] = []
var _rooms: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
var _buffers: Array[PackedFloat32Array] = []
## A second MultiMesh per batch (BATCH_*; null for none) that draws the batch's rows again with a
## mesh of its own (`mirror_batch`: Feel's spell light). Each frame it is handed the very buffer
## the batch uploads, so no row is written twice.
var _mirrors: Array[MultiMesh] = []
## The first batches' nodes by name: the hat ramps' bolts, runes and orbits, the enemy ramp's
## flying shots and runes (drawn one layer above the others).
var _draw_node: MultiMeshInstance2D = null
var _still_node: MultiMeshInstance2D = null
var _orbit_node: MultiMeshInstance2D = null
var _enemy_node: MultiMeshInstance2D = null
var _enemy_still_node: MultiMeshInstance2D = null
## Live shots per batch this frame (BATCH_*), refilled by _count_batches; a member so no array is made per frame.
var _batch_counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
## The card bodies' shaders, body `n` at `n - 1` (`register_body`), and how many batches there are
## with theirs (`batch_count`; the native kernel reads it).
var _body_shaders: Array[Shader] = []
## Each card body's mesh (MESH_HEAD or MESH_QUAD), body `n` at `n - 1` (`register_body`).
var _body_meshes: PackedInt32Array = PackedInt32Array()
var _batch_total: int = BATCH_BODY_FIRST
## What the drawing wrote (`_draw_shots`, `ShotKernel.draw_shots`): the instances of each batch
## (BATCH_*), then the particles asked for, 0 (was the trails' cost), the shots drawn, the enemy shots drawn,
## the tail births laid (`spark_births`' first) and the tail asked for (`tail_demand`).
var _draw_out: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
## The shots' mesh (`head_mesh`), made once.
static var _head_mesh: ArrayMesh = null
## The length of the last step, so the drawing knows when its heads are (see `update_draw`).
var _last_delta: float = 0.0
## True inside step(): the grid is in use, so a target removed then is only
## switched off (layer 0) and swept at the start of the next step.
var _stepping: bool = false
## Hit-test work left in this step, and the slot the next step starts from
## (the first one that went untested when the budget ran out).
var _work_left: int = 0
var _resume: int = 0
## The hit-test work one step may do (WORK_PER_STEP unless a benchmark sets another: shot scale
## measures the crowd with every shot tested).
var work_per_step: int = WORK_PER_STEP
## Each step's parts, timed (PROF_*; shot scale H0, tests/benchmark/shot_scale.gd). Empty in the
## game, where `step()` reads no clock and pays one check a pass. A benchmark sizes it to
## PROF_PARTS and hands the clock (`profile_clock`, microseconds): the manager never reads real
## time itself (core/sim/README.md), so the same step is timed in the headless benchmark and in a
## runner on the real GPU.
var step_profile: PackedInt64Array = PackedInt64Array()
var profile_clock: Callable = Callable()
## Steps taken so far (staggers the homing searches).
var _step_index: int = 0
## Per slot: the key (`_target_key`) of the body a payload must not hit (the one that fired it,
## `exclude`), and above 0 while that holds: until a hit test finds the shot clear of that body where its step starts.
var _skip_id: PackedInt64Array = PackedInt64Array()
var _skip_on: PackedFloat32Array = PackedFloat32Array()
## Per slot: how far off that body's hit circle the shot was cast, when the body is its own caster's
## (the staff tip stands off it; 0 for any other body): within this, coming at the body, it is
## still leaving it (`_still_spares`).
var _skip_near: PackedFloat32Array = PackedFloat32Array()
## Where each actor's orbit shots circle (INF for no anchor), see `set_anchor`; ACTORS of them.
var _anchors: PackedVector2Array = PackedVector2Array()
## Scratch for `ray`, one set per nesting level (a hit handler may fire a ray of its own, as deep
## as the payloads go; `_ray_depth` is how many are in progress): the best hits so far, nearest
## first, and the path walked, kept while its hit handlers run. Plain Arrays, shared by
## reference, so a level grows in place and a busy frame allocates only the first time.
var _ray_nodes: Array[Array] = []
var _ray_along: Array[Array] = []
var _ray_points: Array[Array] = []
var _ray_heads: Array[Array] = []
var _ray_walks: Array[Array] = []
## The indices of a ray's turns at walls in its path, one list per nesting level.
var _ray_turns: Array[Array] = []
var _ray_depth: int = 0
## The path of the ray being found (`ray`, `ray_curve`): up to RAY_SEGMENTS pieces.
var _path: PackedVector2Array = PackedVector2Array()
var _path_heading: Vector2 = Vector2.ZERO
## The piece of `_path` that the last `_path_point` ended on.
var _path_piece: int = 0
## The path the last `ray`, `ray_points` or `ray_curve` walked, from its start to `ray_end`
## (`ray_path_count` points, 0 when it did nothing): straight on, it is its start and end; a
## beam that turned at walls has a point at every turn. Read right after the call, like `ray_end`.
var ray_path: PackedVector2Array = PackedVector2Array()
var ray_path_count: int = 0
## Where the last `ray` or `ray_curve` ended, and the beam's heading there (INF and zero when it
## did nothing). Read right after the call: a nested ray in a hit handler changes them.
var ray_end: Vector2 = Vector2.INF
var ray_end_heading: Vector2 = Vector2.ZERO
## The gates (the `portal` carrier, docs/milestones/portal.md): circles in the world that what goes
## in comes out of elsewhere. A row each: on or not, where, the way it faces, how big, its portal
## (`_gate_group`, the portal's own number), its portal's spell tag and whether it is the portal's mouth (1) or an exit (0).
## The portal carrier opens and closes them; rays (`ray_gates`), shots (`shots_into_gates`) and
## bodies read them here, as they read the walls. `_gate_live` counts the rows on.
var _gate_on: PackedByteArray = PackedByteArray()
var _gate_pos: PackedVector2Array = PackedVector2Array()
var _gate_face: PackedVector2Array = PackedVector2Array()
var _gate_radius: PackedFloat32Array = PackedFloat32Array()
var _gate_group: PackedInt64Array = PackedInt64Array()
var _gate_tag: PackedInt64Array = PackedInt64Array()
var _gate_mouth: PackedByteArray = PackedByteArray()
var _gate_live: int = 0
## With `ray_gates` set, the next rays stop where they enter a gate (a beam, which goes on from the
## other side: `CarrierBeam`); every other ray (a zap, a jump, a sweep) passes gates by. After a ray
## that stopped at one, `ray_gate` is that gate (-1 for none), `ray_gate_at` where it went in,
## `ray_gate_heading` its way in and `ray_gate_left` the length it had left. Read right after the
## call, like `ray_end`.
var ray_gates: bool = false
var ray_gate: int = -1
var ray_gate_at: Vector2 = Vector2.INF
var ray_gate_heading: Vector2 = Vector2.ZERO
var ray_gate_left: float = 0.0
## The gate the last `gate_cut` found (-1 for none).
var gate_hit: int = -1
## What the last `shots_into_gates` found: each shot's slot and the gate it went into (reused).
var gate_shots: PackedInt32Array = PackedInt32Array()
var gate_shot_gates: PackedInt32Array = PackedInt32Array()
## What the last `sweep` found (reused; grows when a sweep finds more): the bodies, where the
## wedge meets each, and the sweep's way there. Read right after the call: a hit handler's sweep changes them.
var sweep_nodes: Array = []
var sweep_points: PackedVector2Array = PackedVector2Array()
var sweep_heads: PackedVector2Array = PackedVector2Array()
## The shots the last `shots_in_wedge` or `shots_on_segment` found (reused; grows). Read right
## after the call: deflecting or blocking them can start other queries.
var guard_slots: PackedInt32Array = PackedInt32Array()
## The shot `threat` found last (-1 for none), and the way off its line (unit; ZERO for none).
var threat_slot: int = -1
var threat_away: Vector2 = Vector2.ZERO
## The spark pool's count (TAILLESS_PARTICLE_CAP; the "Tailless motes" dev slider).
var tailless_particle_cap: int = TAILLESS_PARTICLE_CAP
## A shot's particles as motes (see SPARK_BIRTH_STRIDE): whether something takes the births (no
## births are rolled while nothing does). `spark_births` holds `spark_birth_count` births of the
## last `update_draw` (reused; read before the next one).
var spark_motes: bool = false
var spark_births: PackedFloat32Array = PackedFloat32Array()
var spark_birth_count: int = 0
## Tails as motes (see SPARK_TAIL): whether the shots lay them this frame (the tails off and
## something takes the births), the most a frame (`set_tailless_pool` scales TAIL_BIRTHS), the
## most the thinned groups lay together this frame (see TAIL_FRESH), the widest spacing a group's
## are laid at this frame (TAIL_SPACING, wider when a group asks for more than its share;
## `_group_spacing`), and what the last frame laid and asked for (births at
## TAIL_SPACING; for the tests and the benchmarks).
var tail_births_on: bool = false
var tail_births_cap: int = TAIL_BIRTHS
var tail_thin_most: int = TAIL_BIRTHS
var tail_spacing: float = TAIL_SPACING
var tail_births: int = 0
var tail_demand: int = 0
## Per shot: where its tail was laid to (its drawn point last frame), the pixels of path before
## its next tail mote, and the tail motes it has laid (the dice of each: `tail_hash`).
var _tail_from: PackedVector2Array = PackedVector2Array()
var _tail_carry: PackedFloat32Array = PackedFloat32Array()
var _tail_n: PackedInt32Array = PackedInt32Array()
## The tail asked for while drawing (births at TAIL_SPACING), and the births of thinned groups laid.
var _tail_wanted: float = 0.0
var _tail_thin: int = 0
## Tails' ends (`_end_tail`): the births of the last stretch of every shot that ended in flight since
## the last frame (from where it was drawn last to where it ended), SPARK_BIRTH_STRIDE floats each,
## `_end_count` of them, and the tail they asked for; the next frame lays them after the drawn
## shots' tails (`_lay_ends`).
var _end_births: PackedFloat32Array = PackedFloat32Array()
var _end_count: int = 0
var _end_wanted: float = 0.0
## The groups (see GROUPS). Per slot: its group (`group_of`, set at its spawn). Per group: its live
## shots; and the groups with any, the first `_group_live` of `_groups` (`_group_at`: a group's
## place there).
var _group: PackedInt32Array = PackedInt32Array()
var _group_count: PackedInt32Array = PackedInt32Array()
var _groups: PackedInt32Array = PackedInt32Array()
var _group_at: PackedInt32Array = PackedInt32Array()
var _group_live: int = 0
## The drawing's, per group (`_plan_groups`): its first place in `_by_group` and the place after
## its last (the drawn slots of each group together, in slot order, for its particles), the tail
## and the particles it asked for this frame (births at TAIL_SPACING; `particles_of`, and one for a
## plain shot, whose twinkle asks the pool for none), the spacing
## its tail is laid at and the share of its particles given off, the tail it is expected to ask
## for, and the frame it was last planned in (`_draw_frame`) with its shots then. `_group_sort` is
## the scratch `fair_level` reads, sorted.
var _by_group: PackedInt32Array = PackedInt32Array()
var _group_start: PackedInt32Array = PackedInt32Array()
var _group_end: PackedInt32Array = PackedInt32Array()
var _group_tail: PackedFloat32Array = PackedFloat32Array()
var _group_ask: PackedFloat32Array = PackedFloat32Array()
var _group_spacing: PackedFloat32Array = PackedFloat32Array()
var _group_share: PackedFloat32Array = PackedFloat32Array()
var _group_want: PackedFloat32Array = PackedFloat32Array()
var _group_frame: PackedInt32Array = PackedInt32Array()
var _group_seen: PackedInt32Array = PackedInt32Array()
var _group_sort: PackedFloat32Array = PackedFloat32Array()
var _draw_frame: int = 0
## The last particle moment handed out, and the dice the births are rolled with.
var _spark_moment: int = -1
var _spark_rng := RandomNumberGenerator.new()
## The threat grid (see `threat`): the step and horizon it was built for (-1: none; any spawn,
## deflection or card move throws it away), its cells (THREAT_CELL or wider), each cell's shots as a
## list (`_threat_head` per cell, then `_threat_slot` and `_threat_next` per entry, -1 ends it), the
## shots whose paths cover too many cells (checked by every query), and which shots a query
## already tried (`_threat_seen`, stamped).
var _threat_step: int = -1
## Asks in the step `_threat_ask_step` and in the one before it (whether the grid pays).
var _threat_ask_step: int = -1
var _threat_asks: int = 0
var _threat_asks_before: int = 0
var _threat_horizon: float = 0.0
var _threat_cell: float = THREAT_CELL
var _threat_x: float = 0.0
var _threat_y: float = 0.0
var _threat_w: int = 0
var _threat_h: int = 0
var _threat_head: PackedInt32Array = PackedInt32Array()
var _threat_slot: PackedInt32Array = PackedInt32Array()
var _threat_next: PackedInt32Array = PackedInt32Array()
var _threat_over: PackedInt32Array = PackedInt32Array()
var _threat_over_count: int = 0
var _threat_seen: PackedInt32Array = PackedInt32Array()
var _threat_stamp: int = 0
## The native module's kernel (`ShotKernel`, core/native, native/README.md): the step's common and
## hit passes in C++, or null to run them here. Each of its methods does what the GDScript it
## stands for does, to the bit, on these same arrays (it writes them in place for the length of a
## call); the GDScript stays the reference and the fallback where the module is not built.
## `native` switches it off and on (tests step both and compare: test_native_kernel.gd).
var native: bool = true:
	set = set_native
var _kernel: Object = null
## The threads the native kernel's loops run on: 0 for its own choice (the machine's cores less
## one; 1 on the web). This machine's, never a run's: the kernel gives the same bits on one thread
## or many (shot scale H5, rule T2), and tests compare the two.
var native_threads: int = 0:
	set = set_native_threads
## The first shot the hit pass left untested (the budget ran out), and how many targets the native
## hit pass found for the shot it handed back (`_hit_found`).
var _starved_at: int = -1
var _cand_found: int = 0


func _init() -> void:
	for pass_name in BEHAVIOUR_PASSES:
		_passes.append(Callable(self, pass_name))
	assert(_passes.size() == BEHAVIOURS, "one pass per behaviour, in the order of B_*")
	_spark_rng.seed = 20261104
	_member_count.resize(BEHAVIOURS)
	_path.resize(RAY_PATH_START)
	ray_path.resize(RAY_PATH_START)
	sweep_nodes.resize(SWEEP_START)
	sweep_points.resize(SWEEP_START)
	sweep_heads.resize(SWEEP_START)
	_anchors.resize(ACTORS)
	_anchors.fill(Vector2.INF)
	_group_count.resize(GROUPS)
	_groups.resize(GROUPS)
	_group_at.resize(GROUPS)
	_group_start.resize(GROUPS)
	_group_end.resize(GROUPS)
	_group_frame.resize(GROUPS)
	_group_seen.resize(GROUPS)
	_group_tail.resize(GROUPS)
	_group_ask.resize(GROUPS)
	_group_spacing.resize(GROUPS)
	_group_share.resize(GROUPS)
	_group_want.resize(GROUPS)
	_group_spacing.fill(TAIL_SPACING)
	_group_share.fill(1.0)
	set_cap(DEFAULT_CAP_WEB if OS.has_feature("web") else DEFAULT_CAP_DESKTOP)
	set_bounds(_bounds)
	set_native(native)


## Use the native kernel when `on` and the module is loaded (see `native`). A kernel built against
## other constants or members than these is refused with an error, and the GDScript runs.
func set_native(on: bool) -> void:
	native = on
	_kernel = null
	if not on:
		return
	var kernel: Object = NativeScript.shot_kernel()
	if kernel == null:
		return
	# The kernel holds copies of constants: every one must be this script's (and a few from other
	# scripts), and every member it reads must be here, of its type; it lists any that is not.
	var wrong: PackedStringArray = kernel.call(&"check", native_constants()) + kernel.call(&"check_fields", self)
	if not wrong.is_empty():
		push_error("Projectiles: the native ShotKernel does not match this script (%s); running the GDScript" % ", ".join(wrong))
		return
	_kernel = kernel
	set_native_threads(native_threads)


## The threads the native kernel's loops run on now (0 without the kernel).
func native_thread_count() -> int:
	return _kernel.get(&"threads") if _kernel != null else 0


## Run the native kernel's loops on `threads` threads (see `native_threads`).
func set_native_threads(threads: int) -> void:
	native_threads = maxi(threads, 0)
	if _kernel != null:
		_kernel.set(&"threads", native_threads)


## The constants the native kernel checks its own copies against: this script's (with those of the
## manager it extends, for a script that extends it), and the few it takes from other scripts, by
## the names the kernel gives them.
func native_constants() -> Dictionary:
	var constants: Dictionary = {}
	var script: Script = get_script() as Script
	while script != null:
		constants.merge(script.get_script_constant_map())
		script = script.get_base_script()
	constants.merge({"PI": PI, "TAU": TAU, "HOMING_DRIFT": SpellLimits.HOMING_DRIFT,
			"RAMP_ENEMY": ActorsScript.RAMP_ENEMY, "TEAM_NONE": ActorsScript.NONE})
	return constants


## Whether the native kernel runs the step (`native` is on and the module is loaded).
func is_native() -> bool:
	return _kernel != null


func _ready() -> void:
	# The tick steps it (core/sim/tick.gd, core/sim/sim_area.gd).
	SimArea.join(self, &"Projectiles").steps(&"Projectiles", step).renewed_by(begin_run).takes_rules(take_rules)
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if events != null and not events.tailless_motes_changed.is_connected(set_tailless_pool):
		events.tailless_motes_changed.connect(set_tailless_pool)
	_nodes.resize(BATCH_BODY_FIRST)
	for batch: int in BATCH_ORDER:
		_nodes[batch] = _make_batch(_batch_z(batch), STILL_SHADER if first_batch_mesh(batch) == MESH_QUAD else HEAD_SHADER, null if first_batch_mesh(batch) == MESH_QUAD else head_mesh())
	# The card bodies numbered before it was in the tree.
	for n in _body_shaders.size():
		_make_body_batches(n + 1)
	_draw_node = _nodes[BATCH_BOLT]
	_still_node = _nodes[BATCH_STILL]
	_orbit_node = _nodes[BATCH_ORBIT]
	_enemy_node = _nodes[BATCH_ENEMY]
	_enemy_still_node = _nodes[BATCH_ENEMY_STILL]
	_apply_textures()
	_fit_draw_bounds()


## The body number (from 1) of a card's own shader drawing `mesh` (MESH_QUAD for still shots,
## MESH_HEAD for flying or orbiting ones), numbered the first time the pair is asked for: a pair of
## batches is made with them (`batches_grown`), and the shader is handed to the shader warm-up
## (`ShaderWarmup.want`, drawn as a batch), so it is compiled before the first room when it is
## asked for before then (Spells numbers every carrier card's when it starts). The same shader under
## the other mesh is another body. 0 for none, and for one past MOST_BODIES (an error names it; its
## shots are drawn by their motion's plain batch).
func register_body(shader: Shader, mesh: int = MESH_QUAD) -> int:
	if shader == null:
		return 0
	for at in _body_shaders.size():
		if _body_shaders[at] == shader and _body_meshes[at] == mesh:
			return at + 1
	if _body_shaders.size() >= MOST_BODIES:
		push_error("Projectiles: no batch left for the shot shader %s (MOST_BODIES is %d); its shots are drawn plain" % [shader.resource_path, MOST_BODIES])
		return 0
	if not _body_shaders.has(shader):
		ShaderWarmupScript.want(shader, ShaderWarmupScript.BATCH)
	_body_shaders.append(shader)
	_body_meshes.append(MESH_HEAD if mesh == MESH_HEAD else MESH_QUAD)
	var body: int = _body_shaders.size()
	_batch_total = BATCH_BODY_FIRST + 2 * body
	_rooms.resize(_batch_total)
	_batch_counts.resize(_batch_total)
	_draw_out.resize(DRAW_OUT_FIRST + _batch_total)
	while _buffers.size() < _batch_total:
		_buffers.append(PackedFloat32Array())
	if _mirrors.size() < _batch_total:
		_mirrors.resize(_batch_total)
	if _nodes.size() >= BATCH_BODY_FIRST:
		_make_body_batches(body)
	batches_grown.emit(_batch_total)
	return body


## The mesh a shot of `motion` is written as (`_write_stones` or `_write_head`): MESH_QUAD for a
## still shot, MESH_HEAD for any other. A card body draws a shot only while this is its mesh.
static func mesh_of_motion(motion: int) -> int:
	return MESH_QUAD if motion == MOTION_STILL else MESH_HEAD


## How many draw batches there are now: the first five and a pair for each card body.
func batch_count() -> int:
	return _batch_total


## Batch `batch`'s mesh: MESH_HEAD the shots' (`head_mesh`), MESH_QUAD one quad a shot (runes, a
## still card's body); a card body's batch draws its body's mesh.
func batch_mesh(batch: int) -> int:
	if batch >= BATCH_BODY_FIRST:
		var body: int = (batch - BATCH_BODY_FIRST) / 2 + 1
		return _body_meshes[body - 1] if body <= _body_meshes.size() else MESH_QUAD
	return first_batch_mesh(batch)


## The mesh of one of the first batches (BATCH_BOLT to BATCH_ENEMY_STILL), which every manager has.
static func first_batch_mesh(batch: int) -> int:
	return MESH_HEAD if batch == BATCH_BOLT or batch == BATCH_ORBIT or batch == BATCH_ENEMY else MESH_QUAD


## True for a batch on the enemy ramp's layer, one above the others: its flying shots, its runes,
## and the enemy half of each card body's pair.
static func batch_on_enemy_layer(batch: int) -> bool:
	if batch >= BATCH_BODY_FIRST:
		return (batch - BATCH_BODY_FIRST) % 2 == 1
	return batch == BATCH_ENEMY or batch == BATCH_ENEMY_STILL


## True for a batch given the shot art (`texture`): the hat ramps' bolts, runes and orbits.
static func batch_textured(batch: int) -> bool:
	return batch == BATCH_BOLT or batch == BATCH_STILL or batch == BATCH_ORBIT


## The z its batch's node draws at.
static func _batch_z(batch: int) -> int:
	return DRAW_Z + (1 if batch_on_enemy_layer(batch) else 0)


## The shader of card body `body` (from 1), or null.
func body_shader(body: int) -> Shader:
	return _body_shaders[body - 1] if body >= 1 and body <= _body_shaders.size() else null


## The mesh of card body `body` (from 1; MESH_HEAD or MESH_QUAD), MESH_QUAD for none.
func body_mesh(body: int) -> int:
	return _body_meshes[body - 1] if body >= 1 and body <= _body_meshes.size() else MESH_QUAD


## The batch a shot of card body `body` draws in: its hat ramps' or, with
## `enemy`, its enemy ramp's.
static func body_batch(body: int, enemy: bool) -> int:
	return BATCH_BODY_FIRST + 2 * (body - 1) + (1 if enemy else 0)


## Makes card body `body`'s pair of batches with its shader and mesh (the nodes before it are made),
## fitted to the room as the others are, each placed in the draw order (`_place_body_node`).
func _make_body_batches(body: int) -> void:
	var mesh: int = _body_meshes[body - 1]
	for enemy: bool in [false, true]:
		var batch: int = body_batch(body, enemy)
		if _nodes.size() <= batch:
			_nodes.resize(batch + 1)
		if _nodes[batch] == null:
			_nodes[batch] = _make_batch(_batch_z(batch), _body_shaders[body - 1], head_mesh() if mesh == MESH_HEAD else null)
			_nodes[batch].multimesh.custom_aabb = _nodes[BATCH_BOLT].multimesh.custom_aabb
			_place_body_node(body, enemy)


## Moves card body `body`'s node (the hat ramps' or, with `enemy`, the enemy ramp's) into the first
## batches' draw order at its z (BATCH_ORDER: bolts, runes, orbits; a node later among its siblings
## draws above the ones before it): right after the batch of plain shots its mesh draws
## (BATCH_BOLT or BATCH_ENEMY for a head body, BATCH_STILL or BATCH_ENEMY_STILL for a quad one) and
## the bodies of its mesh and layer numbered before it. So a bolt with a look of its own still draws
## under the runes and the orbit shots, as a plain bolt does.
func _place_body_node(body: int, enemy: bool) -> void:
	var mesh: int = _body_meshes[body - 1]
	var plain: int
	if mesh == MESH_HEAD:
		plain = BATCH_ENEMY if enemy else BATCH_BOLT
	else:
		plain = BATCH_ENEMY_STILL if enemy else BATCH_STILL
	var after: Node = _nodes[plain]
	for earlier in range(1, body):
		if _body_meshes[earlier - 1] == mesh:
			var node: Node = _nodes[body_batch(earlier, enemy)]
			if node != null and node.get_index() > after.get_index():
				after = node
	var mine: Node = _nodes[body_batch(body, enemy)]
	move_child(mine, after.get_index() + 1 if mine.get_index() > after.get_index() else after.get_index())


## Draw batch `batch`'s rows (BATCH_*) again in `multimesh` too, or stop with null (Feel's spell
## light, docs/milestones/spell-spectacle.md, P3a). `multimesh` takes the batch's instance count and
## each frame the same buffer the batch uploads (`update_draw`), so it must have the batch's format
## (TRANSFORM_2D, colours and custom data); its mesh and its node's shader are its own.
func mirror_batch(batch: int, multimesh: MultiMesh) -> void:
	if _mirrors.size() < _batch_total:
		_mirrors.resize(_batch_total)
	_mirrors[batch] = multimesh
	if multimesh != null and batch < _nodes.size() and _nodes[batch] != null:
		var source: MultiMesh = _nodes[batch].multimesh
		multimesh.instance_count = source.instance_count
		multimesh.visible_instance_count = 0


## The MultiMesh mirroring batch `batch` (`mirror_batch`), or null.
func batch_mirror(batch: int) -> MultiMesh:
	return _mirrors[batch] if batch < _mirrors.size() else null


## One batched draw of up to `_cap` instances (TRANSFORM_2D plus a colour and custom data each)
## by `shader`, added as a child: each a quad, or each a `mesh` (the shots' `head_mesh`).
func _make_batch(z: int, shader: Shader, mesh: Mesh) -> MultiMeshInstance2D:
	var node := MultiMeshInstance2D.new()
	if mesh == null:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		mesh = quad
	# Never culled until `_fit_draw_bounds` fits its box to the room.
	var multimesh: MultiMesh = BatchesScript.multimesh()
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	var material := ShaderMaterial.new()
	material.shader = shader
	node.material = material
	multimesh.mesh = mesh
	multimesh.instance_count = 0
	multimesh.visible_instance_count = 0
	node.multimesh = multimesh
	node.z_index = z
	add_child(node)
	return node


## The mesh a shot is drawn as (`shot_head.gdshader`, PARTICLES ARE GEOMETRY there): small
## quads, each told in its UV which quad kind (HEAD_Q_*) it is, in HEAD_QUAD_KINDS' order (the
## light first, then the core). The shader places each quad round the head, or folds it away; a
## vertex says which quad and corner it is in its UV: x 0.25 or 0.75, y the kind + 0.25 or 0.75. A
## quad is one triangle of HEAD_QUAD_VERTICES vertices, twice its box each way, which the fragment
## stage cuts to the box: each vertex runs the whole vertex stage, so three cost a quarter less than
## a square's four (performance, 2026-11-02; the pixels are the same). It is made once and shared
## by the shot batches.
static func head_mesh() -> ArrayMesh:
	if _head_mesh != null:
		return _head_mesh
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var corners: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0)]
	for kind: int in HEAD_QUAD_KINDS:
		var base: int = verts.size()
		for corner: Vector2 in corners:
			verts.append(corner)
			uvs.append(Vector2(0.25 + 0.5 * corner.x, float(kind) + 0.25 + 0.5 * corner.y))
			colors.append(Color.WHITE)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_head_mesh = mesh
	return mesh


func _apply_textures() -> void:
	for batch in _nodes.size():
		if batch_textured(batch):
			_nodes[batch].texture = texture


func _process(_delta: float) -> void:
	update_draw()


## Set the global cap and remove every projectile. Not for use mid-fight. The shots are removed
## first, while the arrays still have the old size: a smaller cap than the shots' highest slot
## then ends them all (`shot_ended`) instead of reading past the shrunk arrays.
func set_cap(value: int) -> void:
	_threat_step = -1
	if _cap > 0 and _alive.size() == _cap:
		clear()
	_cap = maxi(value, 1)
	_pos.resize(_cap)
	_prev.resize(_cap)
	_untested.resize(_cap)
	_vel.resize(_cap)
	_life.resize(_cap)
	_radius.resize(_cap)
	_actor.resize(_cap)
	_team.resize(_cap)
	_ramp.resize(_cap)
	_budget.resize(_cap)
	_layers.resize(_cap)
	_pierce.resize(_cap)
	_tag.resize(_cap)
	_motion.resize(_cap)
	_body.resize(_cap)
	_look_light_intensity.resize(_cap)
	_look_light_reach.resize(_cap)
	_form_id.resize(_cap)
	_orbit_radius.resize(_cap)
	_orbit_angle.resize(_cap)
	_orbit_speed.resize(_cap)
	_orbit_centre.resize(_cap)
	_turn.resize(_cap)
	_home_at.resize(_cap)
	_home_range.resize(_cap)
	_home_target.resize(_cap)
	_seq.resize(_cap)
	_flags.resize(_cap)
	_bounce.resize(_cap)
	_shield.resize(_cap)
	_deflect.resize(_cap)
	_span.resize(_cap)
	_radius0.resize(_cap)
	_growth.resize(_cap)
	_curve_from.resize(_cap)
	_curve_to.resize(_cap)
	_curve_ease.resize(_cap)
	_curve_speed.resize(_cap)
	_wave.resize(_cap)
	_wave_age.resize(_cap)
	_base.resize(_cap)
	_linger.resize(_cap)
	_hold.resize(_cap)
	_freeze.resize(_cap)
	_stick.resize(_cap)
	_stuck_to.resize(_cap)
	_stuck_off.resize(_cap)
	_speed.resize(_cap)
	_caster_slot.resize(_cap)
	_caster_seq.resize(_cap)
	_caster_at.resize(_cap)
	var move_heads: int = _move_head.size()
	_move_head.resize(_cap)
	for slot in range(move_heads, _cap):
		_move_head[slot] = -1
	if _move_left.is_empty():
		_grow_moves(MOVES_START)
	_shot_next.resize(_cap)
	_members.resize(_cap * BEHAVIOURS)
	_member_at.resize(_cap * BEHAVIOURS)
	_kinds.resize(_cap)
	_state.resize(_cap)
	_wait_state.resize(_cap)
	_wait_from.resize(_cap)
	_shield_order.resize(_cap)
	_drawn_seq.resize(_cap)
	_drawn_seq.fill(-1)
	_drawn_radius.resize(_cap)
	_drawn_look.resize(_cap)
	_drawn_batch.resize(_cap)
	_drawn_color.resize(_cap)
	_drawn_size.resize(_cap)
	_drawn_particles.resize(_cap)
	_skip_id.resize(_cap)
	_skip_on.resize(_cap)
	_skip_near.resize(_cap)
	var heads: int = _mem_head.size()
	_mem_head.resize(_cap)
	for slot in range(heads, _cap):
		_mem_head[slot] = -1
	if _mem_id.is_empty():
		_grow_memory(HIT_MEMORY_START)
	_own_prev.resize(_cap)
	_own_next.resize(_cap)
	_core.resize(_cap)
	_look.resize(_cap)
	_tail_from.resize(_cap)
	_tail_carry.resize(_cap)
	_tail_n.resize(_cap)
	_group.resize(_cap)
	_by_group.resize(_cap)
	_born.resize(_cap)
	while _buffers.size() < _batch_total:
		_buffers.append(PackedFloat32Array())
	for buffer in _buffers:
		buffer.resize(0)
	_rooms.fill(0)
	_alive.resize(_cap)
	_free_slots.resize(_cap)
	clear()
	for node in _nodes:
		node.multimesh.instance_count = 0
	for mirror in _mirrors:
		if mirror != null:
			mirror.instance_count = 0


func get_cap() -> int:
	return _cap


## The "Max shots" setting (`projectile_cap_changed`): a new cap applies at once, which ends the
## shots in the air (`set_cap`); the same cap changes nothing.
## The run's rules (core/sim/session_rules.gd; the Tick hands them over at a run's start, before
## `begin_run`, and when a seat changes the cap in a run): the cap (`set_cap` when it differs: the
## shots in the air end) and the hit-test work a step may do.
func take_rules(rules: SessionRules) -> void:
	if rules == null:
		return
	if rules.shot_cap != _cap:
		set_cap(rules.shot_cap)
	work_per_step = rules.hit_work


## The spark pool while the tails are off (`tailless_particle_cap`; the "Tailless motes" dev
## slider, `tailless_motes_changed`, `TaillessMotes` in core/settings). Read each frame.
func set_tailless_pool(pool: int) -> void:
	tailless_particle_cap = maxi(pool, 0)
	tail_births_cap = clampi(TAIL_BIRTHS * tailless_particle_cap / TAILLESS_PARTICLE_CAP, 0, SPARK_BIRTHS_MAX / 2)


## The area the projectiles live in. Also sizes the target grid.
func set_bounds(rect: Rect2) -> void:
	_bounds = rect
	_threat_step = -1
	_fit_draw_bounds()
	_grid_x = rect.position.x
	_grid_y = rect.position.y
	_grid_w = maxi(ceili(rect.size.x / GRID_CELL), 1)
	_grid_h = maxi(ceili(rect.size.y / GRID_CELL), 1)
	_cell_head.resize(_grid_w * _grid_h)
	_cell_head.fill(-1)
	_cell_count.resize(_grid_w * _grid_h)
	_cell_count.fill(0)
	_cell_box.resize(_grid_w * _grid_h)
	_cell_filled.resize(_grid_w * _grid_h)
	_cell_filled.fill(-1)
	_shot_head.resize(_grid_w * _grid_h)
	_scan_step = -1
	_grid_stale = true
	_wall_w = maxi(ceili(rect.size.x / WALL_CELL), 1)
	_wall_h = maxi(ceili(rect.size.y / WALL_CELL), 1)
	_wall_cells.resize(_wall_w * _wall_h)
	clear_walls()


## The longer side of the room (`set_bounds`): what a growing shot or beam grows to at most.
func room_size() -> float:
	return maxf(_bounds.size.x, _bounds.size.y)


## The room's bounds (`set_bounds`), in world pixels.
func bounds() -> Rect2:
	return _bounds


## The room's walls as an image (FORMAT_L8), one pixel a WALL_CELL square from the corner of
## `bounds()`: white for a room wall, black for open (solid shots are left out). Made each call,
## for what is built once a room (Feel's floor marks).
func wall_image() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(_wall_w * _wall_h)
	for i in mini(bytes.size(), _wall_cells.size()):
		bytes[i] = 255 if (_wall_cells[i] & ROOM_CELL) != 0 else 0
	return Image.create_from_data(_wall_w, _wall_h, false, Image.FORMAT_L8, bytes)


## Make these world rectangles solid, replacing any walls set before. Parts outside
## the bounds are ignored. Call it after `set_bounds()`, which removes the walls.
func set_walls(rects: Array[Rect2]) -> void:
	clear_walls()
	for rect in rects:
		_add_wall(rect)


## Remove every wall. A solid shot lays itself again at its next step.
func clear_walls() -> void:
	_wall_cells.fill(0)
	_has_walls = false
	for slot: int in _solids:
		var solid: Solid = _solids[slot]
		solid.cells.clear()
		solid.at = Vector2.INF


## Add the rectangle shapes of a body (a room's static body) as walls. The body must
## be in the tree. Shapes that are not rectangles are ignored; a turned rectangle
## counts as its bounding box.
func add_wall_body(body: CollisionObject2D) -> void:
	for child in body.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.disabled:
			continue
		var rectangle := shape_node.shape as RectangleShape2D
		if rectangle == null:
			continue
		var xf: Transform2D = shape_node.global_transform
		var half: Vector2 = rectangle.size * 0.5
		var low: Vector2 = xf * -half
		var high: Vector2 = low
		for corner: Vector2 in [Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]:
			var point: Vector2 = xf * corner
			low = low.min(point)
			high = high.max(point)
		_add_wall(Rect2(low, high - low))


func _add_wall(rect: Rect2) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var x0: int = maxi(floori((rect.position.x - _bounds.position.x) / WALL_CELL), 0)
	var y0: int = maxi(floori((rect.position.y - _bounds.position.y) / WALL_CELL), 0)
	var x1: int = mini(ceili((rect.end.x - _bounds.position.x) / WALL_CELL), _wall_w)
	var y1: int = mini(ceili((rect.end.y - _bounds.position.y) / WALL_CELL), _wall_h)
	for y in range(y0, y1):
		for x in range(x0, x1):
			_wall_cells[y * _wall_w + x] |= ROOM_CELL
			_has_walls = true


## Make the still shot in `slot` a wall while it lives (the Wall card, rules R4 F6): a row of
## `stones` stones across `across`, `gap` pixels apart (and its radius thick, both growing with
## it). It lies in the wall grid and as a static body on WALL_LAYER, it hits along its row, and
## it follows the shot when homing moves it, stopping at a wall. False for an empty slot or a
## shot that is not still.
func set_solid(slot: int, across: Vector2, stones: int, gap: float) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or _motion[slot] != MOTION_STILL or across.is_zero_approx() or not across.is_finite():
		return false
	var solid := Solid.new()
	solid.across = across.normalized()
	solid.stones = maxi(stones, 1)
	solid.gap = gap / maxf(_radius[slot], 0.01)
	_solids[slot] = solid
	_any_solid = true
	_lay_solid(slot, solid)
	return true


## Half the row of the solid shot in `slot`: from its middle to its last stone's centre.
func _solid_half(slot: int, solid: Solid) -> Vector2:
	return solid.across * (solid.stones - 1) * 0.5 * solid.gap * _radius[slot]


## A solid shot's step, in place of a wall check: when it moved or grew it is lifted, stopped
## where a wall cuts its way, and laid again.
func _step_solid(slot: int, solid: Solid) -> void:
	if _pos[slot] == solid.at and _radius[slot] == solid.radius:
		return
	_lift_solid(solid)
	if _pos[slot] != _prev[slot] and _wall_hit(_prev[slot], _pos[slot]) >= 0.0:
		_pos[slot] = _prev[slot]
	_lay_solid(slot, solid)


## Lay the solid shot in `slot` into the wall grid where it is now: every cell whose centre is
## within its radius and half a cell of its row, so a shot cannot slip between two cells.
func _lay_solid(slot: int, solid: Solid) -> void:
	solid.at = _pos[slot]
	solid.radius = _radius[slot]
	var half: Vector2 = _solid_half(slot, solid)
	var a: Vector2 = solid.at - half
	var b: Vector2 = solid.at + half
	var reach: float = solid.radius + WALL_CELL * 0.5
	var low: Vector2 = a.min(b) - Vector2(reach, reach) - _bounds.position
	var high: Vector2 = a.max(b) + Vector2(reach, reach) - _bounds.position
	for y in range(maxi(floori(low.y / WALL_CELL), 0), mini(ceili(high.y / WALL_CELL), _wall_h)):
		for x in range(maxi(floori(low.x / WALL_CELL), 0), mini(ceili(high.x / WALL_CELL), _wall_w)):
			var centre: Vector2 = _bounds.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * WALL_CELL
			if Geometry2D.get_closest_point_to_segment(centre, a, b).distance_squared_to(centre) > reach * reach:
				continue
			var cell: int = y * _wall_w + x
			if (_wall_cells[cell] & (ROOM_CELL - 1)) < ROOM_CELL - 1:
				_wall_cells[cell] += 1
				solid.cells.append(cell)
	_has_walls = _has_walls or not solid.cells.is_empty()
	if solid.body == null and is_inside_tree():
		solid.body = _spare_bodies.pop_back() if not _spare_bodies.is_empty() else _new_solid_body()
	if solid.body != null:
		solid.body.collision_layer = WALL_LAYER
		solid.body.position = solid.at
		solid.body.rotation = DMath.angle(solid.across)
		var shape := (solid.body.get_child(0) as CollisionShape2D).shape as RectangleShape2D
		shape.size = Vector2(half.length() + solid.radius, solid.radius) * 2.0


func _new_solid_body() -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	body.add_child(shape)
	add_child(body)
	return body


## Take a solid shot's cells out of the wall grid.
func _lift_solid(solid: Solid) -> void:
	_mark_solid(solid, -1)
	solid.cells.clear()


## Add `by` (1 or -1) to the count of every cell a solid shot lies on.
func _mark_solid(solid: Solid, by: int) -> void:
	for cell in solid.cells:
		_wall_cells[cell] += by


## The live solid shot that cast the shot in `slot` (a payload of a wall), or null.
func _own_solid(slot: int) -> Solid:
	return _solid_of(_caster_slot[slot], _caster_seq[slot])


## Where the shot in `slot` meets a wall this step (`cut`, as `_wall_hit` found it) when the
## wall that cast it does not count: a wall's own payloads leave it (its row is lifted while
## they look again). Asked only when it met a wall, so a step with none costs nothing.
func _past_own_solid(slot: int, cut: float) -> float:
	var own: Solid = _own_solid(slot)
	if own == null:
		return cut
	_mark_solid(own, -1)
	cut = _wall_hit(_prev[slot], _pos[slot])
	_mark_solid(own, 1)
	return cut


## The solid shot in `caster` while it is still the shot numbered `seq`, or null.
func _solid_of(caster: int, seq: int) -> Solid:
	if not _any_solid or caster < 0 or caster >= _cap:
		return null
	if _alive[caster] != 0 and _seq[caster] == seq and _solids.has(caster):
		return _solids[caster]
	return null


## The next ray (`ray`, `ray_points`, `ray_curve`) was cast by the shot in `slot` (a payload's
## carrier, as `set_caster_shot` says for a shot): a wall's own ray walks out of it, as its shots
## fly out of it. It holds for that one ray.
func ray_cast_by(slot: int) -> void:
	_ray_caster = slot if slot >= 0 and slot < _cap and _alive[slot] != 0 else -1
	_ray_caster_seq = _seq[_ray_caster] if _ray_caster >= 0 else -1


## The solid shot in `slot` ended: its wall goes, and its body waits for the next one.
func _drop_solid(slot: int) -> void:
	var solid: Solid = _solids[slot]
	_solids.erase(slot)
	_any_solid = not _solids.is_empty()
	_lift_solid(solid)
	if solid.body != null:
		solid.body.collision_layer = 0
		_spare_bodies.append(solid.body)


## The point where the segment from `from` to `to` first meets a wall, or `to` when
## it is clear. If `from` is inside a wall, that is `from`.
func clip_to_walls(from: Vector2, to: Vector2) -> Vector2:
	var t: float = _wall_hit(from, to)
	if t < 0.0:
		return to
	return from.lerp(to, t)


## True when nothing in the wall grid lies on the segment from `from` to `to`: no room wall and
## no solid shot (a Wall card's, whoever cast it), as a shot along it would find. Walks the whole
## segment, however long (an AI's line of fire, `gameplay/ai/sight.gd`).
func line_clear(from: Vector2, to: Vector2) -> bool:
	var cells: int = ceili(from.distance_to(to) / WALL_CELL) * 2 + 2
	return _wall_hit(from, to, maxi(cells, MAX_WALL_VISITS)) < 0.0


## True when a circle of `radius` at `center` is out of the bounds or touches a wall cell
## (checked at the centre and eight points on its rim, each in its 8-pixel cell).
func circle_blocked(center: Vector2, radius: float) -> bool:
	for n in 9:
		var point: Vector2 = center
		if n > 0:
			point += DMath.from_angle(float(n - 1) * TAU / 8.0) * radius
		if not _bounds.has_point(point):
			return true
		if not _has_walls:
			continue
		var cx: int = floori((point.x - _bounds.position.x) / WALL_CELL)
		var cy: int = floori((point.y - _bounds.position.y) / WALL_CELL)
		if cx >= 0 and cx < _wall_w and cy >= 0 and cy < _wall_h and _wall_cells[cy * _wall_w + cx] != 0:
			return true
	return false


## How far along `from`->`to` (0 to 1) the path first enters a solid cell, or -1.0
## when it does not. Walks the cells the path crosses (Amanatides and Woo), at
## most |dx| + |dy| + 1 of them, in cells.
func _wall_hit(from: Vector2, to: Vector2, max_visits: int = MAX_WALL_VISITS) -> float:
	if not _has_walls:
		return -1.0
	var start: Vector2 = (from - _bounds.position) / WALL_CELL
	var delta: Vector2 = (to - from) / WALL_CELL
	var cx: int = floori(start.x)
	var cy: int = floori(start.y)
	var end_x: int = floori(start.x + delta.x)
	var end_y: int = floori(start.y + delta.y)
	if cx == end_x and cy == end_y:
		# The usual step stays in one cell.
		if cx >= 0 and cx < _wall_w and cy >= 0 and cy < _wall_h and _wall_cells[cy * _wall_w + cx] != 0:
			return 0.0
		return -1.0
	if absi(end_x - cx) <= 1 and absi(end_y - cy) <= 1 and mini(cx, end_x) >= 0 and maxi(cx, end_x) < _wall_w and mini(cy, end_y) >= 0 and maxi(cy, end_y) < _wall_h:
		# A short path (a shot's step, a staff from the feet to its tip) only crosses the up to four
		# cells of its corners: when none is solid it meets no wall, without the walk below
		# (performance pass, 2026-10-28).
		var row0: int = cy * _wall_w
		var row1: int = end_y * _wall_w
		if _wall_cells[row0 + cx] == 0 and _wall_cells[row0 + end_x] == 0 and _wall_cells[row1 + cx] == 0 and _wall_cells[row1 + end_x] == 0:
			return -1.0
	var step_x: int = 1 if delta.x > 0.0 else -1
	var step_y: int = 1 if delta.y > 0.0 else -1
	var next_x: float = INF
	var next_y: float = INF
	var per_x: float = INF
	var per_y: float = INF
	if delta.x != 0.0:
		per_x = absf(1.0 / delta.x)
		next_x = (float(cx + (1 if step_x > 0 else 0)) - start.x) / delta.x
	if delta.y != 0.0:
		per_y = absf(1.0 / delta.y)
		next_y = (float(cy + (1 if step_y > 0 else 0)) - start.y) / delta.y
	var t: float = 0.0
	# A huge step (after a hitch) walks at most MAX_WALL_VISITS cells; a path
	# that is still unchecked after that counts as a hit, so a shot never
	# crosses a wall it did not look at.
	var full: int = absi(end_x - cx) + absi(end_y - cy) + 1
	var visits: int = mini(full, max_visits)
	for _n in visits:
		if cx >= 0 and cx < _wall_w and cy >= 0 and cy < _wall_h and _wall_cells[cy * _wall_w + cx] != 0:
			return t
		if next_x < next_y:
			t = next_x
			next_x += per_x
			cx += step_x
		else:
			t = next_y
			next_y += per_y
			cy += step_y
		if t > 1.0:
			return -1.0
	return t if full > visits else -1.0


## The batch's culling box must cover the whole area. Without it the renderer
## culls the batch by a box that does not follow the shots, and shots away from
## the origin were never drawn.
func _fit_draw_bounds() -> void:
	if _draw_node == null:
		return
	var box: Rect2 = _bounds.grow(BOUNDS_MARGIN)
	var aabb := AABB(Vector3(box.position.x, box.position.y, -1.0), Vector3(box.size.x, box.size.y, 2.0))
	for node in _nodes:
		node.multimesh.custom_aabb = aabb


## Remove every projectile (targets stay registered).
func clear() -> void:
	for slot in _high:
		if _alive[slot] != 0 and _tag[slot] != 0:
			shot_ended.emit(_tag[slot])
	for slot: int in _solids.keys():
		_drop_solid(slot)
	_alive.fill(0)
	_state.fill(S_IDLE)
	_member_count.fill(0)
	_kinds.fill(0)
	for i in _cap:
		_free_slots[i] = _cap - 1 - i
	_free_count = _cap
	_count = 0
	_high = 0
	_owned.fill(0)
	_own_head.fill(-1)
	_own_tail.fill(-1)
	_group_count.fill(0)
	_group_live = 0
	_gate_on.fill(0)
	_gate_live = 0
	_end_count = 0
	_end_wanted = 0.0
	# `drawn` stays: the next update_draw() must still empty the batch.


## A run starts (`Tick.begin_run`, online-ready N3b): every shot ends (`clear`), and the manager is
## a fresh one's state (core/sim/sim_fresh.gd): its clock, sequence numbers, groups, grid and every
## dead slot's leftovers, with this session's settings (RUN_KEEPS, the cap) and the room's bounds.
func begin_run() -> void:
	clear()
	# The target table's nodes are kept (DERIVED) and its numbers renewed: a body still registered
	# would lose its row. The last run's bodies have left by now (Flow's world, and Entities' decoys:
	# Tick renews Entities first), so none is.
	if not _targets.is_empty():
		var names: PackedStringArray = PackedStringArray()
		for target in _targets:
			names.append(str(target.get_path()) if is_instance_valid(target) and target.is_inside_tree() else str(target))
		push_error("ProjectileManager.begin_run: %d targets are still registered (%s); the last run's bodies must leave before a run starts" % [_targets.size(), ", ".join(names)])
	var bounds: Rect2 = _bounds
	# The blank's arrays as big as this one's: the cap is kept (RUN_KEEPS).
	SimFresh.renew(self, func(blank: Object) -> void: blank.call(&"set_cap", _cap))
	set_bounds(bounds)


## Live projectiles.
func get_count() -> int:
	return _count


## Live projectiles in the drop bucket of `caster`'s budget (`Actors.budget_of`): a seat's
## actor counts its seat's shots; every actor no seat drives, and NO_PLAYER, the shared count.
func get_count_for(caster: int) -> int:
	if not is_caster(caster):
		return 0
	return _owned[_budget_of(caster)]


## Live projectiles in one budget's drop bucket (0-3 a seat's, `Actors.SHARED`).
func get_count_for_budget(budget: int) -> int:
	return _owned[budget] if budget >= 0 and budget < BUDGETS else 0


## True for a caster number a shot may have: an actor id or NO_PLAYER (no actor).
static func is_caster(caster: int) -> bool:
	return caster >= ActorsScript.NONE and caster < ACTORS


## True for a ramp drawn in a hat colour (0-3); anything else is drawn in the enemy ramp.
static func is_hat_ramp(ramp: int) -> bool:
	return ramp >= 0 and ramp < ActorsScript.RAMP_ENEMY


## The actor table: `actors`, else the `Actors` autoload (looked up once), else null.
func actor_table() -> ActorsScript:
	if actors != null:
		return actors if is_instance_valid(actors) else null
	if _auto_actors == null or not is_instance_valid(_auto_actors):
		_auto_actors = null
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		if tree != null and tree.root != null:
			_auto_actors = tree.root.get_node_or_null(^"Actors") as ActorsScript
	return _auto_actors


## The team `caster` aims for (NONE for no actor).
func _team_of(caster: int) -> int:
	var table: ActorsScript = actor_table()
	return table.team_of(caster) if table != null else ActorsScript.NONE


## The ramp `caster`'s spells are drawn in (NONE for no actor: drawn in the enemy ramp).
func _ramp_of(caster: int) -> int:
	var table: ActorsScript = actor_table()
	return table.ramp_of(caster) if table != null else ActorsScript.NONE


## The budget (and drop bucket) `caster` spends: its seat's, or SHARED.
func _budget_of(caster: int) -> int:
	var table: ActorsScript = actor_table()
	return table.budget_of(caster) if table != null else ActorsScript.SHARED


## The team a target aims as: its owner actor's. A target no actor owns (until actors G6 every
## enemy that casts nothing, and the dummies) is on the team of its layer's bodies: the wizards'
## for LAYER_PLAYER, else the enemies'.
func _team_of_target(owner: int, layer: int) -> int:
	var team: int = _team_of(owner) if owner >= 0 else ActorsScript.NONE
	if team != ActorsScript.NONE:
		return team
	return ActorsScript.TEAM_WIZARDS if (layer & LAYER_PLAYER) != 0 else ActorsScript.TEAM_ENEMIES


## Register a Node2D as something projectiles can hit (`layer` is a non-zero
## bit mask). Registering twice only updates the radius, layer and owner. A freed target is dropped by itself.
## `owner` is the actor whose body it is (or whose decoy), or Events.NO_PLAYER: aim reads it
## (homing never picks its own actor's body) and its team (see `_team_of_target`); a hit never
## asks it. `offset` moves the hit circle from the
## node's origin (usually the feet) to the drawn body, so a shot that looks like it touches
## the sprite does hit. `key` is its identity (`_target_key`): its actor's key (`Actors.key_of`); 0
## gives it one of the manager's own (a plain node, in tests). Registered again with a key, it takes it.
func add_target(node: Node2D, radius: float, layer: int = LAYER_ENEMY, owner: int = EventsScript.NO_PLAYER, offset: Vector2 = Vector2.ZERO, key: int = 0) -> void:
	if node == null or layer == 0:
		return
	var id: int = node.get_instance_id()
	var at: int = _target_id.find(id)
	if at >= 0:
		if key != 0:
			_target_key[at] = key
		_target_radius[at] = radius
		_target_layer[at] = layer
		_target_owner[at] = owner
		_target_team[at] = _team_of_target(owner, layer)
		_target_offset[at] = offset
		_max_target_radius = maxf(_max_target_radius, radius)
		return
	if key == 0:
		_minted_keys -= 1
		key = _minted_keys
	_targets.append(node)
	_target_id.append(id)
	_target_key.append(key)
	_target_radius.append(radius)
	_target_layer.append(layer)
	_target_owner.append(owner)
	_target_team.append(_team_of_target(owner, layer))
	_target_pos.append(Vector2.ZERO)
	_target_offset.append(offset)
	_target_next.append(-1)
	_grid_stale = true
	_max_target_radius = maxf(_max_target_radius, radius)


## Give a registered target a new `owner` (see `add_target`): an enemy that casts a staff
## names its actor, so its own shots skip it. Returns false for a node not registered.
func set_target_owner(node: Node2D, owner: int) -> bool:
	if node == null or not is_caster(owner):
		return false
	var at: int = _target_id.find(node.get_instance_id())
	if at < 0:
		return false
	_target_owner[at] = owner
	_target_team[at] = _team_of_target(owner, _target_layer[at])
	return true


func remove_target(node: Node2D) -> void:
	if node == null:
		return
	var at: int = _target_id.find(node.get_instance_id())
	if at < 0:
		return
	if _stepping:
		_target_layer[at] = 0
	else:
		_remove_target_at(at)
		_grid_stale = true


## The body `old` is replaced by `new` for the same actor (the swarm's promotion, the event
## `body_replaced`; Spells passes it on): `old`'s target entry becomes `new`'s in place (its
## order among the targets kept, and its key: the same actor's), so every shot that keeps it (its
## homing target, its memory of what it hit, the body its payload skips: keys, N5) keeps `new`;
## a shot stuck to `old` sticks to `new`. Call it before `new` registers (its `add_target` then
## updates the entry).
func replace_body(old: Node, new: Node) -> void:
	if old == null or new == null or old == new or not new is Node2D:
		return
	var at: int = _target_id.find(old.get_instance_id())
	var to: int = new.get_instance_id()
	if at >= 0 and _target_id.find(to) < 0:
		_targets[at] = new
		_target_id[at] = to
	for slot in _cap:
		var stuck: Variant = _stuck_to[slot]
		if is_instance_valid(stuck) and stuck == old:
			_stuck_to[slot] = new


func get_target_count() -> int:
	return _targets.size()


## Start a projectile for `caster` (an actor id, or Events.NO_PLAYER for no actor) at
## `origin`, moving `velocity` pixels per second for `lifetime` seconds.
## `pierce` is how many targets it passes through before it ends. Returns its
## slot, or -1 for bad arguments or an origin inside a wall.
## `motion` is MOTION_STRAIGHT or MOTION_STILL (then `velocity` is ignored).
## `tag` is stored and sent back with every hit of this projectile. A full cap never refuses: see the class doc.
func spawn(caster: int, origin: Vector2, velocity: Vector2, lifetime: float, radius: float = 4.0, hit_layers: int = LAYER_ENEMY, pierce: int = 0, tag: int = 0, motion: int = MOTION_STRAIGHT) -> int:
	if motion != MOTION_STRAIGHT and motion != MOTION_STILL:
		return -1
	if not is_caster(caster):
		return -1
	if not (lifetime > 0.0) or not origin.is_finite() or not velocity.is_finite():
		return -1
	return _spawn_row(caster, origin, velocity, lifetime, radius, hit_layers, pierce, tag, motion)


## Start a shot that circles `caster`'s anchor (see `set_anchor`) at `orbit_radius`
## pixels, starting at `angle` (radians, 0 = east of the owner) and turning
## `angular_speed` radians a second (negative turns the other way). The other arguments
## are those of `spawn`. Returns its slot, or -1 for bad arguments, NO_PLAYER or a caster
## outside 0 to ACTORS - 1, or a caster with no anchor. With a finite `centre` it circles that point instead (a
## payload's orbit, whose caster is a shot or the point where one ended; `set_caster_shot`
## then makes it follow the shot), and needs no anchor.
func spawn_orbit(caster: int, orbit_radius: float, angle: float, angular_speed: float, lifetime: float, radius: float = 4.0, hit_layers: int = LAYER_ENEMY, pierce: int = 0, tag: int = 0, centre: Vector2 = Vector2.INF) -> int:
	if caster < 0 or caster >= ACTORS or not (centre.is_finite() or _anchors[caster].is_finite()):
		return -1
	if not (lifetime > 0.0) or not is_finite(orbit_radius) or not is_finite(angle) or not is_finite(angular_speed):
		return -1
	var offset: Vector2 = DMath.from_angle(angle) * maxf(orbit_radius, 0.0)
	var around: Vector2 = centre if centre.is_finite() else _anchors[caster]
	var slot: int = _spawn_row(caster, around + offset, Vector2.ZERO, lifetime, radius, hit_layers, pierce, tag, MOTION_ORBIT)
	if centre.is_finite():
		_caster_slot[slot] = CASTER_POINT
		_caster_at[slot] = centre
	_orbit_radius[slot] = maxf(orbit_radius, 0.0)
	_orbit_angle[slot] = angle
	_orbit_speed[slot] = angular_speed
	_join(slot, B_ORBIT)
	_vel[slot] = _orbit_tangent(slot)
	# It is drawn spiralling out from its caster (`_drawn_at`), so its tail starts there.
	_orbit_centre[slot] = around
	_tail_from[slot] = around
	return slot


## Tell the manager where the body of the actor `caster` is, for its orbit shots. Call it
## every physics step before the manager's (the owner of the body does).
func set_anchor(caster: int, position: Vector2) -> void:
	if caster >= 0 and caster < ACTORS and position.is_finite():
		_anchors[caster] = position


## `set_anchor(caster, anchor)` and `clip_to_walls(from, to)` in one call: what every actor's
## caster does every step (performance pass, 2026-10-28). Returns the clipped point.
func place_caster(caster: int, anchor: Vector2, from: Vector2, to: Vector2) -> Vector2:
	if caster >= 0 and caster < ACTORS and anchor.is_finite():
		_anchors[caster] = anchor
	if not _has_walls:
		return to
	var t: float = _wall_hit(from, to)
	return to if t < 0.0 else from.lerp(to, t)


## The body is gone: its orbit shots end at the next step, quietly.
func clear_anchor(caster: int) -> void:
	if caster >= 0 and caster < ACTORS:
		_anchors[caster] = Vector2.INF


## The shot in `slot` was cast by the shot in `caster` (a payload's carrier): an orbit circles
## it and a returning shot flies back to it while it lives, then to where it was last seen.
## Returns false for an empty slot or a caster that is not a live shot.
func set_caster_shot(slot: int, caster: int) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or caster < 0 or caster >= _cap or _alive[caster] == 0 or caster == slot:
		return false
	_caster_slot[slot] = caster
	_caster_seq[slot] = _seq[caster]
	_caster_at[slot] = _pos[caster]
	return true


## The shot in `slot` was cast from a point that does not move (a payload whose carrier is
## gone): an orbit circles it and a returning shot flies back to it.
func set_caster_point(slot: int, point: Vector2) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or not point.is_finite():
		return false
	_caster_slot[slot] = CASTER_POINT
	_caster_at[slot] = point
	return true


## Where the caster of the shot in `slot` is now: its actor's anchor (INF without one), the
## shot that cast it, or a point. INF for an empty slot.
func get_caster_of(slot: int) -> Vector2:
	if slot < 0 or slot >= _cap or _alive[slot] == 0:
		return Vector2.INF
	return _caster_position(slot)


## The slot of the live shot that cast the shot in `slot`, or -1 when its caster is the wizard,
## a point, or a shot that has ended. It still answers for a shot ended by the hit being sent
## (a pull's), until its slot is used again.
func caster_shot_of(slot: int) -> int:
	if slot < 0 or slot >= _cap:
		return -1
	var caster: int = _caster_slot[slot]
	if caster >= 0 and _alive[caster] != 0 and _seq[caster] == _caster_seq[slot]:
		return caster
	return -1


## True when the shot in `slot` was cast by its actor's body (not by another shot or from a
## point). Like `caster_shot_of`, it still answers for a shot ended by the hit being sent.
func is_cast_by_wizard(slot: int) -> bool:
	return slot >= 0 and slot < _cap and _caster_slot[slot] == CASTER_BODY


func _caster_position(slot: int) -> Vector2:
	var caster: int = _caster_slot[slot]
	if caster == CASTER_BODY:
		return _anchors[_actor[slot]] if _actor[slot] >= 0 else Vector2.INF
	if caster >= 0:
		if _alive[caster] != 0 and _seq[caster] == _caster_seq[slot]:
			# Mid-step, a caster shot whose turn in the hit pass has not come is where it was before
			# the step (the passes moved it already; see `step`).
			var state: int = _state[caster]
			_caster_at[slot] = _prev[caster] if _stepping and state != S_DONE and state != S_IDLE else _pos[caster]
		else:
			# The caster is gone: from now on the shot keeps to where it was last seen.
			_caster_slot[slot] = CASTER_POINT
	return _caster_at[slot]


## Move the shot in `slot` by `offset` pixels over `seconds` on top of its own motion (a dash,
## pull or recoil card whose caster is this shot), or at once for `seconds` 0 or less (a
## teleport or swap, stopped short at the first wall). Moves add up, as the wizard's pushes do: a
## new move runs beside the ones under way, each on its own time (two opposite pushes cancel, a
## pull after a recoil gets both). A moving shot still hits what it passes and still ends on a
## wall. A homing move (`turn_rate` above 0) turns toward the nearest
## target within `within` pixels as it goes (`home_velocity`), the same distance in all.
## Returns false for an empty slot, an orbit shot (its caster holds it), or an offset or time
## that is not finite.
func move_shot(slot: int, offset: Vector2, seconds: float, turn_rate: float = 0.0, within: float = 0.0) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or _motion[slot] == MOTION_ORBIT:
		return false
	if not offset.is_finite() or not is_finite(seconds):
		return false
	_threat_step = -1
	if seconds <= 0.0:
		var to: Vector2 = clip_to_walls(_pos[slot], _pos[slot] + offset) if (_flags[slot] & F_GHOST) == 0 else _pos[slot] + offset
		_base[slot] += to - _pos[slot]
		_pos[slot] = to
		_prev[slot] = to
		# A blink leaves no tail across the gap, and sweeps no hits across it: a deferred shot's
		# path before it goes untested (only a hit handler blinks a shot).
		_flags[slot] &= ~F_DEFERRED
		_tail_from[slot] = to
		return true
	if _move_free < 0:
		_grow_moves(_move_left.size() * 2)
	var at: int = _move_free
	_move_free = _move_next[at]
	_move_left[at] = seconds
	_move_vel[at] = offset / seconds
	var homes: bool = turn_rate > 0.0 and within > 0.0 and is_finite(turn_rate) and is_finite(within)
	_move_turn[at] = turn_rate if homes else 0.0
	_move_range[at] = within if homes else 0.0
	_move_home[at] = 0
	# At the end of the list, so the moves run in the order they were asked.
	_move_next[at] = -1
	var last: int = _move_head[slot]
	if last < 0:
		_move_head[slot] = at
	else:
		while _move_next[last] >= 0:
			last = _move_next[last]
		_move_next[last] = at
	_join(slot, B_MOVE)
	return true


## End every move of the shot in `slot` (it is new or it ended).
func _drop_moves(slot: int) -> void:
	var at: int = _move_head[slot]
	while at >= 0:
		var next: int = _move_next[at]
		_move_next[at] = _move_free
		_move_free = at
		at = next
	_move_head[slot] = -1


## Room for `size` moves under way in all (the new entries go on the free list).
func _grow_moves(size: int) -> void:
	var old: int = _move_left.size()
	_move_left.resize(size)
	_move_vel.resize(size)
	_move_turn.resize(size)
	_move_range.resize(size)
	_move_home.resize(size)
	_move_next.resize(size)
	for at in range(size - 1, old - 1, -1):
		_move_next[at] = _move_free
		_move_free = at


## Make the shot in `slot` home on the curve of radius `curve` pixels (`CompiledSpell.homing_curve`:
## the same curve at any speed, faster or slower later too). See `set_homing`.
func set_homing_curve(slot: int, curve: float, within: float) -> bool:
	if not is_finite(curve) or curve < 0.0:
		return false
	return _set_homing(slot, 0.0 if curve == 0.0 else 1.0 / curve, within)


## Make the shot in `slot` home on targets no further than `within` pixels from it: a straight
## shot turns at most `turn_rate` radians a second at the speed it has now, so on that curve
## whatever its speed later (it keeps the radians a pixel flown, `_turn`), a still one (a rune) creeps toward its
## target at SpellLimits.HOMING_DRIFT. Returns false for an empty slot, an orbit shot (held on
## its circle), a rate that is negative or not finite, or a `within` that is not above 0 and
## finite; true when the rate was applied, 0 included (0 stops homing).
func set_homing(slot: int, turn_rate: float, within: float) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or not is_finite(turn_rate) or turn_rate < 0.0:
		return false
	var pace: float = _vel[slot].length()
	# (A still shot creeps at HOMING_DRIFT: any bend above 0 homes it.)
	return _set_homing(slot, turn_rate / pace if pace > 0.0 else turn_rate, within)


## Homing of `bend` radians a pixel flown (see `set_homing`).
func _set_homing(slot: int, bend: float, within: float) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or _motion[slot] == MOTION_ORBIT:
		return false
	if not is_finite(bend) or bend < 0.0 or not is_finite(within) or within <= 0.0:
		return false
	_turn[slot] = bend
	_home_range[slot] = within
	_home_target[slot] = 0
	_home_at[slot] = Vector2.INF
	if bend > 0.0:
		_join(slot, B_HOMING)
	else:
		_leave(slot, B_HOMING)
	return true


## Give the shot in `slot` the colour of its core: the element's tint (`CompiledSpell.tint`).
## A plain shot keeps white. Returns false for an empty slot or a colour that is not finite.
func set_core(slot: int, color: Color) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0:
		return false
	if not (is_finite(color.r) and is_finite(color.g) and is_finite(color.b)):
		return false
	_core[slot] = Color(color.r, color.g, color.b, 1.0)
	return true


## `set_core`, `set_look`, `set_form` and `set_light` for each of the first `count` shots in
## `slots` (-1 for none), from what one launch's shots share (`launch`, a `LaunchLook`), checked once.
func set_looks(slots: PackedInt32Array, count: int, launch: LaunchLook) -> void:
	var intensity: float = clean_light(launch.light_intensity, LIGHT_INTENSITY_MIN)
	var reach: float = clean_light(launch.light_reach, LIGHT_REACH_MIN)
	var color: Color = launch.core
	var look: int = launch.look
	var form: StringName = launch.form
	var core_ok: bool = is_finite(color.r) and is_finite(color.g) and is_finite(color.b)
	var core: Color = Color(color.r, color.g, color.b, 1.0)
	var look_ok: bool = look >= 0 and look < 1 << (LOOK_COUNT - 1)
	var kind: int = clampi(launch.body, 0, _body_shaders.size())
	for n in count:
		var slot: int = slots[n]
		if slot < 0 or slot >= _cap or _alive[slot] == 0:
			continue
		if core_ok:
			_core[slot] = core
		if look_ok:
			_look[slot] = look
		_form_id[slot] = form
		_set_body(slot, kind)
		_look_light_intensity[slot] = intensity
		_look_light_reach[slot] = reach


## How bright (`intensity`) and how far (`reach`) the shot in `slot` lights the room, each times the
## shot light's own (1 as a plain shot; its card's `look_light_intensity` and `look_light_reach`),
## kept in LIGHT_INTENSITY_MIN to LIGHT_MAX and LIGHT_REACH_MIN to LIGHT_MAX. False for an empty slot.
func set_light(slot: int, intensity: float, reach: float) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0:
		return false
	_look_light_intensity[slot] = clean_light(intensity, LIGHT_INTENSITY_MIN)
	_look_light_reach[slot] = clean_light(reach, LIGHT_REACH_MIN)
	return true


## A light multiplier kept in `least` to LIGHT_MAX (1 for one that is not a number).
static func clean_light(value: float, least: float) -> float:
	return clampf(value, least, LIGHT_MAX) if is_finite(value) else 1.0


## Slot `slot`'s card body is `body` now: drawn again from its batch on (`_remember_drawn`), since
## the batch it draws in follows its body.
func _set_body(slot: int, body: int) -> void:
	if _body[slot] != body:
		_body[slot] = body
		_drawn_seq[slot] = -1


## Give the shot in `slot` its look, packed by `pack_look` (0 for none): the particles it gives
## off and what its head shows (`shot_head.gdshader`). Returns false for an empty slot or a look with a
## bit for a kind that does not exist.
func set_look(slot: int, look: int) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or look < 0 or look >= 1 << (LOOK_COUNT - 1):
		return false
	_look[slot] = look
	return true


## Name the card the shot in `slot` is (`form`: its impacts are told as it, `impact_form`) and the
## body it asks for (`body`: a card body `register_body` numbered, 0 for its motion's own; a shot
## draws it only while its motion is written as the body's mesh). False for an empty slot.
func set_form(slot: int, form: StringName, body: int = 0) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0:
		return false
	_form_id[slot] = form
	_set_body(slot, clampi(body, 0, _body_shaders.size()))
	return true


## The packed look of the shot in `slot`, 0 for an empty slot or a plain shot.
func get_look_of(slot: int) -> int:
	if slot < 0 or slot >= _cap or _alive[slot] == 0:
		return 0
	return _look[slot]


## Pack layer kinds (LOOK_*) into one int for `set_look`: bit `kind - 1` for each kind, so
## any number of cards combine and a kind brought twice shows once. LOOK_NONE and unknown
## kinds are skipped.
static func pack_look(kinds: PackedInt32Array) -> int:
	var look: int = 0
	for kind in kinds:
		if kind > LOOK_NONE and kind < LOOK_COUNT:
			look |= 1 << (kind - 1)
	return look


## True when the packed `look` has `kind`.
static func look_has(look: int, kind: int) -> bool:
	return kind > LOOK_NONE and kind < LOOK_COUNT and (look >> (kind - 1)) & 1 == 1


## The core colour of the shot in `slot`, white for an empty slot or a plain shot.
func get_core_of(slot: int) -> Color:
	if slot < 0 or slot >= _cap or _alive[slot] == 0:
		return Color.WHITE
	return _core[slot]


# --- Behaviours of the projectile kit (staffs B1) -------------------------------------
# Each setter takes the slot `spawn` returned, right after spawning, and returns false (and
# does nothing) for an empty slot, a bad number, or a shot that cannot do it (rules R4h): what
# turns or steers a flight (bounce, ghost, return) needs a straight shot; what changes a motion
# (linger, spiral, sticky) needs a shot that moves, an orbit too; homing any shot but an orbit
# (a rune creeps, R4i); growth takes any shot.

func _is_flyer(slot: int) -> bool:
	return slot >= 0 and slot < _cap and _alive[slot] != 0 and _motion[slot] == MOTION_STRAIGHT


## A live shot that moves: a straight shot or an orbit (a still shot does not move).
func _moves(slot: int) -> bool:
	return slot >= 0 and slot < _cap and _alive[slot] != 0 and _motion[slot] != MOTION_STILL


## The shot bounces off walls `times` times instead of ending on the first (a bounce may hit
## what it hit before; the impact is shown each time).
func set_bounce(slot: int, times: int) -> bool:
	if not _is_flyer(slot) or times < 0:
		return false
	_bounce[slot] = times
	return true


## The shot ignores walls: it neither ends nor bounces on one.
func set_ghost(slot: int) -> bool:
	if not _is_flyer(slot):
		return false
	_flags[slot] |= F_GHOST
	return true


## The shot weaves a sine wave `width` pixels wide (SPIRAL_PERIOD seconds a wave) round its path:
## a flying shot round its straight line, an orbit shot in and out round its circle (`_pass_orbit`).
func set_spiral(slot: int, width: float) -> bool:
	if not _moves(slot) or not (width > 0.0) or not is_finite(width):
		return false
	_wave[slot] = width * 0.5
	_flags[slot] |= F_WAVE
	if _motion[slot] == MOTION_STRAIGHT:
		_join(slot, B_SPIRAL)
	return true


## The shot flies out for half its life, then back to its owner's anchor, hitting again on
## the way; it ends (as an expiry) when it gets there.
func set_return(slot: int) -> bool:
	if not _is_flyer(slot):
		return false
	_flags[slot] |= F_RETURN
	_join(slot, B_RETURN)
	return true


## The shot stops for `seconds` when half its life is gone, then goes on: a flying shot hangs in
## mid-air, an orbit shot stops circling (it keeps to its caster).
func set_linger(slot: int, seconds: float) -> bool:
	if not _moves(slot) or not (seconds > 0.0) or not is_finite(seconds):
		return false
	_linger[slot] = seconds
	_join(slot, B_LINGER)
	return true


## The shot's radius grows by `factor` each second it lives, until it is as big as the room
## (`set_bounds`; nothing is bigger): a wider hit circle (a rune's trigger circle), the same damage. `get_growth_of` tells how much bigger it is.
func set_growth(slot: int, factor: float) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or not (factor > 1.0) or not is_finite(factor):
		return false
	_growth[slot] = factor
	_join(slot, B_GROWTH)
	return true


## The shot's speed changes over its life (speed over life, a card's `speed_start`, `speed_end` and
## `speed_ease`): it leaves at `start` times its speed now and goes to `end` times it as its life runs
## out, `start + (end - start) x (1 - (life left / its life) ^ ease)`: with an ease above 1 most of
## the change comes early (every spell shot's default, SpellLimits.SHOT_SPEED_*: start 2.2, end 0.2, ease 1.5),
## below 1 late. Homing and spiral turn and weave the speed it has; a deflect speeds the whole curve
## up and starts it again with its life. Only a shot that flies; false otherwise, or for bad numbers.
## `start` above SPEED_START_MOST counts as SPEED_START_MOST.
func set_speed_curve(slot: int, start: float, end: float, ease_power: float) -> bool:
	if not _is_flyer(slot) or not (start > 0.0) or not (end >= 0.0) or not (ease_power > 0.0):
		return false
	if not is_finite(start) or not is_finite(end) or not is_finite(ease_power):
		return false
	_curve_from[slot] = minf(start, SPEED_START_MOST)
	_curve_to[slot] = minf(end, SPEED_START_MOST)
	_curve_ease[slot] = ease_power
	_curve_speed[slot] = _vel[slot].length()
	_vel[slot] = _vel[slot] * _curve_from[slot]
	_join(slot, B_CURVE)
	return true


## How many times bigger the shot in `slot` is than when it started (1.0 for a plain shot).
func get_growth_of(slot: int) -> float:
	# The shot whose hit is being sent counts even when that hit spent it (it is gone already).
	if slot < 0 or slot >= _cap or (_alive[slot] == 0 and slot != _event_slot) or _radius0[slot] <= 0.0:
		return 1.0
	return _radius[slot] / _radius0[slot]


## The shot sticks to the first target it hits for `seconds`, then ends there (an expiry); an
## orbit shot leaves its circle for it. The hit is sent as usual, and a stuck shot hits nothing more.
func set_sticky(slot: int, seconds: float) -> bool:
	if not _moves(slot) or not (seconds > 0.0) or not is_finite(seconds):
		return false
	_stick[slot] = seconds
	return true


## The shot stops `charges` shots of other teams that touch it (each costs one charge and sends
## `shot_blocked`). A zero or negative count takes the shield away. A shot of no actor has none.
func set_shield(slot: int, charges: int) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or _actor[slot] < 0:
		return false
	_shield[slot] = maxi(charges, 0)
	if charges > 0:
		_join(slot, B_SHIELD)
	else:
		_leave(slot, B_SHIELD)
	return true


## How many shield charges the shot in `slot` has left.
func get_shield_of(slot: int) -> int:
	return _shield[slot] if slot >= 0 and slot < _cap and _alive[slot] != 0 else 0


## The shots that guard now (a shield or a deflect: `set_shield`, `set_deflect`): how many, and the
## slot of the `n`th, in no order (for looks, read in one pass: Feel draws a shield's shell).
func guarded_count() -> int:
	return _member_count[B_SHIELD]


func guarded_slot(n: int) -> int:
	return _members[B_SHIELD * _cap + n] if n >= 0 and n < _member_count[B_SHIELD] else -1


## Half of a solid shot's row (`set_solid`: from its middle to its end stone's centre, along it),
## zero for any other shot (for looks: a wall's shell is a capsule round its row).
func get_solid_half_of(slot: int) -> Vector2:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or not _solids.has(slot):
		return Vector2.ZERO
	return _solid_half(slot, _solids[slot])


## The shot turns every shot of another team that touches it and makes it its caster's
## (`deflect_shot`; melee I3), as many as touch it while it lives. Deflect goes before a shield
## (owner, 2026-10-29): a touching shot is turned, and the shield keeps its charge. A shot of no
## actor has none.
func set_deflect(slot: int, on: bool) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or _actor[slot] < 0:
		return false
	_deflect[slot] = 1 if on else 0
	if on:
		_join(slot, B_SHIELD)
	elif _shield[slot] <= 0:
		_leave(slot, B_SHIELD)
	return true


func is_deflecting(slot: int) -> bool:
	return slot >= 0 and slot < _cap and _alive[slot] != 0 and _deflect[slot] != 0


## Deflects the shot in `slot` (melee I3; docs/milestones/M2-staffs.md, "Deflect"): it turns off
## what touched it, `normal` the way out from that at the touch (a shot coming in along it is
## mirrored; one already going out keeps its way), flies `SpellLimits.DEFLECT_SPEEDUP` times
## faster (each deflect again: a rally speeds up) and its life starts again, and it becomes the
## actor `by`'s: its team, ramp, budget and hit credit, and a homing or returning shot hunts or
## comes back for its new caster. An orbiting shot leaves its circle and flies straight on. It
## keeps its own cards (its tag: damage, infusions, payloads), may hit what it hit before, and
## `shot_deflected(by, where, by_tag)` is sent. False when there is no such shot or `by` is no
## actor.
func deflect_shot(slot: int, by: int, normal: Vector2, by_tag: int) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or by < 0 or not normal.is_finite():
		return false
	_threat_step = -1
	var out: Vector2 = normal.normalized() if not normal.is_zero_approx() else Vector2.ZERO
	if _motion[slot] == MOTION_ORBIT:
		_vel[slot] = _orbit_tangent(slot)
		_motion[slot] = MOTION_STRAIGHT
		_leave(slot, B_ORBIT)
	var velocity: Vector2 = _vel[slot]
	if out != Vector2.ZERO and velocity.dot(out) < 0.0:
		velocity -= 2.0 * velocity.dot(out) * out
	_vel[slot] = velocity * SpellLimits.DEFLECT_SPEEDUP
	_speed[slot] *= SpellLimits.DEFLECT_SPEEDUP
	_curve_speed[slot] *= SpellLimits.DEFLECT_SPEEDUP
	_base[slot] = _pos[slot]
	_life[slot] = _span[slot]
	_actor[slot] = by
	var table: ActorsScript = actors if actors != null else _auto_actors
	if table == null or not is_instance_valid(table):
		table = actor_table()
	var budget: int = ActorsScript.SHARED
	if table != null and table.is_open(by):
		_team[slot] = table.team_of(by)
		_ramp[slot] = table.ramp_of(by)
		budget = table.budget_of(by)
	else:
		_team[slot] = ActorsScript.NONE
		_ramp[slot] = ActorsScript.NONE
	_owned[_budget[slot]] -= 1
	_budget[slot] = budget
	_owned[budget] += 1
	_caster_slot[slot] = CASTER_BODY
	_home_target[slot] = 0
	_home_at[slot] = Vector2.INF
	_skip_on[slot] = 0.0
	_skip_near[slot] = 0.0
	_forget_all(slot)
	# Its colours are its new caster's: work its look out again.
	_drawn_seq[slot] = -1
	if events != null:
		var outer_slot: int = _event_slot
		_event_slot = slot
		events.shot_deflected.emit(by, _pos[slot], by_tag, slot)
		_event_slot = outer_slot
	return true


## Stops the shot in `slot` as a shield charge does (`shot_blocked(by, where, by_tag)`), for a
## carrier that is no shot (a swing, a beam, a slam, a decoy). `form` is that carrier's id,
## told to looks as `impact_form` while the event is sent: a swing's block is a parry (melee I5).
## The blocker is no shot, so the event's `shot` is -1, whatever event it is sent inside of.
## False when there is no such shot.
func block_shot(slot: int, by: int, by_tag: int, form: StringName = &"") -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0:
		return false
	var at: Vector2 = _pos[slot]
	_end_tail(slot, at)
	_kill(slot)
	if events != null:
		var outer_form: StringName = impact_form
		var outer_slot: int = _event_slot
		impact_form = form
		_event_slot = -1
		events.shot_blocked.emit(by, at, by_tag, -1)
		_event_slot = outer_slot
		impact_form = outer_form
	return true


## The shots of another team than the actor `caster`'s (a shot of no actor included, as a shield
## has it) whose circle reaches into the wedge round `origin` from `from_angle` to `to_angle`
## radians off `direction` (`side` as `sweep`), out to `reach`: a swing's guard (melee I3). Fills
## `guard_slots` and returns how many. `ahead` seconds: also where each shot will be by then, so a
## parry meets a fast shot (an atom) that would otherwise go from outside the wedge into the body
## behind it in one step. Allocation-free once the list has grown.
func shots_in_wedge(caster: int, origin: Vector2, direction: Vector2, side: int, from_angle: float, to_angle: float, reach: float, ahead: float = 0.0) -> int:
	if not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx() or not (reach > 0.0) or to_angle < from_angle:
		return 0
	var mine: int = _team_now(caster)
	var base: float = DMath.angle(direction)
	var turn: float = 1.0 if side >= 0 else -1.0
	var found: int = 0
	for slot in _high:
		if _alive[slot] == 0 or _team[slot] == mine:
			continue
		var radius: float = _radius[slot]
		# Along its last step (and its next `ahead`), so a small fast shot (an atom) does not slip
		# past between steps.
		var flies: bool = ahead > 0.0 and _state[slot] != S_STUCK and _state[slot] != S_FROZEN and _state[slot] != S_HELD
		var next: Vector2 = _pos[slot] + _vel[slot] * ahead if flies else _pos[slot]
		var later: int = _guard_samples_on(_pos[slot], next, radius) if next != _pos[slot] else 0
		var samples: int = _guard_samples(slot)
		for k in samples + later:
			var to: Vector2 = (_guard_point(slot, k, samples) if k < samples else _pos[slot].lerp(next, float(k - samples + 1) / float(later))) - origin
			var distance: float = to.length()
			if distance > reach + radius:
				continue
			var width: float = PI if distance <= radius else DMath.asin(radius / distance)
			var local: float = angle_difference(base, DMath.angle(to)) * turn
			if local + width >= from_angle and local - width <= to_angle:
				found = _guard_add(found, slot)
				break
	return found


## The shots of another team than `caster`'s whose circle touches the segment from `a` to `b`
## widened by `width` each side: a beam's guard (melee I3). Fills `guard_slots`, after the first
## `first` already there, and returns how many there are in all.
func shots_on_segment(caster: int, a: Vector2, b: Vector2, width: float, first: int = 0) -> int:
	if not a.is_finite() or not b.is_finite():
		return first
	var mine: int = _team_now(caster)
	var found: int = first
	for slot in _high:
		if _alive[slot] == 0 or _team[slot] == mine or _guard_has(found, slot):
			continue
		var reach: float = width + _radius[slot]
		var samples: int = _guard_samples(slot)
		for k in samples:
			var at: Vector2 = _guard_point(slot, k, samples)
			if Geometry2D.get_closest_point_to_segment(at, a, b).distance_squared_to(at) <= reach * reach:
				found = _guard_add(found, slot)
				break
	return found


## The shot of another team than `team` that will come within `radius` of `point` soonest, within
## `horizon` seconds: what an AI dodges (enemy AI AI3, docs/milestones/M2-enemy-ai.md). Returns
## the seconds until it gets there (0 for one already there, a still shot standing on the point
## included), or -1.0 for none; `threat_slot` is its slot and `threat_away` the unit way off its
## line on the side `point` already is (away from a still one). The shots of `own` (an actor id,
## -1 for none) are skipped, as they pass their caster. Straight shots move on their velocity; an
## orbit is skipped (it circles its caster). Of two shots that get there at the same moment, the
## lower slot is the one. Allocation-free; an AI asks on its reaction timer, not every step.
##
## Many AIs ask in one step, so with THREAT_GRID_FROM shots or more, once a step (or the one before
## it) has THREAT_GRID_ASKS asks, an ask builds the threat grid (performance, 2026-11-02: one pass
## over 3,000 shots was 1.4 ms an ask, about 10 ms a step for 200 enemies): each shot is filed
## under the cells of the box round its path for the horizon, widened by its radius, and an ask
## tries only the shots filed under the cells its own circle's box touches, with the same exact test. So it finds what one pass over every
## shot finds. A spawn, a deflection or a card's move throws the grid away (they change a path
## between steps); a longer horizon than the grid's builds it again.
func threat(point: Vector2, radius: float, team: int, own: int = -1, horizon: float = 1.0) -> float:
	threat_slot = -1
	threat_away = Vector2.ZERO
	if not point.is_finite() or not (radius > 0.0):
		return -1.0
	var best: float = INF
	if _threat_ask_step != _step_index:
		_threat_asks_before = _threat_asks if _threat_ask_step == _step_index - 1 else 0
		_threat_asks = 0
		_threat_ask_step = _step_index
	_threat_asks += 1
	if _count < THREAT_GRID_FROM or (_threat_step != _step_index and _threat_asks < THREAT_GRID_ASKS and _threat_asks_before < THREAT_GRID_ASKS):
		if _kernel != null:
			return _kernel.call(&"threat_scan", self, point, radius, team, own, horizon)
		# `_threat_try` written out: a call a shot costs a third more over 3,000 shots.
		var best_away: Vector2 = Vector2.ZERO
		for slot in _high:
			if _alive[slot] == 0 or (_team[slot] == team and team != ActorsScript.NONE) or (_actor[slot] == own and own >= 0):
				continue
			if _motion[slot] == MOTION_ORBIT:
				continue
			var reach: float = radius + _radius[slot]
			var rel: Vector2 = point - _pos[slot]
			var vel: Vector2 = _vel[slot]
			var state: int = _state[slot]
			var still: bool = _motion[slot] == MOTION_STILL or state == S_STUCK or state == S_FROZEN or state == S_HELD or vel.length_squared() < 1.0
			var when: float = -1.0
			if rel.length_squared() <= reach * reach:
				when = 0.0
			elif not still:
				var along: float = rel.dot(vel) / vel.length_squared()
				if along <= 0.0 or along > minf(horizon, _life[slot]):
					continue
				if (rel - vel * along).length_squared() > reach * reach:
					continue
				when = along
			# Slots run upward, so of two as soon the first one stays.
			if when < 0.0 or when >= best:
				continue
			best = when
			threat_slot = slot
			if still:
				best_away = rel.normalized() if rel != Vector2.ZERO else Vector2.RIGHT
			else:
				var side: Vector2 = rel - vel * (rel.dot(vel) / vel.length_squared())
				best_away = side.normalized() if side.length_squared() > 0.01 else vel.orthogonal().normalized()
		threat_away = best_away
		return best if threat_slot >= 0 else -1.0
	if _threat_step != _step_index or horizon > _threat_horizon:
		_build_threat_grid(horizon)
	if _kernel != null:
		return _kernel.call(&"threat_query", self, point, radius, team, own, horizon)
	_threat_stamp += 1
	var stamp: int = _threat_stamp
	for n in _threat_over_count:
		best = _threat_try(_threat_over[n], point, radius, team, own, horizon, best)
	var size: float = _threat_cell
	var x0: int = clampi(floori((point.x - radius - _threat_x) / size), 0, _threat_w - 1)
	var x1: int = clampi(floori((point.x + radius - _threat_x) / size), 0, _threat_w - 1)
	var y0: int = clampi(floori((point.y - radius - _threat_y) / size), 0, _threat_h - 1)
	var y1: int = clampi(floori((point.y + radius - _threat_y) / size), 0, _threat_h - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var entry: int = _threat_head[y * _threat_w + x]
			while entry >= 0:
				var slot: int = _threat_slot[entry]
				entry = _threat_next[entry]
				if _threat_seen[slot] == stamp:
					continue
				_threat_seen[slot] = stamp
				best = _threat_try(slot, point, radius, team, own, horizon, best)
	return best if threat_slot >= 0 else -1.0


## `threat`'s exact test of the shot in `slot`: when it comes within `radius` (plus its own) of
## `point`, if sooner than `best` (or as soon, from a lower slot); then it becomes `threat_slot`
## and `threat_away` its way off. Returns the new best.
func _threat_try(slot: int, point: Vector2, radius: float, team: int, own: int, horizon: float, best: float) -> float:
	if _alive[slot] == 0 or (_team[slot] == team and team != ActorsScript.NONE) or (_actor[slot] == own and own >= 0):
		return best
	if _motion[slot] == MOTION_ORBIT:
		return best
	var reach: float = radius + _radius[slot]
	var rel: Vector2 = point - _pos[slot]
	var vel: Vector2 = _vel[slot]
	var state: int = _state[slot]
	var still: bool = _motion[slot] == MOTION_STILL or state == S_STUCK or state == S_FROZEN or state == S_HELD or vel.length_squared() < 1.0
	var when: float = -1.0
	if rel.length_squared() <= reach * reach:
		when = 0.0
	elif not still:
		var speed2: float = vel.length_squared()
		var along: float = rel.dot(vel) / speed2
		if along <= 0.0 or along > minf(horizon, _life[slot]):
			return best
		if (rel - vel * along).length_squared() > reach * reach:
			return best
		when = along
	if when < 0.0 or when > best or (when == best and slot > threat_slot):
		return best
	threat_slot = slot
	if still:
		threat_away = rel.normalized() if rel != Vector2.ZERO else Vector2.RIGHT
	else:
		var side: Vector2 = rel - vel * (rel.dot(vel) / vel.length_squared())
		threat_away = side.normalized() if side.length_squared() > 0.01 else vel.orthogonal().normalized()
	return when


## File every live shot that `threat` could find under the cells of its path's box for `horizon`
## seconds (see `threat`), in one pass: each cell's list grows at its head. Its cells cover the
## bounds, THREAT_CELL wide or wider so there are at most THREAT_GRID_MAX a side; a path is clamped
## to them (a query outside is clamped the same way, so nothing it could meet is missed).
func _build_threat_grid(horizon: float) -> void:
	_threat_step = _step_index
	_threat_horizon = horizon
	var size: float = maxf(THREAT_CELL, maxf(_bounds.size.x, _bounds.size.y) / float(THREAT_GRID_MAX))
	_threat_cell = size
	_threat_x = _bounds.position.x
	_threat_y = _bounds.position.y
	_threat_w = clampi(ceili(_bounds.size.x / size), 1, THREAT_GRID_MAX)
	_threat_h = clampi(ceili(_bounds.size.y / size), 1, THREAT_GRID_MAX)
	var cells: int = _threat_w * _threat_h
	if _threat_head.size() < cells:
		_threat_head.resize(cells)
	if _threat_seen.size() < _cap:
		_threat_seen.resize(_cap)
		_threat_seen.fill(0)
		_threat_over.resize(_cap)
	if _threat_slot.size() < _cap * 4:
		_threat_slot.resize(_cap * 4)
		_threat_next.resize(_cap * 4)
	# The native kernel fills it when its entries fit (they nearly always do).
	if _kernel != null and _kernel.call(&"threat_fill", self, horizon) >= 0:
		return
	_threat_head.fill(-1)
	_threat_over_count = 0
	var room: int = _threat_slot.size()
	var used: int = 0
	var w: int = _threat_w
	var w1: int = w - 1
	var h1: int = _threat_h - 1
	var x_at: float = _threat_x
	var y_at: float = _threat_y
	for slot in _high:
		if _alive[slot] == 0 or _motion[slot] == MOTION_ORBIT:
			continue
		var at: Vector2 = _pos[slot]
		var to: Vector2 = at
		var state: int = _state[slot]
		if _motion[slot] != MOTION_STILL and state != S_STUCK and state != S_FROZEN and state != S_HELD:
			to = at + _vel[slot] * minf(horizon, maxf(_life[slot], 0.0))
		var r: float = _radius[slot]
		var x0: int = clampi(floori((minf(at.x, to.x) - r - x_at) / size), 0, w1)
		var x1: int = clampi(floori((maxf(at.x, to.x) + r - x_at) / size), 0, w1)
		var y0: int = clampi(floori((minf(at.y, to.y) - r - y_at) / size), 0, h1)
		var y1: int = clampi(floori((maxf(at.y, to.y) + r - y_at) / size), 0, h1)
		var span: int = (x1 - x0 + 1) * (y1 - y0 + 1)
		if span > THREAT_SPAN_MAX:
			_threat_over[_threat_over_count] = slot
			_threat_over_count += 1
			continue
		if used + span > room:
			room = maxi(room * 2, used + span)
			_threat_slot.resize(room)
			_threat_next.resize(room)
		for y in range(y0, y1 + 1):
			var row: int = y * w
			for x in range(x0, x1 + 1):
				_threat_slot[used] = slot
				_threat_next[used] = _threat_head[row + x]
				_threat_head[row + x] = used
				used += 1


## How many points of its last step a guard tests a shot at: one for a shot that moves less than
## its own width a step, else one every width (at most GUARD_PATH_SAMPLES), so a small fast shot
## (an atom: 1.5 px, 18 px a step) cannot pass a swing or a beam between two steps.
func _guard_samples(slot: int) -> int:
	return maxi(_guard_samples_on(_prev[slot], _pos[slot], _radius[slot]), 1)


## The points one every width of a shot of `radius` from `a` to `b` takes (at least 1, at most
## GUARD_PATH_SAMPLES).
func _guard_samples_on(a: Vector2, b: Vector2, radius: float) -> int:
	var step: float = a.distance_to(b)
	var width: float = maxf(radius * 2.0, 1.0)
	return 1 if step <= width else mini(ceili(step / width), GUARD_PATH_SAMPLES)


## Point `k` of `samples` along the shot's last step, from where it is now (k 0) back toward where
## it was (that point itself was tested on the step before).
func _guard_point(slot: int, k: int, samples: int) -> Vector2:
	return _pos[slot].lerp(_prev[slot], float(k) / float(samples))


func _guard_has(found: int, slot: int) -> bool:
	for n in found:
		if guard_slots[n] == slot:
			return true
	return false


func _guard_add(found: int, slot: int) -> int:
	if found == guard_slots.size():
		guard_slots.resize(maxi(found * 2, 8))
	guard_slots[found] = slot
	return found + 1


## The team of the actor `caster` now (NONE for no open actor), as `_spawn_row` reads it.
func _team_now(caster: int) -> int:
	var table: ActorsScript = actors if actors != null else _auto_actors
	if table == null or not is_instance_valid(table):
		table = actor_table()
	return table.team_of(caster) if table != null and table.is_open(caster) else ActorsScript.NONE


func _spawn_row(caster: int, origin: Vector2, velocity: Vector2, lifetime: float, radius: float, hit_layers: int, pierce: int, tag: int, motion: int) -> int:
	# An orbit shot is held by its caster and ignores walls. One born in a solid shot's row is
	# made: it ends on that wall at its first step, unless the wall cast it (`_own_solid`).
	if motion != MOTION_ORBIT and _has_walls and (_cell_at(origin) & ROOM_CELL) != 0:
		# Born inside a room wall it would end in the next step: count it as ended, but
		# take no pool slot (at the cap that would evict another shot).
		# No shot existed, so no impact is shown (the staff tip is inside the wall).
		wall_hits += 1
		return -1
	if _free_count == 0:
		_drop_one()
	_free_count -= 1
	var slot: int = _free_slots[_free_count]
	# What the actor table says of the caster now; the shot keeps it for its life. A caster that
	# is no open actor has no team, the enemy ramp and the shared budget.
	var table: ActorsScript = actors if actors != null else _auto_actors
	if table == null or not is_instance_valid(table):
		table = actor_table()
	if table != null and table.is_open(caster):
		_write_row(slot, caster, origin, velocity, lifetime, radius, hit_layers, pierce, tag, motion, table.team_of(caster), table.ramp_of(caster), table.budget_of(caster))
	else:
		_write_row(slot, caster, origin, velocity, lifetime, radius, hit_layers, pierce, tag, motion, ActorsScript.NONE, ActorsScript.NONE, ActorsScript.SHARED)
	return slot


## Whether the pool has a free slot for each of `count` new shots (`spawn_batch` makes them then).
func has_room_for(count: int) -> bool:
	return count <= _free_count


## Straight shots of one launch at once (a nova's ring, a fan): `velocities.size()` of them, as
## `spawn` with each velocity in turn would make them, their slots written to `slots` (sized by
## the caller, at least as long; -1 for one not made). Returns how many it handled: every one, or
## -1 when it made none because the pool has no free slot for each (at the cap a spawn drops
## another shot, which could be one of these not yet set up by the caller: spawn them one by one
## then, each set up before the next). The caster's team, ramp and budget are read once.
func spawn_batch(caster: int, origin: Vector2, velocities: PackedVector2Array, lifetime: float, radius: float, hit_layers: int, pierce: int, tag: int, slots: PackedInt32Array) -> int:
	var count: int = velocities.size()
	if not is_caster(caster) or not (lifetime > 0.0) or not origin.is_finite() or slots.size() < count:
		return -1
	if count > _free_count:
		return -1
	if _has_walls and (_cell_at(origin) & ROOM_CELL) != 0:
		# Born inside a room wall, as `_spawn_row`: each counts as ended, none takes a slot.
		wall_hits += count
		for n in count:
			slots[n] = -1
		return count
	var table: ActorsScript = actors if actors != null else _auto_actors
	if table == null or not is_instance_valid(table):
		table = actor_table()
	var team: int = ActorsScript.NONE
	var ramp: int = ActorsScript.NONE
	var budget: int = ActorsScript.SHARED
	if table != null and table.is_open(caster):
		team = table.team_of(caster)
		ramp = table.ramp_of(caster)
		budget = table.budget_of(caster)
	for n in count:
		var velocity: Vector2 = velocities[n]
		if not velocity.is_finite():
			slots[n] = -1
			continue
		_free_count -= 1
		var slot: int = _free_slots[_free_count]
		_write_row(slot, caster, origin, velocity, lifetime, radius, hit_layers, pierce, tag, MOTION_STRAIGHT, team, ramp, budget)
		slots[n] = slot
	return count


## Write a new shot into the free `slot` (taken off the free list by the caller), with the
## caster's `team`, `ramp` and `budget` as the actor table gave them.
func _write_row(slot: int, caster: int, origin: Vector2, velocity: Vector2, lifetime: float, radius: float, hit_layers: int, pierce: int, tag: int, motion: int, team: int, ramp: int, budget: int) -> void:
	_pos[slot] = origin
	_prev[slot] = origin
	_vel[slot] = velocity if motion == MOTION_STRAIGHT else Vector2.ZERO
	_motion[slot] = motion
	_body[slot] = 0
	_look_light_intensity[slot] = 1.0
	_look_light_reach[slot] = 1.0
	_form_id[slot] = &""
	_turn[slot] = 0.0
	_home_at[slot] = Vector2.INF
	_home_range[slot] = 0.0
	_home_target[slot] = 0
	_life[slot] = lifetime
	_radius[slot] = maxf(radius, 0.0)
	_actor[slot] = caster
	_team[slot] = team
	_ramp[slot] = ramp
	_budget[slot] = budget
	_layers[slot] = hit_layers | ACTOR_LAYERS
	_pierce[slot] = maxi(pierce, 0)
	_tag[slot] = tag
	_core[slot] = Color.WHITE
	_look[slot] = 0
	_born[slot] = sim_time
	_seq[slot] = _next_seq
	_next_seq += 1
	# Its tail (with the tails off) starts where it does, from a phase of its own.
	_tail_from[slot] = origin
	_tail_carry[slot] = TAIL_SPACING * tail_hash(_seq[slot], -1)
	_tail_n[slot] = 0
	_join_group(slot, group_of(caster, tag))
	_skip_on[slot] = 0.0
	_skip_near[slot] = 0.0
	_flags[slot] = 0
	_bounce[slot] = 0
	_shield[slot] = 0
	_deflect[slot] = 0
	_span[slot] = lifetime
	_radius0[slot] = maxf(radius, 0.0)
	_growth[slot] = 1.0
	_curve_from[slot] = 1.0
	_curve_to[slot] = 1.0
	_curve_ease[slot] = 1.0
	_curve_speed[slot] = 0.0
	_wave[slot] = 0.0
	_wave_age[slot] = 0.0
	_linger[slot] = 0.0
	_hold[slot] = -1.0
	_freeze[slot] = 0.0
	_stick[slot] = 0.0
	_stuck_to[slot] = null
	_base[slot] = origin
	_caster_slot[slot] = CASTER_BODY
	_caster_at[slot] = Vector2.INF
	_drop_moves(slot)
	_forget_all(slot)
	_orbit_centre[slot] = Vector2.INF
	_threat_step = -1
	_state[slot] = S_IDLE
	_alive[slot] = 1
	_count += 1
	var owner_index: int = _budget[slot]
	_owned[owner_index] += 1
	_own_prev[slot] = _own_tail[owner_index]
	_own_next[slot] = -1
	if _own_tail[owner_index] >= 0:
		_own_next[_own_tail[owner_index]] = slot
	else:
		_own_head[owner_index] = slot
	_own_tail[owner_index] = slot
	if slot >= _high:
		_high = slot + 1


## Move every projectile by `delta` seconds, find hits and send the events.
##
## The step runs in passes (shots stepped by behaviour, 2026-10-28), so each loop is short and only
## visits the shots it has work for:
## 1. `_pass_common`: every live shot's life runs down (a shot whose life ran out is marked to
##    expire) and every straight shot flies straight on along its velocity.
## 2. One pass per behaviour, in the order of BEHAVIOUR_PASSES, over the list of the shots that have
##    it (see "Shot behaviours" below): each changes what the common pass did for its shots (a
##    homing shot turns and flies on along its new velocity, a lingering one stays where it was).
##    No pass sends an event: a shot that ends there (back at its caster, its anchor gone) is only
##    marked, and ends in the hit pass.
## 3. `_pass_hits`, over every shot in the order the step always took (from where the last step's
##    hit-work budget ran out): it sends the ends marked above, then cuts each path at the walls,
##    tests it for hits and sends those events. So every event is sent in the same order as when
##    each shot was moved and tested in turn.
## 4. The behaviours whose passes come after the hits (shields: every shot's path is this step's).
## The few shots whose motion reads something a hit handler may change, or the hit-work budget,
## wait for their turn in the hit pass (see `_wait`), so they see the same as before.
func step(delta: float) -> void:
	# A benchmark times the parts (`step_profile`); in the game the marks below do nothing. A new
	# pass goes between two marks, and gets a PROF_ part of its own when it is worth timing alone.
	var at: int = _profile_start()
	sim_time += delta
	_mem_step += 1
	_last_delta = delta
	_refresh_targets()
	at = _profiled(PROF_REFRESH, at)
	var top: int = _high
	_stepping = true
	_work_left = work_per_step
	if _kernel != null:
		_kernel.call(&"pass_common", self, top, delta)
	else:
		_pass_common(top, delta)
	at = _profiled(PROF_COMMON, at)
	for kind in AFTER_HITS:
		if _member_count[kind] > 0:
			# The native kernel runs the passes that need nothing of GDScript (growth, linger, orbit, curve,
			# return, homing, spiral); it says false for the others.
			if _kernel == null or not _kernel.call(&"run_pass", self, kind, kind * _cap, _member_count[kind], delta):
				_passes[kind].call(_members, kind * _cap, _member_count[kind], delta)
	at = _profiled(PROF_BEFORE, at)
	_pass_hits(top, delta)
	at = _profiled(PROF_HITS, at)
	for kind in range(AFTER_HITS, BEHAVIOURS):
		if _member_count[kind] > 0:
			_passes[kind].call(_members, kind * _cap, _member_count[kind], delta)
	_step_index += 1
	_stepping = false
	_profiled(PROF_AFTER, at)


## A timed step's start (`step_profile`): its parts cleared and the clock's now. 0, and nothing
## else, in the game.
func _profile_start() -> int:
	if step_profile.is_empty():
		return 0
	step_profile.fill(0)
	return profile_clock.call()


## Sets part `part` of `step_profile` to the microseconds since `since` and returns now. Nothing in
## the game (no profile): the step reads no clock.
func _profiled(part: int, since: int) -> int:
	if step_profile.is_empty():
		return 0
	var now: int = profile_clock.call()
	step_profile[part] = now - since
	return now


## Pass 1: every live shot's life runs down; a straight shot flies on along its velocity (the
## behaviour passes change that for their shots). A shot whose life ran out stays where it is and
## is marked to expire.
func _pass_common(top: int, delta: float) -> void:
	for slot in top:
		if _alive[slot] == 0:
			continue
		if _freeze[slot] > 0.0:
			# A local stop (`freeze_shot`): the shot holds where it is; its life, its motion and the
			# behaviour passes (which read the state) wait.
			_freeze[slot] -= delta
			_prev[slot] = _pos[slot]
			_state[slot] = S_FROZEN
			continue
		_life[slot] -= delta
		var at: Vector2 = _pos[slot]
		_prev[slot] = at
		if _life[slot] <= 0.0:
			_state[slot] = S_EXPIRE
			continue
		_state[slot] = S_MOVING
		if _motion[slot] == MOTION_STRAIGHT:
			_pos[slot] = at + _vel[slot] * delta


## Pass 3: every shot in turn (from `_resume`, see WORK_PER_STEP): its end if a pass marked one,
## then the bounds, the walls on its path and its hits (`_hit_slot`). The native kernel walks the
## shots that need nothing of GDScript (no end, no wall, no hit) and hands back each one that does,
## in turn, so the events are sent in the same order (a pass with solid shots runs here).
func _pass_hits(top: int, delta: float) -> void:
	var limit: Rect2 = _bounds.grow(BOUNDS_MARGIN)
	var resume: int = _resume if _resume < top else 0
	_starved_at = -1
	var n: int = 0
	if _kernel != null and not _any_solid:
		n = _pass_hits_native(top, delta, limit, resume)
	# Every shot the kernel did not reach (all of them without it).
	while n < top:
		_hit_slot(_wrapped(n + resume, top), delta, limit)
		n += 1
	if not step_profile.is_empty() and _starved_at >= 0:
		# The shots from the first starved one round to where the pass began.
		step_profile[PROF_PAST_BUDGET] = top - ((_starved_at - resume + top) % top)
	_resume = maxi(_starved_at, 0)


## The hit pass with the native kernel (`ShotKernel.hits`): it takes the shots that need nothing
## of GDScript, and each it hands back (an end, a wall, hits found) takes its turn here, then the
## kernel goes on after it. Returns the shot the pass got to: `top`, or where the kernel failed (it
## logged why; `_pass_hits` does the rest).
func _pass_hits_native(top: int, delta: float, limit: Rect2, resume: int) -> int:
	var n: int = 0
	var timing: bool = not step_profile.is_empty()
	while n < top:
		# The kernel's scratch holds every target (a hit handler may have added some).
		_fit_hit_scratch()
		var at: int = profile_clock.call() if timing else 0
		var handed: int = _kernel.call(&"hits", self, n, top, resume, limit, delta)
		if timing:
			step_profile[PROF_KERNEL] += profile_clock.call() - at
			step_profile[PROF_HANDBACKS] += 1
		if handed == -1:
			return top
		if handed < -1:
			return -2 - handed
		n = handed >> 1
		var slot: int = _wrapped(n + resume, top)
		if handed & 1 == 0:
			_hit_slot(slot, delta, limit)
		else:
			_hit_found(slot)
		n += 1
		# The shots after it that the kernel would hand straight back take their turns here, without
		# a call each (a crowd of homing shots on their search step, say).
		while n < top and _kernel_hands_back(_wrapped(n + resume, top)):
			_hit_slot(_wrapped(n + resume, top), delta, limit)
			n += 1
	return top


## `n` wrapped round `top` once (the hit pass starts at `_resume`).
static func _wrapped(n: int, top: int) -> int:
	return n - top if n >= top else n


## Size the native hit pass's scratch for every target (`_cand_*`, `_target_mark`, `_target_entry`).
func _fit_hit_scratch() -> void:
	var targets: int = _targets.size()
	if _cand_target.size() < targets:
		_cand_target.resize(targets)
		_cand_along.resize(targets)
		_cand_point.resize(targets)
	if _target_mark.size() < targets:
		_target_mark.resize(targets)
		_target_entry.resize(targets)


## Whether the native hit pass would hand the shot in `slot` straight back for its state: one to
## end, or waiting for passes other than its homing search alone (the kernel catches that up).
func _kernel_hands_back(slot: int) -> bool:
	var state: int = _state[slot]
	if state < S_STUCK:
		return false
	return state != S_WAITING or _wait_from[slot] != B_HOMING or (_kinds[slot] & AFTER_HOMING_MASK) != 0


## One shot's turn in the hit pass (see `_pass_hits`).
func _hit_slot(slot: int, delta: float, limit: Rect2) -> void:
	# A hit handler may have dropped or reused this slot (S_IDLE): a projectile spawned
	# during this step waits for the next one.
	var state: int = _state[slot]
	if state == S_IDLE:
		return
	_state[slot] = S_DONE
	if state >= S_STUCK:
		if state == S_WAITING:
			_catch_up(slot, delta)
			state = _state[slot]
			_state[slot] = S_DONE
		if state == S_EXPIRE:
			if _test_deferred(slot):
				_expire(slot)
			return
		if state == S_GONE:
			if _test_deferred(slot):
				_kill(slot)
			return
		if state == S_STUCK or state == S_FROZEN:
			return
	if not limit.has_point(_pos[slot]):
		if _test_deferred(slot):
			_kill(slot)
		return
	# A shot that meets a wall is cut short there: it can still hit what is
	# in front of the wall, then it ends (or bounces). An orbit or ghost shot ignores walls; a
	# solid one is a wall and stops at one (`_step_solid`).
	var walled: bool = false
	if _any_solid and _solids.has(slot):
		_step_solid(slot, _solids[slot])
	elif _has_walls and _motion[slot] != MOTION_ORBIT and (_flags[slot] & F_GHOST) == 0:
		var cut: float = _wall_hit(_prev[slot], _pos[slot])
		if cut >= 0.0 and _any_solid:
			cut = _past_own_solid(slot, cut)
		if cut >= 0.0:
			walled = true
			_pos[slot] = _prev[slot].lerp(_pos[slot], cut)
	if _layers[slot] != 0 and not _targets.is_empty():
		# Past the budget a shot flies on untested and keeps where its untested path starts; one
		# that ends at a wall is tested all the same (H2: no lost damage).
		if _work_left <= 0 and not walled:
			_defer(slot)
			if _starved_at < 0:
				_starved_at = slot
			return
		# A piercing shot passes through every target on its path this step, each hit once
		# (it remembers it). A hit handler may end it or even reuse the slot.
		var seq: int = _seq[slot]
		_hit_test(slot)
		# What its path no longer touches it may hit again.
		if _alive[slot] != 0 and _seq[slot] == seq:
			_forget_left(slot)
	# A shot that stuck to a target this step stays stuck, even at a wall. One that met a
	# guarding solid shot is turned or stopped by it instead (`_solid_guard`).
	if walled and _alive[slot] != 0 and (_flags[slot] & F_STUCK) == 0 and not (_any_solid and _solid_guard(slot)):
		_wall_end(slot)


## Mark the shot in `slot` passed over by the hit-work budget: its path from `_prev` on (or from
## where an earlier deferral began) waits for its next test.
func _defer(slot: int) -> void:
	var flags: int = _flags[slot]
	if (flags & F_DEFERRED) == 0:
		_flags[slot] = flags | F_DEFERRED
		_untested[slot] = _prev[slot]


## Before a deferred shot ends (its life out, out of bounds, vanishing): test the path it was not
## tested on, whatever the budget, so its damage is not lost. Returns whether it is still the same
## live shot to end (a hit may have ended it, or a handler taken its slot).
func _test_deferred(slot: int) -> bool:
	if (_flags[slot] & F_DEFERRED) == 0:
		return true
	if _layers[slot] == 0 or _targets.is_empty():
		_flags[slot] &= ~F_DEFERRED
		return true
	var seq: int = _seq[slot]
	_hit_test(slot)
	return _alive[slot] != 0 and _seq[slot] == seq


## The rest of a shot's turn once the native hit pass found `_cand_found` targets on its path (it
## did what `_hit_test` does before its hits): hit them, then forget what its path left.
func _hit_found(slot: int) -> void:
	var seq: int = _seq[slot]
	_hit_candidates(slot, _cand_found)
	if _alive[slot] != 0 and _seq[slot] == seq:
		_forget_left(slot)


# --- Shot behaviours, stepped in passes (2026-10-28) ---------------------------------------
# A behaviour that changes how a shot moves is one pass: a function that steps only the shots that
# have it, from a list kept up to date as shots get and lose it. The passes run in the order of
# their numbers (B_*) and of BEHAVIOUR_PASSES, which must match: the one place that says which
# behaviours there are and in which order they run. Behaviours that act only at a wall or a hit
# (bounce, ghost, sticky before it sticks, pierce) have no pass: `_pass_hits`,
# `_wall_end` and `_register_hit` read their numbers.
#
# A pass gets (list, first, count, delta): the shots are list[first] to list[first + count - 1].
# It looks at each shot's `_state` (S_*) for this step and changes it when it takes the shot
# over: it never ends a shot or sends an event (it marks S_EXPIRE or S_GONE and the hit pass ends
# it), and never adds a shot to a list or takes one off (only a setter, a hit and `_kill` do).
#
# The order, and why:
# - stuck first: a stuck shot moves with its target and nothing else of it runs.
# - growth before linger and return: a lingering shot still grows, and a returning one reaches
#   its caster with the radius it has now.
# - linger before return, homing and spiral: a shot that hangs still does none of them.
# - orbit after linger: a lingering orbit stops turning; it weaves its own spiral (no spiral pass).
# - return before homing: a shot on its way back heads for its caster, bent toward the target its
#   homing found (`_pass_return`); the homing pass only searches for it.
# - speed curve after return and before homing and spiral: it sets the speed only of a shot flying
#   out (one on its way home keeps the speed it turned with), and homing and spiral then turn and
#   weave that velocity.
# - homing before spiral: a spiral weaves round the line it turned to.
# - a card's move last: it carries the shot on from wherever its own motion put it.
# - shield after the hits: it checks every shot's whole path of this step.
#
# Adding one: see core/README.md, "How to add a shot behaviour".

const B_STUCK: int = 0
const B_GROWTH: int = 1
const B_LINGER: int = 2
const B_ORBIT: int = 3
const B_RETURN: int = 4
const B_CURVE: int = 5
const B_HOMING: int = 6
const B_SPIRAL: int = 7
const B_MOVE: int = 8
const B_SHIELD: int = 9
## How many behaviours there are; the passes of B_* below AFTER_HITS run before the hit pass.
const BEHAVIOURS: int = 10
const AFTER_HITS: int = B_SHIELD
## The behaviours after homing that run before the hits: a waiting homing shot with none of them is
## caught up by the native hit pass itself (`_kernel_hands_back`).
const AFTER_HOMING_MASK: int = ((1 << AFTER_HITS) - 1) & ~((1 << (B_HOMING + 1)) - 1)
## The pass of each behaviour, by B_* (`_init` makes `_passes` from it).
const BEHAVIOUR_PASSES: Array[StringName] = [
	&"_pass_stuck", &"_pass_growth", &"_pass_linger", &"_pass_orbit", &"_pass_return",
	&"_pass_curve", &"_pass_homing", &"_pass_spiral", &"_pass_move", &"_pass_shield",
]

## What a shot is doing in this step (`_state`), set by the common pass and the behaviour passes and
## read by the hit pass: not stepped (ended, or spawned during the step), flying, held still
## (linger), flying back (return), done (its turn in the hit pass came), and the rare ones, from
## S_STUCK on: riding its target (stuck), to expire, to vanish quietly, waiting for its turn (see
## `_wait`).
const S_IDLE: int = 0
const S_MOVING: int = 1
const S_HELD: int = 2
const S_RETURNING: int = 3
const S_DONE: int = 4
const S_STUCK: int = 5
const S_EXPIRE: int = 6
const S_GONE: int = 7
const S_WAITING: int = 8
## Held by a local stop (`freeze_shot`): nothing of it runs and it tests no hits this step.
const S_FROZEN: int = 9


## Give the shot in `slot` the behaviour `kind` (B_*): its pass steps it from now on. Nothing
## happens if it has it already.
func _join(slot: int, kind: int) -> void:
	if (_kinds[slot] >> kind) & 1 != 0:
		return
	var base: int = kind * _cap
	var n: int = _member_count[kind]
	_members[base + n] = slot
	_member_at[base + slot] = n
	_member_count[kind] = n + 1
	_kinds[slot] |= 1 << kind


## Take the behaviour `kind` from the shot in `slot` (the last shot in its list takes its place).
func _leave(slot: int, kind: int) -> void:
	if (_kinds[slot] >> kind) & 1 == 0:
		return
	var base: int = kind * _cap
	var last: int = _member_count[kind] - 1
	var at: int = _member_at[base + slot]
	var moved: int = _members[base + last]
	_members[base + at] = moved
	_member_at[base + moved] = at
	_member_count[kind] = last
	_kinds[slot] &= ~(1 << kind)


## Take every behaviour from the shot in `slot` (it ended).
func _leave_all(slot: int) -> void:
	var kinds: int = _kinds[slot]
	var kind: int = 0
	while kinds != 0:
		if kinds & 1 != 0:
			_leave(slot, kind)
		kinds >>= 1
		kind += 1


## The shot in `slot` waits for its turn in the hit pass, where its passes from `kind` on run for it
## alone (`_catch_up`). A pass does this for a shot whose motion reads what a hit handler may change
## (a target's place, a shot's caster, which targets are left) or the hit-work budget, so it moves
## when it always did: after the shots before it in the hit pass were tested. The passes after
## `kind` skip a waiting shot.
func _wait(slot: int, kind: int) -> void:
	_wait_state[slot] = _state[slot]
	_wait_from[slot] = kind
	_state[slot] = S_WAITING


## Run the passes a waiting shot missed (see `_wait`), for it alone.
func _catch_up(slot: int, delta: float) -> void:
	_state[slot] = _wait_state[slot]
	_one[0] = slot
	_catching_up = true
	var kinds: int = _kinds[slot]
	for kind in range(_wait_from[slot], AFTER_HITS):
		if (kinds >> kind) & 1 != 0:
			_passes[kind].call(_one, 0, 1, delta)
	_catching_up = false


## Stuck (`set_sticky`, after its first hit): the shot rides its target (it waits for its turn, as a
## hit handler may push the target), and ends with an expiry when the target is gone.
func _pass_stuck(list: PackedInt32Array, first: int, count: int, _delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		if _state[slot] != S_MOVING:
			continue
		if not _catching_up:
			_wait(slot, B_STUCK)
			continue
		var node: Variant = _stuck_to[slot]
		if not is_instance_valid(node):
			_pos[slot] = _prev[slot]
			_state[slot] = S_EXPIRE
			continue
		_pos[slot] = (node as Node2D).global_position + _stuck_off[slot]
		_state[slot] = S_STUCK


## Growth (`set_growth`): the radius grows by its factor a second, until it is as big as the room.
func _pass_growth(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	var room: float = room_size()
	for n in range(first, first + count):
		var slot: int = list[n]
		if _state[slot] == S_MOVING:
			_radius[slot] = minf(_radius[slot] * DMath.pow(_growth[slot], delta), maxf(room, _radius0[slot]))


## Linger (`set_linger`): half way through its life the shot stops for its linger time, which does
## not use up its life.
func _pass_linger(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		if _state[slot] != S_MOVING:
			continue
		if _hold[slot] < 0.0 and _life[slot] <= _span[slot] * 0.5:
			_hold[slot] = _linger[slot]
			_life[slot] += _linger[slot]
		if _hold[slot] > 0.0:
			_hold[slot] = maxf(_hold[slot] - delta, 0.0)
			_pos[slot] = _prev[slot]
			_state[slot] = S_HELD


## Orbit (`spawn_orbit`): the shot turns round its caster, its velocity the tangent (for the
## drawing). It vanishes quietly when its caster's anchor is gone. One whose caster is a shot waits
## for its turn, so it circles that shot where it was when the step came to it. A lingering one
## (S_HELD) keeps to its caster without turning; a spiral (`set_spiral`) weaves its radius.
func _pass_orbit(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		var state: int = _state[slot]
		if state != S_MOVING and state != S_HELD:
			continue
		var caster: int = _caster_slot[slot]
		var centre: Vector2 = _caster_at[slot]
		if caster == CASTER_BODY:
			centre = _anchors[_actor[slot]] if _actor[slot] >= 0 else Vector2.INF
		elif caster >= 0:
			if not _catching_up:
				_wait(slot, B_ORBIT)
				continue
			centre = _caster_position(slot)
		if not centre.is_finite():
			_state[slot] = S_GONE
			continue
		if state == S_MOVING:
			_orbit_angle[slot] = wrapf(_orbit_angle[slot] + _orbit_speed[slot] * delta, -PI, PI)
			_wave_age[slot] += delta
		var away: Vector2 = DMath.from_angle(_orbit_angle[slot])
		_pos[slot] = centre + away * (_orbit_radius[slot] + _wave[slot] * DMath.sin(TAU * _wave_age[slot] / SPIRAL_PERIOD))
		_vel[slot] = Vector2(-away.y, away.x) * (_orbit_radius[slot] * _orbit_speed[slot])
		_orbit_centre[slot] = centre


## Return (`set_return`): from half its life the shot flies back to its caster at the speed it had
## (it may hit again on the way), and ends with an expiry when it gets there; the way home takes no
## life, so it always comes home (rules R4 F4), but it vanishes when its caster's anchor is gone.
## One whose caster is a shot waits for its turn (see `_pass_orbit`).
func _pass_return(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		if _state[slot] != S_MOVING or _life[slot] > _span[slot] * 0.5:
			continue
		if _caster_slot[slot] >= 0 and not _catching_up:
			_wait(slot, B_RETURN)
			continue
		# The way home takes no life: give back what `_pass_common` took this step.
		_life[slot] += delta
		var flags: int = _flags[slot]
		var turned: bool = (flags & F_TURNED) == 0
		if turned:
			_flags[slot] |= F_TURNED
			_speed[slot] = _vel[slot].length()
			_forget_all(slot)
		var anchor: Vector2 = _caster_position(slot)
		if not anchor.is_finite():
			_pos[slot] = _prev[slot]
			_state[slot] = S_GONE
			continue
		var here: Vector2 = _base[slot] if (flags & F_WAVE) != 0 else _prev[slot]
		var way: Vector2 = anchor - here
		if way.length() <= _speed[slot] * delta + _radius[slot]:
			_pos[slot] = anchor
			_state[slot] = S_EXPIRE
			continue
		var heading: Vector2 = way.normalized()
		if _turn[slot] > 0.0:
			# Homing bends the way home (rules R4a): the shot's angle off the line to its caster
			# turns toward its target at the homing rate (back to 0 with none in reach), never past
			# RETURN_BEND, so it always closes in on its caster and never circles.
			var bend: float = 0.0 if turned else clampf(DMath.angle_to(heading, _vel[slot]), -RETURN_BEND, RETURN_BEND)
			var goal: Vector2 = _home_at[slot]
			var want: float = 0.0
			if goal.is_finite() and not goal.is_equal_approx(here):
				want = clampf(DMath.angle_to(heading, goal - here), -RETURN_BEND, RETURN_BEND)
			heading = DMath.rotated(heading, move_toward(bend, want, _turn[slot] * _speed[slot] * delta))
		_vel[slot] = heading * _speed[slot]
		_pos[slot] = _prev[slot] + _vel[slot] * delta
		_state[slot] = S_RETURNING


## Speed over life (`set_speed_curve`): a shot flying out takes the speed of its curve at the share
## of its life left, along the way it flies now, and flies on along it. The share is read at the
## middle of the step (its life was already counted down for the whole step), so a curve that
## changes most early still goes as far as its mean says, to within a pixel, and not a step's
## worth of change short (every shot has a curve, SpellLimits.SHOT_SPEED_*).
func _pass_curve(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		if _state[slot] != S_MOVING:
			continue
		var left: float = clampf((_life[slot] + delta * 0.5) / _span[slot], 0.0, 1.0)
		var factor: float = _curve_from[slot] + (_curve_to[slot] - _curve_from[slot]) * (1.0 - DMath.pow(left, _curve_ease[slot]))
		_vel[slot] = _vel[slot].normalized() * (_curve_speed[slot] * factor)
		_pos[slot] = _prev[slot] + _vel[slot] * delta


## Homing (`set_homing`): the shot turns toward the point it last found, at most its turn rate, and
## flies on along its new velocity; a shot with no speed (a rune) creeps toward it at
## SpellLimits.HOMING_DRIFT. On its search step (one in HOMING_PERIOD, slots taking turns)
## it waits for its turn, then looks for a target while there is hit work left (`_homing_point`).
## A returning shot on its way back only searches: `_pass_return` bends its way with the point.
func _pass_homing(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		var state: int = _state[slot]
		if state != S_MOVING and state != S_RETURNING:
			continue
		if ((slot + _step_index) % HOMING_PERIOD) == 0:
			if not _catching_up:
				_wait(slot, B_HOMING)
				continue
			if _work_left > 0:
				_home_at[slot] = _homing_point(slot, _prev[slot])
		if state == S_RETURNING:
			continue
		var goal: Vector2 = _home_at[slot]
		if not goal.is_finite():
			continue
		var want: Vector2 = goal - _prev[slot]
		if want.is_zero_approx():
			continue
		var velocity: Vector2 = _vel[slot]
		if velocity.is_zero_approx():
			_pos[slot] = _prev[slot] + want.limit_length(SpellLimits.HOMING_DRIFT * delta)
			continue
		# `turned_toward`, written out (this runs for every homing shot every step).
		# Its bend a pixel times the pixels it flies: the same curve at any speed.
		var most: float = _turn[slot] * velocity.length() * delta
		_vel[slot] = DMath.rotated(velocity, clampf(DMath.angle_to(velocity, want), -most, most))
		_pos[slot] = _prev[slot] + _vel[slot] * delta


## Spiral (`set_spiral`): the shot's centre line (`_base`) flies straight on and the shot weaves a
## sine wave of its width round it, SPIRAL_PERIOD seconds a wave.
func _pass_spiral(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		var state: int = _state[slot]
		if state != S_MOVING and state != S_RETURNING:
			continue
		var velocity: Vector2 = _vel[slot]
		_base[slot] += velocity * delta
		_wave_age[slot] += delta
		var side: Vector2 = Vector2(-velocity.y, velocity.x).normalized()
		_pos[slot] = _base[slot] + side * (_wave[slot] * DMath.sin(TAU * _wave_age[slot] / SPIRAL_PERIOD))


## A card's moves (`move_shot`): while each lasts, it carries the shot on top of its own motion (a
## lingering shot too), and the moves under way add up. A shot with a homing move waits for its
## turn: it picks among the targets still there. A move that is over is let go.
func _pass_move(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		var state: int = _state[slot]
		if (state != S_MOVING and state != S_HELD and state != S_RETURNING) or _move_head[slot] < 0:
			continue
		if not _catching_up and _has_homing_move(slot):
			_wait(slot, B_MOVE)
			continue
		var before: int = -1
		var at: int = _move_head[slot]
		while at >= 0:
			var next: int = _move_next[at]
			var part: float = minf(delta, _move_left[at])
			_move_left[at] -= delta
			if _move_turn[at] > 0.0:
				_move_vel[at] = home_velocity(_actor[slot], _pos[slot], _move_vel[at], _move_turn[at], _move_range[at], part, _move_home[at], int(_seq[slot]), _layers[slot])
				_move_home[at] = homing_target
			_pos[slot] += _move_vel[at] * part
			_base[slot] += _move_vel[at] * part
			if _move_left[at] <= 0.0:
				if before < 0:
					_move_head[slot] = next
				else:
					_move_next[before] = next
				_move_next[at] = _move_free
				_move_free = at
			else:
				before = at
			at = next


## True when one of the moves under way of the shot in `slot` homes.
func _has_homing_move(slot: int) -> bool:
	var at: int = _move_head[slot]
	while at >= 0:
		if _move_turn[at] > 0.0:
			return true
		at = _move_next[at]
	return false


## Shield (`set_shield`), after the hits: each shielded shot stops the shots of other teams that its
## path touched this step (`_shield_block`), in slot order.
func _pass_shield(list: PackedInt32Array, first: int, count: int, _delta: float) -> void:
	# The list in slot order (insertion sort into the scratch: shields are few), as blocks spend
	# charges in that order.
	for n in count:
		var slot: int = list[first + n]
		var at: int = n
		while at > 0 and _shield_order[at - 1] > slot:
			_shield_order[at] = _shield_order[at - 1]
			at -= 1
		_shield_order[at] = slot
	for n in count:
		var slot: int = _shield_order[n]
		# A shot spawned during this step (S_IDLE) waits for the next one.
		if _alive[slot] != 0 and (_shield[slot] > 0 or _deflect[slot] != 0) and _state[slot] == S_DONE:
			_shield_block(slot)


## A shot met a wall: it bounces while it has bounces left, otherwise it ends there.
func _wall_end(slot: int) -> void:
	wall_hits += 1
	_emit_wall_impact(slot, _vel[slot])
	if _bounce[slot] <= 0:
		expired_on_wall = true
		_expire(slot)
		expired_on_wall = false
		return
	_bounce[slot] -= 1
	var heading: Vector2 = _vel[slot].normalized()
	# Step back out of the wall cell, then find which face was hit: a face is hit when the
	# cell one cell further along that axis is solid.
	var at: Vector2 = _pos[slot] - heading * 0.5
	_vel[slot] = _bounced(at, heading, _vel[slot])
	_pos[slot] = at
	_base[slot] = at
	# A bounced shot may hit what it hit before.
	_forget_all(slot)
	# Last: a handler's payload may take this slot over (a cap drop).
	var outer_slot: int = _event_slot
	_event_slot = slot
	wall_met.emit(_actor[slot], at, _vel[slot].normalized(), _tag[slot], slot)
	_event_slot = outer_slot


## `velocity` turned off the wall face met at `at` (just out of the wall, heading `heading`): a
## face is hit when the cell one cell further along that axis is solid; both or neither (a
## corner) send it back the way it came. A shot's bounce and a beam's turn share it.
func _bounced(at: Vector2, heading: Vector2, velocity: Vector2) -> Vector2:
	var flip_x: bool = _solid_at(at + Vector2(signf(heading.x) * WALL_CELL, 0.0))
	var flip_y: bool = _solid_at(at + Vector2(0.0, signf(heading.y) * WALL_CELL))
	if flip_x == flip_y:
		return -velocity
	if flip_x:
		return Vector2(-velocity.x, velocity.y)
	return Vector2(velocity.x, -velocity.y)


func _solid_at(point: Vector2) -> bool:
	return _cell_at(point) != 0


## The wall grid's byte at `point` (0 outside the grid).
func _cell_at(point: Vector2) -> int:
	var x: int = floori((point.x - _bounds.position.x) / WALL_CELL)
	var y: int = floori((point.y - _bounds.position.y) / WALL_CELL)
	return _wall_cells[y * _wall_w + x] if x >= 0 and x < _wall_w and y >= 0 and y < _wall_h else 0


## Check a shielded shot against the shots of other teams (aim, actors G3a: a shield stops
## every shot whose caster was on another team when it was cast, a shot of no actor included,
## never its own team's): every one it touches is stopped, one shield charge each (cell by cell,
## in slot order within a cell), and `shot_blocked` is sent. It looks only at the shots on the
## grid cells its path could touch (the shots are put on the target grid's cells once per step,
## the first time a shield needs them). Not charged to the hit-work budget: a block always
## happens (rules R4).
func _shield_block(slot: int) -> void:
	if _scan_step != _step_index:
		_scan_step = _step_index
		_fill_shot_grid()
	# Every shot that may touch this one's path this step: its box, widened by the reach.
	var pad: float = _radius[slot] + _shot_reach
	var low: Vector2 = _prev[slot].min(_pos[slot]) - Vector2(pad, pad)
	var high: Vector2 = _prev[slot].max(_pos[slot]) + Vector2(pad, pad)
	var x0: int = clampi(floori((low.x - _grid_x) / GRID_CELL), 0, _grid_w - 1)
	var x1: int = clampi(floori((high.x - _grid_x) / GRID_CELL), 0, _grid_w - 1)
	var y0: int = clampi(floori((low.y - _grid_y) / GRID_CELL), 0, _grid_h - 1)
	var y1: int = clampi(floori((high.y - _grid_y) / GRID_CELL), 0, _grid_h - 1)
	var mine: int = _team[slot]
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var other: int = _shot_head[y * _grid_w + x]
			while other >= 0:
				if _shield[slot] <= 0 and _deflect[slot] == 0:
					return
				if _alive[other] != 0 and other != slot and _team[other] != mine:
					_shield_meets(slot, other)
				other = _shot_next[other]


## `_shield_block` for one shot of another team: stopped or deflected when it touches the shield.
func _shield_meets(slot: int, other: int) -> void:
	var reach: float = _radius[slot] + _radius[other]
	# Both shots move during the step: in the enemy shot's frame the shield goes along
	# the relative path, so the test is the distance from that segment to the origin.
	var start: Vector2 = _prev[slot] - _prev[other]
	var path: Vector2 = (_pos[slot] - _pos[other]) - start
	var along: float = 0.0
	if not path.is_zero_approx():
		along = clampf(-start.dot(path) / path.length_squared(), 0.0, 1.0)
	if (start + path * along).length_squared() > reach * reach:
		return
	_guard_meets(slot, other, _pos[other] - _pos[slot])


## The shot `other` touched the shield or deflect of the shot in `slot` (`normal` the way out of
## it): turned (deflect goes first and keeps the shield's charge, owner 2026-10-29) or stopped.
func _guard_meets(slot: int, other: int, normal: Vector2) -> void:
	if _deflect[slot] != 0:
		deflect_shot(other, _actor[slot], normal, _tag[slot])
		return
	_shield[slot] -= 1
	var at: Vector2 = _pos[other]
	_kill(other)
	if events != null:
		_event_slot = slot
		events.shot_blocked.emit(_actor[slot], at, _tag[slot], slot)
		_event_slot = -1


## The shot in `slot` met a wall: when it is the row of a solid shot of another team with a
## shield charge or deflect, that guard turns or stops it (`_guard_meets`), as it would on any
## carrier it touches, and this returns true. Else false: it meets the wall as any wall.
func _solid_guard(slot: int) -> bool:
	var at: Vector2 = _pos[slot]
	for owner: int in _solids:
		if owner == slot or _team[owner] == _team[slot] or (_shield[owner] <= 0 and _deflect[owner] == 0):
			continue
		var half: Vector2 = _solid_half(owner, _solids[owner])
		var on: Vector2 = Geometry2D.get_closest_point_to_segment(at, _pos[owner] - half, _pos[owner] + half)
		var reach: float = _radius[owner] + _radius[slot] + WALL_CELL
		if on.distance_squared_to(at) <= reach * reach:
			# Just out of the wall first, as a bounce does, so a turned shot leaves it.
			_pos[slot] = at - _vel[slot].normalized() * 0.5
			_base[slot] = _pos[slot]
			_guard_meets(owner, slot, at - on)
			return true
	return false


## Put every live shot on the target grid's cell where it is now (chains in slot order), and
## find the most any reaches from there this step (radius and path), for `_shield_block`.
func _fill_shot_grid() -> void:
	_shot_head.fill(-1)
	_shot_reach = 0.0
	var other: int = _high - 1
	while other >= 0:
		if _alive[other] != 0:
			var at: Vector2 = _pos[other]
			var cell: int = clampi(floori((at.y - _grid_y) / GRID_CELL), 0, _grid_h - 1) * _grid_w + clampi(floori((at.x - _grid_x) / GRID_CELL), 0, _grid_w - 1)
			_shot_next[other] = _shot_head[cell]
			_shot_head[cell] = other
			_shot_reach = maxf(_shot_reach, _radius[other] + at.distance_to(_prev[other]))
		other -= 1


## Where a shot is drawn when it is at `at`: where it is, except a new orbit shot, which is drawn
## spiralling out from its caster to its circle over ORBIT_GROW seconds (the mockup's; it hits
## at its circle from the start, so a ring's hits do not wait on the look).
func _drawn_at(slot: int, at: Vector2) -> Vector2:
	if _motion[slot] != MOTION_ORBIT:
		return at
	var out: float = (sim_time - _born[slot]) / ORBIT_GROW
	if out >= 1.0 or not _orbit_centre[slot].is_finite():
		return at
	return _orbit_centre[slot].lerp(at, maxf(out, 0.0))


func _orbit_tangent(slot: int) -> Vector2:
	var away: Vector2 = DMath.from_angle(_orbit_angle[slot])
	return Vector2(-away.y, away.x) * (_orbit_radius[slot] * _orbit_speed[slot])


## `velocity` turned toward `want` by at most `most` radians, keeping its length: the one turn
## of homing, for a shot in flight, a shot's move and a wizard's dash. A zero `want` or
## `velocity` gives `velocity` back.
static func turned_toward(velocity: Vector2, want: Vector2, most: float) -> Vector2:
	if velocity.is_zero_approx() or want.is_zero_approx():
		return velocity
	return DMath.rotated(velocity, clampf(DMath.angle_to(velocity, want), -most, most))


## For anything else homing moves (a shot carried by a dash, a wizard dashing): `velocity` at
## `from` turned toward a target on `layers` no further than `within` pixels, in any
## direction, by at most `turn_rate` radians a second for `delta` seconds, as a homing shot
## turns. The target is picked as `homing_point` picks it for `caster` (`keep`, `pick_seed`);
## `homing_target` says which, to hand back as `keep` next step. Allocation-free.
func home_velocity(caster: int, from: Vector2, velocity: Vector2, turn_rate: float, within: float, delta: float, keep: int, pick_seed: int, layers: int = ACTOR_LAYERS) -> Vector2:
	homing_target = 0
	homing_target_radius = 0.0
	if not (turn_rate > 0.0) or not velocity.is_finite() or velocity.is_zero_approx():
		return velocity
	var goal: Vector2 = homing_point(caster, from, velocity, PI, layers, within, keep, pick_seed)
	if not goal.is_finite():
		return velocity
	return turned_toward(velocity, goal - from, turn_rate * delta)


## Where a homing shot at `from` steers: the target it kept, while it may still home on it, or else
## a new one picked at random (`_home_pick`), or INF. Charges the work budget.
func _homing_point(slot: int, from: Vector2) -> Vector2:
	var t: int = _home_pick(_actor[slot], _team[slot], from, Vector2.RIGHT, PI, _layers[slot], _home_range[slot], _home_target[slot], int(_seq[slot]), slot)
	_home_target[slot] = _target_key[t] if t >= 0 else 0
	return _target_pos[t] if t >= 0 else Vector2.INF


## For a beam or a teleport, which cannot turn: `direction` (a unit vector) bent toward the
## target `homing_point` picks, or `direction` unchanged when there is none. Allocation-free.
func homing_aim(caster: int, origin: Vector2, direction: Vector2, max_angle: float, layers: int, within: float, keep: int, pick_seed: int) -> Vector2:
	var goal: Vector2 = homing_point(caster, origin, direction, max_angle, layers, within, keep, pick_seed)
	return direction if not goal.is_finite() else origin.direction_to(goal)


## The centre of the target a homing thing at `origin` going along `direction` steers to, or
## INF when there is none: one on `layers` no further than `within` pixels whose centre lies within `max_angle` radians of `direction` (PI for any
## way). Targets owned by `caster` and those of its team (`Actors.team_of`; homing aims at
## other teams only, actors G3a) are skipped. The target whose
## key (`_target_key`) is `keep` stays the pick while it qualifies; otherwise one is picked at random
## among those that do, from `pick_seed` (the same seed and targets give the same pick), so a
## group of shots spreads over a group of enemies. `homing_target` is left at the pick's key (0 for
## none), for the caller to keep. Allocation-free.
func homing_point(caster: int, origin: Vector2, direction: Vector2, max_angle: float, layers: int, within: float, keep: int, pick_seed: int) -> Vector2:
	homing_target = 0
	homing_target_radius = 0.0
	if not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx() or not is_finite(max_angle) or not is_finite(within) or within <= 0.0:
		return Vector2.INF
	_query_ready()
	var t: int = _home_pick(caster, _team_of(caster), origin, direction, max_angle, layers, within, keep, pick_seed, -1)
	if t < 0:
		return Vector2.INF
	homing_target = _target_key[t]
	homing_target_radius = _target_radius[t]
	return _target_pos[t]


## The one homing search: the target (an index, or -1) `homing_point` describes, for `caster`
## of `team` (NONE: no team, every target but its own body). For a shot (`slot` 0 or more) it
## also skips the targets the shot just hit and charges the work budget.
func _home_pick(caster: int, team: int, origin: Vector2, direction: Vector2, max_angle: float, layers: int, within: float, keep: int, pick_seed: int, slot: int) -> int:
	# Homing never picks its own team (a teammate, for a wizard), though every spell hits it, nor
	# a target the shot is still on (`_mark_memory`).
	var stamp: int = _mark_memory(slot) if slot >= 0 else -1
	var any_way: bool = max_angle >= PI
	var pick: int = -1
	var seen: int = 0
	var cells: Vector4i = _query_cells(origin, within)
	for y in range(cells.y, cells.w + 1):
		for x in range(cells.x, cells.z + 1):
			var t: int = _cell_head[y * _grid_w + x]
			while t >= 0:
				if slot >= 0:
					_work_left -= 1
				if (_target_layer[t] & layers) != 0 and (caster < 0 or _target_owner[t] != caster) and (team == ActorsScript.NONE or _target_team[t] != team) and is_instance_valid(_targets[t]) and (slot < 0 or _target_mark[t] != stamp):
					var to_target: Vector2 = _target_pos[t] - origin
					var reach: float = within + _target_radius[t]
					if to_target.length_squared() <= reach * reach and (any_way or (not to_target.is_zero_approx() and absf(DMath.angle_to(direction, to_target)) <= max_angle)):
						if keep != 0 and _target_key[t] == keep:
							return t
						# Reservoir pick: the n-th target seen replaces the pick one time in n.
						seen += 1
						if posmod(hash(Vector2i(pick_seed, seen)), seen) == 0:
							pick = t
				t = _target_next[t]
	return pick


## An instant beam from `origin` along `direction` for `length` pixels, fired by the actor
## `caster`. It holds no row in the pool. It stops at the first wall (or, with `bounces`, turns
## off it as a bouncing shot does, that many times, and goes on for the length it has left) and
## hits the nearest `pierce + 1` targets on `layers` whose circle the beam touches (`width`
## pixels either side of the line; `exclude` is the body the beam is cast from, its caster's own or
## the one whose hit fired it, which it spares until a piece of its path starts off that body: one
## that bounces or bends back into it hits it, as a shot that comes back does). For each, nearest first, it sends `projectile_impact` and
## `projectile_hit(caster, target, point, tag)`, the point being where the beam passes closest
## to the target; a beam that ends on a wall sends an impact with a `null` target there, and one
## that turns at a wall one at every turn (each wall also sends `wall_met`, after the hits).
## Its caster's own body is hit like any other (but as `exclude`) and, as in `spawn`, it hits ACTOR_LAYERS
## whatever `layers` says. Returns how far the beam got in pixels: the length, the distance to
## the wall, or the distance to the last target it could hit. 0.0 for bad arguments or an origin
## inside a wall. The hits are found before any event is sent, so a handler may remove or free
## targets, or fire another ray, as deep as it likes. Nothing caps a ray (RAY_PATH_START). Where
## it ended and its heading there are left in `ray_end` and `ray_end_heading`, and the path it
## walked in `ray_path`. A `ghost` ray passes through walls (it never turns or ends at one). It
## allocates only when a ray is bigger than any before it.
# --- Gates (the portal carrier; docs/milestones/portal.md) -----------------------------------

## Opens a gate of the portal `group` (cast as the spell `tag`) at `at`, facing `face` (unit),
## `radius` pixels round: its mouth when `mouth`, else one of its exits. Returns its row (rows are reused once closed, the
## lowest free first, so the order is the same every run), or -1 for a bad one.
func open_gate(group: int, tag: int, at: Vector2, face: Vector2, radius: float, mouth: bool) -> int:
	if not at.is_finite() or not face.is_finite() or face.is_zero_approx() or not (radius > 0.0):
		return -1
	var row: int = _gate_on.find(0)
	if row < 0:
		row = _gate_on.size()
		var size: int = maxi(8, row * 2)
		for column: Variant in [_gate_on, _gate_pos, _gate_face, _gate_radius, _gate_group, _gate_tag, _gate_mouth]:
			column.resize(size)
		for n in range(row, size):
			_gate_on[n] = 0
	_gate_on[row] = 1
	_gate_pos[row] = at
	_gate_face[row] = face.normalized()
	_gate_radius[row] = radius
	_gate_group[row] = group
	_gate_tag[row] = tag
	_gate_mouth[row] = 1 if mouth else 0
	_gate_live += 1
	return row


## Closes gate `gate` (nothing when it is not open).
func close_gate(gate: int) -> void:
	if gate_open(gate):
		_gate_on[gate] = 0
		_gate_live -= 1


## How many gate rows there are (open or not), for `gate_open`.
func gate_rows() -> int:
	return _gate_on.size()


## True when there is at least one open gate.
func has_gates() -> bool:
	return _gate_live > 0


func gate_open(gate: int) -> bool:
	return gate >= 0 and gate < _gate_on.size() and _gate_on[gate] != 0


func gate_position(gate: int) -> Vector2:
	return _gate_pos[gate] if gate_open(gate) else Vector2.INF


func gate_face(gate: int) -> Vector2:
	return _gate_face[gate] if gate_open(gate) else Vector2.ZERO


func gate_radius(gate: int) -> float:
	return _gate_radius[gate] if gate_open(gate) else 0.0


func gate_group(gate: int) -> int:
	return _gate_group[gate] if gate_open(gate) else -1


## The spell tag of gate `gate`'s portal (0 when it is not open).
func gate_tag(gate: int) -> int:
	return _gate_tag[gate] if gate_open(gate) else 0


## Gate `gate` is `radius` pixels round from now on (a portal that grows).
func set_gate_radius(gate: int, radius: float) -> void:
	if gate_open(gate) and radius > 0.0 and is_finite(radius):
		_gate_radius[gate] = radius


func gate_is_mouth(gate: int) -> bool:
	return gate_open(gate) and _gate_mouth[gate] != 0


## Where what goes into gate `gate` comes out: from a mouth, every exit of its portal; from an
## exit, its portal's mouth (a portal works both ways; owner, 2026-11-05). Fills `out` (grown when
## needed) in row order and returns how many.
func gate_outs(gate: int, out: PackedInt32Array) -> int:
	if not gate_open(gate):
		return 0
	var group: int = _gate_group[gate]
	var want: int = 0 if _gate_mouth[gate] != 0 else 1
	var found: int = 0
	for row in _gate_on.size():
		if _gate_on[row] != 0 and row != gate and _gate_group[row] == group and _gate_mouth[row] == want:
			if out.size() <= found:
				out.resize(maxi(4, found * 2))
			out[found] = row
			found += 1
	return found


## The way something going `way` into gate `from` leaves gate `to`: the same way. A gate is a
## sphere with no front (owner, 2026-11-05): what hits it from one side leaves the other gate on the
## far side, going on as it went; what is fired back at an exit leaves the mouth flying at the one
## who opened it (P3). Every pass asks here, so a later rule for turning is one place.
func gate_turn(from: int, to: int, way: Vector2) -> Vector2:
	if not gate_open(from) or not gate_open(to):
		return way
	return way


## The share (0 to 1) of the segment from `a` to `b` at which it first goes into an open gate's
## circle widened by `pad`, starting outside it (a segment that starts inside a gate is leaving it);
## -1.0 for none. `gate_hit` says which gate (the lower row of two met at the same point).
func gate_cut(a: Vector2, b: Vector2, pad: float = 0.0) -> float:
	gate_hit = -1
	if _gate_live <= 0:
		return -1.0
	var d: Vector2 = b - a
	var dd: float = d.length_squared()
	var best: float = 2.0
	for row in _gate_on.size():
		if _gate_on[row] == 0:
			continue
		var r: float = _gate_radius[row] + pad
		var f: Vector2 = a - _gate_pos[row]
		var c: float = f.length_squared() - r * r
		if c <= 0.0:
			continue
		if dd <= 0.0:
			continue
		var bq: float = f.dot(d)
		if bq >= 0.0:
			continue
		var disc: float = bq * bq - dd * c
		if disc < 0.0:
			continue
		var t: float = (-bq - sqrt(disc)) / dd
		if t >= 0.0 and t <= 1.0 and t < best:
			best = t
			gate_hit = row
	return best if gate_hit >= 0 else -1.0


## The flying shots whose centre went into a gate on their last step (from where they were to
## where they are), in slot order: `gate_shots` and `gate_shot_gates` (each one's gate), and how
## many. Only shots that fly on their own (straight, not stuck, held or frozen); a still shot, an
## orbit and one that did not move never go through. Nothing is allocated once the lists have grown.
func shots_into_gates() -> int:
	if _gate_live <= 0:
		return 0
	var found: int = 0
	for slot in _high:
		if _alive[slot] == 0 or _motion[slot] != MOTION_STRAIGHT:
			continue
		var state: int = _state[slot]
		if state == S_STUCK or state == S_FROZEN or state == S_HELD:
			continue
		var from: Vector2 = _prev[slot]
		var to: Vector2 = _pos[slot]
		if from == to:
			continue
		if gate_cut(from, to) < 0.0:
			continue
		if gate_shots.size() <= found:
			gate_shots.resize(maxi(8, found * 2))
			gate_shot_gates.resize(gate_shots.size())
		gate_shots[found] = slot
		gate_shot_gates[found] = gate_hit
		found += 1
	return found


## Puts the shot in `slot` at `at` at once, flying `velocity` (a shot that came out of a gate): no
## tail across the gap and no hits swept across it, as a blink (`move_shot` with no seconds). Its
## speed (what homing and return keep) stays. False when there is no such shot.
func pass_shot(slot: int, at: Vector2, velocity: Vector2) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or _motion[slot] == MOTION_ORBIT:
		return false
	if not at.is_finite() or not velocity.is_finite():
		return false
	_threat_step = -1
	_base[slot] += at - _pos[slot]
	_pos[slot] = at
	_prev[slot] = at
	_vel[slot] = velocity
	_flags[slot] &= ~F_DEFERRED
	_tail_from[slot] = at
	_home_at[slot] = Vector2.INF
	return true


func ray(caster: int, origin: Vector2, direction: Vector2, length: float, pierce: int = 0, layers: int = LAYER_ENEMY, tag: int = 0, width: float = 0.0, exclude: Node = null, bounces: int = 0, ghost: bool = false) -> float:
	ray_path_count = 0
	if not direction.is_finite() or direction.is_zero_approx() or not is_finite(length) or length <= 0.0 or not origin.is_finite():
		return _no_ray()
	_path[0] = origin
	_path[1] = origin + direction.normalized() * length
	return _ray_path(caster, 1, pierce, layers, tag, width, exclude, true, bounces, Callable(), ghost)


## A beam like `ray` along the path `points[offset]` to `points[offset + count - 1]`, cut to
## `length` pixels along it: a live beam, whose homing bends it from target to target, and which
## never reaches past its own length. With `hit` false it only finds how far the beam gets
## (walls, and the target that spends it) and sends nothing, for the look of a beam between its
## hits. With `bounces` it turns at walls as `ray` does, and goes on from there along `steer`'s
## path when it is given one (a homing beam homes again after every turn: `steer.call(turn, at,
## way, left)` gets the turn's index in the path, where it is, the way off the wall and the length
## left, and returns the points that follow `at`; empty for straight on), else straight. A
## `ghost` one passes through walls. Returns how far it got along the path; `ray_end` and
## `ray_end_heading` say where, and `ray_path` what it walked.
func ray_points(caster: int, points: PackedVector2Array, offset: int, count: int, length: float, pierce: int = 0, layers: int = LAYER_ENEMY, tag: int = 0, width: float = 0.0, exclude: Node = null, hit: bool = true, bounces: int = 0, steer: Callable = Callable(), ghost: bool = false) -> float:
	ray_path_count = 0
	if count < 2 or offset < 0 or offset + count > points.size() or not is_finite(length) or length <= 0.0 or not points[offset].is_finite():
		return _no_ray()
	_fit_path(count)
	_path[0] = points[offset]
	var total: float = 0.0
	var used: int = 0
	for i in range(1, count):
		var point: Vector2 = points[offset + i]
		if not point.is_finite():
			break
		var piece: float = _path[i - 1].distance_to(point)
		used = i
		if total + piece >= length:
			_path[i] = _path[i - 1].move_toward(point, length - total)
			break
		total += piece
		_path[i] = point
	if used == 0:
		return _no_ray()
	return _ray_path(caster, used, pierce, layers, tag, width, exclude, hit, bounces, steer, ghost)


## A beam like `ray`, bent: it follows the quadratic curve from `origin` to `end` pulled
## toward `bend` (a homing beam: `bend` along the aim, `end` on the target), walked as
## RAY_SEGMENTS straight pieces. With `hit` false it only finds how far the beam gets (walls, and
## the target that spends it) and sends nothing, for the look of a beam between its hits. With
## `bounces` it turns at walls as `ray` does. Returns how far it got along the curve; `ray_end`
## and `ray_end_heading` say where, and `ray_path` what it walked.
func ray_curve(caster: int, origin: Vector2, bend: Vector2, end: Vector2, pierce: int = 0, layers: int = LAYER_ENEMY, tag: int = 0, width: float = 0.0, exclude: Node = null, hit: bool = true, bounces: int = 0) -> float:
	ray_path_count = 0
	if not origin.is_finite() or not bend.is_finite() or not end.is_finite() or origin.is_equal_approx(end):
		return _no_ray()
	_path[0] = origin
	for i in range(1, RAY_SEGMENTS + 1):
		var t: float = float(i) / RAY_SEGMENTS
		var u: float = 1.0 - t
		_path[i] = origin * (u * u) + bend * (2.0 * u * t) + end * (t * t)
	return _ray_path(caster, RAY_SEGMENTS, pierce, layers, tag, width, exclude, hit, bounces)


## A ray that is not cast: its `ray_cast_by` is used up all the same.
func _no_ray() -> float:
	_ray_caster = -1
	ray_gates = false
	_set_ray_gate(-1, Vector2.INF, Vector2.ZERO, 0.0)
	return 0.0


## `_path` holds at least `count` points.
func _fit_path(count: int) -> void:
	if _path.size() < count:
		_path.resize(maxi(count, _path.size() * 2))


## The scratch of nesting level `level`, made the first time a ray goes that deep.
func _ray_level(level: int) -> void:
	while _ray_nodes.size() <= level:
		_ray_nodes.append([])
		_ray_along.append([])
		_ray_points.append([])
		_ray_heads.append([])
		_ray_walks.append([])
		_ray_turns.append([])


## The bodies a swing's sweep touches (melee I2): every target on `layers` (and ACTOR_LAYERS, as
## in `ray`) whose hit circle reaches into the wedge round `origin` from `from_angle` to
## `to_angle` radians off `direction` (`side` 1 counts clockwise on screen, -1 the other way;
## `to_angle` not below `from_angle`), out to `reach` pixels, with no wall between it and
## `origin`. Only `exclude` is skipped (the body it is cast from: its caster's own body is hit
## like any other). It sends nothing: it
## fills `sweep_nodes`, `sweep_points` (where the wedge meets the body, on its line from
## `origin`; for a whole circle `origin` itself, what strikes from there) and `sweep_heads` (the
## way the sweep moves there: round `origin`, or outward for a whole circle) and returns how many (every one: the results grow). Each step of a swing asks for
## the wedge it turned through since the last, so a fast sweep misses nothing between two steps.
## Without `walls` a wall between hides nothing (an explosion). Allocation-free.
func sweep(caster: int, origin: Vector2, direction: Vector2, side: int, from_angle: float, to_angle: float, reach: float, layers: int = LAYER_ENEMY, exclude: Node = null, walls: bool = true) -> int:
	if not is_caster(caster) or not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx():
		return 0
	if not is_finite(reach) or reach <= 0.0 or not is_finite(from_angle) or not is_finite(to_angle) or to_angle < from_angle or _targets.is_empty():
		return 0
	_query_ready()
	layers |= ACTOR_LAYERS
	var base: float = DMath.angle(direction)
	var turn: float = 1.0 if side >= 0 else -1.0
	var whole: bool = to_angle - from_angle >= TAU
	var skip: int = exclude.get_instance_id() if exclude != null else 0
	var pad: Vector2 = Vector2.ONE * (reach + _max_target_radius)
	var x0: int = clampi(floori((origin.x - pad.x - _bounds.position.x) / GRID_CELL), 0, _grid_w - 1)
	var x1: int = clampi(floori((origin.x + pad.x - _bounds.position.x) / GRID_CELL), 0, _grid_w - 1)
	var y0: int = clampi(floori((origin.y - pad.y - _bounds.position.y) / GRID_CELL), 0, _grid_h - 1)
	var y1: int = clampi(floori((origin.y + pad.y - _bounds.position.y) / GRID_CELL), 0, _grid_h - 1)
	var found: int = 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var t: int = _cell_head[y * _grid_w + x]
			while t >= 0:
				if (_target_layer[t] & layers) != 0 and _target_id[t] != skip and is_instance_valid(_targets[t]):
					var to: Vector2 = _target_pos[t] - origin
					var radius: float = _target_radius[t]
					var distance: float = to.length()
					if distance <= reach + radius:
						# How far either side of its centre line the body's circle reaches.
						var width: float = PI if distance <= radius else DMath.asin(radius / distance)
						var local: float = angle_difference(base, DMath.angle(to)) * turn
						if local + width >= from_angle and local - width <= to_angle and not (walls and _has_walls and _wall_hit(origin, _target_pos[t]) >= 0.0):
							var way: Vector2 = to / distance if distance > 0.0 else direction.normalized()
							if found == sweep_nodes.size():
								sweep_nodes.resize(found * 2)
								sweep_points.resize(found * 2)
								sweep_heads.resize(found * 2)
							sweep_nodes[found] = _targets[t]
							sweep_points[found] = origin if whole else origin + way * maxf(distance - radius, 0.0)
							sweep_heads[found] = way if whole else Vector2(-way.y, way.x) * turn
							found += 1
				t = _target_next[t]
	return found


## One hit of an instant carrier on `target` (a swing's, `sweep`): `projectile_impact` with `form`
## for its look, then `projectile_hit(caster, target, point, tag)`, as a beam's hit sends them.
## Returns false when it sent nothing (no events, or a gone target). It nests one ray level, as a
## ray's hits do, so a ray its handlers fire has scratch of its own.
func strike(caster: int, target: Node, point: Vector2, heading: Vector2, tag: int, form: StringName) -> bool:
	if events == null or not is_instance_valid(target) or not is_caster(caster):
		return false
	_ray_depth += 1
	var outer_slot: int = _event_slot
	_event_slot = -1
	impact_form = form
	impact_core = Color.WHITE
	impact_look = 0
	impact_tag = 0
	events.projectile_impact.emit(caster, target, point, heading)
	impact_form = &""
	events.projectile_hit.emit(caster, target, point, tag, -1)
	_ray_depth -= 1
	_event_slot = outer_slot
	return true


## The beam along the first `segments` pieces of `_path` (see `ray` and `ray_curve`).
func _ray_path(caster: int, segments: int, pierce: int, layers: int, tag: int, width: float, exclude: Node, hit: bool, bounces: int = 0, steer: Callable = Callable(), ghost: bool = false) -> float:
	ray_end = Vector2.INF
	ray_end_heading = Vector2.ZERO
	ray_path_count = 0
	ray_gate = -1
	ray_gate_at = Vector2.INF
	ray_gate_heading = Vector2.ZERO
	ray_gate_left = 0.0
	# The flag is for this ray alone: a ray its hit handlers send (a zap, a jump) passes gates by.
	var gates: bool = ray_gates and _gate_live > 0
	ray_gates = false
	var g_gate: int = -1
	var g_at: Vector2 = Vector2.INF
	var g_heading: Vector2 = Vector2.ZERO
	var g_left: float = 0.0
	# A wall's own ray leaves it: its row is lifted while the ray walks (`ray_cast_by`).
	var own: Solid = _solid_of(_ray_caster, _ray_caster_seq)
	_ray_caster = -1
	if not is_caster(caster):
		return 0.0
	var level: int = _ray_depth
	_ray_level(level)
	if own != null:
		_mark_solid(own, -1)
	# Cut the path at the first wall, or turn there while it has bounces: the rest of the path
	# is dropped and it goes on, off the wall, for the length the rest had: along `steer`'s path
	# (a homing beam homes again), else straight.
	var left_turns: int = maxi(bounces, 0)
	var left: float = 0.0
	if left_turns > 0 or gates:
		for i in segments:
			left += _path[i].distance_to(_path[i + 1])
	var reach: float = 0.0
	var walled: bool = false
	var used: int = 0
	# The turns: their indices in the path, `turned` of them.
	var turns: Array = _ray_turns[level]
	var turned: int = 0
	var at_piece: int = 0
	while at_piece < segments:
		var a: Vector2 = _path[at_piece]
		var b: Vector2 = _path[at_piece + 1]
		var piece: float = a.distance_to(b)
		used = at_piece + 1
		# A gate before the wall (or with no wall): the ray stops where it goes in, and its beam
		# goes on from the other side (`ray_gate`).
		var gate_at: float = gate_cut(a, b) if gates else -1.0
		if gate_at >= 0.0:
			var wall_at: float = _wall_hit(a, b, 1 << 30) if _has_walls and not ghost else -1.0
			if wall_at < 0.0 or gate_at <= wall_at:
				var into: Vector2 = a.lerp(b, gate_at)
				g_gate = gate_hit
				g_at = into
				g_heading = (b - a) / piece if piece > 0.0 else Vector2.ZERO
				g_left = maxf(left - piece * gate_at, 0.0)
				_path[at_piece + 1] = into
				reach += piece * gate_at
				break
		if _has_walls and not ghost:
			# A ray walks every cell it crosses, however long it is.
			var cut: float = _wall_hit(a, b, 1 << 30)
			if cut >= 0.0:
				var at: Vector2 = a.lerp(b, cut)
				var heading: Vector2 = (b - a) / piece if piece > 0.0 else Vector2.ZERO
				left -= piece * cut
				if left_turns > 0 and reach + piece * cut > 0.0 and left > 0.5 and not heading.is_zero_approx():
					# Step back out of the wall, as a bouncing shot does, and turn there.
					if turns.size() <= turned:
						turns.resize(maxi(8, turned * 2))
					turns[turned] = at_piece + 1
					turned += 1
					left_turns -= 1
					at -= heading * 0.5
					left += 0.5
					reach += a.distance_to(at)
					var way: Vector2 = _bounced(at, heading, heading)
					_fit_path(at_piece + 2)
					_path[at_piece + 1] = at
					var added: int = 0
					if steer.is_valid():
						# Its own path from the turn on, cut to the length it has left.
						var more: PackedVector2Array = steer.call(at_piece + 1, at, way, left)
						var from: Vector2 = at
						var gone: float = 0.0
						for point in more:
							if not point.is_finite() or gone >= left:
								break
							var step: float = from.distance_to(point)
							_fit_path(at_piece + 3 + added)
							if gone + step >= left:
								point = from.move_toward(point, left - gone)
								step = left - gone
							_path[at_piece + 2 + added] = point
							added += 1
							gone += step
							from = point
					if added == 0:
						_fit_path(at_piece + 3)
						_path[at_piece + 2] = at + way * left
						added = 1
					segments = at_piece + 1 + added
					at_piece += 1
					continue
				walled = true
				_path[at_piece + 1] = at
				reach += piece * cut
				break
		left -= piece
		reach += piece
		at_piece += 1
	if own != null:
		_mark_solid(own, 1)
	var nodes: Array = _ray_nodes[level]
	var alongs: Array = _ray_along[level]
	var points: Array = _ray_points[level]
	var heads: Array = _ray_heads[level]
	var wanted: int = maxi(pierce, 0) + 1
	var found: int = 0
	var skip: int = exclude.get_instance_id() if exclude != null else 0
	if not _targets.is_empty() and reach > 0.0:
		_query_ready()
		layers |= ACTOR_LAYERS
		var wide: float = maxf(width, 0.0)
		var pad: Vector2 = Vector2.ONE * (wide + _max_target_radius)
		var start: float = 0.0
		# `exclude`, the body it is cast from (the caller found it starts on it), is spared until a
		# later piece of the path starts off it (as a shot's step does, `exclude`): a beam that
		# bounces or bends back into it hits it.
		var skip_at: int = _target_id.find(skip) if skip != 0 else -1
		for i in used:
			var a: Vector2 = _path[i]
			var b: Vector2 = _path[i + 1]
			if skip_at >= 0 and i > 0:
				var on: float = wide + _target_radius[skip_at]
				if a.distance_squared_to(_target_pos[skip_at]) > on * on:
					skip = 0
					skip_at = -1
			var piece: float = a.distance_to(b)
			if piece <= 0.0:
				continue
			var heading: Vector2 = (b - a) / piece
			var low: Vector2 = a.min(b) - pad
			var high: Vector2 = a.max(b) + pad
			var x0: int = clampi(floori((low.x - _bounds.position.x) / GRID_CELL), 0, _grid_w - 1)
			var x1: int = clampi(floori((high.x - _bounds.position.x) / GRID_CELL), 0, _grid_w - 1)
			var y0: int = clampi(floori((low.y - _bounds.position.y) / GRID_CELL), 0, _grid_h - 1)
			var y1: int = clampi(floori((high.y - _bounds.position.y) / GRID_CELL), 0, _grid_h - 1)
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					var t: int = _cell_head[y * _grid_w + x]
					while t >= 0:
						if (_target_layer[t] & layers) != 0 and _target_id[t] != skip and is_instance_valid(_targets[t]):
							var along: float = clampf((_target_pos[t] - a).dot(heading), 0.0, piece)
							var closest: Vector2 = a + heading * along
							var touch: float = wide + _target_radius[t]
							if closest.distance_squared_to(_target_pos[t]) <= touch * touch:
								found = _ray_keep(nodes, alongs, points, heads, found, wanted, t, start + along, closest, heading)
						t = _target_next[t]
			start += piece
	var got: float = reach
	if found > 0 and found == wanted:
		# The beam is spent on its last target.
		got = alongs[found - 1]
		walled = false
		if got < reach - 0.001:
			# Spent before the gate: it never got there.
			g_gate = -1
	var end: Vector2 = _path_point(used, got)
	var end_heading: Vector2 = _path_heading
	# What it walked, kept for `ray_path` (and its turns' events) past the hit handlers' rays.
	var walk: Array = _ray_walks[level]
	var walked: int = _path_piece + 2
	if walk.size() < walked:
		walk.resize(walked)
	for n in _path_piece + 1:
		walk[n] = _path[n]
	walk[_path_piece + 1] = end
	if not hit:
		for n in found:
			nodes[n] = null
		ray_end = end
		ray_end_heading = end_heading
		_keep_ray_path(walk, walked)
		_set_ray_gate(g_gate, g_at, g_heading, g_left)
		return got
	_ray_depth += 1
	var outer_slot: int = _event_slot
	_event_slot = -1
	for i in found:
		var node: Variant = nodes[i]
		if events != null and is_instance_valid(node):
			impact_form = &"beam"
			impact_core = Color.WHITE
			impact_look = 0
			impact_tag = 0
			events.projectile_impact.emit(caster, node, points[i], heads[i])
			impact_form = &""
			impact_core = Color.WHITE
			impact_look = 0
			events.projectile_hit.emit(caster, node, points[i], tag, -1)
		nodes[i] = null
	# A spark at every wall it turned at before it ended, and at the wall it ended on; then
	# `wall_met` for each (a handler's payload may fire rays: this level's scratch is kept).
	for k in turned:
		var n: int = turns[k]
		if n >= walked - 1:
			break
		var turn: Vector2 = walk[n]
		if events != null:
			impact_form = &"beam"
			impact_core = Color.WHITE
			impact_look = 0
			impact_tag = 0
			events.projectile_impact.emit(caster, null, turn, (walk[n - 1] as Vector2).direction_to(turn))
			impact_form = &""
			impact_core = Color.WHITE
			impact_look = 0
	if walled and events != null:
		impact_form = &"beam"
		impact_core = Color.WHITE
		impact_look = 0
		impact_tag = 0
		events.projectile_impact.emit(caster, null, end, end_heading)
		impact_form = &""
		impact_core = Color.WHITE
		impact_look = 0
	for k in turned:
		var n: int = turns[k]
		if n >= walked - 1:
			break
		var turn: Vector2 = walk[n]
		wall_met.emit(caster, turn, turn.direction_to(walk[n + 1]), tag, -1)
	if walled:
		wall_met.emit(caster, end - end_heading * 0.5, end_heading, tag, -1)
	_ray_depth -= 1
	_event_slot = outer_slot
	ray_end = end
	ray_end_heading = end_heading
	_keep_ray_path(walk, walked)
	_set_ray_gate(g_gate, g_at, g_heading, g_left)
	return got


## What the last ray says of the gate it stopped at (`ray_gate`).
func _set_ray_gate(gate: int, at: Vector2, heading: Vector2, left: float) -> void:
	ray_gate = gate
	ray_gate_at = at
	ray_gate_heading = heading
	ray_gate_left = left


## Copy the first `count` points of `walk` into `ray_path`.
func _keep_ray_path(walk: Array, count: int) -> void:
	if ray_path.size() < count:
		ray_path.resize(maxi(count, ray_path.size() * 2))
	for n in count:
		ray_path[n] = walk[n]
	ray_path_count = count


## The point `distance` pixels along the first `segments` pieces of `_path`; its heading there
## is left in `_path_heading`, and the piece it is on in `_path_piece`.
func _path_point(segments: int, distance: float) -> Vector2:
	var left: float = maxf(distance, 0.0)
	_path_heading = Vector2.ZERO
	_path_piece = 0
	for i in segments:
		var a: Vector2 = _path[i]
		var b: Vector2 = _path[i + 1]
		var piece: float = a.distance_to(b)
		_path_piece = i
		if piece > 0.0:
			_path_heading = (b - a) / piece
		if left <= piece or i == segments - 1:
			return a + _path_heading * minf(left, piece)
		left -= piece
	return _path[0]


## Put target `t` (at `along` pixels, nearest point `closest`, the beam heading `heading` there)
## into a level's sorted scratch of the best hits (`nodes`, `alongs`, `points`, `heads`) if it is
## among the `wanted` nearest; returns the new count. A target a bent beam touches on two pieces
## keeps its nearer place. The scratch grows when it is full.
func _ray_keep(nodes: Array, alongs: Array, points: Array, heads: Array, found: int, wanted: int, t: int, along: float, closest: Vector2, heading: Vector2) -> int:
	for i in found:
		if nodes[i] == _targets[t]:
			if along >= alongs[i]:
				return found
			# Nearer on this piece: take it out and insert it again below.
			for j in range(i, found - 1):
				alongs[j] = alongs[j + 1]
				points[j] = points[j + 1]
				nodes[j] = nodes[j + 1]
				heads[j] = heads[j + 1]
			found -= 1
			nodes[found] = null
			break
	if found == wanted and along >= alongs[found - 1]:
		return found
	if found == nodes.size():
		var size: int = maxi(16, found * 2)
		nodes.resize(size)
		alongs.resize(size)
		points.resize(size)
		heads.resize(size)
	var at: int = mini(found, wanted - 1)
	while at > 0 and alongs[at - 1] > along:
		alongs[at] = alongs[at - 1]
		points[at] = points[at - 1]
		nodes[at] = nodes[at - 1]
		heads[at] = heads[at - 1]
		at -= 1
	alongs[at] = along
	points[at] = closest
	nodes[at] = _targets[t]
	heads[at] = heading
	return mini(found + 1, wanted)


func update_draw(fraction: float = -1.0) -> void:
	spark_birth_count = 0
	if _draw_node == null:
		drawn = 0
		_end_count = 0
		_end_wanted = 0.0
		return
	# A shot that ended since the last frame still lays its tail's end (`_lay_ends`), even if it was
	# never drawn (fired and spent within a step).
	if _high == 0 and drawn == 0 and _end_count == 0:
		return
	if fraction < 0.0:
		fraction = Engine.get_physics_interpolation_fraction()
	fraction = clampf(fraction, 0.0, 1.0)
	for node in _nodes:
		_set_sim_time(node)
	# The native kernel counts and writes every shot when no shot is solid (`_write_stones`); either
	# way `_draw_out` says what was written, into the kernel's buffers or the manager's.
	var kernel_draw: bool = _kernel != null and not _any_solid
	if kernel_draw:
		_kernel.call(&"count_draw", self)
	else:
		_count_batches()
	for batch in _batch_total:
		_rooms[batch] = _fit_batch(_nodes[batch].multimesh, _buffers[batch], _rooms[batch], _batch_counts[batch])
	# Tails as motes (SPARK_TAIL): the drawing lays them, first in the frame's births.
	tail_births_on = spark_motes
	if tail_births_on and spark_births.size() < SPARK_BIRTHS_MAX * SPARK_BIRTH_STRIDE:
		spark_births.resize(SPARK_BIRTHS_MAX * SPARK_BIRTH_STRIDE)
	_plan_groups()
	if kernel_draw:
		_kernel.call(&"draw_shots", self, fraction)
	else:
		_draw_shots(fraction)
	spark_birth_count = _draw_out[DRAW_BIRTHS]
	tail_demand = _draw_out[DRAW_TAIL] + int(_end_wanted)
	if tail_births_on:
		_lay_ends()
	_end_count = 0
	_end_wanted = 0.0
	tail_births = spark_birth_count
	for batch in _batch_total:
		var out: int = _draw_out[DRAW_OUT_FIRST + batch]
		var multimesh: MultiMesh = _nodes[batch].multimesh
		var mirror: MultiMesh = _mirrors[batch] if batch < _mirrors.size() else null
		if mirror != null and mirror.instance_count != multimesh.instance_count:
			mirror.instance_count = multimesh.instance_count
		if out > 0:
			var rows: PackedFloat32Array = _kernel.call(&"buffer", batch) if kernel_draw else _buffers[batch]
			multimesh.buffer = rows
			if mirror != null:
				mirror.buffer = rows
		multimesh.visible_instance_count = out
		if mirror != null:
			mirror.visible_instance_count = out
	var shots_out: int = _draw_out[DRAW_SHOTS]
	drawn_enemy = _draw_out[DRAW_ENEMY]
	drawn = shots_out
	_share_pool(_draw_out[DRAW_ASKED])
	_share_groups()
	_give_off_sparks(fraction)


## Hand out the particles the drawn shots give off since the last frame, as
## births (`spark_births`; see SPARK_BIRTH_STRIDE), while something takes them. The shader's rule, rolled on the
## CPU: at each moment (SPARK_MOMENTS a second) a flying shot gives off one of its kinds, picked at
## random, at that kind's rate (SPARK_RATES) times its group's share of the pool (GROUPS). Rolled
## per birth, not per shot: for each group, a random one of its drawn shots at each of its shots x
## its share tries a moment, kept at the kind's rate, so the work follows the births (the shares
## bound them), not the shots.
func _give_off_sparks(fraction: float) -> void:
	var moment: int = floori((sim_time - (1.0 - fraction) * _last_delta) * SPARK_MOMENTS)
	var moments: int = clampi(moment - _spark_moment, 0, 4) if _spark_moment >= 0 else 1
	_spark_moment = moment
	if not spark_motes or moments == 0:
		return
	if spark_births.size() < SPARK_BIRTHS_MAX * SPARK_BIRTH_STRIDE:
		spark_births.resize(SPARK_BIRTHS_MAX * SPARK_BIRTH_STRIDE)
	if _high == 0:
		return
	var tries_left: int = SPARK_BIRTHS_MAX * 4
	# The steps the frame's moments cover.
	var span: float = float(moments) / SPARK_MOMENTS / maxf(_last_delta, 0.0001)
	for i in _group_live:
		var group: int = _groups[i]
		var first: int = _group_start[group]
		var shots: int = _group_end[group] - first
		if shots == 0:
			continue
		var tries: int = mini(floori(float(shots * moments) * _group_share[group] + _spark_rng.randf()), tries_left)
		tries_left -= tries
		for n in tries:
			if not _give_off_spark(_by_group[first + _spark_rng.randi_range(0, shots - 1)], fraction, span):
				return


## One try of `_give_off_sparks` on the drawn shot in `slot`: a birth of one of its kinds, kept at
## that kind's rate. Returns false once the frame's SPARK_BIRTHS_MAX are taken.
func _give_off_spark(slot: int, fraction: float, span: float) -> bool:
	if _alive[slot] == 0 or _motion[slot] == MOTION_STILL:
		return true
	var bits: int = _look[slot] & EMITTING_MASK
	var kind: int = 0
	if bits != 0:
		kind = _nth_bit(bits, _spark_rng.randi_range(0, _bit_count(bits) - 1)) + 1
	if _spark_rng.randf() >= SPARK_RATES[kind]:
		return true
	# Anywhere on the path it was drawn along since the last frame (the moments since then, back
	# from where it is drawn now): a frame's births never gather in one part of each step, so a
	# held stream of shots does not line them up (the owner, 2026-11-05).
	var step: Vector2 = _pos[slot] - _prev[slot]
	var at: Vector2 = _prev[slot] + step * (fraction - _spark_rng.randf() * span)
	var back: Vector2 = -step
	if _motion[slot] == MOTION_ORBIT:
		at = _drawn_at(slot, at)
		back = -_orbit_tangent(slot)
	return _add_birth(at, back.normalized(), kind, _ramp[slot], _look[slot], _core[slot], _tag[slot])


## One birth (SPARK_BIRTH_STRIDE floats; see there): a particle of look kind `kind` at `at`, given
## off back along `back`, from a shot of the caster's `ramp`, the look `look` and the core colour
## `core`, of the spell tagged `tag` (S2). Returns false once the frame's SPARK_BIRTHS_MAX are taken.
func _add_birth(at: Vector2, back: Vector2, kind: int, ramp: int, look: int, core: Color, tag: int) -> bool:
	_put_birth(spark_births, spark_birth_count, at, back, kind, ramp, look, core, tag)
	spark_birth_count += 1
	return spark_birth_count < SPARK_BIRTHS_MAX


## Write a birth (see `_add_birth`) as birth `n` of `births`.
static func _put_birth(births: PackedFloat32Array, n: int, at: Vector2, back: Vector2, kind: int, ramp: int, look: int, core: Color, tag: int) -> void:
	var i: int = n * SPARK_BIRTH_STRIDE
	births[i + SPARK_X] = at.x
	births[i + SPARK_Y] = at.y
	births[i + SPARK_BACK_X] = back.x
	births[i + SPARK_BACK_Y] = back.y
	births[i + SPARK_KIND] = float(kind)
	births[i + SPARK_RAMP] = float(ramp)
	births[i + SPARK_LOOK] = float(look)
	births[i + SPARK_CORE] = core.r
	births[i + SPARK_CORE + 1] = core.g
	births[i + SPARK_CORE + 2] = core.b
	births[i + SPARK_TAG] = float(tag & ((1 << SPARK_TAG_BITS) - 1))
	births[i + SPARK_TAG + 1] = float(tag >> SPARK_TAG_BITS)


## The tag of the birth that starts at `i` in `births` (SPARK_TAG's two floats).
static func spark_tag(births: PackedFloat32Array, i: int) -> int:
	return int(births[i + SPARK_TAG]) | (int(births[i + SPARK_TAG + 1]) << SPARK_TAG_BITS)


static func _bit_count(bits: int) -> int:
	var n: int = 0
	while bits != 0:
		bits &= bits - 1
		n += 1
	return n


## The place of the `n`-th set bit of `bits` (0 the lowest).
static func _nth_bit(bits: int, n: int) -> int:
	var at: int = 0
	while bits != 0:
		if bits & 1 == 1:
			if n == 0:
				return at
			n -= 1
		bits >>= 1
		at += 1
	return 0


## `update_draw`'s writing (what `ShotKernel.draw_shots` does natively): every live shot into the
## manager's batch buffers at `fraction` of the last step; `_draw_out` gets the instances written per
## batch (BATCH_*), the particles asked for, 0 (was the trails' cost), the shots drawn, the enemy
## shots drawn, the tail births laid and the tail asked for. `_count_batches` brought each shot's drawn data up to date.
func _draw_shots(fraction: float) -> void:
	for batch in _batch_total:
		_draw_out[DRAW_OUT_FIRST + batch] = 0
	_tail_wanted = 0.0
	_tail_thin = 0
	var asked: int = 0
	for slot in _high:
		if _alive[slot] == 0:
			continue
		var motion: int = _motion[slot]
		var at: Vector2 = _prev[slot].lerp(_pos[slot], fraction)
		if motion == MOTION_ORBIT:
			at = _drawn_at(slot, at)
		var batch: int = _drawn_batch[slot]
		var look_data: Color = _drawn_color[slot]
		asked += _drawn_particles[slot]
		var group: int = _group[slot]
		_group_ask[group] += float(maxi(_drawn_particles[slot], 1))
		_by_group[_group_end[group]] = slot
		_group_end[group] += 1
		if motion == MOTION_STILL:
			# Only a rune's quad turns with the shot (a bolt's head is a `+` whatever way it flies).
			var dir: Vector2 = Vector2.RIGHT
			if _vel[slot].length_squared() > 0.0:
				dir = _vel[slot].normalized()
			_draw_out[DRAW_OUT_FIRST + batch] = _write_stones(_buffers[batch], _draw_out[DRAW_OUT_FIRST + batch], slot, dir, _drawn_size[slot], at, look_data)
			continue
		var flags: int = HEAD_LIVE | (HEAD_ORBIT if motion == MOTION_ORBIT else 0)
		var row: int = _draw_out[DRAW_OUT_FIRST + batch] * DRAW_STRIDE
		var buffer: PackedFloat32Array = _buffers[batch]
		_write_head(buffer, row, at, flags, look_data, _core[slot], _pos[slot] - _prev[slot])
		# Its light multipliers in the row's free floats (written inline: a call per shot costs).
		buffer[row + LIGHT_REACH_FLOAT] = _look_light_reach[slot]
		buffer[row + LIGHT_INTENSITY_FLOAT] = _look_light_intensity[slot]
		_draw_out[DRAW_OUT_FIRST + batch] += 1
		if tail_births_on:
			_lay_tail(slot, at)
	var shots: int = 0
	var enemy_shots: int = 0
	for batch in _batch_total:
		shots += _draw_out[DRAW_OUT_FIRST + batch]
		if batch_on_enemy_layer(batch):
			enemy_shots += _draw_out[DRAW_OUT_FIRST + batch]
	_draw_out[DRAW_SHOTS] = shots
	_draw_out[DRAW_ENEMY] = enemy_shots
	_draw_out[DRAW_ASKED] = asked
	_draw_out[DRAW_ASKED + 1] = 0
	_draw_out[DRAW_BIRTHS] = spark_birth_count
	_draw_out[DRAW_TAIL] = int(_tail_wanted)


## Lay the tail of the shot in `slot`, drawn at `at` this frame, as births (SPARK_TAIL; what
## `ShotKernel.draw_shots` does natively, to the bit): along the path from where it was drawn last
## frame, one at its next tail point and every spacing of its group (`_group_spacing`) x 0.5 to 1.5 pixels on from there
## (`tail_hash` of its sequence and its count), while the frame's most lasts (`tail_births_cap`,
## and `tail_thin_most` for a thinned group's; see TAIL_FRESH). A jump
## longer than TAIL_JUMP (a teleport) lays none. An infused shot gives TAIL_PLAYER_SHARE of its
## tail its caster's colours (a white core, so the motes take its hat ramp).
func _lay_tail(slot: int, at: Vector2) -> void:
	var from: Vector2 = _tail_from[slot]
	_tail_from[slot] = at
	_tail_wanted += _lay_path(slot, from, at, false)


## The last stretch of the tail of the shot in `slot`, which ends in flight at `to` (a hit, a wall,
## its life run out, a block): from where it was drawn last to where it ended, which no frame draws
## it along (the owner, 2026-11-06: an Atom fired at a target close by left its tail a step or two
## short, the gap between its last drawn point and the hit). Laid now, while its slot is still its
## own, into `_end_births`; the next frame lays them after the drawn shots' tails (`_lay_ends`).
## A rune (still) lays no tail, and an orbit shot ends where it would have been drawn.
func _end_tail(slot: int, to: Vector2) -> void:
	if not tail_births_on or _motion[slot] == MOTION_STILL:
		return
	if _motion[slot] == MOTION_ORBIT:
		to = _drawn_at(slot, to)
	if _end_births.size() < tail_births_cap * SPARK_BIRTH_STRIDE:
		_end_births.resize(tail_births_cap * SPARK_BIRTH_STRIDE)
	_end_wanted += _lay_path(slot, _tail_from[slot], to, true)


## Lay the tail of the shot in `slot` along the path from `from` to `at` (see `_lay_tail`), from its
## next tail point; `ending`: the last stretch of a shot that ended (`_end_tail`), into
## `_end_births`, else into the frame's births. Returns the tail it asked for (births at
## TAIL_SPACING); none across a jump.
func _lay_path(slot: int, from: Vector2, at: Vector2, ending: bool) -> float:
	var way: Vector2 = at - from
	var d: float = way.length()
	if not (d > 0.0) or d > TAIL_JUMP:
		return 0.0
	var group: int = _group[slot]
	_group_tail[group] += d / TAIL_SPACING
	var spacing: float = _group_spacing[group]
	var thinned: bool = spacing > TAIL_SPACING
	var carry: float = _tail_carry[slot]
	var n: int = _tail_n[slot]
	var seq: int = _seq[slot]
	var core: Color = _core[slot]
	var mixed: bool = not (core.r > 0.99 and core.g > 0.99 and core.b > 0.99)
	var back: Vector2 = way / -d
	var code: int = tail_code(seq)
	while carry < d:
		if ending:
			if _end_count >= tail_births_cap:
				carry = d
				break
		elif spark_birth_count >= tail_births_cap or (thinned and _tail_thin >= tail_thin_most):
			carry = d
			break
		var colour: Color = core
		if mixed and tail_hash(seq, n * 2) < TAIL_PLAYER_SHARE:
			colour = Color.WHITE
		if ending:
			_put_birth(_end_births, _end_count, from.lerp(at, carry / d), back, code, _ramp[slot], _look[slot], colour, _tag[slot])
			_end_count += 1
		else:
			_add_birth(from.lerp(at, carry / d), back, code, _ramp[slot], _look[slot], colour, _tag[slot])
			_tail_thin += 1 if thinned else 0
		carry += spacing * (0.5 + tail_hash(seq, n * 2 + 1))
		n += 1
	_tail_carry[slot] = carry - d
	_tail_n[slot] = n
	return d / TAIL_SPACING


## After the drawn shots' tails: the ended shots' last stretches (`_end_tail`), while the frame's
## most lasts (`tail_births_cap`; they come last, so they never cut a flying shot's tail).
func _lay_ends() -> void:
	var take: int = clampi(tail_births_cap - spark_birth_count, 0, _end_count)
	if take > 0:
		var into: int = spark_birth_count * SPARK_BIRTH_STRIDE
		for i in take * SPARK_BIRTH_STRIDE:
			spark_births[into + i] = _end_births[i]
		spark_birth_count += take
	_end_count = 0
	_end_wanted = 0.0


## The tail code of the shot of sequence `seq` (SPARK_TAIL + 0 to TAIL_KINDS - 1): its tail kind,
## the same every frame (`tail_hash` of its sequence alone; the kernel's `tail_code`).
static func tail_code(seq: int) -> int:
	return SPARK_TAIL + mini(floori(tail_hash(seq, -1) * TAIL_KINDS), TAIL_KINDS - 1)


## Whether `kind` (a birth's SPARK_KIND) is a tail's: SPARK_TAIL to SPARK_TAIL + TAIL_KINDS - 1.
static func is_tail_code(kind: int) -> bool:
	return kind >= SPARK_TAIL and kind < SPARK_TAIL + TAIL_KINDS


## A number from 0 up to 1 for the pair (`a`, `b`), the same every time (and in the native
## kernel): the tails' dice (`_lay_tail`).
static func tail_hash(a: int, b: int) -> float:
	# Every product stays below 2^63, so GDScript's ints and the kernel's agree.
	var h: int = ((a & 0xFFFFFFFF) * 374761393 + (b & 0xFFFFFFFF) * 668265263) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / 16777216.0


## The group of a shot of the actor `caster` with `tag` (see GROUPS): the caster's staff for a
## spell's shot (`SpellTag.staff_of`), the caster's first for a shot of no spell.
static func group_of(caster: int, tag: int) -> int:
	var staff: int = SpellTag.staff_of(tag) if SpellTag.is_spell_tag(tag) else 0
	return clampi(caster, 0, ACTORS - 1) * GROUP_STAFFS + staff


## The level that shares `cap` out fairly among the asks in `sorted` (smallest first): every ask
## up to it is given whole, every larger one this much, and all of them together `cap`. INF when
## all of them fit.
static func fair_level(sorted: PackedFloat32Array, cap: float) -> float:
	var left: float = cap
	var count: int = sorted.size()
	for i in count:
		var level: float = left / float(count - i)
		if sorted[i] > level:
			return level
		left -= sorted[i]
	return INF


## The shot in `slot` joins `group` (see GROUPS).
func _join_group(slot: int, group: int) -> void:
	_group[slot] = group
	if _group_count[group] == 0:
		_group_at[group] = _group_live
		_groups[_group_live] = group
		_group_live += 1
	_group_count[group] += 1


## The shot in `slot` leaves its group; a group with no shots left leaves the live ones.
func _leave_group(slot: int) -> void:
	var group: int = _group[slot]
	_group_count[group] -= 1
	if _group_count[group] == 0:
		var at: int = _group_at[group]
		_group_live -= 1
		var last: int = _groups[_group_live]
		_groups[at] = last
		_group_at[last] = at


## Before the drawing: place each live group's shots in `_by_group` (the drawing fills them in) and
## share the frame's tail births out among the groups (see GROUPS). A group's ask is the tail it
## asked for last frame, scaled by its shots now against then (a Storm that split since asks for
## that much more); a group new since the last frame asks for nothing yet, so a new cast's tail is
## whole from its first frame. The fair level shares TAIL_FRESH less than the most; a group's
## spacing is TAIL_SPACING, wider by its ask over the level, and the thinned groups lay at most
## the level each (`tail_thin_most`).
func _plan_groups() -> void:
	_draw_frame += 1
	if _group_sort.size() != _group_live:
		_group_sort.resize(_group_live)
	var at: int = 0
	for i in _group_live:
		var group: int = _groups[i]
		var count: int = _group_count[group]
		_group_start[group] = at
		_group_end[group] = at
		at += count
		var want: float = 0.0
		if _group_frame[group] == _draw_frame - 1 and _group_seen[group] > 0:
			want = _group_tail[group] * float(count) / float(_group_seen[group])
		_group_want[group] = want
		_group_sort[i] = want
		_group_frame[group] = _draw_frame
		_group_seen[group] = count
		_group_tail[group] = 0.0
		_group_ask[group] = 0.0
	_group_sort.sort()
	var level: float = maxf(fair_level(_group_sort, float(tail_births_cap) * (1.0 - TAIL_FRESH)), 0.0001)
	var thin: float = 0.0
	tail_spacing = TAIL_SPACING
	for i in _group_live:
		var group: int = _groups[i]
		_group_spacing[group] = TAIL_SPACING * maxf(1.0, _group_want[group] / level)
		tail_spacing = maxf(tail_spacing, _group_spacing[group])
		if _group_spacing[group] > TAIL_SPACING:
			thin += level
	tail_thin_most = ceili(thin)


## After the drawing: each group's share of the particles it asked for (`_group_share`, for
## `_give_off_sparks`): the pool's count shared out fairly among the groups (see GROUPS).
func _share_groups() -> void:
	for i in _group_live:
		_group_sort[i] = _group_ask[_groups[i]]
	_group_sort.sort()
	var level: float = fair_level(_group_sort, float(maxi(tailless_particle_cap, 0)))
	for i in _group_live:
		var group: int = _groups[i]
		var ask: float = _group_ask[group]
		_group_share[group] = 1.0 if ask <= level else level / ask


## Write the rune quad of the still shot in `slot` drawn at `at` into `buffer` from instance
## `out` on, one for each stone of a solid shot's row; returns the instance after the last.
func _write_stones(buffer: PackedFloat32Array, out: int, slot: int, dir: Vector2, size: float, at: Vector2, look_data: Color) -> int:
	var stones: int = 1
	var step: Vector2 = Vector2.ZERO
	if _any_solid and _solids.has(slot):
		var solid: Solid = _solids[slot]
		stones = solid.stones
		step = solid.across * solid.gap * _radius[slot]
		at -= _solid_half(slot, solid)
	var code: float = trace_code(sim_time - _born[slot])
	var kind: int = _kind_of(slot)
	var light_reach: float = _look_light_reach[slot]
	var light_intensity: float = _look_light_intensity[slot]
	# A batch holds the cap at most: stones past it are not drawn.
	for n in mini(stones, buffer.size() / DRAW_STRIDE - out):
		var i: int = out * DRAW_STRIDE
		_write_quad(buffer, i, dir, size, at + step * n, look_data, _core[slot], kind, 0.0, code)
		# Its light multipliers in the row's free floats (written inline: a call per shot costs).
		buffer[i + LIGHT_REACH_FLOAT] = light_reach
		buffer[i + LIGHT_INTENSITY_FLOAT] = light_intensity
		out += 1
	return out


## Work out what `update_draw` keeps for the shot in `slot` (see `_drawn_seq`).
func _remember_drawn(slot: int) -> void:
	_drawn_seq[slot] = _seq[slot]
	_drawn_radius[slot] = _radius[slot]
	_drawn_look[slot] = _look[slot]
	_drawn_batch[slot] = _batch_of(slot)
	_drawn_color[slot] = _look_color(slot)
	_drawn_size[slot] = look_size(_radius[slot])
	_drawn_particles[slot] = particles_of(_look[slot])


## Hand the shader the simulation clock (the shot shaders animate from it).
func _set_sim_time(node: MultiMeshInstance2D) -> void:
	var material: ShaderMaterial = node.material as ShaderMaterial
	material.set_shader_parameter(&"sim_time", sim_time)


## Share the spark pool out for a frame that asked for `asked` particles (see
## TAILLESS_PARTICLE_CAP): past the pool's count every shot's births thin alike.
func _share_pool(asked: int) -> void:
	particle_demand = asked
	var cap: float = float(maxi(tailless_particle_cap, 0))
	particle_share = 1.0 if asked <= 0 else minf(1.0, cap / float(asked))
	for node in _nodes:
		_set_shares(node)


func _set_shares(node: MultiMeshInstance2D) -> void:
	var material: ShaderMaterial = node.material as ShaderMaterial
	material.set_shader_parameter(&"particle_share", particle_share)


## How many particles the pool is asked for by a shot with the packed `look`: 4 + 2 per
## emitting kind (every kind but the weave, which changes the body), at most 12; none for a
## plain shot. The shot shaders that give particles off (`shot_still.gdshader`, `shot_orbit.gdshader`
## and every card's own shot shader) hold the same rule; keep them equal.
static func particles_of(look: int) -> int:
	if look == 0:
		return 0
	var bits: int = look & EMITTING_MASK
	var kinds: int = 0
	while bits != 0:
		bits &= bits - 1
		kinds += 1
	if kinds == 0:
		return 0
	return mini(4 + 2 * kinds, PARTICLES_PER_SHOT_MAX)


## Which draw batch a live slot belongs to (BATCH_*), by its ramp and body. The one rule both the counting and the writing use, so a batch
## always has the room its writes need.
func _batch_of(slot: int) -> int:
	# A card body draws its shot only while the shot's motion is written as the body's mesh; a shot
	# whose motion changed past it (or a card's shader numbered for the other mesh) draws plain.
	var body: int = _body[slot]
	if body > 0 and _body_meshes[body - 1] == mesh_of_motion(_motion[slot]):
		return body_batch(body, not is_hat_ramp(_ramp[slot]))
	if not is_hat_ramp(_ramp[slot]):
		return BATCH_ENEMY_STILL if _motion[slot] == MOTION_STILL else BATCH_ENEMY
	if _motion[slot] == MOTION_STILL:
		return BATCH_STILL
	if _motion[slot] == MOTION_ORBIT:
		return BATCH_ORBIT
	return BATCH_BOLT


## The body a shot has to the world (KIND_BOLT, KIND_RUNE or KIND_ORBIT): its motion's. A still
## shot is a rune however it is drawn (a card body is its batch's shader).
func _kind_of(slot: int) -> int:
	if _motion[slot] == MOTION_STILL:
		return KIND_RUNE
	if _motion[slot] == MOTION_ORBIT:
		return KIND_ORBIT
	return KIND_BOLT


## Count the live shots each batch will draw into _batch_counts, indexed by BATCH_*, and bring
## each live shot's drawn data up to date (`_drawn_seq`). One extra pass over the live slots: the
## price of sizing before writing.
func _count_batches() -> void:
	_batch_counts.fill(0)
	for slot in _high:
		if _alive[slot] != 0:
			if _drawn_seq[slot] != _seq[slot] or _drawn_radius[slot] != _radius[slot] or _drawn_look[slot] != _look[slot]:
				_remember_drawn(slot)
			# A solid shot draws a quad for every stone of its row.
			_batch_counts[_drawn_batch[slot]] += 1 if not _any_solid or not _solids.has(slot) else (_solids[slot] as Solid).stones


## Size a batch's MultiMesh and buffer to draw `used` shots; returns the new room.
## The room stays while `used` fits and is more than a quarter of it, else it becomes
## `used` rounded up to a power of two (at least MIN_BATCH, at most the cap). An empty
## batch keeps its room: nothing is uploaded for it, and it does not reallocate when it
## flickers between empty and busy. The MultiMesh buffer must be exactly instance_count
## x DRAW_STRIDE floats, so a smaller upload means a smaller MultiMesh. The buffer is
## shared, not copied, so resizing it here resizes the caller's.
func _fit_batch(multimesh: MultiMesh, buffer: PackedFloat32Array, room: int, used: int, limit: int = -1) -> int:
	if used == 0 or (used <= room and used * 4 > room):
		return room
	var wanted: int = MIN_BATCH
	while wanted < used:
		wanted *= 2
	wanted = mini(wanted, _cap if limit < 0 else limit)
	if wanted != room:
		multimesh.instance_count = wanted
		buffer.resize(wanted * DRAW_STRIDE)
	return wanted


## The zoom of a shot of hit radius `radius` (see LOOK_CELL_PER_RADIUS).
static func look_zoom(radius: float) -> int:
	return clampi(roundi(radius * LOOK_CELL_PER_RADIUS), 1, LOOK_ZOOM_MAX)


## The zoom a shot of hit radius `radius` tells its shaders: its `look_zoom`, or 0 for a speck
## (below SPECK_RADIUS), whose core the head shader draws as one pixel.
static func look_core_zoom(radius: float) -> int:
	return 0 if radius < SPECK_RADIUS else look_zoom(radius)


## The drawn size in pixels of a shot of hit radius `radius`.
static func look_size(radius: float) -> float:
	return float(LOOK_GRID * look_zoom(radius))


## The drawn length in pixels of a bolt or orbit shot of hit radius `radius`: the shot and its tail.
static func look_length(radius: float) -> float:
	return float(LOOK_LENGTH * look_zoom(radius))


## How far behind a bolt or orbit shot of hit radius `radius` the middle of its quad is (the
## quad reaches look_size / 2 ahead of the shot and the rest behind it).
static func look_back(radius: float) -> float:
	return (look_length(radius) - look_size(radius)) * 0.5


## The code a bend travels as beside the kind (see BEND_ZERO).
static func bend_code(bend: float) -> float:
	return BEND_ZERO + BEND_SPAN * clampf(bend * BEND_RADIUS, -1.0, 1.0)


## The code of a rune `age` seconds old (see RUNE_TRACE): how much of it is traced, 0 when whole.
static func trace_code(age: float) -> float:
	if age >= RUNE_TRACE or age < 0.0:
		return 0.0
	return TRACE_FROM + TRACE_SPAN * age / RUNE_TRACE


## The instance colour of a shot, which the shot shaders read as data, a byte per
## channel: the hat ramp and the zoom in red (`look_red`), the look's bits in green (kinds 1-8),
## blue (9-16) and alpha (17-24; `ramp_look` adds the enemy ramp's flag).
func _look_color(slot: int) -> Color:
	return look_color(_ramp[slot], look_core_zoom(_radius[slot]), _look[slot])


## The instance colour the shot shaders read for a shot or effect in `ramp` (`Actors.
## ramp_of` of its caster: 0-3 a hat ramp, anything else the enemy ramp) at `zoom` (or a dash's
## length in steps, up to 63) with the packed `look`. Feel's effects and Entities' familiars use
## it too, so the encoding lives in one place.
static func look_color(ramp: int, zoom: int, look: int) -> Color:
	var bits: int = ramp_look(ramp, look)
	return Color(float(look_red(ramp, zoom)) / 255.0, float(bits & 255) / 255.0, float((bits >> 8) & 255) / 255.0, float((bits >> 16) & 255) / 255.0)


## `look_color` for the actor `caster`'s ramp (a shot or an effect of its).
func look_color_for(caster: int, zoom: int, look: int) -> Color:
	return look_color(_ramp_of(caster), zoom, look)


## The red byte of the instance colour: the hat ramp (0-3; 0 for the enemy ramp, which is a
## look flag) plus the zoom x 4.
static func look_red(ramp: int, zoom: int) -> int:
	return (ramp if is_hat_ramp(ramp) else 0) + clampi(zoom, 0, 63) * 4


## `look` with the enemy ramp's flag for any ramp that is not a hat ramp (the enemy ramp, or no
## actor's), without it for a hat ramp.
static func ramp_look(ramp: int, look: int) -> int:
	return look & ~LOOK_ENEMY_RAMP if is_hat_ramp(ramp) else look | LOOK_ENEMY_RAMP


## Write one quad at float index `i` of `buffer` (packed arrays are shared, not copied):
## Transform2D(dir * length, dir.orthogonal() * d, centre), row by row, then the colour and the
## colour of the core (custom data). A square quad (`length` 0) is centred on `at`; a long one
## reaches `diameter` / 2 ahead of `at` and the rest behind it (a bolt and its tail).
## `kind` (0 the texture, KIND_BOLT, KIND_RUNE or KIND_ORBIT; at most KIND_MAX) and `code`
## (0 to below 0.5: a bend, `bend_code`, or a rune's trace, `trace_code`) go in the alpha of the
## custom data as 1 - (kind + code) / 16, which the shot shaders read back.
func _write_quad(buffer: PackedFloat32Array, i: int, dir: Vector2, diameter: float, at: Vector2, color: Color, core: Color, kind: int, length: float = 0.0, code: float = 0.0) -> void:
	assert(kind >= 0 and kind <= KIND_MAX, "the kind must fit the alpha encoding")
	assert(code >= 0.0 and code < 0.5, "the code must round away from the kind")
	var along: float = diameter
	var centre: Vector2 = at
	if length > 0.0:
		along = length
		centre = at - dir * (length - diameter) * 0.5
	buffer[i] = dir.x * along
	buffer[i + 1] = dir.y * diameter
	buffer[i + 2] = 0.0
	buffer[i + 3] = centre.x
	buffer[i + 4] = dir.y * along
	buffer[i + 5] = -dir.x * diameter
	buffer[i + 6] = 0.0
	buffer[i + 7] = centre.y
	buffer[i + 8] = color.r
	buffer[i + 9] = color.g
	buffer[i + 10] = color.b
	buffer[i + 11] = color.a
	buffer[i + 12] = core.r
	buffer[i + 13] = core.g
	buffer[i + 14] = core.b
	buffer[i + 15] = 1.0 - (kind + code) / KIND_STEPS


## Write a live shot's instance at float index `i` of `buffer`: its data in the transform, which
## `shot_head.gdshader` reads back (its quads are placed from it; the batch sits untransformed at
## the origin): the head `at`, no path (-1: a tail is motes), the way it flies `way`, its flags, the
## colour and the core.
func _write_head(buffer: PackedFloat32Array, i: int, at: Vector2, flags: int, color: Color, core: Color, way: Vector2) -> void:
	buffer[i] = -1.0
	buffer[i + 1] = way.x
	buffer[i + 2] = 0.0
	buffer[i + 3] = at.x
	buffer[i + 4] = way.y
	buffer[i + 5] = float(flags)
	buffer[i + 6] = 0.0
	buffer[i + 7] = at.y
	buffer[i + 8] = color.r
	buffer[i + 9] = color.g
	buffer[i + 10] = color.b
	buffer[i + 11] = color.a
	buffer[i + 12] = core.r
	buffer[i + 13] = core.g
	buffer[i + 14] = core.b
	buffer[i + 15] = 1.0 - float(KIND_BOLT) / KIND_STEPS


## Position of a live projectile, or Vector2.INF if the slot is empty.
func get_position_of(slot: int) -> Vector2:
	if slot < 0 or slot >= _cap or _alive[slot] == 0:
		return Vector2.INF
	return _pos[slot]


func is_alive(slot: int) -> bool:
	return slot >= 0 and slot < _cap and _alive[slot] != 0


## The tint of the bone body of the actor `caster`'s shots, by its ramp (the enemy ramp's for
## no actor), also used for the beams and rings `feel` draws.
func tint_of(caster: int) -> Color:
	return ramp_tint(_ramp_of(caster))


## The tint of `ramp` (see `tint_of`): a hat ramp's, or the enemy ramp's for any other.
static func ramp_tint(ramp: int) -> Color:
	return Color.WHITE.lerp(ramp_color(ramp), TINT_STRENGTH)


## The base colour of `ramp` (`RAMP_COLORS`): a hat colour, or Blight ochre for any other.
static func ramp_color(ramp: int) -> Color:
	return RAMP_COLORS[ramp] if is_hat_ramp(ramp) else RAMP_COLORS[ActorsScript.RAMP_ENEMY]


## The light shade of `ramp` (`RAMP_LIGHT_COLORS`): a hat colour's, or Blight's for any other.
static func ramp_light(ramp: int) -> Color:
	return RAMP_LIGHT_COLORS[ramp] if is_hat_ramp(ramp) else RAMP_LIGHT_COLORS[ActorsScript.RAMP_ENEMY]


func _kill(slot: int, announce: bool = true) -> void:
	_forget_all(slot)
	if _any_solid and _solids.has(slot):
		_drop_solid(slot)
	_drop_moves(slot)
	if announce and _tag[slot] != 0:
		shot_ended.emit(_tag[slot])
	if _kinds[slot] != 0:
		_leave_all(slot)
	_alive[slot] = 0
	_state[slot] = S_IDLE
	_leave_group(slot)
	_free_slots[_free_count] = slot
	_free_count += 1
	_count -= 1
	var owner_index: int = _budget[slot]
	_owned[owner_index] -= 1
	var before: int = _own_prev[slot]
	var after: int = _own_next[slot]
	if before >= 0:
		_own_next[before] = after
	else:
		_own_head[owner_index] = after
	if after >= 0:
		_own_prev[after] = before
	else:
		_own_tail[owner_index] = before
	while _high > 0 and _alive[_high - 1] == 0:
		_high -= 1


## End a shot whose life ran out or that met a wall, and say so.
func _expire(slot: int) -> void:
	var caster: int = _actor[slot]
	var at: Vector2 = _pos[slot]
	var tag: int = _tag[slot]
	_end_tail(slot, at)
	_kill(slot, false)
	if events != null:
		_event_slot = slot
		impact_form = _form_of(slot)
		impact_body = _kind_of(slot)
		impact_core = _core[slot]
		impact_look = _look[slot]
		impact_tag = tag
		impact_heading = _vel[slot].normalized()
		events.projectile_expired.emit(caster, at, tag, slot)
		impact_form = &""
		impact_body = 0
		impact_core = Color.WHITE
		impact_look = 0
		impact_tag = 0
		impact_heading = Vector2.ZERO
		_event_slot = -1
	if tag != 0:
		shot_ended.emit(tag)


## Remove, quietly (no event, no `shot_ended`), every shot carrying `tag`. Returns how
## many. For the spell runtime, when a tag is revoked. Walks the pool: not for every frame.
func remove_by_tag(tag: int) -> int:
	var removed: int = 0
	for slot in _high:
		if _alive[slot] != 0 and _tag[slot] == tag:
			_kill(slot, false)
			removed += 1
	return removed


## A local stop (hit-stop in co-op, melee I7): the shot in `slot` holds where it is for `seconds` of
## simulation, its life and motion paused, while every other shot flies on. The longer of two
## stops stands. Returns false for a shot that is not alive.
func freeze_shot(slot: int, seconds: float) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or seconds <= 0.0:
		return false
	_freeze[slot] = maxf(_freeze[slot], seconds)
	return true


## Seconds left of the local stop on the shot in `slot` (0 when it flies).
func freeze_left_of(slot: int) -> float:
	return _freeze[slot] if slot >= 0 and slot < _cap and _alive[slot] != 0 else 0.0


## Keep the shot in `slot` from hitting `node` for `seconds` (a payload must not hit the
## target that fired it). One target per shot; a later call replaces it.
## True when the circle (`point`, `radius`) overlaps the hit circle of the registered target
## `node` where it stands now (its node's place and offset, as each step reads it). False for a
## node that is not registered, freed or out of the tree.
func touches_target(node: Node, point: Vector2, radius: float) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var at: int = _target_id.find(node.get_instance_id())
	if at < 0:
		return false
	var body: Node2D = _targets[at] as Node2D
	if body == null or not body.is_inside_tree():
		return false
	return point.distance_to(body.global_position + _target_offset[at]) <= _target_radius[at] + radius


## The shot in `slot` does not hit `node` (the body it started on: its caster's own, or the body whose
## hit fired it, as a payload; the spell runtime gives every launch one) until it has
## been clear of it: the first hit test whose step starts with the shot off that body's hit circle
## ends the exclusion (`_still_spares`), and from then on it hits that body as any other (owner,
## 2026-11-06: no timer, so a slow shot born on its source can no longer hit it as it crawls out).
## A body its own caster owns is the one it was cast from, at the staff tip off that body: how far
## off it was cast (`_skip_near`) it still spares the body while coming at it, so a shot aimed back
## across its caster (a nova's, a mirror's) passes them (owner, 2026-11-07).
func exclude(slot: int, node: Node) -> void:
	if slot >= 0 and slot < _cap and _alive[slot] != 0 and node != null:
		# Kept by its key (N5); a node that is no target (none registered) is never hit anyway.
		var at: int = _target_id.find(node.get_instance_id())
		_skip_id[slot] = _target_key[at] if at >= 0 else 0
		_skip_on[slot] = 1.0
		_skip_near[slot] = 0.0
		if at < 0 or _actor[slot] < 0 or _target_owner[at] != _actor[slot]:
			return
		var body: Node2D = _targets[at] as Node2D
		if body == null or not body.is_inside_tree():
			return
		var off: float = _pos[slot].distance_to(body.global_position + _target_offset[at]) - _radius[slot] - _target_radius[at]
		_skip_near[slot] = off if off > 0.0 and is_finite(off) else 0.0


## The spawn number of the shot in `slot`: it changes when the slot is reused, so a
## listener can tell a shot it knows from a newer one in the same slot.
func get_seq_of(slot: int) -> int:
	return _seq[slot] if slot >= 0 and slot < _cap else -1


## The tag of the shot in `slot` (kept after it ended, until the slot is reused).
func get_tag_of(slot: int) -> int:
	return _tag[slot] if slot >= 0 and slot < _cap else 0


## The actor whose shot the shot in `slot` is now (a deflect changes it), -1 for none.
func get_actor_of(slot: int) -> int:
	return _actor[slot] if slot >= 0 and slot < _cap else -1


## The seconds the shot in `slot` has left to live, 0 for an empty slot.
func get_life_of(slot: int) -> float:
	return _life[slot] if is_alive(slot) else 0.0


## The seconds the shot in `slot` was spawned to live (its whole life), 0 for an empty slot.
func get_span_of(slot: int) -> float:
	return _span[slot] if is_alive(slot) else 0.0


## The hit radius of the shot in `slot` now (growth included), or 0 for an empty slot.
func get_radius_of(slot: int) -> float:
	return _radius[slot] if is_alive(slot) else 0.0


## The velocity of the shot in `slot` (kept after it ended, until the slot is reused).
func get_velocity_of(slot: int) -> Vector2:
	return _vel[slot] if slot >= 0 and slot < _cap else Vector2.ZERO


## Where the actor `caster`'s anchor is (see `set_anchor`), or `Vector2.INF` when it has none.
func get_anchor(caster: int) -> Vector2:
	return _anchors[caster] if caster >= 0 and caster < ACTORS else Vector2.INF


## The actor a registered target belongs to (`add_target`'s `owner`), or `Events.NO_PLAYER`
## for a target no actor owns, an unknown node or null.
func target_owner_of(node: Node) -> int:
	if node == null or not is_instance_valid(node):
		return EventsScript.NO_PLAYER
	var at: int = _target_id.find(node.get_instance_id())
	return EventsScript.NO_PLAYER if at < 0 else _target_owner[at]


## The identity of the registered target `node` (`_target_key`, online-ready N5: its actor's key),
## or 0 for a node that is not registered. What the simulation keeps for "that body" (a chain's last
## body, a zap's roll for it) is this, never an instance id.
func key_of(node: Node) -> int:
	if node == null or not is_instance_valid(node):
		return 0
	var at: int = _target_id.find(node.get_instance_id())
	return _target_key[at] if at >= 0 else 0


## The registered target whose key is `key` (`key_of`), or null: none, or no longer registered.
func target_of_key(key: int) -> Node2D:
	if key == 0:
		return null
	var at: int = _target_key.find(key)
	if at < 0 or not is_instance_valid(_targets[at]):
		return null
	return _targets[at] as Node2D


## The key (`_target_key`) of the target the last `homing_point`, `homing_aim` or `home_velocity`
## picked, 0 for none: hand it back as `keep` so a homing thing stays on one target. And that
## target's hit radius (0 for none), for something that stops at its edge (a teleport).
var homing_target: int = 0
var homing_target_radius: float = 0.0

## Where the target `nearest_target` last returned is (its hit circle's centre).
var nearest_point: Vector2 = Vector2.INF


## Make room: drop the oldest projectile of the budget with the most (the shared one on a tie,
## so the seats keep theirs).
func _drop_one() -> void:
	var richest: int = ActorsScript.SHARED
	for i in ActorsScript.SHARED:
		if _owned[i] > _owned[richest]:
			richest = i
	_kill(_own_head[richest])
	dropped += 1


func _remove_target_at(at: int) -> void:
	var last: int = _targets.size() - 1
	_targets[at] = _targets[last]
	_target_id[at] = _target_id[last]
	_target_key[at] = _target_key[last]
	_target_radius[at] = _target_radius[last]
	_target_layer[at] = _target_layer[last]
	_target_owner[at] = _target_owner[last]
	_target_team[at] = _target_team[last]
	_target_pos[at] = _target_pos[last]
	_target_offset[at] = _target_offset[last]
	_targets.resize(last)
	_target_id.resize(last)
	_target_key.resize(last)
	_target_radius.resize(last)
	_target_layer.resize(last)
	_target_owner.resize(last)
	_target_team.resize(last)
	_target_pos.resize(last)
	_target_offset.resize(last)
	_target_next.resize(last)


## Drop freed targets, read the positions of the rest and fill the grid.
func _refresh_targets() -> void:
	_cell_head.fill(-1)
	_grid_stale = false
	# A new filling: every cell's count and box are taken again when first needed (`_cell_info`).
	_grid_fill += 1
	# The table once for every target (this runs every step for every body).
	var table: ActorsScript = actor_table()
	var grid_x: float = _grid_x
	var grid_y: float = _grid_y
	var last_x: int = _grid_w - 1
	var last_y: int = _grid_h - 1
	var width: int = _grid_w
	# Every actor's team at once (the table's own array, read only): a call per target cost more
	# than the rest of its filling.
	var teams: PackedInt32Array = table.teams() if table != null else PackedInt32Array()
	var team_rows: int = teams.size()
	# One pass: a freed or removed target is dropped where it is found (the last one takes its
	# index and is read next), so the indices and the chains come out as a drop pass and then a
	# fill pass would leave them. Written out: every target, every step (Horde swarm S5).
	var i: int = 0
	while i < _targets.size():
		var held: Variant = _targets[i]
		if _target_layer[i] == 0 or not is_instance_valid(held):
			_remove_target_at(i)
			continue
		var node: Node2D = held
		# A possession may have moved the owner to another team since the last step
		# (`_team_of_target`, written out: `teams` is `team_of` for every id).
		var owner: int = _target_owner[i]
		var team: int = teams[owner] if owner >= 0 and owner < team_rows else ActorsScript.NONE
		if team == ActorsScript.NONE:
			team = ActorsScript.TEAM_WIZARDS if (_target_layer[i] & LAYER_PLAYER) != 0 else ActorsScript.TEAM_ENEMIES
		_target_team[i] = team
		if not node.is_inside_tree():
			_target_pos[i] = Vector2.INF
			_target_next[i] = -1
			i += 1
			continue
		var centre: Vector2 = node.global_position + _target_offset[i]
		_target_pos[i] = centre
		var cell: int = clampi(floori((centre.y - grid_y) / GRID_CELL), 0, last_y) * width + clampi(floori((centre.x - grid_x) / GRID_CELL), 0, last_x)
		_target_next[i] = _cell_head[cell]
		_cell_head[cell] = i
		i += 1


## The nearest target on `layers` whose hit circle overlaps the circle (`point`,
## `radius`), by distance to its centre, or null. `exclude` is skipped (the target
## just hit, for a chain) and so is `exclude_also`. With a `team` (not NONE), targets of that
## team are skipped too: aim at other teams (a chain's jump, an arc's zap, a familiar's cast).
## The hit circle's centre of the target returned is left in `nearest_point`. Allocation-free.
func nearest_target(point: Vector2, radius: float, layers: int, exclude: Node2D = null, exclude_also: Node2D = null, team: int = ActorsScript.NONE) -> Node2D:
	nearest_point = Vector2.INF
	if not point.is_finite() or not is_finite(radius):
		return null
	var best: int = -1
	var best_sq: float = INF
	var skip: int = exclude.get_instance_id() if exclude != null else 0
	var skip_also: int = exclude_also.get_instance_id() if exclude_also != null else 0
	_query_ready()
	var cells: Vector4i = _query_cells(point, radius)
	for y in range(cells.y, cells.w + 1):
		for x in range(cells.x, cells.z + 1):
			var t: int = _cell_head[y * _grid_w + x]
			while t >= 0:
				if _query_match(t, point, radius, layers, skip) and (skip_also == 0 or _target_id[t] != skip_also) and (team == ActorsScript.NONE or _target_team[t] != team):
					var d: float = _target_pos[t].distance_squared_to(point)
					if d < best_sq:
						best_sq = d
						best = t
				t = _target_next[t]
	if best < 0:
		return null
	nearest_point = _target_pos[best]
	return _targets[best]


## Fill `out` with the targets on `layers` not of `team` (Actors.NONE: of any) whose hit circle
## overlaps the circle (`point`, `radius`), `centres` with where each one's hit circle is and
## `radii` with how big, in the same order; return how many (a zap's bodies in reach). Order is the grid's: the same every
## run. With a finite `to`, the circles round every point of the line from `point` to `to` (a
## beam's zap, a piece of its path at a time); with `keep`, `out` is added to, not cleared, and a
## target already in it is not added again. Pass the same arrays each time: nothing is allocated once they have grown.
func targets_near(point: Vector2, radius: float, layers: int, team: int, out: Array[Node2D], centres: PackedVector2Array, radii: PackedFloat32Array, to: Vector2 = Vector2.INF, keep: bool = false) -> int:
	if not keep:
		out.clear()
	if not point.is_finite() or not is_finite(radius):
		return out.size()
	var end: Vector2 = to if to.is_finite() else point
	_query_ready()
	var cells: Vector4i = _query_cells((point + end) * 0.5, radius + point.distance_to(end) * 0.5)
	for y in range(cells.y, cells.w + 1):
		for x in range(cells.x, cells.z + 1):
			var t: int = _cell_head[y * _grid_w + x]
			while t >= 0:
				var at: Vector2 = point if end == point else Geometry2D.get_closest_point_to_segment(_target_pos[t], point, end)
				if _query_match(t, at, radius, layers, 0) and (team == ActorsScript.NONE or _target_team[t] != team) and not (keep and out.has(_targets[t])):
					if centres.size() <= out.size():
						centres.resize(maxi(out.size() * 2, 8))
						radii.resize(centres.size())
					centres[out.size()] = _target_pos[t]
					radii[out.size()] = _target_radius[t]
					out.append(_targets[t])
				t = _target_next[t]
	return out.size()


## Fill `out` (cleared first) with the targets on `layers` whose hit circle overlaps
## the circle (`point`, `radius`), and return how many; with a finite `to`, the circles round
## every point of the line from `point` to `to` (a beam's magnet). Pass the same array each time
## so nothing is allocated. Order is not defined.
func targets_in(point: Vector2, radius: float, layers: int, out: Array[Node2D], to: Vector2 = Vector2.INF) -> int:
	out.clear()
	if not point.is_finite() or not is_finite(radius):
		return 0
	var end: Vector2 = to if to.is_finite() else point
	_query_ready()
	var cells: Vector4i = _query_cells((point + end) * 0.5, radius + point.distance_to(end) * 0.5)
	for y in range(cells.y, cells.w + 1):
		for x in range(cells.x, cells.z + 1):
			var t: int = _cell_head[y * _grid_w + x]
			while t >= 0:
				if _query_match(t, Geometry2D.get_closest_point_to_segment(_target_pos[t], point, end), radius, layers, 0):
					out.append(_targets[t])
				t = _target_next[t]
	return out.size()


## Fill the grid when targets were added since it was last filled. Never inside a
## step, where the grid is in use and already current.
func _query_ready() -> void:
	if _grid_stale and not _stepping:
		_refresh_targets()


## The grid cells (x0, y0, x1, y1) a query circle can reach.
func _query_cells(point: Vector2, radius: float) -> Vector4i:
	var pad: Vector2 = Vector2.ONE * (maxf(radius, 0.0) + _max_target_radius)
	var low: Vector2 = point - pad
	var high: Vector2 = point + pad
	return Vector4i(
		clampi(floori((low.x - _bounds.position.x) / GRID_CELL), 0, _grid_w - 1),
		clampi(floori((low.y - _bounds.position.y) / GRID_CELL), 0, _grid_h - 1),
		clampi(floori((high.x - _bounds.position.x) / GRID_CELL), 0, _grid_w - 1),
		clampi(floori((high.y - _bounds.position.y) / GRID_CELL), 0, _grid_h - 1))


func _query_match(t: int, point: Vector2, radius: float, layers: int, skip: int) -> bool:
	# A target freed since the grid was filled is skipped, never returned.
	if (_target_layer[t] & layers) == 0 or _target_id[t] == skip or not is_instance_valid(_targets[t]):
		return false
	var reach: float = maxf(radius, 0.0) + _target_radius[t]
	return _target_pos[t].distance_squared_to(point) <= reach * reach


## Test the path of the shot in `slot` this step against the targets on the grid, and hit every
## target it touches that it has not hit since it last left it, nearest first, as long as it
## lives (its pierce); returns true when it hit any. One scan finds them all: the shot's
## remembered targets are marked first (`_mark_memory`), so the cost is the targets touched plus
## the ones remembered. The search widens with the largest target radius, so a big target whose
## centre is cells away is still found. The cells searched are those the path touches, widened
## by both radii.
func _hit_test(slot: int) -> bool:
	var from: Vector2 = _prev[slot]
	var to: Vector2 = _pos[slot]
	# A shot the budget passed over sweeps its whole path since its last test (`_defer`).
	if (_flags[slot] & F_DEFERRED) != 0:
		_flags[slot] &= ~F_DEFERRED
		from = _untested[slot]
	# Where the step starts: a payload still on the body that fired it there is not clear of it.
	var start: Vector2 = from
	if _any_solid and _solids.has(slot):
		# A solid shot hits along its row.
		var half: Vector2 = _solid_half(slot, _solids[slot])
		from = to - half
		to += half
	var radius: float = _radius[slot]
	var lowest: Vector2 = from.min(to)
	var highest: Vector2 = from.max(to)
	var pad: Vector2 = Vector2.ONE * (radius + _max_target_radius)
	var low: Vector2 = lowest - pad
	var high: Vector2 = highest + pad
	var x0: int = clampi(floori((low.x - _grid_x) / GRID_CELL), 0, _grid_w - 1)
	var x1: int = clampi(floori((high.x - _grid_x) / GRID_CELL), 0, _grid_w - 1)
	var y0: int = clampi(floori((low.y - _grid_y) / GRID_CELL), 0, _grid_h - 1)
	var y1: int = clampi(floori((high.y - _grid_y) / GRID_CELL), 0, _grid_h - 1)
	# What a target must touch to be hit: the path's box widened
	# by the shot's radius (and a little, for rounding).
	var margin: Vector2 = Vector2.ONE * (radius + 0.05)
	var near_low: Vector2 = lowest - margin
	var near_high: Vector2 = highest + margin
	# The rest is read only once a cell's box lets the path in: most tests in a crowd end at the
	# boxes (Horde swarm S5). A test that looks at no target leaves the shot's memory unmarked, and
	# `_forget_left` then forgets every entry, as it would after marking them and seeing none.
	var looking: bool = false
	var path: Vector2 = Vector2.ZERO
	var path_sq: float = 0.0
	var middle: Vector2 = Vector2.ZERO
	var half: float = 0.0
	var layers: int = 0
	# Whether it still spares the body it started on (`exclude`): on it, or coming at it from close by.
	var spared: bool = _skip_on[slot] > 0.0 and _still_spares(slot, start, _pos[slot] - start)
	var stamp: int = 0
	var found: int = 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell: int = y * _grid_w + x
			if _cell_filled[cell] != _grid_fill:
				_cell_info(cell)
			var in_cell: int = _cell_count[cell]
			if in_cell == 0:
				continue
			# Every target in the cell is charged as examined, and a cell whose targets' box the
			# path's box does not touch is passed at once (performance, 2026-10-28: a hit test in
			# the stress crowd 2.6 -> 2.2 us).
			_work_left -= in_cell
			var box: Vector4 = _cell_box[cell]
			if box.x > near_high.x or box.y > near_high.y or box.z < near_low.x or box.w < near_low.y:
				continue
			if not looking:
				looking = true
				path = to - from
				path_sq = path.length_squared()
				# A target farther from the path's middle than half the path plus both radii misses:
				# that one distance turns most of the targets in the cells away before anything else
				# is read of them (a target the shot is inside of is never that far either).
				middle = (from + to) * 0.5
				half = sqrt(path_sq) * 0.5 + 0.01
				layers = _layers[slot]
				stamp = _mark_memory(slot)
			var t: int = _cell_head[cell]
			while t >= 0:
				var centre: Vector2 = _target_pos[t]
				var reach: float = radius + _target_radius[t]
				var far: float = half + reach
				if middle.distance_squared_to(centre) > far * far:
					t = _target_next[t]
					continue
				if (_target_layer[t] & layers) == 0:
					t = _target_next[t]
					continue
				var along: float = 0.0
				if path_sq > 0.0:
					along = clampf((centre - from).dot(path) / path_sq, 0.0, 1.0)
				var closest: Vector2 = from + path * along
				if closest.distance_squared_to(centre) > reach * reach:
					t = _target_next[t]
					continue
				# A target already hit: the path still touches it, so it stays remembered.
				if _target_mark[t] == stamp:
					_mem_seen[_target_entry[t]] = _mem_step
					t = _target_next[t]
					continue
				if spared and _skip_id[slot] == _target_key[t]:
					t = _target_next[t]
					continue
				found = _keep_candidate(found, t, along, closest)
				t = _target_next[t]
	# Clear of the body it started on, and not coming back across it: it hits it from now.
	if _skip_on[slot] > 0.0 and not spared:
		_skip_on[slot] = 0.0
	return _hit_candidates(slot, found)


## Whether the shot in `slot`, its step starting at `start` and going `way`, still spares the body
## it started on (`exclude`): its step starts on that body's hit circle, or, cast from that body
## (`_skip_near` off it), it is coming at it, its line going into it, and ends no farther off than it
## was cast. A shot cast from a staff tip off its caster's body does not hit that body as it crosses
## it on its way out (owner, 2026-11-07: a nova's shot aimed back across the wizard hit them); one
## that has passed it, or turns back (return, bounce), does.
func _still_spares(slot: int, start: Vector2, way: Vector2) -> bool:
	var t: int = _target_key.find(_skip_id[slot]) if _skip_id[slot] != 0 else -1
	if t < 0 or (_target_layer[t] & _layers[slot]) == 0:
		return false
	var reach: float = _radius[slot] + _target_radius[t]
	var to_centre: Vector2 = _target_pos[t] - start
	var apart_sq: float = to_centre.length_squared()
	if apart_sq <= reach * reach:
		return true
	var near: float = _skip_near[slot]
	if near <= 0.0:
		return false
	var ahead: float = to_centre.dot(way)
	var within: float = reach + near
	if ahead <= 0.0 or (to_centre - way).length_squared() > within * within:
		return false
	# The square of how far the body's centre stands off the shot's line.
	return apart_sq - ahead * ahead / way.length_squared() <= reach * reach


## Hit the `found` targets `_hit_test` kept for the shot in `slot` (`_cand_*`), nearest first;
## returns true when it hit any. A hit handler may end the shot or take its slot; a stuck one stops.
func _hit_candidates(slot: int, found: int) -> bool:
	var seq: int = _seq[slot]
	var hit: bool = false
	for n in found:
		if _alive[slot] == 0 or _seq[slot] != seq or (_flags[slot] & F_STUCK) != 0:
			break
		var t: int = _cand_target[n]
		if _target_layer[t] == 0 or not is_instance_valid(_targets[t]):
			continue
		_work_left -= HIT_WORK
		hit = true
		_register_hit(slot, t, _cand_point[n])
	return hit


## Take the count of `cell` and the box round its targets' hit circles from its chain (see
## `_cell_count`). The positions only change when the grid is filled, so this is what a filling
## would have written.
func _cell_info(cell: int) -> void:
	_cell_filled[cell] = _grid_fill
	var count: int = 0
	var t: int = _cell_head[cell]
	if t < 0:
		_cell_count[cell] = 0
		return
	var low: Vector2 = Vector2.INF
	var high: Vector2 = -Vector2.INF
	while t >= 0:
		var centre: Vector2 = _target_pos[t]
		var r: float = _target_radius[t]
		low = low.min(centre - Vector2(r, r))
		high = high.max(centre + Vector2(r, r))
		count += 1
		t = _target_next[t]
	_cell_count[cell] = count
	_cell_box[cell] = Vector4(low.x, low.y, high.x, high.y)


## Put target `t` (`along` its path, 0 to 1, nearest point `closest`) into the sorted candidates
## of the hit test (`_cand_*`, which grow when full); returns the new count.
func _keep_candidate(found: int, t: int, along: float, closest: Vector2) -> int:
	if found == _cand_target.size():
		var size: int = maxi(16, found * 2)
		_cand_target.resize(size)
		_cand_along.resize(size)
		_cand_point.resize(size)
	var at: int = found
	while at > 0 and _cand_along[at - 1] > along:
		_cand_target[at] = _cand_target[at - 1]
		_cand_along[at] = _cand_along[at - 1]
		_cand_point[at] = _cand_point[at - 1]
		at -= 1
	_cand_target[at] = t
	_cand_along[at] = along
	_cand_point[at] = closest
	return found + 1


## Mark the targets the shot in `slot` remembers (`_target_mark` set to the returned stamp,
## `_target_entry` to their memory entry). An entry keeps the target's index as a hint and finds
## it again by its id when the targets were packed since; one whose target is gone is dropped.
func _mark_memory(slot: int) -> int:
	_mark_stamp += 1
	if _target_mark.size() < _targets.size():
		_target_mark.resize(_targets.size())
		_target_entry.resize(_targets.size())
	var before: int = -1
	var at: int = _mem_head[slot]
	while at >= 0:
		var next: int = _mem_next[at]
		var t: int = _mem_target[at]
		if t < 0 or t >= _targets.size() or _target_key[t] != _mem_id[at]:
			t = _target_key.find(_mem_id[at])
			_mem_target[at] = t
		if t < 0:
			if before < 0:
				_mem_head[slot] = next
			else:
				_mem_next[before] = next
			_mem_next[at] = _mem_free
			_mem_free = at
		else:
			_target_mark[t] = _mark_stamp
			_target_entry[t] = at
			before = at
		at = next
	return _mark_stamp


## The shot in `slot` forgets every target it touches, so it hits each again at its next test,
## though they never left it (a pool's tick: what stands in it is struck again). False for an empty
## slot. Not to be called while the manager steps.
func forget_hits(slot: int) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0:
		return false
	_forget_all(slot)
	return true


## The shot in `slot` hit target `t` this step: remember it until it leaves it.
func _remember(slot: int, t: int) -> void:
	if _mem_free < 0:
		_grow_memory(_mem_id.size() * 2)
	var at: int = _mem_free
	_mem_free = _mem_next[at]
	_mem_id[at] = _target_key[t]
	_mem_target[at] = t
	_mem_seen[at] = _mem_step
	_mem_next[at] = _mem_head[slot]
	_mem_head[slot] = at


## Forget the targets the path of the shot in `slot` did not touch this step: it has left them.
func _forget_left(slot: int) -> void:
	var before: int = -1
	var at: int = _mem_head[slot]
	while at >= 0:
		var next: int = _mem_next[at]
		if _mem_seen[at] != _mem_step:
			if before < 0:
				_mem_head[slot] = next
			else:
				_mem_next[before] = next
			_mem_next[at] = _mem_free
			_mem_free = at
		else:
			before = at
		at = next


## Forget every target of the shot in `slot` (it is new, it turned back or it bounced).
func _forget_all(slot: int) -> void:
	var at: int = _mem_head[slot]
	while at >= 0:
		var next: int = _mem_next[at]
		_mem_next[at] = _mem_free
		_mem_free = at
		at = next
	_mem_head[slot] = -1


## Room for `size` remembered hits in all (the new entries go on the free list).
func _grow_memory(size: int) -> void:
	var old: int = _mem_id.size()
	_mem_id.resize(size)
	_mem_target.resize(size)
	_mem_seen.resize(size)
	_mem_next.resize(size)
	for at in range(size - 1, old - 1, -1):
		_mem_next[at] = _mem_free
		_mem_free = at


## Tell listeners the shot in `slot` ended on a wall where it stands, flying along `velocity`.
func _emit_wall_impact(slot: int, velocity: Vector2) -> void:
	if events != null and not velocity.is_zero_approx():
		impact_form = _form_of(slot)
		impact_body = _kind_of(slot)
		impact_core = _core[slot]
		impact_look = _look[slot]
		impact_tag = _tag[slot]
		events.projectile_impact.emit(_actor[slot], null, _pos[slot], velocity.normalized())
		impact_form = &""
		impact_body = 0
		impact_core = Color.WHITE
		impact_look = 0
		impact_tag = 0


## The form of the shot in `slot`: its card's (`set_form`), else by its body.
func _form_of(slot: int) -> StringName:
	if _form_id[slot] != &"":
		return _form_id[slot]
	var kind: int = _kind_of(slot)
	if kind == KIND_RUNE:
		return &"rune"
	if kind == KIND_ORBIT:
		return &"orbit"
	return &"bolt"


func _register_hit(slot: int, target: int, at: Vector2) -> void:
	var node: Variant = _targets[target]
	var caster: int = _actor[slot]
	var tag: int = _tag[slot]
	var heading: Vector2 = _vel[slot].normalized()
	if heading == Vector2.ZERO:
		# A still shot has no heading: point from the shot to the target instead.
		heading = at.direction_to(_target_pos[target])
		if heading == Vector2.ZERO:
			heading = Vector2.RIGHT
	var spent: bool = false
	if _stick[slot] > 0.0 and is_instance_valid(node):
		# Stick to the target: it carries the shot until the stick time is up.
		_flags[slot] |= F_STUCK
		_stuck_to[slot] = node
		# Where its line of flight comes closest to the target's centre (a head-on shot: the
		# centre), not `at`, the point of this step's path nearest it: that one lies anywhere from
		# the centre to the rim by when in its step the shot met the target, so what a stuck shot
		# fires from inside (a nova) hit all or half of its ring by chance. Only a straight shot
		# has such a line: an orbit (on its circle) and a still shot stick where they are.
		var centre: Vector2 = (node as Node2D).global_position
		var stick_at: Vector2 = at
		if _motion[slot] == MOTION_STRAIGHT and not _vel[slot].is_zero_approx():
			stick_at = at + heading * heading.dot(centre - at)
		_stuck_off[slot] = stick_at - centre
		_life[slot] = _stick[slot]
		_stick[slot] = 0.0
		_join(slot, B_STUCK)
		# `_vel` stays: `_pass_stuck` never moves a stuck shot by it, and a payload it fires (on hit
		# or on a timer) still goes the way the shot was flying.
	elif _pierce[slot] > 0:
		_pierce[slot] -= 1
		_remember(slot, target)
	else:
		spent = true
		_end_tail(slot, at)
		_kill(slot, false)
	if events != null and is_instance_valid(node):
		impact_form = _form_of(slot)
		impact_body = _kind_of(slot)
		impact_core = _core[slot]
		impact_look = _look[slot]
		impact_tag = tag
		events.projectile_impact.emit(caster, node, at, heading)
		impact_form = &""
		impact_body = 0
		impact_core = Color.WHITE
		impact_look = 0
		impact_tag = 0
		_event_slot = slot
		events.projectile_hit.emit(caster, node, at, tag, slot)
		_event_slot = -1
	if spent and tag != 0:
		shot_ended.emit(tag)
