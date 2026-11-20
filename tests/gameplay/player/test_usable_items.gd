extends "res://tests/support/suite.gd"
## The usable tag (the owner, 2026-11-20: "only usable items can be bound to the D-pad, now and in
## the future"; core/base/item_content.gd `usable`, `ItemKinds.usable`): every item the registry has
## that is tagged usable binds to a d-pad arm and is used by it, one taken; every other item of every
## kind is refused for binding (NO_USE) and never auto-bound as it is taken. Played over the whole
## content, so a new item is covered by itself: tagging one is all it takes to bind it, and a tagged
## one the player controller cannot use fails here.
const Fixture := preload("res://tests/gameplay/player/wizard_fixture.gd")

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)


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


func test_the_potions_are_tagged_and_nothing_else_is() -> void:
	var tagged: Array[StringName] = []
	for item: Array in _every_item():
		if ItemKinds.usable(ItemKinds.bag_of(item[0]), item[1], _world.registry):
			tagged.append(item[1])
			check_equal(item[0], ItemKinds.POTION, "%s: only potions are tagged today" % item[1])
	check(tagged.size() >= 5, "every potion is tagged: %s" % [tagged])


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
		_world.hurt(wizard, 50)
		_world.bus.quick_use_requested.emit(0, 2)
		_world.run(1)
		check_equal(wizard.inventory.count_of(bag, id), 0, "%s: its arm used one" % id)
		wizard.health.health = wizard.health.max_health


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
