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
