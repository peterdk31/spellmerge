extends "res://tests/support/suite.gd"
## Determinism on one machine (online-ready N1, docs/milestones/online-ready.md): each scripted scene
## (tests/core/sim_scenes.gd: a staffed fight, a spell storm, a horde wave) played twice from the
## same start gives the same state hash in every area at every tick. When two runs part, the desync
## report names the first tick, the areas and each differing member with both values: a cache filled
## in another order or a timing stat goes into DERIVED, anything else is a bug to fix.
##
## Each scene takes seconds: the runner plays them in processes of their own (tests/support/suite.gd):
# unit-test-shards: 3

const SimScenes := preload("res://tests/core/sim_scenes.gd")

const TICKS: int = 150


func test_a_staffed_fight_plays_the_same_twice() -> void:
	_check_twice(&"fight")


func test_a_spell_storm_plays_the_same_twice() -> void:
	_check_twice(&"storm")


func test_a_horde_wave_plays_the_same_twice() -> void:
	_check_twice(&"horde")


func test_the_hash_tells_two_different_runs_apart() -> void:
	var a := Desync.new()
	var b := Desync.new()
	_record(&"fight", a)
	var scene := SimScenes.new(root, &"fight")
	for i in TICKS:
		if i == 40:
			# One enemy takes one more point of damage than in the first run.
			var areas: Dictionary = scene.areas()
			var combat: Node = areas["combat"]
			var victim: Node2D = areas.values().back() as Node2D
			combat.call(&"hit", -1, victim, 1.0)
		scene.step()
		b.capture(scene.areas())
	scene.free_all()
	check_equal(Desync.first_parting(a, b), 40, "the runs part at the tick the extra damage was dealt")


func _check_twice(scene: StringName) -> void:
	var a := Desync.new()
	var b := Desync.new()
	_record(scene, a)
	_record(scene, b)
	check(a.hashes.size() == TICKS, "%s: the run recorded its ticks" % scene)
	for problem in a.problems:
		check(false, "%s: %s" % [scene, problem])
	var tick: int = Desync.first_parting(a, b)
	if tick < 0:
		return
	# Again, keeping the parting tick's leaves, so the report names the members.
	var a2 := Desync.new(tick)
	var b2 := Desync.new(tick)
	_record(scene, a2)
	_record(scene, b2)
	check(false, "%s: %s" % [scene, Desync.compare(a2, b2)])


func _record(scene: StringName, into: Desync) -> void:
	var played := SimScenes.new(root, scene)
	for i in TICKS:
		played.step()
		into.capture(played.areas())
	played.free_all()
