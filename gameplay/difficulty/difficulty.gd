extends Node
## Difficulty (autoload `Difficulty`): how much harder the room the party is in is, and every enemy
## and boss that stands there scaled to it (run generation RG5, docs/milestones/run-generation.md,
## "Scaling"). The run's area names each room's scale as the party enters it (`run_room_scaled`:
## its depth and the run's players, by the run definition's curves); this area keeps it as the
## level (`level`) and, as Flow stands an enemy or a boss
## (`enemy_standing`, the body not yet in the tree), sets the body's `Actor.stat_scale` to it (an
## elite's, connected biomes CB11, ELITE_HEALTH times it), so its data's health is multiplied by it
## when the body applies its data, and its `Actor.room_level` to the room's depth level
## (`depth_level`, `run_room_leveled`: the room's scale with one player), which its AI's aim sharpens
## by (`AimTuning`; the owner, 2026-11-19: by depth only, so more players never aim it better). Power, spell size and a boss's
## adds join the same scale as the boss plan's OB7 and OB13 land; a difficulty setting later is one
## more factor of the level. The room's scale is not `difficulty_changed`: that event is kept for the
## setting's level, which the enemies' skill follows (enemy AI AI10). Areas never call each other: this area knows the run and Flow by these
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
## The depth level of that room (`run_room_leveled`: its scale with one player, its depth only; 1:
## as the data says): how sharp its enemies aim.
var depth_level: float = 1.0


func _ready() -> void:
	# Renewed at every run's start (core/sim/tick.gd, core/sim/sim_area.gd); it takes no step.
	SimArea.join(self, &"Difficulty").renewed_by(begin_run)
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if events == null:
		push_warning("Difficulty: the Events autoload is missing, so nothing is scaled.")
		return
	events.run_room_scaled.connect(_on_run_room_scaled)
	events.run_room_leveled.connect(_on_run_room_leveled)
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


## The room's depth level `room_level` (`run_room_leveled`): its enemies' aim's.
func _on_run_room_leveled(room_level: float) -> void:
	if not (room_level > 0.0) or not is_finite(room_level):
		push_warning("Difficulty: a room's depth level of %s, so it stays %s." % [room_level, depth_level])
		return
	depth_level = room_level


## An enemy or a boss is about to stand in the room: it takes the room's depth level (its `room_level`,
## which its AI's aim sharpens by) and its health by it (`stat_scale`, an elite's times ELITE_HEALTH).
func _on_enemy_standing(enemy: Node) -> void:
	var actor := enemy as Actor
	if actor != null:
		actor.room_level = depth_level
		actor.stat_scale = level * (ELITE_HEALTH if actor.is_elite() else 1.0)
