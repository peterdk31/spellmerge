class_name FormBase
extends SpellComponent
## A form (bolt, beam, nova, rune, orbit): how the shots leave the caster. Every spell
## has exactly one, and it sets the base numbers the element and modifiers then change.

## How the shots move once spawned.
enum Motion {
	## A shot flies in a line (bolt, nova).
	STRAIGHT,
	## A shot stays where it was placed and waits for a target to enter (rune).
	STILL,
	## A shot circles its caster at `orbit_radius` (orbit).
	ORBIT,
	## No shot: one ray of `ray_length` hits along a line at once (beam).
	RAY,
}

## Damage of one hit before the element and modifiers.
@export var base_damage: int = 1
## Mana taken per cast.
@export var mana_cost: float = 0.0
## Seconds before the same player can cast this spell again. There is no separate cast
## time: the cooldown is the cast time.
@export var cooldown: float = 0.5
## Pixels per second. Ignored by STILL and RAY.
@export var speed: float = 0.0
## Seconds a shot lives. For RAY, how long the drawn beam stays on screen.
@export var lifetime: float = 1.0
## Hit circle of one shot in pixels. For RAY, the half-width of the beam.
@export var radius: float = 4.0
## Shots per cast before modifiers (a nova has many, a bolt one).
@export var shots: int = 1
## Angle in degrees the shots are spread over (360 for a full ring).
@export_range(0.0, 360.0) var spread: float = 0.0
@export var motion: Motion = Motion.STRAIGHT
## Extra targets each shot passes through before it ends.
@export var pierce: int = 0
## ORBIT only: distance from the caster in pixels.
@export var orbit_radius: float = 0.0
## RAY only: how far the ray reaches in pixels.
@export var ray_length: float = 0.0


func kind() -> StringName:
	return &"form"


func ranges() -> Dictionary:
	var limits: Dictionary = super()
	limits.merge({
		"base_damage": Vector2(1, 200),
		"mana_cost": Vector2(0.0, 100.0),
		"cooldown": Vector2(0.05, 10.0),
		"speed": Vector2(0.0, 2000.0),
		"lifetime": Vector2(0.05, 20.0),
		"radius": Vector2(1.0, 64.0),
		"shots": Vector2(1, 24),
		"spread": Vector2(0.0, 360.0),
		"motion": Vector2(0, Motion.size() - 1),
		"pierce": Vector2(0, 16),
		"orbit_radius": Vector2(0.0, 256.0),
		"ray_length": Vector2(0.0, 1024.0),
	})
	return limits
