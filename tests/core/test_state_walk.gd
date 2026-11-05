extends "res://tests/support/suite.gd"
## The state walker, the hash and the desync report (core/sim, online-ready N1) on small made-up
## objects: what is walked, what is skipped, what is a problem, and what the report names.


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
