extends "res://tests/support/suite.gd"
## Tests for the inventory's hands and drops (items I7, gameplay/actor/inventory.gd, "Hands and
## drops"; `Caster.empty_hand`): a staff from the bag onto a hand (the staff there into the bag), from
## one hand onto another (the two change places) and off a hand into the bag, each keeping its
## number, its cards and its mana; a staff or a card dropped; every refusal changes nothing; and the
## player controller's commands (`staff_hand_requested`, `bag_drop_requested`), whose refusals are
## `inventory_refused`, every request refused while the body is down (items I7b).
const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")

const CARDS: StringName = &"cards"
const STAFFS: StringName = &"staffs"

var _world: Fixture
var _staff: StaffBase
var _other: StaffBase
## Every item_drop_requested [actor, kind, id, count, cards, mana], inventory_refused [player, reason]
## and hands_changed of the wizard's inventory.
var _dropped: Array = []
var _refused: Array = []
var _hands_said: int = 0


func before_each() -> void:
	_world = Fixture.new(root, true)
	_staff = StaffBase.new()
	_staff.id = &"test"
	_staff.slots = 3
	_staff.max_mana = 100.0
	_other = StaffBase.new()
	_other.id = &"other"
	_other.slots = 2
	_other.max_mana = 50.0
	_dropped.clear()
	_refused.clear()
	_hands_said = 0
	_world.bus.item_drop_requested.connect(func(actor: int, stack: ItemStack) -> void: _dropped.append([actor, stack.kind, stack.id, stack.count, stack.cards.duplicate(), stack.mana]))
	_world.bus.inventory_refused.connect(func(player: int, reason: String) -> void: _refused.append([player, reason]))


func after_each() -> void:
	_world.free_all()


## A wizard holding `_staff` on RB (with a bolt) and LB (RT and LT empty), `_other` (with a fire)
## as staff 4 in its bag, and the card bag `bag`.
func _wizard(bag: Dictionary = {&"bolt": 2, &"fire": 1}) -> Actor:
	var hands: Array[StaffBase] = [_staff, null, _staff, null]
	var body: Actor = _world.wizard(0, Vector2.ZERO, [[&"bolt"], [], [], []], null, false, hands)
	PlayerController.seat_wizard(body, 0, null, [[&"bolt"], [], [], []], hands, bag)
	_world.add(body)
	var bagged := ItemStack.of_staff(_other, _ids("fire"))
	bagged.mana = 30.0
	check(body.inventory.add(bagged), "a staff in the bag")
	body.inventory.hands_changed.connect(func() -> void: _hands_said += 1)
	return body


