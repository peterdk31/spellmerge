extends "res://tests/support/suite.gd"
## The native kernel against its GDScript (native/README.md): two projectile managers, one with
## the native `ShotKernel` and one without (`Projectiles.native`), are given the same seeded scene
## and stepped side by side. After every step every packed array of the two must be equal byte
## for byte (the shots, the target grid, the hit memory, the threat grid), as must
## what `update_draw` wrote into the draw batches and what `threat` answers to random asks.
## `test_projectiles_step_exact.gd` holds both to its recording too; this test also covers the
## drawing, the threat grid and many more shots (the grid and the hit-work budget both come in).
##
## The scene: walls; enemies that walk and are hit, some owned by an enemy actor, some hit as boxes
## (`HitShape`: homing picks them, shots pass their corners); four wizards
## that walk with their anchors; two props of the world's team (props W4), a long box and a tall
## rounded one, targets no homing shot picks, that cast now and then from their own body (their
## ground is the walking bodies' alone: shots never see it); bolts, runes and orbits of the four hat ramps and of the enemy
## ramp, with card looks, piercing, bouncing, homing, growing, lingering, returning and ghost shots,
## homing shots that also spiral (the kernel hands those back to their passes), sticky shots,
## shots frozen by a local stop, orbits round another shot, and now and then a solid rune (a wall:
## while one lives the hit pass and the drawing run in GDScript, so the two switch mid-run); hit
## handlers that spawn shots (which spare the body hit), remove a target, register one again
## larger and make a later shot a ghost now and then, after the pass (the merged hits are sent at
## its end); and expiry handlers that do the same during it (a shot's end goes out in the pass), so
## the kernel resumes after a target is taken away or grown, or a later shot changed, mid-pass.
##
## The tests: the kernel's own checks of the manager's constants and members, one per test; the
## scene stepped with the native kernel on one thread, and (a test of its own) on four (shot scale
## H5, rule T2), each compared with the GDScript to the bit, so one thread and several give the
## same bits too, each ending with checks that the scene reached what it is meant to compare (a
## scene run takes seconds, so the comparison and those checks share one run); and a scene of its
## own that grows targets mid-pass: both step alike through it, and a cell the pass already took
## keeps its count and box until the next filling. Each test builds and frees its own managers.
## The file runs as two processes (`unit-test-shards`), the two scene runs in different ones.
##
## Without the native module every test only says so (SPELLMERGE_NATIVE=required fails them, as
## in ci/build/build.sh).
# unit-test-shards: 2

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
const NOT_COMPARED: Array[StringName] = [&"_target_id", &"native_threads", &"step_profile", &"profile_clock", &"merged_turns", &"merged_opens",
		&"_cand_target", &"_cand_along", &"_cand_point", &"_cand_found", &"_draw_out", &"_one", &"_tail_wanted", &"_tail_thin"]

## Per manager (0 the GDScript, 1 the native): its bus, actor table, targets and what it sent.
var _mgrs: Array[ManagerScript] = []
var _targets: Array = [[], []]
## The most instances each batch (BATCH_*) drew at once, so every batch is seen compared.
var _batch_seen: PackedInt32Array = PackedInt32Array()
var _wizards: Array = [[], []]
var _events: Array[Array] = [[], []]
var _imp: int = -1
## The props' actor ids (the world's team), their places and their hit shapes: a long box, and a
## tall one rounded by a radius (`HitShape`).
var _props: PackedInt32Array = PackedInt32Array()
const PROP_AT: Array[Vector2] = [Vector2(250.0, 330.0), Vector2(700.0, 220.0)]
const PROP_HALF: Array[Vector2] = [Vector2(40.0, 8.0), Vector2(10.0, 24.0)]
const PROP_RADIUS: Array[float] = [0.0, 3.0]
## Every BOX_EVERY-th enemy is hit as a box this far either way (rounded by its radius).
const BOX_EVERY: int = 6
const ENEMY_HALF: Vector2 = Vector2(9.0, 5.0)
## Each side's props' bodies.
var _prop_nodes: Array = [[], []]
## Each side's bodies hang under a node of their own, so both keep the same names.
var _holders: Array[Node] = []
## Tail births laid while the tails were off (S5 step 4), and whether a frame hit the most.
var _tails_laid: int = 0
var _tails_capped: bool = false
## Whether a circling shot went round backwards after a bounce (its `_orbit_way`), so the kernel's
## orbit pass is compared on one.
var _turned_back: bool = false
## Whether a still body circled (5B), so the kernel drew a moving quad.
var _circled_quad: bool = false
## The box bodies the native side hit, by name (props and box enemies).
var _box_hits: Array[String] = []
## How many differences the running test found: a scene stops at the ninth (the rest follow).
var _differences: int = 0
## The native side's hand-backs counted over the steps, and the hits sent (each merged hit counts
## its shots).
var _handbacks: int = 0
var _hits_sent: int = 0

