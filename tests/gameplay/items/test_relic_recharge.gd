extends "res://tests/support/suite.gd"
## The recharge travels with the relic (the owner, 2026-11-20): an active relic's cooldown left is
## the item's own (`ItemStack.recharge_left`), never its holder's. Dropped mid-recharge it keeps
## recharging on the ground (the Items area's step, sim time), and whoever takes it takes it
## mid-recharge: refused while it recharges, the new holder's HUD told (`item_recharging`). A run's
## start (a loadout) begins ready. What lies recharging is hashed and snapshotted. (A rejoin keeps it:
## tests/gameplay/flow/test_rejoin.gd.)
const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")
const ItemsScript := preload("res://gameplay/items/items.gd")

const RELICS: StringName = &"relics"
## The test-only relic's cooldown, in seconds.
const COOLDOWN: float = 4.0
## Ticks the dropped relic lies before it is taken (the fixture's tick is `Fixture.STEP`).
const ON_GROUND: int = 16

var _world: Fixture
var _items: ItemsScript
var _relic: RelicBase
var _refused: Array = []
## Every item_recharging [player, id, left, whole].
var _told: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_items = ItemsScript.new()
	_items.events = _world.bus
	_items.actors = _world.table
	_items.projectiles = _world.projectiles
	_items.spells = _world.spells
	_items.registry = _world.registry
	_items.frames = _world.frames
	root.add_child(_items)
	_relic = RelicBase.new()
	_relic.id = &"test_wandering_idol"
	_relic.active_use = ItemUse.kept(10.0, 0.0, COOLDOWN)
	check_equal(_relic.problems(), PackedStringArray(), "a sound active relic")
	check(_world.registry.add(RELICS, _relic), "a test-only relic")
	_refused.clear()
	_told.clear()
	_world.bus.inventory_refused.connect(func(player: int, reason: String) -> void: _refused.append([player, reason]))
	_world.bus.item_recharging.connect(func(player: int, _bag: StringName, id: StringName, left: float, whole: float) -> void: _told.append([player, id, left, whole]))


func after_each() -> void:
	_world.registry.remove(RELICS, _relic.id)
	_items.free()
	_world.free_all()


## `count` ticks: the seats' frames and bodies (`Fixture.run`), then the Items step.
func _tick(count: int = 1) -> void:
	for i in count:
		_world.run(1, false)
		_items.step(Fixture.STEP)


## Enough ticks for `seconds` to pass, and one more.
func _ticks_for(seconds: float) -> int:
	return int(ceilf(seconds / Fixture.STEP)) + 1


func _relic_stack() -> ItemStack:
	var stack := ItemStack.new()
	stack.kind = ItemKinds.RELIC
	stack.id = _relic.id
	return stack


## Seat 0 holds the relic and uses it (hurt first, so the heal is wanted): it recharges.
func _used_by_seat_0() -> Actor:
	var wizard: Actor = _world.wizard(0, Vector2.ZERO)
	_tick()
	check(wizard.inventory.add(_relic_stack()), "seat 0 takes the relic")
	_world.hurt(wizard, 50)
	_world.bus.quick_use_requested.emit(0, 0)
	_tick()
	check(wizard.inventory.recharge_left(RELICS, _relic.id) > COOLDOWN - 0.1, "used: recharging")
	return wizard


func _lying() -> GroundItem:
	var lying: Array[GroundItem] = _items.lying()
	check_equal(lying.size(), 1, "one item lies there")
	return lying[0] if not lying.is_empty() else null


