extends "res://tests/support/suite.gd"
## Tests for the inventory (items I3, gameplay/actor/inventory.gd): it takes the staffs the body
## was made with, numbered by button; bags and their capacity in copies; cards stack, staffs are
## numbered; a staff on a hand goes into the Caster when its cards change, and one in the bag is
## never installed; every change is counted and said.
##
## godot --headless --path . --script res://tests/gameplay/actor/test_inventory.gd

const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")

const CARDS: StringName = &"cards"
const STAFFS: StringName = &"staffs"

var _world: Fixture
var _staff: StaffBase
## Every bag_changed and staff_changed of the wizard's inventory.
var _bags_said: Array[StringName] = []
var _staffs_said: Array[int] = []


func before_each() -> void:
	_world = Fixture.new(root, true)
	_staff = StaffBase.new()
	_staff.id = &"test"
	_staff.slots = 3
	_bags_said.clear()
	_staffs_said.clear()


func after_each() -> void:
	_world.free_all()


## A wizard holding `_staff` on RB and LB (RT and LT empty), RB with `bolt`, and the card bag `bag`.
func _wizard(bag: Dictionary = {&"bolt": 2, &"fire": 1}) -> Actor:
	var hands: Array[StaffBase] = [_staff, null, _staff, null]
	var body: Actor = _world.wizard(0, Vector2.ZERO, [[&"bolt"], [], [], []], null, false, hands)
	PlayerController.seat_wizard(body, 0, null, [[&"bolt"], [], [], []], hands, bag)
	_world.add(body)
	body.inventory.bag_changed.connect(func(bag_name: StringName) -> void: _bags_said.append(bag_name))
	body.inventory.staff_changed.connect(func(number: int) -> void: _staffs_said.append(number))
	return body


