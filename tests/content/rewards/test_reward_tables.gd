extends "res://tests/support/suite.gd"
## The reward tables (content/rewards, connected biomes CB10): each one the registry finds has no
## problem (`RewardTable.problems`), every card a line names is a card, and the table a room's clear
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
			if entry != null and entry.kind == RewardEntry.CARD and entry.id != &"":
				var card: Resource = _registry.call(&"get_resource", &"spells", entry.id)
				check(ItemKinds.is_content(ItemKinds.CARD, card), "%s names the card '%s', which is one" % [table.id, entry.id])


func test_a_clear_has_its_table() -> void:
	check(_registry.call(&"get_resource", RewardsScript.TABLES, RewardsScript.CLEAR_TABLE) is RewardTable, "the clear's table is there")


func test_a_tables_problems_are_named() -> void:
	var table := RewardTable.new()
	check_equal(table.problems().size(), 2, "no id and no lines")
	table.id = &"bad"
	table.entries = [RewardEntry.make(&"gem"), RewardEntry.make(RewardEntry.COINS, &"bolt", 0, 0.0), null] as Array[RewardEntry]
	# The gem's kind; the coins' id, count and weight; the empty line.
	check_equal(table.problems().size(), 5, "every line's problems: %s" % [table.problems()])
