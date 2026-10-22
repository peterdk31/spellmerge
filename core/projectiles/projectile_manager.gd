extends Node2D
## The projectile manager: one autoload ("Projectiles") that simulates every
## spell projectile in bulk and draws them all in one batch. Projectiles are
## rows in packed arrays, never nodes, so thousands cost little (PLAN budgets:
## 1,000 on the web, 3,000 on desktop).
##
##     Projectiles.add_target(enemy, 10.0, Projectiles.LAYER_ENEMY)
##     Projectiles.spawn(player, origin, direction * 300.0, 1.5, 4.0)
##
## Targets are Node2Ds registered with a radius and a layer. A projectile hits
## the targets on the layers in its `hit_layers` mask: a fired spell hits
## LAYER_ENEMY, an enemy's shot hits LAYER_PLAYER. A hit sends
## `Events.projectile_hit(player, target, position, tag)`; the projectile then
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
## projectile can hit up to HIT_MEMORY targets in one step (a fast shot passing
## through a crowd), nearest first. It remembers the last HIT_MEMORY targets it
## hit and does not hit them again until it has hit that many others.
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
## Drawing: two batches. Shots of players are tinted with their colour; enemy shots
## (owner NO_PLAYER) have their own texture (`hostile_texture`), are not tinted and are
## drawn one layer above, so a dangerous shot never hides under a friendly one.
##
## Friendly fire: while `friendly_fire` is on, a shot fired by a player (0-3) also
## hits targets on LAYER_PLAYER, except targets registered with that same player
## as their `owner` (a wizard is never hit by its own shot). It is off by default
## and read when a shot is spawned. `gameplay/coop` owns the option.
##
## Walls: `set_walls(rects)` (or `add_wall_body(body)` for a room's static body) gives
## the solid parts of the room. They are rasterised into a grid of WALL_CELL
## pixel cells, so a wall check is a walk over the cells the step's path crosses
## (a few for a normal shot; at most MAX_WALL_VISITS for a huge step, and a path
## not fully walked then counts as a wall hit) and needs no physics query. A
## projectile whose path enters a solid cell ends there, even a piercing one:
## there is no bouncing. It is checked as a point, not a circle. The step is cut
## at the wall first, so a target in front of the wall is still hit by a fast
## shot, and one behind it is not. The wall walk is not charged to the work
## budget above (its length is capped instead). `wall_hits` counts these ends.
## `clip_to_walls(from, to)` shortens a segment to the first wall. `spawn` refuses
## (-1, counted in `wall_hits`) a shot that starts inside a wall, so it takes no
## pool slot and evicts nobody at the cap. Each wall end, and each hit on a
## target, also sends `Events.projectile_impact(player, target, position,
## direction)` (target `null` for a wall), so a listener can show dust or a spray
## without asking the manager anything; it changes nothing here.
##
## The global cap (`get_cap()`, set by platform: DEFAULT_CAP_WEB or
## DEFAULT_CAP_DESKTOP) degrades gracefully. When it is full, a new projectile
## is never refused: the oldest projectile of whoever owns the most of them is
## dropped (in constant time: each owner's projectiles are a list in spawn
## order). Nobody is starved, and a player who floods the screen only loses
## their own old shots. `dropped` counts these. Spell limits (projectiles per
## cast, trigger depth) keep the cap from being reached often.
##
## Expiry: a shot that ends because its life ran out, or on a wall, sends
## `Events.projectile_expired(player, position, tag)` once, after it is removed (so a
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
## Orbit: `spawn_orbit` starts a shot that circles its owner. The owner's position comes
## from a per-player anchor that `set_anchor(player, position)` is given every physics step
## (by `player`), so the manager never looks up a node. The shot's place is the anchor plus
## a turning offset, so it follows a walking wizard; its velocity is the tangent, for the
## drawing. An orbit shot ignores walls (it is held by its caster, who is never inside one)
## and ends quietly, with no event, when its owner's anchor is cleared (`clear_anchor`:
## the wizard left or fell). A step in which the anchor jumped far makes a long path, which
## the hit-work budget bounds as it does for any fast shot.
##
## Homing: `set_homing(slot, turn_rate)` makes a straight shot turn toward the nearest
## target within HOMING_RANGE, at most `turn_rate` radians a second, keeping its speed.
## The search runs on the grid and only every HOMING_PERIOD-th step of a shot (slots take
## turns, so the cost is spread); in between the shot keeps turning toward the point it
## found. It never homes on its shooter's own body or on targets it just hit. The search
## is charged to the step's hit-work budget (1 per target examined); when the budget is
## spent the search waits for the shot's next turn. `homing_aim` does the same for a ray.
##
## An orbit shot is an ordinary piercing shot: `pierce` is how many hits it survives, and
## it remembers only its last HIT_MEMORY targets, so a ring that overlaps more than
## HIT_MEMORY enemies at once hits some of them again on later steps. There is no
## once-per-revolution rule; the orbit form (part 10) picks `pierce` for what it wants.
##
## Rays: `ray(...)` is an instant beam. It holds no row; see its comment.
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
## Nothing here allocates per frame: the arrays are sized when the cap is set,
## and the grid is reused. Coordinates are world coordinates (the manager sits
## at the origin). A handler of `projectile_hit` may spawn more projectiles;
## those start moving on the next step. Tests call `step()` directly.

const EventsScript := preload("res://core/events/events.gd")

## A shot with a non-zero tag ended; see "Ends" above.
signal shot_ended(tag: int)

