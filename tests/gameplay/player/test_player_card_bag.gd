extends "res://tests/support/suite.gd"
## Tests for the seat's counted card bag (items I3, docs/milestones/items.md): the run mode's bag
## handed over with `seat_wizard` (card id to copies), every card of the registry
## Inventory.DEV_COPIES times when none was given; every builder request counted (a card put in
## takes a copy, one taken out gives it back, a card with none left is refused); the inventory's
## events (`bag_changed`, `owned_staff_changed`, `hands_changed`) for the seat.
##
## godot --headless --path . --script res://tests/gameplay/player/test_player_card_bag.gd

const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const CARDS: StringName = &"cards"


## A registry that knows only the cards a test puts in it.
class FakeRegistry:
	extends RegistryScript
	var items: Dictionary = {}

	func get_ids(folder: StringName) -> Array[StringName]:
		var ids: Array[StringName] = []
		if folder == &"spells":
			for id: StringName in items:
				ids.append(id)
		return ids

	func get_resource(folder: StringName, id: StringName) -> Resource:
		return items.get(id) if folder == &"spells" else null


var _world: Fixture
var _registry: FakeRegistry
## Every bag_changed as [player, bag, ids, counts, capacity].
var _bags: Array = []
## Every build_refused as [player, reason].
var _refused: Array = []
## Every owned_staff_changed as [player, staff], and every hands_changed as [player, hands].
var _owned_staffs: Array = []
var _hands: Array = []


func before_each() -> void:
	_world = Fixture.new(root, true)
	_registry = FakeRegistry.new()
	for id: StringName in [&"dash", &"fire", &"bolt", &"rune", &"split"]:
		var card := SpellComponent.new()
		card.id = id
		_registry.items[id] = card
	_bags.clear()
	_refused.clear()
	_owned_staffs.clear()
	_hands.clear()
	_world.bus.bag_changed.connect(func(player: int, bag: StringName, ids: Array[StringName], counts: PackedInt32Array, capacity: int) -> void: _bags.append([player, bag, ids, counts, capacity]))
	_world.bus.build_refused.connect(func(player: int, reason: String) -> void: _refused.append([player, reason]))
	_world.bus.owned_staff_changed.connect(func(player: int, staff: int, _plan: Dictionary) -> void: _owned_staffs.append([player, staff]))
	_world.bus.hands_changed.connect(func(player: int, hands: PackedInt32Array) -> void: _hands.append([player, hands]))


func after_each() -> void:
	_world.free_all()
	_registry.free()


## The wizard of `seat` with the card bag `bag` (empty: none given), reading `_registry`.
func _wizard(seat: int, bag: Dictionary = {}, cards: Array = Fixture.NO_CARDS) -> Actor:
	var body: Actor = _world.wizard(seat, Vector2(40.0 * seat, 0.0), cards, null, false)
	PlayerController.seat_wizard(body, seat, null, cards.duplicate(true), [], bag)
	Fixture.controller(body).registry = _registry
	_world.add(body)
	return body


