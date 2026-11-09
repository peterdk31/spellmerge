extends SceneTree
## The native kernel against its GDScript (native/README.md): two projectile managers, one with
## the native `ShotKernel` and one without (`Projectiles.native`), are given the same seeded scene
## and stepped side by side. After every step every packed array of the two must be equal byte
## for byte (the shots, the target grid, the hit memory, the threat grid), as must
## what `update_draw` wrote into the draw batches and what `threat` answers to random asks.
## `test_projectiles_step_exact.gd` holds both to its recording too; this test also covers the
## drawing, the threat grid and many more shots (the grid and the hit-work budget both come in).
##
## The scene: walls; enemies that walk and are hit, some owned by an enemy actor; four wizards
## that walk with their anchors; bolts, runes and orbits of the four hat ramps and of the enemy
## ramp, with card looks, piercing, bouncing, homing, growing, lingering, returning and ghost shots,
## homing shots that also spiral (the kernel hands those back to their passes), sticky shots,
## shots frozen by a local stop, orbits round another shot, and now and then a solid rune (a wall:
## while one lives the hit pass and the drawing run in GDScript, so the two switch mid-run); hit
## handlers that spawn shots (which spare the body hit), remove a target, register one again
## larger and make a shot further on a ghost now and then.
##
## The scene runs twice: the native kernel on one thread, then on four (shot scale H5, rule T2).
## Both are compared with the GDScript to the bit, so one thread and several give the same bits
## too. A scene of its own grows targets mid-pass: a cell the pass already took keeps its count
## and box until the next filling, in both.
##
## Without the native module the test only says so (SPELLMERGE_NATIVE=required fails it, as in
## ci/build/build.sh).
##
## godot --headless --path . --script res://tests/core/test_native_kernel.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const NativeScript := preload("res://core/native/native.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const DT: float = 1.0 / 60.0
const STEPS: int = 150
## The native kernel's threads in each run: one, then several (more than most CI machines' cores,
## so the threads really share the work out).
const THREADS: Array[int] = [1, 4]
const ROOM: Vector2 = Vector2(960.0, 540.0)
## The draw arrays the native kernel writes into buffers of its own, so the manager's stay as they
## were: compared batch by batch in `_compare_draw`, not by name.
const OWN_BUFFERS: Array[StringName] = [&"_buffers"]
## Not compared: node instance ids (each side has its own nodes; what a shot keeps of a target is
## its key, which is compared: online-ready N5), the hit test's scratch (the native
## pass sizes it for every target at once), what only the native drawing writes, the GDScript
## catch-up's one-shot list and the GDScript drawing's sum of the tail asked for and count of the
## thinned groups' tail births (the native keeps them in locals; the sum is handed out as
## `tail_demand`, which is compared, and the births themselves are compared).
const NOT_COMPARED: Array[StringName] = [&"_target_id", &"native_threads",
		&"_cand_target", &"_cand_along", &"_cand_point", &"_cand_found", &"_draw_out", &"_one", &"_tail_wanted", &"_tail_thin"]

var _failures: Array[String] = []
## Per manager (0 the GDScript, 1 the native): its bus, actor table, targets and what it sent.
var _mgrs: Array[ManagerScript] = []
var _buses: Array[EventsScript] = []
var _tables: Array[Node] = []
var _targets: Array = [[], []]
## The most instances each batch (BATCH_*) drew at once, so every batch is seen compared.
var _batch_seen: PackedInt32Array = PackedInt32Array()
var _wizards: Array = [[], []]
var _events: Array[Array] = [[], []]
var _imp: int = -1
## Each side's bodies hang under a node of their own, so both keep the same names.
var _holders: Array[Node] = []
## Tail births laid while the tails were off (S5 step 4), and whether a frame hit the most.
var _tails_laid: int = 0
var _tails_capped: bool = false
## Whether a circling shot went round backwards after a bounce (its `_orbit_way`), so the kernel's
## orbit pass is compared on one.
var _turned_back: bool = false


