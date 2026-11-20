extends "res://tests/support/suite.gd"
## The usable tag (the owner, 2026-11-20: "only usable items can be bound to the D-pad, now and in
## the future"; core/base/item_content.gd `usable`, `ItemKinds.usable`): every item the registry has
## that is tagged usable binds to a d-pad arm and is used by it, one taken; every other item of every
## kind is refused for binding (NO_USE) and never auto-bound as it is taken. Played over the whole
## content, so a new item is covered by itself: tagging one is all it takes to bind it, and a tagged
## one the player controller cannot use fails here.
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


func test_every_potion_is_tagged_and_nothing_else_is() -> void:
	var potions: int = 0
	for item: Array in _every_item():
		var tagged: bool = ItemKinds.usable(ItemKinds.bag_of(item[0]), item[1], _world.registry)
		check_equal(tagged, item[0] == ItemKinds.POTION, "%s %s: the potions are tagged, nothing else is today" % item)
		if item[0] == ItemKinds.POTION:
			potions += 1
	check(potions >= 5, "every potion asked: %d" % potions)


func test_every_tagged_item_binds_and_is_used_by_its_arm() -> void:
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


func test_a_relic_tagged_usable_binds_and_its_active_use_is_used() -> void:
	var relic := RelicBase.new()
	relic.id = &"test_active_idol"
	relic.usable = true
	relic.active_use = ItemUse.health(25.0, 0.0)
	check_equal(relic.problems(), PackedStringArray(), "a sound active relic")
	check(_world.registry.add(&"relics", relic), "a test-only relic")
	var wizard: Actor = _world.wizard(0, Vector2.ZERO)
	_world.run(1)
	check(ItemKinds.usable(&"relics", relic.id, _world.registry), "tagged: usable, as a potion is")
	var stack := ItemStack.new()
	stack.kind = ItemKinds.RELIC
	stack.id = relic.id
	check(wizard.inventory.add(stack), "taken into the relics bag")
	check_equal(wizard.inventory.quick_id(0), relic.id, "auto-bound up")
	check_equal(wizard.inventory.quick_bag(0), &"relics", "of the relics bag")
	_world.hurt(wizard, 50)
	_refused.clear()
	_world.bus.quick_use_requested.emit(0, 0)
	_world.run(1)
	check_equal(wizard.health.health, 75.0, "its active use healed 25")
	check_equal(_refused, [] as Array[String], "nothing refused")
	check_equal(wizard.inventory.count_of(&"relics", relic.id), 0, "a use takes it, as a potion's does")
	var quiet := RelicBase.new()
	quiet.id = &"test_passive_idol"
	check(_world.registry.add(&"relics", quiet), "an untagged test-only relic")
	var passive := ItemStack.new()
	passive.kind = ItemKinds.RELIC
	passive.id = quiet.id
	check(wizard.inventory.add(passive), "taken")
	check_equal(wizard.inventory.quick_slot_of(&"relics", quiet.id), Inventory.NO_QUICK, "never auto-bound")
	check_equal(wizard.inventory.bind_quick(1, &"relics", quiet.id), Inventory.Refusal.NO_USE, "untagged: refused")
	_world.registry.remove(&"relics", relic.id)
	_world.registry.remove(&"relics", quiet.id)


func test_every_untagged_item_is_refused_for_binding() -> void:
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
