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
##   listed in DERIVED or VIEW (a cache, a test switch) and never holds state; and simulation code
##   reads no clock (`Time`, `OS.get_ticks_*`) and rolls no global dice (`randomize()`, `randf()`,
##   `randi()`, `seed()`): a seed nobody chose comes from `SimSeed.fresh()` (core/sim). View-only
##   scripts (`VIEW_ONLY`) may do both.
## - The simulation folders in core/sim/README.md's table are StateWalk.FOLDERS.
##
## Each failure names the file, the member and the fix ("add it to DERIVED, it is set up again, not
## saved").

## Code a simulation script may not hold outside a comment (see the class doc), and why.
const FORBIDDEN: Dictionary = {
	"(^|[^\\w])randomize\\(": "seeds a generator by the clock; take `SimSeed.fresh()` (core/sim)",
	"(^|[^.\\w])(randf|randi|randf_range|randi_range|randfn|seed)\\(": "rolls the engine's global dice; use a generator of its own, seeded by the game",
	"(^|[^\\w])Time\\.": "reads the clock; the simulation runs on its own time (`delta`, `sim_time`)",
	"(^|[^\\w])OS\\.get_(ticks|unix)": "reads the clock; the simulation runs on its own time (`delta`, `sim_time`)",
}


func test_every_listed_name_is_a_member() -> void:
	for entry in _simulation_scripts():
		var script: Script = entry["script"]
		var members: PackedStringArray = StateWalk.declared(script) + _statics_of(script)
		for list: String in StateWalk.LISTS:
			for name in StateWalk.listed(script, list):
				check(members.has(name), "%s: %s lists %s, which is no member (renamed?); take it out" % [entry["name"], list, name])


func test_no_state_member_is_typed_as_something_it_cannot_save() -> void:
	var classes: Dictionary[String, String] = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		classes[String(entry["class"])] = String(entry["path"])
	for entry in _simulation_scripts():
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
	for entry in _simulation_scripts():
		var script: Script = entry["script"]
		if StateWalk.is_view_only(script):
			continue
		var listed: PackedStringArray = StateWalk.listed(script, "DERIVED") + StateWalk.listed(script, "VIEW")
		for name in _statics_of(script):
			check(listed.has(name), "%s: the static member %s belongs to no object, so no walk sees it; a cache or a switch goes in DERIVED, state goes in an object's member (core/sim/README.md, \"Steps\")" % [entry["name"], name])


func test_simulation_code_reads_no_clock_and_rolls_no_global_dice() -> void:
	var patterns: Array[RegEx] = []
	for pattern: String in FORBIDDEN:
		patterns.append(RegEx.create_from_string(pattern))
	for entry in _simulation_scripts():
		var script: Script = entry["script"]
		var source: String = _source_of(script)
		if source.is_empty() or StateWalk.is_view_only(script):
			continue
		var lines: PackedStringArray = source.split("\n")
		for i in lines.size():
			var code: String = _code_of(lines[i])
			for p in patterns.size():
				if patterns[p].search(code) != null:
					check(false, "%s:%d %s: %s" % [entry["name"], i + 1, FORBIDDEN.values()[p], lines[i].strip_edges()])


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


## Every simulation script, sorted, then its inner classes (an inner class has no path of its own:
## it is found among its file's constants), as {"name": "res://...gd" or "res://...gd::Inner",
## "script": the script}.
static func _simulation_scripts() -> Array[Dictionary]:
	var paths := PackedStringArray()
	for folder in StateWalk.FOLDERS:
		_collect(folder.trim_suffix("/"), paths)
	paths.sort()
	var out: Array[Dictionary] = []
	for path in paths:
		_add_with_inner(path, load(path) as Script, out)
	return out


static func _add_with_inner(name: String, script: Script, out: Array[Dictionary]) -> void:
	out.append({"name": name, "script": script})
	var constants: Dictionary = script.get_script_constant_map()
	for constant: String in constants:
		var value: Variant = constants[constant]
		if value is Script and (value as Script).resource_path.is_empty():
			_add_with_inner("%s::%s" % [name, constant], value as Script, out)


static func _collect(dir_path: String, out: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(dir_path):
		if file.ends_with(".gd"):
			out.append(dir_path + "/" + file)
	for sub in DirAccess.get_directories_at(dir_path):
		_collect(dir_path + "/" + sub, out)


## A script's source ("" for an inner class: its lines are its file's, scanned with the file).
static func _source_of(script: Script) -> String:
	if script.resource_path.is_empty() or not script.resource_path.ends_with(".gd"):
		return ""
	return FileAccess.get_file_as_string(script.resource_path)


## The static members `script` and the scripts it extends declare (from their source; an inner
## class's are its file's).
static func _statics_of(script: Script) -> PackedStringArray:
	var out := PackedStringArray()
	var pattern := RegEx.create_from_string("^static var (\\w+)")
	var at: Script = script
	while at != null:
		for line in _source_of(at).split("\n"):
			var found: RegExMatch = pattern.search(line)
			if found != null:
				out.append(found.get_string(1))
		at = at.get_base_script()
	return out


## A line of GDScript without its comment (a `#` outside a string), and without its strings' text, so
## a doc line or a message that names `randf()` is not code that calls it.
static func _code_of(line: String) -> String:
	var out: String = ""
	var quote: String = ""
	var i: int = 0
	while i < line.length():
		var c: String = line[i]
		if quote.is_empty():
			if c == "#":
				break
			if c == "\"" or c == "'":
				quote = c
			out += c
		else:
			if c == "\\":
				i += 1
			elif c == quote:
				quote = ""
				out += c
		i += 1
	return out
