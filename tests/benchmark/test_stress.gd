extends SceneTree
## Runs a short version of the stress scene (tests/benchmark/stress_runner.gd) under
## `ci/build/build.sh --quick --tests`: all four scenarios (a web build skips the desktop one), a few
## seconds each, and the choice of the horde scenarios and their swarmer (not run here: they
## take long; `stress.gd -- --horde`). The full run is
## `stress.gd`.
##
## godot --headless --path . --script res://tests/benchmark/test_stress.gd

const RunnerScript := preload("res://tests/benchmark/stress_runner.gd")


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
	# The horde scenarios (Horde H1) run only on `--horde`, and a web build drops the desktop one.
	var none: PackedStringArray = PackedStringArray()
	var horde: Array[int] = RunnerScript.scenarios_from_args(PackedStringArray(["--horde"]), all)
	if RunnerScript.scenarios_from_args(none, all) != all or horde != RunnerScript.HORDE:
		printerr("TEST FAILED: --horde should pick the horde scenarios and nothing else the default, got %s" % [horde])
		quit(1)
		return
	var web_horde: Array[int] = RunnerScript.scenarios_for(horde, true)
	if web_horde.size() != 1 or RunnerScript.SCENARIOS[web_horde[0]]["enemies"] < 500:
		printerr("TEST FAILED: a web build should keep the web horde of 500+, got %s" % [web_horde])
		quit(1)
		return
	for index in RunnerScript.HORDE:
		var scenario: Dictionary = RunnerScript.SCENARIOS[index]
		if int(scenario["enemies"]) < 500 or not scenario.has("p95_line_ms") or float(scenario["staffed"]) >= 0.5:
			printerr("TEST FAILED: a horde scenario holds 500+ enemies, mostly swarmers, under a frame line: %s" % [scenario])
			quit(1)
			return
	# A swarmer is the staff enemy's body without its staff: it only chases and touches.
	var imp: EnemyBase = load("res://content/enemies/ember_imp/ember_imp.tres") as EnemyBase
	var swarmer: EnemyBase = RunnerScript.swarm_data(imp)
	if swarmer.staff != null or not swarmer.cards.is_empty() or swarmer.contact_damage <= 0 or swarmer.scene != imp.scene or imp.staff == null:
		printerr("TEST FAILED: the swarmer should be the imp's body with no staff, hurting by touch (and the imp untouched)")
		quit(1)
		return
	runner.set("warm_up", 3.0)
	runner.set("measure", 2.0)
	root.add_child(runner)
