extends "res://tests/support/suite.gd"
## What it costs that every shot touches the floor as it passes (the floor's first slice,
## docs/milestones/floor.md, "Measures"; the owner, 2026-11-25: design and measure that cost):
##
## - **The trail pass** (`ProjectileManager._pass_trail`, natively `ShotKernel.trail_pass`): with
##   SHOTS shots of an element in flight, each step hands back at most one entry a shot, every shot
##   at most once, and none of a shot that did not cross into another cell; natively within
##   TRAIL_BUDGET_US a step (the GDScript fallback's time is printed, not held).
## - **The cover's share:** a tick's worth of passing touches (one a shot) applied by the cover area
##   on the floor's own cover within COVER_BUDGET_US, and a second tick of the same touches (the cells
##   already wet: renewals) within it too.
##
## The numbers are printed (`BUDGET:` lines) for the PR and docs/DECISIONS.md. Real time is read
## here, in a test, never in the game.
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const NativeScript := preload("res://core/native/native.gd")
const Kit := preload("res://tests/gameplay/cover/cover_kit.gd")
const FLOOR: CoverKind = preload("res://content/cover/floor/floor.tres")

const SHOTS: int = 2048
const DT: float = 1.0 / 60.0
const STEPS: int = 30
## The budgets, generous for a shared CI machine running the suite in parallel (alone, the cover's
## tick measured 1.3 to 1.8 ms; under the full parallel suite up to 4.4 ms: see the BUDGET lines).
const TRAIL_BUDGET_US: int = 400
const COVER_BUDGET_US: int = 12000


func _manager(native: bool) -> ManagerScript:
	var m := ManagerScript.new()
	m.native = native
	m.set_cap(SHOTS)
	m.set_bounds(Rect2(-2000.0, -2000.0, 4000.0, 4000.0))
	root.add_child(m)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for n in SHOTS:
		var slot: int = m.spawn(0, Vector2(rng.randf_range(0.0, 640.0), rng.randf_range(0.0, 360.0)), Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 600.0), 30.0, 3.0, ManagerScript.LAYER_ENEMY)
		m.set_trail(slot, true)
	return m


## The mean microseconds of the trail pass alone over STEPS steps, checking each step's hand-back.
func _trail_cost(m: ManagerScript) -> float:
	var spent: int = 0
	for step in STEPS:
		m.step(DT)
		var count: int = m.trail_count()
		check(count <= m.get_count(), "step %d: at most one entry a shot (%d of %d)" % [step, count, m.get_count()])
		var seen := {}
		for n in count:
			var slot: int = m.trail_slot(n)
			check(not seen.has(slot), "step %d: shot %d handed back once" % [step, slot])
			seen[slot] = true
		# The pass alone, timed again: nothing crossed since, so it hands back nothing.
		var start: int = Time.get_ticks_usec()
		var again: int = m.call(&"_pass_trail", m._high) if not m.is_native() else m._kernel.call(&"trail_pass", m, m._high)
		spent += Time.get_ticks_usec() - start
		check_equal(again, 0, "step %d: a shot that stayed in its cell is not handed back" % step)
	return float(spent) / float(STEPS)


func test_the_trail_pass_is_within_its_budget() -> void:
	var gd: ManagerScript = _manager(false)
	var gd_cost: float = _trail_cost(gd)
	print("BUDGET: trail pass, GDScript, %d shots: %.1f us a step" % [SHOTS, gd_cost])
	gd.free()
	if not NativeScript.loaded():
		print("NOTE: the native module is not built; its budget is not held")
		return
	var native: ManagerScript = _manager(true)
	check(native.is_native(), "the kernel runs it")
	var native_cost: float = _trail_cost(native)
	print("BUDGET: trail pass, native, %d shots: %.1f us a step" % [SHOTS, native_cost])
	check(native_cost < float(TRAIL_BUDGET_US), "the native pass within %d us (%.1f)" % [TRAIL_BUDGET_US, native_cost])
	native.free()


func test_the_cover_applies_a_tick_of_passing_within_its_budget() -> void:
	var kit := Kit.new(root, FLOOR)
	var casters := PackedInt32Array()
	var tags := PackedInt64Array()
	var elements: Array[StringName] = []
	var at := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for n in SHOTS:
		casters.append(n % 4)
		tags.append(0)
		elements.append(&"water" if n % 3 != 0 else &"frost")
		at.append(Vector2(rng.randf_range(0.0, 300.0), rng.randf_range(0.0, 140.0)))
	var costs: Array[int] = []
	for tick in 2:
		var start: int = Time.get_ticks_usec()
		kit.world.bus.floor_passed.emit(casters, tags, elements, at)
		var heard: int = Time.get_ticks_usec()
		kit.cover.step(DT)
		costs.append(Time.get_ticks_usec() - start)
		print("BUDGET: cover, tick %d: %d us heard, %d us stepped" % [tick, heard - start, Time.get_ticks_usec() - heard])
	print("BUDGET: cover, %d passing touches: %d us (cells moving), %d us (renewals)" % [SHOTS, costs[0], costs[1]])
	check(kit.count_in(&"wetting") > 50, "the touches wetted the floor (%d)" % kit.count_in(&"wetting"))
	check(costs[0] < COVER_BUDGET_US, "a tick of them within %d us (%d)" % [COVER_BUDGET_US, costs[0]])
	check(costs[1] < COVER_BUDGET_US, "and the next (%d)" % costs[1])
	kit.free_all()
