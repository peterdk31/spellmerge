class_name DamageNumbers
extends ActorLook
## An actor's damage numbers (props W5, docs/milestones/props.md; the owner, 2026-11-10: "make this a
## new node you can attach to an actor", then "Add the damage numbers to every actor"). Every actor
## has one: its scene's own when it holds one (a boss's bigger numbers), else the plain one the actor
## adds when it is set up (`Actor._find_components`), so no scene is edited for it.
##
## It holds no labels and draws nothing itself. It hears its own actor's hits (`Actor.damaged`, and
## `Actor.healed` when `heals`) and tells each to the one drawer of every actor's numbers in Feel
## (`damage_number_shown` on the bus), with where the number starts and how it moves: its numbers
## are data here. An actor never hit costs only the node; the actor never steps it.
##
## A hit that took nothing (the actor is invincible: one of the hub's props) is told as spared, so
## a test there still reads what it would have done. View only, as every look.

const EventsScript := preload("res://core/events/events.gd")

## How far above the top of the actor's hurt shape a number starts, in pixels (above its body
## when it has no hurt shape), so it fits any size of body.
@export var lift: float = 4.0
## How far a number rises while it shows, in pixels, and for how many seconds.
@export var rise: float = 16.0
@export var seconds: float = 0.8
## The text's size, as a share of the plain one (a boss's: 2).
@export var text_size: float = 1.0
## Whether heals show too (in the heal colour).
@export var heals: bool = true


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	if not actor.damaged.is_connected(_on_damaged):
		actor.damaged.connect(_on_damaged)
	if not actor.healed.is_connected(_on_healed):
		actor.healed.connect(_on_healed)


## Where this actor's numbers start now, in world pixels: `lift` above the top of its hurt shape,
## over its centre (its body point when it has no hurt shape).
func start_position() -> Vector2:
	var hurtbox: Hurtbox = actor.hurtbox
	if hurtbox == null:
		return actor.global_position + actor.body_offset + Vector2(0.0, -lift)
	var top: float = hurtbox.offset.y - hurtbox.half().y - hurtbox.round_radius()
	return actor.global_position + Vector2(hurtbox.offset.x, top - lift)


func _on_damaged(_by: int, amount: float, element: StringName) -> void:
	var spared: bool = actor.health != null and actor.health.invincible
	_tell(amount, element, EventsScript.NUMBER_SPARED if spared else EventsScript.NUMBER_HIT)


func _on_healed(_by: int, amount: float) -> void:
	if heals:
		_tell(amount, &"", EventsScript.NUMBER_HEAL)


func _tell(amount: float, element: StringName, kind: StringName) -> void:
	if amount <= 0.0 or actor.events == null:
		return
	actor.events.damage_number_shown.emit(actor.id, start_position(), amount, element, kind, rise, seconds, text_size)
