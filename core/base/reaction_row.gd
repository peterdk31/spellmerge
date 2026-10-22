class_name ReactionRow
extends Resource
## One element reaction: when a hit of `element_id` lands on a target that has the status
## `status_id`, the reaction runs instead of the element's own status. A row of a
## ReactionTable. It has no `id` field on purpose, so the registry never takes it for
## content. A pair of elements reacts both ways, so it has two rows with one `reaction_id`.

## What the reaction does. `gameplay/combat` implements each kind once.
enum Effect {
	## Damage in a circle of `radius` around the target (the target included), pulling
	## everything in it toward the centre by `pull`.
	BURST,
	## Removes the status for `damage` bonus damage on the target (doubled while it is frozen).
	CONSUME,
	## Makes the status last `duration` seconds longer and `strength` stronger. For `chill`
	## it is a freeze instead: a chilled target freezes for `duration` seconds and a frozen
	## one stays frozen that much longer (`strength` is not used).
	EXTEND,
	## Copies the status to the other targets within `radius`.
	SPREAD,
}

## The reaction's name, for `reaction_triggered` and feel, for example &"shatter".
@export var reaction_id: StringName = &""
## Shown in the builder and the codex.
@export var display_name: String = ""
## The status the target already has (`chill` also matches a frozen target).
@export var status_id: StringName = &""
## The element of the hit that sets it off.
@export var element_id: StringName = &""
@export var effect: Effect = Effect.BURST
@export var damage: int = 0
## Pixels, for BURST and SPREAD.
@export var radius: float = 0.0
## Seconds, for EXTEND.
@export var duration: float = 0.0
## For EXTEND (not `chill`): added to the status strength.
@export var strength: float = 0.0
## For BURST: pixels per second that pull the targets in the circle toward its centre.
@export var pull: float = 0.0
## For BURST (and SPREAD, should a row want it): also remove `status_id` from the target (a thaw uses the burn up).
@export var consume_status: bool = false
