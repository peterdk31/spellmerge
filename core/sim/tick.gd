extends Node
## The one clock (online-ready N3, docs/milestones/online-ready.md; the autoload "Tick"): the only
## driver of the simulation. Each physics frame it runs one tick, in this written order:
##
## 1. **The input frames** (`Frames.tick`): each seat's frame for the tick, and the commands.
## 2. **The services:** the projectile manager, Spells, Combat, Entities (decoys, familiars, the AI
##    board), then the horde's swarm.
## 3. **The actors' bodies, by actor id** (`Actor.tick_step`: its step, then its move).
## 4. **The run's rules and timers:** Flow's (the intro, the next wave, the restart), Coop's (the
##    view the camera is fitted to, the revives), the horde director's (its spawns, offers, breaks).
##
## This is the order the scene tree gave them before N3 (the autoloads first, in project order, then
## the bodies of the world, then the frame's `_process` timers), so the game plays as it did; the
## bodies now go by id, not by when they joined the tree. Nothing in the simulation has a
## `_physics_process` or a `_process` of its own for the game; drawing stays in `_process` (view).
##
## **What the tick steps:** an area or a body is stepped while its physics processing is on (the
## timers: its processing) and it can process (its process mode; the tree is never paused then). It has no callback: the flag only
## says "the tick steps me", so a test that steps a body by hand turns it off as it always did
## (`set_physics_process(false)`), and a body another area steps (a decoy: Entities) is off.
##
## **Stops are the game's state** (online-ready N4; `sim.gd`): while the sim is held (`hold`: a
## downed wizard, a boss's death, a number of ticks) or stopped (`stop(reason)`: the horde's build
## break, the pause menu), a tick runs the input frames and nothing else, but the horde director's
## break (its picks and a joiner's bag) while the break stops the game. Presses made meanwhile carry
## to the first tick that steps (`Frames.stood`). The tree's pause is only the picture's: the Tick
## pauses the tree while the sim is stopped (not while it is held: the drawing runs on through a
## hold), and nothing in the simulation reads it. A tree paused while the sim is not stopped (the
## pause menu while a replay plays) runs no tick at all.
##
## **Time:** `step(delta)` keeps its signature everywhere, and the delta is always `DT`, 1/60 of a
## second: the game never scales the engine's time (N4). A slow frame runs up to
## `max_physics_steps_per_frame` ticks; a faster game (a test, a benchmark) raises the tick rate,
## `Engine.physics_ticks_per_second`. `count` is the ticks since the run began (`begin_run`), or
## since the game began before any run, stopped and held ticks too.
##
## **The run's rules** (online-ready N11, core/sim/session_rules.gd): `begin_run` sets `sim.rules`
## (a replay's, else this machine's) and hands them to every area of FRESH_AT_RUN that takes them
## (`take_rules(rules)`) before it is renewed, so it renews under them. This machine's "Max shots"
## (`projectile_cap_changed`) is heard here and goes to the next run; a change while a run plays is
## the command `shot_cap_requested`, applied at the next tick's start (and recorded with it).
##
## No `class_name` (it would hide the autoload): preload it, `const TickScript := preload(...)`, for
## `TickScript.DT`.

const ActorsScript := preload("res://core/actors/actors.gd")
const EventsScript := preload("res://core/events/events.gd")

## A tick's seconds: 60 ticks a second (owner decision 4, online-ready.md).
const DT: float = 1.0 / 60.0
## Before every other node's physics step.
const PRIORITY: int = -1000
## The reasons the game stops for (`stop`): the horde's build break, and offline the pause menu.
const HORDE_BREAK: StringName = &"horde_break"
const MENU: StringName = &"menu"
## The services stepped in step 2, in order: their autoload names.
const SERVICES: Array[StringName] = [&"Projectiles", &"Spells", &"Combat", &"Entities"]
## What a run's start makes fresh (`begin_run`), in order: Entities first, whose `begin_run` frees
## the last run's decoys (bodies outside Flow's world, still registered in the manager and Combat),
## so no service is renewed under a body that leaves after; then the other services in the tick's
## order, then the horde director; the actor table last, once every area has let its bodies go: its
## births count from 0 again (the keys, N5). Every autoload of a simulation script is here or in
## RENEWED_OTHERWISE (`tests/core/test_tick.gd`).
const FRESH_AT_RUN: Array[StringName] = [&"Entities", &"Projectiles", &"Spells", &"Combat", &"Horde", &"Actors"]
## The autoloads of simulation scripts a run's start does not renew, and why each starts a run as a
## fresh game's all the same (the replay test's "after other runs" hashes them too).
const RENEWED_OTHERWISE: Dictionary[StringName, String] = {
	&"Flow": "it starts the run: start_run sets the run's members itself",
	&"Coop": "the seats' joins are the session's; room_entered sets the run's view, wizards and revives",
}

