extends SceneTree
## Runs a short version of the stress scene (tests/benchmark/stress_runner.gd) under
## `ci/build/build.sh --quick --tests`: both scenarios, a few seconds each. The full run is
## `stress.gd`.
##
## godot --headless --path . --script res://tests/benchmark/test_stress.gd

const RunnerScript := preload("res://tests/benchmark/stress_runner.gd")


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	var runner: Node = RunnerScript.new()
	runner.set("warm_up", 3.0)
	runner.set("measure", 2.0)
	root.add_child(runner)
