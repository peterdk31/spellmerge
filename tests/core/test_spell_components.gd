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
	form.cooldown = 99.0
	var problems: PackedStringArray = form.range_problems()
	check_equal(problems.size(), 2, "two fields out of range give two problems")
	var text: String = " ".join(problems)
	check(text.contains("shots:") and text.contains("cooldown:"), "each problem names its field")


func test_enum_fields_are_range_checked() -> void:
	var trigger := TriggerBase.new()
	trigger.set("event", 7)
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
