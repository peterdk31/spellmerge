extends RefCounted
## The simulation scripts' source, for the tests that read it (online-ready N9,
## core/sim/README.md, "The simulation folders"): which scripts are simulation, each one's lines of
## code without comments and strings, and which of those lines are view (a function the script
## lists in `VIEW`, or a line marked `# view: why`).
##
## Used by tests/core/test_sim_rules.gd (what simulation code may not do), test_state_declared.gd
## (its member lists) and test_commands_heard.gd (commands heard at the tick's start).

const StateWalk := preload("res://core/sim/state_walk.gd")

## A line marked as drawing only: rules about the simulation skip it.
const VIEW_MARK: String = "# view:"


## Every simulation script's path, sorted (StateWalk.FOLDERS, without StateWalk.VIEW_FOLDERS).
static func paths() -> PackedStringArray:
	var out := PackedStringArray()
	for folder in StateWalk.FOLDERS:
		_collect(folder.trim_suffix("/"), out)
	out.sort()
	return out


## Every simulation script, sorted, then its inner classes (an inner class has no path of its own:
## it is found among its file's constants), as {"name": "res://...gd" or "res://...gd::Inner",
## "script": the script}.
static func scripts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for path in paths():
		_add_with_inner(path, load(path) as Script, out)
	return out


## A script's source ("" for an inner class: its lines are its file's, read with the file).
static func source_of(script: Script) -> String:
	if script.resource_path.is_empty() or not script.resource_path.ends_with(".gd"):
		return ""
	return FileAccess.get_file_as_string(script.resource_path)


## The functions `script` (with the scripts it extends and its inner classes) names in a `VIEW` list:
## its drawing, which may use real time and the engine's maths.
static func view_functions(script: Script) -> PackedStringArray:
	var out := PackedStringArray()
	var methods := PackedStringArray()
	for info: Dictionary in script.get_script_method_list():
		methods.append(String(info["name"]))
	for name in StateWalk.listed(script, "VIEW"):
		if methods.has(name):
			out.append(name)
	return out


## The lines of a simulation file's code that rules apply to, as {"line": 1-based, "text": the
## line, "code": without comments and strings}: not the lines inside a function the script lists
## in VIEW (its header included), not a VIEW member's declaration, not a line marked `# view:`, not
## a blank or comment-only line.
static func code_lines(script: Script) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var source: String = source_of(script)
	if source.is_empty():
		return out
	var view := PackedStringArray()
	var view_members := PackedStringArray()
	for each in with_inner(script):
		view.append_array(view_functions(each))
		view_members.append_array(StateWalk.listed(each, "VIEW"))
	var header := RegEx.create_from_string("^(\\s*)(static\\s+)?func\\s+(\\w+)\\s*\\(")
	var member := RegEx.create_from_string("^\\s*(@\\w+(\\([^)]*\\))?\\s+)*(static\\s+)?var\\s+(\\w+)")
	var lines: PackedStringArray = source.split("\n")
	var skip_deeper_than: int = -1  # inside a view function: lines indented more than its header
	for i in lines.size():
		var text: String = lines[i]
		var code: String = code_of(text)
		if code.strip_edges().is_empty():
			continue
		var indent: int = _indent(text)
		if skip_deeper_than >= 0:
			if indent > skip_deeper_than:
				continue
			skip_deeper_than = -1
		var found: RegExMatch = header.search(text)
		if found != null and view.has(found.get_string(3)):
			skip_deeper_than = indent
			continue
		if text.contains(VIEW_MARK):
			continue
		var declared: RegExMatch = member.search(text)
		if declared != null and view_members.has(declared.get_string(4)):
			continue  # a VIEW member's declaration (a drawing's own generator)
		out.append({"line": i + 1, "text": text, "code": code})
	return out


## `script` and its inner classes, in turn (an inner class's lines are its file's).
static func with_inner(script: Script) -> Array[Script]:
	var out: Array[Script] = [script]
	var constants: Dictionary = script.get_script_constant_map()
	for constant: String in constants:
		var value: Variant = constants[constant]
		if value is Script and (value as Script).resource_path.is_empty():
			out.append_array(with_inner(value as Script))
	return out


## The names a file's script, the scripts it extends and its inner classes list in `list`.
static func listed_in_file(script: Script, list: String) -> PackedStringArray:
	var out := PackedStringArray()
	for each in with_inner(script):
		out.append_array(StateWalk.listed(each, list))
	return out


## The static members `script` and the scripts it extends declare (from their source; an inner
## class's are its file's).
static func statics_of(script: Script) -> PackedStringArray:
	var out := PackedStringArray()
	var pattern := RegEx.create_from_string("^static var (\\w+)")
	var at: Script = script
	while at != null:
		for line in source_of(at).split("\n"):
			var found: RegExMatch = pattern.search(line)
			if found != null:
				out.append(found.get_string(1))
		at = at.get_base_script()
	return out


## A line of GDScript without its comment (a `#` outside a string), and without its strings' text, so
## a doc line or a message that names `randf()` is not code that calls it.
static func code_of(line: String) -> String:
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


## A line's indentation in tabs (a space counts as one too; the project indents with tabs).
static func _indent(line: String) -> int:
	var n: int = 0
	while n < line.length() and (line[n] == "\t" or line[n] == " "):
		n += 1
	return n


static func _add_with_inner(name: String, script: Script, out: Array[Dictionary]) -> void:
	out.append({"name": name, "script": script})
	var constants: Dictionary = script.get_script_constant_map()
	for constant: String in constants:
		var value: Variant = constants[constant]
		if value is Script and (value as Script).resource_path.is_empty():
			_add_with_inner("%s::%s" % [name, constant], value as Script, out)


static func _collect(dir_path: String, out: PackedStringArray) -> void:
	if StateWalk.VIEW_FOLDERS.has(dir_path + "/"):
		return
	for file in DirAccess.get_files_at(dir_path):
		if file.ends_with(".gd"):
			out.append(dir_path + "/" + file)
	for sub in DirAccess.get_directories_at(dir_path):
		_collect(dir_path + "/" + sub, out)
