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
	# Staffs (A3, docs/milestones/M2-staffs.md). Each is run by the kit named.
	## A shield on the carrier absorbs a hit; the payload fires from there (B1, B2, B3).
	BLOCK,
	## The carrier's hit kills; the payload fires from the target (B2, B3).
	KILL,
	## At once, from the caster, when the carrier is cast (B2).
	CAST,
	## The shot hits a wall; the payload fires from there (B1, B2).
	WALL,
	## The caster takes damage while the carrier lives; the payload fires from the caster (B2, B3).
	HURT,
	## The carrier's hit sets off a reaction; the payload fires from the target (B2, B3).
	REACTION,
}

@export var event: Event = Event.HIT
## TIMER only: seconds between fires. A trigger fires every time its event happens, for as
## long as its carrier lives (owner, 2026-10-29: no per-shot count; the spell runtime's per-step
## fire cap is the only bound).
@export var interval: float = 0.0


func kind() -> StringName:
	return &"trigger"


func ranges() -> Dictionary:
	var limits: Dictionary = super()
	limits.merge({
		"event": Vector2(0, Event.size() - 1),
		"interval": Vector2(0.0, 10.0),
	})
	return limits