func _initialize() -> void:
	await process_frame
	if not NativeScript.loaded():
		if OS.get_environment("SPELLMERGE_NATIVE") == "required":
			printerr("TEST FAILED: SPELLMERGE_NATIVE=required, but the native module is not loaded (ci/build/native.sh)")
			quit(1)
			return
		print("NOTE: the native module is not built; nothing to compare")
		print("TEST OK: native kernel (skipped)")
		quit(0)
		return
	_test_the_constants_are_checked()
	for threads: int in THREADS:
		_test_both_step_alike(threads)
		_teardown()
	_test_a_target_grown_mid_pass()
	_teardown()
	if _failures.is_empty():
		print("TEST OK: native kernel")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _teardown() -> void:
	for side in 2:
		for node: Node in _targets[side] + _wizards[side]:
			if is_instance_valid(node):
				node.free()
		(_targets[side] as Array).clear()
		(_wizards[side] as Array).clear()
	for node: Node in _mgrs + _buses + _tables + _holders:
		if is_instance_valid(node):
			node.free()
	_mgrs.clear()
	_buses.clear()
	_tables.clear()
	_holders.clear()
	_events = [[], []]


## A kernel built against other constants or members is refused, and the manager runs its GDScript:
## the kernel names every constant and member that does not match.
func _test_the_constants_are_checked() -> void:
	var kernel: Object = NativeScript.shot_kernel()
	_check(kernel != null, "the module makes a ShotKernel")
	if kernel == null:
		return
	var mgr := ManagerScript.new()
	var constants: Dictionary = mgr.native_constants()
	_check((kernel.call(&"check", constants) as PackedStringArray).is_empty(), "the manager's constants match the kernel's")
	_check((kernel.call(&"check_fields", mgr) as PackedStringArray).is_empty(), "the manager has every member the kernel reads")
	var changed: Dictionary = constants.duplicate()
	changed["EMITTING_MASK"] = int(changed["EMITTING_MASK"]) + 1
	changed.erase("S_DONE")
	var wrong: String = ", ".join(kernel.call(&"check", changed) as PackedStringArray)
	_check("EMITTING_MASK" in wrong and "S_DONE" in wrong, "a changed and a missing constant are named (%s)" % wrong)
	var stranger := Node2D.new()
	_check("_pos" in ", ".join(kernel.call(&"check_fields", stranger) as PackedStringArray), "a missing member is named")
	stranger.free()
	_check(mgr.is_native(), "a new manager runs the native kernel")
	mgr.native = false
	_check(not mgr.is_native(), "native off runs the GDScript")
	mgr.native = true
	_check(mgr.is_native(), "and on again the kernel")
	mgr.free()


