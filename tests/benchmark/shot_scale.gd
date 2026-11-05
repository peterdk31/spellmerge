extends SceneTree
## Shot scale H0 (docs/milestones/shot-scale.md): the baseline for every later part. Three scenes,
## each at 10,000, 30,000, 50,000 and 100,000 live shots, timed part by part:
##
## - **storm:** the shots fly over the horde arena (1280x720) from four wizards in the middle, with
##   eight training bodies in their way: what flying costs (the kernel's passes, drawing).
## - **crowd:** the same shots among CROWD bodies on a lattice over the arena, each on a small circle
##   about its home (as the swarm moves): what hitting costs as the game does it, with the hit-work
##   budget (`WORK_PER_STEP`) spent every step, so most shots go untested that step.
## - **crowd_all:** the crowd with the budget lifted (`work_per_step` = UNBUDGETED), every shot
##   tested every step: what hitting would cost if nothing waited (H2's question), and the kernel's
##   real share of it (H5's).
##
## Every shot is a real spell's (the cards `--cards=`, a plain bolt by default, compiled by the real
## Spells), so its hit goes through the real listeners: Spells, Combat (damage, statuses) and Feel
## (impacts, sparks, sounds, motes), on a bus of their own, as the clip stage wires them
## (tests/clips/stage.gd). Nothing steps by itself; the script steps one tick (1/60 s) at a time.
## The shots' tails are the game's: motes (`tails_enabled` off, as since 2026-11-05); `--tails` puts
## the tail shader's trails back, for comparing with the numbers before.
##
## Timed, per step (medians and p95, milliseconds): the projectile manager's own `step()`, in the
## parts it times itself when a benchmark asks (`step_profile`, `PROF_*`: the target refresh, the
## common pass, the behaviour passes before the hits, the hit pass, of which the native kernel's own
## time and the rest, the hand-backs to GDScript with every listener of the hits and ends they send,
## the passes after the hits, the trail samples), the hand-backs a step (native `hits` calls), the
## hits and the shots past the hit-work budget; then Spells', Combat's and Feel's own `step`, the
## shots' spawn (not part of the game's cost: the script tops the shots up), `update_draw`, and, in
## a window, the GPU's time for a frame. A second pass of the same scene puts a timer between each
## hit event and each of its listeners (`BENCH: shot scale listener` lines; a listener's time
## includes the events it sends in turn, and the timer adds its own cost, so this pass's step is not
## compared).
##
## It also prints each scene's fingerprint for the damage check (shot-scale.md, "Parts"): the hits,
## a hash of every hit in order (step, caster, body, tag, point) and each body's damage taken
## (`DAMAGE:`, the total and a hash of the per-body totals). Nothing is random, so two versions of
## the code on the same scene must give the same totals.
##
## The numbers are one run on one machine: compare parts and versions with each other, and take a
## frame's real cost from the storm on the real GPU (`--storm` in the Web Test export).
##
## godot --headless --path . --script res://tests/benchmark/shot_scale.gd
## godot --headless --path . --script res://tests/benchmark/shot_scale.gd -- --counts=10000,30000 --only=crowd
## godot --path . --script res://tests/benchmark/shot_scale.gd   (a window: the GPU's frame time too)
##
## User arguments: `--counts=a,b,c` (the shot counts), `--only=storm|crowd|crowd_all` (or several,
## comma separated), `--steps=N` (the steps measured, STEPS), `--crowd=N` (the crowd's bodies,
## CROWD), `--cards=a,b,c` (card ids, in staff order), `--no-native` (the manager's GDScript),
## `--tails` (the tail shader's trails), `--work=N` (the hit-work budget of the storm and the crowd),
## `--no-listeners` (skip the listener pass). Not run in the build: a few minutes headless with the
## native module, longer without.

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const DT: float = 1.0 / 60.0
const ARENA: Rect2 = Rect2(0.0, 0.0, 1280.0, 720.0)
const COUNTS: Array[int] = [10000, 30000, 50000, 100000]
const SCENES: Array[String] = ["storm", "crowd", "crowd_all"]
const CROWD: int = 500
## The storm's bodies in the shots' way, round the wizards.
const STORM_BODIES: int = 8
## The hit-work budget of crowd_all: more than any step spends.
const UNBUDGETED: int = 1 << 40
## Steps before measuring: past one shot lifetime, so the shot count is steady.
const WARMUP: int = 150
const STEPS: int = 120
const SHOT_SPEED: float = 300.0
const SHOT_LIFE: float = 2.0
const SHOT_RADIUS: float = 3.0
## Every third shot pierces this many bodies.
const PIERCE: int = 2
## Bodies never die here, so every scene keeps its targets.
const BODY_HEALTH: float = 1.0e12
const BODY_RADIUS: float = 7.0
## The events a shot's hit or end sends (the sandbox storm's PROFILED_SIGNALS).
const TIMED_SIGNALS: Array[StringName] = [&"projectile_hit", &"projectile_impact", &"projectile_expired", &"damage_dealt", &"hit_landed", &"status_applied", &"reaction_triggered"]
## The lines printed: the manager's parts (its PROF_* times, in step order), then the rest of the tick.
const PARTS: Array[String] = ["refresh targets", "common pass", "passes before hits", "hit pass", "  in the kernel", "  hand-backs and their listeners (GDScript)", "passes after hits", "trail samples", "manager step", "Spells step", "Combat step", "Feel step", "spawn (the script's)", "update_draw"]
const P_REFRESH: int = 0
const P_COMMON: int = 1
const P_BEFORE: int = 2
const P_HITS: int = 3
const P_KERNEL: int = 4
const P_HANDBACK: int = 5
const P_AFTER: int = 6
const P_TRAILS: int = 7
const P_STEP: int = 8
const P_SPELLS: int = 9
const P_COMBAT: int = 10
const P_FEEL: int = 11
const P_SPAWN: int = 12
const P_DRAW: int = 13


