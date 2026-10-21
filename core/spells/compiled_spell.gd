class_name CompiledSpell
extends RefCounted
## A recipe turned into final numbers (`Spells.compile`). It is read-only data for the
## spell runtime and the builder; nothing but `core/spells/` and the builder reads it.
## A spell that broke a rule has `valid == false` and a `reason` the builder shows; the
## other fields are then not meant to be used.

## False when the recipe broke a rule that clamping cannot fix.
var valid: bool = true
## Plain words for the builder when `valid` is false, for example "Too complex: 13 of 12."
var reason: String = ""
## What the player reads in the builder: the stats, anything clamped, and the held spell.
var description: String = ""
## Complexity of this spell and every spell its triggers hold.
var complexity: int = 0
## 0 for the cast, 1 for a spell held by its trigger, 2 for the one below that.
var depth: int = 0

var form_id: StringName = &""
var element_id: StringName = &""
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


## How many spells there are in this chain, this one included.
func chain_length() -> int:
	return 1 if held == null else 1 + held.chain_length()


## The compiled spell `level` levels below this one (0 is this spell), or null.
func at_depth(level: int) -> CompiledSpell:
	if level <= 0:
		return self
	return null if held == null else held.at_depth(level - 1)
