class_name PossessedLook
extends ActorLook
## The ring round a possessed actor (actors G9): a thin circle round its body in the light shade
## of its driver's colour (`Possession.driver_ramp`: the seat's hat colour, or the caster body's
## ramp for an AI driver), with a thicker arc over it for the time left, so "that imp is player
## 2's now" reads at a glance. The actor's own look and spell colours stay as they are. Made by
## the possession and taken off when it ends (`Actor.add_look`, `remove_look`); it redraws only
## when the arc changes by a step (ARC_STEPS) and allocates nothing per step.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## Pixels between the hurt circle and the ring.
const GAP: float = 3.0
## The ring's radius when the actor has no hurt circle.
const PLAIN_RADIUS: float = 11.0
## The arc of the time left is redrawn in this many steps over the whole possession.
const ARC_STEPS: int = 24
const POINTS: int = 32

## The possession it shows (set before it is added).
var possession: Possession = null

var _drawn_steps: int = -1


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	_drawn_steps = -1


func step(_delta: float) -> void:
	if possession == null or possession.seconds <= 0.0:
		return
	var steps: int = ceili(possession.left / possession.seconds * float(ARC_STEPS))
	if steps != _drawn_steps:
		_drawn_steps = steps
		queue_redraw()


func _draw() -> void:
	if actor == null or possession == null:
		return
	var colour: Color = ProjectilesScript.ramp_light(possession.driver_ramp())
	var radius: float = PLAIN_RADIUS
	var centre: Vector2 = actor.body_offset
	if actor.hurtbox != null:
		radius = actor.hurtbox.radius + GAP
		centre = actor.hurtbox.offset
	var faint := Color(colour, 0.45)
	draw_arc(centre, radius, 0.0, TAU, POINTS, faint, 1.0)
	var share: float = clampf(float(maxi(_drawn_steps, 0)) / float(ARC_STEPS), 0.0, 1.0)
	if share > 0.0:
		draw_arc(centre, radius, -PI * 0.5, -PI * 0.5 + TAU * share, POINTS, colour, 2.0)
