extends "res://tests/support/suite.gd"
## Tests for the kinds of item (items I3, core/items/item_kinds.gd): every row answers every
## question, every bag is one kind's, and every content folder a row names is a folder of the
## content root whose resources of the row's class the registry finds (cards and staffs: some).
## The questions every row answers.
const KEYS: Array[String] = ["bag", "stacks", "content", "type", "actions", "premade"]
## What can be done with one held, every action a row may name.
const ACTIONS: Array[StringName] = [ItemKinds.DROP, ItemKinds.DROP_ONE, ItemKinds.HAND, ItemKinds.USE]


func test_every_row_answers_every_question() -> void:
	for kind: StringName in ItemKinds.kinds():
		var row: Dictionary = ItemKinds.RULES[kind]
		for key in KEYS:
			check(row.has(key), "%s answers %s" % [kind, key])
		for action: Variant in row.get("actions", []):
			check(ACTIONS.has(StringName(action)), "%s: %s is an action" % [kind, action])


func test_every_bag_holds_its_kinds() -> void:
	var bags: Array[StringName] = []
	for kind: StringName in ItemKinds.kinds():
		var bag: StringName = ItemKinds.bag_of(kind)
		check(ItemKinds.BAGS.has(bag), "%s's bag %s is a bag" % [kind, bag])
		check(ItemKinds.kinds_in(bag).has(kind), "%s holds %s" % [bag, kind])
		if not bags.has(bag):
			bags.append(bag)
		if ItemKinds.kinds_in(bag).size() == 1:
			check_equal(ItemKinds.kind_in(bag), kind, "%s holds only %s" % [bag, kind])
	check_equal(bags.size(), ItemKinds.BAGS.size(), "every bag is a kind's")


func test_the_currency_bag_holds_the_coins_and_the_keys() -> void:
	check_equal(ItemKinds.kinds_in(&"currency"), [ItemKinds.COIN, ItemKinds.KEY, ItemKinds.REROLL] as Array[StringName], "the coins, the keys and the reward rerolls share the currency bag")
	check_equal(ItemKinds.kind_in(&"currency", RerollBase.REWARD), ItemKinds.REROLL, "a reward reroll's id is a reroll")
	check(ItemKinds.stacks(ItemKinds.REROLL) and ItemKinds.can(ItemKinds.REROLL, ItemKinds.DROP), "a reroll is a stack, dropped as any currency")
	var made: ItemContent = root.get_node("Registry").get_resource(&"rerolls", RerollBase.REWARD) as ItemContent
	check(made is RerollBase and ItemKinds.kind_of(made) == ItemKinds.REROLL, "the reward reroll is found under rerolls")
	check(made != null and made.problems().is_empty(), "the reward reroll has no problems")
	check(root.get_node("Registry").get_resource(&"rerolls", &"room_reroll") == null, "no room reroll (the owner, 2026-11-19: rewards only)")
	check_equal(ItemKinds.kind_in(&"currency", CoinBase.ID), ItemKinds.COIN, "the coin's id is a coin")
	check_equal(ItemKinds.kind_in(&"currency", KeyBase.ID), ItemKinds.KEY, "the key's id is a key")
	check(ItemKinds.stacks(ItemKinds.KEY) and ItemKinds.can(ItemKinds.KEY, ItemKinds.DROP), "a key is one stack, dropped (everything is droppable, the owner, 2026-11-19)")
	var loadout := PlayerLoadout.new()
	check(loadout.add_stack(&"currency", CoinBase.ID, 4) and loadout.add_stack(&"currency", KeyBase.ID, 2), "a loadout carries both")
	var inventory := Inventory.new()
	inventory.take_loadout(loadout, root.get_node("Registry"))
	var kinds: Array[StringName] = []
	for stack: ItemStack in inventory.stacks_in(&"currency"):
		kinds.append(stack.kind)
	check_equal(kinds, [ItemKinds.COIN, ItemKinds.KEY] as Array[StringName], "each stack taken from a loadout knows its kind by its id")
	check(inventory.take(&"currency", KeyBase.ID) and inventory.count_of(&"currency", KeyBase.ID) == 1 and inventory.count_of(&"currency", CoinBase.ID) == 4, "a key taken leaves the coins")
	inventory.free()


func test_the_owners_kinds() -> void:
	check_equal(ItemKinds.BAGS, [&"staffs", &"cards", &"relics", &"potions", &"currency"] as Array[StringName], "Staffs, Cards, Relics, Potions, in order, then the currency")
	check(ItemKinds.stacks(ItemKinds.CARD) and ItemKinds.stacks(ItemKinds.POTION), "cards and potions stack")
	check(ItemKinds.stacks(ItemKinds.COIN) and ItemKinds.can(ItemKinds.COIN, ItemKinds.DROP), "coins are one stack, dropped")
	for kind: StringName in ItemKinds.kinds():
		check(ItemKinds.can(kind, ItemKinds.DROP) or ItemKinds.can(kind, ItemKinds.DROP_ONE), "everything is droppable: %s" % kind)
	check(ItemKinds.can(ItemKinds.POTION, ItemKinds.USE), "a potion is used (drunk)")
	check(not ItemKinds.stacks(ItemKinds.STAFF) and not ItemKinds.stacks(ItemKinds.RELIC), "staffs and relics do not")
	check(ItemKinds.can(ItemKinds.STAFF, ItemKinds.HAND) and not ItemKinds.can(ItemKinds.CARD, ItemKinds.HAND), "only a staff goes on a hand")
	check(ItemKinds.can(ItemKinds.CARD, ItemKinds.DROP_ONE), "a card drops one at a time")


