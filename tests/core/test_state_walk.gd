extends "res://tests/support/suite.gd"
## The state walker, the hash and the desync report (core/sim, online-ready N1) on small made-up
## objects: what is walked, what is skipped, what is a problem, and what the report names.


const NativeScript := preload("res://core/native/native.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")


class Plain:
	extends RefCounted
	const DERIVED: Array[StringName] = [&"cache"]
	const VIEW: Array[StringName] = [&"shown"]
	var health: float = 10.0
	var marks: PackedInt32Array = PackedInt32Array([1, 2, 3])
	var table: Dictionary = {}
	var child: Plain = null
	var cache: Array = []
	var shown: int = 0


class Holder:
	extends Node
	var other: Node = null
	var call_me: Callable = Callable()


## A body with an id (as an actor has), for references.
class Body:
	extends Node
	var id: int = 3


class Pointer:
	extends RefCounted
	const REFS: Array[StringName] = [&"target", &"due"]
	var target: Node = null
	var due: Array[Node] = []


## A carrier's per-actor table: a slot per actor, mostly empty.
class Slots:
	extends RefCounted
	var count: int = 2
	var label: String = "slots"
	var slots: Array[Plain] = [null, null, null, null]
	var loose: Array = [1, null, "x"]


## Made whole and never changed after (a compiled build): hashed once (N3c).
class Built:
	extends RefCounted
	const FROZEN: bool = true
	var power: float = 1.0
	var parts: PackedInt32Array = PackedInt32Array([4, 5])


class UsesBuilt:
	extends RefCounted
	var first: Built = null
	var again: Built = null


## A row's record that says when it is idle (a carrier's homing per row, N3c).
class Row:
	extends RefCounted
	var reach: float = 0.0
	var seed: int = 0

	func idle() -> bool:
		return reach == 0.0


class Rows:
	extends RefCounted
	const SPARES: Array[StringName] = [&"spare"]
	var rows: Array[Row] = []
	var spare: Array[Row] = []


class Based:
	extends RefCounted
	const DERIVED: Array[StringName] = [&"cache"]
	var cache: int = 0
	var kept: int = 0


## A script that extends one with a list cannot declare it again; it names a list of its own.
class Extended:
	extends Based
	const DERIVED_EXTENDED: Array[StringName] = [&"scratch"]
	var scratch: int = 0


func test_derived_and_view_members_are_not_hashed() -> void:
	var a := Plain.new()
	var hashed: int = SimHash.of(a)
	a.cache.append(42)
	a.shown = 7
	check_equal(SimHash.of(a), hashed, "a cache and a drawn value leave the hash alone")
	a.health = 9.0
	check(SimHash.of(a) != hashed, "a state member changes the hash")


func test_a_dictionary_hashes_the_same_in_any_insertion_order() -> void:
	var a := Plain.new()
	var b := Plain.new()
	a.table = {3: "c", 1: "a", 2: "b"}
	b.table = {1: "a", 2: "b", 3: "c"}
	check_equal(SimHash.of(a), SimHash.of(b), "the keys are walked in sorted order")


func test_an_object_met_twice_is_walked_once() -> void:
	var a := Plain.new()
	var shared := Plain.new()
	a.child = shared
	a.table = {0: shared}
	var paths: PackedStringArray = PackedStringArray()
	StateWalk.new().walk("a", a, func(path: String, _value: Variant) -> void: paths.append(path))
	# `table` is declared before `child`, so the dictionary meets it first.
	check(paths.has("a.table[0].health"), "the first meeting walks it")
	check(not paths.has("a.child.health"), "the second only names it")
	check(paths.has("a.child"), "the second meeting is a leaf (the number of the first)")


func test_a_generator_is_hashed_by_its_state() -> void:
	var a := Plain.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	a.table = {0: rng}
	var before: int = SimHash.of(a)
	rng.randf()
	check(SimHash.of(a) != before, "a roll changes the hash")


func test_a_reference_to_a_node_it_does_not_own_is_a_problem() -> void:
	var holder := own(Holder.new()) as Holder
	var stranger := own(Node.new()) as Node
	holder.other = stranger
	holder.call_me = holder.queue_free
	var walk := StateWalk.new()
	walk.walk("holder", holder, func(_path: String, _value: Variant) -> void: pass)
	check(walk.problems.size() >= 2, "both are named: %s" % ", ".join(walk.problems))
	check(", ".join(walk.problems).contains("holder.other"), "the node member is named by its path")
	check(", ".join(walk.problems).contains("DERIVED"), "the fix is named")