func test_a_dropped_relic_recharges_on_the_ground_and_is_taken_mid_recharge() -> void:
	var first: Actor = _used_by_seat_0()
	var second: Actor = _world.wizard(1, Vector2(200, 0))
	_tick(4)
	var held_left: float = first.inventory.recharge_left(RELICS, _relic.id)
	_told.clear()
	check_equal(first.inventory.drop(RELICS, _relic.id), Inventory.Refusal.NONE, "seat 0 drops it mid-recharge")
	check_equal(first.inventory.recharge_left(RELICS, _relic.id), 0.0, "its holder keeps no recharge of it")
	check(_told.has([0, _relic.id, 0.0, 0.0]), "seat 0's HUD told: nothing recharging now (%s)" % [_told])
	var row: GroundItem = _lying()
	check_equal(row.stack.recharge_left, held_left, "it lies as recharged as it was held")
	check_equal(row.stack.recharge_whole, COOLDOWN, "of its whole cooldown")
	_tick(ON_GROUND)
	row = _lying()
	check(absf(row.stack.recharge_left - (held_left - ON_GROUND * Fixture.STEP)) < 0.001, "%d ticks on the ground: as much recharged (%s of %s)" % [ON_GROUND, row.stack.recharge_left, held_left])
	var ground_left: float = row.stack.recharge_left
	second.position = row.at
	_told.clear()
	_world.bus.item_take_requested.emit(1, row.number)
	_tick()
	check_equal(_items.lying().size(), 0, "seat 1 took it")
	check_equal(second.inventory.count_of(RELICS, _relic.id), 1, "into its relics bag")
	var taken_left: float = second.inventory.recharge_left(RELICS, _relic.id)
	check(taken_left > 0.0 and taken_left <= ground_left, "taken mid-recharge (%s of %s)" % [taken_left, ground_left])
	check_equal(second.inventory.recharge_whole(RELICS, _relic.id), COOLDOWN, "of its whole cooldown")
	var told_seat_1: Array = _told.filter(func(entry: Array) -> bool: return entry[0] == 1 and entry[1] == _relic.id)
	check(not told_seat_1.is_empty() and float(told_seat_1[0][2]) > 0.0 and float(told_seat_1[0][3]) == COOLDOWN, "seat 1's HUD told it recharges (%s)" % [_told])
	_world.hurt(second, 50)
	var health: float = second.health.health
	_refused.clear()
	_world.bus.quick_use_requested.emit(1, 0)
	_tick()
	check_equal(_refused, [[1, "That is still recharging."]], "seat 1's use refused while it recharges")
	check_equal(second.health.health, health, "and nothing healed")
	_tick(_ticks_for(taken_left))
	check_equal(second.inventory.recharge_left(RELICS, _relic.id), 0.0, "recharged in seat 1's bag")
	_refused.clear()
	_world.bus.quick_use_requested.emit(1, 0)
	_tick()
	check_equal(_refused, [], "now used")
	check_equal(second.health.health, health + 10.0, "healed by it")


func test_a_ready_relic_dropped_lies_ready_and_two_copies_keep_their_own() -> void:
	var wizard: Actor = _world.wizard(0, Vector2.ZERO)
	_tick()
	check(wizard.inventory.add(_relic_stack()), "one copy")
	check(wizard.inventory.add(_relic_stack()), "and another")
	wizard.inventory.start_recharge(RELICS, _relic.id, COOLDOWN)
	check_equal(wizard.inventory.recharge_left(RELICS, _relic.id), 0.0, "one copy recharging, the other ready: it can be used")
	wizard.inventory.start_recharge(RELICS, _relic.id, 1.0)
	check_equal(wizard.inventory.recharge_left(RELICS, _relic.id), 1.0, "both used: the readiest is shown")
	check_equal(wizard.inventory.recharges().size(), 2, "each copy recharges for itself")
	check_equal(wizard.inventory.drop(RELICS, _relic.id), Inventory.Refusal.NONE, "one dropped")
	check_equal(_lying().stack.recharge_left, COOLDOWN, "the least ready copy is the one let go")
	check_equal(wizard.inventory.recharge_left(RELICS, _relic.id), 1.0, "the readiest kept")
	_tick(_ticks_for(1.0))
	check_equal(wizard.inventory.recharge_left(RELICS, _relic.id), 0.0, "the kept one is ready")
	check_equal(wizard.inventory.drop(RELICS, _relic.id), Inventory.Refusal.NONE, "and dropped too")
	var ready_row: GroundItem = null
	for row: GroundItem in _items.lying():
		if not row.stack.is_recharging():
			ready_row = row
	check(ready_row != null, "it lies ready")


func test_a_run_start_begins_ready() -> void:
	var wizard: Actor = _used_by_seat_0()
	var fresh := Inventory.new()
	fresh.take_loadout(wizard.inventory.loadout(), _world.registry)
	check_equal(fresh.count_of(RELICS, _relic.id), 1, "the loadout carries the relic")
	check_equal(fresh.recharge_left(RELICS, _relic.id), 0.0, "and it begins ready")
	check(not fresh.is_recharging(), "nothing recharges")
	fresh.free()


