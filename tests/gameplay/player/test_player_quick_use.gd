extends "res://tests/support/suite.gd"
## The quick-use slots (the owner, 2026-11-20: "each D-pad direction can be bound to a usable item";
## gameplay/actor/inventory.gd, gameplay/player/player.gd): `quick_bind_requested` binds a slot of the
## shown body to an item it holds and can use (moved from another slot, let go on its own),
## `quick_use_requested` uses one as `bag_use_requested` does; with none left the binding stays and
## is full again as one is taken; no slot is bound at first, and a usable item taken that no slot is
## bound to fills the first free one (up, right, down, left; the owner, 2026-11-20); `quick_bound` tells the HUD each slot; a binding is in the player
## loadout, hashed and saved by a snapshot.
const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")

const POTIONS: StringName = &"potions"

var _world: Fixture
var _refused: Array[String] = []
## Every quick_bound [player, slot, bag, id].
var _bound: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)
	_refused.clear()
	_bound.clear()
	_world.bus.inventory_refused.connect(func(_player: int, reason: String) -> void: _refused.append(reason))
	_world.bus.quick_bound.connect(func(player: int, slot: int, bag: StringName, id: StringName) -> void: _bound.append([player, slot, bag, id]))


func after_each() -> void:
	_world.free_all()


func _bind(body: Actor, slot: int, id: StringName, bag: StringName = POTIONS) -> void:
	_world.bus.quick_bind_requested.emit(0, slot, bag, id, body.key())
	_world.run(1)


func _use(slot: int) -> void:
	_world.bus.quick_use_requested.emit(0, slot)
	_world.run(1)


func _quick(body: Actor) -> Array:
	var out: Array = []
	for slot in Inventory.QUICK_SLOTS:
		out.append(body.inventory.quick_id(slot))
	return out


func test_a_slot_binds_a_usable_item_moves_it_and_lets_it_go() -> void:
	var wizard: Actor = _world.wizard(0, Vector2.ZERO)
	_world.run(1)
	check_equal(_quick(wizard), [&"", &"", &"", &""], "nothing bound at first: no default bindings")
	check(wizard.inventory.add(ItemStack.of(ItemKinds.COIN, CoinBase.ID, 5)), "five coins")
	check_equal(_quick(wizard), [&"", &"", &"", &""], "coins are never used: never bound")
	check(wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"healing", 2)), "two healing potions")
	check_equal(_quick(wizard), [&"healing", &"", &"", &""], "taken, it fills the first free slot: up")
	wizard.inventory.bind_quick(0, POTIONS, &"")
	_bind(wizard, 0, &"healing")
	check_equal(_quick(wizard), [&"healing", &"", &"", &""], "up: the healing potion")
	check_equal(wizard.inventory.quick_bag(0), POTIONS, "of the potions bag")
	check_equal(_bound.back(), [0, 0, POTIONS, &"healing"], "told to the HUD")
	_bind(wizard, 2, &"healing")
	check_equal(_quick(wizard), [&"", &"", &"healing", &""], "bound down, it moved off up")
	_bind(wizard, 2, &"healing")
	check_equal(_quick(wizard), [&"", &"", &"", &""], "bound on its own slot again: let go")
	_bind(wizard, 1, CoinBase.ID, &"currency")
	_bind(wizard, 1, &"max_health")
	_bind(wizard, 7, &"healing")
	check_equal(_refused, ["That cannot be used.", "You do not have that.", "There is no such slot."] as Array[String], "coins are never used, a potion not held, a slot past the four")
	check_equal(_quick(wizard), [&"", &"", &"", &""], "nothing bound by a refusal")
	wizard.inventory.bind_quick(1, POTIONS, &"healing")
	_world.bus.quick_bind_requested.emit(0, 3, POTIONS, &"healing", wizard.key() + 1)
	_world.run(1)
	check_equal(_refused.back(), "That is no longer the body you play.", "another body's key")
	check_equal(_quick(wizard), [&"", &"healing", &"", &""], "kept")


func test_a_usable_item_taken_fills_the_first_free_slot_once() -> void:
	var wizard: Actor = _world.wizard(0, Vector2.ZERO)
	_world.run(1)
	wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"healing", 1))
	wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"max_health", 1))
	check_equal(_quick(wizard), [&"healing", &"max_health", &"", &""], "each new kind the next free slot, in order")
	wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"healing", 2))
	check_equal(_quick(wizard), [&"healing", &"max_health", &"", &""], "one bound already is not bound twice")
	wizard.inventory.bind_quick(0, POTIONS, &"max_health")
	check_equal(_quick(wizard), [&"max_health", &"", &"", &""], "rebound by the player, it moves")
	wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"vigor", 1))
	wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"small_healing", 1))
	wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"large_healing", 1))
	check_equal(_quick(wizard), [&"max_health", &"vigor", &"small_healing", &"large_healing"], "free slots filled up, right, down, left")
	wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"healing", 1))
	check_equal(_quick(wizard), [&"max_health", &"vigor", &"small_healing", &"large_healing"], "none free: nothing changes")
	var made := Inventory.new()
	made.take_loadout(wizard.inventory.loadout(), _world.registry)
	check_equal([made.quick_id(0), made.quick_id(3)], [&"max_health", &"large_healing"], "a loadout taken keeps its own bindings")
	made.free()