func _test_both_step_alike(threads: int) -> void:
	for side in 2:
		var bus := EventsScript.new()
		var table: ActorSeats.ActorsScript = ActorSeats.table()
		_imp = ActorSeats.enemy(table)
		var mgr := ManagerScript.new()
		mgr.native_threads = threads
		mgr.native = side == 1
		mgr.actors = table
		mgr.events = bus
		root.add_child(mgr)
		mgr.set_cap(1500)
		mgr.set_bounds(Rect2(Vector2.ZERO, ROOM))
		# Every card body's pair of batches (`register_body`): quad bodies and head bodies in turn
		# (card-looks phase 1). The shots below take them in turn, still and flying alike, so some
		# draw in their body's pair and some, whose motion is not written as their body's mesh, plain.
		var bodies: Array[Shader] = _body_shaders()
		for n in bodies.size():
			mgr.register_body(bodies[n], ManagerScript.MESH_QUAD if n % 2 == 0 else ManagerScript.MESH_HEAD)
		# The births are handed out (as Feel's motes take them), from the same dice on both sides:
		# with the tails off the drawing lays the tails as births (S5 step 4), compared to the bit.
		mgr.spark_motes = true
		mgr._spark_rng.seed = 11
		mgr.set_walls([Rect2(0, 0, 960, 24), Rect2(0, 516, 960, 24), Rect2(0, 0, 24, 540), Rect2(936, 0, 24, 540),
				Rect2(300, 200, 40, 40), Rect2(620, 300, 40, 40), Rect2(500, 150, 24, 24)] as Array[Rect2])
		_mgrs.append(mgr)
		_buses.append(bus)
		_tables.append(table)
		var holder := Node2D.new()
		root.add_child(holder)
		_holders.append(holder)
		for i in 60:
			var at: Vector2 = Vector2(480.0, 270.0) + Vector2(float(i % 10) * 18.0 - 90.0, float(i / 10) * 18.0 - 45.0)
			var owner: int = _imp if i % 7 == 0 else EventsScript.NO_PLAYER
			(_targets[side] as Array).append(_add_body(side, "enemy%d" % i, at, 7.0 + float(i % 4), ManagerScript.LAYER_ENEMY, owner))
		for seat in 4:
			(_wizards[side] as Array).append(_add_body(side, "wizard%d" % seat, Vector2(160.0 + float(seat) * 200.0, 440.0), 8.0, ManagerScript.LAYER_PLAYER, seat))
		bus.projectile_hit.connect(_on_hit.bind(side))
		bus.projectile_expired.connect(_on_expired.bind(side))
	_check(_mgrs[1].is_native() and not _mgrs[0].is_native(), "one native manager, one GDScript")
	# A build without threads (the web's) runs every loop on one.
	var running: int = _mgrs[1].native_thread_count()
	_check(running == threads or running == 1, "the native kernel runs on %d threads (%d)" % [threads, running])
	if running < threads:
		print("NOTE: this build of the native module has no threads; %d asked, 1 runs" % threads)
	_batch_seen.resize(_mgrs[1].batch_count())
	_batch_seen.fill(0)
	_tails_laid = 0
	_tails_capped = false
	_turned_back = false
	var queries := RandomNumberGenerator.new()
	queries.seed = 7
	for step in STEPS:
		for side in 2:
			_drive(side, step)
		for side in 2:
			_events[side].clear()
			_mgrs[side].step(DT)
		if _events[0] != _events[1]:
			_failures.append("step %d: the same events (%s)" % [step, _first_difference(_events[0], _events[1]) + " / " + _first_difference(_events[1], _events[0])])
		_compare_arrays(step)
		var fraction: float = float(step % 7) / 7.0
		for side in 2:
			_mgrs[side].update_draw(fraction)
		_compare_draw(step)
		_tails_laid += _mgrs[1].tail_births
		_tails_capped = _tails_capped or (_mgrs[1].tail_births == _mgrs[1].tail_births_cap and _mgrs[1].tail_spacing > ManagerScript.TAIL_SPACING)
		_turned_back = _turned_back or _mgrs[1]._orbit_way.has(-1.0)
		# Threat asks: enough in a step for the grid (from the third), and some in a step without it.
		var asks: int = 6 if step % 3 != 2 else 1
		for n in asks:
			var point := Vector2(queries.randf_range(30.0, 930.0), queries.randf_range(30.0, 510.0))
			var radius: float = queries.randf_range(4.0, 40.0)
			var team: int = [-1, 0, 1][queries.randi() % 3]
			var own: int = queries.randi_range(-1, 5)
			var horizon: float = queries.randf_range(0.1, 1.5)
			var a: float = _mgrs[0].threat(point, radius, team, own, horizon)
			var b: float = _mgrs[1].threat(point, radius, team, own, horizon)
			_check(var_to_bytes(a) == var_to_bytes(b) and _mgrs[0].threat_slot == _mgrs[1].threat_slot
					and var_to_bytes(_mgrs[0].threat_away) == var_to_bytes(_mgrs[1].threat_away),
					"step %d ask %d: the same threat (%s %d %s / %s %d %s)" % [step, n, a, _mgrs[0].threat_slot, _mgrs[0].threat_away, b, _mgrs[1].threat_slot, _mgrs[1].threat_away])
		_compare_arrays(step)
		if _failures.size() > 8:
			return
	_check(_mgrs[1].get_count() > 400, "the scene keeps hundreds of shots (%d)" % _mgrs[1].get_count())
	for batch in _mgrs[1].batch_count():
		_check(_batch_seen[batch] > 0, "batch %d was drawn and compared" % batch)
	_check(_mgrs[1].drawn > 300, "and draws them (%d)" % _mgrs[1].drawn)
	_check(_tails_laid > 0 and _tails_capped, "the tails were laid as births (%d), past the most too" % _tails_laid)
	_check(_turned_back, "a circling shot bounced and went round backwards")