## The card bodies of the scene: plain canvas-item shaders, made once per file.
const SCENE_BODIES: int = 6
var _bodies: Array[Shader] = []


func before_each() -> void:
	_handbacks = 0
	_hits_sent = 0
	_mgrs = []
	_targets = [[], []]
	_wizards = [[], []]
	_events = [[], []]
	_prop_nodes = [[], []]
	_holders = []
	_props = PackedInt32Array()
	_imp = -1
	_batch_seen = PackedInt32Array()
	_tails_laid = 0
	_tails_capped = false
	_turned_back = false
	_circled_quad = false
	_box_hits = []
	_differences = 0


## Whether the native module is here to compare; without it a test only says so, and fails when
## SPELLMERGE_NATIVE=required (ci/build/build.sh).
func _native_loaded() -> bool:
	if NativeScript.loaded():
		return true
	check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded (ci/build/native.sh)")
	print("NOTE: the native module is not built; nothing to compare")
	return false


## Records a difference between the two sides.
func _differ(message: String) -> void:
	_differences += 1
	check(false, message)


func _body_shaders() -> Array[Shader]:
	if _bodies.is_empty():
		for n in SCENE_BODIES:
			var shader := Shader.new()
			shader.code = "shader_type canvas_item;\n// body %d\n" % n
			_bodies.append(shader)
	return _bodies


## A manager for `side` (1 the native kernel) on `threads` threads, in the tree, with its own bus,
## actor table (wizards at 0-3) and holder for its bodies; all freed after the test.
func _manager(side: int, threads: int, cap: int, table: ActorSeats.ActorsScript) -> ManagerScript:
	var bus: EventsScript = own(EventsScript.new()) as EventsScript
	own(table)
	var mgr: ManagerScript = own(ManagerScript.new()) as ManagerScript
	mgr.native_threads = threads
	mgr.native = side == 1
	mgr.actors = table
	mgr.events = bus
	root.add_child(mgr)
	mgr.set_cap(cap)
	mgr.set_bounds(Rect2(Vector2.ZERO, ROOM))
	_mgrs.append(mgr)
	var holder: Node2D = own(Node2D.new()) as Node2D
	root.add_child(holder)
	_holders.append(holder)
	return mgr


# --- The kernel's checks of the manager -------------------------------------
# A kernel built against other constants or members is refused, and the manager runs its GDScript:
# the kernel names every constant and member that does not match.

func test_the_module_makes_a_shot_kernel() -> void:
	if not _native_loaded():
		return
	check(NativeScript.shot_kernel() != null, "the module makes a ShotKernel")


func test_the_managers_constants_match_the_kernels() -> void:
	if not _native_loaded():
		return
	var mgr: ManagerScript = own(ManagerScript.new()) as ManagerScript
	var kernel: Object = NativeScript.shot_kernel()
	check((kernel.call(&"check", mgr.native_constants()) as PackedStringArray).is_empty(), "the manager's constants match the kernel's")


func test_the_manager_has_every_member_the_kernel_reads() -> void:
	if not _native_loaded():
		return
	var mgr: ManagerScript = own(ManagerScript.new()) as ManagerScript
	var kernel: Object = NativeScript.shot_kernel()
	check((kernel.call(&"check_fields", mgr) as PackedStringArray).is_empty(), "the manager has every member the kernel reads")