const MAX_PLAYERS: int = 4
## Motion modes of a shot (see the class doc).
const MOTION_STRAIGHT: int = 0
const MOTION_STILL: int = 1
## Only `spawn_orbit` makes this one.
const MOTION_ORBIT: int = 2
## Default global caps on live projectiles: the PLAN budgets for each platform.
const DEFAULT_CAP_WEB: int = 1000
const DEFAULT_CAP_DESKTOP: int = 3000
## How many recently hit targets a piercing projectile remembers; also the most
## hits one projectile can register in a single step.
const HIT_MEMORY: int = 3
## The most hit-test work one step does, in units: each target examined costs 1,
## each hit costs HIT_WORK. Once it is spent, the remaining projectiles are not
## tested this step (see the class doc). Normal play uses a tiny part of it.
const WORK_PER_STEP: int = 8000

## The most wall cells one shot walks in one step (see `_wall_hit`).
const MAX_WALL_VISITS: int = 64
## The work one hit counts for: the event, its handlers and the bookkeeping.
const HIT_WORK: int = 40
## A homing shot looks for a target one step in this many (slots take turns).
const HOMING_PERIOD: int = 4
## How far from a homing shot (or a beam's origin) a target can be and still be homed on.
const HOMING_RANGE: float = 160.0
## The most targets one ray can hit.
const RAY_MAX_HITS: int = 64
## How many rays can be in progress at once: a hit handler that fires another ray (an
## on-hit trigger) nests one level. A deeper one returns 0.0.
const RAY_MAX_DEPTH: int = 4
## The longest beam in pixels: what the wall walk (MAX_WALL_VISITS cells) covers even on
## a diagonal. A longer `length` is cut to this, so a beam never ends on a wall it did
## not look at. Rays are not charged to the hit-work budget; how many a spell fires (and
## so how far a handler's own rays fan out) is bounded by the spell runtime's fire cap.
const RAY_MAX_LENGTH: float = 360.0
## Floats per projectile in the MultiMesh buffer: 8 transform, 4 colour.
const DRAW_STRIDE: int = 12
## Draw order of the shots: above the room and the wizards. The autoload is drawn
## before the current scene, so at z_index 0 the room's floor hid every shot.
const DRAW_Z: int = 50
## A shot is drawn this many times wider than its hit circle (the art has empty
## margins and a pixel-art bolt is small on a 640x360 view).
const DRAW_SCALE: float = 3.0
## How much of the owner's colour tints the art (the rest stays white): a full
## multiply turned the orange bolt of a blue wizard nearly black.
const TINT_STRENGTH: float = 0.45
## Wall grid cell size in pixels. Walls are rounded out to whole cells, so they are
## exact when their edges are multiples of it (room tiles are 32 px).
const WALL_CELL: float = 8.0
## Spatial grid cell size in pixels.
const GRID_CELL: float = 64.0
## Projectiles that leave the bounds by more than this are removed.
const BOUNDS_MARGIN: float = 128.0
## Target layers (bit mask).
const LAYER_ENEMY: int = 1
const LAYER_PLAYER: int = 2
## The base colour of each player's ramp (docs/STYLE.md); enemy shots are Fire.
const PLAYER_COLORS: Array[Color] = [
	Color("#3b73c9"), Color("#d9477a"), Color("#3f8f4f"), Color("#8a4fc4"),
]
const ENEMY_COLOR: Color = Color("#e0592f")

## Drawn tinted with the colour of the owner. Set a texture for the real art.
var texture: Texture2D = null:
	set(value):
		texture = value
		_apply_textures()
## The art of enemy shots (owner NO_PLAYER), drawn apart from the players' shots: other
## shape, no tint, on top. Left empty, they use `texture`.
var hostile_texture: Texture2D = null:
	set(value):
		hostile_texture = value
		_apply_textures()
var events: EventsScript = null
## How many projectiles were dropped because the cap was full, since start.
var dropped: int = 0
## The slot of the shot whose hit or expiry event is being sent, else -1. See "Ends".
var event_slot: int = -1
## How many projectiles ended on a wall, since start.
var wall_hits: int = 0
## Projectiles written into the batch by the last update_draw().
var drawn: int = 0
## Whether shots fired by players also hit other players' targets (see the class doc).
var friendly_fire: bool = false

var _cap: int = 0
var _count: int = 0
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
var _player: PackedInt32Array = PackedInt32Array()
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
## Homing: turn rate in rad/s (0 for none) and the point last found (INF for none).
var _turn: PackedFloat32Array = PackedFloat32Array()
var _home_at: PackedVector2Array = PackedVector2Array()
## Spawn order, so "oldest" is the lowest.
var _seq: PackedInt64Array = PackedInt64Array()
## HIT_MEMORY target ids per slot, newest first (0 for none).
var _last_hit: PackedInt64Array = PackedInt64Array()
## Per-owner list of live slots in spawn order (oldest at the head), indexed
## like _owned: head and tail slot per owner (-1 for none), and the links.
var _own_head: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1, -1])
var _own_tail: PackedInt32Array = PackedInt32Array([-1, -1, -1, -1, -1])
var _own_prev: PackedInt32Array = PackedInt32Array()
var _own_next: PackedInt32Array = PackedInt32Array()
var _alive: PackedByteArray = PackedByteArray()
## Stack of free slots.
var _free_slots: PackedInt32Array = PackedInt32Array()
var _free_count: int = 0
## Live projectiles per owner; index 0 is NO_PLAYER, 1..4 are players 0..3.
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
## The grid: first target in each cell (-1 for none), and the next in its chain.
var _grid_w: int = 1
var _grid_h: int = 1
var _cell_head: PackedInt32Array = PackedInt32Array()
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