## A timer between one event and one listener (the listener pass).
class Timed:
	extends RefCounted
	var key: String
	var target: Callable
	var usec: int = 0
	var calls: int = 0

	func on0() -> void:
		_run([])

	func on1(a: Variant) -> void:
		_run([a])

	func on2(a: Variant, b: Variant) -> void:
		_run([a, b])

	func on3(a: Variant, b: Variant, c: Variant) -> void:
		_run([a, b, c])

	func on4(a: Variant, b: Variant, c: Variant, d: Variant) -> void:
		_run([a, b, c, d])

	func on5(a: Variant, b: Variant, c: Variant, d: Variant, e: Variant) -> void:
		_run([a, b, c, d, e])

	func on6(a: Variant, b: Variant, c: Variant, d: Variant, e: Variant, f: Variant) -> void:
		_run([a, b, c, d, e, f])

	func _run(args: Array) -> void:
		if not target.is_valid():
			return
		var start: int = Time.get_ticks_usec()
		target.callv(args)
		usec += Time.get_ticks_usec() - start
		calls += 1


var _registry: Node
var _cards: Array[StringName] = [&"bolt"]
var _native: bool = true
var _tails: bool = false
var _work: int = ManagerScript.WORK_PER_STEP
var _headless: bool = true

var _bus: EventsScript
var _actors: ActorSeats.ActorsScript
var _mgr: ManagerScript
var _spells: SpellsScript
var _combat: CombatScript
var _feel: FeelScript
var _world: Node2D
var _owned: Array[Object] = []
var _casters: PackedInt32Array = PackedInt32Array()
var _tag: int = 0
var _bodies: Array[Node2D] = []
var _index_of: Dictionary[int, int] = {}
var _home: PackedVector2Array = PackedVector2Array()
var _phase: PackedFloat32Array = PackedFloat32Array()
var _moving: bool = false
var _shots: int = 0
var _fired: int = 0
var _step_no: int = 0
var _velocities: PackedVector2Array = PackedVector2Array()
var _slots: PackedInt32Array = PackedInt32Array()
## The fingerprint: hits, their hash.
var _hits: int = 0
var _hash: int = 0
## This step's measures, filled by `_tick`.
var _part_usec: PackedInt64Array = PackedInt64Array()
## Microseconds in this script's own hit handler this step (taken off the hit pass).
var _handler_usec: int = 0
var _timed: Array[Timed] = []


