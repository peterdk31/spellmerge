extends "res://tests/support/suite.gd"
## A run starts from a fresh game's state (core/sim/sim_fresh.gd, online-ready N3b): an area takes
## every state member from a blank of its own script, keeps its settings, its objects (as the same
## objects) and what is not state, and shares what the blank shares the way the blank does.


## A part an area keeps: the same object across runs (a carrier, the AI board).
class Part:
	extends RefCounted
	const DERIVED: Array[StringName] = [&"owner"]
	var clock: float = 0.0
	var rows: PackedInt32Array = PackedInt32Array([0, 0])
	## Back to the area that holds it (as a kit's runtime): not the blank's after.
	var area: Object = null
	var owner: Object = null


## One item of a pool.
class Item:
	extends RefCounted
	var due: float = 0.0


## An area.
class Area:
	extends Node
	const DERIVED: Array[StringName] = [&"cache"]
	const VIEW: Array[StringName] = [&"drawn"]
	const REFS: Array[StringName] = [&"target"]
	var cap: int = 4
	var clock: float = 0.0
	var next_seq: int = 0
	var slots: PackedFloat32Array = PackedFloat32Array()
	var list: Array[int] = []
	var table: Dictionary = {}
	var part: Part = null
	var parts: Dictionary = {}
	## A pool, and the item in use (one of the pool's, as `Spells._ray` is of `_rays`).
	var pool: Array[Item] = []
	var current: Item = null
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var target: Node = null
	var cache: Dictionary = {}
	var drawn: int = 0

	func _init() -> void:
		slots.resize(cap)
		slots.fill(-1.0)
		part = Part.new()
		part.area = self
		parts = {&"a": part}
		for i in 2:
			pool.append(Item.new())
		current = pool[0]
		rng.seed = 7


## Seeds itself from the run's dealer as it is made (as the horde director does).
class Seeded:
	extends RefCounted
	var rng_seed: int = 0

	func _init() -> void:
		rng_seed = SimSeed.fresh()


## An area after a run: everything moved on.
func _used() -> Area:
	var area: Area = own(Area.new()) as Area
	area.cap = 8
	area.clock = 12.5
	area.next_seq = 400
	area.slots.fill(3.0)
	area.list.append(5)
	area.table["x"] = 1
	area.part.clock = 9.0
	area.part.rows[1] = 6
	area.part.owner = area
	area.pool.append(Item.new())
	area.pool[0].due = 2.0
	area.current = area.pool[2]
	area.rng.randi()
	area.target = area
	area.cache["kept"] = true
	area.drawn = 99
	return area


func _blank() -> Area:
	return own(SimFresh.blank_of(Area)) as Area


func test_the_state_is_the_blanks() -> void:
	var area: Area = _used()
	SimFresh.take(area, _blank())
	check_equal(area.clock, 0.0, "the clock")
	check_equal(area.next_seq, 0, "the counter")
	check_equal(area.cap, 4, "a value not kept")
	check_equal(area.slots, PackedFloat32Array([-1.0, -1.0, -1.0, -1.0]), "a packed array, sized and filled as a fresh one")
	check(area.list.is_empty() and area.table.is_empty(), "an array and a dictionary")
	check_equal(area.target, null, "a REFS member: who the blank points at (no one)")


func test_settings_and_what_is_not_state_stay() -> void:
	var area: Area = _used()
	SimFresh.take(area, _blank(), [&"cap"])
	check_equal(area.cap, 8, "a kept setting")
	check(area.cache.has("kept"), "DERIVED untouched")
	check_equal(area.drawn, 99, "VIEW untouched")


func test_a_packed_array_gets_a_buffer_of_its_own() -> void:
	var area: Area = _used()
	var blank: Area = _blank()
	SimFresh.take(area, blank)
	blank.slots[0] = 42.0
	check_equal(area.slots[0], -1.0, "the blank's later writes do not reach the area")


func test_kept_objects_stay_the_same_and_take_the_blanks_state() -> void:
	var area: Area = _used()
	var part: Part = area.part
	var rng: RandomNumberGenerator = area.rng
	var blank: Area = _blank()
	SimFresh.take(area, blank)
	check(area.part == part and area.parts[&"a"] == part, "the same part, in both places")
	check_equal(part.clock, 0.0, "its clock")
	check_equal(part.rows, PackedInt32Array([0, 0]), "its rows")
	check(part.area == area, "its member back to the area points at the area, not the blank")
	check(part.owner == area, "its DERIVED member untouched")
	check(area.rng == rng, "the same generator")
	check_equal([rng.seed, rng.state], [blank.rng.seed, blank.rng.state], "with the blank's seed and state")


func test_what_the_blank_shares_the_area_shares_the_same_way() -> void:
	var area: Area = _used()
	SimFresh.take(area, _blank())
	check_equal(area.pool.size(), 2, "the pool as a fresh one's")
	check(area.current == area.pool[0], "the item in use is the pool's first again")
	check_equal(area.pool[0].due, 0.0, "its item fresh")
	# Of the blank's size too: the pool is the blank's, and the item in use points into it.
	var old: Item = area.pool[1]
	area.current = old
	old.due = 5.0
	var blank: Area = _blank()
	SimFresh.take(area, blank)
	check(area.pool[0] == blank.pool[0] and area.pool[1] == blank.pool[1], "the pool's items are the blank's")
	check(area.current == area.pool[0], "and the item in use is its first")
	check_equal(area.pool[1].due, 0.0, "fresh")


func test_a_node_is_never_taken_from_the_blank() -> void:
	var area: Area = _used()
	var blank: Area = _blank()
	blank.target = blank
	SimFresh.take(area, blank)
	check(area.target == area, "a REFS member pointing at the blank points at the area in its place")


func test_a_blank_deals_the_run_no_seeds() -> void:
	SimSeed.begin(5)
	var first: int = SimSeed.fresh()
	SimSeed.begin(5)
	var blank: Seeded = SimFresh.blank_of(Seeded) as Seeded
	var after: int = SimSeed.fresh()
	SimSeed.end()
	check_equal(after, first, "the run's first seed is still dealt first")
	check(blank != null, "the blank made")