var _draw_node: MultiMeshInstance2D = null
var _draw_buffer: PackedFloat32Array = PackedFloat32Array()
## The second batch, for enemy shots (see `hostile_texture`).
var _hostile_node: MultiMeshInstance2D = null
var _hostile_buffer: PackedFloat32Array = PackedFloat32Array()
## Enemy shots written by the last update_draw() (part of `drawn`).
var drawn_hostile: int = 0
## True inside step(): the grid is in use, so a target removed then is only
## switched off (layer 0) and swept at the start of the next step.
var _stepping: bool = false
## Hit-test work left in this step, and the slot the next step starts from
## (the first one that went untested when the budget ran out).
var _work_left: int = 0
var _resume: int = 0
## Steps taken so far (staggers the homing searches).
var _step_index: int = 0
## Where each player's orbit shots circle (INF for no anchor), see `set_anchor`.
## Per slot: the target a shot must not hit, and the seconds left of that.
var _skip_id: PackedInt64Array = PackedInt64Array()
var _skip_left: PackedFloat32Array = PackedFloat32Array()
var _anchors: PackedVector2Array = PackedVector2Array([Vector2.INF, Vector2.INF, Vector2.INF, Vector2.INF])
## Scratch for `ray`, RAY_MAX_HITS rows per nesting level: the best hits so far, nearest
## first (reused, never grows). `_ray_depth` is how many rays are in progress.
var _ray_nodes: Array = []
var _ray_along: PackedFloat32Array = PackedFloat32Array()
var _ray_points: PackedVector2Array = PackedVector2Array()
var _ray_depth: int = 0


func _init() -> void:
	_ray_nodes.resize(RAY_MAX_HITS * RAY_MAX_DEPTH)
	_ray_along.resize(RAY_MAX_HITS * RAY_MAX_DEPTH)
	_ray_points.resize(RAY_MAX_HITS * RAY_MAX_DEPTH)
	set_cap(DEFAULT_CAP_WEB if OS.has_feature("web") else DEFAULT_CAP_DESKTOP)
	set_bounds(_bounds)


func _ready() -> void:
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	_draw_node = _make_batch(DRAW_Z)
	_hostile_node = _make_batch(DRAW_Z + 1)
	_apply_textures()
	_fit_draw_bounds()


## One batched draw of up to `_cap` quads (TRANSFORM_2D plus a colour each), added as a child.
func _make_batch(z: int) -> MultiMeshInstance2D:
	var node := MultiMeshInstance2D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = _cap
	multimesh.visible_instance_count = 0
	node.multimesh = multimesh
	node.z_index = z
	add_child(node)
	return node


func _apply_textures() -> void:
	if _draw_node != null:
		_draw_node.texture = texture
	if _hostile_node != null:
		_hostile_node.texture = hostile_texture if hostile_texture != null else texture


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
	_player.resize(_cap)
	_layers.resize(_cap)
	_pierce.resize(_cap)
	_tag.resize(_cap)
	_motion.resize(_cap)
	_orbit_radius.resize(_cap)
	_orbit_angle.resize(_cap)
	_orbit_speed.resize(_cap)
	_turn.resize(_cap)
	_home_at.resize(_cap)
	_seq.resize(_cap)
	_skip_id.resize(_cap)
	_skip_left.resize(_cap)
	_last_hit.resize(_cap * HIT_MEMORY)
	_own_prev.resize(_cap)
	_own_next.resize(_cap)
	_draw_buffer.resize(_cap * DRAW_STRIDE)
	_hostile_buffer.resize(_cap * DRAW_STRIDE)
	_alive.resize(_cap)
	_free_slots.resize(_cap)
	clear()
	if _draw_node != null:
		_draw_node.multimesh.instance_count = _cap
		_hostile_node.multimesh.instance_count = _cap


func get_cap() -> int:
	return _cap


## The area the projectiles live in. Also sizes the target grid.
func set_bounds(rect: Rect2) -> void:
	_bounds = rect
	_fit_draw_bounds()
	_grid_w = maxi(ceili(rect.size.x / GRID_CELL), 1)
	_grid_h = maxi(ceili(rect.size.y / GRID_CELL), 1)
	_cell_head.resize(_grid_w * _grid_h)
	_cell_head.fill(-1)
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


## How far along `from`->`to` (0 to 1) the path first enters a solid cell, or -1.0
## when it does not. Walks the cells the path crosses (Amanatides and Woo), at
## most |dx| + |dy| + 1 of them, in cells.
func _wall_hit(from: Vector2, to: Vector2) -> float:
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
	var visits: int = mini(full, MAX_WALL_VISITS)
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
	_hostile_node.multimesh.custom_aabb = aabb


## Remove every projectile (targets stay registered).
func clear() -> void:
	for slot in _high:
		if _alive[slot] != 0 and _tag[slot] != 0:
			shot_ended.emit(_tag[slot])
	_alive.fill(0)
	for i in _cap:
		_free_slots[i] = _cap - 1 - i
	_free_count = _cap
	_count = 0
	_high = 0
	_owned.fill(0)
	_own_head.fill(-1)
	_own_tail.fill(-1)
	# `drawn` stays: the next update_draw() must still empty the batch.


