extends "res://tests/support/suite.gd"
## Tests for the M2 spell component base classes in core/base: the four kinds, their
## ranges and range problems, and the reaction table (found by pair, never registered as
## content).
##
## godot --headless --path . --script res://tests/core/test_spell_components.gd

const RegistryScript := preload("res://core/registry/registry.gd")
const FIXTURE: String = "res://tests/core/fixtures/spell_components"


func _components() -> Array[SpellComponent]:
	var all: Array[SpellComponent] = [FormBase.new(), ElementBase.new(), ModifierBase.new(), TriggerBase.new()]
	return all


func test_each_class_names_its_own_kind() -> void:
	var kinds: Array[StringName] = []
	for component in _components():
		kinds.append(component.kind())
	var expected: Array[StringName] = [&"form", &"element", &"modifier", &"trigger"]
	check_equal(kinds, expected, "the four classes report form, element, modifier and trigger")


func test_new_components_are_in_range() -> void:
	for component in _components():
		check_equal(component.range_problems(), PackedStringArray(), "%s defaults are in range" % component.kind())


func test_every_range_names_a_real_field() -> void:
	for component in _components():
		for field: String in component.ranges():
			check(field in component, "%s has the field %s" % [component.kind(), field])


func test_every_kind_checks_complexity() -> void:
	for component in _components():
		component.complexity = SpellComponent.COMPLEXITY_MAX + 1
		var problems: PackedStringArray = component.range_problems()
		check(problems.size() == 1 and problems[0].begins_with("complexity:"), "%s reports a complexity over the maximum" % component.kind())


func test_an_out_of_range_field_is_named() -> void:
	var form := FormBase.new()
	form.shots = 0
	form.wind_down = 99.0
	var problems: PackedStringArray = form.range_problems()
	check_equal(problems.size(), 2, "two fields out of range give two problems")
	var text: String = " ".join(problems)
	check(text.contains("shots:") and text.contains("wind_down:"), "each problem names its field")


func test_enum_fields_are_range_checked() -> void:
	var trigger := TriggerBase.new()
	trigger.set("event", TriggerBase.Event.size())
	check(" ".join(trigger.range_problems()).contains("event:"), "an unknown trigger event is reported")


func test_reaction_table_finds_a_pair_in_order() -> void:
	var table := ReactionTable.new()
	var row := ReactionRow.new()
	row.reaction_id = &"shatter"
	row.status_id = &"chill"
	row.element_id = &"storm"
	table.rows.append(row)
	check(table.find(&"chill", &"storm") == row, "chill hit by storm finds shatter")
	check(table.find(&"shock", &"frost") == null, "the reverse pair is a different reaction")
	check(table.find(&"burn", &"void") == null, "a pair with no row gives null")


## The table is searched by an index (performance, 2026-11-02): a row added after a search, or
## another array of rows, is still found, and the first row of a pair wins, as a walk of the rows did.
func test_reaction_table_index_follows_its_rows() -> void:
	var table := ReactionTable.new()
	check(table.for_element(&"storm").is_empty(), "an empty table: no reactions")
	var first := ReactionRow.new()
	first.status_id = &"chill"
	first.element_id = &"storm"
	table.rows.append(first)
	check(table.find(&"chill", &"storm") == first, "found")
	var later := ReactionRow.new()
	later.status_id = &"burn"
	later.element_id = &"storm"
	table.rows.append(later)
	check(table.find(&"burn", &"storm") == later, "a row added after a search is found")
	var twin := ReactionRow.new()
	twin.status_id = &"chill"
	twin.element_id = &"storm"
	table.rows.append(twin)
	check(table.find(&"chill", &"storm") == first, "the first row of a pair wins")
	check_equal(table.for_element(&"storm").size(), 2, "the element's rows by status")
	var other := ReactionRow.new()
	other.status_id = &"hex"
	other.element_id = &"fire"
	var rows: Array[ReactionRow] = [other, null, first]
	table.rows = rows
	check(table.find(&"hex", &"fire") == other, "another array of rows is searched")
	check(table.find(&"burn", &"storm") == null, "and only it")


## `in_order` (what Combat looks a hit's reaction up by, shot scale H3) lines an element's rows up
## with the statuses it is given, and follows the rows as the index does.
func test_reaction_table_in_order_follows_its_rows() -> void:
	var table := ReactionTable.new()
	var order: Array[StringName] = [&"burn", &"chill", &"shock"]
	check(table.in_order(&"storm", order).is_empty(), "an empty table: none")
	var chill := ReactionRow.new()
	chill.status_id = &"chill"
	chill.element_id = &"storm"
	table.rows.append(chill)
	check_equal(table.in_order(&"storm", order), [null, chill, null] as Array[ReactionRow], "lined up with the statuses")
	var burn := ReactionRow.new()
	burn.status_id = &"burn"
	burn.element_id = &"storm"
	table.rows.append(burn)
	check_equal(table.in_order(&"storm", order), [burn, chill, null] as Array[ReactionRow], "a row added after a search is in")
	var other_order: Array[StringName] = [&"chill", &"burn"]
	check_equal(table.in_order(&"storm", other_order), [chill, burn] as Array[ReactionRow], "another order")
	var rows: Array[ReactionRow] = [burn]
	table.rows = rows
	check_equal(table.in_order(&"storm", order), [burn, null, null] as Array[ReactionRow], "a row taken out is gone")
	check(table.in_order(&"fire", order).is_empty(), "an element with no rows: none")


func test_registry_finds_components_but_not_the_reaction_table() -> void:
	var registry: RegistryScript = own(RegistryScript.new()) as RegistryScript
	registry.scan(FIXTURE.path_join("content"), FIXTURE.path_join("audio"))
	var frost: ElementBase = registry.get_resource(&"spells", &"frost") as ElementBase
	check(frost != null, "the frost element is found by id")
	if frost != null:
		check_equal(frost.status_id, &"chill", "the element's data is loaded")
	var ids: Array[StringName] = [&"frost"]
	check_equal(registry.get_ids(&"spells"), ids, "the reaction table is not registered as content")


func test_reaction_table_resource_loads_its_rows() -> void:
	var table: ReactionTable = load(FIXTURE.path_join("content/spells/reactions.tres")) as ReactionTable
	check(table != null, "the fixture table loads")
	if table != null:
		var row: ReactionRow = table.find(&"chill", &"storm")
		check(row != null and row.effect == ReactionRow.Effect.CONSUME, "the shatter row consumes")
