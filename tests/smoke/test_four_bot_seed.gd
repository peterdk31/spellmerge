extends "res://tests/support/suite.gd"
## The 4-bot smoke test plays the same run on every start (tests/smoke/four_bot_runner.gd,
## "Reproducibility"). Regression: it started its run with Play alone, so every start took a random
## run seed (`SimSeed.fresh`) and about one start in eleven played a fight the bots lose; the test
## failed by chance ("player 3 is down at the end") and passed again on a rerun. Now the runner
## records its run with the replay seed REPLAY_SEED, which deals the run's seed: the same seed, so
## the same map and rolls, on every start. `--replay-seed=N` plays another. Since 2026-11-20 the
## runner records the hub, which takes the first seed dealt, and the run from the stone the second.

const RunnerScript := preload("res://tests/smoke/four_bot_runner.gd")
const TickScript := preload("res://core/sim/tick.gd")


## A runner started on the root, as four_bot_smoke.gd starts it, and stopped again; returns the
## seed its hub got (-1 with no Tick autoload).
func _run_seed_of_a_start() -> int:
	var tick: TickScript = root.get_node_or_null(^"Tick") as TickScript
	check(tick != null, "the Tick autoload is missing")
	var runner: Node = RunnerScript.new()
	root.add_child(runner)
	var seed_now: int = tick.sim.run_seed if tick != null else -1
	runner.call("stop")
	runner.free()
	return seed_now


## The run seed a replay of seed `of` deals to the `nth` run it starts (1: the first).
func _dealt(of: int, nth: int = 1) -> int:
	var replay := Replay.new()
	replay.run_seed = of
	var tape: ReplayTape = ReplayTape.recording(replay)
	var dealt: int = 0
	for _i in nth:
		dealt = tape.next_run_seed()
	return dealt


func test_a_start_plays_the_hub_seed_the_replay_seed_deals() -> void:
	check_equal(_run_seed_of_a_start(), _dealt(RunnerScript.REPLAY_SEED), "the hub's seed is not the one REPLAY_SEED deals")


## The run the bots fight (from the hub's stone) plays the replay's second seed: the review of
## 2026-11-20 (a stone's run with a seed of its own would have passed the hub's check above).
func test_the_run_from_the_stone_plays_the_replay_seeds_second() -> void:
	var runner: Node = RunnerScript.new()
	root.add_child(runner)
	for _frame in 1200:
		if bool(runner.call("in_run")):
			break
		await physics_frame
	var started: bool = bool(runner.call("in_run"))
	var got: int = int(runner.call("run_seed"))
	runner.call("stop")
	runner.free()
	check(started, "the bots started the run from the hub's stone")
	check_equal(got, _dealt(RunnerScript.REPLAY_SEED, 2), "the run's seed is not the second REPLAY_SEED deals")


func test_two_starts_play_the_same_run_seed() -> void:
	var first: int = _run_seed_of_a_start()
	var second: int = _run_seed_of_a_start()
	check_equal(second, first, "a second start played another run seed")


func test_the_recording_ends_with_the_run() -> void:
	_run_seed_of_a_start()
	var frames: Node = root.get_node_or_null(^"Frames")
	check(frames != null and not bool(frames.call("is_recording")), "the runner left the frames service recording")


func test_freeing_the_runner_gives_back_its_seats_and_recording() -> void:
	var runner: Node = RunnerScript.new()
	root.add_child(runner)
	runner.free()
	var flow: Node = root.get_node_or_null(^"Flow")
	if flow != null:
		flow.call("stop_run")
	var frames: Node = root.get_node_or_null(^"Frames")
	check(frames != null and not bool(frames.call("is_recording")), "a freed runner left the frames service recording")
	check(frames != null and frames.call("source_of", 0) == null, "a freed runner left a bot filling seat 1's frames")


func test_no_argument_plays_the_replay_seed() -> void:
	check_equal(RunnerScript.replay_seed_of(PackedStringArray()), RunnerScript.REPLAY_SEED, "no argument")
	check_equal(RunnerScript.replay_seed_of(PackedStringArray(["--four-bot", "--other=3"])), RunnerScript.REPLAY_SEED, "unrelated arguments")


func test_the_argument_plays_its_seed() -> void:
	check_equal(RunnerScript.replay_seed_of(PackedStringArray(["--four-bot", "--replay-seed=3"])), 3, "--replay-seed=N")
	check_equal(RunnerScript.replay_seed_of(PackedStringArray(["--replay-seed=0"])), 0, "--replay-seed=0 (a random one)")


func test_a_value_that_is_no_seed_plays_the_replay_seed() -> void:
	check_equal(RunnerScript.replay_seed_of(PackedStringArray(["--replay-seed=three"])), RunnerScript.REPLAY_SEED, "a word is no seed")