func _initialize() -> void:
	await process_frame
	_headless = DisplayServer.get_name() == "headless"
	_registry = root.get_node_or_null("Registry")
	if _registry == null:
		_fail("the Registry autoload must exist")
		return
	var counts: Array[int] = COUNTS.duplicate()
	var only: PackedStringArray = PackedStringArray()
	var steps: int = STEPS
	var crowd: int = CROWD
	var listeners: bool = true
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--counts="):
			counts.clear()
			for part: String in arg.trim_prefix("--counts=").split(",", false):
				counts.append(maxi(part.to_int(), 1))
		elif arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",", false)
		elif arg.begins_with("--steps="):
			steps = maxi(arg.trim_prefix("--steps=").to_int(), 1)
		elif arg.begins_with("--crowd="):
			crowd = maxi(arg.trim_prefix("--crowd=").to_int(), 1)
		elif arg.begins_with("--cards="):
			_cards.clear()
			for id: String in arg.trim_prefix("--cards=").split(",", false):
				_cards.append(StringName(id))
		elif arg.begins_with("--work="):
			_work = maxi(arg.trim_prefix("--work=").to_int(), 1)
		elif arg == "--no-native":
			_native = false
		elif arg == "--tails":
			_tails = true
		elif arg == "--no-listeners":
			listeners = false
	if not _build(16, 1, false, _work):
		return
	var native_on: bool = _mgr.is_native()
	_free_all()
	print("BENCH: shot scale, cards %s, native %s, tails %s, crowd %d, hit-work budget %d, %d steps measured, %s" % [",".join(_cards), "on" if native_on else "off", "the tail shader's" if _tails else "motes", crowd, _work, steps, "headless" if _headless else "in a window"])
	for scene: String in SCENES:
		if not only.is_empty() and not only.has(scene):
			continue
		for count in counts:
			var is_crowd: bool = scene != "storm"
			if not _build(count, crowd if is_crowd else STORM_BODIES, is_crowd, UNBUDGETED if scene == "crowd_all" else _work):
				return
			await _measure(scene, count, steps)
			if listeners:
				_time_listeners(scene, count, steps)
			_free_all()
	print("SHOT SCALE OK")
	quit(0)


