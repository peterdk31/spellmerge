extends "res://tests/support/suite.gd"
## The performance pass's measure (biome_frames_runner.gd): its scenarios are the ones its report
## and the web build expect (every seed at both loads, the wizards together once and apart in each
## split mode, labels unique, the web build only the web's), and it times a viewport only while it
## draws. What a frame costs is the runner's (biome_frames.gd, in a window): headless runs draw
## nothing.

const RunnerScript := preload("res://bench/biome_frames_runner.gd")
const StressScript := preload("res://bench/stress_runner.gd")


func test_every_seed_has_both_loads_together_and_apart_in_each_split() -> void:
	var rows: Array[Dictionary] = RunnerScript.scenario_rows()
	check_equal(rows.size(), RunnerScript.SEEDS.size() * 2 * 3, "three scenarios a seed and load")
	var labels: Dictionary = {}
	for row in rows:
		check(not labels.has(row["label"]), "label %s once" % row["label"])
		labels[row["label"]] = true
	for seed in RunnerScript.SEEDS:
		for load: String in ["desktop", "web"]:
			for want: Array in [["together", SplitScreenSetting.DYNAMIC], ["apart", SplitScreenSetting.DYNAMIC], ["apart", SplitScreenSetting.EQUAL]]:
				var found: int = 0
				for row in rows:
					if int(row["seed"]) == seed and String(row["label"]).contains(load) and row["spread"] == want[0] and int(row["split"]) == int(want[1]):
						found += 1
				check_equal(found, 1, "seed %d %s %s split %d" % [seed, load, want[0], want[1]])


func test_the_web_build_runs_only_the_webs_load() -> void:
	var rows: Array[Dictionary] = RunnerScript.scenario_rows()
	var all: Array[int] = []
	for index in rows.size():
		all.append(index)
	var web: Array[int] = StressScript.scenarios_for(all, true, rows)
	check_equal(web.size(), rows.size() / 2, "half the scenarios on the web")
	for index in web:
		check(String(rows[index]["label"]).contains("web"), "%s is the web's" % rows[index]["label"])


func test_a_viewport_is_timed_only_while_it_draws() -> void:
	var view := own(SubViewport.new()) as SubViewport
	root.add_child(view)
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	check(not RunnerScript._draws(view), "a viewport not drawn keeps its last time: not counted")
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	check(RunnerScript._draws(view), "one drawn every frame is")
	check(RunnerScript._draws(root), "and the root always")
