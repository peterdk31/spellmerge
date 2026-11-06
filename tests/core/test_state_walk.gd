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
## entry, without an engine error.
func test_refs_of_arrays_of_arrays() -> void:
	var striker := Striker.new()
	var body := own(Body.new()) as Body
	striker.struck[1].append(body)
	var walk := StateWalk.new()
	var leaves: Dictionary = {}
	walk.walk("s", striker, func(path: String, value: Variant) -> void: leaves[path] = value)
	check(walk.problems.is_empty(), "no problem: %s" % walk.problems)
	check(leaves.values().has("Body#3") or str(leaves).contains("#3"), "the struck body by who it is: %s" % leaves)
