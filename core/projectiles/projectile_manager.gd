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
## `Events.projectile_hit(player, target, position)`; the projectile then ends,
## unless it has `pierce` left, and `combat` turns the event into damage. The
## manager knows nothing about damage, spells or gameplay.
##
## Hits are found with a spatial grid of the targets (cells of GRID_CELL
## pixels, each target in the cell of its centre). The path a projectile covered
## this step is checked as a segment, and the cells searched are those the
## segment touches, widened by the projectile's radius and the largest target
## radius registered. So fast shots and big targets (bosses) are both found, at
## any speed; the cost only grows with the length of the step. When a segment
## touches several targets, the one nearest the start of the path is hit first,
## and the event carries the point on the path closest to it. A piercing
## projectile remembers its last HIT_MEMORY targets and does not hit them again
## while it is still overlapping them.
##
## The global cap (`get_cap()`, set by platform: DEFAULT_CAP_WEB or
## DEFAULT_CAP_DESKTOP) degrades gracefully. When it is full, a new projectile
## is never refused: the oldest projectile of whoever owns the most of them is
## dropped (in constant time: each owner's projectiles are a list in spawn
## order). Nobody is starved, and a player who floods the screen only loses
## their own old shots. `dropped` counts these. Spell limits (projectiles per
## cast, trigger depth) keep the cap from being reached often.
##
## Nothing here allocates per frame: the arrays are sized when the cap is set,
## and the grid is reused. Coordinates are world coordinates (the manager sits
## at the origin). A handler of `projectile_hit` may spawn more projectiles;
## those start moving on the next step. Tests call `step()` directly.

const EventsScript := preload("res://core/events/events.gd")

const MAX_PLAYERS: int = 4
## Default global caps on live projectiles: the PLAN budgets for each platform.
const DEFAULT_CAP_WEB: int = 1000
const DEFAULT_CAP_DESKTOP: int = 3000
## How many recently hit targets a piercing projectile remembers.
const HIT_MEMORY: int = 3
## Floats per projectile in the MultiMesh buffer: 8 transform, 4 colour.
const DRAW_STRIDE: int = 12
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
		if _draw_node != null:
			_draw_node.texture = value
var events: EventsScript = null
## How many projectiles were dropped because the cap was full, since start.
var dropped: int = 0
## Projectiles written into the batch by the last update_draw().
var drawn: int = 0

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
var _target_id: PackedInt64Array = PackedInt64Array()
## The grid: first target in each cell (-1 for none), and the next in its chain.
var _grid_w: int = 1
var _grid_h: int = 1
var _cell_head: PackedInt32Array = PackedInt32Array()
var _target_next: PackedInt32Array = PackedInt32Array()
## The largest radius of any registered target; sets how far hits are searched.
var _max_target_radius: float = 0.0

var _draw_node: MultiMeshInstance2D = null
var _draw_buffer: PackedFloat32Array = PackedFloat32Array()
## True inside step(): the grid is in use, so a target removed then is only
## switched off (layer 0) and swept at the start of the next step.
var _stepping: bool = false


func _init() -> void:
	set_cap(DEFAULT_CAP_WEB if OS.has_feature("web") else DEFAULT_CAP_DESKTOP)
	set_bounds(_bounds)


func _ready() -> void:
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	_draw_node = MultiMeshInstance2D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = _cap
	multimesh.visible_instance_count = 0
	_draw_node.multimesh = multimesh
	_draw_node.texture = texture
	add_child(_draw_node)


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
	_seq.resize(_cap)
	_last_hit.resize(_cap * HIT_MEMORY)
	_own_prev.resize(_cap)
	_own_next.resize(_cap)
	_draw_buffer.resize(_cap * DRAW_STRIDE)
	_alive.resize(_cap)
	_free_slots.resize(_cap)
	clear()
	if _draw_node != null:
		_draw_node.multimesh.instance_count = _cap


func get_cap() -> int:
	return _cap


## The area the projectiles live in. Also sizes the target grid.
func set_bounds(rect: Rect2) -> void:
	_bounds = rect
	_grid_w = maxi(ceili(rect.size.x / GRID_CELL), 1)
	_grid_h = maxi(ceili(rect.size.y / GRID_CELL), 1)
	_cell_head.resize(_grid_w * _grid_h)


