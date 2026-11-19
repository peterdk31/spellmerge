extends "res://tests/support/suite.gd"
## The 4-bot smoke test plays the same run on every start (tests/smoke/four_bot_runner.gd,
## "Reproducibility"). Regression: it started its run with Play alone, so every start took a random
## run seed (`SimSeed.fresh`) and about one start in ten played a fight the bots lose a fighter in;
## the test failed by chance ("player 3 is down at the end") and passed again on a rerun. Now the
## runner records its run with the replay seed RUN_SEED, which deals the run's seed: the same
## seed, so the same map and rolls, on every start. `--run-seed=N` plays another.

const RunnerScript := preload("res://tests/smoke/four_bot_runner.gd")
const TickScript := preload("res://core/sim/tick.gd")


## A runner started on the root, as four_bot_smoke.gd starts it; returns the run seed it got.
func _run_seed_of_a_start() -> int:
	var runner: Node = RunnerScript.new()
	root.add_child(runner)
	var tick: TickScript = root.get_node_or_null(^"Tick") as TickScript
	var seed_now: int = tick.sim.run_seed if tick != null else 0
	runner.call("stop")
	runner.free()
	return seed_now


## The run seed the replay seed `of` deals to the first run it starts (`ReplayTape.next_run_seed`).
func _dealt(of: int) -> int:
	var dealer := RandomNumberGenerator.new()
	dealer.seed = of
	return dealer.randi()


func test_a_start_plays_the_run_seed_run_seed_deals() -> void:
	check_equal(_run_seed_of_a_start(), _dealt(RunnerScript.RUN_SEED), "the run seed is not the one RUN_SEED deals")


func test_two_starts_play_the_same_run_seed() -> void:
	var first: int = _run_seed_of_a_start()
	var second: int = _run_seed_of_a_start()
	check_equal(second, first, "a second start played another run seed")


func test_the_recording_ends_with_the_run() -> void:
	_run_seed_of_a_start()
	var frames: Node = root.get_node_or_null(^"Frames")
	check(frames != null and not bool(frames.call("is_recording")), "the runner left the frames service recording")


func test_no_argument_plays_run_seed() -> void:
	check_equal(RunnerScript.run_seed_of(PackedStringArray()), RunnerScript.RUN_SEED, "no argument")
	check_equal(RunnerScript.run_seed_of(PackedStringArray(["--four-bot", "--other=3"])), RunnerScript.RUN_SEED, "unrelated arguments")


func test_the_argument_plays_its_seed() -> void:
	check_equal(RunnerScript.run_seed_of(PackedStringArray(["--four-bot", "--run-seed=1282583244"])), 1282583244, "--run-seed=N")
	check_equal(RunnerScript.run_seed_of(PackedStringArray(["--run-seed=0"])), 0, "--run-seed=0 (a random one)")


func test_a_value_that_is_no_seed_plays_run_seed() -> void:
	check_equal(RunnerScript.run_seed_of(PackedStringArray(["--run-seed=three"])), RunnerScript.RUN_SEED, "a word is no seed")
