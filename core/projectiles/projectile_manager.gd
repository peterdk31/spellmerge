extends Node2D
## The projectile manager: one autoload ("Projectiles") that simulates every
## spell projectile in bulk and draws them all in one batch. Projectiles are
## rows in packed arrays, never nodes, so thousands cost little (PLAN budgets:
## 500 on the web, 3,000 on desktop).
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
## The hit work of one step is bounded (WORK_PER_STEP), so a crowd of packed
## targets with thousands of piercing shots inside it cannot stall a frame.
## When the budget runs out, the projectiles not yet tested still move, but
## are not hit-tested this step; the next step starts with them, so nobody is
## starved. A deferred shot that is still inside a target hits it a step late;
## a very fast one may skip a target. Only crowds at the caps ever get there.
## The budget is per `step` call, not per frame: if the engine runs several
## physics steps in one frame to catch up, each has its own budget.
##
## Drawing: a shot is built by the shot shaders on a pixel grid (staffs B6a; the glow look,
## 2026-10-27): a small white-hot core in the ramp of its first infusion's colour (`set_core`;
## its caster's ramp for a plain shot), a long tail that cools and frays, a soft glow round both,
## and particles given off in the styles of all its cards (`set_look`), mixed at random. The tail
## and the particles are left in the world where the shot was (its trail, see TRAIL_SAMPLES; the
## owner, 2026-10-28), so they bend with any path and cool where it ended; a caster's dash is
## drawn the same way (`follow_caster`). It is drawn about its hit size (`look_size`). Shots in
## the enemy ramp (`Actors.RAMP_ENEMY`, and a shot of no actor) are drawn by the same shaders
## (`ramp_look`), one layer above, so a dangerous shot never hides under a friendly one (staffs
## F9b: the old enemy shot's own texture is gone). One shader per kind of thing drawn, each in a
## batch of its own (the owner, 2026-10-29; core/README.md, "The shot shaders"): a flying shot
## and its trail by `shot_trail.gdshader`, as small quads its vertex stage places (`trail_mesh`:
## a quad per tail pixel, particle and light, so the fragment stage stays small), a rune by
## `shot_rune.gdshader`.
##
## Casters (actors G3a, docs/milestones/M2-actors.md): a shot's caster is an actor id (0 to
## ACTORS - 1, `core/actors`) or NO_PLAYER (`Actors.NONE`, a shot of no actor). Nothing here
## asks whether a caster is a wizard or an enemy; the actor table answers four questions, read
## once when a shot is spawned and kept with it (a shot keeps the caster it was cast by):
## - **team** (`team_of`), only for aim: homing and `nearest_target`'s team skip pick other
##   teams, and a shield stops other teams' shots. Never for whether a hit lands: every shot and
##   beam hits both actor layers (ACTOR_LAYERS, actors G3c, owner 2026-10-28: "Everything should
##   be able to damage everything."), and only the caster's own body (and decoys) is skipped,
##   unless the shot is self-hitting.
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
## rune) never moves: its velocity is ignored and it waits for a target to enter its
## circle. It still ends by life or by a hit, as any shot does.
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
## second, keeping its speed. The caller says how far (`CompiledSpell.homing_range`); there
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
##   self hit               may hit its caster once it has left the caster's hitbox
## Self-hit is off until `gameplay/combat` is ready for it (B3). Teammates are always hit (G3c).
##
## Rays: `ray(...)` is an instant beam, `ray_curve(...)` a bent one, `ray_points(...)` one along
## any path of points (a live beam, which a homing one bends from target to target). They hold
## no row; see their comments. The spell runtime keeps a live beam on by casting one every step.
##
## Casters: every shot has a caster, its actor's anchor unless `set_caster_shot` (a payload's
## shot, cast by the shot whose trigger fired it) or `set_caster_point` says otherwise. An orbit
## circles its caster and a returning shot flies back to it; a caster shot that ends leaves the
## point where it was last. `move_shot` moves a shot by a card (a payload's dash, hook, recoil).
##
## Ends: `shot_ended(tag)`, a signal of the manager itself (not on the event bus), is sent
## once for every shot with a non-zero tag when it ends for any reason: a hit that spends it,
## its life, a wall, the bounds, the cap dropping it, a cleared anchor, `clear()`. It is sent
## after that shot's `projectile_hit` or `projectile_expired` handlers have run, so a handler
## can spawn children first. `remove_by_tag` is the exception: it is silent, because its
## caller is the one that revoked the tag. While a `projectile_hit` or `projectile_expired`
## event of a shot is being sent, `event_slot` is that shot's slot (-1 otherwise, and for a
## ray), so a listener can read per-shot state with `get_seq_of` and `get_velocity_of`; a
## slot that just ended is not reused until the next spawn. `exclude(slot, node, seconds)`
## keeps one shot from hitting one target for a while.
##
## The step (shots stepped by behaviour, 2026-10-28): every shot moves on in one short common
## pass, then each behaviour's pass steps only the shots that have it, then one hit pass tests
## every shot in turn and sends the events, in the order they were always sent; see `step` and
## "Shot behaviours, stepped in passes" below, and core/README.md for how to add a behaviour.
## A hit handler sees every shot already moved for this step, also those whose turn in the hit
## pass has not come yet (the caster of an orbit or returning shot is the exception: it is read
## as it was before its turn). So a handler's change to another shot (a hook pulling its carrier,
## a blink) takes effect from that shot's next step whatever the slot order, where it used to
## take effect in this step for a shot in a later slot.
##
## Nothing here allocates per frame: the arrays are sized when the cap is set,
## and the grid is reused. Coordinates are world coordinates (the manager sits
## at the origin). A handler of `projectile_hit` may spawn more projectiles;
## those start moving on the next step. Tests call `step()` directly.

const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

## A shot with a non-zero tag ended; see "Ends" above.
signal shot_ended(tag: int)
## Something met a wall and was not over (for `on wall`, which also fires on a shot's last wall
## through `projectile_expired` and `expired_on_wall`): a shot bounced off one, or a ray (sent
## with `hit`) turned at one or ended on one. `position` is just out of the wall and `heading`
## the way it goes on (at a ray's end, the way it came). While a shot's is sent, `event_slot`
## is that shot; a ray's has -1.
signal wall_met(caster: int, position: Vector2, heading: Vector2, tag: int)

## Every caster number there is: the actor ids (see "Casters").
const ACTORS: int = ActorsScript.ACTORS
## The drop buckets (`_owned`): one per seat and the shared one (`Actors.budget_of`).
const BUDGETS: int = ActorsScript.SHARED + 1
## Motion modes of a shot (see the class doc).
const MOTION_STRAIGHT: int = 0
const MOTION_STILL: int = 1
## Only `spawn_orbit` makes this one.
const MOTION_ORBIT: int = 2
## `_caster_slot` values that are no slot: the caster's anchor, or a fixed point.
const CASTER_WIZARD: int = -1
const CASTER_POINT: int = -2
## Per-shot flags (`_flags`), set by the `set_*` calls below.
const F_SELF: int = 1
const F_SELF_LIVE: int = 2
## Bit 4 was F_ALLY (a mend shot that hits teammates), gone in actors G3c: every shot does.
const F_GHOST: int = 8
const F_STUCK: int = 16
const F_RETURN: int = 32
const F_TURNED: int = 64
const F_WAVE: int = 128

## Seconds one sine wave of a spiral shot takes.
const SPIRAL_PERIOD: float = 0.5

## Default global caps on live projectiles for each platform. The web cap was 1,000 (the PLAN
## budget) until the first web stress run: a physics step of 14 to 20 ms made the engine
## catch up with up to 8 steps per frame (docs/DECISIONS.md, 2026-10-23), so it is 500.
const DEFAULT_CAP_WEB: int = 500
const DEFAULT_CAP_DESKTOP: int = 3000
## How many recently hit targets a piercing projectile remembers; also the most
## hits one projectile can register in a single step.
## Remembered hits (see `_remember`) made room for at first; more are made when needed.
const HIT_MEMORY_START: int = 1024
## Moves under way (see `move_shot`) made room for at first; more are made when needed.
const MOVES_START: int = 64
## The most hit-test work one step does, in units: each target examined costs 1,
## each hit costs HIT_WORK. Once it is spent, the remaining projectiles are not
## tested this step (see the class doc). Normal play uses a tiny part of it.
const WORK_PER_STEP: int = 6000