func test_every_mismatched_constant_is_named() -> void:
	if not _native_loaded():
		return
	var mgr: ManagerScript = own(ManagerScript.new()) as ManagerScript
	var changed: Dictionary = mgr.native_constants().duplicate()
	changed["EMITTING_MASK"] = int(changed["EMITTING_MASK"]) + 1
	changed.erase("S_DONE")
	var wrong: String = ", ".join(NativeScript.shot_kernel().call(&"check", changed) as PackedStringArray)
	check("EMITTING_MASK" in wrong and "S_DONE" in wrong, "a changed and a missing constant are named (%s)" % wrong)


func test_a_missing_member_is_named() -> void:
	if not _native_loaded():
		return
	var stranger: Node2D = own(Node2D.new()) as Node2D
	check("_pos" in ", ".join(NativeScript.shot_kernel().call(&"check_fields", stranger) as PackedStringArray), "a missing member is named")


## The hit pass reads the room grid's walls from the grid (`RoomGrid`, hit batch B1): a manager
## without one is named, and a real one's grid has every member the kernel reads.
func test_the_room_grid_the_kernel_reads_is_checked() -> void:
	if not _native_loaded():
		return
	var stranger: Node2D = own(Node2D.new()) as Node2D
	check("_room_grid" in ", ".join(NativeScript.shot_kernel().call(&"check_fields", stranger) as PackedStringArray), "a manager without a room grid is named")
	var mgr: ManagerScript = own(ManagerScript.new()) as ManagerScript
	check_equal(NativeScript.shot_kernel().call(&"check_fields", mgr) as PackedStringArray, PackedStringArray(), "a real manager and its grid have every member")


## The hit pass reads the merged hits from the hit batch (`HitBatch`, hit batch A1): a manager without
## one is named.
func test_the_hit_batch_the_kernel_reads_is_checked() -> void:
	if not _native_loaded():
		return
	var mgr: ManagerScript = own(ManagerScript.new()) as ManagerScript
	mgr._hit_batch = null
	check("_hit_batch" in ", ".join(NativeScript.shot_kernel().call(&"check_fields", mgr) as PackedStringArray), "a manager without a hit batch is named")


func test_a_new_manager_runs_the_native_kernel() -> void:
	if not _native_loaded():
		return
	var mgr: ManagerScript = own(ManagerScript.new()) as ManagerScript
	check(mgr.is_native(), "a new manager runs the native kernel")


func test_the_native_switch_picks_the_gdscript_or_the_kernel() -> void:
	if not _native_loaded():
		return
	var mgr: ManagerScript = own(ManagerScript.new()) as ManagerScript
	mgr.native = false
	check(not mgr.is_native(), "native off runs the GDScript")
	mgr.native = true
	check(mgr.is_native(), "and on again the kernel")


# --- The scene, stepped side by side ----------------------------------------

## The scene, its hits merged: the kernel takes each shot whose hits only add to merged hits of the
## pass (`HitPass::merge_hits`), with bodies the pass kills passed over (`hit_room_asked`,
## `hit_damage_asked`, answered alike on both sides), to the bit as the GDScript does.
func test_one_thread_steps_like_the_gdscript() -> void:
	if not _native_loaded():
		return
	_step_the_scene_alike(1)
	_check_the_kernel_merged()


func test_several_threads_step_like_the_gdscript() -> void:
	if not _native_loaded():
		return
	_step_the_scene_alike(THREADS[THREADS.size() - 1])
	_check_the_kernel_merged()


## The merged scene reached the kernel's own merging: shots whose hits it merged itself, among the
## ones handed back to GDScript.
func _check_the_kernel_merged() -> void:
	check(_hits_sent > 0, "shots hit (%d)" % _hits_sent)
	check(_mgrs[1].merged_turns > 100, "the kernel merged shots' hits itself (%d turns; %d hand-backs)" % [_mgrs[1].merged_turns, _handbacks])
	check_equal(_mgrs[0].merged_turns, 0, "the GDScript side counts none")
	check(_mgrs[1].merged_opens > 0, "the kernel opened merged hits itself (%d), each a body and a spell the pass had asked of" % _mgrs[1].merged_opens)


