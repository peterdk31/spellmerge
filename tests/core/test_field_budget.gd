extends "res://tests/support/suite.gd"
## What fields cost (docs/milestones/field.md, "The cost, and where it runs"): the field pass
## (`ProjectileManager.shots_into_fields`, natively `ShotKernel.field_pass`) over SHOTS shots in flight
## against FIELDS fields, each step. Each step hands back every shot at most once, only shots in a
## field (inside it after the step, or through it), and natively within FIELD_BUDGET_REFERENCES native references a step
## (the GDScript fallback's time is printed, not held).
##
## - **What held shots cost** (the owner, 2026-11-26: "No limits"): one field holding HELD shots, its
##   step (drawing every one in) within HELD_BUDGET_US, and its burst, spread over steps
##   (BURST_PER_STEP a step), each step within BURST_BUDGET_US, for 500 and 2000.
##
## The numbers are printed (`BUDGET:` lines) for the PR. Real time is read here, in a test, never in
## the game.
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const NativeScript := preload("res://core/native/native.gd")
const WallClock := preload("res://tests/support/wall_clock.gd")

const SHOTS: int = 2048
const FIELDS: int = 16
const DT: float = 1.0 / 60.0
const STEPS: int = 30
## In native references (tests/support/wall_clock.gd), so it holds on any machine and beside other
## tests. The native pass measured about 150 us a step with 2048 shots and 16 fields on a 4-core
## container, 2026-11-26 (see the BUDGET lines); the old 1500 us was about 0.19 of its reference.
const FIELD_BUDGET_REFERENCES: float = 0.19
## The held shots' counts and their budgets, in GDScript (2026-11-26, this 4-core container: 2000 held
## measured about 1.8 ms a step to draw in; their burst 10.5 ms in one step before it was spread,
## about 1.4 ms a step since, BURST_PER_STEP at a time; generous for a shared machine).
const HELD: Array[int] = [500, 2000]
const HELD_BUDGET_US: int = 20000
const BURST_BUDGET_US: int = 8000


func _manager(native: bool) -> Array:
	var m := ManagerScript.new()
	m.native = native
	m.set_cap(SHOTS + FIELDS)
	m.set_bounds(Rect2(-2000.0, -2000.0, 4000.0, 4000.0))
	root.add_child(m)
	m.set_native_threads(1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var fields := PackedInt32Array()
	for n in FIELDS:
		var slot: int = m.spawn(0, Vector2(rng.randf_range(0.0, 640.0), rng.randf_range(0.0, 360.0)), Vector2.ZERO, 30.0, 32.0, ManagerScript.LAYER_ENEMY, 0, 0, ManagerScript.MOTION_STILL)
		m.set_field(slot)
		fields.append(slot)
	for n in SHOTS:
		m.spawn(0, Vector2(rng.randf_range(0.0, 640.0), rng.randf_range(0.0, 360.0)), Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 600.0), 30.0, 3.0, ManagerScript.LAYER_ENEMY)
	return [m, fields]


## Steps STEPS times checking each step's hand-back, then times the field pass alone against
## `reference` (the shots stay where the last step left them).
func _field_cost(m: ManagerScript, fields: PackedInt32Array, reference: Callable) -> WallClock.Timed:
	var handed: int = 0
	for step in STEPS:
		m.step(DT)
		var count: int = m.shots_into_fields(fields, fields.size())
		handed += count
		var seen := {}
		for n in count:
			var slot: int = m.field_shot(n)
			var field: int = fields[m.field_of(n)]
			check(not seen.has(slot), "step %d: shot %d handed back once" % [step, slot])
			seen[slot] = true
			var centre: Vector2 = m.get_position_of(field)
			var r: float = m.get_radius_of(field)
			var from: Vector2 = m.get_prev_of(slot)
			var to: Vector2 = m.get_position_of(slot)
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(centre, from, to)
			check(near.distance_to(centre) <= r + 0.01, "step %d: shot %d is in field %d" % [step, slot, field])
	check(handed > STEPS, "shots came into fields (%d)" % handed)
	return WallClock.against(func() -> void: m.shots_into_fields(fields, fields.size()), reference, STEPS)


func test_the_field_pass_is_within_its_budget() -> void:
	var gd: Array = _manager(false)
	var gd_cost: WallClock.Timed = _field_cost(gd[0], gd[1], WallClock.gdscript_reference)
	print("BUDGET: field pass, GDScript, %d shots, %d fields: %d us a step" % [SHOTS, FIELDS, gd_cost.work_usec])
	(gd[0] as ManagerScript).free()
	if not NativeScript.loaded():
		print("NOTE: the native module is not built; its budget is not held")
		return
	var native: Array = _manager(true)
	check((native[0] as ManagerScript).is_native(), "the kernel runs it")
	var native_cost: WallClock.Timed = _field_cost(native[0], native[1], WallClock.native_reference)
	print("BUDGET: field pass, native, %d shots, %d fields: %d us a step (%.3f native references)" % [SHOTS, FIELDS, native_cost.work_usec, native_cost.multiple])
	check(native_cost.multiple <= FIELD_BUDGET_REFERENCES, "the native pass within %.2f native references (%.3f)" % [FIELD_BUDGET_REFERENCES, native_cost.multiple])
	(native[0] as ManagerScript).free()


func test_no_field_costs_nothing() -> void:
	var m := ManagerScript.new()
	root.add_child(m)
	check_equal(m.shots_into_fields(PackedInt32Array(), 0), 0, "with no field the pass hands back nothing and runs no loop")
	m.free()


func test_held_shots_cost_within_their_budget() -> void:
	for many: int in HELD:
		var arena := ArenaScript.new(root)
		arena.projectiles.set_cap(many + 64)
		arena.install_cards(0, 0, ["fire", "field"])
		check(arena.cast(0, 0), "the field is cast")
		arena.run(DT)
		var fields: CarrierField = CarrierField.of(arena.spells)
		var centre: Vector2 = arena.projectiles.get_position_of(fields.field_slot(0))
		for n in many:
			var way: Vector2 = Vector2.from_angle(TAU * float(n) / float(many))
			arena.projectiles.spawn(0, centre - way * 40.0, way * 300.0, 3.0, 1.0, ManagerScript.LAYER_ENEMY)
		arena.run(0.2)
		check_equal(fields.held_count(), many, "%d held" % many)
		var start: int = Time.get_ticks_usec()
		fields.step(DT)
		var held_us: int = Time.get_ticks_usec() - start
		arena.projectiles.remove_by_tag(arena.projectiles.get_tag_of(fields.field_slot(0)))
		# The burst, spread: BURST_PER_STEP a step, its dearest step timed.
		var worst: int = 0
		var steps: int = 0
		while fields.held_count() > 0 and steps < 100:
			start = Time.get_ticks_usec()
			fields.step(DT)
			worst = maxi(worst, Time.get_ticks_usec() - start)
			steps += 1
		check_equal(fields.held_count(), 0, "%d let go" % many)
		check_equal(steps, ceili(float(many) / float(CarrierField.BURST_PER_STEP)), "%d let go over as many steps as the burst's share a step says" % many)
		print("BUDGET: a field holding %d shots: a step %d us; its burst over %d steps, its dearest step %d us" % [many, held_us, steps, worst])
		check(held_us < HELD_BUDGET_US and worst < BURST_BUDGET_US, "%d held within budget (%d, %d)" % [many, held_us, worst])
		arena.free_all()
