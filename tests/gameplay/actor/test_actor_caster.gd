extends "res://tests/support/suite.gd"
## The Caster (actors G4): staffs built and installed in the real Spells under the actor's caster
## number (its actor id, opened in Spells with the actor and closed when it leaves); casts from the intent (a
## press, or a hold while no sustained card is on) from the staff tip along the aim, paying mana;
## mana back each step and from siphon; `cast_ready` for an AI's windup; one compiled staff shared
## by every caster of the same staff and cards. Its cards' moves move the actor (ported from
## tests/gameplay/ai/test_ai_moves.gd: a dash and its blast, a teleport, a recoil).
##
## godot --headless --path . --script res://tests/gameplay/actor/test_actor_caster.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const StaffKit := preload("res://tests/support/staff_kit.gd")

var _world: Fixture


func after_each() -> void:
	if _world != null:
		_world.free_all()
	_world = null


func _seated(seat: int, cards: Array, at: Vector2 = Vector2.ZERO) -> Actor:
	var controller := Fixture.Scripted.new()
	controller.team = ActorsScript.TEAM_WIZARDS
	controller.seat = seat
	return _world.actor(at, [&"mover", &"caster"], controller, cards)


func _creature(cards: Array, at: Vector2 = Vector2.ZERO) -> Actor:
	return _world.actor(at, [&"mover", &"caster"], Fixture.Scripted.new(), cards)


func _press(body: Actor, staff: int = 0) -> void:
	(body.controller as Fixture.Scripted).presses.append(staff)


func test_every_actor_casts_under_its_actor_id_opened_and_closed_with_it() -> void:
	_world = Fixture.new(root)
	var wizard: Actor = _seated(2, [[&"bolt"]])
	var imp: Actor = _creature([[&"fire", &"bolt"]])
	check(wizard.id >= 0 and imp.id >= 0 and wizard.id != imp.id, "two actor ids: %d, %d" % [wizard.id, imp.id])
	check_equal(wizard.caster_number(), wizard.id, "a seated actor casts under its actor id")
	check_equal(imp.caster_number(), imp.id, "and so does a creature")
	check_equal(wizard.caster.number, wizard.id, "its Caster has the number")
	var number: int = imp.caster_number()
	check(_world.spells.current_tag(number, 0) != 0, "its staff is installed in Spells under it")
	root.remove_child(imp)
	check_equal(_world.spells.current_tag(number, 0), 0, "and closed in Spells when the actor leaves")
	check_equal(imp.caster_number(), -1, "it has none out of the tree")
	root.add_child(imp)
	check_equal(imp.caster_number(), imp.id, "back in the tree it casts under its id again")
	check(imp.caster.has_staff(0), "with its staff installed again")


func test_a_press_casts_from_the_staff_tip_along_the_aim_and_pays() -> void:
	_world = Fixture.new(root)
	var wizard: Actor = _seated(0, [[&"bolt"]], Vector2(100.0, 100.0))
	wizard.hand_offset = Vector2(0.0, -10.0)
	wizard.staff_reach = 14.0
	(wizard.controller as Fixture.Scripted).aim = Vector2.RIGHT
	var casts: Array = []
	wizard.caster.cast_done.connect(func(staff: int, origin: Vector2, direction: Vector2) -> void: casts.append([staff, origin, direction]))
	_world.run(1)
	var mana: float = wizard.caster.mana
	_press(wizard)
	wizard.step(Fixture.STEP)
	check_equal(casts, [[0, Vector2(114.0, 90.0), Vector2.RIGHT]], "cast from the tip along the aim")
	check(_world.projectiles.get_count() > 0, "a shot flies")
	check(wizard.caster.mana < mana, "mana was paid")
	check_equal(wizard.caster.last_form(0), &"bolt", "the carrier is named")


func test_a_held_staff_casts_whenever_it_is_ready_and_a_free_one_does_not() -> void:
	_world = Fixture.new(root)
	var wizard: Actor = _seated(0, [[&"bolt"], [&"bolt"]])
	var count: Array[int] = [0, 0]
	wizard.caster.cast_done.connect(func(staff: int, _origin: Vector2, _direction: Vector2) -> void: count[staff] += 1)
	(wizard.controller as Fixture.Scripted).held = [0] as Array[int]
	_world.run(40)
	check(count[0] > 1, "a held staff casts again and again: %d" % count[0])
	check_equal(count[1], 0, "a staff not pressed or held casts nothing")


func test_an_actor_without_a_controller_casts_nothing() -> void:
	_world = Fixture.new(root)
	var wizard: Actor = _seated(0, [[&"bolt"]])
	(wizard.controller as Fixture.Scripted).held = [0] as Array[int]
	wizard.drive(null)
	_world.run(4)
	check_equal(_world.projectiles.get_count(), 0, "no controller, no cast")


