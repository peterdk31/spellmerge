extends RefCounted
## A fresh game in the same process, for tests: every autoload of project.godot is freed and made
## again, in the project's order, as the game starts them: what a game is before its first run. A
## run starts from a fresh game's state anyway (`Tick.begin_run`, online-ready N3b); the replay
## test (tests/core/test_replay_game.gd) starts runs from a fresh game and in the same game after
## others, and compares them. Static members (caches) stay. The current scene is left alone: stop
## the run first.
##
##     FreshGame.restart(root)


## Free every autoload under `root` and make each again from project.godot, in order.
static func restart(root: Window) -> void:
	var names: Array[String] = []
	var paths: Array[String] = []
	for info: Dictionary in ProjectSettings.get_property_list():
		var key: String = info["name"]
		if not key.begins_with("autoload/"):
			continue
		names.append(key.trim_prefix("autoload/"))
		paths.append(String(ProjectSettings.get_setting(key)).trim_prefix("*"))
	for at in range(names.size() - 1, -1, -1):
		var old: Node = root.get_node_or_null(names[at])
		if old != null:
			root.remove_child(old)
			old.free()
	for at in names.size():
		var made: Node = null
		var resource: Resource = load(paths[at])
		if resource is PackedScene:
			made = (resource as PackedScene).instantiate()
		elif resource is Script:
			made = (resource as Script).new() as Node
		if made == null:
			push_error("FreshGame: the autoload %s (%s) could not be made." % [names[at], paths[at]])
			continue
		made.name = names[at]
		root.add_child(made)