## A merged scene's answers to `hit_room_asked` and `hit_damage_asked`, the same on both sides: a
## body's health by its name, a hit's damage by its tag, so some bodies die in a pass and the shots
## after pass them.
func _on_room_asked(target: Node, room: HitRoom) -> void:
	var kind: int = String(target.name).hash()
	# Some bodies no hit takes health from (unknown: never dead in the pass).
	if kind % 7 == 0:
		return
	room.known = true
	room.health = 15.0 + float(kind % 4) * 10.0
	# A barrier on some bodies that spares one of the two spells: its charges take the other's
	# first hits whole (hit batch A1).
	if kind % 3 == 0:
		room.charges = 2
		room.spares = 2
	# A hex on some (30: a hit of 3 or 6 grows by an amount whose sum's order shows in the last bit),
	# and on some one that takes a hit's damage to 0 (-100: it deals none, and meets no barrier).
	if kind % 5 == 1:
		room.hexed = true
		room.hex = 30.0
	elif kind % 5 == 3:
		room.hexed = true
		room.hex = -100.0


func _on_damage_asked(tag: int, _shot: int, answer: HitDamage) -> void:
	answer.damage = 3.0 * float(tag % 3)


## Builds the scene on both sides, the native one on `threads` threads, and steps it STEPS times,
## comparing after each step; then checks the scene reached what it is meant to compare.
func _step_the_scene_alike(threads: int) -> void:
	for side in 2:
		var table: ActorSeats.ActorsScript = ActorSeats.table()
		_imp = ActorSeats.enemy(table)
		_props.clear()
		for at in PROP_AT:
			_props.append(table.open(ActorSeats.ActorsScript.TEAM_WORLD, ActorSeats.ActorsScript.RAMP_ENEMY))
		var mgr: ManagerScript = _manager(side, threads, 1500, table)
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
		for i in 60:
			var at: Vector2 = Vector2(480.0, 270.0) + Vector2(float(i % 10) * 18.0 - 90.0, float(i / 10) * 18.0 - 45.0)
			var owner_id: int = _imp if i % 7 == 0 else EventsScript.NO_PLAYER
			var half: Vector2 = ENEMY_HALF if i % BOX_EVERY == 3 else Vector2.ZERO
			(_targets[side] as Array).append(_add_body(side, "enemy%d" % i, at, 7.0 + float(i % 4) if half == Vector2.ZERO else 2.0, ManagerScript.LAYER_ENEMY, owner_id, half))
		for seat in 4:
			(_wizards[side] as Array).append(_add_body(side, "wizard%d" % seat, Vector2(160.0 + float(seat) * 200.0, 440.0), 8.0, ManagerScript.LAYER_PLAYER, seat))
		for n in _props.size():
			(_prop_nodes[side] as Array).append(_add_body(side, "prop%d" % n, PROP_AT[n], PROP_RADIUS[n], ManagerScript.LAYER_ENEMY, _props[n], PROP_HALF[n]))
		mgr.events.projectile_hit.connect(_on_hit.bind(side))
		mgr.events.projectile_expired.connect(_on_expired.bind(side))
		mgr.events.hit_room_asked.connect(_on_room_asked)
		mgr.events.hit_damage_asked.connect(_on_damage_asked)
		mgr.shot_ended.connect(func(tag: int) -> void: _events[side].append("ended %d" % tag))
	check(_mgrs[1].is_native() and not _mgrs[0].is_native(), "one native manager, one GDScript")
	# A build without threads (the web's) runs every loop on one.
	var running: int = _mgrs[1].native_thread_count()
	check(running == threads or running == 1, "the native kernel runs on %d threads (%d)" % [threads, running])
	if running < threads:
		print("NOTE: this build of the native module has no threads; %d asked, 1 runs" % threads)
	_batch_seen.resize(_mgrs[1].batch_count())
	_batch_seen.fill(0)
	var queries := RandomNumberGenerator.new()
	queries.seed = 7
	for step in STEPS:
		for side in 2:
			_drive(side, step)
		if step % 10 == 4:
			# Some shots hit alone (a relay's own profile, `set_hits_alone`), alike on both sides.
			for side in 2:
				for slot in range(step % 11, _mgrs[side]._high, 11):
					_mgrs[side].set_hits_alone(slot)
		if _mgrs[1].step_profile.is_empty():
			# The native side counts its hand-backs (`step_profile`, which plays as the plain step).
			_mgrs[1].step_profile.resize(ManagerScript.PROF_PARTS)
			_mgrs[1].profile_clock = Time.get_ticks_usec
		for side in 2:
			_events[side].clear()
			_mgrs[side].step(DT)
		_handbacks += _mgrs[1].step_profile[ManagerScript.PROF_HANDBACKS]
		if _events[0] != _events[1]:
			_differ("step %d: the same events (%s)" % [step, _first_difference(_events[0], _events[1]) + " / " + _first_difference(_events[1], _events[0])])
		_compare_arrays(step)
		var fraction: float = float(step % 7) / 7.0
		for side in 2:
			_mgrs[side].update_draw(fraction)
		_compare_draw(step)
		_tails_laid += _mgrs[1].tail_births
		_tails_capped = _tails_capped or (_mgrs[1].tail_births == _mgrs[1].tail_births_cap and _mgrs[1].tail_spacing > ManagerScript.TAIL_SPACING)
		_turned_back = _turned_back or _mgrs[1]._orbit_way.has(-1.0)
		if not _circled_quad:
			for slot in _mgrs[1]._high:
				if _mgrs[1]._alive[slot] != 0 and _mgrs[1]._motion[slot] == ManagerScript.MOTION_ORBIT and (_mgrs[1]._flags[slot] & ManagerScript.F_QUAD) != 0:
					_circled_quad = true
					break
		# Threat asks: enough in a step for the grid (from the third), and some in a step without it.
		var asks: int = 6 if step % 3 != 2 else 1
		for n in asks:
			var point := Vector2(queries.randf_range(30.0, 930.0), queries.randf_range(30.0, 510.0))
			var radius: float = queries.randf_range(4.0, 40.0)
			var team: int = [-1, 0, 1][queries.randi() % 3]
			var own_id: int = queries.randi_range(-1, 5)
			var horizon: float = queries.randf_range(0.1, 1.5)
			var a: float = _mgrs[0].threat(point, radius, team, own_id, horizon)
			var b: float = _mgrs[1].threat(point, radius, team, own_id, horizon)
			if not (var_to_bytes(a) == var_to_bytes(b) and _mgrs[0].threat_slot == _mgrs[1].threat_slot
					and var_to_bytes(_mgrs[0].threat_away) == var_to_bytes(_mgrs[1].threat_away)):
				_differ("step %d ask %d: the same threat (%s %d %s / %s %d %s)" % [step, n, a, _mgrs[0].threat_slot, _mgrs[0].threat_away, b, _mgrs[1].threat_slot, _mgrs[1].threat_away])
		_compare_arrays(step)
		if _differences > 8:
			return
	# The scene reached what it is meant to compare.
	check(_mgrs[1].get_count() > 400, "the scene keeps hundreds of shots (%d)" % _mgrs[1].get_count())
	for batch in _mgrs[1].batch_count():
		check(_batch_seen[batch] > 0, "batch %d was drawn and compared" % batch)
	check(_mgrs[1].drawn > 300, "and draws them (%d)" % _mgrs[1].drawn)
	check(_tails_laid > 0 and _tails_capped, "the tails were laid as births (%d), past the most too" % _tails_laid)
	check(_turned_back, "a circling shot bounced and went round backwards")
	check(_circled_quad, "a still body circled, drawn as its quad")
	var boxes_hit: int = _box_hits.filter(func(n: String) -> bool: return n.begins_with("prop")).size()
	check(boxes_hit > 0 and _box_hits.size() > boxes_hit, "shots hit the boxes, props (%d) and enemies (%d)" % [boxes_hit, _box_hits.size() - boxes_hit])


