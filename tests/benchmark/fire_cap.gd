extends SceneTree
## The fire cap sweep (fire_cap_runner.gd, which has the scene and what it prints) as a script:
## adds the runner to the root; it quits with 0 or 1. Not a unit test: it takes a few minutes.
##
## godot --headless --path . --script res://tests/benchmark/fire_cap.gd

const RunnerScript := preload("res://tests/benchmark/fire_cap_runner.gd")


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	root.add_child(RunnerScript.new())
