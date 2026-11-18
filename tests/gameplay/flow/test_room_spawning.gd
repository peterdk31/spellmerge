extends "res://tests/support/suite.gd"
## A room's groups as pure rules (enemy spawning EA5, docs/milestones/enemy-spawning.md, "Pacing";
## `RoomSpawning`, no world): group sizes by cost, an enemy dearer than a group still coming, the
## next group only when the room gets quiet (and never while it is busy, however long), the bodies of
## a group a stagger apart, a pace of 0 the whole list at once, and the far-from-wizards spawn pick.

const STEP: float = 1.0 / 60.0


## What each id of the test's list costs (`_begin`).
var _cost: Dictionary = {}


func _ids(count: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	for at in count:
		ids.append(StringName("e%d" % at))
	return ids


## `spawning` begun on ids e0, e1, ... costing `costs`, at the pace given.
func _begin(spawning: RoomSpawning, costs: Array[int], group: int, refill: int, stagger: float) -> void:
	_cost.clear()
	var ids: Array[StringName] = _ids(costs.size())
	for at in ids.size():
		_cost[ids[at]] = costs[at]
	spawning.begin(ids, PackedInt32Array(costs), group, refill, stagger)


## Every id `spawning` gives at once with `standing` cost standing, as Flow asks (`delta`, then 0s),
## each one stood adding its cost to what stands.
func _all_now(spawning: RoomSpawning, delta: float, standing: int) -> Array[StringName]:
	var got: Array[StringName] = []
	var id: StringName = spawning.next(delta, standing)
	while id != &"":
		got.append(id)
		standing += int(_cost.get(id, 0))
		id = spawning.next(0.0, standing)
	return got


func test_a_group_takes_ids_until_its_cost_reaches_the_group() -> void:
	var spawning := RoomSpawning.new()
	_begin(spawning, [2, 2, 2, 2, 3, 1] as Array[int], 6, 0, 0.0)
	check_equal(_all_now(spawning, 0.0, 0), [&"e0", &"e1", &"e2"] as Array[StringName], "2 + 2 + 2 reach the group of 6")
	check_equal(_all_now(spawning, STEP, 6), [] as Array[StringName], "nothing more while the room is busy")
	check_equal(_all_now(spawning, STEP, 0), [&"e3", &"e4", &"e5"] as Array[StringName], "the next group: 2 + 3 + 1")
	check(spawning.is_done(), "the list is used up")
	check_equal(spawning.next(STEP, 0), &"", "and gives nothing more")


func test_an_enemy_dearer_than_a_group_still_comes_alone() -> void:
	var spawning := RoomSpawning.new()
	_begin(spawning, [9, 1, 1] as Array[int], 4, 1, 0.0)
	check_equal(_all_now(spawning, 0.0, 0), [&"e0"] as Array[StringName], "the 9 comes, alone")
	check_equal(_all_now(spawning, STEP, 9), [] as Array[StringName], "the room is busy")
	check_equal(_all_now(spawning, STEP, 1), [&"e1", &"e2"] as Array[StringName], "quiet: the rest")


## The quiet trigger: at `refill_at` or below the next group comes; above it never does, however long.
func test_the_next_group_comes_only_when_the_room_gets_quiet() -> void:
	var spawning := RoomSpawning.new()
	_begin(spawning, [2, 2, 2, 2] as Array[int], 4, 2, 0.0)
	check_equal(_all_now(spawning, 0.0, 0).size(), 2, "the first group")
	var waited: int = 0
	for at in 60 * 600:
		waited += _all_now(spawning, STEP, 3).size()
	check_equal(waited, 0, "ten minutes with 3 standing (above 2): no group")
	check_equal(spawning.left(), 2, "both still to come")
	check_equal(_all_now(spawning, STEP, 2).size(), 2, "2 standing: the next group")


func test_a_group_ripples_in_by_its_stagger() -> void:
	var spawning := RoomSpawning.new()
	_begin(spawning, [1, 1, 1] as Array[int], 3, 0, 0.1)
	check_equal(_all_now(spawning, 0.0, 0).size(), 1, "the first body at once")
	var ticks: Array[int] = []
	for tick in 30:
		if not _all_now(spawning, STEP, 1).is_empty():
			ticks.append(tick)
	check_equal(ticks.size(), 2, "the other two come")
	if ticks.size() == 2:
		check(ticks[0] >= 4 and ticks[0] <= 6, "the second about 0.1 s after: tick %d" % ticks[0])
		check(ticks[1] - ticks[0] >= 5 and ticks[1] - ticks[0] <= 7, "the third 0.1 s after it: %d ticks" % (ticks[1] - ticks[0]))
	check(spawning.is_done(), "the list is used up")


## A group still rippling in is not interrupted by a quiet room, and the next waits until it has all
## started, even with nothing standing.
func test_the_next_group_waits_for_the_current_one_to_start() -> void:
	var spawning := RoomSpawning.new()
	_begin(spawning, [1, 1, 1, 1] as Array[int], 2, 0, 0.5)
	check_equal(_all_now(spawning, 0.0, 0).size(), 1, "the first group's first body")
	check_equal(_all_now(spawning, STEP, 0).size(), 0, "its second waits for the stagger, though the room is quiet")
	var got: int = 0
	for at in 40:
		got += _all_now(spawning, STEP, 0).size()
	check_equal(got, 2, "half a second on: the first group's second body and the next group's first")


func test_a_pace_of_0_is_the_whole_list_at_once() -> void:
	var spawning := RoomSpawning.new()
	_begin(spawning, [3, 3, 3, 3, 3] as Array[int], 0, 0, 0.0)
	check_equal(_all_now(spawning, 0.0, 0).size(), 5, "every id in the room's setup")
	check(spawning.is_done(), "nothing left")
	var empty := RoomSpawning.new()
	empty.begin([] as Array[StringName], PackedInt32Array(), 4, 1, 0.1)
	check(empty.is_done() and empty.next(0.0, 0) == &"", "an empty list is done at once")


func test_take_all_and_clear_empty_the_queue() -> void:
	var spawning := RoomSpawning.new()
	_begin(spawning, [1, 1, 1, 1] as Array[int], 1, 0, 0.0)
	check_equal(spawning.take_all().size(), 4, "every id taken")
	check(spawning.is_done() and spawning.left() == 0, "the queue is empty")
	_begin(spawning, [1, 1, 1, 1] as Array[int], 1, 0, 0.0)
	spawning.clear()
	check(spawning.is_done() and spawning.next(0.0, 0) == &"", "cleared: nothing comes")


func test_the_spawns_farthest_from_every_wizard_come_first() -> void:
	var spawns := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(200, 0), Vector2(300, 0)])
	check_equal(RoomSpawning.rank(spawns, PackedVector2Array([Vector2(0, 0)]), Callable()), PackedInt32Array([3, 2, 1]), "a wizard at the left: from the right, never on the wizard")
	check_equal(RoomSpawning.rank(spawns, PackedVector2Array([Vector2(0, 0), Vector2(300, 0)]), Callable()), PackedInt32Array([1, 2]), "one each end: the middle, ties by index, none on a wizard")
	check_equal(RoomSpawning.rank(spawns, PackedVector2Array(), Callable()), PackedInt32Array([0, 1, 2, 3]), "no wizard standing: in their order")
	var hole := func(at: Vector2) -> bool: return at.x >= 250.0
	check_equal(RoomSpawning.rank(spawns, PackedVector2Array([Vector2(0, 0)]), hole), PackedInt32Array([2, 1]), "a spawn over a hole is left out")
	var all_holes := func(_at: Vector2) -> bool: return true
	check_equal(RoomSpawning.rank(spawns, PackedVector2Array([Vector2(0, 0)]), all_holes), PackedInt32Array([3, 2, 1]), "unless every one is")
	var crowded := PackedVector2Array([Vector2(0, 0), Vector2(40, 0)])
	check_equal(RoomSpawning.rank(crowded, PackedVector2Array([Vector2(0, 0)]), Callable()), PackedInt32Array([1]), "every spawn near a wizard: the farthest alone")


## A group's bodies take the ranked spawns in turn, stacked where one is used again within the group;
## the next group ranks them again from where the wizards stand then.
func test_a_group_takes_the_ranked_spawns_in_turn() -> void:
	var spawns := PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])
	var stack := func(spawn: Vector2, times: int) -> Vector2: return spawn + Vector2(0, 10 * times)
	var spawning := RoomSpawning.new()
	_begin(spawning, [1, 1, 1, 1] as Array[int], 3, 0, 0.0)
	var left := PackedVector2Array([Vector2(0, 0)])
	var placed: Array[Vector2] = []
	for id: StringName in _all_now(spawning, 0.0, 0):
		placed.append(spawning.spawn_for(spawns, left, Callable(), stack))
	check_equal(placed, [Vector2(100, 0), Vector2(100, 10), Vector2(100, 20)] as Array[Vector2], "the far spawn, stacked: never the one the wizard stands on")
	check_equal(_all_now(spawning, 0.0, 0).size(), 1, "the next group")
	check_equal(spawning.spawn_for(spawns, PackedVector2Array([Vector2(100, 0)]), Callable(), stack), Vector2(0, 0), "ranked again: the wizard moved right")