## The card bodies of the scene: plain canvas-item shaders, made once.
const SCENE_BODIES: int = 6
static var _bodies: Array[Shader] = []


static func _body_shaders() -> Array[Shader]:
	if _bodies.is_empty():
		for n in SCENE_BODIES:
			var shader := Shader.new()
			shader.code = "shader_type canvas_item;\n// body %d\n" % n
			_bodies.append(shader)
	return _bodies


## A hit that grows targets mid-pass: the shots after it in the pass must see each target's cell as
## the GDScript does. It keeps a cell's count and box once taken in a filling (`_cell_info`), so a
## shot passing the grown `near` (whose cell an earlier shot of the pass took) still sees its old
## box and misses it, and one passing the grown `far` (whose cell nothing took yet) sees the new
## one and hits it.
func _test_a_target_grown_mid_pass() -> void:
	for side in 2:
		var bus := EventsScript.new()
		var table: ActorSeats.ActorsScript = ActorSeats.table()
		var mgr := ManagerScript.new()
		mgr.native_threads = THREADS[THREADS.size() - 1]
		mgr.native = side == 1
		mgr.actors = table
		mgr.events = bus
		root.add_child(mgr)
		mgr.set_cap(600)
		mgr.set_bounds(Rect2(Vector2.ZERO, ROOM))
		_mgrs.append(mgr)
		_buses.append(bus)
		_tables.append(table)
		var holder := Node2D.new()
		root.add_child(holder)
		_holders.append(holder)
		var first: Node2D = _add_body(side, "first", Vector2(100.0, 270.0), 8.0, ManagerScript.LAYER_ENEMY, EventsScript.NO_PLAYER)
		var near: Node2D = _add_body(side, "near", Vector2(500.0, 270.0), 8.0, ManagerScript.LAYER_ENEMY, EventsScript.NO_PLAYER)
		var far: Node2D = _add_body(side, "far", Vector2(800.0, 270.0), 8.0, ManagerScript.LAYER_ENEMY, EventsScript.NO_PLAYER)
		(_targets[side] as Array).append_array([first, near, far])
		bus.projectile_hit.connect(_on_grow_hit.bind(side, first, [near, far]))
		# First in the pass: a shot past `near` (its cell is taken, its box as it is), then one into `first`.
		mgr.spawn(0, Vector2(440.0, 300.0), Vector2(600.0, 0.0), 1.0, 3.0, ManagerScript.LAYER_ENEMY)
		mgr.spawn(0, Vector2(85.0, 270.0), Vector2(900.0, 0.0), 1.0, 3.0, ManagerScript.LAYER_ENEMY)
		# Then shots 40 px off `near` and `far`: only a grown one reaches them.
		for i in 200:
			mgr.spawn(0, Vector2(470.0 + float(i) * 0.3, 310.0), Vector2(600.0, 0.0), 1.0, 3.0, ManagerScript.LAYER_ENEMY)
			mgr.spawn(0, Vector2(770.0 + float(i) * 0.3, 310.0), Vector2(600.0, 0.0), 1.0, 3.0, ManagerScript.LAYER_ENEMY)
	for step in 3:
		for side in 2:
			_events[side].clear()
			_mgrs[side].step(DT)
		if _events[0] != _events[1]:
			_failures.append("grown mid-pass, step %d: the same events (%s)" % [step, _first_difference(_events[0], _events[1]) + " / " + _first_difference(_events[1], _events[0])])
		_compare_arrays(step)
		if step == 0:
			var on_near: int = _events[0].filter(func(e: String) -> bool: return " near " in e).size()
			var on_far: int = _events[0].filter(func(e: String) -> bool: return " far " in e).size()
			_check(on_near == 0 and on_far > 100, "after the hit, the shots miss the grown near (%d hits) and hit the grown far (%d)" % [on_near, on_far])