func _ids(words: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for word in words.split(" ", false):
		out.append(StringName(word) if word != "-" else &"")
	return out


## The last bag_changed of `bag`.
func _last(bag: StringName) -> Array:
	for at in range(_bags.size() - 1, -1, -1):
		if _bags[at][1] == bag:
			return _bags[at]
	return []


func test_without_a_bag_it_holds_dev_copies_of_every_card() -> void:
	var body := _wizard(0)
	check_equal(body.inventory.stacks_in(CARDS).size(), 5, "every card of the registry")
	check_equal(body.inventory.count_of(CARDS, &"split"), Inventory.DEV_COPIES, "each the dev bag's copies")


func test_seat_wizard_gives_the_counted_bag_and_every_bag_is_announced() -> void:
	_wizard(1, {&"dash": 1, &"bolt": 2})
	var cards: Array = _last(CARDS)
	check_equal(cards, [1, CARDS, _ids("dash bolt"), PackedInt32Array([1, 2]), Inventory.UNLIMITED], "the mode's bag, counted, with no limit")
	for bag: StringName in ItemKinds.BAGS:
		check(not _last(bag).is_empty(), "%s is announced" % bag)
	check_equal(_last(&"relics")[2], [] as Array[StringName], "an empty bag is just empty")


func test_the_start_staffs_and_hands_are_announced_by_number() -> void:
	_wizard(0, {&"bolt": 1})
	check_equal(_owned_staffs, [[0, 0], [0, 1], [0, 2], [0, 3]], "every staff, its number its start button")
	check_equal(_hands, [[0, PackedInt32Array([0, 1, 2, 3])]], "and the hands")


func test_a_card_put_in_takes_a_copy_and_taken_out_gives_it_back() -> void:
	var body := _wizard(0, {&"bolt": 2})
	_world.bus.staff_change_requested.emit(0, 1, 0, &"bolt")
	check_equal(body.caster.cards_of(1)[0], &"bolt", "the card is in the staff on the hand")
	check_equal(body.inventory.count_of(CARDS, &"bolt"), 1, "one copy left in the bag")
	check_equal(_last(CARDS)[3], PackedInt32Array([1]), "and the bag is announced")
	_world.bus.staff_change_requested.emit(0, 1, 0, &"")
	check_equal(body.inventory.count_of(CARDS, &"bolt"), 2, "taken out, it is back")
	check(_refused.is_empty(), "nothing refused")


func test_the_last_copy_goes_and_a_card_with_none_left_is_refused() -> void:
	var body := _wizard(0, {&"bolt": 1, &"fire": 1})
	_world.bus.staff_change_requested.emit(0, 0, 0, &"bolt")
	check_equal(_last(CARDS)[2], _ids("fire"), "a card with none left is not in the bag")
	_world.bus.staff_change_requested.emit(0, 0, 1, &"bolt")
	check_equal(_refused, [[0, PlayerController.NO_CARD]], "the second bolt is refused, with the reason")
	check_equal(body.caster.cards_of(0), _ids("bolt - - -"), "and the staff is unchanged")


func test_a_card_replaced_in_its_slot_goes_back_as_the_new_one_comes_out() -> void:
	var body := _wizard(0, {&"bolt": 1, &"fire": 1})
	_world.bus.staff_change_requested.emit(0, 0, 0, &"bolt")
	_world.bus.staff_change_requested.emit(0, 0, 0, &"fire")
	check_equal(body.caster.cards_of(0), _ids("fire - - -"), "fire in the slot")
	check_equal([body.inventory.count_of(CARDS, &"bolt"), body.inventory.count_of(CARDS, &"fire")], [1, 0], "bolt back, fire out")
	_world.bus.staff_change_requested.emit(0, 0, 0, &"fire")
	check(_refused.is_empty(), "the same card again in its own slot needs no copy")


func test_a_whole_staff_request_is_counted_as_one_change() -> void:
	var body := _wizard(0, {&"bolt": 2, &"fire": 1})
	_world.bus.staff_cards_requested.emit(0, 2, _ids("fire bolt bolt"))
	check_equal(body.inventory.stacks_in(CARDS).size(), 0, "every copy is in the staff")
	_bags.clear()
	# A push-right insert as the builder sends it: the row moves on, nothing comes or goes.
	_world.bus.staff_cards_requested.emit(0, 2, _ids("- fire bolt bolt"))
	check(_bags.is_empty(), "a row only moved changes no count")
	_world.bus.staff_cards_requested.emit(0, 2, _ids("bolt bolt bolt"))
	check_equal(_refused, [[0, PlayerController.NO_CARD]], "a third bolt is refused")
	check_equal(body.caster.cards_of(2), _ids("- fire bolt bolt"), "and the staff is as it was")
	_world.bus.staff_cards_requested.emit(0, 2, [] as Array[StringName])
	check_equal([body.inventory.count_of(CARDS, &"bolt"), body.inventory.count_of(CARDS, &"fire")], [2, 1], "a clear gives every card back")


func test_cards_given_back_past_the_bags_capacity_drop_at_the_feet() -> void:
	var body := _wizard(0, {&"bolt": 1})
	_world.bus.staff_change_requested.emit(0, 0, 0, &"bolt")
	body.inventory.set_capacity(CARDS, 0)
	var dropped: Array[StringName] = []
	_world.bus.item_drop_requested.connect(func(_actor: int, stack: ItemStack) -> void: dropped.append(stack.id))
	_world.bus.staff_change_requested.emit(0, 0, 0, &"")
	check(_refused.is_empty(), "nothing is refused")
	check_equal(body.caster.cards_of(0)[0], &"", "the staff is emptied")
	check_equal(dropped, [&"bolt"] as Array[StringName], "the bolt went to the ground")
	check_equal(_last(CARDS)[4], 0, "the capacity is announced")


func test_the_start_cards_come_with_their_staffs_beside_the_bag() -> void:
	var body := _wizard(0, {&"bolt": 1}, [[&"bolt"], [], [], []])
	check_equal(body.inventory.count_of(CARDS, &"bolt"), 1, "the start bolt is the staff's own, not the bag's")
	_world.bus.staff_change_requested.emit(0, 0, 0, &"")
	check_equal(body.inventory.count_of(CARDS, &"bolt"), 2, "taken out, it joins the bag")


func test_a_request_for_a_staff_it_does_not_own_is_refused() -> void:
	_wizard(0, {&"bolt": 1})
	_world.bus.staff_change_requested.emit(0, 7, 0, &"bolt")
	_world.bus.staff_cards_requested.emit(0, Inventory.NO_STAFF, _ids("bolt"))
	check_equal(_refused, [[0, PlayerController.NO_STAFF], [0, PlayerController.NO_STAFF]], "no such staff, twice")
