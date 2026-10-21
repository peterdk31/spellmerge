class_name ReactionRow
extends Resource
## One element reaction: when a hit of `element_id` lands on a target that has the status
## `status_id`, the reaction runs instead of the element's own status. A row of a
## ReactionTable. It has no `id` field on purpose, so the registry never takes it for
## content.

## What the reaction does. `gameplay/combat` implements each kind once.
enum Effect {
	## Damage in a circle of `radius` around the target.
	BURST,
	## Removes the status for `damage` bonus damage on the target.
	CONSUME,
	## Makes the status last `duration` seconds longer and `strength` stronger.
	EXTEND,
	## Copies the status to the targets within `radius`.
	SPREAD,
}

## The reaction's name, for `reaction_triggered` and feel, for example &"shatter".
@export var reaction_id: StringName = &""
## Shown in the builder and the codex.
@export var display_name: String = ""
## The status the target already has.
@export var status_id: StringName = &""
## The element of the hit that sets it off.
@export var element_id: StringName = &""
@export var effect: Effect = Effect.BURST
@export var damage: int = 0
## Pixels, for BURST and SPREAD.
@export var radius: float = 0.0
## Seconds, for EXTEND.
@export var duration: float = 0.0
## For EXTEND: added to the status strength.
@export var strength: float = 0.0
