extends Node
## Difficulty (autoload `Difficulty`): how much harder the room the party is in is, and every enemy
## and boss that stands there scaled to it (run generation RG5, docs/milestones/run-generation.md,
## "Scaling"). The run's area names each room's scale as the party enters it (`run_room_scaled`:
## its depth and the run's players, by the run definition's curves); this area keeps it as the
## level (`level`) and, as Flow stands an enemy or a boss
## (`enemy_standing`, the body not yet in the tree), sets the body's `Actor.stat_scale` to it (an
## elite's, connected biomes CB11, ELITE_HEALTH times it), so its data's health is multiplied by it
## when the body applies its data. Power, spell size and a boss's
## adds join the same scale as the boss plan's OB7 and OB13 land; a difficulty setting later is one
## more factor of the level. The room's scale is not `difficulty_changed`: that event is kept for the
## setting's level, which the enemies' skill follows (enemy AI AI10), never the room's depth. Areas never call each other: this area knows the run and Flow by these
## events only.
##
## The level is the run's state (hashed, saved in snapshots): a run's start renews it to 1
## (`begin_run`, `Tick.RUN_ORDER`), so out of a run of rooms (the hub) nothing is
## scaled. A body already standing keeps the numbers it stood with (a snapshot restores them).

const EventsScript := preload("res://core/events/events.gd")

## How much more health an elite has than its kind (connected biomes CB11, decision 24): its
## `Actor.stat_scale` is the room's level times this.
const ELITE_HEALTH: float = 1.75

## Not state: a service (core/sim/README.md).
const DERIVED: Array[StringName] = [&"events"]

## The event bus. Only tests set it, before adding the node; otherwise the autoload is used.
var events: EventsScript = null

## How much harder the room the party is in is than the run's first room with one player (1: as
## the data says).
var level: float = 1.0


func _ready() -> void:
	# Renewed at every run's start (core/sim/tick.gd, core/sim/sim_area.gd); it takes no step.
	SimArea.join(self, &"Difficulty").renewed_by(begin_run)
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if events == null:
		push_warning("Difficulty: the Events autoload is missing, so nothing is scaled.")
		return
	events.run_room_scaled.connect(_on_run_room_scaled)
	events.enemy_standing.connect(_on_enemy_standing)


## A run's start: the level as the data says until a run's room is entered.
func begin_run() -> void:
	SimFresh.renew(self)


## The party enters a run's room `scale` times harder: the level.
func _on_run_room_scaled(scale: float) -> void:
	if not (scale > 0.0) or not is_finite(scale):
		push_warning("Difficulty: a room's scale of %s, so the level stays %s." % [scale, level])
		return
	level = scale


## An enemy or a boss is about to stand in the room: it takes the room's level (an elite's times
## ELITE_HEALTH).
func _on_enemy_standing(enemy: Node) -> void:
	var actor := enemy as Actor
	if actor != null:
		actor.stat_scale = level * (ELITE_HEALTH if actor.is_elite() else 1.0)
