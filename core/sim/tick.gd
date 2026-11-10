extends Node
## The one clock (online-ready N3, docs/milestones/online-ready.md; the autoload "Tick"): the only
## driver of the simulation. Each physics frame it runs one tick:
##
## 1. **The input frames** (`Frames.tick`): each seat's frame for the tick, and the commands.
## 2. **The areas' steps, in STEPS' written order**, the actors' bodies among them (BODIES: every
##    body by actor id, `Actor.tick_step`: its step, then its move).
##
## The Tick knows no area. Each joins it in its `_ready` (`SimArea.join`, core/sim/sim_area.gd)
## and names its steps, its run's start and the rules it takes; the Tick calls those, in the order
## of STEPS and RUN_ORDER, the keys it is written in. So the order is written in one place and nothing else
## is: a new area adds its key here and joins. The keys are only names; the Tick calls nothing by
## name. Only the actor table (core/actors) and the frames service are its own, by type.
##
## This is the order the scene tree gave them before N3 (the autoloads first, in project order,
## then the bodies of the world, then the frame's `_process` timers), so the game plays as it did.
## Nothing in the simulation has a `_physics_process` or a `_process` of its own for the game;
## drawing stays in `_process` (view).
##
## **What the tick steps:** an area while it is `ticking` and its node may process
## (`SimArea.is_stepped`); a body while its own `ticking` is on (an Actor's; a decoy, which
## Entities steps, is off). `set_ticking` turns an area off, so a test steps it by hand.
##
## **Stops are the game's state** (online-ready N4; `sim.gd`): while the sim is stopped
## (`stop(reason)`: the pause menu) a tick runs the input frames and only
## the steps that run through every reason it is stopped for (`SimArea.Step.own_stops`); while it
## is held (`hold`: a downed wizard, a boss's death, a number of ticks), the frames alone. Presses
## made meanwhile carry to the first tick that steps (`Frames.stood`). The tree's pause is only the
## picture's: the Tick pauses the tree while the sim is stopped (not while it is held: the drawing
## runs on through a hold), and nothing in the simulation reads it. A tree paused while the sim is
## not stopped (the pause menu while a replay plays) runs no tick at all.
##
## **Time:** `step(delta)` keeps its signature everywhere, and the delta is always `DT`, 1/60 of a
## second: the game never scales the engine's time (N4). A physics step runs the ticks the frames
## service says (`Frames.begin_step`): one, but for a live replay (the online client; netcode spike
## S1) none while its next tick has not arrived and up to three to catch up. A slow frame runs up
## to `max_physics_steps_per_frame` physics steps; a faster game (a test, a benchmark) raises the tick rate,
## `Engine.physics_ticks_per_second`. `count` is the ticks since the run began (`begin_run`), or
## since the game began before any run, stopped and held ticks too.
##
## **A run's start** (`begin_run`, online-ready N3b and N11): the run's seed and rules come from the
## frames service (a replay's while one records or plays, else this machine's; `Frames.next_run`),
## the rules go to every area that takes them, then each area is renewed in RUN_ORDER, the actor
## table last. A change to the rules while a run plays is the command `shot_cap_requested`, applied
## at the next tick's start (and recorded with it).
##
## No `class_name` (it would hide the autoload): preload it, `const TickScript := preload(...)`.

const ActorsScript := preload("res://core/actors/actors.gd")
const EventsScript := preload("res://core/events/events.gd")
const FramesScript := preload("res://core/sim/frames.gd")

## A tick's seconds: 60 ticks a second (owner decision 4, online-ready.md).
const DT: float = 1.0 / 60.0
## Before every other node's physics step.
const PRIORITY: int = -1000
## The step of the actors' bodies, the Tick's own.
const BODIES: StringName = &"bodies"
## The written order of the steps (`SimArea.steps`' keys): the services, the bodies, then the
## run's rules and timers (Flow's: the intro, the next wave, the restart; Coop's: the view the
## camera is fitted to, the revives).
const STEPS: Array[StringName] = [&"Projectiles", &"Spells", &"Combat", &"Entities", BODIES, &"Flow", &"Coop"]
## The order areas are renewed in at a run's start (`SimArea.renewed_by`): Entities first, whose
## `begin_run` frees the last run's decoys (bodies outside Flow's world, still registered in the
## manager and Combat), so no area is renewed under a body that leaves after; then the services in
## the tick's order. The actor table goes last, once every area has let its bodies go: its births
## count from 0 again (the keys, N5).
const RUN_ORDER: Array[StringName] = [&"Entities", &"Projectiles", &"Spells", &"Combat"]
## The name the actor table is part of the state under.
const ACTORS: StringName = &"Actors"

