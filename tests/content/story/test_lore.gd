extends "res://tests/support/suite.gd"
## The story validator (core/story/story_validator.gd) and the first lore: every spell component
## has a description that passes it, the registry hands the text out, and each kind of mistake in
## a lore file is reported with its rule, file, field and fix.
##
## godot --headless --path . --script res://tests/content/story/test_lore.gd

const RegistryScript := preload("res://core/registry/registry.gd")
const FILE: String = "res://content/story/lore/components/bolt.json"


func _registry() -> RegistryScript:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	return registry


func _good() -> Dictionary:
	return {"id": "bolt", "about": "component", "text": "A shot."}


func _rules(problems: Array[Dictionary]) -> Array[String]:
	var rules: Array[String] = []
	for problem in problems:
		rules.append(problem["rule"])
	return rules


func test_the_real_lore_has_no_problem() -> void:
	var problems: Array[Dictionary] = _registry().validate_story()
	var lines: Array[String] = []
	for problem in problems:
		# A component without lore only warns (see DECISIONS.md); a file that is wrong fails.
		if problem["rule"] != "missing-lore":
			lines.append(StoryValidator.format(problem))
	check_equal(lines, [] as Array[String], "every lore file is valid")


func test_the_components_that_ship_have_a_description_the_registry_gives() -> void:
	var registry: RegistryScript = _registry()
	for id in registry.get_ids(&"spells"):
		var text: String = registry.get_lore(&"component", id)
		check(text.length() <= StoryValidator.MAX_LORE_CHARS, "%s fits the limit" % id)
	for id: StringName in [&"bolt", &"fire", &"chain", &"beam", &"pierce", &"bigger"]:
		check(registry.get_lore(&"component", id) != "", "%s has a description" % id)
	check_equal(registry.get_lore(&"component", &"nothing_like_it"), "", "an unknown id has none")
	check_equal(registry.get_lore(&"relic", &"bolt"), "", "and an unknown kind has none")


func test_a_good_file_passes() -> void:
	check_equal(StoryValidator.check_lore(FILE, _good()).size(), 0, "no problem")


func test_a_file_that_is_not_an_object() -> void:
	check_equal(_rules(StoryValidator.check_lore(FILE, null)), ["not-an-object"] as Array[String], "null")
	check_equal(_rules(StoryValidator.check_lore(FILE, ["x"])), ["not-an-object"] as Array[String], "an array")


func test_a_missing_field_and_an_unknown_key() -> void:
	var data: Dictionary = _good()
	data.erase("text")
	data["mood"] = "dry"
	var rules: Array[String] = _rules(StoryValidator.check_lore(FILE, data))
	check(rules.has("missing-field"), "the missing text")
	check(rules.has("unknown-key"), "the unknown key")


func test_a_wrong_type() -> void:
	var data: Dictionary = _good()
	data["text"] = 5
	check_equal(_rules(StoryValidator.check_lore(FILE, data)), ["wrong-type"] as Array[String], "text must be a string")


func test_the_id_must_be_the_file_name() -> void:
	var data: Dictionary = _good()
	data["id"] = "beam"
	var problems: Array[Dictionary] = StoryValidator.check_lore(FILE, data)
	check_equal(_rules(problems), ["id-not-file"] as Array[String], "id and file differ")
	check(String(problems[0]["fix"]).contains("bolt"), "the fix names the file name")


func test_the_text_limits() -> void:
	var data: Dictionary = _good()
	data["text"] = "x".repeat(StoryValidator.MAX_LORE_CHARS)
	check_equal(StoryValidator.check_lore(FILE, data).size(), 0, "exactly the limit passes")
	data["text"] = "x".repeat(StoryValidator.MAX_LORE_CHARS + 1)
	check_equal(_rules(StoryValidator.check_lore(FILE, data)), ["text-too-long"] as Array[String], "one over fails")
	data["text"] = "   "
	check_equal(_rules(StoryValidator.check_lore(FILE, data)), ["empty-text"] as Array[String], "blank fails")
	data["text"] = "Two\nlines."
	check_equal(_rules(StoryValidator.check_lore(FILE, data)), ["text-not-a-line"] as Array[String], "a break fails")
	data["text"] = " padded"
	check_equal(_rules(StoryValidator.check_lore(FILE, data)), ["text-not-a-line"] as Array[String], "padding fails")


func test_an_unknown_about() -> void:
	var data: Dictionary = _good()
	data["about"] = "relic"
	check_equal(_rules(StoryValidator.check_lore(FILE, data)), ["unknown-about"] as Array[String], "only components for now")


func test_a_missing_file_and_a_duplicate_id() -> void:
	var entries: Dictionary = {
		"res://a/bolt.json": _good(),
		"res://b/bolt.json": _good(),
	}
	var ids: Array[StringName] = [&"bolt", &"beam"]
	var rules: Array[String] = _rules(StoryValidator.check_component_lore(entries, ids))
	check(rules.has("duplicate-id"), "bolt twice")
	check(rules.has("missing-lore"), "beam has none")


func test_the_limits_agree_with_the_story_canon() -> void:
	check_equal(StoryValidator.MAX_LORE_CHARS, 60, "a description is at most 60 characters")
	check_equal(StoryValidator.MAX_SPEECH_CHARS, 60, "a line of speech is at most 60")
