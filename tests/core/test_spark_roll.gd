extends "res://tests/support/suite.gd"
## The sparks the drawn shots give off (`ProjectileDraw._give_off_sparks`), rolled natively
## (`ShotKernel.give_off_sparks`, native/src/spark_roll.cpp) and in the GDScript, side by side: two managers, one
## native and one not, step and draw the same shots (every kind of look, several kinds at once, none,
## the weave alone; the hat ramps and the enemy's; straight, circling and still shots; several
## casters and staffs, so several groups; a pool small enough to thin them), and every frame they
## hold the same births, to the bit, and their dice the same state; with the tails laid as births
## first in the frame's (`_lay_tail`, the shot kernel's `draw_shots`) too.
##
## Without the native module the GDScript is still checked (SPELLMERGE_NATIVE=required fails the
## comparison instead).
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const DrawScript := preload("res://core/projectiles/projectile_draw.gd")
const NativeScript := preload("res://core/native/native.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

const FRAMES: int = 90

var _mgrs: Array[ManagerScript] = []
var _imp: int = -1


func before_each() -> void:
	super.before_each()
	_mgrs.clear()


func _manager(native: bool) -> ManagerScript:
	var table: ActorsScript = own(ActorSeats.table()) as ActorsScript
	_imp = ActorSeats.enemy(table)
	var mgr: ManagerScript = own(ManagerScript.new()) as ManagerScript
	mgr.native = native
	mgr.actors = table
	mgr.events = own(EventsScript.new()) as EventsScript
	mgr.set_bounds(Rect2(0.0, 0.0, 960.0, 540.0))
	mgr.set_cap(800)
	root.add_child(mgr)
	mgr.spark_motes = true
	mgr._spark_rng.seed = 5
	_mgrs.append(mgr)
	return mgr


## Whether the second manager rolls natively (a failure when the module is required but not loaded).
func _native() -> bool:
	var on: bool = _mgrs[1]._job_draw._spark_kernel() != null
	if not on and OS.get_environment("SPELLMERGE_NATIVE") == "required":
		check(false, "SPELLMERGE_NATIVE=required, but the native module is not loaded (ci/build/native.sh)")
	return on


## The same shots on both managers: `count` of them, their looks taken in turn from every kind and
## mix, their casters from the four wizards and the imp, some circling and some still.
func _fire(count: int, seed_value: int) -> void:
	var looks: Array[int] = [0, ManagerScript.pack_look(PackedInt32Array([ManagerScript.LOOK_WEAVE]))]
	for kind in range(1, ManagerScript.LOOK_COUNT):
		looks.append(ManagerScript.pack_look(PackedInt32Array([kind])))
	looks.append(ManagerScript.pack_look(PackedInt32Array([ManagerScript.LOOK_EMBERS, ManagerScript.LOOK_SPARKS, ManagerScript.LOOK_DRIFT])))
	looks.append(ManagerScript.pack_look(PackedInt32Array([ManagerScript.LOOK_FLECKS, ManagerScript.LOOK_WEAVE, ManagerScript.LOOK_GLITTER, ManagerScript.LOOK_SLICK])))
	for mgr in _mgrs:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		for i in count:
			var caster: int = _imp if i % 5 == 4 else i % 4
			var tag: int = SpellTag.make(caster, i % 3, 0, 1) if caster != _imp else 0
			var at := Vector2(rng.randf_range(100.0, 860.0), rng.randf_range(100.0, 440.0))
			var velocity := Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(20.0, 240.0)
			var motion: int = ManagerScript.MOTION_STILL if i % 9 == 7 else ManagerScript.MOTION_STRAIGHT
			var slot: int = mgr.spawn(caster, at, velocity, rng.randf_range(0.5, 3.0), rng.randf_range(3.0, 9.0), ManagerScript.LAYER_ENEMY, 99, tag, motion)
			if slot < 0:
				continue
			mgr.set_look(slot, looks[i % looks.size()])
			if i % 7 == 3:
				mgr.set_anchor(caster, at)
				mgr.set_orbit(slot, rng.randf_range(10.0, 40.0), rng.randf_range(0.0, TAU), rng.randf_range(-4.0, 4.0))


func _step_and_compare(frames: int, label: String) -> int:
	var births: int = 0
	for frame in frames:
		var fraction: float = float(frame % 5) / 4.0
		for mgr in _mgrs:
			mgr.step(1.0 / 60.0)
			mgr.update_draw(fraction)
		var a: ManagerScript = _mgrs[0]
		var b: ManagerScript = _mgrs[1]
		births += a.spark_birth_count
		if a.spark_birth_count != b.spark_birth_count:
			check(false, "%s frame %d: as many births (GDScript %d, native %d)" % [label, frame, a.spark_birth_count, b.spark_birth_count])
			return births
		var floats: int = a.spark_birth_count * ManagerScript.SPARK_BIRTH_STRIDE
		var mine: PackedFloat32Array = a.spark_births.slice(0, floats)
		var theirs: PackedFloat32Array = b.spark_births.slice(0, floats)
		if var_to_bytes(mine) != var_to_bytes(theirs):
			for i in floats:
				if var_to_bytes(mine[i]) != var_to_bytes(theirs[i]):
					check(false, "%s frame %d: birth %d float %d (GDScript %s, native %s)" % [label, frame, i / ManagerScript.SPARK_BIRTH_STRIDE, i % ManagerScript.SPARK_BIRTH_STRIDE, mine[i], theirs[i]])
					return births
		if a._spark_rng.state != b._spark_rng.state:
			check(false, "%s frame %d: the dice in the same state" % [label, frame])
			return births
	return births


func test_the_native_sparks_are_the_gdscripts() -> void:
	_manager(false)
	_manager(true)
	if not _native():
		return
	# The cards' births alone: no tails laid.
	for mgr in _mgrs:
		mgr.tail_births_cap = 0
	_fire(300, 3)
	var births: int = _step_and_compare(FRAMES, "sparks")
	check(births > 2000, "many births compared: %d" % births)
	# A pool small enough to thin every group (`_share_groups`), and more shots past the frame's most.
	for mgr in _mgrs:
		mgr.tailless_particle_cap = 150
	_fire(450, 4)
	births = _step_and_compare(FRAMES, "thinned")
	check(births > 500, "thinned births compared: %d" % births)
	check(_mgrs[0].particle_share < 1.0, "the pool thinned them: %.2f" % _mgrs[0].particle_share)


func test_the_native_sparks_after_the_tails_are_the_gdscripts() -> void:
	_manager(false)
	_manager(true)
	if not _native():
		return
	_fire(200, 9)
	var births: int = _step_and_compare(FRAMES, "tails")
	check(births > 2000, "many births compared: %d" % births)
	check(_mgrs[0].tail_births > 0, "tails laid first: %d" % _mgrs[0].tail_births)


## The kernel takes the manager's numbers, and refuses a set with one missing.
func test_the_kernel_takes_the_managers_numbers() -> void:
	var kernel: Object = NativeScript.shot_kernel()
	if kernel == null:
		_manager(true)
		_native()
		return
	check(kernel.call(&"spark_configure", DrawScript.spark_config()), "the manager's numbers")
	var config: Dictionary = DrawScript.spark_config()
	config.erase("SPARK_RATES")
	check(not kernel.call(&"spark_configure", config), "one missing is refused")
