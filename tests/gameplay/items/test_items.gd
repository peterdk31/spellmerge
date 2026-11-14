extends "res://tests/support/suite.gd"
## Tests for the Items area (items I6, gameplay/items/items.gd) and the pickup rule
## (gameplay/items/pickup_rule.gd): what a room places lies there; the item in reach of each
## seat's driven body is said as it changes; A takes it with room (a staff onto a free hand, else
## into the bag; a card into the bag), and without room nothing is taken and the seat hears
## `item_refused`; two seats asking for one item in one tick: the first in seat order takes it; a
## drop lands a step from the body, away from the next item and never in a wall; a run's start
## clears the ground; a snapshot with items lying comes back the same and says them again.
##
## godot --headless --path . --script res://tests/gameplay/items/test_items.gd

const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const ItemsScript := preload("res://gameplay/items/items.gd")
const WILD_STAR: StaffItem = preload("res://content/items/staffs/wild_star/wild_star.tres")

const CARDS: StringName = &"cards"
const STAFFS: StringName = &"staffs"

var _world: Fixture
var _items: ItemsScript
var _staff: StaffBase
## Every item_near_changed [player, item], ground_item_changed [item, gone] and item_refused
## [player, item].
var _near: Array = []
var _ground: Array = []
var _refused: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_items = ItemsScript.new()
	_items.events = _world.bus
	_items.actors = _world.table
	_items.projectiles = _world.projectiles
	_items.spells = _world.spells
	root.add_child(_items)
	_staff = StaffBase.new()
	_staff.id = &"test"
	_staff.slots = 3
	_near.clear()
	_ground.clear()
	_refused.clear()
	_world.bus.item_near_changed.connect(func(player: int, item: int, _at: Vector2, _view: Dictionary) -> void: _near.append([player, item]))
	_world.bus.ground_item_changed.connect(func(item: int, _at: Vector2, view: Dictionary) -> void: _ground.append([item, view.is_empty()]))
	_world.bus.item_refused.connect(func(player: int, item: int) -> void: _refused.append([player, item]))


func after_each() -> void:
	_items.free()
	_world.free_all()


## A wizard of `seat` at `at` holding `_staff` on the hands `hands` says (true: a staff), the card
## bag `bag`.
func _wizard(seat: int, at: Vector2, hands: Array[bool] = [true, false, false, false], bag: Dictionary = {&"bolt": 2}) -> Actor:
	var staffs: Array[StaffBase] = []
	for held: bool in hands:
		staffs.append(_staff if held else null)
	var body: Actor = _world.wizard(seat, at, Fixture.NO_CARDS, null, false, staffs)
	PlayerController.seat_wizard(body, seat, null, Fixture.NO_CARDS, staffs, bag)
	return _world.add(body)


## One tick: the seats' frames (their commands apply), then the Items step.
func _tick() -> void:
	_world.frames.tick(Fixture.STEP)
	_items.step(Fixture.STEP)


func _ask(seat: int, item: int) -> void:
	_world.bus.item_take_requested.emit(seat, item)


func test_a_room_lays_what_it_places_one_copy_each() -> void:
	var bolt: SpellComponent = _world.registry.get_resource(&"spells", &"bolt") as SpellComponent
	_world.bus.room_items_placed.emit([WILD_STAR, bolt, StaffCards.new()] as Array[Resource], PackedVector2Array([Vector2(10, 0), Vector2(40, 0), Vector2(70, 0)]))
	var lying: Array[GroundItem] = _items.lying()
	check_equal(lying.size(), 2, "the staff and the card lie there; what is no item does not")
	check_equal([lying[0].number, lying[0].at, lying[0].stack.kind, lying[0].stack.id], [0, Vector2(10, 0), ItemKinds.STAFF, &"star"], "the premade staff is its staff")
	check_equal(lying[0].stack.cards, WILD_STAR.cards, "with its cards")
	check_equal(lying[0].stack.mana, WILD_STAR.staff.max_mana, "its pool full")
	check_equal([lying[1].number, lying[1].stack.kind, lying[1].stack.id, lying[1].stack.count], [1, ItemKinds.CARD, &"bolt", 1], "the card, one copy")
	check_equal(_ground, [[0, false], [1, false]], "each was said as it was laid")
	var view: Dictionary = _items.view_of(lying[0])
	check_equal(view["name"], "Wild star", "the premade staff is shown by its own name")
	check_equal([view["slots"], view["cards"]], [WILD_STAR.staff.slots, WILD_STAR.cards], "with its numbers and cards")
	check_equal(_items.view_of(lying[1])["name"], _world.spells.component_name(&"bolt"), "the card by its name")
	check(_items.view_of(lying[1])["icon"] == _world.spells.component_icon(&"bolt"), "and its icon")
	check(_items.view_of(lying[1])["icon"] != null, "it has one")


