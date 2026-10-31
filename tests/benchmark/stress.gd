extends SceneTree
## The stress scene, started as a script: adds the runner (stress_runner.gd, which has the
## scenarios and the rules for passing) to the root; the runner quits with 0 or 1. It
## prints `BENCH:` lines and `STRESS OK`, and takes about a minute (four scenarios; three in a web build, longer at its frame rate).
##
## godot --headless --path . --script res://tests/benchmark/stress.gd
## godot --headless --path . --script res://tests/benchmark/stress.gd -- --horde
## godot --headless --path . --script res://tests/benchmark/stress.gd -- --horde-swarm
## godot --headless --path . --script res://tests/benchmark/stress.gd -- --horde-swarm --swarm=600 --staff=16 --profile
##
## With `--horde` it runs only the horde scenarios (500+ enemies, Horde H1; the runner's
## `HORDE`), which the default run leaves out; so does an exported test build started with
## `--stress --horde`.
## With `--horde-swarm` it runs only the swarm scenarios (1,000 swarmers with their look beside 16
## staff enemies, and the web's 500 beside 25; docs/milestones/horde-swarm.md S1 and S4), with the
## physics step's parts timed; `--swarm=N --staff=M` sets their counts, `--profile` adds the tree
## profile (tree_profile.gd) and `--profile-signals` times the hot events' listeners too.
##
## `test_stress.gd` runs a short version under `build.sh --quick --tests`.

const RunnerScript := preload("res://tests/benchmark/stress_runner.gd")


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	root.add_child(RunnerScript.new())
