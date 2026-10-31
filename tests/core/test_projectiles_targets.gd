extends "res://tests/support/suite.gd"
## The projectile manager's target grid with many targets (Horde swarm S5, "Cheaper targets",
## docs/milestones/horde-swarm.md): the filling made cheaper must leave exactly what the old one
## did. Each step is checked against a fresh count made the slow way: which targets are kept and
## at which index (a freed or removed one dropped, the last taking its place), each one's centre
## and team (its owner's, read when the grid is filled, a possession included), every cell's chain
## (its targets, highest index first) and the count and box a hit test reads of a cell. And a
## scripted crowd (moving, freed, removed, added, re-owned and possessed targets; straight,
## piercing and homing shots; `nearest_target` and `targets_in` every step; dense enough that the
## hit-work budget runs out) must send the very hits it sent before the change: the fingerprint
## below was recorded on the manager before S5.
##
## godot --headless --path . --script res://tests/core/test_projectiles_targets.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

const DT: float = 1.0 / 60.0
const ROOM: Vector2 = Vector2(640.0, 360.0)
const BODIES: int = 400
const SHOTS: int = 300
const STEPS: int = 90
## The crowd's hits on the manager before S5 (count and hash of every hit and query, in order),
## recorded again on main's manager and Combat as they were before S5 when main's homing and atom
## changes came in (2026-10-31): a change to how shots fly changes this hash, so record it again
## on the code before the change, never from the code under test.
const RECORDED_HITS: int = 7282
const RECORDED_HASH: int = 3052657089

var _bus: EventsScript
var _mgr: ManagerScript
var _actors: ActorsScript
var _casters: PackedInt32Array
var _holder: Node2D
var _bodies: Array[Node2D] = []
var _owners: PackedInt32Array = PackedInt32Array()
var _index_of: Dictionary = {}
var _hits: int = 0
var _hash: int = 0
var _step_no: int = 0
var _fired: int = 0
var _near: Array[Node2D] = []


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_actors = own(ActorsScript.new()) as ActorsScript
	_casters = ActorSeats.seat_wizards(_actors, 4)
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.actors = _actors
	_mgr.events = _bus
	root.add_child(_mgr)
	_mgr.set_cap(SHOTS)
	_mgr.set_bounds(Rect2(Vector2.ZERO, ROOM))
	_holder = own(Node2D.new()) as Node2D
	_holder.position = Vector2(3.0, -2.0)
	root.add_child(_holder)
	_bodies.clear()
	_owners.clear()
	_index_of.clear()
	_hits = 0
	_hash = 0
	_step_no = 0
	_fired = 0
	for seat in 4:
		var wizard := Node2D.new()
		wizard.position = ROOM * 0.5 + Vector2(-30.0 + 20.0 * seat, 40.0)
		_holder.add_child(wizard)
		_mgr.add_target(wizard, 7.0, ManagerScript.LAYER_PLAYER, _casters[seat], Vector2(0.0, -8.0))
		_index_of[wizard.get_instance_id()] = -1 - seat
	for i in BODIES:
		_add_body(i)


## Body `i`: on a lattice over the room, an enemy actor of its own (every fifth no actor's), a
## few of them bigger.
func _add_body(i: int) -> void:
	var body := Node2D.new()
	body.position = _home(i)
	_holder.add_child(body)
	var owner: int = ActorSeats.enemy(_actors) if i % 5 != 0 else EventsScript.NO_PLAYER
	var radius: float = 14.0 if i % 37 == 0 else 6.0
	_mgr.add_target(body, radius, ManagerScript.LAYER_ENEMY, owner, Vector2(0.0, -6.0))
	_bodies.append(body)
	_owners.append(owner)
	_index_of[body.get_instance_id()] = i


func _home(i: int) -> Vector2:
	return Vector2(fmod(float(i) * 97.31, ROOM.x - 40.0) + 20.0, fmod(float(i) * 53.77 + float(i / 13) * 7.0, ROOM.y - 40.0) + 20.0)


## Every body walks back and forth along its own slant (no trigonometry: the same on every
## platform).
func _move() -> void:
	for i in _bodies.size():
		var held: Variant = _bodies[i]
		if not is_instance_valid(held):
			continue
		var body: Node2D = held
		var swing: float = absf(fmod(float(_step_no + i * 7), 40.0) - 20.0)
		body.position = _home(i) + Vector2(swing, swing * 0.5 * float(i % 3 - 1))


