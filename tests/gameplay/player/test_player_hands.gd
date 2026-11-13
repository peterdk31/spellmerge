extends "res://tests/support/suite.gd"
## Tests for hands that can be empty (items I2, docs/milestones/items.md): a wizard whose buttons
## hold a staff or none (`Caster.empty_hands`, `PlayerController.seat_wizard` with a null staff), with
## a gap between its staffs. The staffs it holds cast from their own buttons; an empty hand casts
## nothing, holds no mana, is never put on show and refuses the builder; the panel hears an empty
## plan for it; a snapshot keeps it. The real spell runtime and registry, the real wizard scene.
##
## godot --headless --path . --script res://tests/gameplay/player/test_player_hands.gd

const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")

## RB empty, RT a staff, LB empty, LT a staff: a gap at the start and between.
const CARDS: Array = [[], [&"bolt"], [], [&"bolt"]]
const START: Vector2 = Vector2(100.0, 100.0)

var _world: Fixture
var _curl: StaffBase
var _star: StaffBase


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_curl = _world.registry.get_resource(&"wizard", &"curl") as StaffBase
	_star = _world.registry.get_resource(&"wizard", &"star") as StaffBase


func after_each() -> void:
	_world.free_all()


func _gapped(seat: int = 0) -> Actor:
	var hands: Array[StaffBase] = [null, _curl, null, _star]
	return _world.wizard(seat, START, CARDS, null, true, hands)


func test_the_hands_say_which_hold_a_staff() -> void:
	check(_curl != null and _star != null, "the basic staffs are in the registry")
	var wizard: Actor = _gapped()
	var caster: Caster = wizard.caster
	check_equal(caster.empty_hands, 0b0101, "RB and LB are empty")
	for at in 4:
		check_equal(caster.holds(at), at % 2 == 1, "hand %d holds a staff only where one was put" % at)
	check_equal(caster.first_held(), 1, "the first staff is on RT")
	check_equal(caster.current, 1, "and it is the one on show at the start, not the empty RB")
	check(caster.has_staff(1) and caster.has_staff(3), "the held staffs are built")
	check(not caster.has_staff(0) and not caster.has_staff(2), "an empty hand has no build")
	check_equal(caster.cards_of(0), [] as Array[StringName], "nor cards")
	check_equal(caster.slot_count(2), 0, "nor slots")
	check_equal(caster.max_mana_of(0), 0.0, "nor a pool")
	check(caster.mana_of(3) > 0.0, "a held staff's pool is full")


func test_a_staff_past_a_gap_casts_from_its_own_button() -> void:
	var wizard: Actor = _gapped()
	var casts: Array = []
	_world.bus.staff_cast.connect(func(player: int, staff: int, _origin: Vector2, _direction: Vector2) -> void:
		casts.append([player, staff]))
	_world.hold(0, &"staff_4")
	_world.run(1)
	_world.release(0, &"staff_4")
	check_equal(casts, [[0, 3]], "LT casts its own staff, past the empty LB")
	check_equal(wizard.caster.current, 3, "and puts it on show")


func test_an_empty_hand_casts_nothing_and_is_not_shown() -> void:
	var wizard: Actor = _gapped()
	var casts: Array = []
	var shown: Array = []
	_world.bus.staff_cast.connect(func(_player: int, staff: int, _origin: Vector2, _direction: Vector2) -> void:
		casts.append(staff))
	_world.bus.staff_shown.connect(func(_actor_id: int, _actor: Node, at: int) -> void:
		shown.append(at))
	_world.run(2)
	for action: StringName in [&"staff_1", &"staff_3"]:
		_world.hold(0, action)
		_world.run(2)
		_world.release(0, action)
		_world.run(1)
	check(casts.is_empty(), "an empty hand casts nothing")
	check(shown.is_empty(), "and nothing goes on show")
	check_equal(wizard.caster.current, 1, "the staff on show stays")
	check_equal(Fixture.look(wizard).shown_staff(), 1, "and the look shows it")
	check_equal(wizard.caster.mana_of(0), 0.0, "an empty hand gets no mana back")


func test_the_panel_hears_an_empty_plan_for_an_empty_hand() -> void:
	var plans: Dictionary = {}
	_world.bus.staff_changed.connect(func(player: int, staff: int, plan: Dictionary) -> void:
		if player == 0:
			plans[staff] = plan)
	_gapped()
	_world.run(1)
	for at in 4:
		check(plans.has(at), "hand %d is announced" % at)
		check_equal((plans.get(at, {}) as Dictionary).is_empty(), at % 2 == 0, "hand %d's plan is empty only for an empty hand" % at)


