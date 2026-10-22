extends SceneTree
## The stress scene, started as a script: adds the runner (stress_runner.gd, which has the
## scenarios and the rules for passing) to the root; the runner quits with 0 or 1. It
## prints `BENCH:` lines and `STRESS OK`, and takes about half a minute.
##
## godot --headless --path . --script res://tests/benchmark/stress.gd
##
## `test_stress.gd` runs a short version under `build.sh --quick --tests`.

const RunnerScript := preload("res://tests/benchmark/stress_runner.gd")


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	root.add_child(RunnerScript.new())
