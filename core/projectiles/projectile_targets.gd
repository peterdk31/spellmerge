class_name ProjectileTargets
extends Object
## The projectile manager's targets (core/projectiles/projectile_manager.gd, the header and "Queries"):
## bodies registered with a hit shape, a layer and an owner, their grid of cells refreshed each step,
## and the asks over it (`nearest_target`, `targets_in`, `targets_near`). Static functions of the
## manager (`pm`), whose members hold all of it.

const Manager := preload("res://core/projectiles/projectile_manager.gd")

## Not state (core/sim/README.md): the manager, the other jobs this one calls and the manager's
## arrays it works on, each the manager's own array (shared, never a copy), linked by `link`.
const DERIVED: Array[StringName] = [&"pm", &"_pos", &"_radius", &"_actor", &"_shot_head", &"_shot_next", &"_alive", &"_targets", &"_target_radius", &"_target_half", &"_target_layer", &"_target_pos", &"_target_offset", &"_target_id", &"_target_key", &"_target_owner", &"_target_team", &"_cell_head", &"_world_rows", &"_cell_count", &"_cell_box", &"_cell_filled", &"_target_next", &"_skip_id", &"_skip_on", &"_skip_near"]

var pm: Manager = null
var _pos: PackedVector2Array
var _radius: PackedFloat32Array
var _actor: PackedInt32Array
var _shot_head: PackedInt32Array
var _shot_next: PackedInt32Array
var _alive: PackedByteArray
var _targets: Array
var _target_radius: PackedFloat32Array
var _target_half: PackedVector2Array
var _target_layer: PackedInt32Array
var _target_pos: PackedVector2Array
var _target_offset: PackedVector2Array
var _target_id: PackedInt64Array
var _target_key: PackedInt64Array
var _target_owner: PackedInt32Array
var _target_team: PackedInt32Array
var _cell_head: PackedInt32Array
var _world_rows: PackedInt32Array
var _cell_count: PackedInt32Array
var _cell_box: PackedVector4Array
var _cell_filled: PackedInt32Array
var _target_next: PackedInt32Array
var _skip_id: PackedInt64Array
var _skip_on: PackedFloat32Array
var _skip_near: PackedFloat32Array


## Takes the manager's arrays and jobs, by the names in DERIVED: again whenever the manager's arrays
## may have been replaced (`ProjectileManager._link_jobs`).
func link(manager: Manager) -> void:
	pm = manager
	for name: StringName in DERIVED:
		if name != &"pm":
			set(name, manager.get(name))


## After a restore: the target grid's chains linked again from the targets' places as the last
## filling read them (`_target_pos`, state; a target out of the tree then is in no chain), in the
## order `_refresh_targets` links them, so a query before the next filling finds what the machine
## that took the snapshot found. The cells' counts and boxes are taken again when first needed, and
## the shots' grid at its next use.
func _relink_targets() -> void:
	var cells: int = pm._grid_w * pm._grid_h
	_cell_head.resize(cells)
	_cell_head.fill(-1)
	_cell_count.resize(cells)
	_cell_count.fill(0)
	_cell_box.resize(cells)
	_cell_filled.resize(cells)
	_cell_filled.fill(-1)
	_shot_head.resize(cells)
	_shot_head.fill(-1)
	_shot_next.resize(pm._cap)
	pm._shot_reach = 0.0
	pm._scan_step = -1
	var rows: int = _target_pos.size()
	_target_next.resize(rows)
	for i in rows:
		var centre: Vector2 = _target_pos[i]
		if not centre.is_finite():
			_target_next[i] = -1
			continue
		var cell: int = clampi(floori((centre.y - pm._grid_y) / Manager.GRID_CELL), 0, pm._grid_h - 1) * pm._grid_w + clampi(floori((centre.x - pm._grid_x) / Manager.GRID_CELL), 0, pm._grid_w - 1)
		_target_next[i] = _cell_head[cell]
		_cell_head[cell] = i