func test_the_builder_cannot_put_a_card_on_an_empty_hand() -> void:
	var wizard: Actor = _gapped()
	var refused: Array[String] = []
	_world.bus.build_refused.connect(func(_player: int, reason: String) -> void:
		refused.append(reason))
	_world.bus.staff_change_requested.emit(0, 0, 0, &"bolt")
	var cards: Array[StringName] = [&"bolt"]
	_world.bus.staff_cards_requested.emit(0, 2, cards)
	_world.run(1)
	check_equal(refused, [PlayerController.EMPTY_HAND, PlayerController.EMPTY_HAND], "both requests are refused, with the reason")
	check(not wizard.caster.holds(0) and not wizard.caster.holds(2), "the hands stay empty")
	check_equal(wizard.caster.cards_of(0), [] as Array[StringName], "with no cards")
	_world.bus.staff_change_requested.emit(0, 3, 1, &"bolt")
	_world.run(1)
	check_equal(wizard.caster.cards_of(3)[1], &"bolt", "a held staff past the gap is still built")


## A wizard with every hand empty has nothing to cast or show, and stands as a bare staff.
func test_a_wizard_with_no_staff_at_all() -> void:
	var none: Array[StaffBase] = [null, null, null, null]
	var wizard: Actor = _world.wizard(0, START, Fixture.NO_CARDS, null, true, none)
	check_equal(wizard.caster.empty_hands, 0b1111, "every hand is empty")
	check_equal(wizard.caster.current, 0, "the first hand is on show")
	_world.hold(0, &"staff_1")
	_world.run(2)
	_world.release(0, &"staff_1")
	check(not wizard.caster.has_staff(0), "nothing casts")
	check_equal(PlayerController.staff_ids(wizard), [&"", &"", &"", &""] as Array[StringName], "no staff id is carried")


## A wizard without the `staffs` list (`staff` on every button) has no empty hand, as before.
func test_no_list_means_every_hand_holds_the_staff() -> void:
	var wizard: Actor = _world.wizard(0, START, CARDS, _curl)
	check_equal(wizard.caster.empty_hands, 0, "no empty hand")
	check(wizard.caster.has_staff(1) and wizard.caster.has_staff(3), "the staffs with cards are built")


func test_the_carried_ids_leave_an_empty_hand_empty() -> void:
	var wizard: Actor = _gapped()
	check_equal(PlayerController.staff_ids(wizard), [&"", &"curl", &"", &"star"] as Array[StringName], "an empty hand carries no id")


## A snapshot keeps which hands are empty and what is on show; restored after a change, the
## wizard is as it was.
func test_a_snapshot_keeps_the_empty_hands() -> void:
	var wizard: Actor = _gapped()
	_world.hold(0, &"staff_4")
	_world.run(1)
	_world.release(0, &"staff_4")
	_world.run(1)
	var areas: Dictionary = {"actors": _world.table, "projectiles": _world.projectiles, "spells": _world.spells, "combat": _world.combat}
	# Each body is an area of its own, as `Tick.state_areas` names it.
	areas["actor %d" % wizard.id] = wizard
	var snapshot := Snapshot.take(areas, root)
	check_equal(snapshot.problems.size(), 0, "taken without problems: %s" % [snapshot.problems])
	wizard.caster.empty_hands = 0
	wizard.caster.current = 0
	check_equal(snapshot.restore(areas, root).size(), 0, "restored without problems")
	check_equal(wizard.caster.empty_hands, 0b0101, "the empty hands come back")
	check_equal(wizard.caster.current, 3, "and the staff on show")
	_world.hold(0, &"staff_1")
	_world.run(1)
	_world.release(0, &"staff_1")
	check(not wizard.caster.has_staff(0), "RB is empty still")


func test_seat_wizard_marks_a_short_list_and_nulls_as_empty() -> void:
	var body := Fixture.WizardScene.instantiate() as Actor
	var short: Array[StaffBase] = [_curl, null]
	PlayerController.seat_wizard(body, 0, null, Fixture.NO_CARDS.duplicate(true), short)
	var caster: Caster = null
	for child in body.get_children():
		if child is Caster:
			caster = child as Caster
	check(caster != null, "the wizard scene has a Caster")
	if caster != null:
		check_equal(caster.empty_hands, 0b1110, "RT by its null, LB and LT past the list's end")
	body.free()


## `replace_staffs` says every hand anew: a null one is empty, one given a staff holds it, and the
## staff on show moves off a hand that is emptied.
func test_replace_staffs_says_every_hand() -> void:
	var wizard: Actor = _gapped()
	var cards: Array = [[&"bolt"], [], [&"bolt"]]
	var hands: Array[StaffBase] = [_star, null, _curl]
	wizard.caster.replace_staffs(hands, cards)
	check_equal(wizard.caster.empty_hands, 0b010, "RT is empty now, RB and LB hold staffs")
	check(wizard.caster.has_staff(0) and wizard.caster.has_staff(2), "and are built")
	check_equal(wizard.caster.current, 0, "the staff on show left the emptied RT for RB")