func test_the_report_names_the_member_that_parts() -> void:
	var a := Desync.new(2)
	var b := Desync.new(2)
	for tick in 4:
		var x := Plain.new()
		var y := Plain.new()
		if tick >= 2:
			y.marks[1] = 9
		a.capture({"area": x})
		b.capture({"area": y})
	check_equal(Desync.first_parting(a, b), 2, "the runs part at tick 2")
	var report: String = Desync.compare(a, b)
	check(report.contains("tick 2"), "the tick is named: %s" % report)
	check(report.contains("area.marks: [1] 2 vs 9"), "the member, the index and both values: %s" % report)


func test_runs_that_agree_have_no_report() -> void:
	var a := Desync.new()
	var b := Desync.new()
	for tick in 3:
		a.capture({"area": Plain.new()})
		b.capture({"area": Plain.new()})
	check_equal(Desync.compare(a, b), "", "no report")


func test_a_reference_is_hashed_as_who_it_points_at() -> void:
	var body := own(Body.new()) as Body
	var other := own(Node.new()) as Node
	var a := Pointer.new()
	a.target = body
	a.due = [other, null]
	var walk := StateWalk.new()
	var leaves: Dictionary = {}
	walk.walk("a", a, func(path: String, value: Variant) -> void: leaves[path] = value)
	check(walk.problems.is_empty(), "a reference listed in REFS is no problem: %s" % ", ".join(walk.problems))
	check(String(leaves.get("a.target", "")).ends_with("#3"), "the body is named by its id: %s" % [leaves.get("a.target")])
	check_equal(leaves.get("a.due[0]"), "Node", "a body without an id is named by what it is")
	check_equal(leaves.get("a.due[1]"), null, "an empty one is null")
	var before: int = SimHash.of(a)
	body.set(&"name", "Moved")
	check_equal(SimHash.of(a), before, "a reference is never entered: the body's own members leave it alone")
	body.id = 4
	check(SimHash.of(a) != before, "pointing at another actor changes the hash")
	# Only filled entries are walked (a slot-sized array is nearly all empty); their index counts.
	a.due = [null, other, null]
	var at_one: int = SimHash.of(a)
	a.due = [null, null, other]
	check(SimHash.of(a) != at_one, "the same body in another slot changes the hash")
	a.due = [null, null, null]
	var empty: int = SimHash.of(a)
	a.due = [null, null]
	check(SimHash.of(a) != empty, "an empty array's size counts")


## A REFS list whose entries are all bodies (Combat's rows) is one leaf of their actor ids, -1 for an
## empty entry (props W3b), and a report names the entry by its index; a list with anything else in
## it is walked entry by entry, as above.
func test_a_list_of_bodies_is_one_leaf_of_ids() -> void:
	var three := own(Body.new()) as Body
	var five := own(Body.new()) as Body
	five.id = 5
	var a := Pointer.new()
	a.due = [three, null, five]
	var walk := StateWalk.new()
	var leaves: Dictionary = {}
	walk.walk("a", a, func(path: String, value: Variant) -> void: leaves[path] = value)
	check(walk.problems.is_empty(), "no problem: %s" % ", ".join(walk.problems))
	check_equal(leaves.get("a.due.ids"), PackedInt64Array([3, StateWalk.NO_BODY, 5]), "one leaf of ids")
	check(not leaves.has("a.due[0]"), "and no leaf an entry")
	var before: int = SimHash.of(a)
	a.due = [five, null, three]
	check(SimHash.of(a) != before, "the same bodies in other rows change the hash")
	a.due = [three, five, null]
	var moved: int = SimHash.of(a)
	check(moved != before, "an empty row moved changes it")
	var b := Pointer.new()
	b.due = [three, null, five]
	var first := Desync.new(0)
	var second := Desync.new(0)
	first.capture({"a": a})
	second.capture({"a": b})
	check(Desync.compare(first, second).contains("a.due.ids: [1]"), "a report names the row: %s" % Desync.compare(first, second))
	# A closed body (no actor id) in the list: walked entry by entry, as before.
	five.id = -1
	var closed := Pointer.new()
	closed.due = [three, five]
	leaves.clear()
	walk.walk("a", closed, func(path: String, value: Variant) -> void: leaves[path] = value)
	check(leaves.has("a.due[1]") and not leaves.has("a.due.ids"), "a closed body: entry by entry: %s" % [leaves.keys()])
	# A body freed since it was pointed at stays in the leaf (no walk entry by entry of a slot table).
	var gone := Body.new()
	var freed := Pointer.new()
	freed.due = [three, gone]
	gone.free()
	leaves.clear()
	walk.walk("a", freed, func(path: String, value: Variant) -> void: leaves[path] = value)
	var ids: Variant = leaves.get("a.due.ids")
	check(ids is PackedInt64Array and (ids as PackedInt64Array)[1] < 0, "a freed body is an entry of the leaf, no id: %s" % [leaves])
	# An object that is no node, even with an id: entry by entry.
	var other := Pointer.new()
	other.due = [three]
	other.due.append(own(Node.new()) as Node)
	leaves.clear()
	walk.walk("a", other, func(path: String, value: Variant) -> void: leaves[path] = value)
	check(not leaves.has("a.due.ids"), "a node with no actor id: entry by entry: %s" % [leaves.keys()])


