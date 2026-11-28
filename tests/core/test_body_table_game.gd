extends "res://tests/support/suite.gd"
## The body table on the real game (perf plan change 2, C1; core/actors/README.md, "The body
## table"): a run with two fighter bots, the enemies spawning in, fighting and dying, is checked right
## after the bodies' step of every tick (a step of this test's, joined under the key after the
## bodies'): every open body's row is what its node says, and every other row is empty. Then a fresh
## game restores the run's snapshot: the rows are the restored nodes' at once, and on every tick from
## there. The bodies' step and the ground cover's are the only steps before the check.

const ReplayRun := preload("res://tests/support/replay_run.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const BodyRows := preload("res://tests/support/body_rows.gd")

const TICKS: int = 300
const SNAPSHOT_AT: int = 60
## The checking step's area name (its node is under the root by it, as an area's must be).
const CHECKER: StringName = &"BodyTableCheck"


## The check after the bodies' step, an area of the test's.
class Checker:
	extends Node
	const DERIVED: Array[StringName] = [&"table", &"wrong", &"checked", &"bodies_seen"]
	var table: ActorsScript = null
	var wrong: PackedStringArray = PackedStringArray()
	var checked: int = 0
	var bodies_seen: int = 0

	func check_rows(_delta: float) -> void:
		checked += 1
		var bad: PackedStringArray = BodyRows.rows_wrong(table)
		for line in bad:
			if wrong.size() < 20:
				wrong.append("tick %d: %s" % [checked, line])
		bodies_seen = maxi(bodies_seen, table.open_count())


var _run: ReplayRun
var _checker: Checker


func before_each() -> void:
	_run = ReplayRun.new(tree)
	_run.ticks = TICKS


func after_each() -> void:
	_run.at_snapshot = Callable()
	_run.at_restore = Callable()
	await _run.fresh()
	if _checker != null and is_instance_valid(_checker):
		_checker.free()


## Joins the check to the game's Tick, under the key after the bodies'.
func _join() -> void:
	if _checker == null or not is_instance_valid(_checker):
		_checker = Checker.new()
		_checker.name = String(CHECKER)
		root.add_child(_checker)
	_checker.table = root.get_node("Actors") as ActorsScript
	SimArea.join(_checker, CHECKER).steps(&"Cover", _checker.check_rows).fresh_because("a test's check, reading only")


func test_the_rows_follow_the_bodies_through_a_fight_and_a_restore() -> void:
	_run.snapshot_at = SNAPSHOT_AT
	_run.at_snapshot = _join
	var replay: Replay = await _run.record(&"play_requested", 2, 0, Desync.new())
	check(replay != null and _run.snapshot != null, "recorded with its snapshot")
	if replay == null or _run.snapshot == null:
		return
	check(_checker.checked >= TICKS - SNAPSHOT_AT - 5, "checked every tick after the snapshot (%d)" % _checker.checked)
	check(_checker.bodies_seen >= 4, "bodies in play: %d" % _checker.bodies_seen)
	check_equal(_checker.wrong, PackedStringArray(), "the recorded run's rows")
	var restored_wrong: Array[PackedStringArray] = []
	_run.at_restore = func() -> void:
		restored_wrong.append(BodyRows.rows_wrong(root.get_node("Actors") as ActorsScript))
		_checker.wrong.clear()
		_checker.checked = 0
		_join()
	await _run.resume(replay, _run.snapshot, SNAPSHOT_AT, 2, Desync.new())
	for problem in _run.problems:
		check(false, problem)
	check_equal(restored_wrong.size(), 1, "restored once")
	if restored_wrong.size() == 1:
		check_equal(restored_wrong[0], PackedStringArray(), "the rows right after the restore")
	check(_checker.checked >= TICKS - SNAPSHOT_AT - 5, "checked every tick after the restore (%d)" % _checker.checked)
	check_equal(_checker.wrong, PackedStringArray(), "the resumed run's rows")