# --- Targets grown mid-pass -------------------------------------------------
# An event that grows targets mid-pass (a shot ending on a wall: its `projectile_expired` goes out
# during the pass, while the merged hits wait for the pass's end): the shots after it in the pass
# must see each target's cell as the GDScript does. It keeps a cell's count and box once taken in a
# filling (`_cell_info`), so a shot passing the grown `near` (whose cell an earlier shot of the pass
# took) still sees its old box and misses it, and one passing the grown `far` (whose cell nothing
# took yet) sees the new one and hits it.

## Builds the scene on both sides and steps it three times, comparing each step; returns the
## GDScript side's events of the first step.
func _step_targets_grown_mid_pass() -> Array:
	var first_step: Array = []
	for side in 2:
		var mgr: ManagerScript = _manager(side, THREADS[THREADS.size() - 1], 600, ActorSeats.table())
		mgr.set_walls([Rect2(96.0, 250.0, 16.0, 40.0)] as Array[Rect2])
		var near: Node2D = _add_body(side, "near", Vector2(500.0, 270.0), 8.0, ManagerScript.LAYER_ENEMY, EventsScript.NO_PLAYER)
		var far: Node2D = _add_body(side, "far", Vector2(800.0, 270.0), 8.0, ManagerScript.LAYER_ENEMY, EventsScript.NO_PLAYER)
		(_targets[side] as Array).append_array([near, far])
		mgr.events.projectile_hit.connect(_on_grow_hit.bind(side))
		mgr.events.projectile_expired.connect(_on_grow_wall.bind(side, [near, far]))
		# First in the pass: a shot past `near` (its cell is taken, its box as it is), then one into the wall.
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
			_differ("grown mid-pass, step %d: the same events (%s)" % [step, _first_difference(_events[0], _events[1]) + " / " + _first_difference(_events[1], _events[0])])
		_compare_arrays(step)
		if step == 0:
			first_step = _events[0].duplicate()
	return first_step