func test_the_item_in_reach_is_said_as_it_changes() -> void:
	var body := _wizard(0, Vector2.ZERO)
	var near: int = _items.lay(ItemStack.card(&"bolt"), Vector2(20, 0))
	var nearer: int = _items.lay(ItemStack.card(&"bolt"), Vector2(-10, 0))
	_tick()
	check_equal(_near, [[0, nearer]], "the nearest in reach")
	_tick()
	check_equal(_near.size(), 1, "said once, while it stays")
	body.position = Vector2(30, 0)
	_tick()
	check_equal(_near.back(), [0, near], "the other, once it is nearer")
	body.position = Vector2(200, 0)
	_tick()
	check_equal(_near.back(), [0, ItemsScript.NONE], "none out of reach")
	check_equal(_items.near_of(1), ItemsScript.NONE, "a seat with no body has none")


func test_a_card_goes_into_the_bag_and_off_the_ground() -> void:
	var body := _wizard(0, Vector2.ZERO)
	var item: int = _items.lay(ItemStack.card(&"fire"), Vector2(10, 0))
	_tick()
	_ask(0, item)
	_tick()
	check_equal(body.inventory.count_of(CARDS, &"fire"), 1, "the fire is in the bag")
	check(_items.lying().is_empty(), "and off the ground")
	check_equal(_ground.back(), [item, true], "said gone")
	check_equal(_near.back(), [0, ItemsScript.NONE], "nothing in reach any more")
	check(_refused.is_empty(), "nothing was refused")


func test_a_staff_goes_on_a_free_hand_else_into_the_bag() -> void:
	var body := _wizard(0, Vector2.ZERO, [true, false, true, true])
	var first: int = _items.lay(ItemStack.of_staff(WILD_STAR.staff, WILD_STAR.cards), Vector2(5, 0))
	var second: int = _items.lay(ItemStack.of_staff(WILD_STAR.staff), Vector2(-5, 0))
	_ask(0, first)
	_tick()
	check_equal(body.inventory.hands()[1], 4, "onto RT, the free hand")
	check(body.caster.holds(1), "its Caster holds it")
	check_equal(body.caster.cards_of(1), WILD_STAR.cards, "with its cards")
	_ask(0, second)
	_tick()
	check_equal(body.inventory.copies(STAFFS), 1, "the next into the staff bag: no hand is free")
	check(_items.lying().is_empty(), "both taken")


func test_without_room_nothing_is_taken_and_the_seat_hears_it() -> void:
	var body := _wizard(0, Vector2.ZERO)
	body.inventory.set_capacity(CARDS, 2)
	var item: int = _items.lay(ItemStack.card(&"fire"), Vector2(10, 0))
	_ask(0, item)
	_tick()
	check_equal(_refused, [[0, item]], "refused, for that seat and item")
	check_equal(body.inventory.count_of(CARDS, &"fire"), 0, "nothing taken")
	check_equal(_items.lying().size(), 1, "it still lies there")


