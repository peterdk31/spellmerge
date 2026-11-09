extends "res://tests/support/suite.gd"
## The shots' looks by name (`core/base/look_names.gd`; owner, 2026-11-09: names, not numbers): the
## table matches the projectile manager's LOOK_* kinds number for number, every card and mote or
## mark kind names a look that exists, and a name that is no look is a problem the validator names.
##
## godot --headless --path . --script res://tests/core/test_look_names.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SPELLS: String = "res://content/spells"


func test_the_names_are_the_managers_kinds() -> void:
	var constants: Dictionary = (ManagerScript as Script).get_script_constant_map()
	check_equal(LookNames.NAMES.size(), ManagerScript.LOOK_COUNT, "a name for every kind the shaders draw")
	for n in range(1, LookNames.NAMES.size()):
		var key: String = "LOOK_" + String(LookNames.NAMES[n]).to_upper()
		check_equal(int(constants.get(key, -1)), n, "%s is LOOK_* kind %d" % [LookNames.NAMES[n], n])
	check_equal(LookNames.NAMES[0], &"plain", "0 is a shot with no look")


func test_names_and_numbers_go_both_ways() -> void:
	for n in LookNames.NAMES.size():
		check_equal(LookNames.layer_of(LookNames.name_of(n)), n, "number %d" % n)
	check_equal(LookNames.layer_of(&""), 0, "no name, no look")
	check_equal(LookNames.layer_of(&"nonsense"), 0, "an unknown name is no look")
	check(not LookNames.known(&"nonsense") and LookNames.known(&"plain"), "known tells them apart")
	check_equal(LookNames.layers_of([&"plain", &"sparks"] as Array[StringName]), PackedInt32Array([0, 5]), "a list of names")
	check_equal(LookNames.names_of(PackedInt32Array([2, 17])), [&"flecks", &"curl"] as Array[StringName], "and back")


func test_a_card_reads_its_number_from_its_name() -> void:
	var card := ModifierBase.new()
	card.look_id = &"curl"
	check_equal(card.look_layer, ManagerScript.LOOK_CURL, "curl is the engine's curl")
	card.look_layer = ManagerScript.LOOK_EMBERS
	check_equal(card.look_id, &"embers", "setting the number names it")
	card.look_id = &"nonsense"
	check(", ".join(card.range_problems()).contains("look_id: nonsense is not a look"), "an unknown name is a problem: %s" % [card.range_problems()])
	var element := ElementBase.new()
	element.look_id = &"nonsense"
	check(", ".join(element.range_problems()).contains("look_id"), "on an infusion too")


func test_every_card_names_a_look_that_exists() -> void:
	var seen: int = 0
	for path: String in _files(SPELLS, ".tres"):
		var card: Resource = load(path)
		if card is ModifierBase or card is ElementBase:
			var id: StringName = card.get(&"look_id")
			check(id == &"" or LookNames.layer_of(id) > 0, "%s: %s is a look" % [path, id])
			if id != &"":
				seen += 1
	check(seen > 30, "most cards have a look (%d)" % seen)


func test_mote_and_mark_kinds_name_looks() -> void:
	var kind := MoteKind.new()
	kind.id = &"probe"
	kind.look_ids = [&"plain", &"nonsense"] as Array[StringName]
	check(", ".join(kind.problems()).contains("nonsense is not a look"), "a mote kind's unknown look is a problem")
	check_equal(kind.look_layers, PackedInt32Array([0]), "and is left out of its numbers")
	for folder: String in ["res://content/motes", "res://content/marks"]:
		for path: String in _files(folder, ".tres"):
			var res: Resource = load(path)
			for look: StringName in res.get(&"look_ids"):
				check(LookNames.known(look), "%s: %s is a look" % [path, look])


## Every file under `folder` ending in `ending`, recursively.
func _files(folder: String, ending: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return found
	for sub in dir.get_directories():
		found.append_array(_files(folder.path_join(sub), ending))
	for file in dir.get_files():
		if file.ends_with(ending):
			found.append(folder.path_join(file))
	return found
