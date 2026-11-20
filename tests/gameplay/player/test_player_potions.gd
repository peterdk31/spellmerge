extends "res://tests/support/suite.gd"
## The player controller's potions and coins (the owner, 2026-11-19: every reward is an item;
## gameplay/player/player.gd, `bag_use_requested`): a potion drunk from the shown body's bag does
## what its content says through Combat (the max health potion nothing until then); refused, keeping
## the potion, for a stale body key, while down, for what is not drunk (coins, cards) and for a heal
## while whole; while possessing, the possessed body drinks its own; a coin drops one at a time (everything is droppable),
## and the seat's coins are always its home wizard's, a possession or not (the HUD's purse).
const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const ActorFixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const RewardsScript := preload("res://gameplay/rewards/rewards.gd")

const POTIONS: StringName = &"potions"
const COINS: StringName = &"currency"

var _world: Fixture
## Every inventory_refused reason, and every currency bag_changed [player, coins].
var _refused: Array[String] = []
var _purses: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)
	_refused.clear()
	_purses.clear()
	_world.bus.inventory_refused.connect(func(_player: int, reason: String) -> void: _refused.append(reason))
	_world.bus.bag_changed.connect(func(player: int, bag: StringName, ids: Array[StringName], counts: PackedInt32Array, _capacity: int) -> void:
		if bag == COINS:
			_purses.append([player, counts[ids.find(CoinBase.ID)] if ids.has(CoinBase.ID) else 0]))


func after_each() -> void:
	_world.free_all()


func _drink(body: Actor, id: StringName, bag: StringName = POTIONS) -> void:
	_world.bus.bag_use_requested.emit(0, bag, id, body.key())
	_world.run(1)


func test_a_potion_does_what_it_says_only_when_drunk() -> void:
	var wizard: Actor = _world.wizard(0, Vector2.ZERO)
	check(wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"max_health", 1)), "a max health potion")
	check(wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"healing", 1)), "a healing potion")
	_world.run(2)
	check_equal(wizard.health.max_health, 100.0, "held, it does nothing")
	_drink(wizard, &"healing")
	check_equal(_refused, ["You are already whole."] as Array[String], "a heal while whole is refused")
	check_equal(wizard.inventory.count_of(POTIONS, &"healing"), 1, "and kept")
	_drink(wizard, &"max_health")
	check_equal([wizard.health.max_health, wizard.health.health], [110.0, 110.0], "drunk: 10 more most health, healed too")
	_world.hurt(wizard, 40)
	_drink(wizard, &"healing")
	check_equal(wizard.health.health, 100.0, "hurt: healed 30")
	check(wizard.inventory.stacks_in(POTIONS).is_empty(), "both gone")


func test_what_is_not_a_potion_or_not_held_is_refused() -> void:
	var wizard: Actor = _world.wizard(0, Vector2.ZERO)
	check(wizard.inventory.add(ItemStack.of(ItemKinds.COIN, CoinBase.ID, 5)), "five coins")
	_world.run(1)
	_drink(wizard, CoinBase.ID, COINS)
	_drink(wizard, &"bolt", &"cards")
	_drink(wizard, &"healing")
	check_equal(_refused, ["That cannot be used.", "That cannot be used.", "You do not have that."] as Array[String], "coins and cards are not drunk; a potion not held is not there")
	check_equal(wizard.inventory.count_of(COINS, CoinBase.ID), 5, "nothing taken")


func test_a_stale_body_or_a_downed_one_keeps_its_potion() -> void:
	var wizard: Actor = _world.wizard(0, Vector2.ZERO)
	check(wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"max_health", 1)), "a potion")
	_world.run(1)
	_world.bus.bag_use_requested.emit(0, POTIONS, &"max_health", wizard.key() + 1)
	_world.run(1)
	check_equal(_refused, ["That is no longer the body you play."] as Array[String], "another body's key")
	_world.hurt(wizard, 100000)
	check(wizard.is_down(), "down")
	_drink(wizard, &"max_health")
	check_equal(_refused.back(), "You cannot do that while down.", "refused while down")
	check_equal(wizard.inventory.count_of(POTIONS, &"max_health"), 1, "kept both times")


## Everything is droppable (the owner, 2026-11-19): the simulation lays one coin of the stack.
func test_a_coin_is_dropped_one_at_a_time() -> void:
	var wizard: Actor = _world.wizard(0, Vector2.ZERO)
	check(wizard.inventory.add(ItemStack.of(ItemKinds.COIN, CoinBase.ID, 5)), "five coins")
	var dropped: Array = []
	_world.bus.item_drop_requested.connect(func(_actor: int, stack: ItemStack) -> void: dropped.append(stack))
	_world.run(1)
	_world.bus.bag_drop_requested.emit(0, COINS, CoinBase.ID, Inventory.NO_STAFF, wizard.key())
	_world.run(1)
	check(_refused.is_empty(), "nothing refused: %s" % [_refused])
	check_equal(dropped.size(), 1, "one stack laid")
	if dropped.size() == 1:
		check_equal([dropped[0].kind, dropped[0].id, dropped[0].count], [ItemKinds.COIN, CoinBase.ID, 1], "one coin")
	check_equal(wizard.inventory.count_of(COINS, CoinBase.ID), 4, "one fewer held")


