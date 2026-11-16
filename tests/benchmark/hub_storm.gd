extends SceneTree
## The hub storm (hub_storm_runner.gd, which has the scene and what it prints) as a script: the
## Frostfire Cascade's split-and-nova build (a premade staff of the hub's rack) cast again and again
## from among the hub's training dummies, counting how many of its shots hit each dummy. Adds the runner to the root; it quits
## with 0 or 1. Not a unit test.
##
## godot --headless --path . --script res://tests/benchmark/hub_storm.gd
## godot --path . --script res://tests/benchmark/hub_storm.gd -- --stay
## godot --headless --path . --script res://tests/benchmark/hub_storm.gd -- --seconds=20 --cap=10000

const RunnerScript := preload("res://tests/benchmark/hub_storm_runner.gd")


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	root.add_child(RunnerScript.new())