## Live projectiles.
func get_count() -> int:
	return _count


## Live projectiles owned by `player` (Events.NO_PLAYER for enemy shots).
func get_count_for(player: int) -> int:
	if player < EventsScript.NO_PLAYER or player >= MAX_PLAYERS:
		return 0
	return _owned[player + 1]


## Register a Node2D as something projectiles can hit (`layer` is a non-zero
## bit mask). Registering twice only updates the radius, layer and owner. A freed target is dropped by itself.
## `owner` is the player (0-3) the target belongs to, or Events.NO_PLAYER: shots of that
## player never hit it (matters with friendly fire). `offset` moves the hit circle from the
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
		_target_offset[at] = offset
		_max_target_radius = maxf(_max_target_radius, radius)
		return
	_targets.append(node)
	_target_id.append(id)
	_target_radius.append(radius)
	_target_layer.append(layer)
	_target_owner.append(owner)
	_target_pos.append(Vector2.ZERO)
	_target_offset.append(offset)
	_target_next.append(-1)
	_grid_stale = true
	_max_target_radius = maxf(_max_target_radius, radius)


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


## Start a projectile for `player` (0-3, or Events.NO_PLAYER for an enemy) at
## `origin`, moving `velocity` pixels per second for `lifetime` seconds.
## `pierce` is how many targets it passes through before it ends. Returns its
## slot, or -1 for bad arguments or an origin inside a wall.
## `motion` is MOTION_STRAIGHT or MOTION_STILL (then `velocity` is ignored).
## `tag` is stored and sent back with every hit of this projectile. A full cap never refuses: see the class doc.
func spawn(player: int, origin: Vector2, velocity: Vector2, lifetime: float, radius: float = 4.0, hit_layers: int = LAYER_ENEMY, pierce: int = 0, tag: int = 0, motion: int = MOTION_STRAIGHT) -> int:
	if motion != MOTION_STRAIGHT and motion != MOTION_STILL:
		return -1
	if player < EventsScript.NO_PLAYER or player >= MAX_PLAYERS:
		return -1
	if not (lifetime > 0.0) or not origin.is_finite() or not velocity.is_finite():
		return -1
	return _spawn_row(player, origin, velocity, lifetime, radius, hit_layers, pierce, tag, motion)


## Start a shot that circles `player`'s anchor (see `set_anchor`) at `orbit_radius`
## pixels, starting at `angle` (radians, 0 = east of the owner) and turning
## `angular_speed` radians a second (negative turns the other way). The other arguments
## are those of `spawn`. Returns its slot, or -1 for bad arguments, a player outside 0-3
## or a player with no anchor.
func spawn_orbit(player: int, orbit_radius: float, angle: float, angular_speed: float, lifetime: float, radius: float = 4.0, hit_layers: int = LAYER_ENEMY, pierce: int = 0, tag: int = 0) -> int:
	if player < 0 or player >= MAX_PLAYERS or not _anchors[player].is_finite():
		return -1
	if not (lifetime > 0.0) or not is_finite(orbit_radius) or not is_finite(angle) or not is_finite(angular_speed):
		return -1
	var offset: Vector2 = Vector2.from_angle(angle) * maxf(orbit_radius, 0.0)
	var slot: int = _spawn_row(player, _anchors[player] + offset, Vector2.ZERO, lifetime, radius, hit_layers, pierce, tag, MOTION_ORBIT)
	_orbit_radius[slot] = maxf(orbit_radius, 0.0)
	_orbit_angle[slot] = angle
	_orbit_speed[slot] = angular_speed
	_vel[slot] = _orbit_tangent(slot)
	return slot


## Tell the manager where `player`'s wizard is, for its orbit shots. Call it every physics
## step before the manager's (the owner of the wizard does).
func set_anchor(player: int, position: Vector2) -> void:
	if player >= 0 and player < MAX_PLAYERS and position.is_finite():
		_anchors[player] = position


## The wizard is gone: its orbit shots end at the next step, quietly.
func clear_anchor(player: int) -> void:
	if player >= 0 and player < MAX_PLAYERS:
		_anchors[player] = Vector2.INF


## Make the straight shot in `slot` home on targets, turning at most `turn_rate` radians
## a second. Returns false for an empty slot, a shot that is not straight, or a rate
## that is negative or not finite; true when the rate was applied, 0 included (0 stops
## homing).
func set_homing(slot: int, turn_rate: float) -> bool:
	if slot < 0 or slot >= _cap or _alive[slot] == 0 or _motion[slot] != MOTION_STRAIGHT:
		return false
	if not is_finite(turn_rate) or turn_rate < 0.0:
		return false
	_turn[slot] = turn_rate
	_home_at[slot] = Vector2.INF
	return true


