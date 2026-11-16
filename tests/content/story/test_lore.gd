extends "res://tests/support/suite.gd"
## The story validator (core/story/story_validator.gd) and the cards' descriptions: every spell
## component carries its own one-line description (`SpellComponent.description`, in its `.tres`),
## `Spells` hands the text out, and each kind of mistake is reported with its rule, file, field
## and fix.
##
## godot --headless --path . --script res://tests/support/run.gd -- res://tests/content/story/test_lore.gd
const RegistryScript := preload("res://core/registry/registry.gd")
const FILE: String = "res://content/spells/carriers/bolt/bolt.tres"


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
	var card := CarrierCard.new()
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
	check_equal(lines, [] as Array[String], "every description and line of lore is valid")


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
	check_equal(SpellValidator.check_descriptions([_card("A shot.")] as Array[SpellComponent]).size(), 0, "no problem")


func test_a_missing_description_is_named() -> void:
	var problems: Array[Dictionary] = SpellValidator.check_descriptions([_card("")] as Array[SpellComponent])
	check_equal(_rules(problems), ["missing-lore"] as Array[String], "none")
	check_equal(str(problems[0]["field"]), "description", "on its field")


func test_the_text_limits() -> void:
	check_equal(StoryValidator.check_line(FILE, "description", "x".repeat(StoryValidator.MAX_LORE_CHARS)).size(), 0, "exactly the limit passes")
	check_equal(_rules(StoryValidator.check_line(FILE, "description", "x".repeat(StoryValidator.MAX_LORE_CHARS + 1))), ["text-too-long"] as Array[String], "one over fails")
	check_equal(_rules(StoryValidator.check_line(FILE, "description", "   ")), ["empty-text"] as Array[String], "blank fails")
	check_equal(_rules(StoryValidator.check_line(FILE, "description", "Two\nlines.")), ["text-not-a-line"] as Array[String], "a break fails")
	check_equal(_rules(StoryValidator.check_line(FILE, "description", " padded")), ["text-not-a-line"] as Array[String], "padding fails")


func test_an_enemys_lore() -> void:
	# Boss OB3: `EnemyBase.lore`, a boss's line of why it fights; a stray needs none.
	const ENEMY: String = "res://content/bosses/some_boss/some_boss.tres"
	check_equal(StoryValidator.check_lore(ENEMY, "", false).size(), 0, "a stray without lore is fine")
	check_equal(_rules(StoryValidator.check_lore(ENEMY, "", true)), ["missing-lore"] as Array[String], "a boss without lore only warns")
	check_equal(StoryValidator.check_lore(ENEMY, "Swept up, and sour about it.", true).size(), 0, "a short line passes")
	var long: Array[Dictionary] = StoryValidator.check_lore(ENEMY, "x".repeat(StoryValidator.MAX_LORE_CHARS + 1), false)
	check_equal(_rules(long), ["text-too-long"] as Array[String], "a stray's lore keeps the limit too")
	check(long.size() == 1 and str(long[0]["field"]) == "lore" and str(long[0]["file"]) == ENEMY, "named by its file and field")


func test_the_story_check_reads_every_enemys_lore() -> void:
	# Each enemy and boss the registry holds, in turn, given a line too long: the story check
	# names it by its file and field. Its own line is put back after.
	var registry: RegistryScript = _registry()
	var checked: int = 0
	for folder: StringName in EnemyBase.FOLDERS:
		for res: Resource in registry.get_all(folder):
			var enemy := res as EnemyBase
			if enemy == null:
				continue
			var kept: String = enemy.lore
			enemy.lore = "x".repeat(StoryValidator.MAX_LORE_CHARS + 1)
			var named: bool = false
			for problem: Dictionary in registry.validate_story():
				if problem["rule"] == "text-too-long" and problem["file"] == enemy.resource_path and problem["field"] == "lore":
					named = true
			enemy.lore = kept
			check(named, "%s: a line too long is named" % enemy.id)
			checked += 1
	check(checked > 0, "the enemies are found")


func test_the_limits_agree_with_the_story_canon() -> void:
	check_equal(StoryValidator.MAX_LORE_CHARS, 60, "a description is at most 60 characters")
	check_equal(StoryValidator.MAX_SPEECH_CHARS, 60, "a line of speech is at most 60")


## What a boss says in its intro is speech (docs/milestones/boss-intro.md, rule 1; docs/STORY.md):
## one line each of at most MAX_SPEECH_CHARS, at most `BossIntro.MAX_LINES` of them.
func test_a_boss_intros_lines_are_held_to_the_speech_rule() -> void:
	var file: String = "res://content/bosses/test/test.tres"
	check_equal(StoryValidator.check_speech(file, ["What an awful smell of The Wizard.", "I must clean it up."] as Array[String]), [] as Array[Dictionary], "two short lines: fine")
	check_equal(StoryValidator.check_speech(file, [] as Array[String]), [] as Array[Dictionary], "no lines: fine")
	check_equal(_rules(StoryValidator.check_speech(file, ["One.", "Two.", "Three.", "Four."] as Array[String])), ["too-many-lines"] as Array[String], "four lines")
	var long: String = "x".repeat(StoryValidator.MAX_SPEECH_CHARS + 1)
	var problems: Array[Dictionary] = StoryValidator.check_speech(file, ["Fine.", long] as Array[String])
	check_equal(_rules(problems), ["speech-too-long"] as Array[String], "a line too long")
	check_equal(problems[0]["field"] if not problems.is_empty() else "", "boss_intro.lines[1]", "named by its number")
	check_equal(_rules(StoryValidator.check_speech(file, ["  "] as Array[String])), ["empty-text"] as Array[String], "an empty line")
	check_equal(_rules(StoryValidator.check_speech(file, [" Spaced."] as Array[String])), ["text-not-a-line"] as Array[String], "spaces at an end")


## The story check reads every boss's intro: a boss's line too long is found in the game's words.
func test_the_story_check_reads_a_boss_intros_lines() -> void:
	var registry: RegistryScript = _registry()
	var data := EnemyBase.new()
	data.id = &"test_speaking_boss"
	data.boss = true
	data.lore = "It was made for this test."
	data.boss_intro = BossIntro.new()
	data.boss_intro.lines = ["x".repeat(StoryValidator.MAX_SPEECH_CHARS + 1)] as Array[String]
	registry.add(&"bosses", data)
	check(_rules(registry.validate_story()).has("speech-too-long"), "its line is checked")
