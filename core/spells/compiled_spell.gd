class_name CompiledSpell
extends RefCounted
## One carrier of a staff turned into final numbers (`StaffCompiler`, docs/milestones/
## M2-staffs.md): what it fires, with the infusions, modifiers and trigger that attached to it,
## and the payload its trigger fires. A fallback (cards that landed on the caster or on a
## payload's origin) is one too, with `fallback` set. It is read-only data for the spell runtime;
## nothing but `core/spells/` reads it (the builder gets plain values from `Spells.staff_view`).

var form_id: StringName = &""
var element_id: StringName = &""
## Display names taken while compiling, so a description needs no second look-up.
var form_name: String = ""
var element_name: String = ""
var modifier_ids: Array[StringName] = []
var trigger_id: StringName = &""

var damage: int = 1
var mana_cost: float = 0.0
var cooldown: float = 0.5
var speed: float = 0.0
var lifetime: float = 1.0
var radius: float = 4.0
## Shots one cast of this carrier makes, after split and the form's own count.
var shots: int = 1
## Degrees the shots fan over.
var spread: float = 0.0
## A `FormBase.Motion` value.
var motion: int = FormBase.Motion.STRAIGHT
var pierce: int = 0
var orbit_radius: float = 0.0
var ray_length: float = 0.0
## The shots the cards asked for (the same as `shots`; kept for the description).
var shots_requested: int = 1

## Element: the status a hit applies (`&""` for plain arcane damage) and the shot tint.
var status_id: StringName = &""
var status_duration: float = 0.0
var status_strength: float = 0.0
var tint: Color = Color.WHITE
## The shot's look, packed by `core/projectiles`' `pack_look`: the `look_layer` of every
## infusion and modifier on it, combined (0 none).
var look: int = 0

## What a hit does, for `Spells.hit_profile`; set by the compiler.
var hit: HitProfile = null
## What an echo's second firing does: the hit at half damage. Null without an `echo` modifier.
var echo_hit: HitProfile = null

## Radians per second a shot turns toward a target; 0 means no homing.
var homing_turn: float = 0.0
## Degrees off its aim a homing beam or teleport still bends to a target: what `homing_turn`
## turns in SpellLimits.INSTANT_HOMING_SECONDS, up to all the way round (0 without homing).
var homing_angle: float = 0.0
## Pixels away a homing spell looks for its target (`StaffCompiler.homing_range`); 0 when it does
## not home, or its form cannot be steered (its homing cards are then listed as wasted).
var homing_range: float = 0.0
## Times a hit jumps on to another target; 0 means no chain.
var chain_jumps: int = 0
## Factor on the staff's `spread` for this carrier's shots (its modifiers' `spread_mult`,
## multiplied); 1 means the staff's own spread.
var spread_mult: float = 1.0
## `arc`: seconds between two zaps (0 for none), how far a zap reaches, and what it hits with.
var arc_interval: float = 0.0
var arc_reach: float = 0.0
var arc_hit: HitProfile = null

## A `TriggerBase.Event` value, meaningful only when `payload` is not null.
var trigger_event: int = TriggerBase.Event.HIT
var trigger_interval: float = 0.0

## `fallback` values: a carrier's spell, the cards that landed on the caster, or on a
## payload's origin.
const FALLBACK_NONE: int = 0
const FALLBACK_CASTER: int = 1
const FALLBACK_POINT: int = 2
var fallback: int = FALLBACK_NONE
## Every infusion on the shot, in slot order; `element_id` is the first.
var element_ids: Array[StringName] = []
## The summed `behaviour_strength` of the modifiers, indexed by `ModifierBase.Behaviour`
## (three shields give 3 at SHIELD).
var behaviours: PackedFloat32Array = PackedFloat32Array()
## The group the trigger fires, or null.
var payload: CompiledGroup = null
## The group a payload carrier (rain, familiar) carries, or null.
var own_payload: CompiledGroup = null
## Index in `CompiledStaff.nodes`; the tag of this spell's shots carries it.
var node: int = -1
## The carrier's slot in the staff, -1 for a fallback.
var slot: int = -1


## The summed strength of `behaviour` (a `ModifierBase.Behaviour`) on this spell, 0 for none.
func behaviour(kind: int) -> float:
	return behaviours[kind] if kind >= 0 and kind < behaviours.size() else 0.0


## How many spells there are in this chain of payloads, this one included (following the first
## spell of each payload).
func chain_length() -> int:
	if payload == null or payload.is_empty():
		return 1
	return 1 + payload.spells[0].chain_length()