func _spawn_row(player: int, origin: Vector2, velocity: Vector2, lifetime: float, radius: float, hit_layers: int, pierce: int, tag: int, motion: int) -> int:
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
	_life[slot] = lifetime
	_radius[slot] = maxf(radius, 0.0)
	_player[slot] = player
	_layers[slot] = (hit_layers | LAYER_PLAYER) if friendly_fire and player >= 0 else hit_layers
	_pierce[slot] = maxi(pierce, 0)
	_tag[slot] = tag
	_seq[slot] = _next_seq
	_next_seq += 1
	_skip_left[slot] = 0.0
	for i in HIT_MEMORY:
		_last_hit[slot * HIT_MEMORY + i] = 0
	_alive[slot] = 1
	_count += 1
	var owner_index: int = player + 1
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
func step(delta: float) -> void:
	_refresh_targets()
	var top: int = _high
	var first_new: int = _next_seq
	var limit: Rect2 = _bounds.grow(BOUNDS_MARGIN)
	_stepping = true
	_work_left = WORK_PER_STEP
	var resume: int = _resume if _resume < top else 0
	var starved_at: int = -1
	for n in top:
		var slot: int = n + resume
		if slot >= top:
			slot -= top
		# A hit handler may have dropped or reused this slot; a projectile
		# spawned during this step waits for the next one.
		if _alive[slot] == 0 or _seq[slot] >= first_new:
			continue
		_life[slot] -= delta
		_skip_left[slot] -= delta
		if _life[slot] <= 0.0:
			_expire(slot)
			continue
		_prev[slot] = _pos[slot]
		var orbiting: bool = _motion[slot] == MOTION_ORBIT
		if orbiting:
			if not _anchors[_player[slot]].is_finite():
				_kill(slot)
				continue
			_orbit_move(slot, delta)
		else:
			if _turn[slot] > 0.0:
				_steer(slot, delta)
			_pos[slot] += _vel[slot] * delta
		if not limit.has_point(_pos[slot]):
			_kill(slot)
			continue
		# A shot that meets a wall is cut short there: it can still hit what is
		# in front of the wall, then it ends. An orbit shot ignores walls.
		var walled: bool = false
		if _has_walls and not orbiting:
			var cut: float = _wall_hit(_prev[slot], _pos[slot])
			if cut >= 0.0:
				walled = true
				_pos[slot] = _prev[slot].lerp(_pos[slot], cut)
		if _layers[slot] != 0 and not _targets.is_empty():
			if _work_left <= 0:
				if walled:
					wall_hits += 1
					_emit_wall_impact(_player[slot], _pos[slot], _vel[slot])
					_expire(slot)
				elif starved_at < 0:
					starved_at = slot
				continue
			# A piercing shot may pass through several targets this step. A
			# hit handler may end it or even reuse the slot, so check each time.
			var seq: int = _seq[slot]
			for _hit in HIT_MEMORY:
				if not _hit_test(slot) or _alive[slot] == 0 or _seq[slot] != seq:
					break
		if walled and _alive[slot] != 0:
			wall_hits += 1
			_emit_wall_impact(_player[slot], _pos[slot], _vel[slot])
			_expire(slot)
	_resume = maxi(starved_at, 0)
	_step_index += 1
	_stepping = false


## Advance an orbit shot: turn its angle and place it round the anchor.
func _orbit_move(slot: int, delta: float) -> void:
	_orbit_angle[slot] = wrapf(_orbit_angle[slot] + _orbit_speed[slot] * delta, -PI, PI)
	_pos[slot] = _anchors[_player[slot]] + Vector2.from_angle(_orbit_angle[slot]) * _orbit_radius[slot]
	_vel[slot] = _orbit_tangent(slot)


func _orbit_tangent(slot: int) -> Vector2:
	var away: Vector2 = Vector2.from_angle(_orbit_angle[slot])
	return Vector2(-away.y, away.x) * (_orbit_radius[slot] * _orbit_speed[slot])


## Turn a homing shot toward the point it last found, and look for a new one when it is
## this shot's turn (and there is hit work left).
func _steer(slot: int, delta: float) -> void:
	if ((slot + _step_index) % HOMING_PERIOD) == 0 and _work_left > 0:
		_home_at[slot] = _homing_point(slot)
	var goal: Vector2 = _home_at[slot]
	var velocity: Vector2 = _vel[slot]
	if not goal.is_finite() or velocity.is_zero_approx():
		return
	var want: Vector2 = goal - _pos[slot]
	if want.is_zero_approx():
		return
	var most: float = _turn[slot] * delta
	_vel[slot] = velocity.rotated(clampf(velocity.angle_to(want), -most, most))


## The centre of the nearest target within HOMING_RANGE of a shot that it may home on
## (not its shooter's body, not one it just hit), or INF. Charges the work budget.
func _homing_point(slot: int) -> Vector2:
	var point: Vector2 = _pos[slot]
	# Homing never picks a wizard, even with friendly fire on.
	var layers: int = _layers[slot] & ~LAYER_PLAYER
	var shooter: int = _player[slot]
	var best: int = -1
	var best_sq: float = INF
	var cells: Vector4i = _query_cells(point, HOMING_RANGE)
	for y in range(cells.y, cells.w + 1):
		for x in range(cells.x, cells.z + 1):
			var t: int = _cell_head[y * _grid_w + x]
			while t >= 0:
				_work_left -= 1
				if (_target_layer[t] & layers) != 0 and (shooter < 0 or _target_owner[t] != shooter) and not _remembers(slot, _target_id[t]) and is_instance_valid(_targets[t]):
					var reach: float = HOMING_RANGE + _target_radius[t]
					var d: float = _target_pos[t].distance_squared_to(point)
					if d <= reach * reach and d < best_sq:
						best_sq = d
						best = t
				t = _target_next[t]
	return _target_pos[best] if best >= 0 else Vector2.INF