## Remove every projectile (targets stay registered).
func clear() -> void:
	_alive.fill(0)
	for i in _cap:
		_free_slots[i] = _cap - 1 - i
	_free_count = _cap
	_count = 0
	_high = 0
	_owned.fill(0)
	_own_head.fill(-1)
	_own_tail.fill(-1)
	drawn = 0


## Live projectiles.
func get_count() -> int:
	return _count


## Live projectiles owned by `player` (Events.NO_PLAYER for enemy shots).
func get_count_for(player: int) -> int:
	if player < EventsScript.NO_PLAYER or player >= MAX_PLAYERS:
		return 0
	return _owned[player + 1]


## Register a Node2D as something projectiles can hit (`layer` is a non-zero
## bit mask). Registering twice only updates the radius and layer. A freed target is dropped by itself.
func add_target(node: Node2D, radius: float, layer: int = LAYER_ENEMY) -> void:
	if node == null or layer == 0:
		return
	var id: int = node.get_instance_id()
	var at: int = _target_id.find(id)
	if at >= 0:
		_target_radius[at] = radius
		_target_layer[at] = layer
		_max_target_radius = maxf(_max_target_radius, radius)
		return
	_targets.append(node)
	_target_id.append(id)
	_target_radius.append(radius)
	_target_layer.append(layer)
	_target_pos.append(Vector2.ZERO)
	_target_next.append(-1)
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


func get_target_count() -> int:
	return _targets.size()


## Start a projectile for `player` (0-3, or Events.NO_PLAYER for an enemy) at
## `position`, moving `velocity` pixels per second for `lifetime` seconds.
## `pierce` is how many targets it passes through before it ends. Returns its
## slot, or -1 for bad arguments. A full cap never refuses: see the class doc.
func spawn(player: int, position: Vector2, velocity: Vector2, lifetime: float, radius: float = 4.0, hit_layers: int = LAYER_ENEMY, pierce: int = 0) -> int:
	if player < EventsScript.NO_PLAYER or player >= MAX_PLAYERS:
		return -1
	if not (lifetime > 0.0) or not position.is_finite() or not velocity.is_finite():
		return -1
	if _free_count == 0:
		_drop_one()
	_free_count -= 1
	var slot: int = _free_slots[_free_count]
	_pos[slot] = position
	_prev[slot] = position
	_vel[slot] = velocity
	_life[slot] = lifetime
	_radius[slot] = maxf(radius, 0.0)
	_player[slot] = player
	_layers[slot] = hit_layers
	_pierce[slot] = maxi(pierce, 0)
	_seq[slot] = _next_seq
	_next_seq += 1
	for i in HIT_MEMORY:
		_last_hit[slot * HIT_MEMORY + i] = 0
	_alive[slot] = 1
	_count += 1
	var owner: int = player + 1
	_owned[owner] += 1
	_own_prev[slot] = _own_tail[owner]
	_own_next[slot] = -1
	if _own_tail[owner] >= 0:
		_own_next[_own_tail[owner]] = slot
	else:
		_own_head[owner] = slot
	_own_tail[owner] = slot
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
	for slot in top:
		# A hit handler may have dropped or reused this slot; a projectile
		# spawned during this step waits for the next one.
		if _alive[slot] == 0 or _seq[slot] >= first_new:
			continue
		_life[slot] -= delta
		if _life[slot] <= 0.0:
			_kill(slot)
			continue
		_prev[slot] = _pos[slot]
		_pos[slot] += _vel[slot] * delta
		if not limit.has_point(_pos[slot]):
			_kill(slot)
			continue
		if _layers[slot] != 0 and not _targets.is_empty():
			_hit_test(slot)
	_stepping = false


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
	var fraction: float = clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var out: int = 0
	for slot in _high:
		if _alive[slot] == 0:
			continue
		var diameter: float = maxf(_radius[slot] * 2.0, 1.0)
		var dir: Vector2 = Vector2.RIGHT
		if _vel[slot].length_squared() > 0.0:
			dir = _vel[slot].normalized()
		var at: Vector2 = _prev[slot].lerp(_pos[slot], fraction)
		var color: Color = _color_of(_player[slot])
		# Transform2D(dir * d, dir.orthogonal() * d, at), row by row, then the colour.
		var i: int = out * DRAW_STRIDE
		_draw_buffer[i] = dir.x * diameter
		_draw_buffer[i + 1] = dir.y * diameter
		_draw_buffer[i + 2] = 0.0
		_draw_buffer[i + 3] = at.x
		_draw_buffer[i + 4] = dir.y * diameter
		_draw_buffer[i + 5] = -dir.x * diameter
		_draw_buffer[i + 6] = 0.0
		_draw_buffer[i + 7] = at.y
		_draw_buffer[i + 8] = color.r
		_draw_buffer[i + 9] = color.g
		_draw_buffer[i + 10] = color.b
		_draw_buffer[i + 11] = color.a
		out += 1
	if out > 0:
		multimesh.buffer = _draw_buffer
	multimesh.visible_instance_count = out
	drawn = out


