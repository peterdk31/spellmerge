extends SceneTree
## Times the per-body cost of the projectile manager and of Combat (Horde swarm S5,
## docs/milestones/horde-swarm.md, "Cheaper targets") with 600 and 1,000 swarm bodies, and prints
## `BENCH:` lines. Each body is what a swarmer is: a bare Node2D (no script, no children)
## registered through Combat as a plain body (its own actor id, its hurt circle a projectile
## target, a touch that hurts), moved by writing its `position` every step, round a small circle
## about its home on a lattice over the room. Four wizards stand in the middle (Combat rows on the
## wizards' team, so the swarm's touch hurts them, and projectile targets of their own casters) and
## keep the web cap of shots (500) flying outward on a fixed fan, a third of them piercing.
##
## Timed (medians, so a busy machine moves them less): the manager's whole `step`, its target
## refresh alone (`_refresh_targets`: positions, teams, the grid), the same shots with no targets
## (what the step costs without bodies), and Combat's `step` (statuses, contact). Each runs in the
## horde arena (1280x720) and in the usual room (640x360, denser: more bodies to a grid cell).
##
## It also prints a fingerprint of every shot hit and every touch (`HITS:` counts and a hash of
## step, caster, body, tag and point), so two versions can be compared on the same scene: the
## hits must match. Nothing is random.
##
## godot --headless --path . --script res://tests/benchmark/target_grid.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const DT: float = 1.0 / 60.0
## The horde arena, and the usual room H1 measured in.
const ARENA: Vector2 = Vector2(1280.0, 720.0)
const SMALL_ROOM: Vector2 = Vector2(640.0, 360.0)
const SHOTS: int = 500
const WARMUP: int = 60
const STEPS: int = 240
## (bodies, room) per run.
const RUNS: Array = [[600, ARENA], [1000, ARENA], [600, SMALL_ROOM], [1000, SMALL_ROOM]]
## Wizards never die here.
const WIZARD_HEALTH: int = 1 << 30

var _bus: Node
var _mgr: Node2D
var _combat: Node
var _actors: ActorSeats.ActorsScript
var _casters: PackedInt32Array
var _holder: Node2D
var _bodies: Array[Node2D] = []
var _index_of: Dictionary = {}
var _home: PackedVector2Array = PackedVector2Array()
var _phase: PackedFloat32Array = PackedFloat32Array()
var _hits: int = 0
var _touches: int = 0
var _hash: int = 0
var _step_no: int = 0
var _fired: int = 0
## Microseconds spent in this script's own handlers (taken off the step's time).
var _handler_us: int = 0
var _room: Vector2 = ARENA


func _initialize() -> void:
	await process_frame
	for run: Array in RUNS:
		_room = run[1]
		_run(run[0])
	print("TARGET GRID DONE")
	quit(0)


