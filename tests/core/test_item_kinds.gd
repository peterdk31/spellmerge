extends "res://tests/support/suite.gd"
## Tests for the kinds of item (items I3, core/items/item_kinds.gd): every row answers every
## question, every bag is one kind's, and every content folder a row names is a folder of the
## content root whose resources of the row's class the registry finds (cards and staffs: some).
##
## godot --headless --path . --script res://tests/core/test_item_kinds.gd

## The questions every row answers.
const KEYS: Array[String] = ["bag", "stacks", "content", "type", "actions"]
## What can be done with one held, every action a row may name.
const ACTIONS: Array[StringName] = [ItemKinds.DROP, ItemKinds.DROP_ONE, ItemKinds.HAND, ItemKinds.USE]


func test_every_row_answers_every_question() -> void:
	for kind: StringName in ItemKinds.kinds():
		var row: Dictionary = ItemKinds.RULES[kind]
		for key in KEYS:
			check(row.has(key), "%s answers %s" % [kind, key])
		for action: Variant in row.get("actions", []):
			check(ACTIONS.has(StringName(action)), "%s: %s is an action" % [kind, action])


func test_every_bag_holds_one_kind() -> void:
	var bags: Array[StringName] = []
	for kind: StringName in ItemKinds.kinds():
		var bag: StringName = ItemKinds.bag_of(kind)
		check(ItemKinds.BAGS.has(bag), "%s's bag %s is a bag" % [kind, bag])
		check(not bags.has(bag), "%s is one kind's bag" % bag)
		bags.append(bag)
		check_equal(ItemKinds.kind_in(bag), kind, "%s holds %s" % [bag, kind])
	check_equal(bags.size(), ItemKinds.BAGS.size(), "every bag is a kind's")


func test_the_owners_four_kinds() -> void:
	check_equal(ItemKinds.BAGS, [&"staffs", &"cards", &"relics", &"potions"] as Array[StringName], "Staffs, Cards, Relics, Potions, in order")
	check(ItemKinds.stacks(ItemKinds.CARD) and ItemKinds.stacks(ItemKinds.POTION), "cards and potions stack")
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
			if kind == ItemKinds.CARD or kind == ItemKinds.STAFF:
				check(found > 0, "%s: the registry finds some under %s (%d)" % [kind, folder, found])


func test_is_content_goes_by_the_rows_class() -> void:
	check(ItemKinds.is_content(ItemKinds.CARD, CarrierCard.new()), "a carrier is a card (a SpellComponent)")
	check(not ItemKinds.is_content(ItemKinds.CARD, StaffBase.new()), "a staff is not")
	check(ItemKinds.is_content(ItemKinds.STAFF, StaffBase.new()), "a staff is a staff")
	check(not ItemKinds.is_content(&"no_such_kind", StaffBase.new()), "no kind holds nothing")
	check(not ItemKinds.is_content(ItemKinds.CARD, null), "nor nothing")