## The team a target aims as: its owner actor's. A target no actor owns (until actors G6 every
## enemy that casts nothing, and the dummies) is on the team of its layer's bodies: the wizards'
## for LAYER_PLAYER, else the enemies'.
func _team_of_target(owner: int, layer: int) -> int:
	var team: int = pm._team_of(owner) if owner >= 0 else Manager.ActorsScript.NONE
	if team != Manager.ActorsScript.NONE:
		return team
	return Manager.ActorsScript.TEAM_WIZARDS if (layer & Manager.LAYER_PLAYER) != 0 else Manager.ActorsScript.TEAM_ENEMIES


## Register a Node2D as something projectiles can hit (`layer` is a non-zero
## bit mask). Registering twice only updates the shape, layer and owner. A freed target is dropped by itself.
## `owner` is the actor whose body it is (or whose decoy), or Events.NO_PLAYER: aim reads it
## (homing never picks its own actor's body) and its team (see `_team_of_target`); a hit never
## asks it. Its hit shape (`HitShape`) is a circle of `radius`, or with a `half` a box that far
## either way of its centre (rounded by `radius`); `offset` moves its centre from the
## node's origin (usually the feet) to the drawn body, so a shot that looks like it touches
## the sprite does hit. `key` is its identity (`_target_key`): its actor's key (`Actors.key_of`); 0
## gives it one of the manager's own (a plain node, in tests). Registered again with a key, it takes it.
func add_target(node: Node2D, radius: float, layer: int = Manager.LAYER_ENEMY, owner: int = Manager.EventsScript.NO_PLAYER, offset: Vector2 = Vector2.ZERO, key: int = 0, half: Vector2 = Vector2.ZERO) -> void:
	if node == null or layer == 0:
		return
	half = half.max(Vector2.ZERO)
	pm._max_target_reach = maxf(pm._max_target_reach, HitShape.axis_reach(half, radius))
	var at: int = pm._target_row(node)
	if at >= 0:
		if key != 0:
			_target_key[at] = key
		_target_radius[at] = radius
		_target_half[at] = half
		_target_layer[at] = layer
		_target_owner[at] = owner
		_target_team[at] = _team_of_target(owner, layer)
		_target_offset[at] = offset
		return
	if key == 0:
		pm._minted_keys -= 1
		key = pm._minted_keys
	_targets.append(node)
	_target_id.append(node.get_instance_id())
	_target_key.append(key)
	_target_radius.append(radius)
	_target_half.append(half)
	_target_layer.append(layer)
	_target_owner.append(owner)
	_target_team.append(_team_of_target(owner, layer))
	_target_pos.append(Vector2.ZERO)
	_target_offset.append(offset)
	_target_next.append(-1)
	pm._grid_stale = true


## Give a registered target a new `owner` (see `add_target`): an enemy that casts a staff
## names its actor, so its own shots skip it. Returns false for a node not registered.
func set_target_owner(node: Node2D, owner: int) -> bool:
	if node == null or not Manager.is_caster(owner):
		return false
	var at: int = pm._target_row(node)
	if at < 0:
		return false
	_target_owner[at] = owner
	_target_team[at] = _team_of_target(owner, _target_layer[at])
	return true


func remove_target(node: Node2D) -> void:
	if node == null:
		return
	var at: int = pm._target_row(node)
	if at < 0:
		return
	if pm._stepping:
		_target_layer[at] = 0
	else:
		_remove_target_at(at)
		pm._grid_stale = true


## True when the circle (`point`, `radius`) overlaps the hit shape of the registered target
## `node` where it stands now (its node's place and offset, as each step reads it). False for a
## node that is not registered, freed or out of the tree.
func touches_target(node: Node, point: Vector2, radius: float) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var at: int = pm._target_row(node)
	if at < 0:
		return false
	var body: Node2D = _targets[at] as Node2D
	if body == null or not body.is_inside_tree():
		return false
	return HitShape.gap(point - (body.global_position + _target_offset[at]), _target_half[at]) <= _target_radius[at] + radius