## What happens to the crowd at some steps: bodies freed, removed, taken out of the tree and put
## back, added, given a new owner, and an actor possessed onto the wizards' team and back.
func _events() -> void:
	match _step_no:
		10:
			for i in range(0, 60, 3):
				_bodies[i].free()
		20:
			for i in range(1, 40, 3):
				_mgr.remove_target(_bodies[i])
		30:
			for i in range(2, 50, 6):
				_holder.remove_child(_bodies[i])
		40:
			for i in range(2, 50, 6):
				_holder.add_child(_bodies[i])
			for i in 30:
				_add_body(_bodies.size())
		50:
			_mgr.set_target_owner(_bodies[101], _casters[1])
			if _owners[103] >= 0:
				_actors.set_driver(_owners[103], ActorsScript.TEAM_WIZARDS, ActorsScript.NONE)
		60:
			if _owners[103] >= 0:
				_actors.set_driver(_owners[103], ActorsScript.TEAM_ENEMIES, ActorsScript.NONE)
			for i in range(200, 260, 2):
				_bodies[i].queue_free()


## Keep the cap full from the wizards on a fixed fan (whole-number directions), a third piercing,
## every seventh homing.
func _top_up() -> void:
	while _mgr.get_count() < SHOTS:
		var seat: int = _fired % 4
		var way: Vector2 = Vector2(float(_fired % 23 - 11), float(_fired % 17 - 8))
		if way.is_zero_approx():
			way = Vector2.RIGHT
		var origin: Vector2 = ROOM * 0.5 + Vector2(-30.0 + 20.0 * seat, 32.0)
		var pierce: int = 2 if _fired % 3 == 0 else 0
		var slot: int = _mgr.spawn(_casters[seat], origin, way.normalized() * 420.0, 1.5, 4.0, ManagerScript.LAYER_ENEMY, pierce, _fired + 1)
		if _fired % 7 == 0:
			_mgr.set_homing(slot, 6.0, 120.0)
		_fired += 1


func _on_hit(caster: int, target: Node, point: Vector2, tag: int, _slot: int) -> void:
	_hits += 1
	_hash = hash([_hash, _step_no, caster, _index_of.get(target.get_instance_id(), -99), tag, point])


## The queries every step, folded into the fingerprint: the nearest target of another team and
## the targets in a circle.
func _query() -> void:
	for n in 8:
		var at: Vector2 = Vector2(40.0 + 70.0 * float(n), 60.0 + 30.0 * float((n + _step_no) % 9))
		var found: Node2D = _mgr.nearest_target(at, 40.0, ManagerScript.ACTOR_LAYERS, null, null, ActorsScript.TEAM_WIZARDS)
		_hash = hash([_hash, -1, _index_of.get(found.get_instance_id(), -99) if found != null else -98])
		var count: int = _mgr.targets_in(at, 30.0, ManagerScript.LAYER_ENEMY, _near)
		var ids: Array[int] = []
		for k in count:
			ids.append(_index_of.get(_near[k].get_instance_id(), -99))
		ids.sort()
		_hash = hash([_hash, -2, ids])


func test_the_crowd_sends_the_hits_it_sent_before() -> void:
	_bus.projectile_hit.connect(_on_hit)
	for i in STEPS:
		if i == 62:
			# The bodies queued for freeing go.
			await process_frame
		_move()
		_events()
		_top_up()
		_mgr.step(DT)
		_query()
		_step_no += 1
	print("crowd: %d hits, hash %d" % [_hits, _hash])
	check(_hits > 1000, "the crowd is hit a lot (%d hits)" % _hits)
	check_equal(_hits, RECORDED_HITS, "as many hits as before")
	check_equal(_hash, RECORDED_HASH, "the same hits, queries and order as before")


func test_each_filling_matches_a_fresh_count() -> void:
	for i in 70:
		if i == 62:
			await process_frame
		_move()
		_events()
		_top_up()
		_mgr.step(DT)
		_step_no += 1
		_check_grid("step %d" % i)
	# A query after a change outside a step fills it again.
	_bodies[300].free()
	_add_body(_bodies.size())
	_mgr.nearest_target(Vector2(100.0, 100.0), 20.0, ManagerScript.ACTOR_LAYERS)
	_check_grid("after a query")