## A tick has stepped (the last thing `run` does: its frames, its steps, the clock moved on). For
## whoever follows the game tick by tick from outside the simulation (the netcode's sessions, net/:
## they send the tick and hash its state). Nothing in the simulation may hear it: an area that
## steps joins STEPS.
signal ticked

## Ticks since the run began (or the game, before any run): the game's clock, `sim.tick`, which is
## state (a snapshot restores it, online-ready N10). Read only.
var count: int:
	get:
		return sim.tick
## The game's time and chance (`sim.gd`, online-ready N3c): the tick (`count`) and the run's seed,
## dealt at each run's start. Areas and bodies take it as their `sim` (`Sim.found`).
var sim: Sim = Sim.new()
## The services the Tick drives by type. Only tests set these; otherwise the autoloads.
var events: EventsScript = null
var frames: FramesScript = null
var actors: ActorsScript = null

## The areas joined, by name, in the order they joined.
var _areas: Dictionary[StringName, SimArea] = {}
## Every area's steps in STEPS' order, and the area of each (rebuilt when steps are added).
var _order: Array[SimArea.Step] = []
var _order_area: Array[SimArea] = []
## The steps `_order` was built from (`_steps_known`), to see one added since.
var _steps_seen: int = -1
## Whether the tree's pause last shown was the sim's stop (`_show_stop`).
var _shown_stopped: bool = false
## The open actor ids of this tick, in order (reused).
var _ids: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = PRIORITY


func _ready() -> void:
	if events == null:
		events = get_node_or_null(^"/root/Events") as EventsScript
	if frames == null:
		frames = get_node_or_null(^"/root/Frames") as FramesScript
	if actors == null:
		actors = get_node_or_null(^"/root/Actors") as ActorsScript
	if events != null:
		events.listen(&"shot_cap_requested", _on_shot_cap_requested)


## The game's Tick for a node in the game's tree (the autoload), else null. Typed callers take it
## `as TickScript`.
static func of(node: Node) -> Node:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_node_or_null(^"/root/Tick")


## Add `node` as the area `name` (`SimArea.join` does this for the game's autoloads; tests call it with
## stand-ins). An area joined again under its name replaces the first.
func add_area(name: StringName, node: Node) -> SimArea:
	var area := SimArea.new(name, node)
	_areas[name] = area
	_steps_seen = -1
	return area


## The area joined as `name`, or null.
func area(name: StringName) -> SimArea:
	return _areas.get(name, null) as SimArea


## The tick steps the area whose node is `node` (`on`) or leaves it to its owner (a test that
## steps it by hand). False when `node` is no area of this Tick's.
func set_ticking(node: Node, on: bool) -> bool:
	for name: StringName in _areas:
		var joined: SimArea = _areas[name]
		if joined.node == node:
			joined.ticking = on
			return true
	return false


func _physics_process(_delta: float) -> void:
	# First, also under a picture's pause: a live replay's feed reads what arrived and sends.
	var due: int = frames.begin_step(DT) if frames != null and frames.auto_tick else 1
	# A pause not the sim's (the pause menu while a replay plays): the picture's alone, so no tick
	# (the replay waits).
	if get_tree().paused and not _shown_stopped:
		return
	for i in due:
		run(DT)


## One tick of `delta` seconds (the game's is always DT), in the written order (see the class doc).
func run(delta: float) -> void:
	# The frames run in every tick, stopped and held too (a command still arrives then).
	var ticks_frames: bool = frames != null and frames.auto_tick
	if ticks_frames:
		frames.tick(delta)
	# The frames' commands may have stopped the game or let it go: the picture follows at once, so
	# the tree is never paused while the tick steps.
	if is_inside_tree():
		_show_stop()
	var stopped: bool = sim.is_stopped()
	var held: bool = not stopped and sim.hold_left > 0
	if held:
		sim.hold_left -= 1
	else:
		_run_steps(delta, stopped)
	if (stopped or held) and ticks_frames:
		frames.stood()
	sim.tick += 1
	ticked.emit()


## Every step in order; while the game is stopped, only those that run through its stops.
func _run_steps(delta: float, stopped: bool) -> void:
	if _steps_seen != _steps_known():
		_build_order()
	for i in _order.size():
		var step: SimArea.Step = _order[i]
		if stopped and not step.runs_through(sim.stops):
			continue
		if step.key == BODIES:
			_step_bodies(delta)
		elif _order_area[i].is_stepped() and step.call.is_valid():
			step.call.call(delta)


