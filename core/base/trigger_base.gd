class_name TriggerBase
extends SpellComponent
## A trigger (on hit, on expire, timer): when the spell it holds fires. A spell has at
## most one; the held spell is built from the same slots, one level deeper. Held spells
## fire from the shot's position (`core/spells`, M2 part 6).

## What fires the held spell.
enum Event {
	## A shot hits a target; the held spell fires from the hit point.
	HIT,
	## A shot ends (its life runs out or it reaches a wall); the held spell fires there.
	EXPIRE,
	## Every `interval` seconds while the shot lives.
	TIMER,
}

@export var event: Event = Event.HIT
## TIMER only: seconds between fires.
@export var interval: float = 0.0
## How often one shot may fire the held spell at most.
@export var max_fires: int = 1


func kind() -> StringName:
	return &"trigger"


func ranges() -> Dictionary:
	var limits: Dictionary = super()
	limits.merge({
		"event": Vector2(0, Event.size() - 1),
		"interval": Vector2(0.0, 10.0),
		"max_fires": Vector2(1, 4),
	})
	return limits