## The grid against a count made the slow way. `kept` mirrors the manager's own drop (the last
## takes the place of a dropped one) over its targets before the filling.
func _check_grid(when: String) -> void:
	var problems: int = 0
	var count: int = _mgr._targets.size()
	for t in count:
		var held: Variant = _mgr._targets[t]
		if not is_instance_valid(held) or _mgr._target_layer[t] == 0:
			problems += 1
			continue
		var node: Node2D = held
		var expected: Vector2 = node.global_position + _mgr._target_offset[t] if node.is_inside_tree() else Vector2.INF
		if _mgr._target_pos[t] != expected:
			problems += 1
		var owner: int = _mgr._target_owner[t]
		var team: int = _actors.team_of(owner) if owner >= 0 else ActorsScript.NONE
		if team == ActorsScript.NONE:
			team = ActorsScript.TEAM_WIZARDS if (_mgr._target_layer[t] & ManagerScript.LAYER_PLAYER) != 0 else ActorsScript.TEAM_ENEMIES
		if _mgr._target_team[t] != team:
			problems += 1
	check_equal(problems, 0, "%s: every target kept is there, at its centre, on its team" % when)
	# Every cell's chain: its targets, highest index first; the count and box a hit test reads.
	var bad_cells: int = 0
	var cells: int = _mgr._grid_w * _mgr._grid_h
	var in_cell: Array = []
	in_cell.resize(cells)
	for c in cells:
		in_cell[c] = []
	for t in count:
		var at: Vector2 = _mgr._target_pos[t]
		if not at.is_finite():
			continue
		var cell: int = clampi(floori((at.y - _mgr._grid_y) / ManagerScript.GRID_CELL), 0, _mgr._grid_h - 1) * _mgr._grid_w + clampi(floori((at.x - _mgr._grid_x) / ManagerScript.GRID_CELL), 0, _mgr._grid_w - 1)
		(in_cell[cell] as Array).push_front(t)
	for c in cells:
		var chain: Array = []
		var t: int = _mgr._cell_head[c]
		while t >= 0 and chain.size() <= count:
			chain.append(t)
			t = _mgr._target_next[t]
		var want: Array = in_cell[c]
		if chain != want:
			bad_cells += 1
			continue
		_mgr._cell_info(c)
		if _mgr._cell_count[c] != want.size():
			bad_cells += 1
			continue
		if want.is_empty():
			continue
		var box := Vector4(INF, INF, -INF, -INF)
		for k: int in want:
			var centre: Vector2 = _mgr._target_pos[k]
			var r: float = _mgr._target_radius[k]
			box = Vector4(minf(box.x, centre.x - r), minf(box.y, centre.y - r), maxf(box.z, centre.x + r), maxf(box.w, centre.y + r))
		if _mgr._cell_box[c] != box:
			bad_cells += 1
	check_equal(bad_cells, 0, "%s: every cell's chain, count and box" % when)


func test_kept_targets_keep_the_order_of_a_drop_then_fill() -> void:
	_mgr.step(DT)
	var ids: Array[int] = []
	for t in _mgr._targets.size():
		ids.append((_mgr._targets[t] as Node).get_instance_id())
	# Drop the way the manager does, the slow way: the last takes the dropped one's index.
	var gone: Array[int] = [5, 6, ids.size() - 1, 100, 101, 250]
	for t: int in gone:
		(_mgr._targets[t] as Node).free()
	var expected: Array[int] = ids.duplicate()
	var dropped: Array[int] = []
	for t: int in gone:
		dropped.append(ids[t])
	var at: int = 0
	while at < expected.size():
		if dropped.has(expected[at]):
			expected[at] = expected[expected.size() - 1]
			expected.resize(expected.size() - 1)
			continue
		at += 1
	_mgr.step(DT)
	var kept: Array[int] = []
	for t in _mgr._targets.size():
		kept.append((_mgr._targets[t] as Node).get_instance_id())
	check_equal(kept.size(), ids.size() - gone.size(), "the dropped ones are gone")
	check(kept == expected, "the rest keep the indices a drop pass would leave")
