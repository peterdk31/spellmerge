extends SceneTree
## Runs a short version of the stress scene (bench/stress_runner.gd) under
## `ci/build/build.sh --quick --tests`: all four scenarios (a web build skips the desktop one), a few
## seconds each. The full run is `stress.gd`.
##
## The unit test runner plays each scenario in a process of its own (`--shard=K/N`, as
## tests/support/suite.gd takes it; the checks before the run are made in each):
# unit-test-shards: 4

const RunnerScript := preload("res://bench/stress_runner.gd")
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
	# The costliest staffs the warning names (staffs D3): hits a tick (over the window's ticks) plus
	# live shots a tick (over the samples), ties by seat then staff; a staff with only shots ranks too.
	var hits: Dictionary[Vector2i, int] = {Vector2i(1, 1): 600, Vector2i(2, 1): 300, Vector2i(0, 0): 60}
	var shots: Dictionary[Vector2i, int] = {Vector2i(2, 1): 98, Vector2i(3, 2): 5}
	var ranked: Array[Dictionary] = RunnerScript.staffs_by_cost(hits, shots, 10, 600)
	var order: Array[Vector2i] = []
	for row: Dictionary in ranked:
		order.append(Vector2i(int(row["seat"]), int(row["staff"])))
	# (2, 1): 0.5 + 9.8; (1, 1): 1.0; (3, 2): 0.5; (0, 0): 0.1.
	if order != ([Vector2i(2, 1), Vector2i(1, 1), Vector2i(3, 2), Vector2i(0, 0)] as Array[Vector2i]) or not is_equal_approx(float(ranked[0]["cost"]), 10.3):
		printerr("TEST FAILED: the staffs by cost are out of order or miscounted: %s" % [ranked])
		quit(1)
		return
	# The same counts over a window twice as long rank the same: both parts are a tick.
	var longer: Dictionary[Vector2i, int] = {}
	for key: Vector2i in hits:
		longer[key] = hits[key] * 2
	var doubled: Array[Dictionary] = RunnerScript.staffs_by_cost(longer, shots, 10, 1200)
	for n in ranked.size():
		if int(doubled[n]["seat"]) != int(ranked[n]["seat"]) or not is_equal_approx(float(doubled[n]["cost"]), float(ranked[n]["cost"])):
			printerr("TEST FAILED: a longer window changed the staffs by cost: %s / %s" % [ranked, doubled])
			quit(1)
			return
	var none_hits: Dictionary[Vector2i, int] = {}
	var none_shots: Dictionary[Vector2i, int] = {}
	if not RunnerScript.staffs_by_cost(none_hits, none_shots, 0, 0).is_empty():
		printerr("TEST FAILED: no staff measured should rank none")
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