func test_targets_grown_mid_pass_step_like_the_gdscript() -> void:
	if not _native_loaded():
		return
	_step_targets_grown_mid_pass()


func test_a_cell_the_pass_took_keeps_its_box_until_the_next_filling() -> void:
	if not _native_loaded():
		return
	var events: Array = _step_targets_grown_mid_pass()
	# Each merged hit's count is its event's last word (`x` and the hits it stands for).
	var on_near: int = 0
	var on_far: int = 0
	for e: String in events:
		var count: int = int(e.get_slice(" x", 1)) if " x" in e else 0
		if " near " in e:
			on_near += count
		elif " far " in e:
			on_far += count
	check(on_near == 0 and on_far > 100, "after the hit, the shots miss the grown near (%d hits) and hit the grown far (%d)" % [on_near, on_far])


func _on_grow_hit(caster: int, target: Node, position: Vector2, tag: int, shot: int, side: int) -> void:
	_events[side].append("hit %d %s %s %d %d x%d" % [caster, (target as Node).name, var_to_str(position), tag, shot, _mgrs[side].impact_count])


func _on_grow_wall(caster: int, position: Vector2, tag: int, shot: int, side: int, grown: Array) -> void:
	_events[side].append("wall %d %s %d %d" % [caster, var_to_str(position), tag, shot])
	for node: Node2D in grown:
		_mgrs[side].add_target(node, 60.0)