## The most wall cells one shot walks in one step (see `_wall_hit`).
const MAX_WALL_VISITS: int = 64
## The work one hit counts for: the event, its handlers and the bookkeeping.
const HIT_WORK: int = 40
## A homing shot looks for a target one step in this many (slots take turns).
const HOMING_PERIOD: int = 4
## The straight pieces a bent beam (`ray_curve`) is walked as.
const RAY_SEGMENTS: int = 8
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
## The smallest a batch's MultiMesh buffer gets, in shots. A batch holds as many shots
## as the busiest recent frame needed, rounded up to a power of two (never above the
## cap), so a quiet batch uploads a few KB a frame rather than cap x 16 floats.
const MIN_BATCH: int = 64
## The draw batches by ramp: bolts, runes (still) and orbit shots in the four hat ramps, and the
## shots in the enemy ramp (`Actors.RAMP_ENEMY`, and a shot of no actor), flying ones and runes
## apart (each batch has one shader), drawn above the others.
const BATCH_BOLT: int = 0
const BATCH_RUNE: int = 1
const BATCH_ORBIT: int = 2
const BATCH_ENEMY: int = 3
const BATCH_ENEMY_RUNE: int = 4
const BATCHES: int = 5
## The bodies a shot is drawn as (the shot shaders build them on a pixel grid; staffs B6a): a
## bolt with its tail (`shot_trail.gdshader`), a rune (a diamond that pulses, `shot_rune.gdshader`),
## an orbit shot drawn whole with its tail bent round its circle (`shot_orbit.gdshader`, Entities'
## familiars; the manager's orbit shots are trails). Kind 0 is no body.
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
## `set_look`). The body stays plain; each kind is a style of particle the shot gives off from
## its tail (`shot_trail.gdshader`), and a shot shows every kind its cards bring, mixed at
## random: the look is a set, one bit per kind. WEAVE and STREAKS also change the body (a
## weave, a longer core). A new kind of effect is a new number here (up to LOOK_MAX_KINDS) and
## a branch in the shader's `particle`; a new card with an old kind needs neither.
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
## Kind 22 is the poof flag (`Feel.POOF`), 23 the enemy ramp and 24 the exact colour: not kinds.
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
## The spark pool (staffs B6b): the sparks, embers and the rest that all the shots give off come
## from one pool with a global count, `particle_cap` (a visual budget, under the effect quality
## setting once there is one; never a build rule). A shot with `n` emitting kinds asks for
## `particles_of(look)` of them (4 + 2n, at most 12) and a bolt's trail for TRAIL_COST more.
## Under the cap everything is drawn. Over it the trails thin first (shorter, then gone), and only
## when the particles alone are over the cap do the particles thin too, every shot alike.
const PARTICLE_CAP: int = 1024
## What a bolt's trail counts in the pool.
const TRAIL_COST: int = 4
## Trails (the owner, 2026-10-28: tails that stay where the shot was, as in the mockup): every
## flying shot keeps the last TRAIL_SAMPLES points of its path, one every TRAIL_EVERY seconds and
## one at every bounce, jump and end, each with how far the shot had gone and when. The shader
## leaves the tail pixels and the card particles along that path in the world, so they bend with
## it and stay behind; the rows go to the shader in one texture (`trail_data`, a row of
## TRAIL_SAMPLES texels x, y, odometer, time per trail). A trail outlives its shot by TRAIL_KEEP
## seconds (the longest any of it lives), so the tail cools where the shot ended. There are
## TRAIL_ROWS_PER_SLOT x the cap rows; a shot that finds none is drawn without a tail. A step
## longer than TRAIL_JUMP pixels (a teleport) starts the path afresh.
const TRAIL_SAMPLES: int = 32
const TRAIL_EVERY: float = 1.0 / 30.0
const TRAIL_KEEP: float = 1.0
const TRAIL_ROWS_PER_SLOT: int = 2
const TRAIL_JUMP: float = 96.0
## Floats per trail row in `trail_data`.
const TRAIL_STRIDE: int = TRAIL_SAMPLES * 4
## The smallest the trail texture gets, in rows (it grows by powers of two with the rows used).
const MIN_TRAIL_ROWS: int = 64
## A trail's flags in its instance (the shader's TF_*): its shot is alive (the core is drawn and
## the path runs on to it), an orbit shot (a shorter tail), a wizard's dash (`follow_caster`).
const TRAIL_HEAD: int = 1
const TRAIL_ORBIT: int = 2
const TRAIL_DASH: int = 4
## The quad kinds of a trail's mesh (`trail_mesh`; the shader's Q_*): the core's light, a piece's
## light (a dash: a speed streak's), a particle's light, a particle, a tail pixel (a dash: a speed
## streak), a step of lightning's jagged line, the core.
const TRAIL_Q_HEAD_LIGHT: int = 0
const TRAIL_Q_PIECE_LIGHT: int = 1
const TRAIL_Q_SPARK_LIGHT: int = 2
const TRAIL_Q_SPARK: int = 3
const TRAIL_Q_TAIL: int = 4
const TRAIL_Q_JAG: int = 5
const TRAIL_Q_CORE: int = 6
## Slots a trail has for its particles (one per 60th of a second it keeps), its tail pixels (one
## per pixel of travel; a tail longer than this, a very fast shot's, loses its oldest end) and the
## steps of lightning's line (a tenth of a second at 4 px a step).
const TRAIL_SPARKS: int = int(TRAIL_KEEP * 60.0) + 1
const TRAIL_TAIL_PIXELS: int = 128
const TRAIL_JAGS: int = 16
## The quads of a trail's mesh in draw order: (kind, slots, 1 when drawn oldest first). The
## lights are added, so only the head's goes first (void's dark heart dims what is under it).
const TRAIL_QUADS: Array[Vector3i] = [
	Vector3i(TRAIL_Q_HEAD_LIGHT, 1, 0),
	Vector3i(TRAIL_Q_PIECE_LIGHT, TRAIL_SAMPLES, 0),
	Vector3i(TRAIL_Q_SPARK_LIGHT, TRAIL_SPARKS, 0),
	Vector3i(TRAIL_Q_SPARK, TRAIL_SPARKS, 1),
	Vector3i(TRAIL_Q_TAIL, TRAIL_TAIL_PIXELS, 1),
	Vector3i(TRAIL_Q_JAG, TRAIL_JAGS, 1),
	Vector3i(TRAIL_Q_CORE, 1, 0),
]
## What holds a trail row, when it is not a shot's slot.
const ROW_FREE: int = -1
const ROW_FADING: int = -2
const ROW_CASTER: int = -3
## An orbit shot spirals out from its caster to its circle over this many seconds.
const ORBIT_GROW: float = 0.25
## Particles a shot keeps in the air at most (the same number as the shader's).
const PARTICLES_PER_SHOT_MAX: int = 12
## The look bits of the kinds that give off particles: all of them but the weave.
const EMITTING_MASK: int = ((1 << (LOOK_COUNT - 1)) - 1) & ~(1 << (LOOK_WEAVE - 1))
## Build the shots from their looks (see "Drawing" above): flying shots and their trails, runes.
const TRAIL_SHADER: Shader = preload("res://core/projectiles/shot_trail.gdshader")
const RUNE_SHADER: Shader = preload("res://core/projectiles/shot_rune.gdshader")
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

## The art of the hat-ramp batches. Since staffs B6a the shader builds every shot (runes
## and orbit shots too) and never reads it; only the sprite path of Feel's lone flashes does.
var texture: Texture2D = null:
	set(value):
		texture = value
		_apply_textures()
var events: EventsScript = null
## How many projectiles were dropped because the cap was full, since start.
var dropped: int = 0
## The slot of the shot whose hit or expiry event is being sent, else -1. See "Ends".
var event_slot: int = -1
## The form of the shot whose `projectile_impact` is being sent: `&"bolt"`, `&"rune"`, `&"orbit"`
## or `&"beam"`, whoever cast it (any time outside an impact: `&""`). For looks only.
var impact_form: StringName = &""
## The core colour and the look (`set_core`, `set_look`) of the shot whose `projectile_impact`
## is being sent, so its flare can take the shot's colours and card effects (white and 0 for a
## beam and outside an impact). For looks only.
var impact_core: Color = Color.WHITE
var impact_look: int = 0
## The way the shot was flying, while a `projectile_expired` is sent (with `impact_form`,
## `impact_core` and `impact_look`, so Feel can show where its life ran out).
var impact_heading: Vector2 = Vector2.ZERO
## How many projectiles ended on a wall, since start.
var wall_hits: int = 0
## Projectiles written into the batch by the last update_draw().
var drawn: int = 0
## Trails drawn in the last `update_draw` that no live shot holds (cooling, or a caster's).
var drawn_trails: int = 0
## The global count of the spark pool (see PARTICLE_CAP). Tests and a future effect quality
## setting change it; it never changes what a shot does.
var particle_cap: int = PARTICLE_CAP
## What the drawn shots asked of the pool in the last update_draw(): particles, and bolt trails
## (in pool units, TRAIL_COST each).
var particle_demand: int = 0
var trail_demand: int = 0
## The share of the particles and of the trails the pool drew in the last update_draw() (1.0 is
## all of them; trails go down first).
var particle_share: float = 1.0
var trail_share: float = 1.0
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
## Orbit shots: radius from the anchor, current angle and angular speed (rad/s).
var _orbit_radius: PackedFloat32Array = PackedFloat32Array()
var _orbit_angle: PackedFloat32Array = PackedFloat32Array()
var _orbit_speed: PackedFloat32Array = PackedFloat32Array()
## Where an orbit shot's caster was at its last step (INF before its first), for `_drawn_at`.
var _orbit_centre: PackedVector2Array = PackedVector2Array()
## Homing: turn rate in rad/s (0 for none) and the point last found (INF for none).
var _turn: PackedFloat32Array = PackedFloat32Array()
var _home_at: PackedVector2Array = PackedVector2Array()
var _home_range: PackedFloat32Array = PackedFloat32Array()
## The instance id of the target each homing shot keeps, 0 for none.
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
var _span: PackedFloat32Array = PackedFloat32Array()
var _radius0: PackedFloat32Array = PackedFloat32Array()
var _growth: PackedFloat32Array = PackedFloat32Array()
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
## anchor (CASTER_WIZARD), a fixed point in `_caster_at` (CASTER_POINT), or the shot in that slot
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
## The live shots a shield checks, made once a step the first time a shield needs it (see
## `_shield_block`).
var _scan_slots: PackedInt32Array = PackedInt32Array()
var _scan_count: int = 0
var _scan_step: int = -1
## True while a `projectile_expired` is sent for a shot that ended on a wall (the `on wall`
## trigger reads it); false for every other end.
var expired_on_wall: bool = false
## The targets each shot is touching and has hit, so it hits them once until it leaves them: a
## list per slot (`_mem_head`, -1 for none) through one growing pool (`_mem_id` the target's
## instance id, `_mem_seen` the step its path last touched it, `_mem_next` the link; `_mem_free`
## heads the free entries). `_mem_step` counts the steps.
var _mem_head: PackedInt32Array = PackedInt32Array()
var _mem_id: PackedInt64Array = PackedInt64Array()
## The target's index when it was hit: a hint, checked against its id (`_mark_memory`).
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
## max y), so a hit test passes a cell its path cannot touch without a look at each target.
var _cell_count: PackedInt32Array = PackedInt32Array()
var _cell_box: PackedVector4Array = PackedVector4Array()
var _target_next: PackedInt32Array = PackedInt32Array()
## The largest radius of any registered target; sets how far hits are searched.
var _max_target_radius: float = 0.0
## True when targets were added since the grid was filled (a query refreshes it).
var _grid_stale: bool = false

## The wall grid over the bounds: one byte per WALL_CELL cell, 1 for solid.
var _wall_w: int = 1
var _wall_h: int = 1
var _wall_cells: PackedByteArray = PackedByteArray()
var _has_walls: bool = false

## The colour of each shot's core (white for a plain shot), see `set_core`.
var _core: PackedColorArray = PackedColorArray()
## The packed look layers of each shot (0 none), see `set_look`.
var _look: PackedInt32Array = PackedInt32Array()
## The simulation time each shot was born at (`sim_time`), for the rune's trace.
var _born: PackedFloat32Array = PackedFloat32Array()
var _draw_node: MultiMeshInstance2D = null
## Shots each batch's MultiMesh and buffer have room for now (see `_batch_room`).
var _draw_room: int = 0
var _rune_room: int = 0
var _orbit_room: int = 0
## Live shots per batch this frame (BATCH_*), refilled by _count_batches; a member so no array is made per frame.
var _batch_counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])
var _draw_buffer: PackedFloat32Array = PackedFloat32Array()
## The batches of runes and orbit shots, beside the bolts' `_draw_node`.
var _rune_node: MultiMeshInstance2D = null
var _rune_buffer: PackedFloat32Array = PackedFloat32Array()
var _orbit_node: MultiMeshInstance2D = null
var _orbit_buffer: PackedFloat32Array = PackedFloat32Array()
## The shots in the enemy ramp, drawn one layer above the others: flying ones and their trails,
## and runes.
var _enemy_node: MultiMeshInstance2D = null
var _enemy_buffer: PackedFloat32Array = PackedFloat32Array()
var _enemy_room: int = 0
var _enemy_rune_node: MultiMeshInstance2D = null
var _enemy_rune_buffer: PackedFloat32Array = PackedFloat32Array()
var _enemy_rune_room: int = 0
## The mesh every trail instance is drawn as (`trail_mesh`), made once.
static var _trail_mesh: ArrayMesh = null
## Trails (see TRAIL_SAMPLES): each shot's row (-1 for none), and per row its samples (`trail_data`
## in the shader), the number of its newest sample, how many it keeps, how far it has gone, its
## last point, what holds it (a slot or ROW_*), and, once its shot is gone (or for a caster's
## trail), what it is drawn as and until when.
var _trail: PackedInt32Array = PackedInt32Array()
var _trail_data: PackedFloat32Array = PackedFloat32Array()
var _trail_newest: PackedInt32Array = PackedInt32Array()
var _trail_kept: PackedInt32Array = PackedInt32Array()
var _trail_odo: PackedFloat32Array = PackedFloat32Array()
var _trail_last: PackedVector2Array = PackedVector2Array()
var _trail_holder: PackedInt32Array = PackedInt32Array()
var _trail_caster: PackedInt32Array = PackedInt32Array()
## Each row's ramp (`Actors.ramp_of` of its caster when the row began; see `look_color`).
var _trail_ramp: PackedInt32Array = PackedInt32Array()
var _trail_look: PackedInt32Array = PackedInt32Array()
var _trail_core: PackedColorArray = PackedColorArray()
var _trail_zoom: PackedInt32Array = PackedInt32Array()
var _trail_flags: PackedInt32Array = PackedInt32Array()
## Each row's `look_color` of its ramp, zoom and look, worked out when the row is let loose (a
## cooling trail is drawn every frame and never changes them).
var _trail_color: PackedColorArray = PackedColorArray()
var _trail_until: PackedFloat32Array = PackedFloat32Array()
var _trail_free: PackedInt32Array = PackedInt32Array()
var _trail_free_count: int = 0
var _trail_high: int = 0
## The rows held by no live shot (fading, or a caster's), so drawing never walks every row.
var _loose: PackedInt32Array = PackedInt32Array()
var _loose_count: int = 0
## The last sample tick taken (sim_time / TRAIL_EVERY, floored), and whether a row changed since
## the texture was last sent.
var _trail_tick: int = -1
var _trail_dirty: bool = false
var _trail_image: Image = null
var _trail_texture: ImageTexture = null
var _trail_rows: int = 0
## The length of the last step, so the drawing knows when its heads are (see `update_draw`).
var _last_delta: float = 0.0
## True inside step(): the grid is in use, so a target removed then is only
## switched off (layer 0) and swept at the start of the next step.
var _stepping: bool = false
## Hit-test work left in this step, and the slot the next step starts from
## (the first one that went untested when the budget ran out).
var _work_left: int = 0
var _resume: int = 0
## Steps taken so far (staggers the homing searches).
var _step_index: int = 0
## Per slot: the target a shot must not hit, and the seconds left of that.
var _skip_id: PackedInt64Array = PackedInt64Array()
var _skip_left: PackedFloat32Array = PackedFloat32Array()
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
## What the last `sweep` found (reused; grows when a sweep finds more): the bodies, where the
## wedge meets each, and the sweep's way there. Read right after the call: a hit handler's sweep changes them.
var sweep_nodes: Array = []
var sweep_points: PackedVector2Array = PackedVector2Array()
var sweep_heads: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	for pass_name in BEHAVIOUR_PASSES:
		_passes.append(Callable(self, pass_name))
	assert(_passes.size() == BEHAVIOURS, "one pass per behaviour, in the order of B_*")
	_member_count.resize(BEHAVIOURS)
	_path.resize(RAY_PATH_START)
	ray_path.resize(RAY_PATH_START)
	sweep_nodes.resize(SWEEP_START)
	sweep_points.resize(SWEEP_START)
	sweep_heads.resize(SWEEP_START)
	_anchors.resize(ACTORS)
	_anchors.fill(Vector2.INF)
	set_cap(DEFAULT_CAP_WEB if OS.has_feature("web") else DEFAULT_CAP_DESKTOP)
	set_bounds(_bounds)