## An area handed over as nothing (a service gone) is a leaf, not an error; a value an area hands
## over of itself (an actor's part, `SimHash.ActorPart`) is walked as its member would be.
func test_a_missing_area_and_a_handed_value() -> void:
	var hashes: Dictionary[String, int] = SimHash.areas({"gone": null})
	check(hashes.has("gone"), "a null area hashes: %s" % [hashes])
	var plain := Plain.new()
	var walk := StateWalk.new()
	var leaves: Dictionary = {}
	walk.walk_value("p", [plain, 3], plain, func(path: String, value: Variant) -> void: leaves[path] = value)
	check(walk.problems.is_empty() and leaves.has("p[1]"), "a value is walked as a member: %s" % [leaves])
	# Both ways give the same leaves, in order (as `SimHash.area` hashes them).
	var handed: Array = []
	walk.walk_value("p", [plain, 3], plain, func(_path: String, value: Variant) -> void: SimHash.add_leaf(handed, value))
	var quick: Array = []
	var by_values := StateWalk.new()
	by_values.with_paths = false
	by_values.values_of("p", [plain, 3], plain, quick)
	check(not quick.is_empty() and SimHash.of_leaves(quick) == SimHash.of_leaves(handed), "both ways, the same leaves")


## An array with empty slots walks only its filled ones, each after its index (the hash's walk was
## mostly the empty slots of the carriers' per-actor tables): where an object is still counts.
func test_an_array_with_empty_slots_hashes_where_its_objects_are() -> void:
	var a := Slots.new()
	var plain := Plain.new()
	a.slots[1] = plain
	var at_one: int = SimHash.of(a)
	a.slots[1] = null
	a.slots[2] = plain
	check(SimHash.of(a) != at_one, "the same object in another slot changes the hash")
	a.slots[2] = null
	var empty: int = SimHash.of(a)
	a.slots.resize(5)
	check(SimHash.of(a) != empty, "an empty array's size counts")
	var paths: Array[String] = []
	var b := Slots.new()
	b.slots[3] = plain
	StateWalk.new().walk("b", b, func(path: String, _value: Variant) -> void: paths.append(path))
	check(paths.has("b.slots[3].health"), "the filled slot is walked: %s" % [paths])
	check(not paths.has("b.slots[0]"), "an empty slot is not a leaf: %s" % [paths])
	check(paths.has("b.loose[0]") and not paths.has("b.loose[1]"), "an untyped array with a null is walked the same way: %s" % [paths])


## The hash's own walk (`StateWalk.values`: no sink, plain members appended as they are) hashes as the
## walk with a sink (a desync report's kept tick) does, whatever the area holds.
func test_the_hash_is_the_same_with_or_without_a_sink() -> void:
	var a := Slots.new()
	a.slots[0] = Plain.new()
	a.slots[0].child = Plain.new()
	a.slots[0].table = {&"b": 1, "a": [2, null, Vector2.ONE]}
	a.slots[2] = a.slots[0]
	var walk := StateWalk.new()
	walk.with_paths = false
	var without: int = SimHash.area(walk, "a", a)
	var kept: Dictionary = {}
	var with_sink: int = SimHash.area(StateWalk.new(), "a", a, func(path: String, value: Variant) -> void: kept[path] = value)
	check_equal(with_sink, without, "the same hash either way")
	check(not kept.is_empty(), "the sink was handed the leaves")
	a.slots[0].health = 3.0
	check(SimHash.area(walk, "a", a) != without, "a plain member changes the hash's own walk")


