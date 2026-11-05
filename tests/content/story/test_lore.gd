extends "res://tests/support/suite.gd"
## The story validator (core/story/story_validator.gd) and the cards' descriptions: every spell
## component carries its own one-line description (`SpellComponent.description`, in its `.tres`),
## `Spells` hands the text out, and each kind of mistake is reported with its rule, file, field
## and fix.
##
## godot --headless --path . --script res://tests/content/story/test_lore.gd

const RegistryScript := preload("res://core/registry/registry.gd")
const FILE: String = "res://content/spells/forms/bolt/bolt.tres"


func _registry() -> RegistryScript:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	return registry


func _rules(problems: Array[Dictionary]) -> Array[String]:
	var rules: Array[String] = []
	for problem in problems:
		rules.append(problem["rule"])
	return rules


func _card(text: String) -> SpellComponent:
	var card := FormBase.new()
	card.id = &"bolt"
	card.description = text
	return card


func test_the_real_descriptions_have_no_problem() -> void:
	var problems: Array[Dictionary] = _registry().validate_story()
	var lines: Array[String] = []
	for problem in problems:
		# A component without a description only warns (see DECISIONS.md); a wrong one fails.
		if problem["rule"] != "missing-lore":
			lines.append(StoryValidator.format(problem))
	check_equal(lines, [] as Array[String], "every description is valid")


func test_the_components_that_ship_have_a_description() -> void:
	var registry: RegistryScript = _registry()
	var spells: Node = own(load("res://core/spells/spells.gd").new()) as Node
	spells.set(&"registry", registry)
	for id in registry.get_ids(&"spells"):
		var text: String = spells.call(&"component_description", id)
		check(text.length() <= StoryValidator.MAX_LORE_CHARS, "%s fits the limit" % id)
	for id: StringName in [&"bolt", &"fire", &"chain", &"beam", &"pierce", &"bigger"]:
		check(String(spells.call(&"component_description", id)) != "", "%s has a description" % id)
	check_equal(String(spells.call(&"component_description", &"nothing_like_it")), "", "an unknown id has none")


func test_a_good_description_passes() -> void:
	check_equal(StoryValidator.check_descriptions([_card("A shot.")] as Array[SpellComponent]).size(), 0, "no problem")


func test_a_missing_description_is_named() -> void:
	var problems: Array[Dictionary] = StoryValidator.check_descriptions([_card("")] as Array[SpellComponent])
	check_equal(_rules(problems), ["missing-lore"] as Array[String], "none")
	check_equal(str(problems[0]["field"]), "description", "on its field")


func test_the_text_limits() -> void:
	check_equal(StoryValidator.check_line(FILE, "description", "x".repeat(StoryValidator.MAX_LORE_CHARS)).size(), 0, "exactly the limit passes")
	check_equal(_rules(StoryValidator.check_line(FILE, "description", "x".repeat(StoryValidator.MAX_LORE_CHARS + 1))), ["text-too-long"] as Array[String], "one over fails")
	check_equal(_rules(StoryValidator.check_line(FILE, "description", "   ")), ["empty-text"] as Array[String], "blank fails")
	check_equal(_rules(StoryValidator.check_line(FILE, "description", "Two\nlines.")), ["text-not-a-line"] as Array[String], "a break fails")
	check_equal(_rules(StoryValidator.check_line(FILE, "description", " padded")), ["text-not-a-line"] as Array[String], "padding fails")


func test_the_limits_agree_with_the_story_canon() -> void:
	check_equal(StoryValidator.MAX_LORE_CHARS, 60, "a description is at most 60 characters")
	check_equal(StoryValidator.MAX_SPEECH_CHARS, 60, "a line of speech is at most 60")