func _ready() -> void:
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	_draw_node = _make_batch(DRAW_Z, TRAIL_SHADER, trail_mesh())
	_rune_node = _make_batch(DRAW_Z, RUNE_SHADER, null)
	_orbit_node = _make_batch(DRAW_Z, TRAIL_SHADER, trail_mesh())
	_enemy_node = _make_batch(DRAW_Z + 1, TRAIL_SHADER, trail_mesh())
	_enemy_rune_node = _make_batch(DRAW_Z + 1, RUNE_SHADER, null)
	_apply_textures()
	_fit_draw_bounds()


## One batched draw of up to `_cap` instances (TRANSFORM_2D plus a colour and custom data each)
## by `shader`, added as a child: each a quad, or each a `mesh` (the trails' mesh).
func _make_batch(z: int, shader: Shader, mesh: Mesh) -> MultiMeshInstance2D:
	var node := MultiMeshInstance2D.new()
	if mesh == null:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		mesh = quad
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
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


## The mesh a trail is drawn as (`shot_trail.gdshader`, PARTICLES ARE GEOMETRY there): small
## quads, each told in its UV which quad kind (TRAIL_Q_*) and slot it is, in TRAIL_QUADS' order
## (the lights first, then the pixels, oldest first and the core last). The shader places every
## quad from the trail's data, or folds it away; a vertex says which quad and corner it is in its
## UV: x the slot + 0.25 or 0.75, y the kind + 0.25 or 0.75. Made once, shared by every trail
## batch.
static func trail_mesh() -> ArrayMesh:
	if _trail_mesh != null:
		return _trail_mesh
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var corners: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for entry: Vector3i in TRAIL_QUADS:
		for n in entry.y:
			var slot: int = entry.y - 1 - n if entry.z == 1 else n
			var base: int = verts.size()
			for corner: Vector2 in corners:
				verts.append(corner)
				uvs.append(Vector2(float(slot) + 0.25 + 0.5 * corner.x, float(entry.x) + 0.25 + 0.5 * corner.y))
				colors.append(Color.WHITE)
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	_trail_mesh = ArrayMesh.new()
	_trail_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _trail_mesh


func _apply_textures() -> void:
	if _draw_node != null:
		_draw_node.texture = texture
		_rune_node.texture = texture
		_orbit_node.texture = texture


func _physics_process(delta: float) -> void:
	step(delta)


func _process(_delta: float) -> void:
	update_draw()


## Set the global cap and remove every projectile. Not for use mid-fight.
func set_cap(value: int) -> void:
	_cap = maxi(value, 1)
	_pos.resize(_cap)
	_prev.resize(_cap)
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
	_span.resize(_cap)
	_radius0.resize(_cap)
	_growth.resize(_cap)
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
	_scan_slots.resize(_cap)
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
	_skip_left.resize(_cap)
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
	_born.resize(_cap)
	_trail.resize(_cap)
	_trail.fill(-1)
	var rows: int = _cap * TRAIL_ROWS_PER_SLOT
	_trail_newest.resize(rows)
	_trail_kept.resize(rows)
	_trail_odo.resize(rows)
	_trail_last.resize(rows)
	_trail_holder.resize(rows)
	_trail_caster.resize(rows)
	_trail_ramp.resize(rows)
	_trail_color.resize(rows)
	_trail_look.resize(rows)
	_trail_core.resize(rows)
	_trail_zoom.resize(rows)
	_trail_flags.resize(rows)
	_trail_until.resize(rows)
	_trail_free.resize(rows)
	_loose.resize(rows)
	_trail_data.resize(0)
	_trail_rows = 0
	_draw_buffer.resize(0)
	_rune_buffer.resize(0)
	_orbit_buffer.resize(0)
	_enemy_buffer.resize(0)
	_enemy_rune_buffer.resize(0)
	_draw_room = 0
	_rune_room = 0
	_orbit_room = 0
	_enemy_room = 0
	_enemy_rune_room = 0
	_alive.resize(_cap)
	_free_slots.resize(_cap)
	clear()
	if _draw_node != null:
		_draw_node.multimesh.instance_count = 0
		_rune_node.multimesh.instance_count = 0
		_orbit_node.multimesh.instance_count = 0
		_enemy_node.multimesh.instance_count = 0
		_enemy_rune_node.multimesh.instance_count = 0


func get_cap() -> int:
	return _cap


## The area the projectiles live in. Also sizes the target grid.
func set_bounds(rect: Rect2) -> void:
	_bounds = rect
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
	_grid_stale = true
	_wall_w = maxi(ceili(rect.size.x / WALL_CELL), 1)
	_wall_h = maxi(ceili(rect.size.y / WALL_CELL), 1)
	_wall_cells.resize(_wall_w * _wall_h)
	clear_walls()


## Make these world rectangles solid, replacing any walls set before. Parts outside
## the bounds are ignored. Call it after `set_bounds()`, which removes the walls.
func set_walls(rects: Array[Rect2]) -> void:
	clear_walls()
	for rect in rects:
		_add_wall(rect)


## Remove every wall.
func clear_walls() -> void:
	_wall_cells.fill(0)
	_has_walls = false


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
			_wall_cells[y * _wall_w + x] = 1
			_has_walls = true


## The point where the segment from `from` to `to` first meets a wall, or `to` when
## it is clear. If `from` is inside a wall, that is `from`.
func clip_to_walls(from: Vector2, to: Vector2) -> Vector2:
	var t: float = _wall_hit(from, to)
	if t < 0.0:
		return to
	return from.lerp(to, t)


## True when a circle of `radius` at `center` is out of the bounds or touches a wall cell
## (checked at the centre and eight points on its rim, each in its 8-pixel cell).
func circle_blocked(center: Vector2, radius: float) -> bool:
	for n in 9:
		var point: Vector2 = center
		if n > 0:
			point += Vector2.RIGHT.rotated(float(n - 1) * TAU / 8.0) * radius
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
	_draw_node.multimesh.custom_aabb = aabb
	_rune_node.multimesh.custom_aabb = aabb
	_orbit_node.multimesh.custom_aabb = aabb
	_enemy_node.multimesh.custom_aabb = aabb
	_enemy_rune_node.multimesh.custom_aabb = aabb


## Remove every projectile (targets stay registered).
func clear() -> void:
	for slot in _high:
		if _alive[slot] != 0 and _tag[slot] != 0:
			shot_ended.emit(_tag[slot])
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
	_trail.fill(-1)
	_trail_holder.fill(ROW_FREE)
	var rows: int = _trail_free.size()
	for i in rows:
		_trail_free[i] = rows - 1 - i
	_trail_free_count = rows
	_trail_high = 0
	_loose_count = 0
	_trail_dirty = true
	# `drawn` stays: the next update_draw() must still empty the batch.


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
## `owner` is the actor whose body it is (or whose decoy), or Events.NO_PLAYER: shots of that
## actor never hit it (unless they self-hit), and its team is what aim reads (see
## `_team_of_target`). `offset` moves the hit circle from the
## node's origin (usually the feet) to the drawn body, so a shot that looks like it touches
## the sprite does hit.
func add_target(node: Node2D, radius: float, layer: int = LAYER_ENEMY, owner: int = EventsScript.NO_PLAYER, offset: Vector2 = Vector2.ZERO) -> void:
	if node == null or layer == 0:
		return
	var id: int = node.get_instance_id()
	var at: int = _target_id.find(id)
	if at >= 0:
		_target_radius[at] = radius
		_target_layer[at] = layer
		_target_owner[at] = owner
		_target_team[at] = _team_of_target(owner, layer)
		_target_offset[at] = offset
		_max_target_radius = maxf(_max_target_radius, radius)
		return
	_targets.append(node)
	_target_id.append(id)
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
	var offset: Vector2 = Vector2.from_angle(angle) * maxf(orbit_radius, 0.0)
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
	# It is drawn spiralling out from its caster (`_drawn_at`), so its trail starts there.
	_orbit_centre[slot] = around
	if _trail[slot] >= 0:
		_trail_kept[_trail[slot]] = 0
		_trail_sample(_trail[slot], around)
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
## (a hook's), until its slot is used again.
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
	return slot >= 0 and slot < _cap and _caster_slot[slot] == CASTER_WIZARD


func _caster_position(slot: int) -> Vector2:
	var caster: int = _caster_slot[slot]
	if caster == CASTER_WIZARD:
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
## hook or recoil card whose caster is this shot), or at once for `seconds` 0 or less (a
## teleport or swap, stopped short at the first wall). Moves add up, as the wizard's pushes do: a
## new move runs beside the ones under way, each on its own time (two opposite pushes cancel, a
## hook after a recoil gets both). A moving shot still hits what it passes and still ends on a
## wall. A homing move (`turn_rate` above 0) turns toward the nearest
## target within `within` pixels as it goes (`home_velocity`), the same distance in all.
## Returns false for an empty slot, an orbit shot (its caster holds it), or an offset or time
## that is not finite.
func move_shot(slot: int, offset: Vector2, seconds: float, turn_rate: float = 0.0, within: float = 0.0) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or _motion[slot] == MOTION_ORBIT:
		return false
	if not offset.is_finite() or not is_finite(seconds):
		return false
	if seconds <= 0.0:
		var to: Vector2 = clip_to_walls(_pos[slot], _pos[slot] + offset) if (_flags[slot] & F_GHOST) == 0 else _pos[slot] + offset
		_base[slot] += to - _pos[slot]
		_pos[slot] = to
		_prev[slot] = to
		if _trail[slot] >= 0:
			# A blink leaves no tail across the gap.
			_trail_kept[_trail[slot]] = 0
			_trail_sample(_trail[slot], to)
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