func test_an_item_out_of_reach_or_gone_is_not_taken_and_says_nothing() -> void:
	var body := _wizard(0, Vector2.ZERO)
	var item: int = _items.lay(ItemStack.card(&"fire"), Vector2(100, 0))
	check_equal(_items.take(body.id, item), ItemsScript.Take.OUT_OF_REACH, "out of reach")
	check_equal(_items.take(body.id, 99), ItemsScript.Take.GONE, "no such item")
	_ask(0, item)
	_tick()
	check(_refused.is_empty(), "no shake for either")
	check_equal(body.inventory.count_of(CARDS, &"fire"), 0, "nothing taken")


func test_two_seats_and_one_item_the_first_in_seat_order_takes_it() -> void:
	# The frames service as the game's: commands wait for the tick's start and apply seat by seat.
	root.add_child(_world.frames)
	var first := _wizard(0, Vector2(-8, 0))
	var second := _wizard(1, Vector2(8, 0))
	var item: int = _items.lay(ItemStack.card(&"fire"), Vector2.ZERO)
	_ask(1, item)
	_ask(0, item)
	_tick()
	check_equal(first.inventory.count_of(CARDS, &"fire"), 1, "seat 0 took it")
	check_equal(second.inventory.count_of(CARDS, &"fire"), 0, "seat 1 did not")
	check(_refused.is_empty(), "and nobody was refused: it was gone")


func test_a_downed_body_takes_nothing_and_has_nothing_in_reach() -> void:
	var body := _wizard(0, Vector2.ZERO)
	var item: int = _items.lay(ItemStack.card(&"fire"), Vector2(5, 0))
	_world.hurt(body, 100000)
	check(body.is_down(), "down")
	_tick()
	check_equal(_items.near_of(0), ItemsScript.NONE, "nothing in reach")
	check_equal(_items.take(body.id, item), ItemsScript.Take.NO_HOLDER, "nor taken")


func test_a_drop_lands_a_step_away_from_the_next_item_and_never_in_a_wall() -> void:
	var body := _wizard(0, Vector2(100, 100))
	_items.lay(ItemStack.card(&"bolt"), Vector2(100, 90))
	_world.bus.item_drop_requested.emit(body.id, ItemStack.card(&"fire"))
	var dropped: GroundItem = _items.lying().back()
	check_equal(dropped.stack.id, &"fire", "the fire lies there")
	check_equal(dropped.at, Vector2(100, 100) + Vector2(0, ItemsScript.DROP_STEPS[0]), "a step below: away from the bolt above")
	# A wall below and to the left: the next free way, the furthest from the bolt.
	_world.projectiles.set_walls([Rect2(60, 104, 50, 40)] as Array[Rect2])
	var spot: Vector2 = _items.drop_spot(Vector2(100, 100), Vector2(100, 90))
	check_equal(spot, Vector2(100 + ItemsScript.DROP_STEPS[0], 100), "to the right: below, below left and below right are in the wall, left is walled at its rim")
	check(not _world.projectiles.circle_blocked(spot, ItemsScript.DROP_RADIUS), "in no wall")
	check_equal(_items.drop_spot(Vector2(100, 100), Vector2(100, 90)), spot, "the same spot every time")
	_world.projectiles.set_walls([Rect2(60, 60, 80, 80)] as Array[Rect2])
	check_equal(_items.drop_spot(Vector2(100, 100)), Vector2(100, 100), "walled in: at the feet")


## Regression (review): cards dropped together never pile up: each lands on a spot of its own.
func test_cards_dropped_together_each_land_on_a_spot_of_their_own() -> void:
	var body := _wizard(0, Vector2(100, 100), [true, false, false, false], {&"bolt": 1, &"fire": 1, &"frost": 1})
	check_equal(body.inventory.set_cards(0, [&"bolt", &"fire", &"frost"] as Array[StringName]), Inventory.Refusal.NONE, "three in")
	body.inventory.set_capacity(CARDS, 0)
	check_equal(body.inventory.set_cards(0, [] as Array[StringName]), Inventory.Refusal.NONE, "all out")
	var lying: Array[GroundItem] = _items.lying()
	check_equal(lying.size(), 3, "all three lie on the ground")
	for i in lying.size():
		for j in range(i + 1, lying.size()):
			check(lying[i].at.distance_to(lying[j].at) >= 2.0 * ItemsScript.DROP_RADIUS, "%s and %s lie apart (%s, %s)" % [lying[i].stack.id, lying[j].stack.id, lying[i].at, lying[j].at])