func test_while_possessing_the_purse_and_the_drink_are_the_possessed_bodys() -> void:
	var wizard: Actor = _world.wizard(0, Vector2.ZERO, [[&"possess", &"bolt"], [], [], []])
	check(wizard.inventory.add(ItemStack.of(ItemKinds.COIN, CoinBase.ID, 12)), "twelve coins")
	var imp := _possess(wizard)
	check_equal(_purses.back(), [0, 0], "the purse is the imp's coins while it is driven (none yet: 0)")
	check(imp.inventory.add(ItemStack.of(ItemKinds.COIN, CoinBase.ID, 3)), "an enemy's inventory has room for coins")
	check_equal(_purses.back(), [0, 3], "told at once")
	check(wizard.inventory.add(ItemStack.of(ItemKinds.COIN, CoinBase.ID, 1)), "a coin the wizard gains meanwhile")
	check_equal(_purses.back(), [0, 3], "is not the shown body's")
	check(imp.inventory.add(ItemStack.of(ItemKinds.POTION, &"max_health", 1)), "the imp holds a potion")
	_world.run(1)
	_drink(imp, &"max_health")
	check_equal(imp.health.max_health, 60.0, "the body shown drinks its own")
	check_equal(wizard.health.max_health, 100.0, "not the wizard")
	_world.run(80)
	check(wizard.controller == Fixture.controller(wizard), "the possession ended")
	check_equal(_purses.back(), [0, 13], "the purse is the wizard's again")


func test_a_possessing_seat_buys_with_the_possessed_bodys_coins() -> void:
	var rewards := RewardsScript.new()
	rewards.events = _world.bus
	rewards.actors = _world.table
	rewards.projectiles = _world.projectiles
	rewards.spells = _world.spells
	rewards.registry = _world.registry
	rewards.sim = Sim.seeded(3)
	root.add_child(rewards)
	var wizard: Actor = _world.wizard(0, Vector2.ZERO, [[&"possess", &"bolt"], [], [], []])
	check(wizard.inventory.add(ItemStack.of(ItemKinds.COIN, CoinBase.ID, 99)), "a rich wizard")
	var imp := _possess(wizard)
	_world.bus.special_room_opened.emit(4, RoomKind.FILL_SHOP, &"shelf", Rect2(), PackedVector2Array([imp.position]), imp.position + Vector2(0, 400))
	var item: Dictionary = rewards.shelf()[0]
	var refused: Array = []
	_world.bus.shelf_refused.connect(func(seat: int, number: int) -> void: refused.append([seat, number]))
	_world.bus.shelf_buy_requested.emit(0, item["number"])
	_world.run(1)
	rewards.step(Fixture.STEP)
	check_equal(refused, [[0, item["number"]]], "the imp has no coins: refused, whatever its wizard holds")
	check(imp.inventory.add(ItemStack.of(ItemKinds.COIN, CoinBase.ID, 99)), "the imp's own coins")
	_world.bus.shelf_buy_requested.emit(0, item["number"])
	_world.run(1)
	rewards.step(Fixture.STEP)
	check(rewards.shelf().is_empty(), "bought by the body doing the buying")
	check_equal(imp.inventory.count_of(COINS, CoinBase.ID), 99 - int(item["price"]), "paid from the imp's coins")
	check_equal(wizard.inventory.count_of(COINS, CoinBase.ID), 99, "not the wizard's")
	rewards.free()


## Seat 0's wizard (holding `possess · bolt`) possesses an imp 60 px below it; the imp.
func _possess(wizard: Actor) -> Actor:
	var imp := _imp(Vector2(0.0, 60.0))
	_world.hold(0, &"staff_1")
	_world.release(0, &"staff_1")
	_world.run(8)
	check(imp.controller == Fixture.controller(wizard), "the seat drives the imp")
	return imp


## A creature of the kit standing in for an enemy: Health 50, a hurtbox, a Mover, a Caster with a
## bolt and a scripted controller (as tests/gameplay/actor/test_possess.gd's).
func _imp(at: Vector2) -> Actor:
	var body := Actor.new()
	body.name = "Imp"
	var health := Health.new()
	health.max_health = 50
	body.add_child(health)
	body.add_child(Hurtbox.new())
	body.add_child(Mover.new())
	var caster := Caster.new()
	caster.staff_count = 1
	caster.start_cards = [[&"bolt"]]
	body.add_child(caster)
	body.add_child(ActorFixture.Scripted.new())
	body.position = at
	return _world.add(body)
