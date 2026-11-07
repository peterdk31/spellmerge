extends "res://tests/support/suite.gd"
## Determinism on the real game, through a replay (online-ready N2, docs/milestones/online-ready.md):
## a run on the real autoloads (Flow, Coop, the wizards' PlayerControllers, the spell runtime, the
## projectile manager, Combat, the AI) is recorded by the Frames autoload, and the replay played
## back from the same start gives the same state hash in every area at every tick. When they part,
## the desync report names the first tick, the areas and each differing member.
##
## The runs (a scripted player in the sandbox, a wave of two bots, a horde run of a bot), how each
## starts from a fresh game and what is held to the tick until N3 and N4 are in
## tests/support/replay_run.gd, which the platform runner (N2b) shares.
##
## Each run takes seconds: the runner plays them in processes of their own (tests/support/suite.gd):
# unit-test-shards: 6

const ReplayRun := preload("res://tests/support/replay_run.gd")

## Ticks recorded and played (four seconds of game).
const TICKS: int = 240

var _run: ReplayRun


func before_each() -> void:
	_run = ReplayRun.new(self)
	_run.ticks = TICKS


func after_each() -> void:
	await _run.fresh()


func test_a_scripted_sandbox_run_replays_tick_for_tick() -> void:
	await _check_replay(&"sandbox_requested", 0, 1)


func test_a_wave_of_bots_replays_tick_for_tick() -> void:
	await _check_replay(&"play_requested", 2, 0)


func test_a_horde_run_of_a_bot_replays_tick_for_tick() -> void:
	await _check_replay(&"horde_requested", 1, 0)


## A run starts from a fresh game's state (online-ready N3b): a replay recorded in a fresh game
## plays the same after other runs in the same game, and a run recorded after other runs plays the
## same as the one recorded fresh (the same frames and seed). The other runs between use what the
## run does not (a horde's swarm and director, a wave's AI), and every service's clocks, counters,
## pools and slots. Without `Tick.begin_run` the runs part at tick 0.
func test_a_sandbox_replay_plays_the_same_after_other_runs() -> void:
	await _check_after_other_runs(&"sandbox_requested", 0, 1, [&"horde_requested", &"play_requested"])


func test_a_horde_replay_plays_the_same_after_other_runs() -> void:
	await _check_after_other_runs(&"horde_requested", 1, 0, [&"sandbox_requested", &"horde_requested"])


## The run started by `start` with `bots` bots and `scripted` scripted players, recorded fresh,
## played after `others[0]`, and recorded again after `others[1]`: all three agree at every tick.
func _check_after_other_runs(start: StringName, bots: int, scripted: int, others: Array[StringName]) -> void:
	var runs: Array[Desync] = await _after_other_runs(start, bots, scripted, others, -1)
	for problem in _run.problems:
		check(false, problem)
	check_equal(runs[1].hashes.size(), TICKS, "%s: the replay after other runs played every tick" % start)
	var what: Array[String] = ["", "a replay played after other runs plays as recorded", "a run recorded after other runs plays as one recorded fresh"]
	for at in [1, 2]:
		var tick: int = Desync.first_parting(runs[0], runs[at])
		if tick < 0:
			continue
		# Again, keeping the parting tick's leaves, so the report names the members.
		var again: Array[Desync] = await _after_other_runs(start, bots, scripted, others, tick)
		check_equal(Desync.compare(again[0], again[at]), "", "%s: %s" % [start, what[at]])


## The run recorded in a fresh game; the first other run; its replay played in the same game (its
## bots watching); the second other run; the run recorded again in the same game. The hashes of the
## first, the replay and the last, keeping tick `keep`'s leaves.
func _after_other_runs(start: StringName, bots: int, scripted: int, others: Array[StringName], keep: int) -> Array[Desync]:
	_run.run_seed = 0x5eed
	_run.fresh_game = true
	var fresh := Desync.new(keep)
	var replay: Replay = await _run.record(start, bots, scripted, fresh)
	_run.fresh_game = false
	await _other_run(others[0])
	var played := Desync.new(keep)
	if replay != null:
		await _run.play(replay, bots, played)
	await _other_run(others[1])
	var late := Desync.new(keep)
	await _run.record(start, bots, scripted, late)
	_run.fresh_game = true
	return [fresh, played, late]


