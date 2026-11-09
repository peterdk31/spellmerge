extends SceneTree
## Runs a short version of the stress scene (tests/benchmark/stress_runner.gd) under
## `ci/build/build.sh --quick --tests`: all four scenarios (a web build skips the desktop one), a few
## seconds each. The full run is `stress.gd`.
##
## godot --headless --path . --script res://tests/benchmark/test_stress.gd
##
## The unit test runner plays each scenario in a process of its own (`--shard=K/N`, as
## tests/support/suite.gd takes it; the checks before the run are made in each):
# unit-test-shards: 4

const RunnerScript := preload("res://tests/benchmark/stress_runner.gd")
const Suite := preload("res://tests/support/suite.gd")


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	var runner: Node = RunnerScript.new()
	# A variant turns drawing and hit particles off; the restore step must turn them back on
	# (the run itself quits the tree, so it is checked here, before the run starts).
	var feel: Node = root.get_node_or_null("Feel")
	runner.set("_feel", feel)
	RenderingServer.render_loop_enabled = false
	if feel != null:
		feel.set("particles_enabled", false)
	runner.call("_restore_diagnostics")
	var restored: bool = RenderingServer.render_loop_enabled
	if feel != null:
		restored = restored and bool(feel.get("particles_enabled"))
	if not restored:
		printerr("TEST FAILED: the render loop or the hit particles stayed off after a variant")
		quit(1)
		return
	# A web build skips the desktop scenario (its budget is the desktop export's); others keep all.
	var all: Array[int] = [0, 2, 3, 1]
	var web: Array[int] = RunnerScript.scenarios_for(all, true)
	if web != ([0, 2, 3] as Array[int]) or RunnerScript.scenarios_for(all, false) != all:
		printerr("TEST FAILED: the web run should skip only the desktop scenario, got %s" % [web])
		quit(1)
		return
	runner.set("warm_up", 3.0)
	runner.set("measure", 2.0)
	var shard: Vector2i = Suite.shard_of(OS.get_cmdline_user_args())
	if shard.y > 1:
		var mine: Array[int] = []
		for i in all.size():
			if i % shard.y == shard.x:
				mine.append(all[i])
		runner.set("scenarios", mine)
	root.add_child(runner)
