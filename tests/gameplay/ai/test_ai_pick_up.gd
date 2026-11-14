extends "res://tests/support/suite.gd"
## Tests for the AI picking things up (items I9, docs/milestones/items.md, "I9";
## gameplay/ai/behaviours/pick_up.gd): an enemy whose profile takes staffs walks to a staff beside it,
## takes it onto its free hand and casts it; with every hand full it takes a stronger staff in place
## of its weakest (into its bag) and leaves a weaker one; a card goes into the free slot where it
## does something and the staff is strongest, and a card that fits nowhere is left; a profile that
## takes nothing never looks. The AI sees the ground through the bus (`ground_looked`) and takes by
## actor (`actor_take_requested`), never calling the Items area. A world of its own
## (tests/gameplay/ai/ai_fixture.gd) with an Items area on its bus, stepped by hand.
##
## godot --headless --path . --script res://tests/gameplay/ai/test_ai_pick_up.gd

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const ItemsScript := preload("res://gameplay/items/items.gd")
const PickUp := preload("res://gameplay/ai/behaviours/pick_up.gd")

const STAFFS: StringName = &"staffs"
const CARDS: StringName = &"cards"

var _world: Fixture
var _items: ItemsScript
## How often anyone looked at the ground (`ground_looked`).
var _looks: int = 0


func before_each() -> void:
	_world = Fixture.new(root)
	_items = ItemsScript.new()
	_items.events = _world.bus
	_items.actors = _world.actors
	_items.projectiles = _world.projectiles
	_items.spells = _world.spells
	_items.registry = _world.registry
	root.add_child(_items)
	_looks = 0
	_world.bus.ground_looked.connect(func(_actor: int, _feet: Vector2, _reach: float, _sight: GroundSight) -> void: _looks += 1)
	# The wizard far off, so nothing draws the enemy into a fight.
	_world.players[0].position = Vector2(4000.0, 4000.0)


func after_each() -> void:
	_items.free()
	_world.free_all()


## A profile that plays as `Fixture.exact()` and takes `kinds`.
func _taker(kinds: Array[StringName]) -> AIProfile:
	var made: AIProfile = Fixture.exact().duplicate() as AIProfile
	made.takes = kinds
	return made


## A staff of `slots` slots (no wind-up, a big pool) holding nothing.
func _staff(slots: int = 1) -> StaffBase:
	var made: StaffBase = Fixture.staff_entry([&"bolt"]).staff
	made.slots = slots
	made.wind_up = 0.0
	return made


func _stack(cards: Array[StringName], slots: int = -1) -> ItemStack:
	return ItemStack.of_staff(_staff(cards.size() if slots < 0 else slots), cards)


func _strength(body: Actor, base: StaffBase, cards: Array[StringName]) -> float:
	return PickUp.strength(body.caster.sense_of_build(base, cards))


func test_an_enemy_beside_a_staff_walks_to_it_takes_it_and_casts_it() -> void:
	var body: Actor = _world.staffed_enemy([[&"bolt"]], Vector2.ZERO, _taker([ItemKinds.STAFF]))
	var inventory: Inventory = body.inventory
	# Its one hand emptied (the staff dropped, then the ground cleared): it holds nothing.
	inventory.drop_staff(inventory.hands()[0])
	_items.clear()
	check(not body.caster.holds(0), "its hand is empty")
	var item: int = _items.lay(_stack([&"bolt"] as Array[StringName]), Vector2(60.0, 0.0))
	_world.run(body, 4)
	check(body.position.x > 0.0, "it walks to the staff")
	_world.run(body, 40)
	check(_items.lying().is_empty(), "the staff is off the ground")
	check(body.caster.holds(0), "on its hand")
	check_equal(body.caster.cards_of(0), [&"bolt"] as Array[StringName], "with its cards")
	check(item >= 0, "it lay there")
	var casts: Array[int] = []
	body.caster.cast_done.connect(func(at: int, _origin: Vector2, _direction: Vector2) -> void: casts.append(at))
	_world.players[0].position = body.position + Vector2(80.0, 0.0)
	_world.run(body, 40)
	check(casts.has(0), "and casts it at the wizard")