func _ids(words: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for word in words.split(" ", false):
		out.append(StringName(word) if word != "-" else &"")
	return out


func test_a_staff_from_the_bag_goes_on_an_empty_hand() -> void:
	var body := _wizard()
	var inventory: Inventory = body.inventory
	check_equal(inventory.set_hand(4, 1), Inventory.Refusal.NONE, "onto RT")
	check_equal(inventory.hands(), PackedInt32Array([0, 4, 2, Inventory.NO_STAFF]), "RT holds it, under its number")
	check_equal(inventory.copies(STAFFS), 0, "out of the bag")
	check(body.caster.holds(1), "its Caster's RT holds it")
	check_equal(body.caster.staff_of(1), _other, "the staff itself")
	check_equal(body.caster.cards_of(1), _ids("fire -"), "with its cards")
	check_equal(body.caster.mana_of(1), 30.0, "and the mana it kept in the bag")
	check_equal(inventory.count_of(CARDS, &"fire"), 1, "nothing was counted")
	check_equal(_hands_said, 1, "the hands were said")


func test_a_staff_from_the_bag_sends_the_one_on_that_hand_into_the_bag() -> void:
	var body := _wizard()
	var inventory: Inventory = body.inventory
	body.caster.set_mana(0, 40.0)
	check_equal(inventory.set_hand(4, 0), Inventory.Refusal.NONE, "onto RB")
	check_equal(inventory.hands()[0], 4, "RB holds it")
	check_equal(inventory.copies(STAFFS), 1, "one staff in the bag still")
	var bagged: ItemStack = inventory.stacks_in(STAFFS)[0]
	check_equal(bagged.number, 0, "RB's old staff, under its own number")
	check_equal(bagged.cards, _ids("bolt - -"), "with its cards")
	check_equal(bagged.mana, 40.0, "and the mana it had on the hand")
	check_equal(body.caster.cards_of(0), _ids("fire -"), "the Caster's RB is the new one")
	check_equal(inventory.set_hand(0, 0), Inventory.Refusal.NONE, "and back again")
	check_equal(body.caster.mana_of(0), 40.0, "with the mana it left with: no refill")


func test_a_staff_from_another_hand_changes_places() -> void:
	var body := _wizard()
	var inventory: Inventory = body.inventory
	check_equal(inventory.set_cards(2, _ids("fire")), Inventory.Refusal.NONE, "LB built")
	body.caster.set_mana(0, 10.0)
	body.caster.set_mana(2, 70.0)
	check_equal(inventory.set_hand(0, 2), Inventory.Refusal.NONE, "RB's staff onto LB")
	check_equal(inventory.hands(), PackedInt32Array([2, Inventory.NO_STAFF, 0, Inventory.NO_STAFF]), "the two changed places")
	check_equal(body.caster.cards_of(2), _ids("bolt - -"), "LB holds RB's cards")
	check_equal(body.caster.cards_of(0), _ids("fire - -"), "RB holds LB's")
	check_equal([body.caster.mana_of(0), body.caster.mana_of(2)], [70.0, 10.0], "each with its own mana")
	check_equal(inventory.copies(STAFFS), 1, "the bag is as it was")
	check_equal(inventory.set_hand(2, 3), Inventory.Refusal.NONE, "onto the empty LT")
	check_equal(inventory.hands(), PackedInt32Array([Inventory.NO_STAFF, Inventory.NO_STAFF, 0, 2]), "RB is empty now")
	check(not body.caster.holds(0), "and so is the Caster's")


func test_a_staff_off_its_hand_goes_into_the_bag_and_keeps_its_mana() -> void:
	var body := _wizard()
	var inventory: Inventory = body.inventory
	body.caster.set_mana(0, 25.0)
	check_equal(body.caster.current, 0, "RB on show")
	check_equal(inventory.set_hand(0, Inventory.NO_HAND), Inventory.Refusal.NONE, "into the bag")
	check_equal(inventory.hands()[0], Inventory.NO_STAFF, "RB is empty")
	check(not body.caster.holds(0), "the Caster's too")
	check_equal(body.caster.cards_of(0), [] as Array[StringName], "with no cards")
	check_equal(body.caster.current, 2, "LB is on show now")
	check_equal(inventory.copies(STAFFS), 2, "two staffs in the bag")
	check_equal(inventory.staff(0).mana, 25.0, "the mana it had")
	check_equal(inventory.cards_of(0), _ids("bolt - -"), "and its cards")
	_world.run(30)
	check_equal(inventory.staff(0).mana, 25.0, "a staff in the bag regains none")


func test_every_refusal_changes_nothing() -> void:
	var body := _wizard()
	var inventory: Inventory = body.inventory
	check_equal(inventory.set_hand(9, 1), Inventory.Refusal.NO_STAFF, "a staff it does not own")
	check_equal(inventory.set_hand(4, 4), Inventory.Refusal.NO_HAND, "a hand past the last")
	check_equal(inventory.set_hand(4, -2), Inventory.Refusal.NO_HAND, "a hand before the first")
	check_equal(inventory.set_hand(0, 0), Inventory.Refusal.NONE, "the hand it is on: nothing to do")
	inventory.set_capacity(STAFFS, 1)
	check_equal(inventory.set_hand(0, Inventory.NO_HAND), Inventory.Refusal.NO_ROOM, "the staff bag is full")
	check_equal(inventory.drop_staff(9), Inventory.Refusal.NO_STAFF, "drop a staff it does not own")
	check_equal(inventory.drop(CARDS, &"rune"), Inventory.Refusal.NO_ITEM, "a card it has none of")
	check_equal(inventory.drop(STAFFS, &"other"), Inventory.Refusal.NO_ITEM, "a staff by its id: by number only")
	check_equal(inventory.drop(&"nowhere", &"bolt"), Inventory.Refusal.NO_ITEM, "a bag there is not")
	body.caster.empty_hands |= 1 << 2
	check_equal(inventory.set_hand(2, 1), Inventory.Refusal.NO_STAFF, "a hand the Caster lost")
	check_equal(inventory.drop_staff(2), Inventory.Refusal.NO_STAFF, "nor dropped from it")
	check_equal(inventory.hands(), PackedInt32Array([0, Inventory.NO_STAFF, 2, Inventory.NO_STAFF]), "the hands are as they were")
	check_equal(inventory.copies(STAFFS), 1, "and the bag")
	check(body.caster.holds(0) and body.caster.cards_of(0) == _ids("bolt - -"), "and the Caster's RB")
	check(_dropped.is_empty() and _hands_said == 0, "nothing dropped, nothing said")


func test_a_staff_dropped_lies_down_with_its_cards_and_mana() -> void:
	var body := _wizard()
	var inventory: Inventory = body.inventory
	body.caster.set_mana(0, 60.0)
	check_equal(inventory.drop_staff(0), Inventory.Refusal.NONE, "RB's staff dropped")
	check_equal(inventory.hands()[0], Inventory.NO_STAFF, "off its hand")
	check(not body.caster.holds(0), "and the Caster's")
	check(inventory.staff(0) == null and inventory.plan_of(0).is_empty(), "no longer owned")
	check_equal(_dropped, [[body.id, ItemKinds.STAFF, &"test", 1, _ids("bolt - -"), 60.0]], "on the ground with its cards and the mana it had")
	check_equal(_hands_said, 1, "the hands were said")
	check_equal(inventory.count_of(CARDS, &"bolt"), 2, "its cards went with it: not the bag's")
	check_equal(inventory.drop_staff(4), Inventory.Refusal.NONE, "the bag's staff dropped")
	check_equal(inventory.copies(STAFFS), 0, "the bag is empty")
	check_equal(_dropped.back(), [body.id, ItemKinds.STAFF, &"other", 1, _ids("fire -"), 30.0], "with its own")


func test_a_card_dropped_is_one_copy() -> void:
	var body := _wizard()
	var inventory: Inventory = body.inventory
	check_equal(inventory.drop(CARDS, &"bolt"), Inventory.Refusal.NONE, "one bolt")
	check_equal(inventory.count_of(CARDS, &"bolt"), 1, "one left")
	check_equal(_dropped, [[body.id, ItemKinds.CARD, &"bolt", 1, [] as Array[StringName], 0.0]], "one copy on the ground")
	check_equal(inventory.drop(CARDS, &"bolt"), Inventory.Refusal.NONE, "the last")
	check_equal(inventory.drop(CARDS, &"bolt"), Inventory.Refusal.NO_ITEM, "none left")
	check(not inventory.stacks_in(CARDS).any(func(stack: ItemStack) -> bool: return stack.id == &"bolt"), "gone from the bag")


## The empty hand of the Caster: it casts nothing, holds no mana and comes back as it left.
func test_an_emptied_hand_casts_nothing_and_holds_no_mana() -> void:
	var body := _wizard()
	check(body.caster.has_staff(0), "RB casts before")
	check_equal(body.caster.empty_hand(0), 100.0, "the mana it held")
	check(not body.caster.has_staff(0), "nothing after")
	check_equal(body.caster.mana_of(0), 0.0, "no mana")
	check_equal(body.caster.max_mana_of(0), 0.0, "no pool")
	check(body.caster.plan_of(0).is_empty(), "no plan")
	check_equal(body.caster.empty_hand(0), -1.0, "an empty hand empties nothing")


func test_the_commands_go_to_the_seats_own_inventory() -> void:
	var body := _wizard()
	_world.bus.staff_hand_requested.emit(0, 4, 3, _world.body_key(0))
	check_equal(body.inventory.hands()[3], 4, "seat 0 put staff 4 on LT")
	_world.bus.staff_hand_requested.emit(1, 0, 1, _world.body_key(1))
	check_equal(body.inventory.hands()[1], Inventory.NO_STAFF, "another seat's request is not this one's")
	_world.bus.bag_drop_requested.emit(0, CARDS, &"fire", Inventory.NO_STAFF, _world.body_key(0))
	check_equal(body.inventory.count_of(CARDS, &"fire"), 0, "a fire dropped")
	_world.bus.bag_drop_requested.emit(0, STAFFS, &"test", 2, _world.body_key(0))
	check_equal(body.inventory.hands()[2], Inventory.NO_STAFF, "LB's staff dropped by its number")
	check_equal(_dropped.size(), 2, "both on the ground")
	check(_refused.is_empty(), "nothing refused")
	_world.bus.staff_hand_requested.emit(0, 9, 1, _world.body_key(0))
	_world.bus.bag_drop_requested.emit(0, CARDS, &"rune", Inventory.NO_STAFF, _world.body_key(0))
	check_equal(_refused, [[0, PlayerController.NO_STAFF], [0, PlayerController.NO_ITEM]], "refusals are said in words, to the seat")


## Items I7b: a downed body's builder and inventory requests are refused by the simulation, each
## in words and changing nothing (the HUD closes both menus, but a late frame can still bring one).
func test_a_downed_body_refuses_every_request() -> void:
	var body := _wizard()
	var built: Array = []
	_world.bus.build_refused.connect(func(player: int, reason: String) -> void: built.append([player, reason]))
	_world.hurt(body, 1000)
	_world.run(1)
	check(body.is_down(), "the wizard is down")
	var hands: PackedInt32Array = body.inventory.hands()
	var cards: Array[StringName] = body.inventory.plan_of(0).get("cards", []).duplicate()
	var fire: int = body.inventory.count_of(CARDS, &"fire")
	_world.bus.staff_hand_requested.emit(0, 4, 1, _world.body_key(0))
	_world.bus.bag_drop_requested.emit(0, CARDS, &"fire", Inventory.NO_STAFF, _world.body_key(0))
	_world.bus.bag_drop_requested.emit(0, STAFFS, &"test", 2, _world.body_key(0))
	_world.bus.staff_change_requested.emit(0, 0, 1, &"fire", _world.body_key(0))
	_world.bus.staff_cards_requested.emit(0, 0, _ids("- fire"), _world.body_key(0))
	check_equal(body.inventory.hands(), hands, "no staff moved")
	check_equal(body.inventory.count_of(CARDS, &"fire"), fire, "no card dropped or spent")
	check_equal(body.inventory.plan_of(0).get("cards", []), cards, "the staff unbuilt")
	check(_dropped.is_empty(), "nothing on the ground")
	check_equal(_refused, [[0, PlayerController.NO_DOWN], [0, PlayerController.NO_DOWN], [0, PlayerController.NO_DOWN]], "the inventory's refused in words")
	check_equal(built, [[0, PlayerController.NO_DOWN], [0, PlayerController.NO_DOWN]], "and the builder's")
	Fixture.downed(body).revive(1)
	_world.run(1)
	check(not body.is_down(), "up again")
	_world.bus.staff_hand_requested.emit(0, 4, 1, _world.body_key(0))
	check_equal(body.inventory.hands()[1], 4, "requests are heard again once up")


## The commands cross the wire as every other: a frame with them decodes to the same.
func test_the_commands_cross_a_frame() -> void:
	var frame := InputFrame.new()
	check(frame.add_command(&"staff_hand_requested", [4, -1, 5]), "a staff into the bag")
	check(frame.add_command(&"bag_drop_requested", [CARDS, &"bolt", -1, 5]), "a card dropped")
	check(not frame.add_command(&"bag_drop_requested", [CARDS, "res://x", -1, 5]), "a path is no id")
	var back: InputFrame = InputFrame.from_bytes(frame.to_bytes())
	check(back != null, "decodes")
	check_equal(back.commands, frame.commands, "the same commands")


## Review: a staff put on a hand is drawn and waits its own cooldown, so moving staffs between hands
## skips no delay (the delay is the hand's in Spells; the staff's own cooldown holds it).
func test_a_staff_moved_onto_a_hand_waits_its_own_cooldown() -> void:
	var body := _wizard()
	_staff.cooldown = 0.5
	_other.cooldown = 1.5
	check_equal(body.inventory.set_hand(4, 1), Inventory.Refusal.NONE, "the bag's staff onto RT")
	check(_world.spells.cooldown_left(body.id, 1) >= 1.5, "RT waits its staff's cooldown (%s)" % _world.spells.cooldown_left(body.id, 1))
	check_equal(body.inventory.set_hand(0, 1), Inventory.Refusal.NONE, "RB's staff onto RT: they change places")
	check(_world.spells.cooldown_left(body.id, 0) >= 1.5, "RB waits the longer staff's cooldown")


## Review: the staff on show moves to a hand still held when its own is emptied, and with no hand
## held nothing empty is put on show.
func test_the_staff_on_show_moves_to_a_hand_still_held() -> void:
	var body := _wizard()
	var shown: Array[int] = []
	_world.bus.staff_shown.connect(func(_actor: int, _body: Node, at: int) -> void: shown.append(at))
	check_equal(body.caster.current, 0, "RB on show")
	body.caster.empty_hand(0)
	check_equal(body.caster.current, 2, "LB, the hand still held")
	check_equal(shown, [2] as Array[int], "said once")
	body.caster.empty_hand(2)
	check_equal(body.caster.current, 2, "no hand held: it stays")
	check_equal(shown, [2] as Array[int], "and no empty hand is put on show")


## Review: a kind that does not stack drops its stack itself, whatever it holds.
func test_a_kind_that_does_not_stack_drops_its_own_stack() -> void:
	var body := _wizard()
	var relic := ItemStack.new()
	relic.kind = &"relic"
	relic.id = &"charm"
	relic.count = 1
	relic.mana = 7.0
	if not ItemKinds.has(&"relic"):
		check(true, "no relic kind yet")
		return
	check(body.inventory.add(relic), "a relic in its bag")
	var bag: StringName = ItemKinds.bag_of(&"relic")
	check_equal(body.inventory.drop(bag, &"charm"), Inventory.Refusal.NONE, "dropped")
	check_equal(body.inventory.copies(bag), 0, "its bag is empty")
	check_equal(_dropped.back()[5], 7.0, "the stack itself went, with what it held")
