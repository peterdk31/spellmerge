extends "res://tests/support/suite.gd"
## What it costs that every shot touches the floor as it passes (the floor's first slice,
## docs/milestones/floor.md, "Measures"; the owner, 2026-11-25: design and measure that cost):
##
## - **The trail pass** (`ProjectileManager._pass_trail`, natively `ShotKernel.trail_pass`): with
##   SHOTS shots of an element in flight, each step hands back at most one entry a shot, every shot
##   at most once, and none of a shot that did not cross into another cell; natively within
##   TRAIL_BUDGET_REFERENCES a step (the GDScript fallback's time is printed, not held).
## - **The cover's share:** a tick's worth of passing touches (one a shot) applied by the cover area
##   on the floor's own cover within COVER_BUDGET_REFERENCES, and a second tick of the same touches (the cells
##   already wet: renewals) within it too.
##
## The numbers are printed (`BUDGET:` lines) for the PR and docs/DECISIONS.md. Real time is read
## here, in a test, never in the game.
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const NativeScript := preload("res://core/native/native.gd")
const Kit := preload("res://tests/gameplay/cover/cover_kit.gd")
const WallClock := preload("res://tests/support/wall_clock.gd")
const FLOOR: CoverKind = preload("res://content/cover/floor/floor.tres")

const SHOTS: int = 2048
const DT: float = 1.0 / 60.0
const STEPS: int = 30
## In references (tests/support/wall_clock.gd), so they hold on any machine and beside other tests.
## Deliberately as loose as the old fixed limits (a gross-slowdown guard, not a tight one). The trail pass natively: 0.0012 native references measured (10 us of an 8 ms reference, 4-core
## container, 2026-11-26); the budget keeps the old 400 us, 0.05 of a reference.
const TRAIL_BUDGET_REFERENCES: float = 0.05
## The cover's tick: 1.3 GDScript references when the cells move, 0.35 for renewals (the same
## machine); the old 12 ms was about 2.3 of its references, and one budget holds both.
const COVER_BUDGET_REFERENCES: float = 2.0
const COVER_RUNS: int = 4


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


## Steps the manager STEPS times, checking each step's hand-back, then times the pass alone against
## `reference` (nothing crosses between its runs, so each hands back nothing).
func _trail_cost(m: ManagerScript, reference: Callable) -> WallClock.Timed:
	for step in STEPS:
		m.step(DT)
		var count: int = m.trail_count()
		check(count <= m.get_count(), "step %d: at most one entry a shot (%d of %d)" % [step, count, m.get_count()])
		var seen := {}
		for n in count:
			var slot: int = m.trail_slot(n)
			check(not seen.has(slot), "step %d: shot %d handed back once" % [step, slot])
			seen[slot] = true
		var again: int = _pass(m)
		check_equal(again, 0, "step %d: a shot that stayed in its cell is not handed back" % step)
	return WallClock.against(func() -> void: _pass(m), reference, STEPS)


func _pass(m: ManagerScript) -> int:
	return m.call(&"_pass_trail", m._high) if not m.is_native() else m._kernel.call(&"trail_pass", m, m._high)


func test_the_trail_pass_is_within_its_budget() -> void:
	var gd: ManagerScript = _manager(false)
	var gd_cost: WallClock.Timed = _trail_cost(gd, WallClock.gdscript_reference)
	print("BUDGET: trail pass, GDScript, %d shots: %.1f us a step (%.3f GDScript references)" % [SHOTS, gd_cost.work_usec, gd_cost.multiple])
	gd.free()
	if not NativeScript.loaded():
		print("NOTE: the native module is not built; its budget is not held")
		return
	var native: ManagerScript = _manager(true)
	check(native.is_native(), "the kernel runs it")
	native.set_native_threads(1)
	var native_cost: WallClock.Timed = _trail_cost(native, WallClock.native_reference)
	print("BUDGET: trail pass, native, %d shots: %.1f us a step (%.4f native references)" % [SHOTS, native_cost.work_usec, native_cost.multiple])
	check(native_cost.multiple <= TRAIL_BUDGET_REFERENCES, "the native pass within %.4f native references (%.4f)" % [TRAIL_BUDGET_REFERENCES, native_cost.multiple])
	native.free()


func test_the_cover_applies_a_tick_of_passing_within_its_budget() -> void:
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
	# A fresh kit for each timed run (a tick's touches change the floor): the first tick on each,
	# then the same touches again on the same kits (the cells already wet: renewals).
	var kits: Array = []
	for run in COVER_RUNS:
		kits.append(Kit.new(root, FLOOR))
	var next: Array[int] = [0]
	var tick := func() -> void:
		var kit: Kit = kits[next[0]]
		next[0] += 1
		kit.world.bus.floor_passed.emit(casters, tags, elements, at)
		kit.cover.step(DT)
	var moving: WallClock.Timed = WallClock.against(tick, WallClock.gdscript_reference, COVER_RUNS)
	next[0] = 0
	var renewing: WallClock.Timed = WallClock.against(tick, WallClock.gdscript_reference, COVER_RUNS)
	print("BUDGET: cover, %d passing touches: %.2f GDScript references, %d us (cells moving), %.2f references, %d us (renewals), a reference %d us" % [SHOTS, moving.multiple, moving.work_usec, renewing.multiple, renewing.work_usec, moving.reference_usec])
	var wet: int = (kits[0] as Kit).count_in(&"wetting")
	check(wet > 50, "the touches wetted the floor (%d)" % wet)
	check(moving.multiple <= COVER_BUDGET_REFERENCES, "a tick of them within %.1f GDScript references (%.2f)" % [COVER_BUDGET_REFERENCES, moving.multiple])
	check(renewing.multiple <= COVER_BUDGET_REFERENCES, "and the next within %.1f (%.2f)" % [COVER_BUDGET_REFERENCES, renewing.multiple])
	for kit: Kit in kits:
		kit.free_all()
