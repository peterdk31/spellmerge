class_name PropState
extends Resource
## One state of a prop (props W6, docs/milestones/props.md, "What a prop is made of"): its
## triggers, and what the body is while in it. A row of `PropStates.list`; it has no `id` field the
## registry would read (its name is `state_id`), so it is never taken for content.
##
## Triggers belong to states, so "only once" is a state change, never a flag: a fusing barrel has no
## fire trigger, a broken one none at all. How a state looks is the prop's, not the state's
## (`PropBase.looks`, props W7), so props sharing a states file look as each wants.

## Its name (&"idle", &"lit", &"fusing", &"broken"), unique in its prop; triggers go to it by this.
@export var state_id: StringName = &""
## Its triggers, in order: on a moment every one that matches fires, in this order (`PropStateTriggers`).
@export var triggers: Array[PropTrigger] = []
## Whether its footprint blocks the bodies that walk (`Footprint.set_solid`; rubble does not).
@export var blocks: bool = true
## Whether its hurt shape can be hit (`Hurtbox.set_enabled`; rubble cannot).
@export var hittable: bool = true
## Entering it frees the prop, after its `entered` triggers (a crate that leaves nothing).
@export var gone: bool = false


## A state named `id` with `rows` (tests and code-made props).
static func make(id: StringName, rows: Array[PropTrigger] = [], is_blocking: bool = true, is_hittable: bool = true, is_gone: bool = false) -> PropState:
	var made := PropState.new()
	made.state_id = id
	made.triggers = rows
	made.blocks = is_blocking
	made.hittable = is_hittable
	made.gone = is_gone
	return made


## True when one of its triggers fires on `kind` (whatever its numbers): a moment it may listen for.
func listens(kind: PropTrigger.When) -> bool:
	for row in triggers:
		if row != null and row.when == kind:
			return true
	return false
