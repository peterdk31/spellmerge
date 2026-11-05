extends RefCounted
## A fresh game in the same process, for tests: every autoload of project.godot is freed and made
## again, in the project's order, as the game starts them. The services keep clocks, counters
## and pools from run to run (the projectile manager's `sim_time` and `_next_seq`, Spells'
## clock, Combat's steps, the AI board's clock), so a run's state depends on the runs before it in
## the process; a test that compares two runs from the same start (a recorded run and its
## replay, tests/core/test_replay_game.gd) starts each from a fresh game. Static members (caches)
## stay. The current scene is left alone: stop the run first.
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
