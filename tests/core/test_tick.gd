extends "res://tests/support/suite.gd"
## The one clock (core/sim/tick.gd, online-ready N3): a tick runs the areas' steps in its written
## order (STEPS), the bodies by actor id, only what is ticking and may process, and every delta is
## DT. Stand-in areas join a Tick of the test's own (`add_area`, as `SimArea.join` does for the
## game's autoloads) and record what it asks of them.

const TickScript := preload("res://core/sim/tick.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const FramesScript := preload("res://core/sim/frames.gd")
## A stop of the test's own, which the Flow stand-in's step runs through (as an area's step may
## run through a stop it makes itself).
const OWN_STOP: StringName = &"own_stop"
const CoopScript := preload("res://gameplay/coop/coop.gd")

## Every call the stand-ins got this test: [what, delta].
var calls: Array = []


## An area: records each step it is asked for.
class Area:
	extends Node
	var calls: Array = []

	func _init(area_name: String, into: Array) -> void:
		name = area_name
		calls = into

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


## An area that keeps state by actor id, hashed id by id (`SimHash.ActorPart`, props W3), as Spells does
## by caster.
class ByActorArea:
	extends Area
	const BY_ACTOR: Array[StringName] = [&"by_id"]
	var by_id: Array[int] = []
	var shared: int = 0

	func actor_parts() -> int:
		return by_id.size()

	## An id with 0 has no share: no area.
	func actor_part(id: int) -> Array:
		return [by_id[id]] if by_id[id] != 0 else []

	func actor_part_problems() -> PackedStringArray:
		return PackedStringArray()


## The frames service: records its tick and its stood ticks, and says how many ticks a physics step
## runs (`due`).
class StandInFrames:
	extends FramesScript
	var calls: Array = []
	var due: int = 1
	var asked: int = 0

	func _ready() -> void:
		pass

	func begin_step(_delta: float) -> int:
		asked += 1
		return due

	func tick(delta: float) -> void:
		calls.append(["Frames.tick", delta])

	func stood() -> void:
		calls.append(["Frames.stood", 0.0])


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
var _frames: StandInFrames


func before_each() -> void:
	calls = []
	_areas = own(Node.new()) as Node
	root.add_child(_areas)
	_actors = ActorsScript.new()
	_actors.name = "Actors"
	_areas.add_child(_actors)
	_frames = StandInFrames.new()
	_frames.calls = calls
	_areas.add_child(_frames)
	_tick = own(TickScript.new()) as TickScript
	_tick.actors = _actors
	_tick.frames = _frames
	# The game's areas, as each joins in its `_ready`.
	_join("Entities").steps(&"Entities", _stand_in("Entities").step).renewed_by(_stand_in("Entities").begin_run)
	_join("Projectiles").steps(&"Projectiles", _stand_in("Projectiles").step).renewed_by(_stand_in("Projectiles").begin_run).takes_rules(_stand_in("Projectiles").take_rules)
	_join("Spells").steps(&"Spells", _stand_in("Spells").step).renewed_by(_stand_in("Spells").begin_run).takes_rules(_stand_in("Spells").take_rules)
	_join("Combat").steps(&"Combat", _stand_in("Combat").step).renewed_by(_stand_in("Combat").begin_run)
	_join("Flow").steps(&"Flow", _stand_in("Flow").step, [OWN_STOP] as Array[StringName]).fresh_because("a stand-in")
	_join("Coop").steps(&"Coop", _stand_in("Coop").step_rules).fresh_because("a stand-in")


func after_each() -> void:
	paused = false
	if is_instance_valid(_areas):
		_areas.queue_free()


## The stand-in area `area_name` (made on first ask).
func _stand_in(area_name: String) -> Area:
	var found: Area = _areas.get_node_or_null(NodePath(area_name)) as Area
	if found == null:
		found = Area.new(area_name, calls)
		_areas.add_child(found)
	return found


func _join(area_name: String) -> SimArea:
	return _tick.add_area(StringName(area_name), _stand_in(area_name))


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
	check_equal(_names(), ["Frames.tick", "Projectiles.step", "Spells.step", "Combat.step", "Entities.step", "body a", "Flow.step", "Coop.step_rules"], "the order")
	check_equal(_tick.count, 1, "one tick counted")


## `ticked` (netcode spike S4): once after every tick, when everything of it has stepped and the
## clock has moved on, held and stopped ticks too (a session follows every tick).
func test_ticked_is_sent_after_every_tick_has_stepped() -> void:
	_body("a")
	var seen: Array[Array] = []
	_tick.ticked.connect(func() -> void: seen.append([_tick.count, _names().back()]))
	_tick.run(TickScript.DT)
	check_equal(seen, [[1, "Coop.step_rules"]], "after the tick's last step, the clock moved on")
	_tick.sim.hold(1)
	_tick.run(TickScript.DT)
	check_equal(seen.size(), 2, "a held tick is a tick too")
	check_equal(seen[1], [2, "Frames.stood"], "after its frames stood")


## The game's state in parts (`SimHash.slice`, N3c): each area in exactly one part, the parts
## together the whole, the services spread one to a part, each body in the part of its id, and
## each part an area keeps by actor id ("Kept 3", as Spells' casters, props W3) in the part of
## that body.
func test_the_state_splits_into_parts_that_cover_it_once() -> void:
	for i in 5:
		_body("b%d" % i)
	var kept: ByActorArea = own(ByActorArea.new("Kept", calls)) as ByActorArea
	kept.by_id = [10, 11, 12, 13, 14, 0]
	var whole: Dictionary = _tick.state_areas()
	check(whole.has("Sim") and whole.has("Spells") and whole.has("Actors") and whole.has("actor 4"), "the whole names the sim, the areas, the actor table and the bodies: %s" % [whole.keys()])
	whole["Kept"] = kept
	var all: Dictionary = SimHash.split_by_actor(whole)
	check(all.has("Kept 4") and not all.has("Kept 5") and all["Kept"] is SimHash.ActorPart, "each actor's part is an area of its own (none for an empty share), and the area without them another: %s" % [all.keys()])
	var services: int = whole.size() - 5
	for slices: int in [1, 2, 7, 60]:
		var met: Dictionary = {}
		for slice in slices:
			for name: String in SimHash.slice(whole, slice, slices):
				check(not met.has(name), "%s is in one part of %d" % [name, slices])
				met[name] = slice
		check_equal(met.size(), all.size(), "the %d parts cover the whole" % slices)
		if slices >= services:
			check(met["Sim"] != met["Spells"] and met["Spells"] != met["Projectiles"], "services one to a part of %d" % slices)
		check_equal(met["actor 3"], 3 % slices, "a body by its id, of %d" % slices)
		check_equal(met["Kept 3"], 3 % slices, "an id's part with its body, of %d" % slices)
	# Hashed whole or spread, the same hashes.
	var spread: Dictionary[String, int] = {}
	for slice in 7:
		spread.merge(SimHash.areas(SimHash.slice(whole, slice, 7)))
	var at_once: Dictionary[String, int] = SimHash.areas(whole)
	for name: String in at_once:
		check_equal(spread.get(name), at_once[name], "%s hashes the same spread" % name)
	# An id's part changes its own hash only, and the area alone (`of`) is all of it.
	var before: int = SimHash.of(kept)
	kept.by_id[3] = 99
	var after: Dictionary[String, int] = SimHash.areas(whole)
	for name: String in at_once:
		check_equal(after[name] != at_once[name], name == "Kept 3", "a change of id 3 changes %s's hash: %s" % [name, name == "Kept 3"])
	check(SimHash.of(kept) != before, "the area alone is hashed whole")
	# The area less its parts still hashes its other members.
	kept.shared = 5
	var shared: Dictionary[String, int] = SimHash.areas(whole)
	check(shared["Kept"] != after["Kept"] and shared["Kept 3"] == after["Kept 3"], "a member not BY_ACTOR changes the area's own hash only")


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
	off.ticking = false
	check(_tick.set_ticking(_stand_in("Spells"), false), "Spells is an area of the tick")
	_tick.set_ticking(_stand_in("Flow"), false)
	_stand_in("Combat").process_mode = Node.PROCESS_MODE_DISABLED
	_frames.auto_tick = false
	_tick.run(TickScript.DT)
	for name in ["body off", "Spells.step", "Flow.step", "Combat.step", "Frames.tick"]:
		check(not _names().has(name), "%s not stepped" % name)
	check(_names().has("Projectiles.step"), "the rest stepped")
	var stranger: Node = own(Node.new()) as Node
	check(not _tick.set_ticking(stranger, false), "a node that is no area is not one")


## A hold (online-ready N4: a downed wizard, a boss's death) stands the simulation still for its
## ticks: they count, and only the frames run (their presses carry, `Frames.stood`).
func test_a_held_game_runs_only_the_frames_for_its_ticks() -> void:
	_body("a")
	_tick.sim.hold(2)
	_tick.run(TickScript.DT)
	_tick.run(TickScript.DT)
	check_equal(_names(), ["Frames.tick", "Frames.stood", "Frames.tick", "Frames.stood"], "only the frames, and their presses kept")
	check_equal(_tick.count, 2, "the held ticks count")
	check_equal(_tick.sim.hold_left, 0, "the hold is spent")
	calls.clear()
	_tick.run(TickScript.DT)
	check(_names().has("body a") and not _names().has("Frames.stood"), "then the game steps again")


## A stop (an area's own, the pause menu) lasts until its `go`; a step runs through the stops that
## are its own only: in its own stop the Flow stand-in steps on, but not while the menu stops the
## game too.
func test_a_stopped_game_runs_the_frames_and_the_steps_through_their_own_stops() -> void:
	_body("a")
	_tick.sim.stop(OWN_STOP)
	_tick.run(TickScript.DT)
	check_equal(_names(), ["Frames.tick", "Flow.step", "Frames.stood"], "the frames and the step through its own stop")
	calls.clear()
	_tick.sim.stop(CoopScript.MENU_OF[0])
	_tick.run(TickScript.DT)
	check_equal(_names(), ["Frames.tick", "Frames.stood"], "with the menu open too, only the frames")
	_tick.sim.go(OWN_STOP)
	calls.clear()
	_tick.run(TickScript.DT)
	check_equal(_names(), ["Frames.tick", "Frames.stood"], "its own stop over, the menu still stops it")
	_tick.sim.go(CoopScript.MENU_OF[0])
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
	_tick.sim.stop(CoopScript.MENU_OF[0])
	_tick.run(TickScript.DT)
	check(paused, "a stopped sim pauses the tree")
	_tick.sim.go(CoopScript.MENU_OF[0])
	_tick.run(TickScript.DT)
	check(not paused, "and lets it go with the game")
	root.remove_child(_tick)


## A physics step runs the ticks the frames service says (netcode spike S1): none while a live
## replay waits, up to three to catch up; it is asked every step, also under the picture's pause.
func test_a_physics_step_runs_the_ticks_the_frames_say() -> void:
	_frames.auto_tick = true
	root.add_child(_tick)
	await physics_frame
	_frames.due = 0
	await physics_frame
	calls.clear()
	var asked: int = _frames.asked
	await physics_frame
	await physics_frame
	check(calls.is_empty(), "no tick while it says none")
	check_equal(_frames.asked - asked, 2, "asked every step")
	_frames.due = 3
	await physics_frame
	calls.clear()
	asked = _frames.asked
	await physics_frame
	await physics_frame
	var ticks: int = _names().count("Frames.tick")
	check_equal(ticks, 3 * (_frames.asked - asked), "three ticks a step")
	check(ticks > 0, "and some ran")
	check_equal(_names().count("Combat.step"), ticks, "each a whole tick")
	_frames.due = 1
	paused = true
	asked = _frames.asked
	calls.clear()
	await physics_frame
	await physics_frame
	check(calls.is_empty(), "the picture's pause: no tick")
	check(_frames.asked > asked, "but still asked (a live replay reads what arrived)")
	paused = false
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


## A run's start (online-ready N3b): the clock counts from 0 again, every area that takes the rules
## takes the run's, then the services are made fresh in RUN_ORDER; the rest
## is not asked.
func test_a_run_starts_the_clock_again_and_makes_the_areas_fresh() -> void:
	for i in 3:
		_tick.run(TickScript.DT)
	calls.clear()
	_tick.begin_run()
	check_equal(_tick.count, 0, "the clock from 0")
	var expected: Array[String] = ["Projectiles.take_rules", "Spells.take_rules"]
	for area: String in ["Entities", "Projectiles", "Spells", "Combat"]:
		expected.append("%s.begin_run" % area)
	check_equal(_names(), expected, "the rules handed over, then the areas made fresh in order")
	_tick.run(TickScript.DT)
	check_equal(_tick.count, 1, "the run's first tick")


## A run takes the frames service's rules (online-ready N11): this machine's, or a replay's while one
## is on its deck, as a copy of its own: a later change of the machine's is the next run's.
func test_a_run_takes_the_machines_rules_or_a_replays() -> void:
	SessionRules.machine().shot_cap = 750
	_tick.begin_run()
	check_equal(_tick.sim.rules.shot_cap, 750, "the machine's")
	check(calls.has(["Projectiles.take_rules", 750.0]), "handed to the areas")
	SessionRules.machine().shot_cap = 1500
	check_equal(_tick.sim.rules.shot_cap, 750, "the run keeps its own")
	var replay := Replay.new()
	replay.rules.shot_cap = 250
	_frames.set(&"_tape", ReplayTape.playing(replay))
	_tick.begin_run()
	check_equal(_tick.sim.rules.shot_cap, 250, "a replay's while it is on the deck")
	replay.rules.shot_cap = 4000
	check_equal(_tick.sim.rules.shot_cap, 250, "a copy of it")
	_frames.set(&"_tape", null)
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


## Every autoload of a simulation script joins the game's Tick, and is made fresh at a run's start
## (`renewed_by`, in RUN_ORDER) or says why it need not be (`fresh_because`), so a new area cannot
## carry one run's state into the next unnoticed; every area joined is part of the state hash (N3c),
## and every step it takes is one of STEPS.
func test_every_simulation_autoload_joins_the_tick_and_starts_each_run_fresh_or_says_why() -> void:
	var game: TickScript = root.get_node_or_null(^"Tick") as TickScript
	check(game != null, "the Tick autoload")
	if game == null:
		return
	var autoloads: Dictionary[StringName, Script] = {}
	for info: Dictionary in ProjectSettings.get_property_list():
		var key: String = info["name"]
		if key.begins_with("autoload/"):
			var path: String = String(ProjectSettings.get_setting(key)).trim_prefix("*")
			autoloads[StringName(key.trim_prefix("autoload/"))] = load(path) as Script
	var state: Dictionary = game.state_areas()
	for name: StringName in autoloads:
		var script: Script = autoloads[name]
		if script == null or not StateWalk.is_simulation(script) or name == TickScript.ACTORS:
			continue
		var joined: SimArea = game.area(name)
		check(joined != null, "%s (%s) is a simulation area: join the Tick in its _ready (`SimArea.join(self, &\"%s\")`, core/sim/sim_area.gd)" % [name, script.resource_path, name])
		if joined == null:
			continue
		var renewed: bool = joined.begin_run.is_valid()
		var otherwise: bool = joined.fresh_otherwise != ""
		check(renewed != otherwise, "%s: either renewed_by(begin_run) (a begin_run that calls SimFresh.renew) or fresh_because(the reason it starts each run fresh) (core/sim/README.md, \"A run's start\")" % name)
		if renewed:
			check(TickScript.RUN_ORDER.has(name), "%s is renewed at a run's start: list it in Tick.RUN_ORDER" % name)
		check(state.has(String(name)), "%s is part of the state hash (Tick.state_areas)" % name)
		for step in joined.step_list:
			check(TickScript.STEPS.has(step.key) and step.key != TickScript.BODIES, "%s's step %s is one of Tick.STEPS" % [name, step.key])
	check(state.has(String(TickScript.ACTORS)), "the actor table is part of the state hash")
	for name: StringName in TickScript.RUN_ORDER:
		check(autoloads.has(name), "Tick.RUN_ORDER lists %s, which is no autoload (renamed?)" % name)