## Position of a live projectile, or Vector2.INF if the slot is empty.
func get_position_of(slot: int) -> Vector2:
	if slot < 0 or slot >= _cap or _alive[slot] == 0:
		return Vector2.INF
	return _pos[slot]


func is_alive(slot: int) -> bool:
	return slot >= 0 and slot < _cap and _alive[slot] != 0


func _color_of(player: int) -> Color:
	if player < 0:
		return ENEMY_COLOR
	return PLAYER_COLORS[player]


func _kill(slot: int) -> void:
	_alive[slot] = 0
	_free_slots[_free_count] = slot
	_free_count += 1
	_count -= 1
	var owner: int = _player[slot] + 1
	_owned[owner] -= 1
	var before: int = _own_prev[slot]
	var after: int = _own_next[slot]
	if before >= 0:
		_own_next[before] = after
	else:
		_own_head[owner] = after
	if after >= 0:
		_own_prev[after] = before
	else:
		_own_tail[owner] = before
	while _high > 0 and _alive[_high - 1] == 0:
		_high -= 1


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
	_target_pos[at] = _target_pos[last]
	_targets.resize(last)
	_target_id.resize(last)
	_target_radius.resize(last)
	_target_layer.resize(last)
	_target_pos.resize(last)
	_target_next.resize(last)


## Drop freed targets, read the positions of the rest and fill the grid.
func _refresh_targets() -> void:
	if _targets.is_empty():
		return
	var at: int = 0
	while at < _targets.size():
		var node: Variant = _targets[at]
		if not is_instance_valid(node) or _target_layer[at] == 0:
			_remove_target_at(at)
			continue
		at += 1
	_cell_head.fill(-1)
	for i in _targets.size():
		var node: Node2D = _targets[i]
		_target_next[i] = -1
		if not node.is_inside_tree():
			_target_pos[i] = Vector2.INF
			continue
		_target_pos[i] = node.global_position
		var cell: int = _cell_of(_target_pos[i])
		_target_next[i] = _cell_head[cell]
		_cell_head[cell] = i


func _cell_of(point: Vector2) -> int:
	var cx: int = clampi(floori((point.x - _bounds.position.x) / GRID_CELL), 0, _grid_w - 1)
	var cy: int = clampi(floori((point.y - _bounds.position.y) / GRID_CELL), 0, _grid_h - 1)
	return cy * _grid_w + cx


## Hit the first target along this step's path (nearest its start). The cells
## searched are those the path touches, widened by both radii.
func _hit_test(slot: int) -> void:
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
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var t: int = _cell_head[y * _grid_w + x]
			while t >= 0:
				if (_target_layer[t] & _layers[slot]) != 0 and not _remembers(slot, _target_id[t]):
					var along: float = 0.0
					if path_sq > 0.0:
						along = clampf((_target_pos[t] - from).dot(path) / path_sq, 0.0, 1.0)
					var closest: Vector2 = from + path * along
					var reach: float = _radius[slot] + _target_radius[t]
					if closest.distance_squared_to(_target_pos[t]) <= reach * reach and (best < 0 or along < best_along):
						best = t
						best_along = along
						best_point = closest
				t = _target_next[t]
	if best >= 0:
		_register_hit(slot, best, best_point)


func _remembers(slot: int, id: int) -> bool:
	for i in HIT_MEMORY:
		if _last_hit[slot * HIT_MEMORY + i] == id:
			return true
	return false


func _register_hit(slot: int, target: int, at: Vector2) -> void:
	var node: Variant = _targets[target]
	var player: int = _player[slot]
	if _pierce[slot] > 0:
		_pierce[slot] -= 1
		var memory: int = slot * HIT_MEMORY
		for i in range(HIT_MEMORY - 1, 0, -1):
			_last_hit[memory + i] = _last_hit[memory + i - 1]
		_last_hit[memory] = _target_id[target]
	else:
		_kill(slot)
	if events != null and is_instance_valid(node):
		events.projectile_hit.emit(player, node, at)
