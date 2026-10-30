extends "res://tests/support/suite.gd"
## The spell content validator (core/spells/validator.gd): the real content has no problem,
## and each kind of component and the reaction table has a broken fixture that fails with the
## rule, file, field and fix. Also the registry's `validate_spells()` and its duplicate ids.
##
## godot --headless --path . --script res://tests/content/spells/test_validators.gd

const RegistryScript := preload("res://core/registry/registry.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const FIXTURES: String = "res://tests/content/spells/fixtures"
const DUPLICATES: String = "res://tests/content/spells/fixtures_duplicates"
const ICON: Texture2D = preload("res://content/spells/elements/fire/icon.svg")


func _manifest() -> Dictionary:
	return SpellValidator.load_manifest()


func _component(path: String) -> SpellComponent:
	return load(path) as SpellComponent


## The fields of the problems with this rule, in order.
func _fields(problems: Array[Dictionary], rule: String) -> Array[String]:
	var fields: Array[String] = []
	for problem in problems:
		if problem["rule"] == rule:
			fields.append(problem["field"])
	return fields


func _has_rule(problems: Array[Dictionary], rule: String) -> bool:
	return not _fields(problems, rule).is_empty()


func _registry() -> RegistryScript:
	return own(RegistryScript.new()) as RegistryScript


## A component that is fine, with a path whose folder is its id.
func _fine(component: SpellComponent) -> SpellComponent:
	component.id = &"fixture"
	component.display_name = "Fixture"
	component.icon = ICON
	component.take_over_path("res://x/fixture/fixture.tres")
	return component


func _listed() -> Dictionary:
	var listed: Dictionary = {}
	listed[ICON.resource_path.trim_prefix("res://")] = true
	return listed


func test_the_real_spell_content_has_no_problem() -> void:
	var registry := _registry()
	registry.scan()
	for problem in registry.validate_spells():
		check(false, SpellValidator.format(problem))


func test_the_real_reaction_table_names_only_real_elements_and_known_statuses() -> void:
	var registry := _registry()
	registry.scan()
	var table := load("res://content/spells/reactions.tres") as ReactionTable
	var elements: Array[StringName] = []
	for id in registry.get_ids(&"spells"):
		if registry.get_resource(&"spells", id) is ElementBase:
			elements.append(id)
	check_equal(elements.size(), 6, "the six elements are found")
	check_equal(SpellValidator.check_reactions(table, elements).size(), 0, "no reaction problem")


func test_the_known_statuses_are_the_ones_combat_reacts_to() -> void:
	var expected: Array[StringName] = []
	expected.assign(CombatScript.REACTING_STATUSES)
	check_equal(SpellValidator.KNOWN_STATUSES, expected, "the validator and combat list the same statuses")


func test_the_effect_range_covers_every_reaction_effect() -> void:
	var bounds: Vector2 = SpellValidator.REACTION_RANGES["effect"]
	check_equal(int(bounds.y), ReactionRow.Effect.size() - 1, "the last effect is the top of the range")


func test_a_problem_has_a_rule_a_file_a_field_and_a_fix() -> void:
	var form := _component(FIXTURES + "/form/broken_form.tres")
	var problems: Array[Dictionary] = SpellValidator.check_component(form, _manifest())
	check(not problems.is_empty(), "the broken form has problems")
	for problem in problems:
		for part: String in ["rule", "file", "field", "fix"]:
			check(String(problem.get(part, "")) != "", "%s is filled in" % part)
		check_equal(problem["file"], form.resource_path, "the problem names the file")
	check(SpellValidator.format(problems[0]).contains(form.resource_path), "the formatted line has the file")


func test_the_broken_form_fails() -> void:
	var problems := SpellValidator.check_component(_component(FIXTURES + "/form/broken_form.tres"), _manifest())
	check_equal(_fields(problems, "id-folder"), ["id"] as Array[String], "id differs from the folder")
	check(_fields(problems, "required-field").has("display_name"), "no name")
	check(_fields(problems, "required-field").has("speed"), "a straight form without speed")
	check_equal(_fields(problems, "icon"), ["icon"] as Array[String], "no icon")
	check_equal(_fields(problems, "range"), ["shots"] as Array[String], "too many shots")


func test_the_broken_element_fails() -> void:
	var problems := SpellValidator.check_component(_component(FIXTURES + "/element/broken_element.tres"), _manifest())
	check_equal(_fields(problems, "unknown-status"), ["status_id"] as Array[String], "an unknown status")
	check(_fields(problems, "required-field").has("status_duration"), "a status without duration")
	check(_fields(problems, "range").has("damage_scale"), "damage scale out of range")
	check(_fields(problems, "range").has("complexity"), "complexity out of range")


func test_the_broken_modifier_fails() -> void:
	var problems := SpellValidator.check_component(_component(FIXTURES + "/modifier/broken_modifier.tres"), _manifest())
	check(_fields(problems, "range").has("damage_mult"), "damage_mult out of range")
	check(_fields(problems, "range").has("behaviour"), "an unknown behaviour")
	check_equal(_fields(problems, "required-field").filter(func(f: String) -> bool: return f != "display_name"), ["behaviour_strength"] as Array[String], "a behaviour without strength")


func test_the_broken_trigger_fails() -> void:
	var problems := SpellValidator.check_component(_component(FIXTURES + "/trigger/broken_trigger.tres"), _manifest())
	check(_fields(problems, "range").has("event"), "an unknown event")
	check(not _has_rule(problems, "required-field"), "a trigger that is no timer needs no interval")


func test_a_timer_trigger_needs_an_interval() -> void:
	var trigger := _fine(TriggerBase.new()) as TriggerBase
	trigger.event = TriggerBase.Event.TIMER
	trigger.interval = 0.0
	check_equal(_fields(SpellValidator.check_component(trigger, _listed()), "required-field"), ["interval"] as Array[String], "a timer without interval")
	trigger.interval = 0.5
	check_equal(SpellValidator.check_component(trigger, _listed()).size(), 0, "a timer with an interval is fine")


func test_a_homing_or_chain_modifier_needs_strength() -> void:
	var modifier := _fine(ModifierBase.new()) as ModifierBase
	modifier.behaviour = ModifierBase.Behaviour.CHAIN
	check_equal(_fields(SpellValidator.check_component(modifier, _listed()), "required-field"), ["behaviour_strength"] as Array[String], "chain without jumps")
	modifier.behaviour_strength = 2.0
	check_equal(SpellValidator.check_component(modifier, _listed()).size(), 0, "chain with jumps is fine")


func test_a_homing_modifier_needs_a_reach() -> void:
	var modifier := _fine(ModifierBase.new()) as ModifierBase
	modifier.behaviour = ModifierBase.Behaviour.HOMING
	modifier.behaviour_strength = 3.0
	check_equal(_fields(SpellValidator.check_component(modifier, _listed()), "required-field"), ["behaviour_reach"] as Array[String], "homing that looks nowhere")
	modifier.behaviour_reach = 160.0
	check_equal(SpellValidator.check_component(modifier, _listed()).size(), 0, "homing with a reach is fine")


func test_the_broken_reaction_table_fails() -> void:
	var table := load(FIXTURES + "/reactions/broken_reactions.tres") as ReactionTable
	var elements: Array[StringName] = [&"fire", &"frost"]
	var problems := SpellValidator.check_reactions(table, elements)
	check_equal(_fields(problems, "reaction-element").size(), 1, "one row names an element that does not exist")
	check_equal(_fields(problems, "unknown-status").size(), 1, "one row names an unknown status")
	check_equal(_fields(problems, "unknown-effect").size(), 1, "one row has an unknown effect")
	check_equal(_fields(problems, "reaction-pair").size(), 1, "burn + frost is listed twice")
	check(_has_rule(problems, "range"), "damage 500 is out of range")
	check(_fields(problems, "required-field").size() >= 3, "a missing reaction id, a name and a radius")
	for problem in problems:
		check_equal(problem["file"], table.resource_path, "the problem names the table")


func test_a_form_needs_what_its_carrier_uses() -> void:
	var form := _fine(FormBase.new()) as FormBase
	form.carrier = &"atom"
	form.speed = 100.0
	check_equal(SpellValidator.check_component(form, _listed()).size(), 0, "a straight form with speed is fine")
	form.speed = 0.0
	check_equal(_fields(SpellValidator.check_component(form, _listed()), "required-field"), ["speed"] as Array[String], "straight needs speed")
	form.carrier = &"orbit"
	check_equal(_fields(SpellValidator.check_component(form, _listed()), "required-field"), ["orbit_radius"] as Array[String], "orbit needs a radius")
	form.carrier = &"beam"
	check_equal(_fields(SpellValidator.check_component(form, _listed()), "required-field"), ["ray_length"] as Array[String], "a ray needs a length")
	form.carrier = &"rune"
	check_equal(SpellValidator.check_component(form, _listed()).size(), 0, "a rune needs nothing more")


func test_a_form_that_names_no_carrier_is_refused() -> void:
	var form := _fine(FormBase.new()) as FormBase
	form.carrier = &"fissure"
	check(_has_rule(SpellValidator.check_component(form, _listed()), "unknown-carrier"), "a name no carrier has")
	# The carrier that runs nothing has the id &"", so an empty name once passed as its own.
	form.carrier = &""
	check(_has_rule(SpellValidator.check_component(form, _listed()), "unknown-carrier"), "an empty name")
	check(not form.range_problems().is_empty(), "and its ranges say so too")


func test_a_staff_pose_must_be_known_keys_in_order_and_in_range() -> void:
	var form := _fine(FormBase.new()) as FormBase
	form.carrier = &"rune"
	form.staff_pose = [{"phase": "wind", "at": 1.0, "lift": 10, "push": -5, "ease": "out", "mood": "angry"}, {"phase": "after", "at": 0.1}] as Array[Dictionary]
	check_equal(SpellValidator.check_component(form, _listed()).size(), 0, "two keys in order are fine")
	form.staff_pose = [{"phase": "later", "at": 0.1}] as Array[Dictionary]
	check(_has_rule(SpellValidator.check_component(form, _listed()), "pose"), "an unknown phase is reported")
	form.staff_pose = [{"phase": "after", "at": 0.1}, {"phase": "wind", "at": 1.0}] as Array[Dictionary]
	check(_has_rule(SpellValidator.check_component(form, _listed()), "pose"), "a key before the one before it is reported")
	form.staff_pose = [{"phase": "after", "at": 0.1, "glow": 2.0}] as Array[Dictionary]
	check(_has_rule(SpellValidator.check_component(form, _listed()), "pose"), "a glow above 1 is reported")
	form.staff_pose = [{"phase": "after", "at": 0.1, "wobble": 1.0}] as Array[Dictionary]
	check(_has_rule(SpellValidator.check_component(form, _listed()), "pose"), "an unknown channel is reported")
	form.staff_pose = [{"phase": "after", "at": 0.1, "mood": "sleepy"}] as Array[Dictionary]
	check(_has_rule(SpellValidator.check_component(form, _listed()), "pose"), "an unknown mood is reported")


func test_an_icon_missing_from_the_manifest_is_reported() -> void:
	var element := _component("res://content/spells/elements/fire/fire.tres")
	check_equal(SpellValidator.check_component(element, _manifest()).size(), 0, "fire is fine with the real manifest")
	var problems := SpellValidator.check_component(element, {})
	check_equal(_fields(problems, "icon-manifest"), ["icon"] as Array[String], "an empty manifest lists no icon")
	check(String(problems[0]["fix"]).contains("assets.json"), "the fix names the assets file")


func test_complexity_above_the_whole_spell_budget_is_reported_once_as_a_range() -> void:
	var element := _fine(ElementBase.new())
	element.complexity = SpellComponent.COMPLEXITY_MAX + 1
	var problems := SpellValidator.check_component(element, _listed())
	check_equal(_fields(problems, "range"), ["complexity"] as Array[String], "one range problem")
	check_equal(problems.size(), 1, "and no second one")


func test_an_assets_file_in_a_content_folder_is_read() -> void:
	var listed: Dictionary = SpellValidator.load_manifest("res://tests/content/spells/no_such_manifest.json", ["res://tests/content/spells/fixtures_assets"] as Array[String])
	check(listed.has("content/spells/forms/fixture_only/icon.svg"), "an assets.json two folders down is read")
	check(SpellValidator.load_manifest().has("art/vfx/hit_spark.svg"), "the art manifest is still read")


func test_a_missing_manifest_is_empty() -> void:
	check(SpellValidator.load_manifest("res://tests/content/spells/no_such_manifest.json", [] as Array[String]).is_empty(), "empty")


func test_the_registry_warns_once_per_problem() -> void:
	var registry := _registry()
	registry.scan(DUPLICATES, "res://tests/content/spells/no_audio")
	var expected: int = registry.validate_spells().size()
	check(expected > 0, "the duplicate fixture has a problem")
	check_equal(registry.warn_spell_problems(), expected, "one warning per problem")


func test_an_id_used_twice_is_reported() -> void:
	var fire := _component("res://content/spells/elements/fire/fire.tres")
	var components: Array[SpellComponent] = [fire, fire]
	var problems := SpellValidator.check_components(components, _manifest())
	check_equal(_fields(problems, "unique-id"), ["id"] as Array[String], "the second fire is a duplicate")


func test_the_registry_reports_a_duplicate_id_across_kinds() -> void:
	var registry := _registry()
	registry.scan(DUPLICATES, "res://tests/content/spells/no_audio")
	var problems: Array[Dictionary] = registry.validate_spells()
	check_equal(_fields(problems, "unique-id").size(), 1, "one id is used by a form and an element")
	var fix: String = ""
	for problem in problems:
		if problem["rule"] == "unique-id":
			fix = problem["fix"]
	check(fix.contains("twin"), "the fix names the id")


func test_a_scan_without_a_reaction_table_checks_only_the_components() -> void:
	var registry := _registry()
	registry.scan(DUPLICATES, "res://tests/content/spells/no_audio")
	for problem in registry.validate_spells():
		check(not String(problem["file"]).ends_with("reactions.tres"), "no problem from a table that is not there")


func test_non_component_resources_in_spells_are_skipped() -> void:
	var resources: Array[Resource] = [Resource.new(), _component("res://content/spells/elements/fire/fire.tres")]
	check_equal(SpellValidator.check_all(resources, null, _manifest()).size(), 0, "a plain resource is not a component")
