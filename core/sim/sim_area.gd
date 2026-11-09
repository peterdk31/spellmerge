class_name SimArea
extends RefCounted
## An area of the simulation as the Tick knows it (core/sim/tick.gd): the node, the steps it takes
## and where, how it starts a run, and whether the tick steps it now. An area joins the game's
## Tick in its `_ready` (`join`) and says all of this itself, so the Tick calls typed Callables
## in its written order and knows nothing of what an area is or does:
##
##     SimArea.join(self, &"Projectiles") \
##         .steps(&"Projectiles", step) \
##         .renewed_by(begin_run) \
##         .takes_rules(take_rules)
##
## - **Steps** (`steps`): each under a key of `TickScript.STEPS`, the tick's written order. A step
##   runs while the game goes; while it is stopped, only a step whose `own_stops` hold every reason
##   it is stopped for (a step that must run through a stop of its own, never through the pause menu).
## - **A run's start** (`renewed_by`): its `begin_run`, which ends what it holds and takes a fresh
##   game's state (core/sim/sim_fresh.gd), called in `TickScript.RUN_ORDER`. An area that starts
##   each run fresh some other way says why instead (`fresh_because`); tests/core/test_tick.gd fails
##   on an area that does neither.
## - **The run's rules** (`takes_rules`): handed the run's `SessionRules` before it is renewed, and
##   again when a command changes them.
## - **`ticking`**: whether the tick steps it now (`Tick.set_ticking`). Off, a test steps it by hand.
##
## Every area is part of the game's state, by its name (`Tick.state_areas`: the hash, the desync
## report and later snapshots).

const TickScript := preload("res://core/sim/tick.gd")

## A step: its key in `TickScript.STEPS`, what it calls with the tick's delta, and the reasons to
## stop the game it runs through.
class Step:
	extends RefCounted
	var key: StringName
	var call: Callable
	var own_stops: Array[StringName] = []

	## True when it runs on a tick the game is stopped for `stops`: each of them is its own.
	func runs_through(stops: Array[StringName]) -> bool:
		if own_stops.is_empty():
			return false
		for reason in stops:
			if not own_stops.has(reason):
				return false
		return true


var name: StringName = &""
var node: Node = null
## Whether the tick steps it now.
var ticking: bool = true
var step_list: Array[Step] = []
## A run's start: renewed by this (no arguments), or `fresh_otherwise` says why it need not be.
var begin_run: Callable = Callable()
var fresh_otherwise: String = ""
## Takes the run's rules (a `SessionRules`), or invalid for an area no rule changes.
var take_rules: Callable = Callable()


func _init(area_name: StringName, area_node: Node) -> void:
	name = area_name
	node = area_node


## `node` joins the game's Tick as the area `name` when it is that area's autoload
## (`/root/<name>`), and the Tick steps it as the returned entry says. Any other node (a test's own
## area, out of the tree or under a node of its own) gets an entry no Tick holds, so the same
## `_ready` runs everywhere and only the game's areas are stepped by the game's clock.
static func join(node: Node, name: StringName) -> SimArea:
	var tick: TickScript = TickScript.of(node) as TickScript
	if tick != null and node.get_path() == NodePath("/root/" + String(name)):
		return tick.add_area(name, node)
	return SimArea.new(name, node)


## Take a step under `key` (one of `TickScript.STEPS`), calling `call` with the tick's delta, and
## running through the game's stops for `own_stops` only.
func steps(key: StringName, call: Callable, own_stops: Array[StringName] = []) -> SimArea:
	var step := Step.new()
	step.key = key
	step.call = call
	step.own_stops = own_stops.duplicate()
	step_list.append(step)
	return self


## A run's start calls `call` (its `begin_run`).
func renewed_by(call: Callable) -> SimArea:
	begin_run = call
	return self


## It starts each run fresh with no `begin_run`, for `reason`.
func fresh_because(reason: String) -> SimArea:
	fresh_otherwise = reason
	return self


## The run's rules go to `call`.
func takes_rules(call: Callable) -> SimArea:
	take_rules = call
	return self


## True when the tick steps it now: `ticking`, and its node is there and may process (a node
## disabled by its process mode is not stepped; the tree is never paused while the tick steps).
func is_stepped() -> bool:
	return ticking and node != null and is_instance_valid(node) and node.is_inside_tree() and node.can_process()
