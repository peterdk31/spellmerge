extends "res://tests/support/suite.gd"
## A room whose enemies come in groups, snapshotted and resumed (enemy spawning EA5,
## docs/milestones/enemy-spawning.md, "Tests that need a look"): a run of the arena paced in groups of
## half its budget (tests/support/replay_run.gd, pinned with `spawning`), recorded with a snapshot
## early, while the first group is still rippling in (the restored queue starts its next bodies) and
## later groups wait, and later, between groups (the first group in, the next held: the scripted
## player kills nothing, so the restored queue must keep holding it); a fresh game restores the
## snapshot and plays the replay on from the next tick, and every tick from there agrees with the
## recorded run's (Flow's queue, `RoomSpawning`, is state saved in snapshots). A group's start from
## a quiet room is the pure rules' and the flow tests' (test_room_spawning.gd, test_flow_spawning.gd).
# unit-test-shards: 2

const ReplayRun := preload("res://tests/support/replay_run.gd")
const ARENA: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")

const TICKS: int = 200

var _run: ReplayRun
## What the snapshot caught: ids still to come, and bodies spawning.
var _left: int = -1
var _spawning: int = -1
## Ids still to come at the recorded run's end, and at the restored run's.
var _left_after: int = -1
var _left_restored: int = -1


func before_each() -> void:
	_run = ReplayRun.new(tree)
	_run.ticks = TICKS
	_run.run_seed = 0x5eed
	var pace := SpawnRules.new()
	pace.group_share = 0.5
	pace.refill_share = 0.0
	pace.stagger = 0.3
	_run.room = ARENA
	_run.spawning = pace
	_run.at_snapshot = _caught
	_left = -1
	_spawning = -1


func after_each() -> void:
	_run.room = null
	_run.spawning = null
	_run.at_snapshot = Callable()
	await _run.fresh()


func _caught() -> void:
	var flow: Node = root.get_node("Flow")
	_left = int((flow.get(&"spawn_queue") as RoomSpawning).left())
	_spawning = 0
	for enemy: Node in flow.get(&"_enemies") as Array[Node]:
		if is_instance_valid(enemy) and (enemy as Actor).is_spawning():
			_spawning += 1


func test_a_snapshot_mid_spawn_with_groups_to_come_plays_on_the_same() -> void:
	await _check_resumed(4)
	check(_left > 0, "the snapshot caught groups still to come: %d" % _left)
	check(_spawning > 0, "and a body spawning: %d" % _spawning)
	check(_left_after >= 0 and _left_after < _left, "the group's ripple went on after it: %d then %d to come" % [_left, _left_after])
	check_equal(_left_restored, _left_after, "in the restored game too")


func test_a_snapshot_between_groups_plays_on_the_same() -> void:
	await _check_resumed(120)
	check(_left > 0, "the snapshot caught groups still to come: %d" % _left)
	check_equal(_left_after, _left, "the next group held to the end, as nothing was killed")
	check_equal(_left_restored, _left, "in the restored game too")


## The run recorded with a snapshot after tick `at`, resumed from it in a fresh game: the two agree.
func _check_resumed(at: int) -> void:
	var recorded := Desync.new()
	_run.snapshot_at = at
	var replay: Replay = await _run.record(&"play_requested", 0, 1, recorded)
	_left_after = int((root.get_node("Flow").get(&"spawn_queue") as RoomSpawning).left())
	check(replay != null and _run.snapshot != null, "recorded with its snapshot")
	if replay == null or _run.snapshot == null:
		return
	for problem in _run.snapshot.problems:
		check(false, "the snapshot: %s" % problem)
	recorded.hashes = recorded.hashes.slice(at + 1)
	var resumed := Desync.new()
	await _run.resume(replay, _run.snapshot, at, 0, resumed)
	_left_restored = int((root.get_node("Flow").get(&"spawn_queue") as RoomSpawning).left())
	for problem in _run.problems:
		check(false, problem)
	_run.problems.clear()
	check_equal(resumed.hashes.size(), TICKS - at - 1, "the resumed run played every tick after the snapshot")
	var tick: int = Desync.first_parting(recorded, resumed)
	check(tick < 0, "the resumed run parts from the recorded one %d ticks after the snapshot" % (tick + 1))