func test_an_enemy_that_dropped_its_staff_takes_it_back() -> void:
	var body: Actor = _world.staffed_enemy([[&"bolt"]], Vector2(100.0, 100.0), _taker([ItemKinds.STAFF]))
	body.inventory.drop_staff(body.inventory.hands()[0])
	check_equal(_items.lying().size(), 1, "it lies beside it")
	_world.run(body, 8)
	check(_items.lying().is_empty(), "taken back")
	check(body.caster.holds(0), "on its hand again")


func test_with_every_hand_full_a_stronger_staff_takes_the_weakest_place() -> void:
	var body: Actor = _world.staffed_enemy([[&"bolt"]], Vector2.ZERO, _taker([ItemKinds.STAFF]))
	var inventory: Inventory = body.inventory
	var was: int = inventory.hands()[0]
	var stronger: Array[StringName] = [&"double", &"bolt", &"bolt"]
	check(_strength(body, _staff(3), stronger) > _strength(body, body.caster.staff_of(0), body.caster.cards_of(0)), "two bolts at once are stronger (the test's premise)")
	_items.lay(_stack(stronger), Vector2(10.0, 0.0))
	_world.run(body, 8)
	check(_items.lying().is_empty(), "the stronger staff is taken")
	check_equal(body.caster.cards_of(0), stronger, "onto the hand")
	check_equal(inventory.hand_of(was), -1, "the weakest is off its hand")
	check_equal(inventory.stacks_in(STAFFS).size(), 1, "and in its staff bag")


func test_with_every_hand_full_a_weaker_staff_is_left() -> void:
	var body: Actor = _world.staffed_enemy([[&"double", &"bolt", &"bolt"]], Vector2.ZERO, _taker([ItemKinds.STAFF]))
	var held: Array[StringName] = body.caster.cards_of(0)
	_items.lay(_stack([&"bolt"] as Array[StringName]), Vector2(10.0, 0.0))
	_world.run(body, 12)
	check_equal(_items.lying().size(), 1, "the weaker staff still lies there")
	check_equal(body.caster.cards_of(0), held, "its own staff stays on its hand")
	check(body.inventory.stacks_in(STAFFS).is_empty(), "and nothing went into its bag")


func test_a_body_with_no_caster_leaves_staffs() -> void:
	var data: EnemyBase = Fixture.staffed([])
	var body: Actor = _world.enemy(data.scene, data, Vector2.ZERO)
	Fixture.ai(body).profile = _taker([ItemKinds.STAFF])
	_items.lay(_stack([&"bolt"] as Array[StringName]), Vector2(10.0, 0.0))
	_world.run(body, 12)
	check_equal(_items.lying().size(), 1, "it has no hands: the staff stays")


func test_a_card_goes_into_the_free_slot_where_it_does_something() -> void:
	var body: Actor = _world.staffed_enemy([[&"", &"bolt"]], Vector2.ZERO, _taker([ItemKinds.CARD]))
	var row: Array[StringName] = [&"heavy", &"bolt"]
	check(body.caster.sense_of_build(body.caster.staff_of(0), row, 0) != null, "heavy does something before a bolt (the test's premise)")
	check(_strength(body, body.caster.staff_of(0), row) >= _strength(body, body.caster.staff_of(0), body.caster.cards_of(0)), "and is no weaker")
	_items.lay(ItemStack.card(&"heavy"), Vector2(10.0, 0.0))
	_world.run(body, 8)
	check(_items.lying().is_empty(), "the card is taken")
	check_equal(body.caster.cards_of(0), row, "into the free slot")
	check_equal(body.inventory.count_of(CARDS, &"heavy"), 0, "out of its card bag again")


func test_a_card_that_fits_nowhere_is_left() -> void:
	var body: Actor = _world.staffed_enemy([[&"bolt"]], Vector2.ZERO, _taker([ItemKinds.CARD]))
	_items.lay(ItemStack.card(&"heavy"), Vector2(10.0, 0.0))
	_world.run(body, 12)
	check_equal(_items.lying().size(), 1, "no free slot: the card still lies there")
	check_equal(body.inventory.count_of(CARDS, &"heavy"), 0, "and is not in its bag")