func test_what_lies_recharging_is_hashed_and_snapshotted() -> void:
	var wizard: Actor = _used_by_seat_0()
	check_equal(wizard.inventory.drop(RELICS, _relic.id), Inventory.Refusal.NONE, "dropped mid-recharge")
	_tick()
	var hashed: int = SimHash.of(_items)
	_tick()
	check(SimHash.of(_items) != hashed, "its recharge on the ground changes the area's hash")
	var areas: Dictionary = {"actors": _world.table, "items": _items}
	areas["actor %d" % wizard.id] = wizard
	var snapshot := Snapshot.take(areas, root)
	check_equal(snapshot.problems.size(), 0, "taken without problems: %s" % [snapshot.problems])
	var left: float = _lying().stack.recharge_left
	hashed = SimHash.of(_items)
	_tick(_ticks_for(COOLDOWN))
	check(not _lying().stack.is_recharging(), "recharged where it lies")
	check_equal(snapshot.restore(areas, root).size(), 0, "restored without problems")
	check_equal(_lying().stack.recharge_left, left, "the recharge comes back as it was")
	check_equal(SimHash.of(_items), hashed, "and the hash")
	_tick(2)
	check(_lying().stack.recharge_left < left, "and counts down again")


## A copy taken beside one held: the readiest is what is used and shown (the HUD told only when that
## changes); `take` lets the least ready copy go, as a drop does; a rejoin's list
## (`recharges`/`set_recharges`) gives each copy its own recharge back.
func test_copies_taken_beside_one_held() -> void:
	var wizard: Actor = _world.wizard(0, Vector2.ZERO)
	_tick()
	check(wizard.inventory.add(_relic_stack()), "a ready copy held")
	_told.clear()
	var tired: ItemStack = _relic_stack()
	tired.start_recharge(COOLDOWN)
	check(wizard.inventory.add(tired), "a recharging copy taken beside it")
	check_equal(wizard.inventory.recharge_left(RELICS, _relic.id), 0.0, "still usable: the ready copy")
	check_equal(_told, [], "nothing told: what is shown did not change")
	check(wizard.inventory.is_recharging(), "but the taken copy recharges")
	check(wizard.inventory.take(RELICS, _relic.id, 1), "one taken out")
	check_equal(wizard.inventory.recharge_left(RELICS, _relic.id), 0.0, "the least ready went: the ready copy kept")
	check(not wizard.inventory.is_recharging(), "nothing recharges now")
	wizard.inventory.start_recharge(RELICS, _relic.id, COOLDOWN)
	_told.clear()
	check(wizard.inventory.add(_relic_stack()), "a ready copy taken while its own recharges")
	check_equal(wizard.inventory.recharge_left(RELICS, _relic.id), 0.0, "usable at once")
	check_equal(_told, [[0, _relic.id, 0.0, 0.0]], "the HUD told it is ready")
	wizard.inventory.start_recharge(RELICS, _relic.id, 1.0)
	var list: Array = wizard.inventory.recharges()
	check_equal(list.size(), 2, "two copies recharging, each its own")
	var fresh := Inventory.new()
	fresh.take_loadout(wizard.inventory.loadout(), _world.registry)
	check(not fresh.is_recharging(), "a loadout: both ready")
	fresh.set_recharges(list)
	check_equal(fresh.recharges(), list, "a rejoin's list gives each copy its recharge back")
	check_equal(fresh.recharge_left(RELICS, _relic.id), 1.0, "the readiest shown")
	fresh.free()


## A held relic recharges in the simulation's time whatever holds its body (the owner's "sim time"):
## while its holder spawns in, as one lying on the ground does.
func test_a_held_relic_recharges_while_its_holder_is_held() -> void:
	var wizard: Actor = _used_by_seat_0()
	var left: float = wizard.inventory.recharge_left(RELICS, _relic.id)
	wizard.spawn_left = 10.0
	_tick(4)
	check(absf(wizard.inventory.recharge_left(RELICS, _relic.id) - (left - 4.0 * Fixture.STEP)) < 0.001, "counted while it spawns in (%s of %s)" % [wizard.inventory.recharge_left(RELICS, _relic.id), left])