func _on_grow_hit(caster: int, target: Node, position: Vector2, tag: int, shot: int, side: int, first: Node2D, grown: Array) -> void:
	_events[side].append("hit %d %s %s %d %d" % [caster, (target as Node).name, var_to_str(position), tag, shot])
	if target == first:
		for node: Node2D in grown:
			_mgrs[side].add_target(node, 60.0)


func _add_body(side: int, name: String, at: Vector2, radius: float, layer: int, owner: int) -> Node2D:
	var node := Node2D.new()
	node.name = name
	_holders[side].add_child(node)
	node.global_position = at
	_mgrs[side].add_target(node, radius, layer, owner)
	return node


## What happens before a step, the same on both sides: bodies walk, shots are cast.
func _drive(side: int, step: int) -> void:
	var m: ManagerScript = _mgrs[side]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + step
	for seat in 4:
		var node: Node2D = _wizards[side][seat]
		node.global_position = Vector2(160.0 + float(seat) * 200.0, 440.0) + Vector2.from_angle(float(step) * 0.07 + float(seat)) * 20.0
		m.set_anchor(seat, node.global_position)
	var targets: Array = _targets[side]
	for i in targets.size():
		var node: Node2D = targets[i]
		if is_instance_valid(node):
			node.global_position += Vector2.from_angle(float(step) * 0.05 + float(i)) * 0.6
	if step == 80:
		# Fewer tail births than the shots ask for: the most is kept and the spacing widens.
		m.tail_births_cap = 60
	if step == 45:
		m.set_anchor(_imp, Vector2(480.0, 140.0))
	for i in 40 if step < 100 else 8:
		var caster: int = _imp if i % 5 == 4 else i % 4
		var from: Vector2 = Vector2(160.0 + float(i % 4) * 200.0, 420.0) if caster != _imp else Vector2(480.0, 120.0)
		var velocity: Vector2 = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 420.0)
		var kind: int = rng.randi() % 10
		var slot: int = -1
		if kind == 0:
			slot = m.spawn(caster, from + Vector2(rng.randf_range(-60, 60), rng.randf_range(-200, 0)), Vector2.ZERO, rng.randf_range(0.5, 2.0), rng.randf_range(4.0, 14.0), ManagerScript.ACTOR_LAYERS, 2, 1, ManagerScript.MOTION_STILL)
			if slot >= 0:
				# A rune, or one of the card bodies (their batches, the enemy ramp's too).
				m.set_form(slot, &"", slot % (SCENE_BODIES + 1))
		elif kind == 1:
			# A shot set circling its caster's body (orbit as a modifier, 5A): most are bolts cast with
			# a speed, turned by it over their radius plus a drift; some have no speed and only drift.
			# (The speed curve below takes them too: the orbit pass reads `_curve_factor`.)
			var who: int = caster if caster != _imp else 0
			var round_radius: float = rng.randf_range(20.0, 60.0)
			var angle: float = rng.randf() * TAU
			var drift: float = rng.randf_range(-4.0, 4.0)
			var own_speed: Vector2 = velocity if rng.randf() < 0.75 else Vector2.ZERO
			slot = m.spawn(who, m.get_anchor(who), own_speed, rng.randf_range(0.5, 2.0), rng.randf_range(1.5, 6.0), ManagerScript.LAYER_ENEMY, 1000, 1)
			if slot >= 0 and not m.set_orbit(slot, round_radius, angle, drift):
				_failures.append("step %d: set_orbit refused a live straight shot" % step)
			if slot >= 0 and slot % 2 == 0:
				# Some bounce: a wall across the circle (the block by the imp's anchor) turns them back round.
				m.set_bounce(slot, 3)
			if slot >= 0 and slot % 3 == 0:
				# An orbit shot of a card body: a head body's pair, or plain for a quad body.
				m.set_form(slot, &"", slot % (SCENE_BODIES + 1))
		else:
			slot = m.spawn(caster, from, velocity, rng.randf_range(0.3, 2.5), rng.randf_range(1.0, 9.0), ManagerScript.ACTOR_LAYERS, rng.randi() % 4, 1 if kind != 9 else 2)
			if slot >= 0 and kind == 8:
				# A flying shot of a card body (a bolt's own head): a head body's pair, or plain.
				m.set_form(slot, &"", slot % (SCENE_BODIES + 1))
		if slot < 0:
			continue
		if slot % 4 == 1:
			# A card's light (card-looks phase 1b): written into the row's free floats on both sides.
			m.set_light(slot, 0.25 + 0.25 * float(slot % 7), 0.5 + 0.25 * float(slot % 5))
		# Any look bits, the enemy ramp's flag among them (`ramp_look`), so a new kind is covered too.
		m.set_look(slot, rng.randi() & ((1 << ManagerScript.LOOK_MAX_KINDS) - 1) if rng.randf() < 0.6 else 0)
		if rng.randf() < 0.4:
			m.set_core(slot, Color(rng.randf(), rng.randf(), rng.randf()))
		match kind:
			2:
				m.set_bounce(slot, 3)
			3:
				m.set_homing(slot, 3.0, 150.0)
			4:
				m.set_growth(slot, 1.6)
			5:
				m.set_ghost(slot)
			6:
				m.set_linger(slot, 0.2)
			7:
				m.set_spiral(slot, 8.0)
			8:
				# Out and back to its caster, some homing on the way (return bends toward the target).
				m.set_return(slot)
				if rng.randf() < 0.5:
					m.set_homing(slot, 2.5, 140.0)
		# A speed curve on any of them (a flying or circling shot takes it): it sets the speed of the
		# kinds above before homing turns and spiral weaves it, a returning one turns with its speed,
		# and a circling one turns by it. Circling shots take one more often, so many are compared.
		if rng.randf() < (0.5 if kind == 1 else 0.2):
			m.set_speed_curve(slot, rng.randf_range(0.3, 5.0), rng.randf_range(0.0, 2.0), rng.randf_range(0.3, 3.0))
		# Rarer kinds, from the same draws on both sides.
		var extra: float = rng.randf()
		if extra < 0.05 and kind == 3:
			m.set_spiral(slot, 6.0)
		elif extra < 0.1:
			m.set_sticky(slot, 0.4)
		elif extra < 0.14:
			m.freeze_shot(slot, rng.randf_range(0.05, 0.3))
		elif extra < 0.17 and kind == 1 and slot > 0 and m.is_alive(slot - 1):
			# An orbit round the shot before it, for as long as that one flies.
			m.set_caster_shot(slot, slot - 1)
		elif extra < 0.2 and kind == 0 and step % 25 < 5:
			m.set_solid(slot, Vector2.from_angle(rng.randf() * TAU), 3, 10.0)