func _ids(words: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for word in words.split(" ", false):
		out.append(StringName(word) if word != "-" else &"")
	return out


func test_it_takes_the_start_staffs_numbered_by_their_button() -> void:
	var inventory: Inventory = _wizard().inventory
	check_equal(inventory.numbers(), PackedInt32Array([0, 2]), "RB's and LB's staffs, numbered by their buttons")
	check_equal(inventory.hands(), PackedInt32Array([0, Inventory.NO_STAFF, 2, Inventory.NO_STAFF]), "RT and LT empty")
	check_equal(inventory.cards_of(0), _ids("bolt - -"), "with their start cards, as long as the staff's slots")
	check_equal(inventory.staff(2).staff, _staff, "the staff itself")
	check_equal(inventory.copies(STAFFS), 0, "a staff on a hand is out of the staff bag")


func test_cards_stack_and_staffs_get_the_next_number() -> void:
	var inventory: Inventory = _wizard().inventory
	check(inventory.add(ItemStack.card(&"bolt", 3)), "more bolts")
	check_equal(inventory.count_of(CARDS, &"bolt"), 5, "join the bolts' stack")
	check_equal(inventory.stacks_in(CARDS).size(), 2, "still two stacks")
	check(inventory.add(ItemStack.of_staff(_staff, _ids("fire"))), "a staff into the bag")
	check(inventory.add(ItemStack.of_staff(_staff)), "and another")
	check_equal(inventory.numbers(), PackedInt32Array([0, 2, 4, 5]), "numbered on from the hands', after them")
	check_equal(inventory.hand_of(4), -1, "on no hand")
	check_equal(inventory.copies(STAFFS), 2, "two staffs in the bag")
	check_equal(_staffs_said, [4, 5] as Array[int], "each new staff is said")


func test_a_bag_has_a_capacity_counted_in_copies() -> void:
	var inventory: Inventory = _wizard().inventory
	check_equal(inventory.capacity_of(CARDS), Inventory.UNLIMITED, "no limit at the start")
	inventory.set_capacity(CARDS, 4)
	check(inventory.add(ItemStack.card(&"rune", 1)), "the fourth copy fits")
	check(not inventory.has_room(ItemStack.card(&"rune", 1)), "a fifth does not")
	check(not inventory.add(ItemStack.card(&"bolt", 1)), "so it is refused")
	check_equal(inventory.copies(CARDS), 4, "and nothing changed")
	inventory.set_capacity(STAFFS, 1)
	check(inventory.add(ItemStack.of_staff(_staff)), "one staff in a bag of one")
	check(not inventory.add(ItemStack.of_staff(_staff)), "a second is refused")


func test_take_refuses_more_than_it_holds() -> void:
	var inventory: Inventory = _wizard().inventory
	check(not inventory.take(CARDS, &"fire", 2), "two fires from one")
	check_equal(inventory.count_of(CARDS, &"fire"), 1, "nothing taken")
	check(inventory.take(CARDS, &"fire"), "one fire")
	check_equal(inventory.stacks_in(CARDS).size(), 1, "an empty stack goes")


func test_a_staff_on_a_hand_goes_into_the_caster() -> void:
	var body := _wizard()
	_world.fake.installed.clear()
	check_equal(body.inventory.set_cards(2, _ids("fire bolt")), Inventory.Refusal.NONE, "LB's staff built")
	check_equal(body.caster.cards_of(2), _ids("fire bolt -"), "the Caster holds its cards")
	check(_world.fake.installed.has(Vector2i(body.id, 2)), "installed on LB")
	check_equal([body.inventory.count_of(CARDS, &"bolt"), body.inventory.count_of(CARDS, &"fire")], [1, 0], "counted")
	check(_bags_said.has(CARDS) and _staffs_said.has(2), "and said")


func test_a_staff_edited_in_the_bag_is_not_installed_in_the_caster() -> void:
	var body := _wizard()
	var inventory: Inventory = body.inventory
	check(inventory.add(ItemStack.of_staff(_staff)), "a staff into the bag")
	var before: Array = []
	for at in Inventory.HANDS:
		before.append(body.caster.cards_of(at))
	_world.fake.installed.clear()
	check_equal(inventory.set_card(4, 1, &"fire"), Inventory.Refusal.NONE, "its slot set")
	check_equal(inventory.cards_of(4), _ids("- fire -"), "the bag's staff holds it")
	check(_world.fake.installed.is_empty(), "nothing was installed")
	var after: Array = []
	for at in Inventory.HANDS:
		after.append(body.caster.cards_of(at))
	check_equal(after, before, "no hand's staff changed")
	check_equal(inventory.count_of(CARDS, &"fire"), 0, "the card is counted all the same")
	check(not inventory.plan_of(4).is_empty(), "the builder can still see it")


func test_every_refusal_changes_nothing() -> void:
	var body := _wizard({&"bolt": 1})
	var inventory: Inventory = body.inventory
	check_equal(inventory.set_cards(1, _ids("bolt")), Inventory.Refusal.NO_STAFF, "an empty hand's number")
	check_equal(inventory.set_card(0, 3, &"bolt"), Inventory.Refusal.NO_SLOT, "a slot past the staff's")
	check_equal(inventory.set_cards(0, _ids("bolt bolt bolt bolt")), Inventory.Refusal.NO_SLOT, "more cards than slots")
	check_equal(inventory.set_cards(0, _ids("bolt bolt bolt")), Inventory.Refusal.NO_CARD, "more bolts than it has")
	check_equal(inventory.set_card(0, 1, &"rune"), Inventory.Refusal.NO_CARD, "a card it has none of")
	inventory.set_capacity(CARDS, 1)
	check_equal(inventory.set_cards(0, [] as Array[StringName]), Inventory.Refusal.BAG_FULL, "no room for the bolt given back")
	check_equal(inventory.cards_of(0), _ids("bolt - -"), "the staff is as it was")
	check_equal(body.caster.cards_of(0), _ids("bolt - -"), "and so is the Caster's")
	check_equal(inventory.count_of(CARDS, &"bolt"), 1, "and the bag")
	check(_staffs_said.is_empty(), "nothing was said")


## Regression (review): a kind that does not stack is a stack a copy, whatever count it came with.
func test_a_kind_that_does_not_stack_is_a_stack_a_copy() -> void:
	var inventory: Inventory = _wizard().inventory
	var three := ItemStack.of_staff(_staff)
	three.count = 3
	check(inventory.add(three), "three staffs at once")
	check_equal(inventory.stacks_in(STAFFS).size(), 3, "three stacks")
	check_equal(inventory.numbers(), PackedInt32Array([0, 2, 4, 5, 6]), "each with its number")
	check(inventory.stacks_in(STAFFS).all(func(stack: ItemStack) -> bool: return stack.count == 1), "each one copy")


## Regression (review): taking staffs takes as many stacks as asked, and says each staff gone.
func test_taking_staffs_takes_each_and_says_it_gone() -> void:
	var inventory: Inventory = _wizard().inventory
	inventory.add(ItemStack.of_staff(_staff))
	inventory.add(ItemStack.of_staff(_staff))
	_staffs_said.clear()
	check(inventory.take(STAFFS, &"test", 2), "both staffs")
	check_equal(inventory.copies(STAFFS), 0, "the bag is empty")
	check_equal(_staffs_said, [4, 5] as Array[int], "each said gone")
	check(inventory.staff(4) == null and inventory.plan_of(4).is_empty(), "and no longer owned")


## Regression (review): a hand the Caster no longer holds refuses, and nothing is counted.
func test_a_hand_the_caster_lost_refuses_and_counts_nothing() -> void:
	var body := _wizard()
	body.caster.empty_hands |= 1 << 2
	check_equal(body.inventory.set_cards(2, _ids("bolt")), Inventory.Refusal.NO_STAFF, "refused")
	check_equal(body.inventory.count_of(CARDS, &"bolt"), 2, "the bolt stays in the bag")


func test_the_dev_bag_is_every_card_the_registry_finds() -> void:
	var registry: Node = root.get_node("Registry")
	var bag: Dictionary = Inventory.dev_cards(registry)
	var cards: int = 0
	for id: StringName in registry.call("get_ids", &"spells"):
		if registry.call("get_resource", &"spells", id) is SpellComponent:
			cards += 1
	check_equal(bag.size(), cards, "every card")
	check(bag.values().all(func(copies: Variant) -> bool: return int(copies) == Inventory.DEV_COPIES), "DEV_COPIES of each")
