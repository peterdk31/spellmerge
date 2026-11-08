extends "res://tests/support/suite.gd"
## Every carrier card names its looks as cues (content/spells/forms/, `FormBase.cast_cue`,
## `shown_cue`, `impact_cue` and `end_cue`; S6 2): every cue it names is a cue file (content/cues/),
## and its looks have no problems. Which cue each card's moments play, and a wall's stones, are in
## each card's own test (content/spells/forms/<id>/test_<id>.gd).
##
## godot --headless --path . --script res://tests/content/spells/test_carrier_looks.gd

const RegistryScript := preload("res://core/registry/registry.gd")

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


func test_a_look_shader_that_is_not_canvas_item_is_reported() -> void:
	var form := FormBase.new()
	form.id = &"test_form"
	var spatial := Shader.new()
	spatial.code = "shader_type spatial;\nvoid fragment() {}\n"
	form.look_shader = spatial
	var found: PackedStringArray = form.look_problems()
	check_equal(found.size(), 1, "one problem: %s" % [found])
	check(" ".join(found).contains("canvas_item"), "a shot shader that is no canvas-item shader")
	form.look_shader = preload("res://content/spells/forms/pool/pool.gdshader")
	check(form.look_problems().is_empty(), "a card's own canvas-item shader is fine")


## `shot_shader` was renamed `look_shader` (docs/milestones/card-looks.md): a card written with the
## old name keeps its look (it is taken as `look_shader`) and the validator names it, so it never
## loads clean and draws plain in silence.
func test_a_card_with_the_old_shot_shader_name_keeps_its_look_and_is_reported() -> void:
	var text: String = FileAccess.get_file_as_string("res://content/spells/forms/pool/pool.tres").replace("look_shader = ", "shot_shader = ")
	check(text.contains("shot_shader = "), "the pool card, written with the old name")
	var path: String = "user://test_old_shot_shader.tres"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var form: FormBase = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as FormBase
	DirAccess.remove_absolute(path)
	check(form != null, "it loads")
	if form == null:
		return
	check(form.look_shader == preload("res://content/spells/forms/pool/pool.gdshader"), "its shader is kept, as its look_shader")
	var found: PackedStringArray = form.look_problems()
	check_equal(found.size(), 1, "one problem: %s" % [found])
	check(" ".join(found).contains("renamed `look_shader`"), "it names the rename")


## A card's light (card-looks phase 1b): the atom lights less, and less far, than the bolt, and its
## compiled spell carries that to its shots (`Projectiles.set_looks`).
func test_the_atom_lights_less_than_the_bolt() -> void:
	var atom: FormBase = load("res://content/spells/forms/atom/atom.tres") as FormBase
	var bolt: FormBase = load("res://content/spells/forms/bolt/bolt.tres") as FormBase
	check(atom.look_light_intensity < bolt.look_light_intensity, "dimmer: %s against %s" % [atom.look_light_intensity, bolt.look_light_intensity])
	check(atom.look_light_reach < bolt.look_light_reach, "and nearer: %s against %s" % [atom.look_light_reach, bolt.look_light_reach])
	var registry := own(preload("res://core/registry/registry.gd").new()) as Node
	registry.call("scan")
	var spells := own(preload("res://core/spells/spells.gd").new()) as Node
	spells.set(&"registry", registry)
	var staff := StaffBase.new()
	staff.id = &"test"
	staff.slots = 4
	var spell: CompiledSpell = (spells.call(&"compile_staff", [&"atom"] as Array[StringName], staff) as CompiledStaff).casts[0].group.spells[0]
	check(is_equal_approx(spell.look_light_intensity, atom.look_light_intensity) and is_equal_approx(spell.look_light_reach, atom.look_light_reach), "its compiled spell carries its light")


## Out of range, the light is a range problem the validator names.
func test_a_light_out_of_range_is_reported() -> void:
	var form := FormBase.new()
	form.id = &"test_form"
	form.look_light_intensity = 3.0
	form.look_light_reach = 0.1
	var found: String = " ".join(form.range_problems())
	check(found.contains("look_light_intensity") and found.contains("look_light_reach"), "both named: %s" % found)


## Spells answers a card's look for the area that draws its carrier (card-looks phases 2 and 3):
## the beam card's shader to Feel's beams, nothing to another area, and nothing for an id that is
## no carrier card; its light likewise (1 elsewhere).
func test_spells_answers_a_cards_look_for_its_own_area() -> void:
	var registry := own(preload("res://core/registry/registry.gd").new()) as Node
	registry.call("scan")
	var spells := own(preload("res://core/spells/spells.gd").new()) as Node
	spells.set(&"registry", registry)
	var beam: Shader = preload("res://content/spells/forms/beam/beam.gdshader")
	check(spells.call(&"look_shader_of", &"beam", Carrier.LOOK_BEAM) == beam, "the beam card's shader, to the beams")
	check(spells.call(&"look_shader_of", &"beam", Carrier.LOOK_SWING) == null, "not to the swing trails")
	check(spells.call(&"look_shader_of", &"bolt", Carrier.LOOK_BEAM) == null, "a bolt's ray is no beam card's: plain")
	check(spells.call(&"look_shader_of", &"no_such_card", Carrier.LOOK_BEAM) == null, "no card: plain")
	check(spells.call(&"look_shader_of", &"swing", Carrier.LOOK_SWING) == preload("res://content/spells/forms/swing/swing.gdshader"), "the swing card's, to the trails")
	check(is_equal_approx(float(spells.call(&"look_light_intensity_of", &"atom", Carrier.LOOK_SHOT)), 0.5), "the atom's light, for shots")
	check(is_equal_approx(float(spells.call(&"look_light_intensity_of", &"atom", Carrier.LOOK_BEAM)), 1.0), "and 1 to another area")
	check(is_equal_approx(float(spells.call(&"look_light_reach_of", &"no_such_card", Carrier.LOOK_BEAM)), 1.0), "1 for no card")
