extends Node
## A benchmark's fixed clock (the owner, 2026-11-21: the benchmark plays its fights from a fixed
## script, so each run is the same and the fight rows stop jumping): while in the tree, the Tick runs
## exactly one tick a drawn frame, first in the frame (before any look is stepped or drawn), instead
## of as many as the real time since the last frame calls for (`Tick._physics_process`: none on a
## quick frame, two or three on a slow one). So frame N always shows tick N, whatever the machine
## does meanwhile, and a scenario's fights (the bots decide by the game's own state, the runner's
## crowd and shots come from a seeded generator, each at a tick: `stepped`) play the same every run.
## A frame's time is then one tick's work and one frame's drawing, never a catch-up of several.
##
## Out of the tree the Tick runs by the real clock again. A test tool: the game never does this.

const TickScript := preload("res://core/sim/tick.gd")

## Sent once a tick, right after it ran (the runner's per-tick work: shots topped up).
signal stepped

var _tick: TickScript = null
## The ticks it ran.
var ticks: int = 0


func _init() -> void:
	name = "FixedSteps"
	# Before every other node's frame: the tick first, then the looks, as a physics step would be.
	process_priority = -1000000


func _enter_tree() -> void:
	_tick = get_tree().root.get_node_or_null("Tick") as TickScript
	if _tick != null:
		_tick.set_physics_process(false)


func _exit_tree() -> void:
	if _tick != null and is_instance_valid(_tick):
		_tick.set_physics_process(true)


func _process(_delta: float) -> void:
	if _tick == null:
		return
	# One physics step a frame, as the engine's would be: the frames service's start, then the ticks
	# due (one; none while a live replay waits, which a benchmark never plays).
	var ran: int = _tick.step_physics()
	ticks += ran
	for i in ran:
		stepped.emit()