## The areas whose state is the game's, by autoload name, for `state_areas` (with the sim and the
## bodies): the hash, the desync report and later snapshots.
const STATE_AREAS: Array[StringName] = [&"Actors", &"Projectiles", &"Spells", &"Combat", &"Entities", &"Flow", &"Coop", &"Horde"]

## Ticks since the run began (or the game, before any run).
var count: int = 0
## The game's time and chance (`sim.gd`, online-ready N3c): the tick (`count`) and the run's seed,
## dealt at each run's start. Areas and bodies take it as their `sim` (`Sim.found`).
var sim: Sim = Sim.new()
## Where the areas are found by name. Only tests set this (stand-ins); otherwise the tree's root.
var areas: Node = null
## The event bus (the "Events" autoload, found in `_ready`; tests may set it).
var events: EventsScript = null
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
	if events != null:
		if not events.projectile_cap_changed.is_connected(_on_machine_cap):
			events.projectile_cap_changed.connect(_on_machine_cap)
		events.listen(&"shot_cap_requested", _on_shot_cap_requested)
		events.listen(&"pause_requested", _on_pause_requested)


## The pause menu opened or closed (a command, at a tick's start): offline the game stops while it
## is open (one menu is open at a time, MENU).
func _on_pause_requested(_player: int, on: int) -> void:
	if on != 0:
		sim.stop(MENU)
	else:
		sim.go(MENU)


func _physics_process(_delta: float) -> void:
	# A pause not the sim's (the pause menu while a replay plays): the picture's alone, so no tick
	# (the replay waits).
	if get_tree().paused and not _shown_stopped:
		return
	run(DT)


## One tick of `delta` seconds (the game's is always DT), in the written order (see the class doc).
func run(delta: float) -> void:
	var root: Node = areas if areas != null else get_tree().root
	sim.tick = count
	# The frames run in every tick, stopped and held too (the horde's break takes its picks then).
	var frames: Node = root.get_node_or_null(^"Frames")
	var ticks_frames: bool = frames != null and bool(frames.get(&"auto_tick"))
	if ticks_frames:
		frames.call(&"tick", delta)
	# The frames' commands may have stopped the game or let it go: the picture follows at once, so
	# the tree is never paused while the tick steps.
	if areas == null:
		_show_stop()
	if sim.stands_still():
		_stand_still(root, delta)
		if ticks_frames:
			frames.call(&"stood")
		count += 1
		return
	for service in SERVICES:
		var area: Node = root.get_node_or_null(NodePath(service))
		if area != null and _steps(area):
			area.call(&"step", delta)
	var horde: Node = root.get_node_or_null(^"Horde")
	if horde != null and _steps(horde):
		horde.call(&"physics_step", delta)
	_step_bodies(root.get_node_or_null(^"Actors") as ActorsScript, delta)
	var flow: Node = root.get_node_or_null(^"Flow")
	if flow != null and _times(flow):
		flow.call(&"step", delta)
	var coop: Node = root.get_node_or_null(^"Coop")
	if coop != null and _times(coop):
		coop.call(&"step_rules", delta)
	if horde != null and _times(horde):
		horde.call(&"step_timers", delta)
	count += 1


## A tick the simulation stands still: a hold's tick is spent (a stop's waits for its `go`), and
## the horde's break runs on while the break stops the game (but not while the pause menu does).
func _stand_still(root: Node, delta: float) -> void:
	if sim.is_stopped():
		var horde: Node = root.get_node_or_null(^"Horde")
		if horde != null and sim.stopped_for(HORDE_BREAK) and not sim.stopped_for(MENU) and _times(horde):
			horde.call(&"step_timers", delta)
		return
	sim.hold_left -= 1


## The tree's pause follows the sim's stop (the picture stands while the game is stopped); set
## only when it changes, so a test's own pause is left alone.
func _show_stop() -> void:
	var stopped: bool = sim.is_stopped()
	if stopped != _shown_stopped:
		_shown_stopped = stopped
		get_tree().paused = stopped


## The whole simulation stands still for `ticks` ticks (a downed wizard, a boss's death).
func hold(ticks: int) -> void:
	sim.hold(ticks)


## The game stops for `reason` (HORDE_BREAK, MENU) until `go(reason)`.
func stop(reason: StringName) -> void:
	sim.stop(reason)


func go(reason: StringName) -> void:
	sim.go(reason)