## The shot in `slot` does not hit `node` (the body it started on: its caster's own, or the body whose
## hit fired it, as a payload; the spell runtime gives every launch one) until it has
## been clear of it: the first hit test whose step starts with the shot off that body's hit shape
## ends the exclusion (`_still_spares`), and from then on it hits that body as any other (owner,
## 2026-11-06: no timer, so a slow shot born on its source can no longer hit it as it crawls out).
## A body its own caster owns is the one it was cast from, at the staff tip off that body: it still
## spares the body while coming at it (`_skip_near`), so a shot aimed back across its caster (a
## nova's, a mirror's) passes them (owner, 2026-11-07), however fast it is and however they move
## (owner, 2026-11-16).
func exclude(slot: int, node: Node) -> void:
	if slot >= 0 and slot < pm._cap and _alive[slot] != 0 and node != null:
		# Kept by its key (N5); a node that is no target (none registered) is never hit anyway.
		var at: int = pm._target_row(node)
		_skip_id[slot] = _target_key[at] if at >= 0 else 0
		_skip_on[slot] = 1.0
		_skip_near[slot] = 0.0
		if at < 0 or _actor[slot] < 0 or _target_owner[at] != _actor[slot]:
			return
		var body: Node2D = _targets[at] as Node2D
		if body == null or not body.is_inside_tree():
			return
		var off: float = HitShape.gap(_pos[slot] - (body.global_position + _target_offset[at]), _target_half[at]) - _radius[slot] - _target_radius[at]
		_skip_near[slot] = (off if off > 0.0 and is_finite(off) else 0.0) + Manager.SPARE_DRIFT


## The registered target whose key is `key` (`key_of`), or null: none, or no longer registered.
func target_of_key(key: int) -> Node2D:
	if key == 0:
		return null
	var at: int = _target_key.find(key)
	if at < 0 or not is_instance_valid(_targets[at]):
		return null
	return _targets[at] as Node2D


func _remove_target_at(at: int) -> void:
	var last: int = _targets.size() - 1
	_targets[at] = _targets[last]
	_target_id[at] = _target_id[last]
	_target_key[at] = _target_key[last]
	_target_radius[at] = _target_radius[last]
	_target_half[at] = _target_half[last]
	_target_layer[at] = _target_layer[last]
	_target_owner[at] = _target_owner[last]
	_target_team[at] = _target_team[last]
	_target_pos[at] = _target_pos[last]
	_target_offset[at] = _target_offset[last]
	_targets.resize(last)
	_target_id.resize(last)
	_target_key.resize(last)
	_target_radius.resize(last)
	_target_half.resize(last)
	_target_layer.resize(last)
	_target_owner.resize(last)
	_target_team.resize(last)
	_target_pos.resize(last)
	_target_offset.resize(last)
	_target_next.resize(last)


## Drop freed targets, read the positions of the rest and fill the grid.
func _refresh_targets() -> void:
	_cell_head.fill(-1)
	_world_rows.resize(0)
	pm._grid_stale = false
	# A new filling: every cell's count and box are taken again when first needed (`_cell_info`).
	pm._grid_fill += 1
	# The table once for every target (this runs every step for every body).
	var table: Manager.ActorsScript = pm.actor_table()
	var grid_x: float = pm._grid_x
	var grid_y: float = pm._grid_y
	var last_x: int = pm._grid_w - 1
	var last_y: int = pm._grid_h - 1
	var width: int = pm._grid_w
	# Every actor's team at once (the table's own array, read only): a call per target cost more
	# than the rest of its filling.
	var teams: PackedInt32Array = table.teams() if table != null else PackedInt32Array()
	var team_rows: int = teams.size()
	# One pass: a freed or removed target is dropped where it is found (the last one takes its
	# index and is read next), so the indices and the chains come out as a drop pass and then a
	# fill pass would leave them. Written out: every target, every step (2026-10-31).
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
		var team: int = teams[owner] if owner >= 0 and owner < team_rows else Manager.ActorsScript.NONE
		if team == Manager.ActorsScript.NONE:
			team = Manager.ActorsScript.TEAM_WIZARDS if (_target_layer[i] & Manager.LAYER_PLAYER) != 0 else Manager.ActorsScript.TEAM_ENEMIES
		_target_team[i] = team
		if team == Manager.ActorsScript.TEAM_WORLD:
			_world_rows.append(i)
		if not node.is_inside_tree():
			_target_pos[i] = Vector2.INF
			_target_next[i] = -1
			i += 1
			continue
		var centre: Vector2 = node.global_position + _target_offset[i]
		_target_pos[i] = centre
		var cell: int = clampi(floori((centre.y - grid_y) / Manager.GRID_CELL), 0, last_y) * width + clampi(floori((centre.x - grid_x) / Manager.GRID_CELL), 0, last_x)
		_target_next[i] = _cell_head[cell]
		_cell_head[cell] = i
		i += 1


