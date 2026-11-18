extends SceneTree
## The camera spike's split screen (connected biomes CB1), started as a script: adds the runner
## (split_views_runner.gd: the stress fight drawn in 0 to 4 Voronoi views) to the root; it quits
## with 0 or 1 and prints `BENCH:` lines and `SPLIT VIEWS OK`. It needs a window: on a machine
## with no GPU, under `xvfb-run` (llvmpipe draws, slower than a GPU but its times follow the work).
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --script res://tests/benchmark/split_views.gd
## ... -- --only="desktop 4 views,web 4 views"   those scenarios alone (labels, comma separated)
## ... -- --no-native                              the GDScript kernels in place of the module
##
## `test_split_views.gd` checks the runner's scenarios and the views' cells without drawing.

const RunnerScript := preload("res://tests/benchmark/split_views_runner.gd")


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	root.add_child(RunnerScript.new())
