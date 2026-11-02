extends "res://tests/support/suite.gd"
## Every carrier card brings its looks (content/spells/forms/, `FormBase.cast_look` and
## `impact_look`): both are given, only with keys something reads, and every cue they name is a
## cue file (content/cues/). A card's `shot_body` is compiled into its shots' body.
##
## godot --headless --path . --script res://tests/content/spells/test_carrier_looks.gd

const RegistryScript := preload("res://core/registry/registry.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

var registry: RegistryScript


func before_each() -> void:
	registry = own(RegistryScript.new()) as RegistryScript
	registry.scan()


func _forms() -> Array[FormBase]:
	var found: Array[FormBase] = []
	for card: Resource in registry.get_all(&"spells"):
		if card is FormBase:
			found.append(card as FormBase)
	return found


func test_every_carrier_card_has_both_looks() -> void:
	var forms: Array[FormBase] = _forms()
	check(forms.size() >= 15, "the carrier cards are found: %d" % forms.size())
	for form: FormBase in forms:
		check(not form.cast_look.is_empty(), "%s has a cast look" % form.id)
		check(not form.impact_look.is_empty(), "%s has an impact look" % form.id)
		check_equal(form.look_problems(), PackedStringArray(), "%s's looks have only keys something reads" % form.id)


func test_every_cue_a_card_names_is_a_cue() -> void:
	for form: FormBase in _forms():
		for look: Dictionary in [form.cast_look, form.impact_look]:
			if look.has("cue"):
				check(registry.get_resource(&"cues", look["cue"]) is CueBase, "%s names the cue %s, which is in content/cues" % [form.id, look["cue"]])


func test_the_moments_have_their_cues() -> void:
	var cues: Dictionary = {
		[&"teleport", true]: &"vanish", [&"teleport", false]: &"appear", [&"swap", true]: &"trade",
		[&"rain", true]: &"telegraph", [&"rain", false]: &"rainfall", [&"nova", true]: &"nova",
		[&"slam", false]: &"slam", [&"decoy", true]: &"conjure", [&"decoy", false]: &"dismiss",
		[&"familiar", true]: &"conjure", [&"familiar", false]: &"dismiss",
	}
	for key: Array in cues:
		var form: FormBase = registry.get_resource(&"spells", key[0]) as FormBase
		var look: Dictionary = form.cast_look if key[1] else form.impact_look
		check_equal(look.get("cue"), cues[key], "%s's %s look plays %s" % [key[0], "cast" if key[1] else "impact", cues[key]])


func test_a_look_key_nothing_reads_is_reported() -> void:
	var form := FormBase.new()
	form.id = &"test_form"
	form.cast_look = {"size": 0.5, "stretch": 2.0}
	form.impact_look = {"cue": "quake"}
	form.shot_body = &"crystal"
	var found: PackedStringArray = form.look_problems()
	check_equal(found.size(), 3, "three problems: %s" % [found])
	check(" ".join(found).contains("stretch"), "a key nothing reads")
	check(" ".join(found).contains("cue should be a cue id"), "a cue that is a string, not a name")
	check(" ".join(found).contains("crystal"), "a body that is none")


func test_a_wall_is_built_of_stones() -> void:
	var spells: SpellsScript = own(SpellsScript.new()) as SpellsScript
	spells.registry = registry
	var staff := StaffBase.new()
	staff.id = &"test"
	staff.slots = 4
	var wall: CompiledSpell = spells.compile_staff([&"wall"] as Array[StringName], staff).casts[0].group.spells[0]
	var bolt: CompiledSpell = spells.compile_staff([&"bolt"] as Array[StringName], staff).casts[0].group.spells[0]
	check_equal(wall.body, ProjectilesScript.KIND_STONE, "a wall's shots are stones")
	check_equal(bolt.body, 0, "a bolt's the body of their motion")