## Regression (review): a restore over a ground that holds what the snapshot does not tells this
## machine's looks that it is gone.
func test_a_restore_says_gone_what_the_snapshot_does_not_hold() -> void:
	_wizard(0, Vector2.ZERO)
	_items.lay(ItemStack.card(&"bolt"), Vector2(60, 0))
	var areas: Dictionary = {&"Items": _items}
	var snapshot: Snapshot = Snapshot.take(areas, root)
	var later: int = _items.lay(ItemStack.card(&"fire"), Vector2(90, 0))
	_ground.clear()
	check_equal(snapshot.restore(areas, root), PackedStringArray(), "restored")
	check(_ground.has([later, true]), "the card laid after the snapshot is said gone: %s" % [_ground])
	check(_ground.has([0, false]), "the one it holds is said again")
	check_equal(_items.lying().size(), 1, "one lies there")


func test_a_runs_start_clears_the_ground() -> void:
	_wizard(0, Vector2.ZERO)
	var item: int = _items.lay(ItemStack.card(&"bolt"), Vector2(5, 0))
	_tick()
	_items.begin_run()
	check(_items.lying().is_empty(), "nothing lies there")
	check_equal(_ground.back(), [item, true], "said gone")
	check_equal(_near.back(), [0, ItemsScript.NONE], "and out of reach")
	check_equal(_items.lay(ItemStack.card(&"bolt"), Vector2.ZERO), 0, "numbers count from 0 again")


func test_a_snapshot_with_items_lying_comes_back_the_same_and_says_them_again() -> void:
	_wizard(0, Vector2.ZERO)
	_items.lay(ItemStack.of_staff(WILD_STAR.staff, WILD_STAR.cards), Vector2(5, 0))
	_items.lay(ItemStack.card(&"bolt"), Vector2(60, 0))
	_tick()
	var areas: Dictionary = {&"Items": _items}
	var before: int = SimHash.of(_items)
	var snapshot: Snapshot = Snapshot.take(areas, root)
	check_equal(snapshot.problems, PackedStringArray(), "nothing it cannot save")
	_items.begin_run()
	_ground.clear()
	_near.clear()
	var problems: PackedStringArray = snapshot.restore(areas, root)
	check_equal(problems, PackedStringArray(), "nothing it cannot restore")
	check_equal(SimHash.of(_items), before, "the same state")
	check_equal(_items.lying().size(), 2, "both lie there again")
	check_equal(_ground, [[0, false], [1, false]], "each said again, for this machine's looks")
	check_equal(_near, [[0, 0], [1, ItemsScript.NONE], [2, ItemsScript.NONE], [3, ItemsScript.NONE]], "and what is in reach")


func test_the_pickup_rule() -> void:
	check(PickupRule.in_reach(Vector2.ZERO, Vector2(PickupRule.REACH, 0)), "at its reach")
	check(not PickupRule.in_reach(Vector2.ZERO, Vector2(PickupRule.REACH + 0.5, 0)), "past it")
	var rows: Array[GroundItem] = [GroundItem.make(3, Vector2(10, 0), ItemStack.card(&"a")), GroundItem.make(1, Vector2(-10, 0), ItemStack.card(&"b"))]
	check_equal(PickupRule.nearest(rows, Vector2.ZERO), 1, "a tie goes to the lower number")
	check_equal(PickupRule.nearest(rows, Vector2(100, 0)), -1, "none in reach")
	check(not PickupRule.has_room(null, ItemStack.card(&"a")), "no inventory has no room")
