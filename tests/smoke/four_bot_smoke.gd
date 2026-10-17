extends SceneTree
## 4-bot smoke test, started as a script: adds the runner (four_bot_runner.gd, which
## has the checks and the rules for passing) to the root; the runner quits with 0 or
## 1. `test_four_bot_smoke.gd` runs it under `build.sh --quick --tests`.
##
## godot --headless --path . --script res://tests/smoke/four_bot_smoke.gd

const RunnerScript := preload("res://tests/smoke/four_bot_runner.gd")


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	root.add_child(RunnerScript.new())
