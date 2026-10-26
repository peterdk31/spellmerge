class_name CompiledSpell
extends RefCounted
## A recipe turned into final numbers (`Spells.compile`). It is read-only data for the
## spell runtime and the builder; nothing but `core/spells/` and the builder reads it.
## A spell that broke a rule has `valid == false` and a `reason` the builder shows; the
## other fields are then not meant to be used.

## False when the recipe broke a rule that clamping cannot fix.
var valid: bool = true
## Plain words for the builder when `valid` is false, for example "Too complex: 13 of 12. Remove one."
var reason: String = ""
## What the player reads in the builder: the stats, anything clamped, and the held spell.
var description: String = ""
## Complexity of this spell and every spell its triggers hold.
var complexity: int = 0
## 0 for the cast, 1 for a spell held by its trigger, 2 for the one below that.
var depth: int = 0

var form_id: StringName = &""
var element_id: StringName = &""
## Display names taken while compiling, so the description needs no second look-up.
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
## Shots one cast makes, already clamped to `SpellLimits.MAX_SHOTS`.
var shots: int = 1
## Degrees the shots fan over.
var spread: float = 0.0
## A `FormBase.Motion` value.
var motion: int = FormBase.Motion.STRAIGHT
var pierce: int = 0
var orbit_radius: float = 0.0
var ray_length: float = 0.0
## Shots the recipe asked for before the limit.
var shots_requested: int = 1
## True when the shot count was cut to the limit.
var shots_clamped: bool = false

## Element: the status a hit applies (`&""` for plain arcane damage) and the shot tint.
var status_id: StringName = &""
var status_duration: float = 0.0
var status_strength: float = 0.0
var tint: Color = Color.WHITE
## The element's shot shape (0 plain), see `ElementBase.shape`.
var shape: int = 0

## What a hit does, for `Spells.hit_profile`; set by the compiler.
var hit: HitProfile = null

## Radians per second a shot turns toward a target; 0 means no homing.
var homing_turn: float = 0.0
## Times a hit jumps on to another target; 0 means no chain.
var chain_jumps: int = 0

## A `TriggerBase.Event` value, meaningful only when `held` is not null.
var trigger_event: int = TriggerBase.Event.HIT
var trigger_interval: float = 0.0
var trigger_max_fires: int = 1
## The spell the trigger fires, or null.
var held: CompiledSpell = null

# --- Staffs (A4, docs/milestones/M2-staffs.md) --------------------------------
# A staff's cards compile into these same spells (`StaffCompiler`); the recipe compiler above
# leaves them at their defaults until A6c removes it.

## `fallback` values: a carrier's spell, the cards that landed on the caster, or on a
## payload's origin.
const FALLBACK_NONE: int = 0
const FALLBACK_CASTER: int = 1
const FALLBACK_POINT: int = 2
var fallback: int = FALLBACK_NONE
## Every infusion on the shot, in slot order; `element_id` is the first.
var element_ids: Array[StringName] = []
## The summed `behaviour_strength` of the modifiers, indexed by `ModifierBase.Behaviour`
## (three shields give 3 at SHIELD). Empty for a recipe spell.
var behaviours: PackedFloat32Array = PackedFloat32Array()
## The group the trigger fires (staffs), or null.
var payload: CompiledGroup = null
## The group a payload carrier (rain, familiar) carries, or null.
var own_payload: CompiledGroup = null
## Index in `CompiledStaff.nodes`, -1 for a recipe spell.
var node: int = -1
## The carrier's slot in the staff, -1 for a fallback or a recipe spell.
var slot: int = -1


## The summed strength of `behaviour` (a `ModifierBase.Behaviour`) on this spell, 0 for none.
func behaviour(kind: int) -> float:
	return behaviours[kind] if kind >= 0 and kind < behaviours.size() else 0.0


## How many spells there are in this chain, this one included.
func chain_length() -> int:
	return 1 if held == null else 1 + held.chain_length()


## The compiled spell `level` levels below this one (0 is this spell), or null.
func at_depth(level: int) -> CompiledSpell:
	if level <= 0:
		return self
	return null if held == null else held.at_depth(level - 1)
