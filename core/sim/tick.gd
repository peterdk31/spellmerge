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
## timers: its processing) and it can process (`Node.can_process`: the tree's pause and its process
## mode, as before). It has no callback: the flag only says "the tick steps me", so a test that
## steps a body by hand turns it off as it always did (`set_physics_process(false)`), and a body
## another area steps (a decoy: Entities) is off.
##
## **Time:** `step(delta)` keeps its signature everywhere, and the delta is the physics step's: 1/60
## of a second (`DT`), except while Feel's stops scale the engine's time (A1; N4 counts them in
## ticks). A slow frame runs up to `max_physics_steps_per_frame` ticks and never changes the delta.
## `count` is the ticks since the run began (`begin_run`), or since the game began before any run.
##
## No `class_name` (it would hide the autoload): preload it, `const TickScript := preload(...)`, for
## `TickScript.DT`.

const ActorsScript := preload("res://core/actors/actors.gd")

## A tick's seconds: 60 ticks a second (owner decision 4, online-ready.md).
const DT: float = 1.0 / 60.0
## Before every other node's physics step.
const PRIORITY: int = -1000
## The services stepped in step 2, in order: their autoload names.
const SERVICES: Array[StringName] = [&"Projectiles", &"Spells", &"Combat", &"Entities"]
## What a run's start makes fresh (`begin_run`), in order: the services, then the horde director.
## Every autoload of a simulation script is here or in RENEWED_OTHERWISE (`tests/core/test_tick.gd`).
const FRESH_AT_RUN: Array[StringName] = [&"Projectiles", &"Spells", &"Combat", &"Entities", &"Horde"]
## The autoloads of simulation scripts a run's start does not renew, and why each starts a run as a
## fresh game's all the same (the replay test's "after other runs" hashes them too).
const RENEWED_OTHERWISE: Dictionary[StringName, String] = {
	&"Actors": "every body closes its own id as it leaves the tree, and the last run's bodies have left",
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

## The open actor ids of this tick, in order (reused).
var _ids: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = PRIORITY


func _physics_process(delta: float) -> void:
	run(delta)


## One tick of `delta` seconds, in the written order (see the class doc).
func run(delta: float) -> void:
	var root: Node = areas if areas != null else get_tree().root
	sim.tick = count
	# The frames run while the tree stands paused too (the horde's break takes its picks then).
	var frames: Node = root.get_node_or_null(^"Frames")
	if frames != null and bool(frames.get(&"auto_tick")):
		frames.call(&"tick", delta)
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


## A run starts (Flow, once the last run's world is gone and before the new one is made;
## online-ready N3b): the clock counts from 0 again, the run takes its seed (`SimSeed.fresh`: a
## replay's while one records or plays, else random; N3c), and every service takes a fresh game's
## state (its `begin_run`; core/sim/sim_fresh.gd), in the tick's order, then the horde director. So
## a run plays the same whatever ran before it in this game, and a replay recorded in any run plays
## the same in any other.
func begin_run() -> void:
	count = 0
	sim.tick = 0
	sim.run_seed = SimSeed.fresh()
	var root: Node = areas if areas != null else get_tree().root
	for service in FRESH_AT_RUN:
		var area: Node = root.get_node_or_null(NodePath(service))
		if area == null:
			continue
		if not area.has_method(&"begin_run"):
			push_error("Tick: %s has no begin_run, so it keeps the last run's state (core/sim/sim_fresh.gd)" % service)
			continue
		area.call(&"begin_run")


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


## True when the tick steps `node` now (its physics processing on, and it can process).
static func _steps(node: Node) -> bool:
	return node.is_physics_processing() and node.can_process()


## True when the tick runs `node`'s timers now (its processing on, and it can process).
static func _times(node: Node) -> bool:
	return node.is_processing() and node.can_process()
