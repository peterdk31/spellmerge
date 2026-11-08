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
