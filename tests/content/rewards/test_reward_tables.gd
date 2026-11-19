extends "res://tests/support/suite.gd"
## The reward tables (content/rewards, connected biomes CB10): each one the registry finds has no
## problem (`RewardTable.problems`), every line wraps an item that is there (the owner, 2026-11-19:
## a card it names is a card, a potion a potion, the coin the coin), and the table a room's clear
## rolls from is there.

const RewardsScript := preload("res://gameplay/rewards/rewards.gd")

var _registry: Node = null


func before_each() -> void:
	_registry = own(preload("res://core/registry/registry.gd").new())
	_registry.call(&"scan")


func test_every_reward_table_is_sound() -> void:
	var tables: Array[Resource] = _registry.call(&"get_all", RewardsScript.TABLES)
	check(not tables.is_empty(), "there are reward tables")
	for found: Resource in tables:
		var table := found as RewardTable
		check(table != null, "%s is a RewardTable" % found)
		if table == null:
			continue
		check(table.problems().is_empty(), "%s: %s" % [table.id, table.problems()])
		for entry: RewardEntry in table.entries:
			if entry == null or (entry.kind == ItemKinds.CARD and entry.id == &""):
				continue
			var item: Resource = ItemLooks.content_of(entry.kind, entry.id, _registry)
			check(item != null, "%s names the %s '%s', which is one" % [table.id, entry.kind, entry.id])


func test_a_clear_has_its_table() -> void:
	check(_registry.call(&"get_resource", RewardsScript.TABLES, RewardsScript.CLEAR_TABLE) is RewardTable, "the clear's table is there")


func test_a_tables_problems_are_named() -> void:
	var table := RewardTable.new()
	check_equal(table.problems().size(), 2, "no id and no lines")
	table.id = &"bad"
	table.entries = [RewardEntry.make(&"gem", &"ruby"), RewardEntry.make(ItemKinds.COIN, &"bolt", 0, 0.0), RewardEntry.make(ItemKinds.POTION), null] as Array[RewardEntry]
	# The gem's kind; the coins' id, count and weight; the potion naming none; the empty line.
	check_equal(table.problems().size(), 6, "every line's problems: %s" % [table.problems()])


func test_every_kind_of_reward_wraps_an_item() -> void:
	var tables: Array[Resource] = _registry.call(&"get_all", RewardsScript.TABLES)
	var kinds: Dictionary = {}
	for found: Resource in tables:
		for entry: RewardEntry in (found as RewardTable).entries:
			kinds[entry.kind] = true
	for kind: StringName in [ItemKinds.CARD, ItemKinds.POTION, ItemKinds.COIN]:
		check(kinds.has(kind), "a table gives a %s, an inventory item" % kind)
	check(ItemLooks.content_of(ItemKinds.POTION, &"healing", _registry) is PotionBase, "the healing potion")
	check(ItemLooks.content_of(ItemKinds.POTION, &"max_health", _registry) is PotionBase, "the max health potion")
	check(ItemLooks.content_of(ItemKinds.COIN, CoinBase.ID, _registry) is CoinBase, "the coin")
