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
	## Over and over while the shot lives: its payload winds up (this card's `wind_up` and the
	## payload's own; docs/milestones/cast-timing.md, T8), leaves, and the next tick starts.
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
## `ModifierBase.RULES` "needs": from its carrier "any" (one of these traits) and "not" (none of them), or
## "or_cards" (a card with one of these behaviours on it does instead: what a blast strikes is the
## carrier's hit, rules R4 F2); from the cards on it "cards" (one of these behaviours, or an
## infusion where "or_infused") and "not_cards" (none of these where they work). A trigger not here
## goes off on every carrier. A new trigger adds its line here, never per carrier or in the compiler.
const NEEDS: Dictionary = {
	Event.HIT: {"any": CarrierTraits.HITS, "or_cards": [ModifierBase.Behaviour.BLAST]},
	Event.TIMER: {"any": CarrierTraits.LASTS},
	Event.HURT: {"any": CarrierTraits.LASTS},
	Event.BLOCK: {"any": CarrierTraits.MEETS_SHOTS, "cards": [ModifierBase.Behaviour.SHIELD, ModifierBase.Behaviour.DEFLECT]},
	Event.KILL: {"any": CarrierTraits.HITS, "or_cards": [ModifierBase.Behaviour.BLAST]},
	Event.REACTION: {"any": CarrierTraits.HITS, "or_cards": [ModifierBase.Behaviour.BLAST], "cards": [ModifierBase.Behaviour.RELAY], "or_infused": true},
	Event.WALL: {"any": CarrierTraits.FLIES | CarrierTraits.LINE, "not_cards": [ModifierBase.Behaviour.GHOST]},
}

@export var event: Event = Event.HIT
## Seconds its payload winds up where it fired, before the payload's own cards' wind-up (every
## card has one; docs/milestones/cast-timing.md). A timer ticks over and over: each tick its
## payload winds up (this and the payload's), leaves, and the next starts, so the payload's cards
## change its pace (T8; it had a fixed `interval`); this share no card changes (a staff or a relic
## may, later: T9). A trigger fires every
## time its event happens, for as long as its carrier lives (owner, 2026-10-29: no per-shot count;
## the spell runtime's per-step fire cap is the only bound).
@export var wind_up: float = 0.0


func kind() -> StringName:
	return &"trigger"


func ranges() -> Dictionary:
	var limits: Dictionary = super()
	limits.merge({
		"event": Vector2(0, Event.size() - 1),
		"wind_up": Vector2(0.0, 10.0),
	})
	return limits
