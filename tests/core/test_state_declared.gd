extends "res://tests/support/suite.gd"
## The state is declared (online-ready N1, core/sim/README.md, "State by default"): every member of
## a simulation script (StateWalk.FOLDERS) is state unless the script lists it in DERIVED or VIEW
## (REFS are state, walked as who they point at), and state must be something the walker can hash
## and save. These checks read the scripts, not a game; tests/core/test_state_walked.gd walks the
## state of running games.
##
## - For every simulation script and every inner class of one: every listed name is a member (a
##   rename leaves none behind), and no state member is typed as something that cannot be state: a
##   node of the engine or of a script outside the simulation (a service, a sprite), a view-only
##   node, a Callable, a Signal or an RID.
## - What the walker cannot see, from the source: a static member belongs to no object, so it is
##   listed in DERIVED or VIEW (a cache, a test switch) and never holds state; and no state member
##   keeps a generator: chance comes from `sim` (core/sim/sim.gd, N3c). What simulation code may
##   not call (a clock, the dice, the engine's maths, input, the camera) is
##   tests/core/test_sim_rules.gd's (N9).
## - A name in VIEW is a member, or a function that only draws (N9).
## - A script that lists PARTED hands its parts over (`state_parts`, `state_part`; props W3).
## - The simulation folders in core/sim/README.md's table are StateWalk.FOLDERS.
##
## Each failure names the file, the member and the fix ("add it to DERIVED, it is set up again, not
## saved").

const SimSource := preload("res://tests/support/sim_source.gd")

func test_every_listed_name_is_a_member() -> void:
	for entry in SimSource.scripts():
		var script: Script = entry["script"]
		var members: PackedStringArray = StateWalk.declared(script) + SimSource.statics_of(script)
		var view_functions: PackedStringArray = SimSource.view_functions(script)
		for list: String in StateWalk.LISTS:
			for name in StateWalk.listed(script, list):
				var known: bool = members.has(name) or (list == "VIEW" and view_functions.has(name))
				check(known, "%s: %s lists %s, which is no member%s (renamed?); take it out" % [entry["name"], list, name, " or function" if list == "VIEW" else ""])


## A script that lists PARTED (state the hash walks id by id, props W3) hands each id's part over:
## `state_parts() -> int` and `state_part(id) -> Array` (core/sim/sim_hash.gd, `Part`).
func test_a_parted_script_hands_its_parts_over() -> void:
	for entry in SimSource.scripts():
		var script: Script = entry["script"]
		if StateWalk.listed(script, "PARTED").is_empty():
			continue
		var methods: Dictionary[String, String] = {}
		for method: Dictionary in script.get_script_method_list():
			var returned: Dictionary = method["return"]
			methods[String(method["name"])] = type_string(int(returned["type"]))
		check_equal(methods.get("state_parts", ""), "int", "%s lists PARTED: it has state_parts() -> int" % entry["name"])
		check_equal(methods.get("state_part", ""), "Array", "%s lists PARTED: it has state_part(id) -> Array" % entry["name"])


## A setting a new run keeps (RUN_KEEPS, core/sim/sim_fresh.gd) is a state member: one in DERIVED or
## VIEW is never reset anyway, so listing it there too says the wrong thing.
func test_every_run_keep_is_state() -> void:
	for entry in SimSource.scripts():
		var script: Script = entry["script"]
		var not_state: PackedStringArray = StateWalk.listed(script, "DERIVED") + StateWalk.listed(script, "VIEW")
		for name in StateWalk.listed(script, "RUN_KEEPS"):
			check(not not_state.has(name), "%s: RUN_KEEPS lists %s, which is DERIVED or VIEW (never reset at a run's start anyway); take it out of one" % [entry["name"], name])


func test_no_state_member_is_typed_as_something_it_cannot_save() -> void:
	var classes: Dictionary[String, String] = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		classes[String(entry["class"])] = String(entry["path"])
	for entry in SimSource.scripts():
		var script: Script = entry["script"]
		if StateWalk.is_view_only(script):
			continue
		var skip: PackedStringArray = StateWalk.listed(script, "DERIVED") + StateWalk.listed(script, "VIEW") + StateWalk.listed(script, "REFS")
		var inherited: PackedStringArray = StateWalk.declared(script.get_base_script()) if script.get_base_script() != null else PackedStringArray()
		for info: Dictionary in script.get_script_property_list():
			var name: String = info["name"]
			if int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or skip.has(name) or inherited.has(name):
				continue
			var why: String = _cannot_hold(info, classes)
			check(why.is_empty(), "%s: %s holds %s; add it to DERIVED (a service, set up again), REFS (another body, state) or VIEW (only the drawing reads it) (core/sim/README.md, \"Steps\")" % [entry["name"], name, why])


func test_no_static_member_holds_state() -> void:
	for entry in SimSource.scripts():
		var script: Script = entry["script"]
		if StateWalk.is_view_only(script):
			continue
		var listed: PackedStringArray = StateWalk.listed(script, "DERIVED") + StateWalk.listed(script, "VIEW")
		for name in SimSource.statics_of(script):
			check(listed.has(name), "%s: the static member %s belongs to no object, so no walk sees it; a cache or a switch goes in DERIVED, state goes in an object's member (core/sim/README.md, \"Steps\")" % [entry["name"], name])


func test_no_state_member_keeps_a_generator() -> void:
	for entry in SimSource.scripts():
		var script: Script = entry["script"]
		if StateWalk.is_view_only(script):
			continue
		var skip: PackedStringArray = StateWalk.listed(script, "VIEW")
		for info: Dictionary in script.get_script_property_list():
			var name: String = info["name"]
			if int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or skip.has(name):
				continue
			check(String(info["class_name"]) != "RandomNumberGenerator", "%s: %s keeps a generator; the simulation takes chance from its `sim` (core/sim/sim.gd): `sim.chance(purpose, key, counter)`, with a counter of its rolls as state (core/sim/README.md, \"Chance\")" % [entry["name"], name])


func test_the_readme_lists_the_simulation_folders() -> void:
	var listed := PackedStringArray()
	var row := RegEx.create_from_string("^\\| `([a-z_/]+/)` \\|")
	for line in FileAccess.get_file_as_string("res://core/sim/README.md").split("\n"):
		var found: RegExMatch = row.search(line)
		if found != null:
			listed.append("res://" + found.get_string(1))
	check_equal(listed, PackedStringArray(StateWalk.FOLDERS), "core/sim/README.md's table of simulation folders is StateWalk.FOLDERS, in order")


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