func test_it_takes_only_the_kinds_its_profile_names() -> void:
	var body: Actor = _world.staffed_enemy([[&"", &"bolt"]], Vector2.ZERO, _taker([ItemKinds.STAFF]))
	_items.lay(ItemStack.card(&"heavy"), Vector2(10.0, 0.0))
	_world.run(body, 12)
	check_equal(_items.lying().size(), 1, "a card, to a profile that takes staffs: left")


func test_a_profile_that_takes_nothing_never_looks() -> void:
	var body: Actor = _world.staffed_enemy([[&"", &"bolt"]], Vector2.ZERO)
	_items.lay(ItemStack.card(&"heavy"), Vector2(10.0, 0.0))
	_world.run(body, 12)
	check_equal(_looks, 0, "no look at the ground")
	check_equal(_items.lying().size(), 1, "nothing taken")


func test_the_sight_is_the_nearest_first_and_says_what_is_in_reach() -> void:
	var far: int = _items.lay(ItemStack.card(&"bolt"), Vector2(60.0, 0.0))
	var near: int = _items.lay(ItemStack.card(&"heavy"), Vector2(-10.0, 0.0))
	_items.lay(ItemStack.card(&"fire"), Vector2(500.0, 0.0))
	var sight := GroundSight.new()
	_world.bus.ground_looked.emit(0, Vector2.ZERO, 96.0, sight)
	check_equal(sight.count, 2, "the two within the look")
	check_equal(sight.numbers[0], near, "the nearest first")
	check_equal(sight.numbers[1], far, "then the other")
	check_equal(sight.in_reach[0], 1, "the near one in reach")
	check_equal(sight.in_reach[1], 0, "the far one not")
	check_equal(sight.stacks[0].id, &"heavy", "with its stack")


func test_a_full_sight_keeps_the_nearest() -> void:
	var sight := GroundSight.new()
	for i in GroundSight.MOST + 3:
		sight.add(i, Vector2(float(GroundSight.MOST + 3 - i), 0.0), float(GroundSight.MOST + 3 - i), false, null)
	check_equal(sight.count, GroundSight.MOST, "at most MOST")
	check_equal(sight.numbers[0], GroundSight.MOST + 2, "the nearest first")
	check_equal(sight.numbers[GroundSight.MOST - 1], 3, "the farthest let go")


## Regression (review of I9): a card in reach that its full bag has no room for is not wanted, so
## the AI goes on fighting instead of standing by it for good.
func test_a_card_with_no_room_in_its_bag_does_not_keep_it_from_fighting() -> void:
	var body: Actor = _world.staffed_enemy([[&"", &"bolt"]], Vector2.ZERO, _taker([ItemKinds.CARD]))
	body.inventory.set_capacity(CARDS, 0)
	_items.lay(ItemStack.card(&"heavy"), Vector2(10.0, 0.0))
	var casts: Array[int] = []
	body.caster.cast_done.connect(func(at: int, _origin: Vector2, _direction: Vector2) -> void: casts.append(at))
	_world.players[0].position = Vector2(80.0, 0.0)
	_world.run(body, 40)
	check_equal(_items.lying().size(), 1, "the card still lies there")
	check(not casts.is_empty(), "and it casts at the wizard")


## Regression (review of I9): trying builds never puts them in the staffs' own cache, which starts
## over once full and would lose every held staff's compiled build.
func test_a_tried_build_stays_out_of_the_staffs_cache() -> void:
	var body: Actor = _world.staffed_enemy([[&"", &"bolt"]], Vector2.ZERO)
	var tried: Array[StringName] = [&"pierce", &"bolt"]
	var key: String = body.caster._key(tried, body.caster.staff_of(0))
	check(body.caster.sense_of_build(body.caster.staff_of(0), tried) != null, "the tried build casts")
	check(not Caster._cache.has(key), "not in the staffs' cache")
	check(Caster._trials.has(key), "kept with the trials")
	var held: String = body.caster._key(body.caster.cards_of(0), body.caster.staff_of(0))
	check(Caster._cache.has(held), "the held build is the staffs' cache's")
	check(not Caster._trials.has(held), "and is not compiled again for a trial")
