extends "res://tests/support/suite.gd"
## The one clock (core/sim/tick.gd, online-ready N3): a tick runs the areas in its written order,
## the bodies by actor id, only what is switched on and may process, and every delta is DT.
## Stand-in areas under a node of their own (`Tick.areas`) record what the tick asks of them.

const TickScript := preload("res://core/sim/tick.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

## Every call the stand-ins got this test: [what, delta].
var calls: Array = []


## An area: records each step it is asked for.
class Area:
	extends Node
	var calls: Array = []
	## Frames' switch: false and the tick leaves the frames to the test.
	var auto_tick: bool = true

	func _init(area_name: String, into: Array) -> void:
		name = area_name
		calls = into
		set_physics_process(true)
		set_process(true)

	func tick(delta: float) -> void:
		calls.append(["%s.tick" % name, delta])

	func step(delta: float) -> void:
		calls.append(["%s.step" % name, delta])

	func physics_step(delta: float) -> void:
		calls.append(["%s.physics_step" % name, delta])

	func step_rules(delta: float) -> void:
		calls.append(["%s.step_rules" % name, delta])

	func step_timers(delta: float) -> void:
		calls.append(["%s.step_timers" % name, delta])

	func begin_run() -> void:
		calls.append(["%s.begin_run" % name, 0.0])

	func take_rules(rules: SessionRules) -> void:
		calls.append(["%s.take_rules" % name, float(rules.shot_cap)])
	func stood() -> void:
		calls.append(["%s.stood" % name, 0.0])


## A body: an Actor that only records its tick (none of an actor's set-up runs).
class Body:
	extends Actor
	var calls: Array = []

	func _enter_tree() -> void:
		pass

	func _ready() -> void:
		pass

	func _exit_tree() -> void:
		pass

	func tick_step(delta: float) -> void:
		calls.append(["body %s" % name, delta])


var _tick: TickScript
var _areas: Node
var _actors: ActorsScript


func before_each() -> void:
	calls = []
	_areas = own(Node.new()) as Node
	root.add_child(_areas)
	for area: String in ["Frames", "Projectiles", "Spells", "Combat", "Entities", "Horde", "Flow", "Coop"]:
		_areas.add_child(Area.new(area, calls))
	_actors = ActorsScript.new()
	_actors.name = "Actors"
	_areas.add_child(_actors)
	_tick = own(TickScript.new()) as TickScript
	_tick.areas = _areas


func after_each() -> void:
	paused = false
	if is_instance_valid(_areas):
		_areas.queue_free()


## A body with an actor id, in the tree.
func _body(label: String) -> Body:
	var body := Body.new()
	body.name = label
	body.calls = calls
	body.id = _actors.open(ActorsScript.TEAM_ENEMIES, 0)
	_actors.set_node(body.id, body)
	_areas.add_child(body)
	return body


func _names() -> Array[String]:
	var out: Array[String] = []
	for call: Array in calls:
		out.append(call[0])
	return out


func test_a_tick_runs_the_areas_in_the_written_order() -> void:
	_body("a")
	_tick.run(TickScript.DT)
	check_equal(_names(), ["Frames.tick", "Projectiles.step", "Spells.step", "Combat.step", "Entities.step", "Horde.physics_step", "body a", "Flow.step", "Coop.step_rules", "Horde.step_timers"], "the order")
	check_equal(_tick.count, 1, "one tick counted")


## The game's state in parts (`state_slice`, N3c): each area in exactly one part, the parts together
## the whole, the services spread one to a part, each body in the part of its id.
func test_the_state_splits_into_parts_that_cover_it_once() -> void:
	for i in 5:
		_body("b%d" % i)
	var whole: Dictionary = _tick.state_areas()
	check(whole.has("Sim") and whole.has("Spells") and whole.has("actor 4"), "the whole names the sim, the areas and the bodies: %s" % [whole.keys()])
	for slices: int in [1, 2, 7, 60]:
		var met: Dictionary = {}
		for slice in slices:
			for name: String in _tick.state_slice(slice, slices):
				check(not met.has(name), "%s is in one part of %d" % [name, slices])
				met[name] = slice
		check_equal(met.size(), whole.size(), "the %d parts cover the whole" % slices)
		if slices >= TickScript.STATE_AREAS.size() + 1:
			check(met["Sim"] != met["Spells"] and met["Spells"] != met["Projectiles"], "services one to a part of %d" % slices)
		check_equal(met["actor 3"], 3 % slices, "a body by its id, of %d" % slices)


func test_the_bodies_go_by_actor_id_not_by_tree_order() -> void:
	var first: Body = _body("first")
	var second: Body = _body("second")
	# Freed ids are taken again lowest first: the body made last gets the lowest id.
	_actors.close(first.id)
	first.id = ActorsScript.NONE
	first.queue_free()
	await process_frame
	var third: Body = _body("third")
	check(third.id < second.id, "the newest body has the lower id")
	calls.clear()
	_tick.run(TickScript.DT)
	check_equal(_names().filter(func(n: String) -> bool: return n.begins_with("body")), ["body third", "body second"], "by id")


func test_what_is_switched_off_is_not_stepped() -> void:
	var off: Body = _body("off")
	off.set_physics_process(false)
	_areas.get_node(^"Spells").set_physics_process(false)
	_areas.get_node(^"Flow").set_process(false)
	(_areas.get_node(^"Frames") as Area).auto_tick = false
	_tick.run(TickScript.DT)
	for name in ["body off", "Spells.step", "Flow.step", "Frames.tick"]:
		check(not _names().has(name), "%s not stepped" % name)
	check(_names().has("Combat.step"), "the rest stepped")


## A hold (online-ready N4: a downed wizard, a boss's death) stands the simulation still for its
## ticks: they count, and only the frames run (their presses carry, `Frames.stood`).
func test_a_held_game_runs_only_the_frames_for_its_ticks() -> void:
	_body("a")
	_tick.hold(2)
	_tick.run(TickScript.DT)
	_tick.run(TickScript.DT)
	check_equal(_names(), ["Frames.tick", "Frames.stood", "Frames.tick", "Frames.stood"], "only the frames, and their presses kept")
	check_equal(_tick.count, 2, "the held ticks count")
	check_equal(_tick.sim.hold_left, 0, "the hold is spent")
	calls.clear()
	_tick.run(TickScript.DT)
	check(_names().has("body a") and not _names().has("Frames.stood"), "then the game steps again")


## A stop (the horde's build break, the pause menu) lasts until its `go`; in a break the director's
## timers run on (a joiner's bag), but not while the menu stops the game too.
func test_a_stopped_game_runs_the_frames_and_the_breaks_timers() -> void:
	_body("a")
	_tick.stop(TickScript.HORDE_BREAK)
	_tick.run(TickScript.DT)
	check_equal(_names(), ["Frames.tick", "Horde.step_timers", "Frames.stood"], "the frames and the break's timers")
	calls.clear()
	_tick._on_pause_requested(0, 1)
	_tick.run(TickScript.DT)
	check_equal(_names(), ["Frames.tick", "Frames.stood"], "with the menu open too, only the frames")
	check(_tick.sim.stopped_for(TickScript.MENU), "the menu's command is a stop of its own")
	_tick.go(TickScript.HORDE_BREAK)
	calls.clear()
	_tick.run(TickScript.DT)
	check_equal(_names(), ["Frames.tick", "Frames.stood"], "the break over, the menu still stops it")
	_tick._on_pause_requested(0, 0)
	calls.clear()
	_tick.run(TickScript.DT)
	check(_names().has("body a"), "it steps again once nothing stops it")
	check_equal(_tick.count, 4, "every tick counted")


## The tree's pause is the picture's: a tree paused with the sim going (the pause menu while a replay
## plays) runs no tick at all, and the Tick pauses the tree while the sim is stopped.
func test_a_paused_tree_runs_no_tick_and_a_stop_pauses_the_tree() -> void:
	_body("a")
	root.add_child(_tick)
	paused = true
	await physics_frame
	await physics_frame
	check(calls.is_empty(), "no tick while the tree is paused and the sim goes")
	paused = false
	await physics_frame
	check(not calls.is_empty(), "ticks once the tree goes")
	_tick.stop(TickScript.MENU)
	_tick.call(&"_show_stop")
	check(paused, "a stopped sim pauses the tree")
	_tick.go(TickScript.MENU)
	_tick.call(&"_show_stop")
	check(not paused, "and lets it go with the game")
	root.remove_child(_tick)


func test_every_delta_is_the_physics_step() -> void:
	check_equal(TickScript.DT, 1.0 / float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60)), "DT is the project's physics step")
	_body("a")
	root.add_child(_tick)
	for i in 3:
		await physics_frame
	await physics_frame
	root.remove_child(_tick)
	check(calls.size() > 0, "the tick ran in the tree")
	for call: Array in calls:
		check_equal(call[1], TickScript.DT, "%s got DT" % call[0])


