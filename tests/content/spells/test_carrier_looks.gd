extends "res://tests/support/suite.gd"
## Every carrier card names its looks as cues (content/spells/forms/, `FormBase.cast_cue`,
## `shown_cue`, `impact_cue` and `end_cue`; S6 2): every cue it names is a cue file (content/cues/),
## and each moment plays the cue it should. A card's `shot_body` is compiled into its shots' body.
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


## The cues `form` names, by moment.
func _cues_of(form: FormBase) -> Dictionary:
	return {&"cast": form.cast_cue, &"shown": form.shown_cue, &"impact": form.impact_cue, &"end": form.end_cue}


func test_every_carrier_card_casts_and_lands_in_a_cue() -> void:
	var forms: Array[FormBase] = _forms()
	check(forms.size() >= 15, "the carrier cards are found: %d" % forms.size())
	for form: FormBase in forms:
		check(form.cast_cue != &"", "%s has a cast cue" % form.id)
		check(form.impact_cue != &"", "%s has an impact cue" % form.id)
		check_equal(form.look_problems(), PackedStringArray(), "%s's looks have no problems" % form.id)


func test_every_cue_a_card_names_is_a_cue() -> void:
	for form: FormBase in _forms():
		var cues: Dictionary = _cues_of(form)
		for moment: StringName in cues:
			var id: StringName = cues[moment]
			if id != &"":
				check(registry.get_resource(&"cues", id) is CueBase, "%s's %s cue %s is in content/cues" % [form.id, moment, id])


func test_the_moments_have_their_cues() -> void:
	var want: Dictionary = {
		[&"teleport", &"shown"]: &"vanish", [&"teleport", &"end"]: &"appear", [&"swap", &"shown"]: &"trade",
		[&"rain", &"shown"]: &"telegraph", [&"rain", &"end"]: &"rainfall", [&"nova", &"shown"]: &"nova",
		[&"slam", &"end"]: &"slam", [&"decoy", &"shown"]: &"conjure", [&"decoy", &"end"]: &"dismiss",
		[&"familiar", &"shown"]: &"conjure", [&"familiar", &"end"]: &"dismiss",
		[&"rune", &"impact"]: &"rune_burst", [&"nova", &"impact"]: &"impact_ring", [&"bolt", &"impact"]: &"impact",
		[&"nova", &"cast"]: &"cast_nova", [&"rune", &"cast"]: &"cast_rune", [&"orbit", &"cast"]: &"cast_orbit",
		[&"decoy", &"cast"]: &"cast",
	}
	for key: Array in want:
		var form: FormBase = registry.get_resource(&"spells", key[0]) as FormBase
		check_equal(_cues_of(form)[key[1]], want[key], "%s's %s plays %s" % [key[0], key[1], want[key]])


func test_a_body_that_is_none_is_reported() -> void:
	var form := FormBase.new()
	form.id = &"test_form"
	form.shot_body = &"crystal"
	var found: PackedStringArray = form.look_problems()
	check_equal(found.size(), 1, "one problem: %s" % [found])
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