func test_a_press_uses_one_and_an_empty_binding_stays_until_refilled() -> void:
	var wizard: Actor = _world.wizard(0, Vector2.ZERO)
	check(wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"healing", 1)), "one healing potion")
	_world.run(1)
	_bind(wizard, 3, &"healing")
	check_equal(_quick(wizard), [&"", &"", &"", &"healing"], "bound left, off up where it fell")
	_use(3)
	check_equal(_refused, ["You are already whole."] as Array[String], "whole: never wasted")
	check_equal(wizard.inventory.count_of(POTIONS, &"healing"), 1, "kept")
	_world.hurt(wizard, 50)
	_use(1)
	check_equal(wizard.health.health, 50.0, "a slot bound to nothing does nothing")
	_use(3)
	check_equal(wizard.health.health, 80.0, "left: healed 30, through Combat")
	check_equal(wizard.inventory.count_of(POTIONS, &"healing"), 0, "the last one gone")
	check_equal(wizard.inventory.quick_id(3), &"healing", "the binding stays with none left")
	_use(3)
	check_equal(_refused.back(), "You do not have that.", "none left: refused")
	check(wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"healing", 1)), "another picked up")
	_use(3)
	check_equal(wizard.health.health, 100.0, "refilled: the same press heals again")
	_world.hurt(wizard, 100000)
	check(wizard.is_down(), "down")
	check(wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"healing", 1)), "one more")
	_use(3)
	check_equal(_refused.back(), "You cannot do that while down.", "refused while down")
	check_equal(wizard.inventory.count_of(POTIONS, &"healing"), 1, "and kept")


func test_the_slots_are_announced_with_the_body() -> void:
	var wizard: Actor = _world.wizard(0, Vector2.ZERO)
	check(wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"max_health", 1)), "a potion")
	wizard.inventory.bind_quick(1, POTIONS, &"max_health")
	check_equal(wizard.inventory.quick_id(0), &"", "moved off up")
	_bound.clear()
	var controller: PlayerController = Fixture.controller(wizard)
	controller.rebuild_derived()
	controller._watched = null
	controller._show_anew()
	check_equal(_bound, [[0, 0, &"", &""], [0, 1, POTIONS, &"max_health"], [0, 2, &"", &""], [0, 3, &"", &""]], "every slot, after the announcement")


func test_a_binding_is_in_the_loadout_the_hash_and_a_snapshot() -> void:
	var wizard: Actor = _world.wizard(0, Vector2.ZERO)
	check(wizard.inventory.add(ItemStack.of(ItemKinds.POTION, &"healing", 2)), "two potions")
	wizard.inventory.bind_quick(0, POTIONS, &"")
	_world.run(1)
	var loadout: PlayerLoadout = wizard.inventory.loadout()
	var before: int = SimHash.of(wizard)
	wizard.inventory.bind_quick(2, POTIONS, &"healing")
	check(not wizard.inventory.at_rest(), "bound, it is no longer as made")
	check(SimHash.of(wizard) != before, "a binding changes the state's hash")
	check(not wizard.inventory.loadout().equals(loadout), "and the loadout")
	check_equal([wizard.inventory.loadout().quick_bag(2), wizard.inventory.loadout().quick_id(2)], [POTIONS, &"healing"], "bound in it")
	var made := Inventory.new()
	made.take_loadout(wizard.inventory.loadout(), _world.registry)
	check_equal(made.quick_id(2), &"healing", "a wizard made from it holds it bound")
	made.free()
	var areas: Dictionary = {"actors": _world.table, "projectiles": _world.projectiles, "spells": _world.spells, "combat": _world.combat}
	areas["actor %d" % wizard.id] = wizard
	var snapshot := Snapshot.take(areas, root)
	check_equal(snapshot.problems.size(), 0, "taken without problems: %s" % [snapshot.problems])
	var hashed: int = SimHash.of(wizard)
	wizard.inventory.bind_quick(0, POTIONS, &"healing")
	check_equal(snapshot.restore(areas, root).size(), 0, "restored without problems")
	check_equal(_quick(wizard), [&"", &"", &"healing", &""], "the binding comes back as it was")
	check_equal(SimHash.of(wizard), hashed, "and its hash")