## The nearest target on `layers` whose hit shape overlaps the circle (`point`,
## `radius`), by distance to its centre, or null. `exclude` is skipped (the target
## just hit, for a chain) and so is `exclude_also`. With a `team` (not NONE), targets of that
## team are skipped too, and the world's always: aim at foes only (`Actors.is_foe`: a chain's jump,
## an arc's zap, a familiar's cast).
## The hit shape's centre of the target returned is left in `nearest_point`. Allocation-free.
func nearest_target(point: Vector2, radius: float, layers: int, exclude: Node2D = null, exclude_also: Node2D = null, team: int = Manager.ActorsScript.NONE) -> Node2D:
	var _kernel: Object = pm._kernel
	pm.nearest_point = Vector2.INF
	if not point.is_finite() or not is_finite(radius):
		return null
	var best: int = -1
	_query_ready()
	var skip: int = pm._target_row(exclude)
	var skip_also: int = pm._target_row(exclude_also)
	# The search in C++ when the module is loaded (sim-native SN3: an AI's look for its nearest foe
	# goes over the whole crowd), else here; -2 only when the kernel refused the grid.
	var native_search: bool = _kernel != null and pm._kernel_nearest
	if native_search:
		best = _kernel.call(&"nearest_target", pm, point, radius, layers, skip, skip_also, team)
	if best == -2 or not native_search:
		best = _gd_nearest_row(point, radius, layers, skip, skip_also, team)
	if best < 0:
		return null
	pm.nearest_point = _target_pos[best]
	return _targets[best]


## True when a target on `layers` that is a foe of `team` (not of `team`, Actors.NONE for none, and
## never the world's) has a hit shape overlapping the circle (`point`, `radius`): a staff-language
## condition's `close` (docs/milestones/staff-language.md, L2). A pure read: it writes nothing, not
## `nearest_point` and not the grid (it does not refresh a stale one, so between ticks it answers from
## the grid as the simulation last left it), so the HUD may ask it every frame without changing the
## state a tick hashes. `refresh`: asked in the tick, where a stale grid is refilled first, as
## `nearest_target` does. Allocation-free.
func has_foe_near(point: Vector2, radius: float, layers: int, team: int, refresh: bool = false) -> bool:
	if refresh:
		# In the tick (a sigil's close, staff-language L4): a stale grid is brought up to date first,
		# as every query of the simulation's is (`_query_ready`).
		_query_ready()
	if not point.is_finite() or not is_finite(radius) or _cell_head.size() < pm._grid_w * pm._grid_h:
		return false
	var cells: Vector4i = _query_cells(point, radius)
	for y in range(cells.y, cells.w + 1):
		for x in range(cells.x, cells.z + 1):
			var t: int = _cell_head[y * pm._grid_w + x]
			while t >= 0:
				if _query_match(t, point, radius, layers, -1) and _target_team[t] != Manager.ActorsScript.TEAM_WORLD and (team == Manager.ActorsScript.NONE or _target_team[t] != team):
					return true
				t = _target_next[t]
	return false