func _on_hit(caster: int, target: Node, position: Vector2, tag: int, shot: int, side: int) -> void:
	_events[side].append("hit %d %s %s %d %d" % [caster, (target as Node).name, var_to_str(position), tag, shot])
	var m: ManagerScript = _mgrs[side]
	if tag == 2:
		# A splitting shot: two children from the hit, which spare the body they burst from until clear
		# of it (as a payload does).
		for k in 2:
			var child: int = m.spawn(caster, position, Vector2.from_angle(float(shot + k) * 2.1) * 200.0, 0.4, 3.0, ManagerScript.LAYER_ENEMY, 0, 1)
			m.exclude(child, target)
	if shot % 97 == 13 and target.name.begins_with("enemy"):
		# Now and then a hit takes its target away (it died).
		m.remove_target(target as Node2D)
	elif shot % 89 == 7 and target.name.begins_with("enemy"):
		# Or makes it much larger (registered again) for the shots after it.
		m.add_target(target as Node2D, 60.0)
	if shot % 13 == 5:
		# Or changes a shot further on in the pass (a ghost now, pulled a little, as a pull would).
		var later: int = (shot + 31) % m.get_cap()
		if m.set_ghost(later):
			m._pos[later] += Vector2(6.0, -4.0)


func _on_expired(caster: int, position: Vector2, tag: int, shot: int, side: int) -> void:
	_events[side].append("expired %d %s %d %d" % [caster, var_to_str(position), tag, shot])