func _add_body(side: int, body_name: String, at: Vector2, radius: float, layer: int, owner_id: int, half: Vector2 = Vector2.ZERO) -> Node2D:
	var node := Node2D.new()
	node.name = body_name
	_holders[side].add_child(node)
	node.global_position = at
	_mgrs[side].add_target(node, radius, layer, owner_id, Vector2.ZERO, 0, half)
	if half != Vector2.ZERO:
		node.set_meta(&"box", true)
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
		# Now and then a prop casts, from its body (its shots spare it until they leave it).
		var prop: int = (i / 11) % _props.size() if i % 11 == 10 else -1
		var caster: int = _imp if i % 5 == 4 else (_props[prop] if prop >= 0 else i % 4)
		var from: Vector2 = Vector2(160.0 + float(i % 4) * 200.0, 420.0) if caster != _imp else Vector2(480.0, 120.0)
		if prop >= 0:
			# From a staff tip just off the prop's box, so its shots aimed back across it pass it.
			from = PROP_AT[prop] + Vector2(0.0, -(PROP_HALF[prop].y + PROP_RADIUS[prop] + 4.0))
		var velocity: Vector2 = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 420.0)
		var kind: int = rng.randi() % 10
		var slot: int = -1
		if kind == 0:
			slot = m.spawn(caster, from + Vector2(rng.randf_range(-60, 60), rng.randf_range(-200, 0)), Vector2.ZERO, rng.randf_range(0.5, 2.0), rng.randf_range(4.0, 14.0), ManagerScript.ACTOR_LAYERS, 2, 1, ManagerScript.MOTION_STILL)
			if slot >= 0:
				# A rune, or one of the card bodies (their batches, the enemy ramp's too).
				m.set_carrier_card(slot, &"", slot % (SCENE_BODIES + 1))
		elif kind == 1:
			# A shot set circling its caster's body (orbit as a modifier, 5A): most are bolts cast with
			# a speed, turned by it over their radius plus a drift; some have no speed and only drift.
			# (The speed curve below takes them too: the orbit pass reads `_curve_factor`.)
			var who: int = caster if caster != _imp else 0
			var round_radius: float = rng.randf_range(20.0, 60.0)
			var angle: float = rng.randf() * TAU
			var drift: float = rng.randf_range(-4.0, 4.0)
			var own_speed: Vector2 = velocity if rng.randf() < 0.75 else Vector2.ZERO
			# Half of those with no speed are still bodies set circling (5B: a rune, a pool, a stone):
			# they keep their quad (`F_QUAD`) while they move.
			var still: bool = own_speed == Vector2.ZERO and step % 2 == 0
			slot = m.spawn(who, m.get_anchor(who), own_speed, rng.randf_range(0.5, 2.0), rng.randf_range(1.5, 6.0), ManagerScript.LAYER_ENEMY, 1000, 1, ManagerScript.MOTION_STILL if still else ManagerScript.MOTION_STRAIGHT)
			if slot >= 0 and not m.set_orbit(slot, round_radius, angle, drift):
				_differ("step %d: set_orbit refused a live straight shot" % step)
			if slot >= 0 and slot % 2 == 0:
				# Some bounce: a wall across the circle (the block by the imp's anchor) turns them back round.
				m.set_bounce(slot, 3)
			if slot >= 0 and slot % 3 == 0:
				# An orbit shot of a card body: a head body's pair, or plain for a quad body.
				m.set_carrier_card(slot, &"", slot % (SCENE_BODIES + 1))
		else:
			slot = m.spawn(caster, from, velocity, rng.randf_range(0.3, 2.5), rng.randf_range(1.0, 9.0), ManagerScript.ACTOR_LAYERS, rng.randi() % 4, 1 if kind != 9 else 2)
			if slot >= 0 and kind == 8:
				# A flying shot of a card body (a bolt's own head): a head body's pair, or plain.
				m.set_carrier_card(slot, &"", slot % (SCENE_BODIES + 1))
		if slot < 0:
			continue
		if prop >= 0:
			# Cast from the prop's own box: spared while on it, or coming back across it.
			m.exclude(slot, _prop_nodes[side][prop])
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
	var m_hit: ManagerScript = _mgrs[side]
	_events[side].append("hit %d %s %s %d %d x%d" % [caster, (target as Node).name, var_to_str(position), tag, shot, m_hit.impact_count])
	if side == 1:
		_hits_sent += m_hit.impact_count
	if side == 1 and target.has_meta(&"box"):
		_box_hits.append(String(target.name))
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
		# Or makes it much larger (registered again) for the next pass.
		m.add_target(target as Node2D, 60.0)
	if shot % 13 == 5:
		# Or changes another shot (a ghost now, pulled a little, as a pull would).
		var later: int = (shot + 31) % m.get_cap()
		if m.set_ghost(later):
			m._pos[later] += Vector2(6.0, -4.0)


func _on_expired(caster: int, position: Vector2, tag: int, shot: int, side: int) -> void:
	_events[side].append("expired %d %s %d %d" % [caster, var_to_str(position), tag, shot])
	# During the pass, alike on both sides: now and then an end takes an enemy away, makes one much
	# larger (registered again), or makes a shot later in the pass a ghost and pulls it a little.
	var m: ManagerScript = _mgrs[side]
	var enemies: Array = _targets[side]
	if enemies.is_empty():
		return
	var body: Node2D = enemies[(shot * 7) % enemies.size()] as Node2D
	if shot % 23 == 4 and body.name.begins_with("enemy"):
		m.remove_target(body)
	elif shot % 19 == 9 and body.name.begins_with("enemy"):
		m.add_target(body, 60.0)
	if shot % 11 == 2:
		var later: int = (shot + 17) % m.get_cap()
		if m.set_ghost(later):
			m._pos[later] += Vector2(6.0, -4.0)