## The scene: the bus, the real Spells, Combat and Feel, the manager at `count` shots with the hit-work
## budget `work`, the wizards and `bodies` bodies (a lattice over the arena when `crowd`, else round
## the wizards).
func _build(count: int, bodies: int, crowd: bool, work: int) -> bool:
	_bus = _own(EventsScript.new()) as EventsScript
	_actors = _own(ActorSeats.table()) as ActorSeats.ActorsScript
	_casters = PackedInt32Array()
	for seat in 4:
		_casters.append(_actors.actor_of_seat(seat))
	_mgr = _own(ManagerScript.new()) as ManagerScript
	_mgr.actors = _actors
	_mgr.events = _bus
	_mgr.set_native(_native)
	_mgr.set_cap(count)
	_mgr.set_bounds(ARENA)
	_mgr.set_tails_enabled(_tails)
	_mgr.work_per_step = work
	_mgr.profile_clock = Time.get_ticks_usec
	_spells = _own(SpellsScript.new()) as SpellsScript
	_spells.registry = _registry
	_spells.bind(_mgr, _bus)
	_combat = _own(CombatScript.new()) as CombatScript
	_combat.events = _bus
	_combat.projectiles = _mgr
	_combat.spells = _spells
	_combat.setup()
	_feel = _own(FeelScript.new()) as FeelScript
	_feel.events = _bus
	_feel.actors = _actors
	_feel.registry = _registry as RegistryScript
	_feel.projectiles = _mgr
	_feel.spells = _spells
	_feel.drive_engine = false
	_world = _own(Node2D.new()) as Node2D
	root.add_child(_world)
	var camera := Camera2D.new()
	camera.position = ARENA.get_center()
	camera.zoom = Vector2.ONE * minf(float(root.size.x) / ARENA.size.x, float(root.size.y) / ARENA.size.y)
	_world.add_child(camera)
	camera.make_current()
	_world.add_child(_mgr)
	_world.add_child(_feel)
	_mgr.set_physics_process(false)
	_mgr.set_process(false)
	_feel.set_process(false)
	var plain := StaffBase.new()
	plain.slots = maxi(_cards.size(), 1)
	plain.cast_delay = 0.0
	plain.recharge = 0.0
	var built: CompiledStaff = _spells.compile_staff(_cards, plain)
	if built.is_empty():
		_fail("the cards %s cast nothing" % ",".join(_cards))
		return false
	_tag = _spells.install_staff(_casters[0], 0, built)
	_bodies.clear()
	_index_of.clear()
	_home.resize(bodies)
	_phase.resize(bodies)
	_moving = crowd
	var middle: Vector2 = ARENA.get_center()
	for i in bodies:
		var at: Vector2
		if crowd:
			at = Vector2(fmod(float(i) * 97.31, ARENA.size.x - 40.0) + 20.0, fmod(float(i) * 53.77 + float(i / 13) * 7.0, ARENA.size.y - 40.0) + 20.0)
		else:
			at = middle + Vector2.from_angle(TAU * float(i) / float(bodies)) * 120.0
		_home[i] = at
		_phase[i] = float(i) * 0.37
		var body := Node2D.new()
		body.position = at
		_world.add_child(body)
		_combat.register_actor(body, BODY_HEALTH, BODY_RADIUS)
		_bodies.append(body)
		_index_of[body.get_instance_id()] = i
	_bus.projectile_hit.connect(_on_hit)
	_shots = count
	_fired = 0
	_step_no = 0
	_hits = 0
	_hash = 0
	_velocities.resize(256)
	_slots.resize(256)
	_part_usec.resize(PARTS.size())
	return true


## One tick: bodies, the top-up, the manager's `step()` (timing its own parts when `timed`), Spells,
## Combat, Feel.
func _tick(timed: bool) -> void:
	_part_usec.fill(0)
	_handler_usec = 0
	_move()
	var t: int = Time.get_ticks_usec()
	_top_up()
	_part_usec[P_SPAWN] = Time.get_ticks_usec() - t
	for seat in 4:
		_mgr.set_anchor(_casters[seat], _origin(seat))
	if timed and _mgr.step_profile.is_empty():
		_mgr.step_profile.resize(ManagerScript.PROF_PARTS)
	elif not timed:
		_mgr.step_profile.clear()
	t = Time.get_ticks_usec()
	_mgr.step(DT)
	var t1: int = Time.get_ticks_usec()
	_part_usec[P_STEP] = t1 - t - _handler_usec
	if timed:
		var profile: PackedInt64Array = _mgr.step_profile
		_part_usec[P_REFRESH] = profile[ManagerScript.PROF_REFRESH]
		_part_usec[P_COMMON] = profile[ManagerScript.PROF_COMMON]
		_part_usec[P_BEFORE] = profile[ManagerScript.PROF_BEFORE]
		_part_usec[P_HITS] = profile[ManagerScript.PROF_HITS] - _handler_usec
		_part_usec[P_KERNEL] = profile[ManagerScript.PROF_KERNEL]
		_part_usec[P_HANDBACK] = _part_usec[P_HITS] - _part_usec[P_KERNEL]
		_part_usec[P_AFTER] = profile[ManagerScript.PROF_AFTER]
		_part_usec[P_TRAILS] = profile[ManagerScript.PROF_TRAILS]
	_spells.step(DT)
	var t2: int = Time.get_ticks_usec()
	_combat.step(DT)
	var t3: int = Time.get_ticks_usec()
	_feel.step(DT)
	var t4: int = Time.get_ticks_usec()
	_part_usec[P_SPELLS] = t2 - t1
	_part_usec[P_COMBAT] = t3 - t2
	_part_usec[P_FEEL] = t4 - t3
	_step_no += 1


