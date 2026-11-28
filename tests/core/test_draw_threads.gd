extends "res://tests/support/suite.gd"
## The native drawing's loops (`ShotKernel.count_draw`, `draw_shots`) run on one thread below
## DRAW_THREADS_FROM slots (native/README.md, "Threads"), so test_native_kernel.gd's runs at four
## threads draw on one. Here a manager past it draws the same frame on four threads and on one, and
## every batch's rows are the same to the bit (rule T2: a result never depends on the threads).
##
## Without the native module, or in a build without threads, the test only says so
## (SPELLMERGE_NATIVE=required fails it instead).
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

## Past the kernel's DRAW_THREADS_FROM (16,384 slots).
const SHOTS: int = 17000


func test_the_drawing_past_its_threshold_is_the_same_on_four_threads_and_one() -> void:
	var mgr: ManagerScript = own(ManagerScript.new()) as ManagerScript
	mgr.native = true
	mgr.actors = own(ActorSeats.table()) as ActorsScript
	mgr.events = own(EventsScript.new()) as EventsScript
	mgr.set_bounds(Rect2(0.0, 0.0, 4000.0, 4000.0))
	mgr.set_cap(SHOTS)
	root.add_child(mgr)
	if not mgr.is_native():
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded")
		return
	mgr.set_native_threads(4)
	if mgr.native_thread_count() < 2:
		print("NOTE: this build of the native module has no threads; nothing to compare")
		return
	var looks: Array[int] = [0, ManagerScript.pack_look(PackedInt32Array([ManagerScript.LOOK_EMBERS])),
			ManagerScript.pack_look(PackedInt32Array([ManagerScript.LOOK_SPARKS, ManagerScript.LOOK_DRIFT]))]
	for i in SHOTS:
		var motion: int = ManagerScript.MOTION_STILL if i % 9 == 7 else ManagerScript.MOTION_STRAIGHT
		var at := Vector2(100.0 + float(i % 130) * 29.0, 100.0 + float(i / 130) * 29.0)
		var slot: int = mgr.spawn(i % 4, at, Vector2.from_angle(float(i) * 0.37) * 60.0, 5.0, 3.0 + float(i % 5), ManagerScript.LAYER_ENEMY, 0, 0, motion)
		mgr.set_look(slot, looks[i % looks.size()])
	check_equal(mgr._high, SHOTS, "every shot fired")
	mgr.step(1.0 / 60.0)
	mgr.update_draw(0.5)
	var threaded: Array[PackedFloat32Array] = _rows(mgr)
	mgr.set_native_threads(1)
	mgr.update_draw(0.5)
	var alone: Array[PackedFloat32Array] = _rows(mgr)
	var drawn: int = 0
	for batch in threaded.size():
		drawn += threaded[batch].size() / ManagerScript.DRAW_STRIDE
		check(var_to_bytes(threaded[batch]) == var_to_bytes(alone[batch]), "batch %d: the same rows on four threads and one" % batch)
	check_equal(drawn, SHOTS, "every shot drawn")


## Each batch's rows drawn this frame, copied.
func _rows(mgr: ManagerScript) -> Array[PackedFloat32Array]:
	var rows: Array[PackedFloat32Array] = []
	var out: PackedInt32Array = mgr.get(&"_draw_out")
	for batch in mgr.batch_count():
		var count: int = out[ManagerScript.DRAW_OUT_FIRST + batch]
		var buffer: PackedFloat32Array = mgr._kernel.call(&"buffer", batch)
		rows.append(buffer.slice(0, count * ManagerScript.DRAW_STRIDE))
	return rows
