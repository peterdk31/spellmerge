extends SceneTree
## The frames of a run as it is played (play_frames_runner.gd: 1 to 4 players in a generated crypt
## biome, near and far zoom, together and apart in Dynamic and Equal, no stress crowd), started as a
## script: adds the runner to the root; it quits with 0 or 1 and prints `BENCH:` lines and
## `PLAY FRAMES OK`. It needs a window: on a machine with no GPU, under `xvfb-run` (llvmpipe draws,
## slower than a GPU but its times follow the work).
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --script res://tests/benchmark/play_frames.gd
## ... -- --only="1p near,4p apart equal"   those scenarios alone (labels, comma separated)
## ... -- --profile                         the tree profile too (each script's time)
## ... -- --off=light,shadows,air,fog        those passes switched off by their settings
## ... -- --picture=1280x720                 the picture drawn at that size (the light at its own)
## ... -- --light-at-picture                 the light drawn at the picture's resolution (the A/B)

const RunnerScript := preload("res://bench/play_frames_runner.gd")


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	root.add_child(RunnerScript.new())