func test_every_content_folder_named_is_there_and_holds_its_kind() -> void:
	var registry: Node = root.get_node("Registry")
	for kind: StringName in ItemKinds.kinds():
		for folder: StringName in ItemKinds.content_of(kind):
			check(DirAccess.dir_exists_absolute("res://content/%s" % folder), "%s: content/%s is there" % [kind, folder])
			var found: int = 0
			for id: StringName in registry.call("get_ids", folder):
				if ItemKinds.is_content(kind, registry.call("get_resource", folder, id) as Resource):
					found += 1
			if kind != ItemKinds.RELIC:
				check(found > 0, "%s: the registry finds some under %s (%d)" % [kind, folder, found])


func test_potions_and_the_coin_are_sound_content() -> void:
	var registry: Node = root.get_node("Registry")
	for folder: StringName in [&"potions", &"coins", &"keys"]:
		for id: StringName in registry.call("get_ids", folder):
			var item := registry.call("get_resource", folder, id) as ItemContent
			check(item != null and item.problems().is_empty(), "%s/%s: %s" % [folder, id, item.problems() if item != null else "not an item"])
			check(ItemKinds.stack_of(item) != null, "%s/%s can lie on the ground as a stack" % [folder, id])
	var healing := registry.call("get_resource", &"potions", &"healing") as PotionBase
	check(healing.wasted_on(100.0, 100.0) and not healing.wasted_on(50.0, 100.0), "a heal is wasted only on the whole")
	var more := registry.call("get_resource", &"potions", &"max_health") as PotionBase
	check(not more.wasted_on(100.0, 100.0), "more most health never is")


func test_is_content_goes_by_the_rows_class() -> void:
	check(ItemKinds.is_content(ItemKinds.CARD, CarrierCard.new()), "a carrier is a card (a SpellComponent)")
	check(not ItemKinds.is_content(ItemKinds.CARD, StaffBase.new()), "a staff is not")
	check(ItemKinds.is_content(ItemKinds.STAFF, StaffBase.new()), "a staff is a staff")
	check(not ItemKinds.is_content(&"no_such_kind", StaffBase.new()), "no kind holds nothing")
	check(not ItemKinds.is_content(ItemKinds.CARD, null), "nor nothing")


## Items I6: every premade folder a row names is there, and the registry finds premade items of
## that kind in it, each a stack of the kind (the hub's rack among them).
func test_every_premade_folder_holds_items_of_its_kind() -> void:
	var registry: Node = root.get_node("Registry")
	for kind: StringName in ItemKinds.kinds():
		for folder: StringName in ItemKinds.premade_of(kind):
			check(DirAccess.dir_exists_absolute("res://content/%s" % folder), "%s: content/%s is there" % [kind, folder])
			var found: int = 0
			for id: StringName in registry.call("get_ids", folder):
				var stack: ItemStack = ItemKinds.stack_of(registry.call("get_resource", folder, id) as Resource)
				check(stack != null and stack.kind == kind, "%s: %s under %s is one" % [kind, id, folder])
				var item: Resource = registry.call("get_resource", folder, id) as Resource
				var name: String = (item as StaffItem).shown_name() if item is StaffItem else ""
				check(GroundLoadout.new().add_item(kind, id, name, 1, Vector2.ZERO, 0.0, stack.cards if stack != null else ([] as Array[StringName])), "%s: %s's name and cards travel in a recording (plain text, at most %d letters)" % [kind, id, GroundLoadout.MAX_TITLE])
				found += 1
			check(found > 0, "%s: some under %s" % [kind, folder])


func test_stack_of_makes_one_of_anything_that_lies_on_the_ground() -> void:
	var registry: Node = root.get_node("Registry")
	var card: ItemStack = ItemKinds.stack_of(registry.call("get_resource", &"spells", &"bolt") as Resource)
	check_equal([card.kind, card.id, card.count], [ItemKinds.CARD, &"bolt", 1], "a card, one copy")
	var curl: StaffBase = registry.call("get_resource", &"wizard", &"curl") as StaffBase
	var staff: ItemStack = ItemKinds.stack_of(curl)
	check_equal([staff.kind, staff.id, staff.cards.size(), staff.mana], [ItemKinds.STAFF, &"curl", curl.slots, curl.max_mana], "a staff, empty and full")
	var premade := StaffItem.new()
	premade.staff = curl
	premade.cards = [&"bolt"] as Array[StringName]
	check_equal(ItemKinds.stack_of(premade).cards[0], &"bolt", "a premade staff with its cards")
	check(ItemKinds.stack_of(StaffItem.new()) == null, "a premade staff with no staff is nothing")
	check(ItemKinds.stack_of(StaffCards.new()) == null, "what is no kind's is nothing")
	check(ItemKinds.stack_of(null) == null, "nor is nothing")