## For a beam, which cannot turn: `direction` (a unit vector) bent toward the nearest
## target on `layers` within HOMING_RANGE of `origin` whose centre lies within
## `max_angle` radians of it, or `direction` unchanged when there is none. Targets
## owned by `player` are skipped, and so are wizards (LAYER_PLAYER). Allocation-free.
func homing_aim(player: int, origin: Vector2, direction: Vector2, max_angle: float, layers: int) -> Vector2:
	if not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx() or not is_finite(max_angle):
		return direction
	_query_ready()
	layers &= ~LAYER_PLAYER
	var best: int = -1
	var best_sq: float = INF
	var cells: Vector4i = _query_cells(origin, HOMING_RANGE)
	for y in range(cells.y, cells.w + 1):
		for x in range(cells.x, cells.z + 1):
			var t: int = _cell_head[y * _grid_w + x]
			while t >= 0:
				if (_target_layer[t] & layers) != 0 and (player < 0 or _target_owner[t] != player) and is_instance_valid(_targets[t]):
					var to_target: Vector2 = _target_pos[t] - origin
					var reach: float = HOMING_RANGE + _target_radius[t]
					var d: float = to_target.length_squared()
					if d <= reach * reach and d < best_sq and not to_target.is_zero_approx() and absf(direction.angle_to(to_target)) <= max_angle:
						best_sq = d
						best = t
				t = _target_next[t]
	if best < 0:
		return direction
	return origin.direction_to(_target_pos[best])


