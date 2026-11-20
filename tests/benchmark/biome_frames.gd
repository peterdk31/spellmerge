extends SceneTree
## The performance pass's measure, started as a script: adds the runner (biome_frames_runner.gd:
## four bots in a generated 16-room crypt biome, busy fights, the game's split screen in Dynamic and
## Equal, over seeded runs) to the root; it quits with 0 or 1 and prints `BENCH:` lines and
## `BIOME FRAMES OK`. It needs a window: on a machine with no GPU, under `xvfb-run` (llvmpipe draws,
## slower than a GPU but its times follow the work).
##
## xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --script res://tests/benchmark/biome_frames.gd
## ... -- --only="seed 11 desktop apart dynamic"   those scenarios alone (labels, comma separated)
## ... -- --profile                                 the tree profile too (each script's time)
## ... -- --no-native                               the GDScript kernels in place of the module

const RunnerScript := preload("res://tests/benchmark/biome_frames_runner.gd")


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	root.add_child(RunnerScript.new())