## Every packed array (and int and float) member of the two managers, byte for byte.
func _compare_arrays(step: int) -> void:
	for prop: Dictionary in _mgrs[0].get_property_list():
		var name: StringName = prop["name"]
		var type: int = prop["type"]
		if (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or name in OWN_BUFFERS or name in NOT_COMPARED:
			continue
		if type < TYPE_PACKED_BYTE_ARRAY and type != TYPE_INT and type != TYPE_FLOAT and type != TYPE_VECTOR2:
			continue
		var a: Variant = _mgrs[0].get(name)
		var b: Variant = _mgrs[1].get(name)
		if var_to_bytes(a) != var_to_bytes(b):
			_failures.append("step %d: %s differs (GDScript %s, native %s)" % [step, name, _first_difference(a, b), _first_difference(b, a)])


func _first_difference(a: Variant, b: Variant) -> String:
	if typeof(a) < TYPE_ARRAY:
		return str(a)
	if a.size() != b.size():
		return "size %d" % a.size()
	for i in a.size():
		if var_to_bytes(a[i]) != var_to_bytes(b[i]):
			return "[%d] = %s" % [i, var_to_str(a[i])]
	return "?"


## What the two drew: the counts, the shares and every written instance of every batch.
func _compare_draw(step: int) -> void:
	var a: ManagerScript = _mgrs[0]
	var b: ManagerScript = _mgrs[1]
	_check(a.drawn == b.drawn and a.drawn_enemy == b.drawn_enemy,
			"step %d: the same drawn counts (%d %d / %d %d)" % [step, a.drawn, a.drawn_enemy, b.drawn, b.drawn_enemy])
	_check(a.particle_demand == b.particle_demand, "step %d: the same demand" % step)
	for batch in b.batch_count():
		var count_a: int = a._nodes[batch].multimesh.visible_instance_count
		var count_b: int = b._nodes[batch].multimesh.visible_instance_count
		_check(count_a == count_b, "step %d batch %d: the same instances (%d / %d)" % [step, batch, count_a, count_b])
		_batch_seen[batch] = maxi(_batch_seen[batch], count_a)
		var buffer_a: PackedFloat32Array = a._buffers[batch]
		# The native side drew into the kernel's buffers, or into its own while a solid shot lived.
		var buffer_b: PackedFloat32Array = b._kernel.call(&"buffer", batch) if not b._any_solid else b._buffers[batch]
		var floats: int = mini(count_a, count_b) * ManagerScript.DRAW_STRIDE
		if buffer_a.size() < floats or buffer_b.size() < floats:
			_failures.append("step %d batch %d: a buffer too small" % [step, batch])
			continue
		if var_to_bytes(buffer_a.slice(0, floats)) != var_to_bytes(buffer_b.slice(0, floats)):
			_failures.append("step %d batch %d: the instances differ (%s / %s)" % [step, batch, _first_difference(buffer_a.slice(0, floats), buffer_b.slice(0, floats)), _first_difference(buffer_b.slice(0, floats), buffer_a.slice(0, floats))])