## `nearest_target`'s search in GDScript: the reference `ShotKernel.nearest_target` mirrors, and the
## fallback. The row of the nearest target (by distance to its centre) or -1.
func _gd_nearest_row(point: Vector2, radius: float, layers: int, skip: int, skip_also: int, team: int) -> int:
	var best: int = -1
	var best_sq: float = INF
	var cells: Vector4i = _query_cells(point, radius)
	for y in range(cells.y, cells.w + 1):
		for x in range(cells.x, cells.z + 1):
			var t: int = _cell_head[y * pm._grid_w + x]
			while t >= 0:
				if _query_match(t, point, radius, layers, skip) and t != skip_also and _target_team[t] != Manager.ActorsScript.TEAM_WORLD and (team == Manager.ActorsScript.NONE or _target_team[t] != team):
					var d: float = _target_pos[t].distance_squared_to(point)
					if d < best_sq:
						best_sq = d
						best = t
				t = _target_next[t]
	return best


## Fill `out` with the targets on `layers` that are foes of `team` (`Actors.is_foe`: not of `team`,
## Actors.NONE for none, and never the world's) whose hit shape
## overlaps the circle (`point`, `radius`), `centres` with where each one's hit shape is centred and
## `radii` with how far it reaches from there at most (`HitShape.outer_radius`: a circle's radius), in the same order; return how many (a zap's bodies in reach). Order is the grid's: the same every
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
			var t: int = _cell_head[y * pm._grid_w + x]
			while t >= 0:
				var at: Vector2 = point if end == point else _nearest_on_line(t, point, end)
				if _query_match(t, at, radius, layers, -1) and _target_team[t] != Manager.ActorsScript.TEAM_WORLD and (team == Manager.ActorsScript.NONE or _target_team[t] != team) and not (keep and out.has(_targets[t])):
					if centres.size() <= out.size():
						centres.resize(maxi(out.size() * 2, 8))
						radii.resize(centres.size())
					centres[out.size()] = _target_pos[t]
					radii[out.size()] = HitShape.outer_radius(_target_half[t], _target_radius[t])
					out.append(_targets[t])
				t = _target_next[t]
	return out.size()


## Fill `out` (cleared first) with the targets on `layers` whose hit shape overlaps
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
			var t: int = _cell_head[y * pm._grid_w + x]
			while t >= 0:
				if _query_match(t, _nearest_on_line(t, point, end), radius, layers, -1):
					out.append(_targets[t])
				t = _target_next[t]
	return out.size()


## Fill the grid when targets were added since it was last filled. Never inside a
## step, where the grid is in use and already current.
func _query_ready() -> void:
	if pm._grid_stale and not pm._stepping:
		_refresh_targets()


## The grid cells (x0, y0, x1, y1) a query circle can reach.
func _query_cells(point: Vector2, radius: float) -> Vector4i:
	var pad: Vector2 = Vector2.ONE * (maxf(radius, 0.0) + pm._max_target_reach)
	var low: Vector2 = point - pad
	var high: Vector2 = point + pad
	return Vector4i(
		clampi(floori((low.x - pm._bounds.position.x) / Manager.GRID_CELL), 0, pm._grid_w - 1),
		clampi(floori((low.y - pm._bounds.position.y) / Manager.GRID_CELL), 0, pm._grid_h - 1),
		clampi(floori((high.x - pm._bounds.position.x) / Manager.GRID_CELL), 0, pm._grid_w - 1),
		clampi(floori((high.y - pm._bounds.position.y) / Manager.GRID_CELL), 0, pm._grid_h - 1))


## The point of the line from `point` to `end` nearest target `t`'s hit shape (`HitShape.along`; a
## circle's: nearest its centre).
func _nearest_on_line(t: int, point: Vector2, end: Vector2) -> Vector2:
	var box: Vector2 = _target_half[t]
	if box == Vector2.ZERO:
		return Geometry2D.get_closest_point_to_segment(_target_pos[t], point, end)
	var path: Vector2 = end - point
	return point + path * HitShape.along(point, path, path.length_squared(), _target_pos[t], box)


func _query_match(t: int, point: Vector2, radius: float, layers: int, skip: int) -> bool:
	# A target freed since the grid was filled is skipped, never returned; `skip` is a row (-1: none).
	if (_target_layer[t] & layers) == 0 or t == skip or not is_instance_valid(_targets[t]):
		return false
	var reach: float = maxf(radius, 0.0) + _target_radius[t]
	return HitShape.gap_sq(point - _target_pos[t], _target_half[t]) <= reach * reach