## Every packed array (and int and float) member of the two managers, byte for byte.
func _compare_arrays(step: int) -> void:
	for prop: Dictionary in _mgrs[0].get_property_list():
		var member: StringName = prop["name"]
		var type: int = prop["type"]
		if (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or member in OWN_BUFFERS or member in NOT_COMPARED:
			continue
		if type < TYPE_PACKED_BYTE_ARRAY and type != TYPE_INT and type != TYPE_FLOAT and type != TYPE_VECTOR2:
			continue
		var a: Variant = _mgrs[0].get(member)
		var b: Variant = _mgrs[1].get(member)
		if var_to_bytes(a) != var_to_bytes(b):
			_differ("step %d: %s differs (GDScript %s, native %s)" % [step, member, _first_difference(a, b), _first_difference(b, a)])
	# The room grid's too (the walls and the solid shots' stones on them; hit batch B1).
	for prop: Dictionary in _mgrs[0].grid().get_property_list():
		var member: StringName = prop["name"]
		if (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var a: Variant = _mgrs[0].grid().get(member)
		var b: Variant = _mgrs[1].grid().get(member)
		if var_to_bytes(a) != var_to_bytes(b):
			_differ("step %d: the room grid's %s differs" % [step, member])
	# The hit batch's (its entries, the bodies' tallies, the spent shots; hit batch A1).
	_compare_batch(step, _mgrs[0]._hit_batch, _mgrs[1]._hit_batch)


## The hit batch's scratch of its last `add` (what it asked, at which count, the damage slot kept):
## an entry the native hit pass opens does not go through `add` (hit batch A4).
const BATCH_SCRATCH: Array[StringName] = [&"asks", &"_asked_at", &"_asked_alone", &"_kept"]


## Every packed array, int and float member of the two managers' hit batches, byte for byte.
func _compare_batch(step: int, first: HitBatch, second: HitBatch) -> void:
	for prop: Dictionary in first.get_property_list():
		var member: StringName = prop["name"]
		var type: int = prop["type"]
		if (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or member in BATCH_SCRATCH:
			continue
		if type < TYPE_PACKED_BYTE_ARRAY and type != TYPE_INT and type != TYPE_FLOAT and type != TYPE_VECTOR2:
			continue
		var a: Variant = first.get(member)
		var b: Variant = second.get(member)
		if var_to_bytes(a) != var_to_bytes(b):
			_differ("step %d: the hit batch's %s differs (GDScript %s, native %s)" % [step, member, _first_difference(a, b), _first_difference(b, a)])


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
	if a.drawn != b.drawn or a.drawn_enemy != b.drawn_enemy:
		_differ("step %d: the same drawn counts (%d %d / %d %d)" % [step, a.drawn, a.drawn_enemy, b.drawn, b.drawn_enemy])
	if a.particle_demand != b.particle_demand:
		_differ("step %d: the same demand" % step)
	for batch in b.batch_count():
		var count_a: int = a._nodes[batch].multimesh.visible_instance_count
		var count_b: int = b._nodes[batch].multimesh.visible_instance_count
		if count_a != count_b:
			_differ("step %d batch %d: the same instances (%d / %d)" % [step, batch, count_a, count_b])
		_batch_seen[batch] = maxi(_batch_seen[batch], count_a)
		var buffer_a: PackedFloat32Array = a._buffers[batch]
		# The native side drew into the kernel's buffers, or into its own while a solid shot lived.
		var buffer_b: PackedFloat32Array = b._kernel.call(&"buffer", batch) if not b._any_solid else b._buffers[batch]
		var floats: int = mini(count_a, count_b) * ManagerScript.DRAW_STRIDE
		if buffer_a.size() < floats or buffer_b.size() < floats:
			_differ("step %d batch %d: a buffer too small" % [step, batch])
			continue
		if var_to_bytes(buffer_a.slice(0, floats)) != var_to_bytes(buffer_b.slice(0, floats)):
			_differ("step %d batch %d: the instances differ (%s / %s)" % [step, batch, _first_difference(buffer_a.slice(0, floats), buffer_b.slice(0, floats)), _first_difference(buffer_b.slice(0, floats), buffer_a.slice(0, floats))])

