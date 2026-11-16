extends SceneTree
## What ground cover costs (ground cover GC6, docs/milestones/ground-cover.md, "Cost"): adds the
## runner (cover_cost_runner.gd), which plays the largest room of the game fully covered under a
## stand-in grass with 100 bodies in it, and prints the tick's and the frame's cost with no cover
## (the game as main plays it, before GC8's art), at rest, all of it burning at once and with a fire
## spreading through it (`BENCH: cover`), then `COVER COST OK`. Not run in the build; under a minute.
##
## godot --headless --path . --script res://tests/benchmark/cover_cost.gd [-- --bodies=100 --ticks=300 --only=none,rest,burning,front]

const RunnerScript := preload("res://tests/benchmark/cover_cost_runner.gd")


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	root.add_child(RunnerScript.new())
