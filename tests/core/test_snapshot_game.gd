extends "res://tests/support/suite.gd"
## Snapshots on the real game (online-ready N10, core/sim/snapshot.gd): a run on the real autoloads
## (Flow, Coop, the wizards' PlayerControllers, the spell runtime, the projectile manager, Combat,
## the AI) is recorded with a snapshot after one of its ticks; a fresh game then starts
## the replay's run, restores the snapshot and plays the replay's frames on from the next tick, as a
## player joining the run online would. Every tick from there agrees with the recorded run's in every
## area. When they part, the desync report names the first tick, the areas and each member.
##
## Every room the registry finds that holds a wave (it has enemy spawns) plays one so (online-ready
## N12): a new room is covered the day its folder lands, with no test written for it. The hub holds
## none; its own start is resumed from a snapshot on its stone. Cards and enemies are covered the same way, in a
## scripted fight each (tests/core/test_content_determinism.gd).
##
## The runs are the replay test's (tests/support/replay_run.gd). Each takes seconds: the runner plays
## them in processes of their own (tests/support/suite.gd):
# unit-test-shards: 3

const ReplayRun := preload("res://tests/support/replay_run.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

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


## A wave in every room the registry finds, with a scripted player, not bots: a bot reads the game
## through queries that fill the services' caches, which count as state (core/sim/README.md,
## "Input"), so a run of bots goes on the same only with the same bots watching from the same state.
## A player joining a run never runs the host's bots; its frames come from the host.
func test_a_wave_in_every_room_restored_plays_on_the_same() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var rooms: Array[StringName] = []
	for id: StringName in registry.get_ids(&"rooms"):
		# A room with no enemy spawns holds no wave (the hub: its own test below).
		if not (registry.get_resource(&"rooms", id) as RoomBase).places().enemy_spawns.is_empty():
			rooms.append(id)
	check(rooms.size() >= 2, "it finds the rooms (%d)" % rooms.size())
	for room in rooms:
		_run.room = room
		await _check_resumed(&"play_requested", 0, 1)


## The hub (online-lobby L1), snapshot while its player stands on the lit stone, resumed: the
## resumed game starts the run of waves on the same tick (the press after the snapshot) and plays on
## the same.
func test_the_hub_restored_starts_its_run_on_the_same_tick() -> void:
	_run.stone_press_at = SNAPSHOT_AT + 20
	await _check_resumed(&"hub_requested", 0, 1)
	_run.stone_press_at = -1
	check_equal(root.get_node("Flow").get(&"mode"), &"waves", "the resumed game started the run from the stone")


## A run started by `start` with `bots` fighter bots and `scripted` scripted players, recorded with a
## snapshot after SNAPSHOT_AT, then resumed from it in a fresh game: the two agree from there on.
func _check_resumed(start: StringName, bots: int, scripted: int) -> void:
	var label: String = start if _run.room == &"" else "%s in %s" % [start, _run.room]
	var recorded := Desync.new()
	var resumed := Desync.new()
	var replay: Replay = await _record(start, bots, scripted, recorded)
	if replay == null:
		return
	var snapshot: Snapshot = _run.snapshot
	for problem in snapshot.problems:
		check(false, "%s: %s" % [label, problem])
	await _run.resume(replay, snapshot, SNAPSHOT_AT, bots, resumed)
	for problem in _run.problems:
		check(false, problem)
	_run.problems.clear()
	check_equal(resumed.hashes.size(), TICKS - SNAPSHOT_AT - 1, "%s: the resumed run played every tick after the snapshot" % label)
	var tick: int = Desync.first_parting(recorded, resumed)
	if tick < 0:
		return
	# Again, keeping the parting tick's leaves, so the report names the members.
	var recorded2 := Desync.new(SNAPSHOT_AT + 1 + tick)
	var resumed2 := Desync.new(tick)
	replay = await _record(start, bots, scripted, recorded2)
	await _run.resume(replay, _run.snapshot, SNAPSHOT_AT, bots, resumed2)
	check(false, "%s: the run resumed from its snapshot parts from it %d ticks after: %s" % [label, tick + 1, Desync.compare(recorded2, resumed2)])


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
