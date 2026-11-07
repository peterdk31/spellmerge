extends "res://tests/support/suite.gd"
## Commands are heard at the tick's start (online-ready N2, core/events/events.gd): simulation code
## hears a command through `Events.listen`, never by connecting to its signal, which would hear it
## the moment the HUD sends it, in the middle of a tick, and differently in a replay. The HUD and
## tests may still connect to see a command sent. This reads the simulation folders' source
## (StateWalk.FOLDERS) for a connection to any of `InputFrame.COMMAND_NAMES`.


## Every `.gd` file under `folder`, recursively.
func _scripts(folder: String, into: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	for name in dir.get_files():
		if name.ends_with(".gd"):
			into.append(folder.path_join(name))
	for sub in dir.get_directories():
		_scripts(folder.path_join(sub), into)


func test_no_simulation_script_connects_to_a_command() -> void:
	var paths := PackedStringArray()
	for folder: String in StateWalk.FOLDERS:
		_scripts(folder.trim_suffix("/"), paths)
	check(paths.size() > 50, "the simulation folders hold scripts (%d)" % paths.size())
	var patterns: Array[RegEx] = []
	var names: Array[StringName] = []
	for command: StringName in InputFrame.COMMAND_NAMES:
		if command == InputFrame.JOIN or command == InputFrame.LEAVE:
			continue
		var by_signal := RegEx.new()
		by_signal.compile("\\.%s\\.connect\\(" % command)
		var by_name := RegEx.new()
		by_name.compile("connect\\(\\s*&?\"%s\"" % command)
		patterns.append(by_signal)
		patterns.append(by_name)
		names.append(command)
		names.append(command)
	for path in paths:
		var text: String = FileAccess.get_file_as_string(path)
		var lines: PackedStringArray = text.split("\n")
		for at in lines.size():
			var line: String = lines[at].strip_edges()
			if line.begins_with("#"):
				continue
			for i in patterns.size():
				check(patterns[i].search(line) == null, "%s:%d connects to the command %s: hear it with `events.listen(&\"%s\", ...)` so it applies at the tick's start (core/events/events.gd, \"Commands\")" % [path, at + 1, names[i], names[i]])


## The check sees a connection where there is one.
func test_the_check_finds_a_connection() -> void:
	var by_signal := RegEx.new()
	by_signal.compile("\\.%s\\.connect\\(" % "pause_requested")
	check(by_signal.search("events.pause_requested.connect(_on_pause)") != null, "a signal's connect")
	check(by_signal.search("events.listen(&\"pause_requested\", _on_pause)") == null, "a listen is no connect")