## An instant beam from `origin` along `direction` for up to `length` pixels, fired by
## `player`. It holds no row in the pool. It stops at the first wall and hits the
## nearest `pierce + 1` targets on `layers` (at most RAY_MAX_HITS) whose circle the beam
## touches (`width` pixels either side of the line; `exclude` is a target it never hits,
## for a beam that starts on the one that fired it). For each, nearest first, it sends
## `projectile_impact` and `projectile_hit(player, target, point, tag)`, the point being
## where the beam passes closest to the target; a beam that ends on a wall sends an
## impact with a `null` target there. Targets owned by `player` are skipped and, as in
## `spawn`, friendly fire adds LAYER_PLAYER. Returns how far the beam got in pixels: the
## length, the distance to the wall, or the distance to the last target it could hit.
## 0.0 for bad arguments or an origin inside a wall. The hits are found before any event
## is sent, so a handler may remove or free targets, or fire another ray (up to
## RAY_MAX_DEPTH deep, a deeper one returns 0.0). A `length` over RAY_MAX_LENGTH is cut
## to it. Allocation-free.
func ray(player: int, origin: Vector2, direction: Vector2, length: float, pierce: int = 0, layers: int = LAYER_ENEMY, tag: int = 0, width: float = 0.0, exclude: Node = null) -> float:
	if player < EventsScript.NO_PLAYER or player >= MAX_PLAYERS:
		return 0.0
	if not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx() or not is_finite(length) or length <= 0.0:
		return 0.0
	if _ray_depth >= RAY_MAX_DEPTH:
		return 0.0
	length = minf(length, RAY_MAX_LENGTH)
	var base: int = _ray_depth * RAY_MAX_HITS
	var heading: Vector2 = direction.normalized()
	var reach: float = length
	var walled: bool = false
	if _has_walls:
		var cut: float = _wall_hit(origin, origin + heading * length)
		if cut >= 0.0:
			walled = true
			reach = length * cut
	var end: Vector2 = origin + heading * reach
	var wanted: int = mini(maxi(pierce, 0) + 1, RAY_MAX_HITS)
	var found: int = 0
	var skip: int = exclude.get_instance_id() if exclude != null else 0
	if not _targets.is_empty():
		_query_ready()
		if friendly_fire and player >= 0:
			layers |= LAYER_PLAYER
		var wide: float = maxf(width, 0.0)
		var pad: Vector2 = Vector2.ONE * (wide + _max_target_radius)
		var low: Vector2 = origin.min(end) - pad
		var high: Vector2 = origin.max(end) + pad
		var x0: int = clampi(floori((low.x - _bounds.position.x) / GRID_CELL), 0, _grid_w - 1)
		var x1: int = clampi(floori((high.x - _bounds.position.x) / GRID_CELL), 0, _grid_w - 1)
		var y0: int = clampi(floori((low.y - _bounds.position.y) / GRID_CELL), 0, _grid_h - 1)
		var y1: int = clampi(floori((high.y - _bounds.position.y) / GRID_CELL), 0, _grid_h - 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var t: int = _cell_head[y * _grid_w + x]
				while t >= 0:
					if (_target_layer[t] & layers) != 0 and (player < 0 or _target_owner[t] != player) and _target_id[t] != skip and is_instance_valid(_targets[t]):
						var along: float = clampf((_target_pos[t] - origin).dot(heading), 0.0, reach)
						var closest: Vector2 = origin + heading * along
						var touch: float = wide + _target_radius[t]
						if closest.distance_squared_to(_target_pos[t]) <= touch * touch:
							found = _ray_keep(base, found, wanted, t, along, closest)
					t = _target_next[t]
	var got: float = reach
	if found > 0 and found == maxi(pierce, 0) + 1:
		# The beam is spent on its last target.
		got = _ray_along[base + found - 1]
		walled = false
	_ray_depth += 1
	var outer_slot: int = event_slot
	event_slot = -1
	for i in found:
		var node: Variant = _ray_nodes[base + i]
		if events != null and is_instance_valid(node):
			events.projectile_impact.emit(player, node, _ray_points[base + i], heading)
			events.projectile_hit.emit(player, node, _ray_points[base + i], tag)
		_ray_nodes[base + i] = null
	_ray_depth -= 1
	event_slot = outer_slot
	if walled and events != null:
		events.projectile_impact.emit(player, null, origin + heading * got, heading)
	return got


## Put target `t` (at `along` pixels, nearest point `closest`) into the sorted scratch of
## the best hits if it is among the `wanted` nearest; returns the new count.
func _ray_keep(base: int, found: int, wanted: int, t: int, along: float, closest: Vector2) -> int:
	if found == wanted and along >= _ray_along[base + found - 1]:
		return found
	var at: int = mini(found, wanted - 1)
	while at > 0 and _ray_along[base + at - 1] > along:
		_ray_along[base + at] = _ray_along[base + at - 1]
		_ray_points[base + at] = _ray_points[base + at - 1]
		_ray_nodes[base + at] = _ray_nodes[base + at - 1]
		at -= 1
	_ray_along[base + at] = along
	_ray_points[base + at] = closest
	_ray_nodes[base + at] = _targets[t]
	return mini(found + 1, wanted)


## Copy the live projectiles into the one batched draw (a single buffer write).
## Called every frame. Positions are interpolated between physics steps, so
## shots stay smooth on screens faster than the physics rate. Does nothing
## while there are no projectiles.
func update_draw() -> void:
	if _draw_node == null:
		drawn = 0
		return
	if _high == 0 and drawn == 0:
		return
	var multimesh: MultiMesh = _draw_node.multimesh
	var hostile_multimesh: MultiMesh = _hostile_node.multimesh
	var fraction: float = clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var out: int = 0
	var hostile_out: int = 0
	for slot in _high:
		if _alive[slot] == 0:
			continue
		var diameter: float = maxf(_radius[slot] * 2.0, 1.0) * DRAW_SCALE
		var dir: Vector2 = Vector2.RIGHT
		if _vel[slot].length_squared() > 0.0:
			dir = _vel[slot].normalized()
		var at: Vector2 = _prev[slot].lerp(_pos[slot], fraction)
		if _player[slot] < 0:
			_write_quad(_hostile_buffer, hostile_out * DRAW_STRIDE, dir, diameter, at, Color.WHITE)
			hostile_out += 1
		else:
			_write_quad(_draw_buffer, out * DRAW_STRIDE, dir, diameter, at, _color_of(_player[slot]))
			out += 1
	if out > 0:
		multimesh.buffer = _draw_buffer
	multimesh.visible_instance_count = out
	if hostile_out > 0:
		hostile_multimesh.buffer = _hostile_buffer
	hostile_multimesh.visible_instance_count = hostile_out
	drawn_hostile = hostile_out
	drawn = out + hostile_out


## Write one quad at float index `i` of `buffer` (packed arrays are shared, not copied):
## Transform2D(dir * d, dir.orthogonal() * d, at), row by row, then the colour.
func _write_quad(buffer: PackedFloat32Array, i: int, dir: Vector2, diameter: float, at: Vector2, color: Color) -> void:
	buffer[i] = dir.x * diameter
	buffer[i + 1] = dir.y * diameter
	buffer[i + 2] = 0.0
	buffer[i + 3] = at.x
	buffer[i + 4] = dir.y * diameter
	buffer[i + 5] = -dir.x * diameter
	buffer[i + 6] = 0.0
	buffer[i + 7] = at.y
	buffer[i + 8] = color.r
	buffer[i + 9] = color.g
	buffer[i + 10] = color.b
	buffer[i + 11] = color.a


## Position of a live projectile, or Vector2.INF if the slot is empty.
func get_position_of(slot: int) -> Vector2:
	if slot < 0 or slot >= _cap or _alive[slot] == 0:
		return Vector2.INF
	return _pos[slot]


func is_alive(slot: int) -> bool:
	return slot >= 0 and slot < _cap and _alive[slot] != 0


func _color_of(player: int) -> Color:
	if player < 0:
		return Color.WHITE.lerp(ENEMY_COLOR, TINT_STRENGTH)
	return Color.WHITE.lerp(PLAYER_COLORS[player], TINT_STRENGTH)


func _kill(slot: int, announce: bool = true) -> void:
	if announce and _tag[slot] != 0:
		shot_ended.emit(_tag[slot])
	_alive[slot] = 0
	_free_slots[_free_count] = slot
	_free_count += 1
	_count -= 1
	var owner_index: int = _player[slot] + 1
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
	var player: int = _player[slot]
	var at: Vector2 = _pos[slot]
	var tag: int = _tag[slot]
	_kill(slot, false)
	if events != null:
		event_slot = slot
		events.projectile_expired.emit(player, at, tag)
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


## Keep the shot in `slot` from hitting `node` for `seconds` (a held spell must not hit the
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


## Where `player`'s anchor is (see `set_anchor`), or `Vector2.INF` when it has none.
func get_anchor(player: int) -> Vector2:
	return _anchors[player] if player >= 0 and player < MAX_PLAYERS else Vector2.INF


## Where the target `nearest_target` last returned is (its hit circle's centre).
var nearest_point: Vector2 = Vector2.INF


## Make room: drop the oldest projectile of the owner with the most.
func _drop_one() -> void:
	var richest: int = 0
	for i in range(1, _owned.size()):
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
	_target_pos[at] = _target_pos[last]
	_target_offset[at] = _target_offset[last]
	_targets.resize(last)
	_target_id.resize(last)
	_target_radius.resize(last)
	_target_layer.resize(last)
	_target_owner.resize(last)
	_target_pos.resize(last)
	_target_offset.resize(last)
	_target_next.resize(last)


## Drop freed targets, read the positions of the rest and fill the grid.
func _refresh_targets() -> void:
	if _targets.is_empty():
		_cell_head.fill(-1)
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
	_grid_stale = false
	for i in _targets.size():
		var node: Node2D = _targets[i]
		_target_next[i] = -1
		if not node.is_inside_tree():
			_target_pos[i] = Vector2.INF
			continue
		_target_pos[i] = node.global_position + _target_offset[i]
		var cell: int = _cell_of(_target_pos[i])
		_target_next[i] = _cell_head[cell]
		_cell_head[cell] = i


## The nearest target on `layers` whose hit circle overlaps the circle (`point`,
## `radius`), by distance to its centre, or null. `exclude` is skipped (the target
## just hit, for a chain) and so is `exclude_also`. The hit circle's centre of the target
## returned is left in `nearest_point`. Allocation-free.
func nearest_target(point: Vector2, radius: float, layers: int, exclude: Node2D = null, exclude_also: Node2D = null) -> Node2D:
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
				if _query_match(t, point, radius, layers, skip) and (skip_also == 0 or _target_id[t] != skip_also):
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


func _cell_of(point: Vector2) -> int:
	var cx: int = clampi(floori((point.x - _bounds.position.x) / GRID_CELL), 0, _grid_w - 1)
	var cy: int = clampi(floori((point.y - _bounds.position.y) / GRID_CELL), 0, _grid_h - 1)
	return cy * _grid_w + cx


## Hit the first target along this step's path (nearest its start) and say
## whether there was one. The cells searched are those the path touches,
## widened by both radii.
func _hit_test(slot: int) -> bool:
	var from: Vector2 = _prev[slot]
	var to: Vector2 = _pos[slot]
	var pad: Vector2 = Vector2.ONE * (_radius[slot] + _max_target_radius)
	var low: Vector2 = from.min(to) - pad
	var high: Vector2 = from.max(to) + pad
	var x0: int = clampi(floori((low.x - _bounds.position.x) / GRID_CELL), 0, _grid_w - 1)
	var x1: int = clampi(floori((high.x - _bounds.position.x) / GRID_CELL), 0, _grid_w - 1)
	var y0: int = clampi(floori((low.y - _bounds.position.y) / GRID_CELL), 0, _grid_h - 1)
	var y1: int = clampi(floori((high.y - _bounds.position.y) / GRID_CELL), 0, _grid_h - 1)
	var path: Vector2 = to - from
	var path_sq: float = path.length_squared()
	var best: int = -1
	var best_along: float = 0.0
	var best_point: Vector2 = to
	var layers: int = _layers[slot]
	var shooter: int = _player[slot]
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var t: int = _cell_head[y * _grid_w + x]
			while t >= 0:
				var next_target: int = _target_next[t]
				_work_left -= 1
				# Skip other layers, the shooter's own body, and targets already hit.
				if (_target_layer[t] & layers) == 0 or (shooter >= 0 and _target_owner[t] == shooter) or _remembers(slot, _target_id[t]) or (_skip_left[slot] > 0.0 and _skip_id[slot] == _target_id[t]):
					t = next_target
					continue
				var along: float = 0.0
				if path_sq > 0.0:
					along = clampf((_target_pos[t] - from).dot(path) / path_sq, 0.0, 1.0)
				var closest: Vector2 = from + path * along
				var reach: float = _radius[slot] + _target_radius[t]
				if closest.distance_squared_to(_target_pos[t]) <= reach * reach and (best < 0 or along < best_along):
					best = t
					best_along = along
					best_point = closest
				t = next_target
	if best < 0:
		return false
	_work_left -= HIT_WORK
	_register_hit(slot, best, best_point)
	return true


func _remembers(slot: int, id: int) -> bool:
	for i in HIT_MEMORY:
		if _last_hit[slot * HIT_MEMORY + i] == id:
			return true
	return false


## Tell listeners a shot ended on a wall at `at`, flying along `velocity`.
func _emit_wall_impact(player: int, at: Vector2, velocity: Vector2) -> void:
	if events != null and not velocity.is_zero_approx():
		events.projectile_impact.emit(player, null, at, velocity.normalized())


func _register_hit(slot: int, target: int, at: Vector2) -> void:
	var node: Variant = _targets[target]
	var player: int = _player[slot]
	var tag: int = _tag[slot]
	var heading: Vector2 = _vel[slot].normalized()
	if heading == Vector2.ZERO:
		# A still shot has no heading: point from the shot to the target instead.
		heading = at.direction_to(_target_pos[target])
		if heading == Vector2.ZERO:
			heading = Vector2.RIGHT
	var spent: bool = false
	if _pierce[slot] > 0:
		_pierce[slot] -= 1
		var memory: int = slot * HIT_MEMORY
		for i in range(HIT_MEMORY - 1, 0, -1):
			_last_hit[memory + i] = _last_hit[memory + i - 1]
		_last_hit[memory] = _target_id[target]
	else:
		spent = true
		_kill(slot, false)
	if events != null and is_instance_valid(node):
		events.projectile_impact.emit(player, node, at, heading)
		event_slot = slot
		events.projectile_hit.emit(player, node, at, tag)
		event_slot = -1
	if spent and tag != 0:
		shot_ended.emit(tag)
