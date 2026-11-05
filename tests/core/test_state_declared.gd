extends "res://tests/support/suite.gd"
## The state is declared (online-ready N1, docs/milestones/online-ready.md, "State by default"):
## every member of a simulation script (StateWalk.FOLDERS) is state unless the script lists it in
## DERIVED or VIEW, and state must be something the walker can hash and save.
##
## - Statically, for every simulation script: every name in DERIVED and VIEW is a member (a rename
##   leaves none behind), and no state member is typed as something that cannot be state: a node of
##   the engine or of a script outside the simulation (a service, a sprite), a view-only node, a
##   Callable, a Signal or an RID.
## - Live: the determinism tests' scenes (tests/core/sim_scenes.gd: a staffed fight, a spell storm,
##   a horde wave) are walked after two seconds, and the walk must meet no problem (a reference to a
##   node it does not own, an engine object).
##
## Each failure names the file, the member and the fix ("add it to DERIVED, it is set up again, not
## saved").

const SimScenes := preload("res://tests/core/sim_scenes.gd")

const STEPS: int = 120


func test_every_listed_name_is_a_member() -> void:
	for path in _simulation_scripts():
		var script: Script = load(path) as Script
		var members: PackedStringArray = StateWalk.declared(script)
		for list: String in ["DERIVED", "VIEW"]:
			for name in StateWalk.listed(script, list):
				check(members.has(name), "%s: %s lists %s, which is no member (renamed?); take it out" % [path, list, name])


func test_no_state_member_is_typed_as_something_it_cannot_save() -> void:
	var classes: Dictionary[String, String] = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		classes[String(entry["class"])] = String(entry["path"])
	for path in _simulation_scripts():
		var script: Script = load(path) as Script
		if StateWalk.is_view_only(script):
			continue
		var skip: PackedStringArray = StateWalk.listed(script, "DERIVED") + StateWalk.listed(script, "VIEW")
		var inherited: PackedStringArray = StateWalk.declared(script.get_base_script()) if script.get_base_script() != null else PackedStringArray()
		for info: Dictionary in script.get_script_property_list():
			var name: String = info["name"]
			if int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or skip.has(name) or inherited.has(name):
				continue
			var why: String = _cannot_hold(info, classes)
			check(why.is_empty(), "%s: %s holds %s; add it to DERIVED (or VIEW if only the drawing reads it), it is set up again, not saved" % [path, name, why])


func test_a_staffed_fight_walks_without_problems() -> void:
	_check_scene(&"fight")


func test_a_spell_storm_walks_without_problems() -> void:
	_check_scene(&"storm")


func test_a_horde_wave_walks_without_problems() -> void:
	_check_scene(&"horde")


## The scene (tests/core/sim_scenes.gd) played a few seconds, then walked.
func _check_scene(name: StringName) -> void:
	var scene := SimScenes.new(root, name)
	for i in STEPS:
		scene.step()
	_check_walk(scene.areas())
	scene.free_all()


func _check_walk(areas: Dictionary) -> void:
	var walk := StateWalk.new()
	var leaves: Array[int] = [0]
	for name: Variant in areas:
		walk.walk(String(name), areas[name] as Object, func(_path: String, _value: Variant) -> void: leaves[0] += 1)
	check(leaves[0] > 0, "the walk reached some state")
	for problem in walk.problems:
		check(false, problem)


## What a member typed by `info` holds that cannot be state, or "".
static func _cannot_hold(info: Dictionary, classes: Dictionary[String, String]) -> String:
	var type: int = info["type"]
	match type:
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return "a %s" % type_string(type)
		TYPE_OBJECT:
			return _cannot_be(String(info["class_name"]), classes)
		TYPE_ARRAY:
			if int(info["hint"]) == PROPERTY_HINT_ARRAY_TYPE:
				return _cannot_be(String(info["hint_string"]), classes)
		TYPE_DICTIONARY:
			if int(info["hint"]) == PROPERTY_HINT_DICTIONARY_TYPE:
				for part in String(info["hint_string"]).split(";"):
					var why: String = _cannot_be(part, classes)
					if not why.is_empty():
						return why
	return ""


## Why an object of class `name` (engine or global script class) cannot be state, or "".
static func _cannot_be(name: String, classes: Dictionary[String, String]) -> String:
	if name.is_empty():
		return ""
	if classes.has(name):
		var script: Script = load(classes[name]) as Script
		if not _is_node(script.get_instance_base_type()):
			return ""
		if not StateWalk.is_simulation(script):
			return "a node of %s, outside the simulation" % classes[name].get_file()
		if StateWalk.is_view_only(script):
			return "a view-only node (%s)" % classes[name].get_file()
		return ""
	if _is_node(StringName(name)):
		return "a %s" % name
	return ""


static func _is_node(native: StringName) -> bool:
	return ClassDB.class_exists(native) and (native == &"Node" or ClassDB.is_parent_class(native, &"Node"))


## Every script in the simulation folders, sorted.
static func _simulation_scripts() -> PackedStringArray:
	var out := PackedStringArray()
	for folder in StateWalk.FOLDERS:
		_collect(folder.trim_suffix("/"), out)
	out.sort()
	return out


static func _collect(dir_path: String, out: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(dir_path):
		if file.ends_with(".gd"):
			out.append(dir_path + "/" + file)
	for sub in DirAccess.get_directories_at(dir_path):
		_collect(dir_path + "/" + sub, out)
