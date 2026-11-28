extends "res://tests/support/suite.gd"
## The native step's loops over every slot (the common pass) and over a behaviour's members run on
## one thread below STEP_THREADS_FROM shots (native/src/shot_kernel.cpp; native/README.md,
## "Threads"), so test_native_kernel.gd's scene (at most 1,500 shots) steps them on one at any
## thread count. Here two managers past it, one on four threads and one on one, step the same
## shots (every one homing, so the homing pass's members are past it too), and every packed array
## of theirs is the same to the bit after each step (rule T2: a result never depends on the threads).
##
## Without the native module, or in a build without threads, the test only says so
## (SPELLMERGE_NATIVE=required fails it instead).
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

## Past the kernel's STEP_THREADS_FROM (65,536 shots).
const SHOTS: int = 66000
const STEPS: int = 4
## A row of shots, SPACING apart.
const ROW: int = 260
const SPACING: float = 30.0


func test_the_step_past_its_threshold_is_the_same_on_four_threads_and_one() -> void:
	var threaded: ManagerScript = _manager(4)
	var alone: ManagerScript = _manager(1)
	if threaded == null or alone == null:
		return
	if threaded.native_thread_count() < 2:
		print("NOTE: this build of the native module has no threads; nothing to compare")
		return
	check_equal(alone.native_thread_count(), 1, "the other manager on one thread")
	for step in STEPS:
		threaded.step(1.0 / 60.0)
		alone.step(1.0 / 60.0)
		_compare(step, threaded, alone)
	check_equal(threaded.get_count(), SHOTS, "every shot still flying")


## A native manager on `threads` threads with SHOTS shots, alike whatever the threads; null
## without the native module.
func _manager(threads: int) -> ManagerScript:
	var mgr: ManagerScript = own(ManagerScript.new()) as ManagerScript
	mgr.native = true
	mgr.actors = own(ActorSeats.table()) as ActorsScript
	mgr.events = own(EventsScript.new()) as EventsScript
	mgr.set_bounds(Rect2(0.0, 0.0, 8400.0, 8400.0))
	mgr.set_cap(SHOTS)
	root.add_child(mgr)
	if not mgr.is_native():
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded")
		return null
	mgr.set_native_threads(threads)
	var homing: int = 0
	for i in SHOTS:
		var at := Vector2(100.0 + float(i % ROW) * SPACING, 100.0 + float(i / ROW) * SPACING)
		var slot: int = mgr.spawn(i % 4, at, Vector2.from_angle(float(i) * 0.37) * 60.0, 5.0, 3.0 + float(i % 5))
		if mgr.set_homing(slot, 2.0 + float(i % 3), 120.0):
			homing += 1
	check_equal(mgr._high, SHOTS, "every shot fired")
	check_equal(homing, SHOTS, "every shot homing")
	return mgr


## Every packed array member of the two managers, byte for byte.
func _compare(step: int, a: ManagerScript, b: ManagerScript) -> void:
	var compared: int = 0
	for prop: Dictionary in a.get_property_list():
		if (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0 or int(prop["type"]) < TYPE_PACKED_BYTE_ARRAY:
			continue
		var member: StringName = prop["name"]
		compared += 1
		check(var_to_bytes(a.get(member)) == var_to_bytes(b.get(member)), "step %d: %s the same on four threads and one" % [step, member])
	check(compared > 10, "the managers' arrays compared (%d)" % compared)
