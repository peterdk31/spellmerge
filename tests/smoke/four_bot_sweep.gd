extends SceneTree
## The seed sweep: a balance signal, never a gate. It plays the 4-bot smoke test's run
## (tests/smoke/four_bot_runner.gd, the same checks) for many replay seeds, one after another in
## this one process, each on a fresh game (`FreshGame.restart`, as the suites' host does between
## files), and prints which seeds the bots lose and the loss rate. It always quits with 0: a lost
## seed is a number to watch, not a failure. No build runs it.
##
##   godot --headless --fixed-fps 60 --path . --script res://tests/smoke/four_bot_sweep.gd -- --seeds=1-40
##
## `--seeds=A-B` plays replay seeds A to B (both in, either way round; DEFAULT_FIRST to DEFAULT_LAST without it), and
## `--seeds=3,11,17` those seeds. A lost seed is played again alone with the smoke test's own
## argument (`four_bot_smoke.gd -- --replay-seed=N`), which prints why. The lines it prints:
##   SWEEP seed 7: won (run seed 123...)
##   SWEEP seed 9: LOST (run seed 456...): player 2 is down at the end (and was not revived)
##   SWEEP RESULT: 3 of 40 seeds lost (7.5%): 9, 21, 33

const RunnerScript := preload("res://tests/smoke/four_bot_runner.gd")
const FreshGameScript := preload("res://tests/support/fresh_game.gd")

const SEEDS_ARGUMENT: String = "--seeds="
const DEFAULT_FIRST: int = 1
const DEFAULT_LAST: int = 40

var _done: bool = false
var _failures: Array[String] = []
var _run_seed: int = 0


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	var seeds: PackedInt64Array = seeds_of(OS.get_cmdline_user_args())
	var lost: PackedStringArray = PackedStringArray()
	for at in seeds.size():
		if at > 0:
			await _fresh_game()
		var replay_seed: int = seeds[at]
		await _play(replay_seed)
		if _failures.is_empty():
			print("SWEEP seed %d: won (run seed %d)" % [replay_seed, _run_seed])
		else:
			lost.append(str(replay_seed))
			print("SWEEP seed %d: LOST (run seed %d): %s" % [replay_seed, _run_seed, "; ".join(_failures)])
	print(result_line(seeds.size(), lost))
	quit(0)


## The replay seeds `args` ask for (`--seeds=A-B` or `--seeds=A,B,C`; DEFAULT_FIRST to DEFAULT_LAST
## without, or with a value it cannot read). Seeds are 1 or more (0 would be a random one).
static func seeds_of(args: PackedStringArray) -> PackedInt64Array:
	var out: PackedInt64Array = PackedInt64Array()
	for arg in args:
		if not arg.begins_with(SEEDS_ARGUMENT):
			continue
		var value: String = arg.trim_prefix(SEEDS_ARGUMENT)
		var ends: PackedStringArray = value.split("-")
		if ends.size() == 2 and ends[0].is_valid_int() and ends[1].is_valid_int():
			var low: int = mini(ends[0].to_int(), ends[1].to_int())
			var high: int = maxi(ends[0].to_int(), ends[1].to_int())
			for seed_value in range(maxi(low, 1), high + 1):
				out.append(seed_value)
		else:
			for part in value.split(","):
				if part.is_valid_int() and part.to_int() >= 1:
					out.append(part.to_int())
	if out.is_empty():
		for seed_value in range(DEFAULT_FIRST, DEFAULT_LAST + 1):
			out.append(seed_value)
	return out


## The summary line: how many of `played` seeds were lost, the rate, and which.
static func result_line(played: int, lost: PackedStringArray) -> String:
	var rate: float = 100.0 * float(lost.size()) / float(maxi(played, 1))
	return "SWEEP RESULT: %d of %d seeds lost (%.1f%%)%s" % [lost.size(), played, rate, (": " + ", ".join(lost)) if not lost.is_empty() else ""]


## One run of `replay_seed`, to its end.
func _play(replay_seed: int) -> void:
	_done = false
	_failures = []
	var runner: Node = RunnerScript.new()
	runner.set("replay_seed_wanted", replay_seed)
	runner.set("standalone", false)
	runner.connect("finished", _on_finished)
	root.add_child(runner)
	while not _done:
		await process_frame
	runner.queue_free()
	await process_frame


func _on_finished(failures: Array[String], _replay_seed: int, run_seed: int) -> void:
	_failures = failures.duplicate()
	_run_seed = run_seed
	_done = true


## What the last run left is cleared and every autoload made again (tests/support/run.gd does the
## same between suite files).
func _fresh_game() -> void:
	paused = false
	current_scene = null
	var names: Array[String] = []
	for info: Dictionary in ProjectSettings.get_property_list():
		var key: String = info["name"]
		if key.begins_with("autoload/"):
			names.append(key.trim_prefix("autoload/"))
	for child: Node in root.get_children():
		if not names.has(String(child.name)):
			root.remove_child(child)
			child.free()
	Engine.time_scale = 1.0
	InputMap.load_from_project_settings()
	FreshGameScript.restart(root)
	await process_frame
