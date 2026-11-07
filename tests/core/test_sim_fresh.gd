extends "res://tests/support/suite.gd"
## A run starts from a fresh game's state (core/sim/sim_fresh.gd, online-ready N3b): an area takes
## every state member from a blank of its own script, keeps its settings (RUN_KEEPS, at every level),
## its objects (as the same objects) and what is not state, shares what the blank shares the way the
## blank does, and names a node it would drop.


## A part an area keeps: the same object across runs (a carrier, the AI board).
class Part:
	extends RefCounted
	const DERIVED: Array[StringName] = [&"owner"]
	const RUN_KEEPS: Array[StringName] = [&"setting"]
	var clock: float = 0.0
	var setting: int = 1
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
	const RUN_KEEPS: Array[StringName] = [&"cap"]
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
	## Bodies it keeps out of the tree between uses (as Entities' decoys).
	var bodies: Array[Node2D] = []
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
	area.part.setting = 3
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


func test_renew_makes_the_state_the_blanks() -> void:
	var area: Area = _used()
	SimFresh.renew(area)
	check_equal(area.clock, 0.0, "the clock")
	check_equal(area.next_seq, 0, "the counter")
	check_equal(area.slots, PackedFloat32Array([-1.0, -1.0, -1.0, -1.0]), "a packed array, sized and filled as a fresh one")
	check(area.list.is_empty() and area.table.is_empty(), "an array and a dictionary")
	check_equal(area.target, null, "a REFS member: who the blank points at (no one)")


func test_settings_and_what_is_not_state_stay() -> void:
	var area: Area = _used()
	SimFresh.renew(area)
	check_equal(area.cap, 8, "the area's RUN_KEEPS")
	check_equal(area.part.setting, 3, "a kept object's own RUN_KEEPS")
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


func test_a_node_out_of_the_tree_it_would_drop_is_named() -> void:
	var area: Area = _used()
	var body: Node2D = own(Node2D.new()) as Node2D
	body.name = "Spare"
	area.bodies.append(body)
	var problems: PackedStringArray = SimFresh.take(area, _blank())
	check_equal(problems.size(), 1, "one problem")
	check(problems.size() == 1 and problems[0].contains("bodies") and problems[0].contains("Spare"), "it names the member and the node: %s" % [problems])
	# In the tree, it is the tree's to free: nothing to say.
	root.add_child(body)
	area.bodies.append(body)
	check(SimFresh.take(area, _blank()).is_empty(), "no problem for a node in the tree")




## An area whose blank holds two parts where a used one may share one (N3b's rule: one object takes
## one blank's), a dictionary of parts, content, and a member a blank fills that a used one emptied.
class Sharing:
	extends Node
	var left: Part = Part.new()
	var right: Part = Part.new()
	var by_name: Dictionary = {&"a": Part.new()}
	var card: Resource = null
	var maybe: Part = Part.new()

	func _init() -> void:
		card = Resource.new()
		card.resource_name = "blank's"


## An area that extends one with settings: its own list keeps beside its parent's, at every level.
class Wider:
	extends Area
	const RUN_KEEPS_WIDER: Array[StringName] = [&"budget"]
	var budget: int = 10
	var spent: int = 0


func test_one_object_shared_where_the_blank_holds_two_becomes_two() -> void:
	var area: Sharing = own(Sharing.new()) as Sharing
	area.right = area.left
	area.left.clock = 4.0
	var blank: Sharing = own(Sharing.new()) as Sharing
	SimFresh.take(area, blank)
	check(area.left != area.right, "two parts again, as the blank has")
	check_equal(area.left.clock, 0.0, "each fresh")
	check_equal(area.right.clock, 0.0, "each fresh")


func test_a_dictionary_of_another_shape_is_the_blanks_again() -> void:
	var area: Sharing = own(Sharing.new()) as Sharing
	var kept: Part = area.by_name[&"a"]
	area.by_name[&"b"] = Part.new()
	var blank: Sharing = own(Sharing.new()) as Sharing
	SimFresh.take(area, blank)
	check_equal(area.by_name.keys(), [&"a"], "its keys are the blank's")
	check(area.by_name[&"a"] == blank.by_name[&"a"] and area.by_name[&"a"] != kept, "taken from the blank whole, not kept")
	check(area.by_name != blank.by_name or not is_same(area.by_name, blank.by_name), "a dictionary of its own")


func test_a_dictionary_of_the_same_shape_keeps_its_objects() -> void:
	var area: Sharing = own(Sharing.new()) as Sharing
	var kept: Part = area.by_name[&"a"]
	kept.clock = 3.0
	SimFresh.take(area, own(Sharing.new()) as Sharing)
	check(area.by_name[&"a"] == kept, "the same part")
	check_equal(kept.clock, 0.0, "fresh")


func test_content_and_emptied_members_are_the_blanks() -> void:
	var area: Sharing = own(Sharing.new()) as Sharing
	var used := Resource.new()
	area.card = used
	area.maybe = null
	var blank: Sharing = own(Sharing.new()) as Sharing
	SimFresh.take(area, blank)
	check(area.card == blank.card, "a resource is data: the blank's")
	check(area.maybe != null and area.maybe == blank.maybe, "a member emptied in the run is the blank's object again")


func test_renew_readies_the_blank_first() -> void:
	var area: Area = _used()
	var seen: Array = []
	SimFresh.renew(area, func(blank: Object) -> void:
		seen.append(blank)
		(blank as Area).next_seq = 77)
	check_equal(seen.size(), 1, "the setup saw the blank")
	check_equal(area.next_seq, 77, "and the area took the readied blank's state")


func test_a_subclass_keeps_its_own_settings_and_its_parents() -> void:
	var area: Wider = own(Wider.new()) as Wider
	area.cap = 6
	area.budget = 3
	area.spent = 2
	area.clock = 1.0
	SimFresh.renew(area)
	check_equal(area.cap, 6, "its parent's RUN_KEEPS")
	check_equal(area.budget, 3, "its own")
	check_equal(area.spent, 0, "the rest fresh")
	check_equal(area.clock, 0.0, "its parent's state too")
