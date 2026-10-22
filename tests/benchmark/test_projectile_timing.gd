extends SceneTree
## Times the projectile manager at its caps and prints `BENCH:` lines: adds the runner
## (projectile_timing_runner.gd, which has the timings and what they check) to the root;
## the runner quits with 0 or 1.
##
## godot --headless --path . --script res://tests/benchmark/test_projectile_timing.gd

const RunnerScript := preload("res://tests/benchmark/projectile_timing_runner.gd")


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	root.add_child(RunnerScript.new())
