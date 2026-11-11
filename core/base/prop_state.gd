class_name PropState
extends Resource
## One state of a prop (props W6, docs/milestones/props.md, "What a prop is made of"): its
## reactions, and what the body is while in it. A row of `PropStates.list`; it has no `id` field the
## registry would read (its name is `state_id`), so it is never taken for content.
##
## Reactions belong to states, so "only once" is a state change, never a flag: a fusing barrel has no
## fire reaction, a broken one none at all. The look of a state (art layers, mote sources, a light
## spot) is W7's.

## Its name (&"idle", &"lit", &"fusing", &"broken"), unique in its prop; reactions go to it by this.
@export var state_id: StringName = &""
## Its reactions, in order: on a moment every one that matches fires, in this order (`Reactions`).
@export var reactions: Array[PropReaction] = []
## Whether its footprint blocks the bodies that walk (`Footprint.set_solid`; rubble does not).
@export var blocks: bool = true
## Whether its hurt shape can be hit (`Hurtbox.set_enabled`; rubble cannot).
@export var hittable: bool = true
## Entering it frees the prop, after its `entered` reactions (a crate that leaves nothing).
@export var gone: bool = false


## A state named `id` with `rows` (tests and code-made props).
static func make(id: StringName, rows: Array[PropReaction] = [], is_blocking: bool = true, is_hittable: bool = true, is_gone: bool = false) -> PropState:
	var made := PropState.new()
	made.state_id = id
	made.reactions = rows
	made.blocks = is_blocking
	made.hittable = is_hittable
	made.gone = is_gone
	return made


## True when one of its reactions fires on `kind` (whatever its numbers): a moment it may listen for.
func listens(kind: PropReaction.When) -> bool:
	for row in reactions:
		if row != null and row.when == kind:
			return true
	return false