func test_a_list_may_carry_a_name_of_its_own() -> void:
	check_equal(StateWalk.members(Extended), PackedStringArray(["kept"]), "DERIVED and DERIVED_EXTENDED are both skipped")
	check_equal(StateWalk.listed(Extended, "DERIVED"), PackedStringArray(["scratch", "cache"]), "the lists of the script and its base")


func test_a_dictionary_keyed_by_an_object_is_a_problem() -> void:
	var a := Plain.new()
	a.table = {Plain.new(): 1}
	var walk := StateWalk.new()
	walk.walk("a", a, func(_path: String, _value: Variant) -> void: pass)
	check(", ".join(walk.problems).contains("keyed by an object"), "an object key is named: %s" % ", ".join(walk.problems))


func test_the_report_keeps_paths_only_for_its_tick() -> void:
	var a := Desync.new(1)
	for tick in 3:
		a.capture({"area": Plain.new()})
	check(a.leaves.has("area") and (a.leaves["area"] as Dictionary).has("area.health"), "the kept tick's leaves are named by path")
	check_equal(a.hashes[0], a.hashes[1], "a kept tick hashes as any other")


func test_a_script_counted_as_simulation_is_walked_as_one() -> void:
	var holder := own(Holder.new()) as Holder
	var child := Body.new()
	holder.add_child(child)
	holder.other = child
	var walk := StateWalk.new()
	walk.walk("holder", holder, func(_path: String, _value: Variant) -> void: pass)
	check(", ".join(walk.problems).contains("holder.other"), "a node of a script outside the simulation is a problem")
	var counted := StateWalk.new()
	counted.also_simulation = [Body]
	var paths: PackedStringArray = PackedStringArray()
	counted.walk("holder", holder, func(path: String, _value: Variant) -> void: paths.append(path))
	check(not ", ".join(counted.problems).contains("holder.other"), "counted as simulation, the child it owns is walked: %s" % ", ".join(counted.problems))
	check(paths.has("holder.other.id"), "its members are state")


## A report shows a float with every digit it needs (it used `%.17g`, which GDScript's `%` does not
## know: the report was an error line per float).
func test_the_report_shows_floats_whole() -> void:
	var lines: PackedStringArray = Desync.members_parting({"a.x": 0.1, "a.y": 1e-20}, {"a.x": 0.30000000000000004, "a.y": 2e-20})
	check_equal(lines, PackedStringArray(["a.x: 0.1 vs 0.30000000000000004", "a.y: 1e-20 vs 2e-20"]), "the floats as they are")


## An area that is a node of no script is a problem, not a crash.
func test_an_area_of_no_script_is_a_problem() -> void:
	var plain: Node = own(Node.new()) as Node
	var walk := StateWalk.new()
	SimHash.areas({"plain": plain}, walk)
	check_equal(walk.problems.size(), 1, "named: %s" % walk.problems)


## A kept tick's leaves are the values at that tick: an array changed later does not change them
## (packed arrays are held by reference; the report showed later values).
func test_kept_leaves_are_copies() -> void:
	var plain := Plain.new()
	var desync := Desync.new(0)
	desync.capture({"plain": plain})
	plain.marks[0] = 99
	check_equal(desync.leaves["plain"]["plain.marks"], PackedInt32Array([1, 2, 3]), "the leaf as captured")


## A kept leaf of the projectile manager stays as captured when the native kernel steps: the kernel
## writes into the manager's arrays in place, past copy-on-write, so a copy sharing the buffer
## (`duplicate`) showed the next step's shots (found by N2b). Skipped without the native module.
func test_kept_leaves_survive_the_native_kernel() -> void:
	if not NativeScript.loaded():
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "SPELLMERGE_NATIVE=required, but the native module is not loaded")
		return
	var manager: ManagerScript = own(ManagerScript.new()) as ManagerScript
	manager.actors = own(ActorSeats.table()) as Node
	manager.events = own(EventsScript.new()) as Node
	manager.set_native(true)
	check(manager.is_native(), "the manager runs the native kernel")
	manager.spawn(0, Vector2.ZERO, Vector2(60.0, 0.0), 1.0)
	var desync := Desync.new(0)
	desync.capture({"shots": manager})
	var life: PackedFloat32Array = desync.leaves["shots"]["shots._life"]
	manager.step(1.0 / 60.0)
	check_equal(life[0], 1.0, "the kept life is the captured one")
	check(manager.get(&"_life")[0] < 1.0, "the shot aged")