## Make the straight shot in `slot` home on targets no further than `within` pixels from
## it, turning at most `turn_rate` radians a second. Returns false for an empty slot, a shot
## that is not straight, a rate that is negative or not finite, or a `within` that is not
## above 0 and finite; true when the rate was applied, 0 included (0 stops homing).
func set_homing(slot: int, turn_rate: float, within: float) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or _motion[slot] != MOTION_STRAIGHT:
		return false
	if not is_finite(turn_rate) or turn_rate < 0.0 or not is_finite(within) or within <= 0.0:
		return false
	_turn[slot] = turn_rate
	_home_range[slot] = within
	_home_target[slot] = 0
	_home_at[slot] = Vector2.INF
	if turn_rate > 0.0:
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


## Give the shot in `slot` its look, packed by `pack_look` (0 for none): every effect
## `shot_trail.gdshader` draws along its path. Returns false for an empty slot or a look with a
## bit for a kind that does not exist.
func set_look(slot: int, look: int) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or look < 0 or look >= 1 << (LOOK_COUNT - 1):
		return false
	_look[slot] = look
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
# does nothing) for a slot that is not a live straight shot or a bad number. Orbit and still
# shots keep their own motion, so the travel behaviours do not apply to them.

func _is_flyer(slot: int) -> bool:
	return slot >= 0 and slot < _cap and _alive[slot] != 0 and _motion[slot] == MOTION_STRAIGHT


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


## The shot flies in a sine wave `width` pixels wide (SPIRAL_PERIOD seconds a wave); its centre
## line is the straight path.
func set_spiral(slot: int, width: float) -> bool:
	if not _is_flyer(slot) or not (width > 0.0) or not is_finite(width):
		return false
	_wave[slot] = width * 0.5
	_flags[slot] |= F_WAVE
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


## The shot stops in mid-air for `seconds` when half its life is gone, then goes on.
func set_linger(slot: int, seconds: float) -> bool:
	if not _is_flyer(slot) or not (seconds > 0.0) or not is_finite(seconds):
		return false
	_linger[slot] = seconds
	_join(slot, B_LINGER)
	return true


## The shot's radius grows by `factor` each second of flight, until it is as big as the room
## (`set_bounds`; nothing is bigger): a wider hit circle, the same damage. `get_growth_of` tells how much bigger it is.
func set_growth(slot: int, factor: float) -> bool:
	if not _is_flyer(slot) or not (factor > 1.0) or not is_finite(factor):
		return false
	_growth[slot] = factor
	_join(slot, B_GROWTH)
	return true


## How many times bigger the shot in `slot` is than when it started (1.0 for a plain shot).
func get_growth_of(slot: int) -> float:
	# The shot whose hit is being sent counts even when that hit spent it (it is gone already).
	if slot < 0 or slot >= _cap or (_alive[slot] == 0 and slot != event_slot) or _radius0[slot] <= 0.0:
		return 1.0
	return _radius[slot] / _radius0[slot]


## The shot sticks to the first target it hits for `seconds`, then ends there (an expiry).
## The hit is sent as usual, and a stuck shot hits nothing more.
func set_sticky(slot: int, seconds: float) -> bool:
	if not _is_flyer(slot) or not (seconds > 0.0) or not is_finite(seconds):
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


## The shot may hit its own caster, once it has left the caster's hitbox (the first step it
## no longer overlaps it). Off by default; `gameplay/combat` decides what such a hit does. A shot
## of no actor has no caster to hit.
func set_self_hit(slot: int) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or _actor[slot] < 0:
		return false
	_flags[slot] |= F_SELF
	_flags[slot] &= ~F_SELF_LIVE
	return true


## True once a self-hitting shot has left its caster, so that it can hit them.
func is_self_live(slot: int) -> bool:
	return slot >= 0 and slot < _cap and _alive[slot] != 0 and (_flags[slot] & F_SELF_LIVE) != 0


func _spawn_row(caster: int, origin: Vector2, velocity: Vector2, lifetime: float, radius: float, hit_layers: int, pierce: int, tag: int, motion: int) -> int:
	# An orbit shot is held by its caster and ignores walls.
	if motion != MOTION_ORBIT and _has_walls and _wall_hit(origin, origin) >= 0.0:
		# Born inside a wall it would end in the next step: count it as ended, but
		# take no pool slot (at the cap that would evict another shot).
		# No shot existed, so no impact is shown (the staff tip is inside the wall).
		wall_hits += 1
		return -1
	if _free_count == 0:
		_drop_one()
	_free_count -= 1
	var slot: int = _free_slots[_free_count]
	_pos[slot] = origin
	_prev[slot] = origin
	_vel[slot] = velocity if motion == MOTION_STRAIGHT else Vector2.ZERO
	_motion[slot] = motion
	_turn[slot] = 0.0
	_home_at[slot] = Vector2.INF
	_home_range[slot] = 0.0
	_home_target[slot] = 0
	_life[slot] = lifetime
	_radius[slot] = maxf(radius, 0.0)
	_actor[slot] = caster
	# What the actor table says of the caster now; the shot keeps it for its life. A caster that
	# is no open actor has no team, the enemy ramp and the shared budget.
	var table: ActorsScript = actors if actors != null else _auto_actors
	if table == null or not is_instance_valid(table):
		table = actor_table()
	if table != null and table.is_open(caster):
		_team[slot] = table.team_of(caster)
		_ramp[slot] = table.ramp_of(caster)
		_budget[slot] = table.budget_of(caster)
	else:
		_team[slot] = ActorsScript.NONE
		_ramp[slot] = ActorsScript.NONE
		_budget[slot] = ActorsScript.SHARED
	_layers[slot] = hit_layers | ACTOR_LAYERS
	_pierce[slot] = maxi(pierce, 0)
	_tag[slot] = tag
	_core[slot] = Color.WHITE
	_look[slot] = 0
	_born[slot] = sim_time
	_seq[slot] = _next_seq
	_next_seq += 1
	_skip_left[slot] = 0.0
	_flags[slot] = 0
	_bounce[slot] = 0
	_shield[slot] = 0
	_span[slot] = lifetime
	_radius0[slot] = maxf(radius, 0.0)
	_growth[slot] = 1.0
	_wave[slot] = 0.0
	_wave_age[slot] = 0.0
	_linger[slot] = 0.0
	_hold[slot] = -1.0
	_freeze[slot] = 0.0
	_stick[slot] = 0.0
	_stuck_to[slot] = null
	_base[slot] = origin
	_caster_slot[slot] = CASTER_WIZARD
	_caster_at[slot] = Vector2.INF
	_drop_moves(slot)
	_forget_all(slot)
	_orbit_centre[slot] = Vector2.INF
	_trail[slot] = -1 if motion == MOTION_STILL else _open_row(slot, origin)
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
	return slot


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
## wait for their turn in the hit pass (see `_wait`), so they see the same as before. Then the
## trails take their points.
func step(delta: float) -> void:
	sim_time += delta
	_mem_step += 1
	_last_delta = delta
	_refresh_targets()
	var top: int = _high
	_stepping = true
	_work_left = WORK_PER_STEP
	_pass_common(top, delta)
	for kind in AFTER_HITS:
		if _member_count[kind] > 0:
			_passes[kind].call(_members, kind * _cap, _member_count[kind], delta)
	_pass_hits(top, delta)
	for kind in range(AFTER_HITS, BEHAVIOURS):
		if _member_count[kind] > 0:
			_passes[kind].call(_members, kind * _cap, _member_count[kind], delta)
	_step_index += 1
	_stepping = false
	_sample_trails()


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
		if _skip_left[slot] > 0.0:
			# Only a payload's skip counts down (read only while above 0).
			_skip_left[slot] -= delta
		var at: Vector2 = _pos[slot]
		_prev[slot] = at
		if _life[slot] <= 0.0:
			_state[slot] = S_EXPIRE
			continue
		_state[slot] = S_MOVING
		if _motion[slot] == MOTION_STRAIGHT:
			_pos[slot] = at + _vel[slot] * delta


## Pass 3: every shot in turn (from `_resume`, see WORK_PER_STEP): its end if a pass marked one,
## then the bounds, the walls on its path and its hits.
func _pass_hits(top: int, delta: float) -> void:
	var limit: Rect2 = _bounds.grow(BOUNDS_MARGIN)
	var resume: int = _resume if _resume < top else 0
	var starved_at: int = -1
	for n in top:
		var slot: int = n + resume
		if slot >= top:
			slot -= top
		# A hit handler may have dropped or reused this slot (S_IDLE): a projectile spawned
		# during this step waits for the next one.
		var state: int = _state[slot]
		if state == S_IDLE:
			continue
		_state[slot] = S_DONE
		if state >= S_STUCK:
			if state == S_WAITING:
				_catch_up(slot, delta)
				state = _state[slot]
				_state[slot] = S_DONE
			if state == S_EXPIRE:
				_expire(slot)
				continue
			if state == S_GONE:
				_kill(slot)
				continue
			if state == S_STUCK or state == S_FROZEN:
				continue
		if not limit.has_point(_pos[slot]):
			_kill(slot)
			continue
		# A shot that meets a wall is cut short there: it can still hit what is
		# in front of the wall, then it ends (or bounces). An orbit or ghost shot ignores walls.
		var walled: bool = false
		if _has_walls and _motion[slot] != MOTION_ORBIT and (_flags[slot] & F_GHOST) == 0:
			var cut: float = _wall_hit(_prev[slot], _pos[slot])
			if cut >= 0.0:
				walled = true
				_pos[slot] = _prev[slot].lerp(_pos[slot], cut)
		if _layers[slot] != 0 and not _targets.is_empty():
			if _work_left <= 0:
				if walled:
					_wall_end(slot)
				elif starved_at < 0:
					starved_at = slot
				continue
			# A piercing shot passes through every target on its path this step, each hit once
			# (it remembers it). A hit handler may end it or even reuse the slot.
			var seq: int = _seq[slot]
			_hit_test(slot)
			# What its path no longer touches it may hit again.
			if _alive[slot] != 0 and _seq[slot] == seq:
				_forget_left(slot)
		# A shot that stuck to a target this step stays stuck, even at a wall.
		if walled and _alive[slot] != 0 and (_flags[slot] & F_STUCK) == 0:
			_wall_end(slot)
	_resume = maxi(starved_at, 0)