## Warm up, then STEPS steps with the manager's parts timed, `update_draw` and, in a window, a drawn
## frame each.
func _measure(scene: String, count: int, steps: int) -> void:
	for i in WARMUP:
		_tick(false)
	var samples: Array[PackedFloat64Array] = []
	for p in PARTS.size():
		samples.append(PackedFloat64Array())
	var handbacks := PackedFloat64Array()
	var hits := PackedFloat64Array()
	var past := PackedFloat64Array()
	var alive := PackedFloat64Array()
	var gpu := PackedFloat64Array()
	var viewport: RID = root.get_viewport_rid()
	if not _headless:
		RenderingServer.viewport_set_measure_render_time(viewport, true)
	for i in steps:
		var hits_before: int = _hits
		_tick(true)
		var t: int = Time.get_ticks_usec()
		_mgr.update_draw(1.0)
		_part_usec[P_DRAW] = Time.get_ticks_usec() - t
		for p in PARTS.size():
			samples[p].append(float(_part_usec[p]))
		handbacks.append(float(_mgr.step_profile[ManagerScript.PROF_HANDBACKS]))
		hits.append(float(_hits - hits_before))
		past.append(float(_mgr.step_profile[ManagerScript.PROF_PAST_BUDGET]))
		alive.append(float(_mgr.get_count()))
		if not _headless:
			await process_frame
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport) * 1000.0)
	_mgr.step_profile.clear()
	if not _headless:
		RenderingServer.viewport_set_measure_render_time(viewport, false)
	var label: String = "%s %d" % [scene, count]
	print("BENCH: shot scale %s: %.0f shots alive, %.1f hits a step, %.0f hand-backs a step, %.0f slots past the hit budget a step (medians)" % [label, _median(alive), _median(hits), _median(handbacks), _median(past)])
	for p in PARTS.size():
		print("BENCH: shot scale %s: %s %.3f ms (p95 %.3f)" % [label, PARTS[p], _median(samples[p]) / 1000.0, _p95(samples[p]) / 1000.0])
	if _headless:
		print("BENCH: shot scale %s: GPU frame not measured (headless)" % label)
	else:
		print("BENCH: shot scale %s: GPU frame %.3f ms (p95 %.3f)" % [label, _median(gpu) / 1000.0, _p95(gpu) / 1000.0])
	print("HITS: shot scale %s: %d hits, hash %d" % [label, _hits, _hash])
	print("DAMAGE: shot scale %s: %s" % [label, _damage_line()])


## The same scene on, with a timer between every timed event and each listener.
func _time_listeners(scene: String, count: int, steps: int) -> void:
	_timed.clear()
	for signal_name in TIMED_SIGNALS:
		var arity: int = 0
		for info: Dictionary in _bus.get_signal_list():
			if info["name"] == signal_name:
				arity = (info["args"] as Array).size()
		for connection: Dictionary in _bus.get_signal_connection_list(signal_name):
			var callable: Callable = connection["callable"]
			if int(connection["flags"]) & (CONNECT_DEFERRED | CONNECT_ONE_SHOT) != 0 or callable == Callable(self, &"_on_hit"):
				continue
			var object: Object = callable.get_object()
			var script: Script = object.get_script() as Script if object != null else null
			var who: String = script.resource_path.get_file().get_basename() if script != null and not script.resource_path.is_empty() else str(object)
			var timer := Timed.new()
			timer.key = "%s -> %s.%s" % [signal_name, who, callable.get_method()]
			timer.target = callable
			_bus.disconnect(signal_name, callable)
			_bus.connect(signal_name, Callable(timer, "on%d" % arity))
			_timed.append(timer)
	for i in steps:
		_tick(false)
	_timed.sort_custom(func(a: Timed, b: Timed) -> bool: return a.usec > b.usec)
	for timer in _timed:
		if timer.calls == 0:
			continue
		print("BENCH: shot scale listener %s %d: %s %.3f ms a step, %.1f calls a step, %.2f us a call" % [scene, count, timer.key, float(timer.usec) / float(steps) / 1000.0, float(timer.calls) / float(steps), float(timer.usec) / float(timer.calls)])
	_timed.clear()


