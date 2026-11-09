extends "res://tests/support/suite.gd"
## Snapshots on the real game (online-ready N10, core/sim/snapshot.gd): a run on the real autoloads
## (Flow, Coop, the wizards' PlayerControllers, the spell runtime, the projectile manager, Combat,
## the AI) is recorded with a snapshot after one of its ticks; a fresh game then starts
## the replay's run, restores the snapshot and plays the replay's frames on from the next tick, as a
## player joining the run online would. Every tick from there agrees with the recorded run's in every
## area. When they part, the desync report names the first tick, the areas and each member.
##
## The runs are the replay test's (tests/support/replay_run.gd). Each takes seconds: the runner plays
## them in processes of their own (tests/support/suite.gd):
# unit-test-shards: 3

const ReplayRun := preload("res://tests/support/replay_run.gd")

## Ticks recorded, and the tick the snapshot is taken after (past the scripted player's rebuild and
## pause in the sandbox, so the frames after it hold neither).
const TICKS: int = 260
const SNAPSHOT_AT: int = 180
const RUN_SEED: int = 0x5eed

var _run: ReplayRun


func before_each() -> void:
	_run = ReplayRun.new(self)
	_run.ticks = TICKS
	# One seed, so a run recorded again for the report is the same run.
	_run.run_seed = RUN_SEED


func after_each() -> void:
	await _run.fresh()


func test_a_sandbox_run_restored_plays_on_the_same() -> void:
	await _check_resumed(&"sandbox_requested", 0, 1)


## The wave with a scripted player, not bots: a bot reads the game through queries
## that fill the services' caches, which count as state (core/sim/README.md, "Input"), so a run of
## bots goes on the same only with the same bots watching from the same state. A player joining a
## run never runs the host's bots; its frames come from the host.
func test_a_wave_restored_plays_on_the_same() -> void:
	await _check_resumed(&"play_requested", 0, 1)


## A run started by `start` with `bots` fighter bots and `scripted` scripted players, recorded with a
## snapshot after SNAPSHOT_AT, then resumed from it in a fresh game: the two agree from there on.
func _check_resumed(start: StringName, bots: int, scripted: int) -> void:
	var recorded := Desync.new()
	var resumed := Desync.new()
	var replay: Replay = await _record(start, bots, scripted, recorded)
	if replay == null:
		return
	var snapshot: Snapshot = _run.snapshot
	for problem in snapshot.problems:
		check(false, "%s: %s" % [start, problem])
	await _run.resume(replay, snapshot, SNAPSHOT_AT, bots, resumed)
	for problem in _run.problems:
		check(false, problem)
	_run.problems.clear()
	check_equal(resumed.hashes.size(), TICKS - SNAPSHOT_AT - 1, "%s: the resumed run played every tick after the snapshot" % start)
	var tick: int = Desync.first_parting(recorded, resumed)
	if tick < 0:
		return
	# Again, keeping the parting tick's leaves, so the report names the members.
	var recorded2 := Desync.new(SNAPSHOT_AT + 1 + tick)
	var resumed2 := Desync.new(tick)
	replay = await _record(start, bots, scripted, recorded2)
	await _run.resume(replay, _run.snapshot, SNAPSHOT_AT, bots, resumed2)
	check(false, "%s: the run resumed from its snapshot parts from it %d ticks after: %s" % [start, tick + 1, Desync.compare(recorded2, resumed2)])


## The run recorded with its snapshot; `into` keeps the ticks after the snapshot only, as the
## resumed run's.
func _record(start: StringName, bots: int, scripted: int, into: Desync) -> Replay:
	_run.snapshot_at = SNAPSHOT_AT
	var replay: Replay = await _run.record(start, bots, scripted, into)
	check(replay != null and _run.snapshot != null, "%s: the run was recorded with its snapshot" % start)
	into.hashes = into.hashes.slice(SNAPSHOT_AT + 1)
	if into.keep_tick >= 0:
		into.keep_tick -= SNAPSHOT_AT + 1
	return replay if _run.snapshot != null else null