## A run's start (online-ready N3b): the clock counts from 0 again, and the services, then the horde
## director, are made fresh, in the tick's order; the rest is not asked.
func test_a_run_starts_the_clock_again_and_makes_the_areas_fresh() -> void:
	for i in 3:
		_tick.run(TickScript.DT)
	calls.clear()
	_tick.begin_run()
	check_equal(_tick.count, 0, "the clock from 0")
	var expected: Array[String] = []
	for area: String in ["Entities", "Projectiles", "Spells", "Combat", "Horde"]:
		expected.append("%s.take_rules" % area)
		expected.append("%s.begin_run" % area)
	check_equal(_names(), expected, "the areas made fresh, in order, each under the run's rules")
	_tick.run(TickScript.DT)
	check_equal(_tick.count, 1, "the run's first tick")


## A run takes this machine's rules, or a replay's while one deals them (online-ready N11), as a copy
## of its own: a later change of the machine's is the next run's.
func test_a_run_takes_the_machines_rules_or_a_replays() -> void:
	SessionRules.machine().shot_cap = 750
	_tick.begin_run()
	check_equal(_tick.sim.rules.shot_cap, 750, "the machine's")
	check(calls.has(["Projectiles.take_rules", 750.0]), "handed to the areas")
	SessionRules.machine().shot_cap = 1500
	check_equal(_tick.sim.rules.shot_cap, 750, "the run keeps its own")
	var replayed := SessionRules.new()
	replayed.shot_cap = 250
	SessionRules.begin(replayed)
	replayed.shot_cap = 4000
	_tick.begin_run()
	check_equal(_tick.sim.rules.shot_cap, 250, "a replay's while it deals them")
	SessionRules.end()
	_tick.begin_run()
	check_equal(_tick.sim.rules.shot_cap, 1500, "the machine's again after")