## A run starts (Flow, once the last run's world is gone and before the new one is made;
## online-ready N3b): the clock counts from 0 again, the run takes its seed (`SimSeed.fresh`: a
## replay's while one records or plays, else random; N3c), and every service takes a fresh game's
## state (its `begin_run`; core/sim/sim_fresh.gd), in FRESH_AT_RUN's order. So
## a run plays the same whatever ran before it in this game, and a replay recorded in any run plays
## the same in any other.
func begin_run() -> void:
	count = 0
	sim.tick = 0
	# The last run's stops and hold end with it (a new run starts with the game going).
	sim.hold_left = 0
	sim.stops.clear()
	sim.run_seed = SimSeed.fresh()
	sim.rules = SessionRules.for_run()
	var root: Node = areas if areas != null else get_tree().root
	for service in FRESH_AT_RUN:
		var area: Node = root.get_node_or_null(NodePath(service))
		if area == null:
			continue
		if area.has_method(&"take_rules"):
			area.call(&"take_rules", sim.rules)
		if not area.has_method(&"begin_run"):
			push_error("Tick: %s has no begin_run, so it keeps the last run's state (core/sim/sim_fresh.gd)" % service)
			continue
		area.call(&"begin_run")


## This machine's "Max shots" changed (the pause menu's setting, or the saved one loaded): the
## cap the next run takes. A run playing now changes only by the command (`shot_cap_requested`).
func _on_machine_cap(cap: int) -> void:
	SessionRules.machine().shot_cap = cap


## The command `shot_cap_requested` (a seat moved "Max shots" in a run; online-ready N11): the run's
## shot cap from this tick on, handed to the areas that take the rules (the shots in the air end).
func apply_shot_cap(cap: int) -> void:
	if cap < 1 or cap > SessionRules.MAX_SHOT_CAP or cap == sim.rules.shot_cap:
		return
	sim.rules.shot_cap = cap
	var root: Node = areas if areas != null else get_tree().root
	for service in FRESH_AT_RUN:
		var area: Node = root.get_node_or_null(NodePath(service))
		if area != null and area.has_method(&"take_rules"):
			area.call(&"take_rules", sim.rules)


func _on_shot_cap_requested(_seat: int, cap: int) -> void:
	apply_shot_cap(cap)


## The game's state by area (online-ready N1's `SimHash.areas`, `Desync.capture`): "Sim" (the tick
## and the run's seed), each of STATE_AREAS there is, then every actor's body by actor id
## ("actor 3"). Areas never reach into each other: the tick names them (N3c).
func state_areas() -> Dictionary:
	var root: Node = areas if areas != null else get_tree().root
	var out: Dictionary = {"Sim": sim}
	for name in STATE_AREAS:
		var area: Node = root.get_node_or_null(NodePath(name))
		if area != null:
			out[String(name)] = area
	var actors: ActorsScript = root.get_node_or_null(^"Actors") as ActorsScript
	if actors != null:
		var n: int = actors.open_ids(_ids)
		for i in n:
			# Actor bodies only: a swarm row's target node holds an id too, and is the swarm's.
			var body: Actor = actors.node_of(_ids[i]) as Actor
			if body != null:
				out["actor %d" % _ids[i]] = body
	return out


## Part `slice` (0 to `slices` - 1) of `state_areas()`, so a check of the whole state can be spread
## over `slices` ticks (N3c: hashing it all in one tick took tens of milliseconds in a crowd; a
## netcode checking once a second hashes part `count % 60` each tick, and every machine hashes the
## same part at the same tick). "Sim" and STATE_AREAS go one to a part, spread evenly; a body goes
## to part `id % slices`. Each area is in exactly one part.
func state_slice(slice: int, slices: int) -> Dictionary:
	var all: Dictionary = state_areas()
	if slices <= 1:
		return all
	var out: Dictionary = {}
	var services: int = STATE_AREAS.size() + 1
	for name: String in all:
		var part: int
		if name.begins_with("actor "):
			part = posmod(int(name.trim_prefix("actor ")), slices)
		else:
			var index: int = 0 if name == "Sim" else STATE_AREAS.find(StringName(name)) + 1
			part = floori(float(index) * float(slices) / float(services))
		if part == slice:
			out[name] = all[name]
	return out


## Every actor's body by id: those open when the bodies' turn starts (a body made during it takes
## its first step next tick).
func _step_bodies(actors: ActorsScript, delta: float) -> void:
	if actors == null:
		return
	var n: int = actors.open_ids(_ids)
	for i in n:
		var body: Actor = actors.node_of(_ids[i]) as Actor
		if body != null and body.is_inside_tree() and _steps(body):
			body.tick_step(delta)


## True when the tick steps `node` now (its physics processing on, and it can process: in the game
## the tree is never paused while the tick steps, so this is its process mode).
static func _steps(node: Node) -> bool:
	return node.is_physics_processing() and node.can_process()


## True when the tick runs `node`'s timers now (its processing on, and it can process).
static func _times(node: Node) -> bool:
	return node.is_processing() and node.can_process()
