extends "res://tests/support/suite.gd"
## Determinism on one machine (online-ready N1, docs/milestones/online-ready.md): each scripted scene
## (tests/core/sim_scenes.gd: a staffed fight, a spell storm) played twice from the
## same start gives the same state hash in every area at every tick. When two runs part, the desync
## report names the first tick, the areas and each differing member with both values: a cache filled
## in another order or a timing stat goes into DERIVED, anything else is a bug to fix.
##
## Each scene takes seconds: the runner plays them in processes of their own (tests/support/suite.gd):
# unit-test-shards: 3

const SimScenes := preload("res://tests/core/sim_scenes.gd")
const SimSource := preload("res://tests/support/sim_source.gd")

const TICKS: int = 150


func test_a_staffed_fight_plays_the_same_twice() -> void:
	_check_twice(&"fight")


func test_a_spell_storm_plays_the_same_twice() -> void:
	_check_twice(&"storm")


## The view stepped thrice (online-ready N9): a simulation script's drawing (the functions it lists
## in VIEW: the projectile manager's `update_draw`) may read the game but never write it, so a run
## whose drawing runs three times between ticks, as at a high frame rate, plays the same as one
## whose drawing never runs. Run by hand, so it is the same on every machine.
func test_the_view_stepped_thrice_plays_the_same() -> void:
	for scene: StringName in [&"fight", &"storm"]:
		var a := Desync.new()
		var b := Desync.new()
		_record(scene, a)
		_record(scene, b, 3)
		var tick: int = Desync.first_parting(a, b)
		if tick < 0:
			continue
		var a2 := Desync.new(tick)
		var b2 := Desync.new(tick)
		_record(scene, a2)
		_record(scene, b2, 3)
		check(false, "%s: a view function writes state: %s" % [scene, Desync.compare(a2, b2)])


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


## Play `scene` for TICKS ticks into `into`; with `view_runs`, every simulation script's view
## functions run that many times after each tick.
func _record(scene: StringName, into: Desync, view_runs: int = 0) -> void:
	var played := SimScenes.new(root, scene)
	for i in TICKS:
		played.step()
		for run in view_runs:
			_run_views(played.areas())
		into.capture(played.areas())
	played.free_all()


## Every view function (`VIEW`) of the areas and of everything under the area nodes, called with
## no arguments, or with a tick's length for one that takes a delta (`_process`).
static func _run_views(areas: Dictionary) -> void:
	var objects: Array[Object] = []
	for area: Variant in areas.values():
		if not area is Object:
			continue
		objects.append(area as Object)
		if area is Node:
			objects.append_array((area as Node).find_children("*", "", true, false))
	for object in objects:
		var script: Script = object.get_script() as Script
		if script == null:
			continue
		for name in SimSource.view_functions(script):
			for info: Dictionary in script.get_script_method_list():
				if info["name"] != name:
					continue
				var required: int = (info["args"] as Array).size() - (info["default_args"] as Array).size()
				if required == 0:
					object.call(name)
				elif required == 1:
					object.call(name, 1.0 / 60.0)
				break
