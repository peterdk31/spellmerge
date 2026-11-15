extends "res://tests/support/suite.gd"
## A move's speed curve (boss plan OB10, `MoveCurve`, core/spells/move_curve.gd): its start and end
## factors and its ease, a move that still goes its whole way in its whole time whatever its steps,
## NONE changing nothing, a curve read from a staff's cards, those cards wasted where nothing moves
## along a way, and a dash moving a shot along its curve too.
##
## godot --headless --path . --script res://tests/core/test_move_curve.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

## A lurch and a drag (the Lumber card's numbers).
const LURCH: Vector3 = Vector3(0.1, 0.0, 3.0)


func test_none_keeps_the_speed() -> void:
	check(not MoveCurve.shapes(MoveCurve.NONE), "NONE shapes nothing")
	for u: float in [0.0, 0.3, 1.0]:
		check_equal(MoveCurve.factor(MoveCurve.NONE, u), 1.0, "even at %s" % u)
	check(is_equal_approx(MoveCurve.share(MoveCurve.NONE, 1.0, 1.0, 0.25), 0.25), "a quarter of the time, a quarter of the way")


func test_a_curve_starts_and_ends_at_its_factors() -> void:
	var area: float = MoveCurve.share(LURCH, 1.0, 1.0, 1.0)
	check(is_equal_approx(area, 1.0), "the whole time is the whole way (%s)" % area)
	var start: float = MoveCurve.factor(LURCH, 0.0)
	var end: float = MoveCurve.factor(LURCH, 1.0)
	var middle: float = MoveCurve.factor(LURCH, 0.5)
	check(start > 0.0 and start < 0.3, "it lurches off slowly (%s of its even speed)" % start)
	check(is_equal_approx(end, 0.0), "and stops dead at the end")
	check(middle > 1.2, "fast in the middle (%s)" % middle)
	# A burst, as a start above 1 gives.
	var burst := Vector3(2.0, 1.0, 1.0)
	check(MoveCurve.factor(burst, 0.0) > MoveCurve.factor(burst, 1.0), "a start above 1 bursts and eases down")


func test_every_step_adds_up_to_the_whole_way() -> void:
	for total: float in [0.5, 1.1, 2.0 / 3.0]:
		for delta: float in [1.0 / 60.0, 0.0625, 0.3]:
			# Counted down in float32, as the Mover's and the manager's arrays hold it.
			var left := PackedFloat32Array([total, total])
			var sum: float = 0.0
			while left[0] > 0.0:
				sum += MoveCurve.share(LURCH, left[1], left[0], delta)
				left[0] -= delta
			check(absf(sum - 1.0) < 1e-6, "%s s in steps of %s: the whole way (%s)" % [total, delta, sum])


func test_a_curve_that_would_hardly_move_is_none() -> void:
	check(not MoveCurve.shapes(Vector3(0.0, 0.0, 1.0)), "start 0, end 0, ease 1 has no area")
	check(not MoveCurve.shapes(Vector3(-1.0, 1.0, 1.0)), "a factor below 0 is not a curve")
	check(not MoveCurve.shapes(Vector3(INF, 1.0, 1.0)), "nor one that is not finite")
	check(MoveCurve.shapes(LURCH), "the lurch is")


func test_the_cards_curve_is_compiled_and_wasted_where_nothing_moves_along_a_way() -> void:
	var arena := ArenaScript.new(root)
	var dash: CompiledStaff = arena.install_cards(0, 0, ["lumber", "dash"])
	var spell: CompiledSpell = dash.casts[0].group.spells[0]
	check_equal(MoveCurve.of(spell), LURCH, "a Lumber dash takes the card's curve")
	var plain: CompiledStaff = arena.install_cards(0, 0, ["dash"])
	check_equal(MoveCurve.of(plain.casts[0].group.spells[0]), MoveCurve.NONE, "a plain dash none")
	arena.free_all()
	var carriers := Carriers.make_all()
	check(carriers[&"dash"].moves_along(), "a dash moves its caster along a way")
	for id: StringName in [&"teleport", &"atom", &"swap", &"beam"]:
		check(not carriers[id].moves_along(), "%s does not" % id)
	var curve_only := ModifierBase.new()
	curve_only.move_start = 0.5
	check(StaffCompiler._numbers_count(curve_only, carriers[&"dash"], false, false, false), "a curve counts on a dash")
	check(not StaffCompiler._numbers_count(curve_only, carriers[&"atom"], false, false, false), "and is wasted on a bolt (an atom)")
	check(not StaffCompiler._numbers_count(curve_only, carriers[&"teleport"], false, false, false), "and on a teleport, over at once")


func test_a_curved_move_carries_a_shot_its_whole_way() -> void:
	var bus := own(EventsScript.new()) as EventsScript
	var mgr := own(ManagerScript.new()) as ManagerScript
	mgr.events = bus
	mgr.set_cap(16)
	var even: int = mgr.spawn(ActorsScript.NONE, Vector2.ZERO, Vector2.ZERO, 10.0, 4.0, ManagerScript.LAYER_ENEMY)
	var curved: int = mgr.spawn(ActorsScript.NONE, Vector2(0.0, 50.0), Vector2.ZERO, 10.0, 4.0, ManagerScript.LAYER_ENEMY)
	check(mgr.move_shot(even, Vector2(100.0, 0.0), 0.5), "an even move")
	check(mgr.move_shot(curved, Vector2(100.0, 0.0), 0.5, 0.0, 0.0, LURCH), "a curved move")
	mgr.step(1.0 / 60.0)
	check(mgr.get_position_of(curved).x < mgr.get_position_of(even).x * 0.5, "the curved one lurches off (%s, %s)" % [mgr.get_position_of(curved).x, mgr.get_position_of(even).x])
	for i in 40:
		mgr.step(1.0 / 60.0)
	check(absf(mgr.get_position_of(even).x - 100.0) < 0.01, "the even one went its way (%s)" % mgr.get_position_of(even))
	check(absf(mgr.get_position_of(curved).x - 100.0) < 0.01, "and so did the curved one (%s)" % mgr.get_position_of(curved))