## The steps in STEPS' order: each area's under its key, in the order the areas joined; BODIES once,
## the Tick's own. A key outside STEPS is an error (its area is not stepped there).
func _build_order() -> void:
	_order.clear()
	_order_area.clear()
	for key in STEPS:
		if key == BODIES:
			var bodies := SimArea.Step.new()
			bodies.key = BODIES
			_order.append(bodies)
			_order_area.append(null)
			continue
		for name: StringName in _areas:
			var joined: SimArea = _areas[name]
			for step in joined.step_list:
				if step.key == key:
					_order.append(step)
					_order_area.append(joined)
	for name: StringName in _areas:
		for step in (_areas[name] as SimArea).step_list:
			if not STEPS.has(step.key) or step.key == BODIES:
				push_error("Tick: %s's step %s is not one of Tick.STEPS, so it is never run (core/sim/tick.gd)" % [name, step.key])
	_steps_seen = _steps_known()


func _steps_known() -> int:
	var n: int = 0
	for name: StringName in _areas:
		n += (_areas[name] as SimArea).step_list.size()
	return n


## The tree's pause follows the sim's stop (the picture stands while the game is stopped); set
## only when it changes, so a test's own pause is left alone.
func _show_stop() -> void:
	var stopped: bool = sim.is_stopped()
	if stopped != _shown_stopped:
		_shown_stopped = stopped
		get_tree().paused = stopped


## A run starts (Flow, once the last run's world is gone and before the new one is made;
## online-ready N3b): the clock counts from 0 again, the run takes its seed and rules (the frames
## service's: a replay's while one records or plays, else random and this machine's), every area
## takes the rules, then a fresh game's state (its `begin_run`, core/sim/sim_fresh.gd) in
## RUN_ORDER, and the actor table last. So a run plays the same whatever ran before it in this
## game, and a replay recorded in any run plays the same in any other.
func begin_run() -> void:
	sim.tick = 0
	# The last run's stops and hold end with it (a new run starts with the game going).
	sim.hold_left = 0
	sim.stops.clear()
	if frames != null:
		sim.run_seed = frames.next_run_seed()
		sim.rules = frames.next_run_rules()
	else:
		sim.run_seed = SimSeed.fresh()
		sim.rules = SessionRules.machine().copy()
	_hand_rules()
	for name in RUN_ORDER:
		var joined: SimArea = area(name)
		if joined != null and joined.begin_run.is_valid():
			joined.begin_run.call()
	for name: StringName in _areas:
		var joined: SimArea = _areas[name]
		if not RUN_ORDER.has(name) and joined.begin_run.is_valid():
			push_error("Tick: %s is renewed by its begin_run but is not in Tick.RUN_ORDER, so it keeps the last run's state (core/sim/tick.gd)" % name)
	if actors != null:
		actors.begin_run()


## The command `shot_cap_requested` (a seat moved "Max shots" in a run; online-ready N11): the run's
## shot cap from this tick on, handed to the areas that take the rules (the shots in the air end).
func apply_shot_cap(cap: int) -> void:
	if cap < 1 or cap > SessionRules.MAX_SHOT_CAP or cap == sim.rules.shot_cap:
		return
	sim.rules.shot_cap = cap
	_hand_rules()


func _on_shot_cap_requested(_seat: int, cap: int) -> void:
	apply_shot_cap(cap)


## The run's rules to every area that takes them.
func _hand_rules() -> void:
	for name: StringName in _areas:
		var joined: SimArea = _areas[name]
		if joined.take_rules.is_valid():
			joined.take_rules.call(sim.rules)


## The game's state by area (online-ready N1's `SimHash.areas`, `Desync.capture`): "Sim" (the tick
## and the run's seed), each area joined, the actor table, then every actor's body by actor id
## ("actor 3"). `SimHash.slice` spreads it over ticks.
func state_areas() -> Dictionary:
	var out: Dictionary = {"Sim": sim}
	for name: StringName in _areas:
		var node: Node = (_areas[name] as SimArea).node
		if node != null and is_instance_valid(node):
			out[String(name)] = node
	if actors != null:
		out[String(ACTORS)] = actors
		var n: int = actors.open_ids(_ids)
		for i in n:
			# Actor bodies only: a plain Combat body (a stand-in) holds an id too, and is its maker's.
			var body: Actor = actors.node_of(_ids[i]) as Actor
			if body != null:
				out[SimHash.BODY_PREFIX + str(_ids[i])] = body
	return out


## Every actor's body by id: those open when the bodies' turn starts (a body made during it takes
## its first step next tick).
func _step_bodies(delta: float) -> void:
	if actors == null:
		return
	var n: int = actors.open_ids(_ids)
	for i in n:
		var body: Actor = actors.node_of(_ids[i]) as Actor
		if body != null and body.ticking and body.is_inside_tree() and body.can_process():
			body.tick_step(delta)
