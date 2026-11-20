extends "res://tests/support/suite.gd"
## Usable items (the owner, 2026-11-20: "only usable items can be bound to the D-pad"; an item is
## usable exactly when it has a use, `ItemContent.use_of`, `ItemKinds.usable`): every item the
## registry has with a use binds to a d-pad arm and is used by it; every other item of every kind is
## refused for binding (NO_USE) and never auto-bound as it is taken. Played over the whole content,
## so a new item is covered by itself. An active relic (a test-only one) is kept by a use and
## recharges for its cooldown, refused while it does; the recharge is hashed and snapshotted.
const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")

var _world: Fixture
var _refused: Array[String] = []


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)
	_refused.clear()
	_world.bus.inventory_refused.connect(func(_player: int, reason: String) -> void: _refused.append(reason))


func after_each() -> void:
	_world.free_all()


## Every [kind, id] the registry has content of, by the kinds table's folders (`ItemKinds.content`).
func _every_item() -> Array:
	var out: Array = []
	for kind: StringName in ItemKinds.kinds():
		for folder: StringName in ItemKinds.content_of(kind):
			for id: StringName in _world.registry.get_ids(folder):
				if ItemKinds.content(kind, id, _world.registry) != null:
					out.append([kind, id])
	return out


func test_usable_is_exactly_having_a_use_for_every_item() -> void:
	var potions: int = 0
	for item: Array in _every_item():
		var content := ItemKinds.content(item[0], item[1], _world.registry) as ItemContent
		var has_use: bool = content != null and content.use_of() != null
		check_equal(ItemKinds.usable(ItemKinds.bag_of(item[0]), item[1], _world.registry), has_use, "%s %s: usable exactly when it has a use" % item)
		check_equal(has_use, item[0] == ItemKinds.POTION, "%s %s: today the potions have one, nothing else" % item)
		if item[0] == ItemKinds.POTION:
			potions += 1
			check(content.use_of().consumed and content.use_of().cooldown == 0.0, "%s: a potion's use is consumed, with no cooldown" % item[1])
	check(potions >= 5, "every potion asked: %d" % potions)


func test_every_usable_item_binds_and_is_used_by_its_arm() -> void:
	var wizard: Actor = _world.wizard(0, Vector2.ZERO)
	_world.run(1)
	for item: Array in _every_item():
		var bag: StringName = ItemKinds.bag_of(item[0])
		var id: StringName = item[1]
		if not ItemKinds.usable(bag, id, _world.registry):
			continue
		for slot in Inventory.QUICK_SLOTS:
			wizard.inventory.bind_quick(slot, &"", &"")
		check(wizard.inventory.add(ItemStack.of(item[0], id, 1)), "%s taken" % id)
		check_equal(wizard.inventory.quick_id(0), id, "%s: taken, auto-bound up" % id)
		check_equal(wizard.inventory.bind_quick(2, bag, id), Inventory.Refusal.NONE, "%s binds down" % id)
		check_equal([wizard.inventory.quick_id(0), wizard.inventory.quick_id(2)], [&"", id], "%s: moved off up" % id)
		_world.hurt(wizard, 50)
		var before: float = wizard.health.health
		_refused.clear()
		_world.bus.quick_use_requested.emit(0, 2)
		_world.run(1)
		check_equal(wizard.inventory.count_of(bag, id), 0, "%s: its arm used one" % id)
		check(wizard.health.health > before, "%s: and it did something" % id)
		check_equal(_refused, [] as Array[String], "%s: nothing refused" % id)
		wizard.health.health = wizard.health.max_health


## A test-only active relic: heals 25, kept, recharging for COOLDOWN seconds.
const COOLDOWN: float = 2.0


func _active_relic() -> RelicBase:
	var relic := RelicBase.new()
	relic.id = &"test_active_idol"
	relic.active_use = ItemUse.kept(25.0, 0.0, COOLDOWN)
	check_equal(relic.problems(), PackedStringArray(), "a sound active relic")
	check(_world.registry.add(&"relics", relic), "a test-only relic")
	return relic


func _take_relic(wizard: Actor, id: StringName) -> void:
	var stack := ItemStack.new()
	stack.kind = ItemKinds.RELIC
	stack.id = id
	check(wizard.inventory.add(stack), "%s taken into the relics bag" % id)


func _press(slot: int) -> void:
	_refused.clear()
	_world.bus.quick_use_requested.emit(0, slot)
	_world.run(1)