## A seat's "Max shots" in a run (`shot_cap_requested`, applied at the next tick by the frames):
## the run's cap from then on, handed to the areas; this machine's is the setting's, not the
## command's. A cap out of range or the same again does nothing.
func test_a_cap_request_changes_the_runs_cap() -> void:
	_tick.begin_run()
	calls.clear()
	_tick.apply_shot_cap(500)
	check_equal(_tick.sim.rules.shot_cap, 500, "the run's cap")
	check(calls.has(["Projectiles.take_rules", 500.0]), "handed to the areas")
	check_equal(SessionRules.machine().shot_cap, SessionRules.defaults().shot_cap, "not this machine's")
	calls.clear()
	_tick.apply_shot_cap(500)
	_tick.apply_shot_cap(0)
	_tick.apply_shot_cap(SessionRules.MAX_SHOT_CAP + 1)
	check(calls.is_empty() and _tick.sim.rules.shot_cap == 500, "the same cap or one out of range: nothing")


## Every autoload of a simulation script is either made fresh at a run's start (with a `begin_run`)
## or says why it need not be (`RENEWED_OTHERWISE`), so a new area cannot carry one run's state into
## the next unnoticed; and the state hash sees each (`STATE_AREAS`, N3c).
func test_every_simulation_autoload_starts_each_run_fresh_or_says_why() -> void:
	var autoloads: Dictionary[StringName, Script] = {}
	for info: Dictionary in ProjectSettings.get_property_list():
		var key: String = info["name"]
		if key.begins_with("autoload/"):
			var path: String = String(ProjectSettings.get_setting(key)).trim_prefix("*")
			autoloads[StringName(key.trim_prefix("autoload/"))] = load(path) as Script
	for area: StringName in autoloads:
		var script: Script = autoloads[area]
		if script == null or not StateWalk.is_simulation(script):
			continue
		var renewed: bool = TickScript.FRESH_AT_RUN.has(area)
		var otherwise: bool = TickScript.RENEWED_OTHERWISE.has(area)
		check(renewed != otherwise, "%s (%s) is a simulation area: list it in Tick.FRESH_AT_RUN (with a begin_run that calls SimFresh.renew) or in Tick.RENEWED_OTHERWISE with the reason it starts each run fresh (core/sim/README.md, \"A run's start\")" % [area, script.resource_path])
		if renewed:
			var methods: Array[String] = []
			for method: Dictionary in script.get_script_method_list():
				methods.append(String(method["name"]))
			check(methods.has("begin_run"), "%s is in Tick.FRESH_AT_RUN but has no begin_run" % area)
		# Its state is the game's: the hash and the desync report see it (N3c).
		check(TickScript.STATE_AREAS.has(area), "%s (%s) is a simulation area: list it in Tick.STATE_AREAS, so the state hash sees it (core/sim/README.md, \"The hash\")" % [area, script.resource_path])
	for area: StringName in TickScript.FRESH_AT_RUN + TickScript.RENEWED_OTHERWISE.keys() + TickScript.STATE_AREAS:
		check(autoloads.has(area), "Tick lists %s, which is no autoload (renamed?)" % area)
