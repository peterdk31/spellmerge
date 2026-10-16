extends SceneTree
## Boot smoke test: starts the main scene, runs it for a few seconds of frames
## and fails unless the menu came up with a build version.
##
## godot --headless --path . --script res://tests/smoke/boot_smoke.gd

const FRAMES := 300

var _frames: int = 0
var _menu: Node


func _initialize() -> void:
	var path := str(ProjectSettings.get_setting("application/run/main_scene"))
	var scene := load(path) as PackedScene
	if scene == null:
		_fail("the main scene %s did not load" % path)
		return
	_menu = scene.instantiate()
	root.add_child(_menu)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < FRAMES:
		return false
	var version := _menu.get_node_or_null("%Version") as Label
	if version == null or version.text.is_empty():
		_fail("the main menu shows no build version")
	else:
		print("SMOKE OK: main menu ran %d frames, version '%s'" % [_frames, version.text])
		quit(0)
	return true


func _fail(reason: String) -> void:
	printerr("SMOKE FAILED: " + reason)
	quit(1)