## The crowd on its circles, as the swarm writes `position` each step.
func _move() -> void:
	if not _moving:
		return
	var t: float = float(_step_no) * DT
	for i in _bodies.size():
		var a: float = _phase[i] + t * 1.3
		_bodies[i].position = _home[i] + Vector2(cos(a), sin(a)) * 18.0


## Keep the shots at `_shots`: new ones from the wizards on a fixed fan (the golden angle), a third
## piercing, in batches as a nova spawns them.
func _top_up() -> void:
	var missing: int = _shots - _mgr.get_count()
	while missing > 0:
		var seat: int = _fired % 4
		var pierce: int = PIERCE if _fired % 3 == 0 else 0
		var n: int = mini(missing, _velocities.size())
		var velocities: PackedVector2Array = _velocities if n == _velocities.size() else _velocities.slice(0, n)
		for k in n:
			velocities[k] = Vector2.from_angle(float(_fired + k) * 2.399963) * SHOT_SPEED
		if _mgr.spawn_batch(_casters[seat], _origin(seat), velocities, SHOT_LIFE, SHOT_RADIUS, ManagerScript.LAYER_ENEMY, pierce, _tag, _slots) < 0:
			return
		_fired += n
		missing -= n


func _origin(seat: int) -> Vector2:
	return ARENA.get_center() + Vector2(-30.0 + 20.0 * float(seat), -8.0)


func _on_hit(caster: int, target: Node, point: Vector2, tag: int, _shot: int) -> void:
	var start: int = Time.get_ticks_usec()
	_hits += 1
	var which: int = _index_of.get(target.get_instance_id(), -99)
	_hash = hash([_hash, _step_no, caster, which, tag, snappedf(point.x, 0.001), snappedf(point.y, 0.001)])
	_handler_usec += Time.get_ticks_usec() - start


## Every body's damage taken: the total and a hash of the totals in body order.
func _damage_line() -> String:
	var total: float = 0.0
	var mix: int = 0
	for body in _bodies:
		var taken: float = BODY_HEALTH - _combat.health_of(body)
		total += taken
		mix = hash([mix, snappedf(taken, 0.001)])
	return "%.1f damage on %d bodies, hash %d" % [total, _bodies.size(), mix]


func _median(samples: PackedFloat64Array) -> float:
	if samples.is_empty():
		return 0.0
	var sorted: PackedFloat64Array = samples.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _p95(samples: PackedFloat64Array) -> float:
	if samples.is_empty():
		return 0.0
	var sorted: PackedFloat64Array = samples.duplicate()
	sorted.sort()
	return sorted[mini(int(float(sorted.size()) * 0.95), sorted.size() - 1)]


func _own(object: Object) -> Object:
	_owned.append(object)
	return object


func _free_all() -> void:
	if _bus != null and _bus.projectile_hit.is_connected(_on_hit):
		_bus.projectile_hit.disconnect(_on_hit)
	for object in _owned:
		if is_instance_valid(object):
			if object is Node and (object as Node).is_inside_tree():
				(object as Node).get_parent().remove_child(object as Node)
			object.free()
	_owned.clear()
	_bodies.clear()
	_index_of.clear()


func _fail(why: String) -> void:
	printerr("SHOT SCALE FAILED: %s" % why)
	_free_all()
	quit(1)
