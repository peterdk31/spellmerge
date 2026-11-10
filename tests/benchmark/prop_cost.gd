extends SceneTree
## What a prop costs the simulation (props W1, docs/milestones/props.md): adds the runner
## (prop_cost_runner.gd), which stands 0, 300 and 1,000 controller-less stand-ins in the real hub and
## prints the tick's, the state hash's and a snapshot's cost for each (`BENCH: props`), then
## `PROP COST OK`. Not run in the build; a few seconds.
##
## godot --headless --path . --script res://tests/benchmark/prop_cost.gd [-- --counts=0,300,1000]

const RunnerScript := preload("res://tests/benchmark/prop_cost_runner.gd")


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	root.add_child(RunnerScript.new())
