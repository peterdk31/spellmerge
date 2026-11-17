extends SceneTree
## What the enemy arrival look costs a frame (enemy arrivals, docs/milestones/enemy-arrivals.md,
## "The look"; gameplay/feel/arrive_look.gd): adds the runner (arrive_cost_runner.gd), which holds
## N enemies mid-rise in the crypt's first arena and times the frame as built (the body's root a
## clip parent), with the cut off (shifted only), with a per-sprite `region_rect` cut in its place
## (a prototype, in the runner only), and against the same N standing. It prints `BENCH: arrive`
## lines, then `ARRIVE COST OK`. Not run in the build; it needs a window (a GPU, or `xvfb-run`
## with llvmpipe), a couple of minutes on llvmpipe.
##
##   godot --path . --script res://tests/benchmark/arrive_cost.gd
##   ... -- --counts=0,1,4,8,16,32 --frames=300 --warm=120 --only=stand,clip,noclip,region,clip_nomarks,clip_nocue --shots=DIR

const RunnerScript := preload("res://tests/benchmark/arrive_cost_runner.gd")


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	root.add_child(RunnerScript.new())
