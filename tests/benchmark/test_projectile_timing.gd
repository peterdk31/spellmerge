extends SceneTree
## Times the projectile manager at its caps and prints `BENCH:` lines: adds the runner
## (projectile_timing_runner.gd, which has the timings and what they check) to the root;
## the runner quits with 0 or 1.
##
## godot --headless --path . --script res://tests/benchmark/test_projectile_timing.gd
##
## The unit test runner plays its rounds (native and GDScript, each at both caps) in processes of
## their own (`--shard=K/N`, as tests/support/suite.gd takes it; `part` and `parts` of the runner):
# unit-test-shards: 4

const RunnerScript := preload("res://tests/benchmark/projectile_timing_runner.gd")
const Suite := preload("res://tests/support/suite.gd")


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	var runner: Node = RunnerScript.new()
	runner.set(&"compare", true)
	var shard: Vector2i = Suite.shard_of(OS.get_cmdline_user_args())
	runner.set(&"part", shard.x)
	runner.set(&"parts", shard.y)
	root.add_child(runner)