func _run(count: int) -> void:
	_bus = EventsScript.new()
	_mgr = ManagerScript.new()
	_actors = ActorSeats.ActorsScript.new()
	_casters = ActorSeats.seat_wizards(_actors, 4)
	_mgr.set("actors", _actors)
	_mgr.events = _bus
	root.add_child(_mgr)
	_mgr.set_cap(SHOTS)
	_mgr.set_bounds(Rect2(Vector2.ZERO, _room))
	_combat = CombatScript.new()
	_combat.set("actors", _actors)
	_combat.set("projectiles", _mgr)
	_combat.set("events", _bus)
	root.add_child(_combat)
	_holder = Node2D.new()
	root.add_child(_holder)
	_bodies.clear()
	_index_of.clear()
	_home.resize(count)
	_phase.resize(count)
	# The wizards, in the middle: Combat rows turned to the wizards' team, and targets of their own
	# casters on the wizards' layer.
	for seat in 4:
		var wizard := Node2D.new()
		wizard.position = _room * 0.5 + Vector2(-30.0 + 20.0 * seat, 0.0)
		_holder.add_child(wizard)
		var row: int = _combat.call("register_actor", wizard, WIZARD_HEALTH, 7.0, 0, Vector2(0.0, -8.0))
		_actors.set_driver(row, ActorSeats.ActorsScript.TEAM_WIZARDS, ActorSeats.ActorsScript.NONE)
		_mgr.add_target(wizard, 7.0, ManagerScript.LAYER_PLAYER, _casters[seat], Vector2(0.0, -8.0))
		_index_of[wizard.get_instance_id()] = -1 - seat
	# The swarm: a jittered lattice over the room, each on a small circle round its home.
	for i in count:
		var body := Node2D.new()
		var home := Vector2(fmod(float(i) * 97.31, _room.x - 40.0) + 20.0, fmod(float(i) * 53.77 + float(i / 13) * 7.0, _room.y - 40.0) + 20.0)
		_home[i] = home
		_phase[i] = float(i) * 0.37
		body.position = home
		_holder.add_child(body)
		_combat.call("register_actor", body, 10, 6.0, 3, Vector2(0.0, -6.0))
		_bodies.append(body)
		_index_of[body.get_instance_id()] = i
	_bus.projectile_hit.connect(_on_hit)
	_bus.hit_landed.connect(_on_touch)
	_hits = 0
	_touches = 0
	_hash = 0
	_step_no = 0
	_fired = 0
	for i in WARMUP:
		_tick()
	var step_us := PackedFloat64Array()
	var combat_us := PackedFloat64Array()
	for i in STEPS:
		_move()
		_top_up()
		_handler_us = 0
		var t0: int = Time.get_ticks_usec()
		_mgr.step(DT)
		var t1: int = Time.get_ticks_usec()
		step_us.append(t1 - t0 - _handler_us)
		_handler_us = 0
		_combat.call("step", DT)
		combat_us.append(Time.get_ticks_usec() - t1 - _handler_us)
		_step_no += 1
	var refresh_us := PackedFloat64Array()
	for i in STEPS:
		_move()
		var t: int = Time.get_ticks_usec()
		_mgr.call("_refresh_targets")
		refresh_us.append(Time.get_ticks_usec() - t)
	# The shots alone: the same shots with no targets left (what the step costs without bodies).
	for body in _holder.get_children():
		_mgr.remove_target(body)
	var shots_us := PackedFloat64Array()
	for i in STEPS:
		_top_up()
		var t: int = Time.get_ticks_usec()
		_mgr.step(DT)
		shots_us.append(Time.get_ticks_usec() - t)
	var room: String = "%dx%d" % [int(_room.x), int(_room.y)]
	print("BENCH: %d bodies, %s (medians): manager step %.3f ms, its target refresh %.3f ms, the shots without targets %.3f ms; Combat step %.3f ms" % [
		count, room, _median_ms(step_us), _median_ms(refresh_us), _median_ms(shots_us), _median_ms(combat_us)])
	print("HITS: %d bodies, %s: %d shot hits, %d touches, hash %d" % [count, room, _hits, _touches, _hash])
	_bus.projectile_hit.disconnect(_on_hit)
	_bus.hit_landed.disconnect(_on_touch)
	_combat.free()
	_holder.free()
	_mgr.free()
	_bus.free()
	_actors.free()


func _tick() -> void:
	_move()
	_top_up()
	_mgr.step(DT)
	_combat.call("step", DT)
	_step_no += 1


## Every body on its circle (as the swarm writes `position` each step).
func _move() -> void:
	var t: float = float(_step_no) * DT
	for i in _bodies.size():
		var a: float = _phase[i] + t * 1.3
		_bodies[i].position = _home[i] + Vector2(cos(a), sin(a)) * 18.0


## Keep the cap full: new shots from the wizards, outward on a fixed fan, a third piercing.
func _top_up() -> void:
	while _mgr.get_count() < SHOTS:
		var seat: int = _fired % 4
		var angle: float = float(_fired) * 2.399963
		var origin: Vector2 = _room * 0.5 + Vector2(-30.0 + 20.0 * seat, -8.0)
		var pierce: int = 2 if _fired % 3 == 0 else 0
		_mgr.spawn(_casters[seat], origin, Vector2(cos(angle), sin(angle)) * 420.0, 2.0, 4.0, ManagerScript.LAYER_ENEMY, pierce, _fired + 1)
		_fired += 1


func _on_hit(caster: int, target: Node, point: Vector2, tag: int, _slot: int) -> void:
	var start: int = Time.get_ticks_usec()
	_hits += 1
	var which: int = _index_of.get(target.get_instance_id(), -99)
	_hash = hash([_hash, _step_no, caster, which, tag, snappedf(point.x, 0.001), snappedf(point.y, 0.001)])
	_handler_us += Time.get_ticks_usec() - start


func _on_touch(by: int, target: Node, amount: int, _where: Vector2, kind: StringName, _slot: int) -> void:
	var start: int = Time.get_ticks_usec()
	_touches += 1
	var which: int = _index_of.get(target.get_instance_id(), -99)
	_hash = hash([_hash, _step_no, by, which, amount, kind])
	_handler_us += Time.get_ticks_usec() - start


## The median of `samples` (microseconds), in milliseconds.
func _median_ms(samples: PackedFloat64Array) -> float:
	samples.sort()
	return samples[samples.size() / 2] / 1000.0