## A table with StringName keys is walked by the keys' text, whatever order the names were made in:
## the engine sorts StringNames by where they are in memory (the web walked Spells' carriers in
## another order than Linux; found by N2b).
func test_string_name_keys_are_walked_by_their_text() -> void:
	var words: Array[String] = ["zebra", "kite", "apple", "moss", "berry", "yarn", "cloud", "ivy"]
	var table: Dictionary = {}
	for word in words:
		# Made here, so the names are new and lie in memory in the order made.
		table[StringName("n2b_%s_%d" % [word, word.length()])] = word
	var paths: Array[String] = []
	StateWalk.new().walk("t", Keyed.new(table), func(path: String, _value: Variant) -> void:
		if path.ends_with("{}"):
			paths.append(path))
	var sorted: Array[String] = paths.duplicate()
	sorted.sort()
	check_equal(paths, sorted, "keys walked in text order")
	check_equal(StateWalk.sorted_keys({&"b": 1, "c": 2, &"a": 3, 1: 4}), [1, &"a", &"b", "c"], "mixed keys: by type, then by text")


class Keyed:
	extends RefCounted
	var table: Dictionary = {}

	func _init(with: Dictionary) -> void:
		table = with


class Striker:
	extends RefCounted
	const REFS: Array[StringName] = [&"struck"]
	var struck: Array[Array] = [[], []]


## A REFS member that is a typed array of arrays (a carrier's struck lists) is walked, entry by
## entry, without an engine error; each inner list of bodies is one leaf of their ids.
func test_refs_of_arrays_of_arrays() -> void:
	var striker := Striker.new()
	var body := own(Body.new()) as Body
	striker.struck[1].append(body)
	var walk := StateWalk.new()
	var leaves: Dictionary = {}
	walk.walk("s", striker, func(path: String, value: Variant) -> void: leaves[path] = value)
	check(walk.problems.is_empty(), "no problem: %s" % walk.problems)
	check_equal(leaves.get("s.struck[1].ids"), PackedInt64Array([3]), "the struck body by its actor id (a list of bodies, props W3b): %s" % leaves)


func test_a_frozen_object_is_hashed_by_its_contents_once() -> void:
	var a := UsesBuilt.new()
	a.first = Built.new()
	a.again = a.first
	var b := UsesBuilt.new()
	b.first = Built.new()
	b.again = Built.new()
	check_equal(SimHash.of(a), SimHash.of(b), "met twice, or two with the same contents: the same leaves")
	var c := UsesBuilt.new()
	c.first = Built.new()
	c.first.power = 2.0
	c.again = a.first
	check(SimHash.of(c) != SimHash.of(a), "other contents hash otherwise")
	var walk := StateWalk.new()
	SimHash.area(walk, "a", a)
	a.first.power = 3.0
	var again := StateWalk.new()
	again.verify_frozen = true
	SimHash.area(again, "a", a)
	check(again.problems.size() > 0 and again.problems[0].contains("FROZEN"), "one changed after it was made is named: %s" % [again.problems])


func test_idle_rows_and_spare_records_hash_as_little() -> void:
	var a := Rows.new()
	var b := Rows.new()
	for i in 4:
		a.rows.append(Row.new())
		var row := Row.new()
		row.seed = 99
		b.rows.append(row)
	a.spare.append(Row.new())
	var spare := Row.new()
	spare.reach = 5.0
	b.spare.append(spare)
	check_equal(SimHash.of(a), SimHash.of(b), "an idle row is one leaf (its seed is set when it starts); a spare by the pool's size")
	b.rows[2].reach = 1.0
	check(SimHash.of(a) != SimHash.of(b), "a row at work is walked")
	b.rows[2].reach = 0.0
	b.spare.append(Row.new())
	check(SimHash.of(a) != SimHash.of(b), "the pool's size counts")
	var walked := StateWalk.new()
	var report: int = SimHash.area(walked, "a", a, func(_p: String, _v: Variant) -> void: pass)
	check_equal(report, SimHash.of(a), "the report's walk hashes the same")