func test_a_down_actor_cannot_cast() -> void:
	_world = Fixture.new(root)
	var wizard: Actor = _seated(0, [[&"bolt"]])
	wizard.set_down(true)
	check(not wizard.caster.cast(0), "down, no cast")
	_press(wizard)
	_world.run(1)
	check_equal(_world.projectiles.get_count(), 0, "nothing flies")


func test_mana_comes_back_up_to_the_most_and_siphon_refunds_it() -> void:
	_world = Fixture.new(root)
	var wizard: Actor = _seated(1, [[&"bolt"]])
	wizard.caster.mana = 10.0
	_world.run(16)
	check(is_equal_approx(wizard.caster.mana, 10.0 + wizard.caster.regen), "a second of regen: %f" % wizard.caster.mana)
	_world.bus.mana_refund_requested.emit(wizard.id, 5.0)
	check(is_equal_approx(wizard.caster.mana, 15.0 + wizard.caster.regen), "siphon refunds its actor id")
	_world.bus.mana_refund_requested.emit(wizard.id + 1, 5.0)
	_world.bus.mana_refund_requested.emit(wizard.id, -3.0)
	check(is_equal_approx(wizard.caster.mana, 15.0 + wizard.caster.regen), "another number's or a negative refund changes nothing")
	_world.bus.mana_refund_requested.emit(wizard.id, 1000.0)
	check_equal(wizard.caster.mana, wizard.caster.max_mana, "never above the most")
	var imp: Actor = _creature([[&"fire", &"bolt"]])
	imp.caster.mana = 10.0
	_world.bus.mana_refund_requested.emit(imp.id, 5.0)
	check(is_equal_approx(imp.caster.mana, 15.0), "a creature's refund comes by the same event: %f" % imp.caster.mana)


func test_cast_ready_waits_for_the_delay_and_the_mana() -> void:
	_world = Fixture.new(root)
	var staff: StaffBase = StaffKit.plain_staff(2)
	staff.cast_delay = 0.5
	var imp: Actor = _world.actor(Vector2.ZERO, [&"caster"], Fixture.Scripted.new(), [[&"fire", &"bolt"]], staff)
	check(imp.caster.next_cast_mana() > 0.0, "the next cast costs mana")
	check(imp.caster.next_cast_reach() > 0.0, "and reaches along the aim")
	check(imp.caster.next_cast_radius() > 0.0, "with a width")
	check(imp.caster.cast_ready(0.0), "ready at once with full mana")
	_press(imp)
	_world.run(1)
	check(not imp.caster.cast_ready(0.1), "not within its delay")
	check(imp.caster.cast_ready(_world.spells.cooldown_left(imp.caster_number(), 0)), "but within a windup as long as it")
	imp.caster.mana = 0.0
	imp.caster.regen = 0.0
	check(not imp.caster.cast_ready(5.0), "never without the mana")


func test_one_compiled_staff_serves_every_caster_of_the_same_cards() -> void:
	_world = Fixture.new(root)
	var staff: StaffBase = StaffKit.plain_staff(2)
	var before: int = Caster._cache.size()
	for i in 3:
		_world.actor(Vector2.ZERO, [&"caster"], Fixture.Scripted.new(), [[&"fire", &"bolt"]], staff)
	check_equal(Caster._cache.size() - before, 1, "three imps of one staff compiled it once")


func test_set_staff_pads_to_the_slots_and_says_it_built() -> void:
	_world = Fixture.new(root)
	var wizard: Actor = _seated(0, [[], [], [], []])
	var built: Array[int] = []
	wizard.caster.staff_built.connect(func(staff: int) -> void: built.append(staff))
	check(wizard.caster.set_staff(3, [&"bolt"] as Array[StringName]), "a staff that exists")
	check_equal(wizard.caster.cards_of(3), [&"bolt", &"", &"", &""] as Array[StringName], "padded to the slots")
	check(wizard.caster.has_staff(3), "and it can cast")
	check(not wizard.caster.set_staff(4, [&"bolt"] as Array[StringName]), "no fifth staff")
	check_equal(built, [3] as Array[int], "staff_built for the one built")
	check_equal(wizard.caster.plan_of(3).is_empty(), false, "a builder's plan of it")


func test_a_dash_card_dashes_the_actor_and_its_blast_goes_off_where_it_ends() -> void:
	_world = Fixture.new(root, _move_cards())
	var finished: Array = []
	var areas: Array = []
	_world.bus.caster_move_finished.connect(func(player: int, mode: StringName, at: Vector2, tag: int) -> void: finished.append([player, mode, at, tag]))
	_world.bus.cue_shown.connect(func(player: int, _cue: StringName, at: Vector2, _direction: Vector2, radius: float, _tint: Color, _look: int) -> void: areas.append([player, at, radius]))
	var imp: Actor = _creature([[&"blast", &"dash"]])
	(imp.controller as Fixture.Scripted).aim = Vector2.RIGHT
	_world.run(1)
	var tag: int = _world.spells.current_tag(imp.caster_number(), 0)
	_press(imp)
	_world.run(1)
	check(imp.mover.is_moving(), "the actor dashes")
	_world.run(8)
	check(not imp.mover.is_moving(), "for the card's time")
	check(is_equal_approx(imp.position.x, 60.0), "the card's distance along its aim (%.2f)" % imp.position.x)
	check(finished.size() == 1 and finished[0][0] == imp.id and finished[0][1] == &"dash" and finished[0][3] == tag, "it says where it ended, under its actor id: %s" % [finished])
	check(areas.size() == 1 and (areas[0][1] as Vector2).is_equal_approx(imp.position), "the card's blast goes off there")