## A run of two fighter bots started by `start`, half as long, for its leftovers only (its own
## seed: another game than the one replayed).
func _other_run(start: StringName) -> void:
	var seed_before: int = _run.run_seed
	_run.run_seed = 0x0dd
	_run.ticks = TICKS / 2
	await _run.record(start, 2, 0, Desync.new())
	_run.ticks = TICKS
	_run.run_seed = seed_before


## A run plays by its rules (online-ready N11, core/sim/session_rules.gd): a replay recorded on a
## machine whose "Max shots" is 750, with a seat moving it to 500 mid-run, plays to the same hashes
## at every tick on a machine whose own cap is 6,000; the run's cap is the replay's, then the
## command's, and the machine keeps its own.
func test_a_replay_plays_by_its_rules_on_a_machine_with_other_settings() -> void:
	_run.cap = 750
	_run.cap_request = Vector2i(120, 500)
	var recorded := Desync.new()
	var replay: Replay = await _run.record(&"sandbox_requested", 0, 1, recorded)
	check(replay != null and replay.rules.shot_cap == 750, "the replay carries the run's cap")
	if replay == null:
		return
	var game: Sim = root.get_node("Tick").get(&"sim") as Sim
	check_equal(game.rules.shot_cap, 500, "the seat's request applied in the run")
	var asked: bool = false
	var frames: Array[InputFrame] = []
	for seat in 4:
		frames.append(InputFrame.new())
	for tick in replay.tick_count():
		replay.read_tick(tick, frames)
		for command in frames[0].commands:
			asked = asked or (command[0] == &"shot_cap_requested" and command[1] == 500)
	check(asked, "the request is in the replay, at its tick")
	_run.cap = 6000
	_run.cap_request = Vector2i(-1, 0)
	var played := Desync.new()
	await _run.play(Replay.from_bytes(replay.to_bytes()), 0, played)
	for problem in _run.problems:
		check(false, problem)
	check_equal(played.hashes.size(), TICKS, "the replay played every tick")
	check_equal(Desync.first_parting(recorded, played), -1, "it plays as recorded, on this machine's other cap")
	game = root.get_node("Tick").get(&"sim") as Sim
	check_equal(game.rules.shot_cap, 500, "the run's cap, not this machine's")
	check_equal(SessionRules.machine().shot_cap, 6000, "the machine keeps its own")


## A replay of other content is not played.
func test_a_replay_of_other_content_is_refused() -> void:
	var frames: Node = root.get_node("Frames")
	var replay := Replay.new()
	replay.content = 12345
	check(not bool(frames.call("play", replay)), "refused")
	check(not bool(frames.call("is_playing")), "nothing plays")


## A run started by `start` with `bots` fighter bots and `scripted` scripted players (seats in that
## order), recorded and played back; the hashes must agree at every tick.
func _check_replay(start: StringName, bots: int, scripted: int) -> void:
	var recorded := Desync.new()
	var replay: Replay = await _run.record(start, bots, scripted, recorded)
	check(replay != null and replay.tick_count() == TICKS, "%s: the replay holds every tick (%d)" % [start, replay.tick_count() if replay != null else -1])
	if replay == null:
		return
	if scripted > 0:
		check(ReplayRun.has_command(replay), "%s: the rebuild is in the replay" % start)
	# Through its bytes, as a file would carry it.
	var again: Replay = Replay.from_bytes(replay.to_bytes())
	check(again != null, "%s: the replay reads back from its bytes" % start)
	if again == null:
		return
	var played := Desync.new()
	await _run.play(again, bots, played)
	for problem in recorded.problems:
		check(false, "%s: %s" % [start, problem])
	for problem in _run.problems:
		check(false, problem)
	check_equal(played.hashes.size(), TICKS, "%s: the replay played every tick" % start)
	var tick: int = Desync.first_parting(recorded, played)
	if tick < 0:
		return
	# Again, keeping the parting tick's leaves, so the report names the members.
	var recorded2 := Desync.new(tick)
	var replay2: Replay = await _run.record(start, bots, scripted, recorded2)
	var played2 := Desync.new(tick)
	await _run.play(replay2, bots, played2)
	check(false, "%s: the replay parts from the run it recorded: %s" % [start, Desync.compare(recorded2, played2)])
