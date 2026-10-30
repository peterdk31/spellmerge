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

## What each trigger needs to go off (`Carrier.fires`, `Carrier.fires_with`), in the rows of
## `ModifierBase.NEEDS`: from its carrier "any" (one of these traits) and "not" (none of them), or
## "or_cards" (a card with one of these behaviours on it does instead: a blast's area hit carries
## the carrier's tag); from the cards on it "cards" (one of these behaviours, or an infusion where
## "or_infused") and "not_cards" (none of these where they work). A trigger not here goes off on
## every carrier. A new trigger adds its line here, never per carrier or in the compiler.
const NEEDS: Dictionary = {
	Event.HIT: {"any": CarrierTraits.HITS},
	Event.TIMER: {"any": CarrierTraits.LASTS},
	Event.HURT: {"any": CarrierTraits.LASTS},
	Event.BLOCK: {"any": CarrierTraits.MEETS_SHOTS, "cards": [ModifierBase.Behaviour.SHIELD, ModifierBase.Behaviour.DEFLECT]},
	Event.KILL: {"any": CarrierTraits.HITS, "or_cards": [ModifierBase.Behaviour.BLAST]},
	Event.REACTION: {"any": CarrierTraits.HITS, "or_cards": [ModifierBase.Behaviour.BLAST], "cards": [ModifierBase.Behaviour.RELAY], "or_infused": true},
	Event.WALL: {"any": CarrierTraits.FLIES | CarrierTraits.LINE, "not_cards": [ModifierBase.Behaviour.GHOST]},
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