func test_a_dash_the_actor_casts_goes_the_way_it_walks_not_the_way_it_aims() -> void:
	# Owner, R4 F1 option (b): a dash its own body casts goes the way it walks (staffs A6a);
	# with no walk, along the aim.
	_world = Fixture.new(root, _move_cards())
	var walker: Actor = _creature([[&"dash"]])
	(walker.controller as Fixture.Scripted).aim = Vector2.RIGHT
	(walker.controller as Fixture.Scripted).move = Vector2.UP
	var stander: Actor = _creature([[&"dash"]], Vector2(0.0, 200.0))
	(stander.controller as Fixture.Scripted).aim = Vector2.RIGHT
	_world.run(1)
	_press(walker)
	_press(stander)
	var from: Vector2 = walker.position
	_world.run(9)
	check(absf(walker.position.x) < 0.01 and from.y - walker.position.y > 59.0, "the walker dashes up, the way it walks (%s)" % walker.position)
	check(is_equal_approx(stander.position.x, 60.0), "the stander dashes along its aim (%s)" % stander.position)


func test_a_mirrored_dash_goes_the_walk_way_and_back_and_ends_where_it_started() -> void:
	_world = Fixture.new(root, _move_cards())
	var walker: Actor = _creature([[&"mirror", &"dash"]])
	(walker.controller as Fixture.Scripted).aim = Vector2.RIGHT
	_world.run(1)
	var from: Vector2 = walker.position
	(walker.controller as Fixture.Scripted).move = Vector2.UP
	_press(walker)
	_world.run(1)
	(walker.controller as Fixture.Scripted).move = Vector2.ZERO
	_world.run(9)
	check(absf(walker.position.x - from.x) < 0.01, "nothing along the aim (%s)" % walker.position)
	check(absf(walker.position.y - from.y) < 8.0, "the two dashes cancel, give or take the step it walked (%s from %s)" % [walker.position, from])


func test_a_teleport_card_jumps_and_a_recoil_card_pushes_back() -> void:
	_world = Fixture.new(root, _move_cards())
	var jumper: Actor = _creature([[&"teleport"]])
	var shooter: Actor = _seated(0, [[&"recoil", &"bolt"]], Vector2(0.0, 200.0))
	for body: Actor in [jumper, shooter]:
		(body.controller as Fixture.Scripted).aim = Vector2.RIGHT
	_world.run(1)
	_press(jumper)
	_press(shooter)
	_world.run(12)
	check(is_equal_approx(jumper.position.x, 70.0), "a teleport lands its distance along the aim (%.2f)" % jumper.position.x)
	check(is_equal_approx(shooter.position.x, -30.0), "a recoil pushes the recoil's distance back (%.2f)" % shooter.position.x)


## Cards for the moves (as tests/gameplay/ai/test_ai_moves.gd makes them).
func _move_cards() -> Fixture.FakeRegistry:
	var fake := Fixture.FakeRegistry.new()
	var bolt := FormBase.new()
	bolt.base_damage = 5
	bolt.speed = 200.0
	bolt.lifetime = 1.0
	bolt.radius = 4.0
	bolt.mana_cost = 2.0
	_put(fake, bolt, &"bolt")
	var dash := FormBase.new()
	dash.motion = FormBase.Motion.DASH
	dash.ray_length = 60.0
	dash.speed = 300.0
	dash.lifetime = 0.2
	dash.mana_cost = 2.0
	_put(fake, dash, &"dash")
	var teleport := FormBase.new()
	teleport.motion = FormBase.Motion.TELEPORT
	teleport.ray_length = 70.0
	teleport.mana_cost = 2.0
	_put(fake, teleport, &"teleport")
	var recoil := ModifierBase.new()
	recoil.behaviour = ModifierBase.Behaviour.RECOIL
	recoil.behaviour_strength = 30.0
	_put(fake, recoil, &"recoil")
	var mirror := ModifierBase.new()
	mirror.behaviour = ModifierBase.Behaviour.MIRROR
	mirror.behaviour_strength = 1.0
	_put(fake, mirror, &"mirror")
	var blast := ModifierBase.new()
	blast.behaviour = ModifierBase.Behaviour.BLAST
	blast.behaviour_strength = 20.0
	_put(fake, blast, &"blast")
	return fake


func _put(fake: Fixture.FakeRegistry, component: SpellComponent, id: StringName) -> void:
	component.id = id
	component.display_name = String(id).capitalize()
	component.complexity = 1
	fake.items[id] = component