func test_an_active_relic_is_kept_and_recharges_between_uses() -> void:
	var relic: RelicBase = _active_relic()
	var recharges: Array = []
	_world.bus.item_recharging.connect(func(_player: int, _bag: StringName, id: StringName, left: float, whole: float) -> void: recharges.append([id, left > 0.0, whole]))
	var wizard: Actor = _world.wizard(0, Vector2.ZERO)
	_world.run(1)
	check(ItemKinds.usable(&"relics", relic.id, _world.registry), "it has a use: usable, as a potion is")
	_take_relic(wizard, relic.id)
	check_equal([wizard.inventory.quick_bag(0), wizard.inventory.quick_id(0)], [&"relics", relic.id], "auto-bound up")
	_world.hurt(wizard, 80)
	var before_use: int = recharges.size()
	_press(0)
	check_equal(wizard.health.health, 45.0, "its active use healed 25")
	check_equal(_refused, [] as Array[String], "nothing refused")
	check_equal(wizard.inventory.count_of(&"relics", relic.id), 1, "kept: a use does not take it (its stat changes stay)")
	check(wizard.inventory.recharge_left(&"relics", relic.id) > COOLDOWN - 0.1, "recharging for its cooldown")
	check_equal(recharges.back(), [relic.id, true, COOLDOWN], "the HUD told: recharging, of its whole cooldown")
	_press(0)
	check_equal(_refused, ["That is still recharging."] as Array[String], "pressed again while recharging: refused with a hint")
	check_equal(wizard.health.health, 45.0, "and nothing healed")
	# Counted from the use's own start (the recharge runs on through the hurt's hit-stop: sim time).
	var told: int = before_use + 1
	_world.run(int(COOLDOWN * 60.0) + 2)
	check_equal(wizard.inventory.recharge_left(&"relics", relic.id), 0.0, "recharged after its cooldown")
	check_equal(recharges.size() - told, ItemStack.RECHARGE_STEPS, "told at each sixteenth and once ready: %d" % (recharges.size() - told))
	check_equal((recharges.back() as Array).slice(0, 2), [relic.id, false], "the HUD told: ready")
	_press(0)
	check_equal(wizard.health.health, 70.0, "used again across its cooldown: healed again")
	check_equal(wizard.inventory.count_of(&"relics", relic.id), 1, "still kept")
	var quiet := RelicBase.new()
	quiet.id = &"test_passive_idol"
	check(_world.registry.add(&"relics", quiet), "a passive test-only relic (no use)")
	_take_relic(wizard, quiet.id)
	check_equal(wizard.inventory.quick_slot_of(&"relics", quiet.id), Inventory.NO_QUICK, "never auto-bound")
	check_equal(wizard.inventory.bind_quick(1, &"relics", quiet.id), Inventory.Refusal.NO_USE, "no use: refused")
	_world.registry.remove(&"relics", relic.id)
	_world.registry.remove(&"relics", quiet.id)


func test_a_recharge_is_hashed_and_snapshotted() -> void:
	var relic: RelicBase = _active_relic()
	var wizard: Actor = _world.wizard(0, Vector2.ZERO)
	_world.run(1)
	_take_relic(wizard, relic.id)
	_world.hurt(wizard, 50)
	var before: int = SimHash.of(wizard)
	_press(0)
	check(SimHash.of(wizard) != before, "a recharge changes the hash")
	var areas: Dictionary = {"actors": _world.table, "projectiles": _world.projectiles, "spells": _world.spells, "combat": _world.combat}
	areas["actor %d" % wizard.id] = wizard
	var snapshot := Snapshot.take(areas, root)
	check_equal(snapshot.problems.size(), 0, "taken without problems: %s" % [snapshot.problems])
	var left: float = wizard.inventory.recharge_left(&"relics", relic.id)
	var hashed: int = SimHash.of(wizard)
	_world.run(int(COOLDOWN * 60.0) + 2)
	check_equal(wizard.inventory.recharge_left(&"relics", relic.id), 0.0, "recharged")
	check_equal(snapshot.restore(areas, root).size(), 0, "restored without problems")
	check_equal(wizard.inventory.recharge_left(&"relics", relic.id), left, "the recharge comes back as it was")
	check_equal(SimHash.of(wizard), hashed, "and its hash")
	_world.run(30)
	check(wizard.inventory.recharge_left(&"relics", relic.id) < left, "and counts down again")
	_world.registry.remove(&"relics", relic.id)


func test_every_item_with_no_use_is_refused_for_binding() -> void:
	var wizard: Actor = _world.wizard(0, Vector2.ZERO)
	_world.run(1)
	var refused: int = 0
	for item: Array in _every_item():
		var bag: StringName = ItemKinds.bag_of(item[0])
		var id: StringName = item[1]
		if ItemKinds.usable(bag, id, _world.registry) or item[0] == ItemKinds.STAFF:
			continue
		check(wizard.inventory.add(ItemStack.of(item[0], id, 1)), "%s taken" % id)
		check_equal(wizard.inventory.quick_slot_of(bag, id), Inventory.NO_QUICK, "%s: never auto-bound" % id)
		check_equal(wizard.inventory.bind_quick(1, bag, id), Inventory.Refusal.NO_USE, "%s: refused, not usable" % id)
		refused += 1
	var staff: StaffBase = Inventory.staff_content(_world.registry, &"curl")
	check(staff != null and wizard.inventory.add(ItemStack.of_staff(staff)), "a staff taken")
	check_equal(wizard.inventory.bind_quick(1, &"staffs", &"curl"), Inventory.Refusal.NO_USE, "a staff: refused")
	check(refused > 3, "cards, coins, keys and rerolls were all asked: %d" % refused)
	check_equal(wizard.inventory.quick_id(1), &"", "nothing bound by a refusal")