# --- Shot behaviours, stepped in passes (2026-10-28) ---------------------------------------
# A behaviour that changes how a shot moves is one pass: a function that steps only the shots that
# have it, from a list kept up to date as shots get and lose it. The passes run in the order of
# their numbers (B_*) and of BEHAVIOUR_PASSES, which must match: the one place that says which
# behaviours there are and in which order they run. Behaviours that act only at a wall or a hit
# (bounce, ghost, sticky before it sticks, self-hit, pierce) have no pass: `_pass_hits`,
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
# - orbit: on its own (an orbit shot has no other motion behaviour).
# - return before homing: a shot on its way back does not home.
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
const B_HOMING: int = 5
const B_SPIRAL: int = 6
const B_MOVE: int = 7
const B_SHIELD: int = 8
## How many behaviours there are; the passes of B_* below AFTER_HITS run before the hit pass.
const BEHAVIOURS: int = 9
const AFTER_HITS: int = B_SHIELD
## The pass of each behaviour, by B_* (`_init` makes `_passes` from it).
const BEHAVIOUR_PASSES: Array[StringName] = [
	&"_pass_stuck", &"_pass_growth", &"_pass_linger", &"_pass_orbit", &"_pass_return",
	&"_pass_homing", &"_pass_spiral", &"_pass_move", &"_pass_shield",
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
	var room: float = maxf(_bounds.size.x, _bounds.size.y)
	for n in range(first, first + count):
		var slot: int = list[n]
		if _state[slot] == S_MOVING:
			_radius[slot] = minf(_radius[slot] * pow(_growth[slot], delta), maxf(room, _radius0[slot]))


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
## for its turn, so it circles that shot where it was when the step came to it.
func _pass_orbit(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		if _state[slot] != S_MOVING:
			continue
		var caster: int = _caster_slot[slot]
		var centre: Vector2 = _caster_at[slot]
		if caster == CASTER_WIZARD:
			centre = _anchors[_actor[slot]] if _actor[slot] >= 0 else Vector2.INF
		elif caster >= 0:
			if not _catching_up:
				_wait(slot, B_ORBIT)
				continue
			centre = _caster_position(slot)
		if not centre.is_finite():
			_state[slot] = S_GONE
			continue
		_orbit_angle[slot] = wrapf(_orbit_angle[slot] + _orbit_speed[slot] * delta, -PI, PI)
		var away: Vector2 = Vector2.from_angle(_orbit_angle[slot])
		_pos[slot] = centre + away * _orbit_radius[slot]
		_vel[slot] = Vector2(-away.y, away.x) * (_orbit_radius[slot] * _orbit_speed[slot])
		_orbit_centre[slot] = centre


## Return (`set_return`): from half its life the shot flies back to its caster at the speed it had
## (it may hit again on the way), and ends with an expiry when it gets there; it vanishes when its
## caster's anchor is gone. One whose caster is a shot waits for its turn (see `_pass_orbit`).
func _pass_return(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		if _state[slot] != S_MOVING or _life[slot] > _span[slot] * 0.5:
			continue
		if _caster_slot[slot] >= 0 and not _catching_up:
			_wait(slot, B_RETURN)
			continue
		var flags: int = _flags[slot]
		if (flags & F_TURNED) == 0:
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
		_vel[slot] = way.normalized() * _speed[slot]
		_pos[slot] = _prev[slot] + _vel[slot] * delta
		_state[slot] = S_RETURNING


## Homing (`set_homing`): the shot turns toward the point it last found, at most its turn rate, and
## flies on along its new velocity. On its search step (one in HOMING_PERIOD, slots taking turns)
## it waits for its turn, then looks for a target while there is hit work left (`_homing_point`).
func _pass_homing(list: PackedInt32Array, first: int, count: int, delta: float) -> void:
	for n in range(first, first + count):
		var slot: int = list[n]
		if _state[slot] != S_MOVING:
			continue
		if ((slot + _step_index) % HOMING_PERIOD) == 0:
			if not _catching_up:
				_wait(slot, B_HOMING)
				continue
			if _work_left > 0:
				_home_at[slot] = _homing_point(slot, _prev[slot])
		var goal: Vector2 = _home_at[slot]
		var velocity: Vector2 = _vel[slot]
		if not goal.is_finite() or velocity.is_zero_approx():
			continue
		var want: Vector2 = goal - _prev[slot]
		if want.is_zero_approx():
			continue
		# `turned_toward`, written out (this runs for every homing shot every step).
		var most: float = _turn[slot] * delta
		_vel[slot] = velocity.rotated(clampf(velocity.angle_to(want), -most, most))
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
		_pos[slot] = _base[slot] + side * (_wave[slot] * sin(TAU * _wave_age[slot] / SPIRAL_PERIOD))


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
	# charges and the hit-work budget in that order.
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
		if _alive[slot] != 0 and _shield[slot] > 0 and _state[slot] == S_DONE:
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
	# The corner, so the tail turns there.
	if _trail[slot] >= 0:
		_trail_sample(_trail[slot], at)
	# A bounced shot may hit what it hit before.
	_forget_all(slot)
	# Last: a handler's payload may take this slot over (a cap drop).
	var outer_slot: int = event_slot
	event_slot = slot
	wall_met.emit(_actor[slot], at, _vel[slot].normalized(), _tag[slot])
	event_slot = outer_slot


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
	var x: int = floori((point.x - _bounds.position.x) / WALL_CELL)
	var y: int = floori((point.y - _bounds.position.y) / WALL_CELL)
	return x >= 0 and x < _wall_w and y >= 0 and y < _wall_h and _wall_cells[y * _wall_w + x] != 0


## Check a shielded shot against the shots of other teams (aim, actors G3a: a shield stops
## every shot whose caster was on another team when it was cast, a shot of no actor included,
## never its own team's): every one it touches is stopped, one shield charge each, and
## `shot_blocked` is sent. The list of live shots is made once per step, the first time a shield
## needs it; the scan is charged to the hit-work budget.
func _shield_block(slot: int) -> void:
	if _scan_step != _step_index:
		_scan_step = _step_index
		_scan_count = 0
		for other in _high:
			if _alive[other] != 0:
				_scan_slots[_scan_count] = other
				_scan_count += 1
	var mine: int = _team[slot]
	for n in _scan_count:
		if _shield[slot] <= 0 or _work_left <= 0:
			return
		_work_left -= 1
		var other: int = _scan_slots[n]
		if _alive[other] == 0 or other == slot or _team[other] == mine:
			continue
		var reach: float = _radius[slot] + _radius[other]
		# Both shots move during the step: in the enemy shot's frame the shield goes along
		# the relative path, so the test is the distance from that segment to the origin.
		var start: Vector2 = _prev[slot] - _prev[other]
		var path: Vector2 = (_pos[slot] - _pos[other]) - start
		var along: float = 0.0
		if not path.is_zero_approx():
			along = clampf(-start.dot(path) / path.length_squared(), 0.0, 1.0)
		if (start + path * along).length_squared() > reach * reach:
			continue
		_shield[slot] -= 1
		var at: Vector2 = _pos[other]
		_kill(other)
		if events != null:
			event_slot = slot
			events.shot_blocked.emit(_actor[slot], at, _tag[slot])
			event_slot = -1


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
	var away: Vector2 = Vector2.from_angle(_orbit_angle[slot])
	return Vector2(-away.y, away.x) * (_orbit_radius[slot] * _orbit_speed[slot])


## `velocity` turned toward `want` by at most `most` radians, keeping its length: the one turn
## of homing, for a shot in flight, a shot's move and a wizard's dash. A zero `want` or
## `velocity` gives `velocity` back.
static func turned_toward(velocity: Vector2, want: Vector2, most: float) -> Vector2:
	if velocity.is_zero_approx() or want.is_zero_approx():
		return velocity
	return velocity.rotated(clampf(velocity.angle_to(want), -most, most))


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
	var t: int = _home_pick(_actor[slot], _team[slot], from, Vector2.RIGHT, PI, _layers[slot], _home_range[slot], _home_target[slot], int(_seq[slot]), slot, 0)
	_home_target[slot] = _target_id[t] if t >= 0 else 0
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
## instance id is `keep` stays the pick while it qualifies; otherwise one is picked at random
## among those that do, from `pick_seed` (the same seed and targets give the same pick), so a
## group of shots spreads over a group of enemies. The target whose id is `avoid` (the one it
## just reached) is picked only when no other qualifies. `homing_target` is left at the pick's
## id (0 for none), for the caller to keep. Allocation-free.
func homing_point(caster: int, origin: Vector2, direction: Vector2, max_angle: float, layers: int, within: float, keep: int, pick_seed: int, avoid: int = 0) -> Vector2:
	homing_target = 0
	homing_target_radius = 0.0
	if not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx() or not is_finite(max_angle) or not is_finite(within) or within <= 0.0:
		return Vector2.INF
	_query_ready()
	var t: int = _home_pick(caster, _team_of(caster), origin, direction, max_angle, layers, within, keep, pick_seed, -1, avoid)
	if t < 0:
		return Vector2.INF
	homing_target = _target_id[t]
	homing_target_radius = _target_radius[t]
	return _target_pos[t]


## The one homing search: the target (an index, or -1) `homing_point` describes, for `caster`
## of `team` (NONE: no team, every target but its own body). For a shot (`slot` 0 or more) it
## also skips the targets the shot just hit and charges the work budget.
func _home_pick(caster: int, team: int, origin: Vector2, direction: Vector2, max_angle: float, layers: int, within: float, keep: int, pick_seed: int, slot: int, avoid: int) -> int:
	# Homing never picks its own team (a teammate, for a wizard), though every spell hits it, nor
	# a target the shot is still on (`_mark_memory`).
	var stamp: int = _mark_memory(slot) if slot >= 0 else -1
	var any_way: bool = max_angle >= PI
	var pick: int = -1
	var avoided: int = -1
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
					if to_target.length_squared() <= reach * reach and (any_way or (not to_target.is_zero_approx() and absf(direction.angle_to(to_target)) <= max_angle)):
						if keep != 0 and _target_id[t] == keep:
							return t
						if avoid != 0 and _target_id[t] == avoid:
							avoided = t
							t = _target_next[t]
							continue
						# Reservoir pick: the n-th target seen replaces the pick one time in n.
						seen += 1
						if posmod(hash(Vector2i(pick_seed, seen)), seen) == 0:
							pick = t
				t = _target_next[t]
	return pick if pick >= 0 else avoided


## An instant beam from `origin` along `direction` for `length` pixels, fired by the actor
## `caster`. It holds no row in the pool. It stops at the first wall (or, with `bounces`, turns
## off it as a bouncing shot does, that many times, and goes on for the length it has left) and
## hits the nearest `pierce + 1` targets on `layers` whose circle the beam touches (`width`
## pixels either side of the line; `exclude` is a target it never hits, for a beam that starts
## on the one that fired it). For each, nearest first, it sends `projectile_impact` and
## `projectile_hit(caster, target, point, tag)`, the point being where the beam passes closest
## to the target; a beam that ends on a wall sends an impact with a `null` target there, and one
## that turns at a wall one at every turn (each wall also sends `wall_met`, after the hits).
## Targets owned by `caster` (its own body) are skipped and, as in `spawn`, it hits ACTOR_LAYERS
## whatever `layers` says. Returns how far the beam got in pixels: the length, the distance to
## the wall, or the distance to the last target it could hit. 0.0 for bad arguments or an origin
## inside a wall. The hits are found before any event is sent, so a handler may remove or free
## targets, or fire another ray, as deep as it likes. Nothing caps a ray (RAY_PATH_START). Where
## it ended and its heading there are left in `ray_end` and `ray_end_heading`, and the path it
## walked in `ray_path`. It allocates only when a ray is bigger than any before it.
func ray(caster: int, origin: Vector2, direction: Vector2, length: float, pierce: int = 0, layers: int = LAYER_ENEMY, tag: int = 0, width: float = 0.0, exclude: Node = null, bounces: int = 0) -> float:
	ray_path_count = 0
	if not direction.is_finite() or direction.is_zero_approx() or not is_finite(length) or length <= 0.0 or not origin.is_finite():
		return 0.0
	_path[0] = origin
	_path[1] = origin + direction.normalized() * length
	return _ray_path(caster, 1, pierce, layers, tag, width, exclude, true, bounces)


## A beam like `ray` along the path `points[offset]` to `points[offset + count - 1]`, cut to
## `length` pixels along it: a live beam, whose homing bends it from target to target, and which
## never reaches past its own length. With `hit` false it only finds how far the beam gets
## (walls, and the target that spends it) and sends nothing, for the look of a beam between its
## hits. With `bounces` it turns at walls as `ray` does, and goes on from there along `steer`'s
## path when it is given one (a homing beam homes again after every turn: `steer.call(turn, at,
## way, left)` gets the turn's index in the path, where it is, the way off the wall and the length
## left, and returns the points that follow `at`; empty for straight on), else straight. Returns
## how far it got along the path; `ray_end` and `ray_end_heading` say where, and `ray_path` what
## it walked.
func ray_points(caster: int, points: PackedVector2Array, offset: int, count: int, length: float, pierce: int = 0, layers: int = LAYER_ENEMY, tag: int = 0, width: float = 0.0, exclude: Node = null, hit: bool = true, bounces: int = 0, steer: Callable = Callable()) -> float:
	ray_path_count = 0
	if count < 2 or offset < 0 or offset + count > points.size() or not is_finite(length) or length <= 0.0 or not points[offset].is_finite():
		return 0.0
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
		return 0.0
	return _ray_path(caster, used, pierce, layers, tag, width, exclude, hit, bounces, steer)


## A beam like `ray`, bent: it follows the quadratic curve from `origin` to `end` pulled
## toward `bend` (a homing beam: `bend` along the aim, `end` on the target), walked as
## RAY_SEGMENTS straight pieces. With `hit` false it only finds how far the beam gets (walls, and
## the target that spends it) and sends nothing, for the look of a beam between its hits. With
## `bounces` it turns at walls as `ray` does. Returns how far it got along the curve; `ray_end`
## and `ray_end_heading` say where, and `ray_path` what it walked.
func ray_curve(caster: int, origin: Vector2, bend: Vector2, end: Vector2, pierce: int = 0, layers: int = LAYER_ENEMY, tag: int = 0, width: float = 0.0, exclude: Node = null, hit: bool = true, bounces: int = 0) -> float:
	ray_path_count = 0
	if not origin.is_finite() or not bend.is_finite() or not end.is_finite() or origin.is_equal_approx(end):
		return 0.0
	_path[0] = origin
	for i in range(1, RAY_SEGMENTS + 1):
		var t: float = float(i) / RAY_SEGMENTS
		var u: float = 1.0 - t
		_path[i] = origin * (u * u) + bend * (2.0 * u * t) + end * (t * t)
	return _ray_path(caster, RAY_SEGMENTS, pierce, layers, tag, width, exclude, hit, bounces)


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
## `origin`. Targets `caster` owns (its body) and `exclude` are skipped. It sends nothing: it
## fills `sweep_nodes`, `sweep_points` (where the wedge meets the body, on its line from
## `origin`) and `sweep_heads` (the way the sweep moves there) and returns how many (every one:
## the results grow). Each step of a swing asks for the wedge it turned through since the last, so
## a fast sweep misses nothing between two steps. Allocation-free.
func sweep(caster: int, origin: Vector2, direction: Vector2, side: int, from_angle: float, to_angle: float, reach: float, layers: int = LAYER_ENEMY, exclude: Node = null) -> int:
	if not is_caster(caster) or not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx():
		return 0
	if not is_finite(reach) or reach <= 0.0 or not is_finite(from_angle) or not is_finite(to_angle) or to_angle < from_angle or _targets.is_empty():
		return 0
	_query_ready()
	layers |= ACTOR_LAYERS
	var base: float = direction.angle()
	var turn: float = 1.0 if side >= 0 else -1.0
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
				if (_target_layer[t] & layers) != 0 and (caster < 0 or _target_owner[t] != caster) and _target_id[t] != skip and is_instance_valid(_targets[t]):
					var to: Vector2 = _target_pos[t] - origin
					var radius: float = _target_radius[t]
					var distance: float = to.length()
					if distance <= reach + radius:
						# How far either side of its centre line the body's circle reaches.
						var width: float = PI if distance <= radius else asin(radius / distance)
						var local: float = angle_difference(base, to.angle()) * turn
						if local + width >= from_angle and local - width <= to_angle and not (_has_walls and _wall_hit(origin, _target_pos[t]) >= 0.0):
							var way: Vector2 = to / distance if distance > 0.0 else direction.normalized()
							if found == sweep_nodes.size():
								sweep_nodes.resize(found * 2)
								sweep_points.resize(found * 2)
								sweep_heads.resize(found * 2)
							sweep_nodes[found] = _targets[t]
							sweep_points[found] = origin + way * maxf(distance - radius, 0.0)
							sweep_heads[found] = Vector2(-way.y, way.x) * turn
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
	var outer_slot: int = event_slot
	event_slot = -1
	impact_form = form
	impact_core = Color.WHITE
	impact_look = 0
	events.projectile_impact.emit(caster, target, point, heading)
	impact_form = &""
	events.projectile_hit.emit(caster, target, point, tag)
	_ray_depth -= 1
	event_slot = outer_slot
	return true


## The beam along the first `segments` pieces of `_path` (see `ray` and `ray_curve`).
func _ray_path(caster: int, segments: int, pierce: int, layers: int, tag: int, width: float, exclude: Node, hit: bool, bounces: int = 0, steer: Callable = Callable()) -> float:
	ray_end = Vector2.INF
	ray_end_heading = Vector2.ZERO
	ray_path_count = 0
	if not is_caster(caster):
		return 0.0
	var level: int = _ray_depth
	_ray_level(level)
	# Cut the path at the first wall, or turn there while it has bounces: the rest of the path
	# is dropped and it goes on, off the wall, for the length the rest had: along `steer`'s path
	# (a homing beam homes again), else straight.
	var left_turns: int = maxi(bounces, 0)
	var left: float = 0.0
	if left_turns > 0:
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
		if _has_walls:
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
		for i in used:
			var a: Vector2 = _path[i]
			var b: Vector2 = _path[i + 1]
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
						if (_target_layer[t] & layers) != 0 and (caster < 0 or _target_owner[t] != caster) and _target_id[t] != skip and is_instance_valid(_targets[t]):
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
		return got
	_ray_depth += 1
	var outer_slot: int = event_slot
	event_slot = -1
	for i in found:
		var node: Variant = nodes[i]
		if events != null and is_instance_valid(node):
			impact_form = &"beam"
			impact_core = Color.WHITE
			impact_look = 0
			events.projectile_impact.emit(caster, node, points[i], heads[i])
			impact_form = &""
			impact_core = Color.WHITE
			impact_look = 0
			events.projectile_hit.emit(caster, node, points[i], tag)
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
			events.projectile_impact.emit(caster, null, turn, (walk[n - 1] as Vector2).direction_to(turn))
			impact_form = &""
			impact_core = Color.WHITE
			impact_look = 0
	if walled and events != null:
		impact_form = &"beam"
		impact_core = Color.WHITE
		impact_look = 0
		events.projectile_impact.emit(caster, null, end, end_heading)
		impact_form = &""
		impact_core = Color.WHITE
		impact_look = 0
	for k in turned:
		var n: int = turns[k]
		if n >= walked - 1:
			break
		var turn: Vector2 = walk[n]
		wall_met.emit(caster, turn, turn.direction_to(walk[n + 1]), tag)
	if walled:
		wall_met.emit(caster, end - end_heading * 0.5, end_heading, tag)
	_ray_depth -= 1
	event_slot = outer_slot
	ray_end = end
	ray_end_heading = end_heading
	_keep_ray_path(walk, walked)
	return got


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


## Copy the live projectiles into the one batched draw (a single buffer write).
## Called every frame. Positions are interpolated between physics steps, so
## shots stay smooth on screens faster than the physics rate. Does nothing
## while there are no projectiles. `fraction` (0 to 1) fixes how far between the last two
## steps shots are drawn, instead of the engine's real time since the last physics tick;
## 1.0 draws every shot where its last step put it (the clip recorder needs that).
## Take a trail row for `holder` (a slot, or ROW_CASTER) starting at `at`, or -1 when none is free.
func _open_row(holder: int, at: Vector2) -> int:
	if _trail_free_count == 0:
		return -1
	_trail_free_count -= 1
	var row: int = _trail_free[_trail_free_count]
	_trail_holder[row] = holder
	_trail_kept[row] = 0
	_trail_newest[row] = -1
	_trail_odo[row] = 0.0
	_trail_flags[row] = 0
	if row >= _trail_high:
		_trail_high = row + 1
		_fit_trail_data()
	_trail_sample(row, at)
	return row


## Add the point `at` (now) to trail `row`.
func _trail_sample(row: int, at: Vector2) -> void:
	var kept: int = _trail_kept[row]
	if kept > 0:
		var moved: float = at.distance_to(_trail_last[row])
		if moved > TRAIL_JUMP:
			kept = 0
		else:
			_trail_odo[row] += moved
	var n: int = _trail_newest[row] + 1
	var i: int = row * TRAIL_STRIDE + (n % TRAIL_SAMPLES) * 4
	_trail_data[i] = at.x
	_trail_data[i + 1] = at.y
	_trail_data[i + 2] = _trail_odo[row]
	_trail_data[i + 3] = sim_time
	_trail_newest[row] = n
	_trail_kept[row] = mini(kept + 1, TRAIL_SAMPLES)
	_trail_last[row] = at
	_trail_dirty = true


## The shot in `slot` ended: its trail takes its last point and is drawn on by itself, without a
## core, until all of it has cooled (TRAIL_KEEP).
func _fade_row(row: int, slot: int) -> void:
	_trail_sample(row, _drawn_at(slot, _pos[slot]))
	_trail_caster[row] = _actor[slot]
	_trail_ramp[row] = _ramp[slot]
	_trail_look[row] = _look[slot]
	_trail_core[row] = _core[slot]
	_trail_zoom[row] = look_zoom(_radius[slot])
	_trail_flags[row] = TRAIL_ORBIT if _motion[slot] == MOTION_ORBIT else 0
	_trail_color[row] = look_color(_trail_ramp[row], _trail_zoom[row], _trail_look[row])
	_let_loose(row, sim_time + TRAIL_KEEP)


func _let_loose(row: int, until: float) -> void:
	if _trail_holder[row] != ROW_CASTER:
		_loose[_loose_count] = row
		_loose_count += 1
	_trail_holder[row] = ROW_FADING
	_trail_until[row] = until


## Draw an actor's dash (a wizard's, an enemy's): a trail that follows `caster`'s anchor (see
## `set_anchor`) for `seconds`, in its ramp's colours with the card particles of `look` in the
## ramp of `core`, then cools like a shot's. Returns its row, or -1 when there is no anchor or no
## free row. The path is the caster's own, so a dash that slides along a wall or homes is drawn
## where it went.
func follow_caster(caster: int, core: Color, look: int, seconds: float) -> int:
	if not is_caster(caster) or caster < 0 or not _anchors[caster].is_finite() or not (seconds >= 0.0):
		return -1
	var row: int = _open_row(ROW_CASTER, _anchors[caster])
	if row < 0:
		return -1
	_trail_caster[row] = caster
	_trail_ramp[row] = _ramp_of(caster)
	_trail_look[row] = look
	_trail_core[row] = Color(core.r, core.g, core.b, 1.0)
	_trail_zoom[row] = 1
	_trail_flags[row] = TRAIL_DASH
	_trail_color[row] = look_color(_trail_ramp[row], _trail_zoom[row], _trail_look[row])
	_trail_until[row] = sim_time + seconds
	_loose[_loose_count] = row
	_loose_count += 1
	return row


## Live trails: how many rows a shot or a caster holds, or that are still cooling (for tests).
func get_trail_count() -> int:
	return _trail_free.size() - _trail_free_count


## The trail row of the shot in `slot` (-1 for none or an empty slot), for tests.
func get_trail_of(slot: int) -> int:
	if slot < 0 or slot >= _cap or _alive[slot] == 0:
		return -1
	return _trail[slot]


## How many points trail `row` keeps, and its newest (x, y, odometer, time), for tests.
func get_trail_kept(row: int) -> int:
	return _trail_kept[row] if row >= 0 and row < _trail_kept.size() else 0


func get_trail_point(row: int, back: int) -> Vector4:
	if row < 0 or row >= _trail_kept.size() or back < 0 or back >= _trail_kept[row]:
		return Vector4(INF, INF, INF, INF)
	var i: int = row * TRAIL_STRIDE + ((_trail_newest[row] - back) % TRAIL_SAMPLES) * 4
	return Vector4(_trail_data[i], _trail_data[i + 1], _trail_data[i + 2], _trail_data[i + 3])


## Every TRAIL_EVERY seconds: each flying shot and each caster's trail takes its point, a caster's
## trail whose time is up starts to cool, and the cooled rows are given back.
func _sample_trails() -> void:
	var tick: int = floori(sim_time / TRAIL_EVERY)
	if tick == _trail_tick:
		return
	_trail_tick = tick
	# `_trail_sample` and `_drawn_at` written out: this runs for every flying shot every other step
	# (two calls a shot less: 2.1 -> 1.1 ms a sample at 3,000 shots).
	var now: float = sim_time
	for slot in _high:
		var row: int = _trail[slot]
		if row < 0 or _alive[slot] == 0:
			continue
		var at: Vector2 = _pos[slot]
		if _motion[slot] == MOTION_ORBIT:
			at = _drawn_at(slot, at)
		var kept: int = _trail_kept[row]
		if kept > 0:
			var moved: float = at.distance_to(_trail_last[row])
			if moved > TRAIL_JUMP:
				kept = 0
			else:
				_trail_odo[row] += moved
		var newest: int = _trail_newest[row] + 1
		var i: int = row * TRAIL_STRIDE + (newest % TRAIL_SAMPLES) * 4
		_trail_data[i] = at.x
		_trail_data[i + 1] = at.y
		_trail_data[i + 2] = _trail_odo[row]
		_trail_data[i + 3] = now
		_trail_newest[row] = newest
		_trail_kept[row] = mini(kept + 1, TRAIL_SAMPLES)
		_trail_last[row] = at
		_trail_dirty = true
	var n: int = 0
	while n < _loose_count:
		var row: int = _loose[n]
		if _trail_holder[row] == ROW_CASTER:
			var at: Vector2 = _anchors[_trail_caster[row]]
			if at.is_finite():
				_trail_sample(row, at)
			if sim_time >= _trail_until[row] or not at.is_finite():
				_trail_holder[row] = ROW_FADING
				_trail_until[row] = sim_time + TRAIL_KEEP
		elif sim_time >= _trail_until[row]:
			# Cooled: give the row back.
			_trail_holder[row] = ROW_FREE
			_trail_free[_trail_free_count] = row
			_trail_free_count += 1
			_loose_count -= 1
			_loose[n] = _loose[_loose_count]
			continue
		n += 1
	while _trail_high > 0 and _trail_holder[_trail_high - 1] == ROW_FREE:
		_trail_high -= 1


## Size `_trail_data` for the rows in use: a power of two, at least MIN_TRAIL_ROWS.
func _fit_trail_data() -> void:
	var wanted: int = maxi(_trail_rows, MIN_TRAIL_ROWS)
	while wanted < _trail_high:
		wanted *= 2
	if wanted != _trail_rows:
		_trail_rows = wanted
		_trail_data.resize(wanted * TRAIL_STRIDE)
		_trail_texture = null


## Send the trails to the shader when a row changed: one texture of `_trail_rows` rows.
func _upload_trails() -> void:
	if not _trail_dirty or _trail_rows == 0:
		return
	_trail_dirty = false
	if _trail_image == null:
		_trail_image = Image.create_empty(TRAIL_SAMPLES, _trail_rows, false, Image.FORMAT_RGBAF)
	_trail_image.set_data(TRAIL_SAMPLES, _trail_rows, false, Image.FORMAT_RGBAF, _trail_data.to_byte_array())
	if _trail_texture == null or _trail_texture.get_height() != _trail_rows:
		_trail_texture = ImageTexture.create_from_image(_trail_image)
		for node: MultiMeshInstance2D in [_draw_node, _orbit_node, _enemy_node]:
			(node.material as ShaderMaterial).set_shader_parameter(&"trail_data", _trail_texture)
	else:
		_trail_texture.update(_trail_image)


func update_draw(fraction: float = -1.0) -> void:
	if _draw_node == null:
		drawn = 0
		return
	if _high == 0 and drawn == 0 and drawn_trails == 0 and _loose_count == 0:
		return
	var multimesh: MultiMesh = _draw_node.multimesh
	if fraction < 0.0:
		fraction = Engine.get_physics_interpolation_fraction()
	fraction = clampf(fraction, 0.0, 1.0)
	_set_sim_time(_draw_node, fraction)
	_set_sim_time(_rune_node, fraction)
	_set_sim_time(_orbit_node, fraction)
	_set_sim_time(_enemy_node, fraction)
	_set_sim_time(_enemy_rune_node, fraction)
	_upload_trails()
	_count_batches()
	var counts: PackedInt32Array = _batch_counts
	# The bolts' and the enemies' batches also draw the loose trails (more than the cap).
	_draw_room = _fit_batch(multimesh, _draw_buffer, _draw_room, counts[BATCH_BOLT], _cap * (1 + TRAIL_ROWS_PER_SLOT))
	_rune_room = _fit_batch(_rune_node.multimesh, _rune_buffer, _rune_room, counts[BATCH_RUNE])
	_orbit_room = _fit_batch(_orbit_node.multimesh, _orbit_buffer, _orbit_room, counts[BATCH_ORBIT])
	_enemy_room = _fit_batch(_enemy_node.multimesh, _enemy_buffer, _enemy_room, counts[BATCH_ENEMY], _cap * (1 + TRAIL_ROWS_PER_SLOT))
	_enemy_rune_room = _fit_batch(_enemy_rune_node.multimesh, _enemy_rune_buffer, _enemy_rune_room, counts[BATCH_ENEMY_RUNE])
	var out: int = 0
	var rune_out: int = 0
	var orbit_out: int = 0
	var enemy_out: int = 0
	var enemy_rune_out: int = 0
	var asked: int = 0
	var trails: int = 0
	for slot in _high:
		if _alive[slot] == 0:
			continue
		var motion: int = _motion[slot]
		var at: Vector2 = _prev[slot].lerp(_pos[slot], fraction)
		if motion == MOTION_ORBIT:
			at = _drawn_at(slot, at)
		# `_count_batches` brought the slot's drawn data up to date.
		var batch: int = _drawn_batch[slot]
		var size: float = _drawn_size[slot]
		var look_data: Color = _drawn_color[slot]
		asked += _drawn_particles[slot]
		var rune: bool = motion == MOTION_STILL
		# Only a rune's quad turns with the shot (a trail is drawn along its path).
		var dir: Vector2 = Vector2.RIGHT
		if rune:
			if _vel[slot].length_squared() > 0.0:
				dir = _vel[slot].normalized()
		else:
			trails += TRAIL_COST
		var flags: int = TRAIL_HEAD | (TRAIL_ORBIT if motion == MOTION_ORBIT else 0)
		if batch == BATCH_ENEMY:
			_write_trail(_enemy_buffer, enemy_out * DRAW_STRIDE, _trail[slot], at, flags, look_data, _core[slot])
			enemy_out += 1
		elif batch == BATCH_ENEMY_RUNE:
			_write_quad(_enemy_rune_buffer, enemy_rune_out * DRAW_STRIDE, dir, size, at, look_data, _core[slot], KIND_RUNE, 0.0, trace_code(sim_time - _born[slot]))
			enemy_rune_out += 1
		elif batch == BATCH_RUNE:
			_write_quad(_rune_buffer, rune_out * DRAW_STRIDE, dir, size, at, look_data, _core[slot], KIND_RUNE, 0.0, trace_code(sim_time - _born[slot]))
			rune_out += 1
		elif batch == BATCH_ORBIT:
			_write_trail(_orbit_buffer, orbit_out * DRAW_STRIDE, _trail[slot], at, flags, look_data, _core[slot])
			orbit_out += 1
		else:
			_write_trail(_draw_buffer, out * DRAW_STRIDE, _trail[slot], at, flags, look_data, _core[slot])
			out += 1
	var shots_out: int = out + rune_out + orbit_out + enemy_out + enemy_rune_out
	var enemy_shots: int = enemy_out + enemy_rune_out
	# The trails held by no live shot: cooling where their shot ended, or following a caster.
	for n in _loose_count:
		var row: int = _loose[n]
		var caster: int = _trail_caster[row]
		var head: Vector2 = _trail_last[row]
		var flags: int = _trail_flags[row]
		if _trail_holder[row] == ROW_CASTER:
			flags |= TRAIL_HEAD
			if _anchors[caster].is_finite():
				head = _anchors[caster]
		var data: Color = _trail_color[row]
		var ramp: int = _trail_ramp[row]
		if ramp >= 0 and ramp < ActorsScript.RAMP_ENEMY:
			# A hat ramp (`is_hat_ramp`, written out: this runs for every cooling trail every frame).
			_write_trail(_draw_buffer, out * DRAW_STRIDE, row, head, flags, data, _trail_core[row])
			out += 1
		else:
			_write_trail(_enemy_buffer, enemy_out * DRAW_STRIDE, row, head, flags, data, _trail_core[row])
			enemy_out += 1
	if out > 0:
		multimesh.buffer = _draw_buffer
	multimesh.visible_instance_count = out
	if rune_out > 0:
		_rune_node.multimesh.buffer = _rune_buffer
	_rune_node.multimesh.visible_instance_count = rune_out
	if orbit_out > 0:
		_orbit_node.multimesh.buffer = _orbit_buffer
	_orbit_node.multimesh.visible_instance_count = orbit_out
	if enemy_out > 0:
		_enemy_node.multimesh.buffer = _enemy_buffer
	_enemy_node.multimesh.visible_instance_count = enemy_out
	if enemy_rune_out > 0:
		_enemy_rune_node.multimesh.buffer = _enemy_rune_buffer
	_enemy_rune_node.multimesh.visible_instance_count = enemy_rune_out
	drawn_enemy = enemy_shots
	drawn = shots_out
	drawn_trails = out + rune_out + orbit_out + enemy_out + enemy_rune_out - shots_out
	_share_pool(asked, trails)


## Work out what `update_draw` keeps for the shot in `slot` (see `_drawn_seq`).
func _remember_drawn(slot: int) -> void:
	_drawn_seq[slot] = _seq[slot]
	_drawn_radius[slot] = _radius[slot]
	_drawn_look[slot] = _look[slot]
	_drawn_batch[slot] = _batch_of(slot)
	_drawn_color[slot] = _look_color(slot)
	_drawn_size[slot] = look_size(_radius[slot])
	_drawn_particles[slot] = particles_of(_look[slot])


## Hand the shader the simulation clock (the shot shaders animate from it), and the moment
## the heads are drawn at, `fraction` of the way through the last step (`trail_now`).
func _set_sim_time(node: MultiMeshInstance2D, fraction: float) -> void:
	var material: ShaderMaterial = node.material as ShaderMaterial
	material.set_shader_parameter(&"sim_time", sim_time)
	material.set_shader_parameter(&"trail_now", sim_time - (1.0 - fraction) * _last_delta)


## Share the spark pool out for a frame that asked for `asked` particles and `trails` of trail:
## the particles come first, the trails get what is left of the cap (see PARTICLE_CAP), and the
## shader draws that share of each.
func _share_pool(asked: int, trails: int) -> void:
	particle_demand = asked
	trail_demand = trails
	var cap: float = float(maxi(particle_cap, 0))
	particle_share = 1.0 if asked <= 0 else minf(1.0, cap / float(asked))
	trail_share = 1.0 if trails <= 0 else clampf((cap - float(asked)) / float(trails), 0.0, 1.0)
	_set_shares(_draw_node)
	_set_shares(_rune_node)
	_set_shares(_orbit_node)
	_set_shares(_enemy_node)
	_set_shares(_enemy_rune_node)


func _set_shares(node: MultiMeshInstance2D) -> void:
	var material: ShaderMaterial = node.material as ShaderMaterial
	material.set_shader_parameter(&"particle_share", particle_share)
	material.set_shader_parameter(&"trail_share", trail_share)


## How many particles the pool is asked for by a shot with the packed `look`: 4 + 2 per
## emitting kind (every kind but the weave, which changes the body), at most 12; none for a
## plain shot. The shot shaders (`shot_rune.gdshader`, `shot_orbit.gdshader`) hold the same rule;
## keep them equal.
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


## Which draw batch a live slot belongs to (BATCH_*), by its ramp and body. The one rule both
## the counting and the writing use, so a batch always has the room its writes need.
func _batch_of(slot: int) -> int:
	if not is_hat_ramp(_ramp[slot]):
		return BATCH_ENEMY_RUNE if _motion[slot] == MOTION_STILL else BATCH_ENEMY
	if _motion[slot] == MOTION_STILL:
		return BATCH_RUNE
	if _motion[slot] == MOTION_ORBIT:
		return BATCH_ORBIT
	return BATCH_BOLT


## The body a shader-drawn shot has (KIND_BOLT, KIND_RUNE or KIND_ORBIT), by its motion.
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
			_batch_counts[_drawn_batch[slot]] += 1
	for n in _loose_count:
		var ramp: int = _trail_ramp[_loose[n]]
		_batch_counts[BATCH_BOLT if ramp >= 0 and ramp < ActorsScript.RAMP_ENEMY else BATCH_ENEMY] += 1


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
	return look_color(_ramp[slot], look_zoom(_radius[slot]), _look[slot])


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


## Write trail `row`'s instance at float index `i` of `buffer` (-1: a shot without a trail, drawn
## by its core alone): its data in the transform, which `shot_trail.gdshader` reads back (its
## quads are placed from it; the batch sits untransformed at the origin), the head `at`, the
## colour and the core.
func _write_trail(buffer: PackedFloat32Array, i: int, row: int, at: Vector2, flags: int, color: Color, core: Color) -> void:
	buffer[i] = float(row)
	buffer[i + 1] = float(_trail_kept[row]) if row >= 0 else 0.0
	buffer[i + 2] = 0.0
	buffer[i + 3] = at.x
	buffer[i + 4] = float(_trail_newest[row]) if row >= 0 else 0.0
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
	_drop_moves(slot)
	if announce and _tag[slot] != 0:
		shot_ended.emit(_tag[slot])
	if _trail[slot] >= 0:
		_fade_row(_trail[slot], slot)
		_trail[slot] = -1
	if _kinds[slot] != 0:
		_leave_all(slot)
	_alive[slot] = 0
	_state[slot] = S_IDLE
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
	_kill(slot, false)
	if events != null:
		event_slot = slot
		impact_form = _form_of(slot)
		impact_core = _core[slot]
		impact_look = _look[slot]
		impact_heading = _vel[slot].normalized()
		events.projectile_expired.emit(caster, at, tag)
		impact_form = &""
		impact_core = Color.WHITE
		impact_look = 0
		impact_heading = Vector2.ZERO
		event_slot = -1
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
func exclude(slot: int, node: Node, seconds: float) -> void:
	if slot >= 0 and slot < _cap and _alive[slot] != 0 and node != null:
		_skip_id[slot] = node.get_instance_id()
		_skip_left[slot] = seconds


## The spawn number of the shot in `slot`: it changes when the slot is reused, so a
## listener can tell a shot it knows from a newer one in the same slot.
func get_seq_of(slot: int) -> int:
	return _seq[slot] if slot >= 0 and slot < _cap else -1


## The tag of the shot in `slot` (kept after it ended, until the slot is reused).
func get_tag_of(slot: int) -> int:
	return _tag[slot] if slot >= 0 and slot < _cap else 0


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


## The instance id of the target the last `homing_point`, `homing_aim` or `home_velocity`
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
	_target_radius[at] = _target_radius[last]
	_target_layer[at] = _target_layer[last]
	_target_owner[at] = _target_owner[last]
	_target_team[at] = _target_team[last]
	_target_pos[at] = _target_pos[last]
	_target_offset[at] = _target_offset[last]
	_targets.resize(last)
	_target_id.resize(last)
	_target_radius.resize(last)
	_target_layer.resize(last)
	_target_owner.resize(last)
	_target_team.resize(last)
	_target_pos.resize(last)
	_target_offset.resize(last)
	_target_next.resize(last)


## Drop freed targets, read the positions of the rest and fill the grid.
func _refresh_targets() -> void:
	if _targets.is_empty():
		_cell_head.fill(-1)
		_cell_count.fill(0)
		_grid_stale = false
		return
	var at: int = 0
	while at < _targets.size():
		var node: Variant = _targets[at]
		if not is_instance_valid(node) or _target_layer[at] == 0:
			_remove_target_at(at)
			continue
		at += 1
	_cell_head.fill(-1)
	_cell_count.fill(0)
	_grid_stale = false
	# The table once for every target (this runs every step for every body).
	var table: ActorsScript = actor_table()
	for i in _targets.size():
		var node: Node2D = _targets[i]
		_target_next[i] = -1
		# A possession may have moved the owner to another team since the last step
		# (`_team_of_target`, written out).
		var owner: int = _target_owner[i]
		var team: int = table.team_of(owner) if owner >= 0 and table != null else ActorsScript.NONE
		if team == ActorsScript.NONE:
			team = ActorsScript.TEAM_WIZARDS if (_target_layer[i] & LAYER_PLAYER) != 0 else ActorsScript.TEAM_ENEMIES
		_target_team[i] = team
		if not node.is_inside_tree():
			_target_pos[i] = Vector2.INF
			continue
		var centre: Vector2 = node.global_position + _target_offset[i]
		_target_pos[i] = centre
		# Its grid cell (written out: every target, every step).
		var cell: int = clampi(floori((centre.y - _grid_y) / GRID_CELL), 0, _grid_h - 1) * _grid_w + clampi(floori((centre.x - _grid_x) / GRID_CELL), 0, _grid_w - 1)
		_target_next[i] = _cell_head[cell]
		_cell_head[cell] = i
		var r: float = _target_radius[i]
		var box: Vector4 = Vector4(centre.x - r, centre.y - r, centre.x + r, centre.y + r)
		if _cell_count[cell] > 0:
			var had: Vector4 = _cell_box[cell]
			box = Vector4(minf(box.x, had.x), minf(box.y, had.y), maxf(box.z, had.z), maxf(box.w, had.w))
		_cell_box[cell] = box
		_cell_count[cell] += 1


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


## Fill `out` (cleared first) with the targets on `layers` whose hit circle overlaps
## the circle (`point`, `radius`), and return how many. Pass the same array each time
## so nothing is allocated. Order is not defined.
func targets_in(point: Vector2, radius: float, layers: int, out: Array[Node2D]) -> int:
	out.clear()
	if not point.is_finite() or not is_finite(radius):
		return 0
	_query_ready()
	var cells: Vector4i = _query_cells(point, radius)
	for y in range(cells.y, cells.w + 1):
		for x in range(cells.x, cells.z + 1):
			var t: int = _cell_head[y * _grid_w + x]
			while t >= 0:
				if _query_match(t, point, radius, layers, 0):
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
	# What a target must touch to be hit (or to hold a self-hitting shot): the path's box widened
	# by the shot's radius (and a little, for rounding).
	var margin: Vector2 = Vector2.ONE * (radius + 0.05)
	var near_low: Vector2 = lowest - margin
	var near_high: Vector2 = highest + margin
	var path: Vector2 = to - from
	var path_sq: float = path.length_squared()
	# A target farther from the path's middle than half the path plus both radii misses: that one
	# distance turns most of the targets in the cells away before anything else is read of them
	# (a target the shot is inside of is never that far either).
	var middle: Vector2 = (from + to) * 0.5
	var half: float = sqrt(path_sq) * 0.5 + 0.01
	var layers: int = _layers[slot]
	var shooter: int = _actor[slot]
	var flags: int = _flags[slot]
	var skip_left: bool = _skip_left[slot] > 0.0
	var stamp: int = _mark_memory(slot)
	var found: int = 0
	var inside: bool = false
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell: int = y * _grid_w + x
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
			var t: int = _cell_head[cell]
			while t >= 0:
				var centre: Vector2 = _target_pos[t]
				var reach: float = radius + _target_radius[t]
				var far: float = half + reach
				if middle.distance_squared_to(centre) > far * far:
					t = _target_next[t]
					continue
				if shooter >= 0 and _target_owner[t] == shooter:
					# The shooter's own body: only a self-hitting shot that has left it.
					if (flags & F_SELF) == 0:
						t = _target_next[t]
						continue
					if (flags & F_SELF_LIVE) == 0:
						if to.distance_squared_to(centre) <= reach * reach:
							inside = true
						t = _target_next[t]
						continue
				elif (_target_layer[t] & layers) == 0:
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
				if skip_left and _skip_id[slot] == _target_id[t]:
					t = _target_next[t]
					continue
				found = _keep_candidate(found, t, along, closest)
				t = _target_next[t]
	if (flags & F_SELF) != 0 and (flags & F_SELF_LIVE) == 0 and not inside:
		_flags[slot] |= F_SELF_LIVE
	# Hit them nearest first. A hit handler may end the shot or take its slot; a stuck one stops.
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
		if t < 0 or t >= _targets.size() or _target_id[t] != _mem_id[at]:
			t = _target_id.find(_mem_id[at])
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


## The shot in `slot` hit target `t` this step: remember it until it leaves it.
func _remember(slot: int, t: int) -> void:
	if _mem_free < 0:
		_grow_memory(_mem_id.size() * 2)
	var at: int = _mem_free
	_mem_free = _mem_next[at]
	_mem_id[at] = _target_id[t]
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
		impact_core = _core[slot]
		impact_look = _look[slot]
		events.projectile_impact.emit(_actor[slot], null, _pos[slot], velocity.normalized())
		impact_form = &""
		impact_core = Color.WHITE
		impact_look = 0


## The form of the shot in `slot`, by its body.
func _form_of(slot: int) -> StringName:
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
		_stuck_off[slot] = at - (node as Node2D).global_position
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
		_kill(slot, false)
	if events != null and is_instance_valid(node):
		impact_form = _form_of(slot)
		impact_core = _core[slot]
		impact_look = _look[slot]
		events.projectile_impact.emit(caster, node, at, heading)
		impact_form = &""
		impact_core = Color.WHITE
		impact_look = 0
		event_slot = slot
		events.projectile_hit.emit(caster, node, at, tag)
		event_slot = -1
	if spent and tag != 0:
		shot_ended.emit(tag)
