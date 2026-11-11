class_name PropStates
extends Resource
## The states a body can be in and their reactions (props W6, docs/milestones/props.md, "Triggers"),
## as a file of their own (`exploding_barrel_states.tres`): a `PropBase` names one, and two props may share one
## (a small and a big exploding barrel). The `Reactions` component (gameplay/actor) runs it and reads nothing
## else of the prop, so any actor's data could name one. It has no `id`, so the registry never takes
## it for content.

## The states; the first is the one a body starts in.
@export var list: Array[PropState] = []


## A set of `states` (tests and code-made props).
static func make(states: Array[PropState]) -> PropStates:
	var made := PropStates.new()
	made.list = states
	return made


## The index of the state named `state_id`, -1 for none.
func state_at(state_id: StringName) -> int:
	for at in list.size():
		if list[at] != null and list[at].state_id == state_id:
			return at
	return -1


## True when a reaction of any state fires on `kind`: whether a body of it listens for that moment.
func listens(kind: PropReaction.When) -> bool:
	for state in list:
		if state != null and state.listens(kind):
			return true
	return false


## What is wrong with the states, one line each after `owner` (empty when they are fine), for a body
## of `staffs` staffs: no state, a state with no name or a name twice, a reaction's problems (a staff
## it does not hold, a state that is not there, a name the game does not know: `known`, as
## `PropReaction.problems` takes it), and states whose `entered` reactions go round for ever.
func problems(owner: String, staffs: int, known: Dictionary = {}) -> PackedStringArray:
	var found := PackedStringArray()
	if list.is_empty():
		found.append("%s has no state." % owner)
	var ids := PackedStringArray()
	for at in list.size():
		var state: PropState = list[at]
		if state == null:
			found.append("%s: state %d is empty." % [owner, at])
			continue
		if state.state_id == &"":
			found.append("%s: state %d has no state_id." % [owner, at])
		elif ids.has(String(state.state_id)):
			found.append("%s: two states are named '%s'." % [owner, state.state_id])
		ids.append(String(state.state_id))
	for state in list:
		if state == null:
			continue
		for k in state.reactions.size():
			var row: PropReaction = state.reactions[k]
			if row == null:
				found.append("%s: %s: reaction %d is empty." % [owner, state.state_id, k])
				continue
			for line: String in row.problems(staffs, ids, known):
				found.append("%s: %s: %s" % [owner, state.state_id, line])
	var loop: StringName = _entered_loop()
	if loop != &"":
		found.append("%s: entering '%s' leads back to it through entered reactions alone, for ever." % [owner, loop])
	return found


## The first state from which `entered` reactions alone lead back round (each state goes on to the
## first `then` of its `entered` rows, as a moment sets it), or &"" when none does.
func _entered_loop() -> StringName:
	for start in list.size():
		var seen: Dictionary[int, bool] = {}
		var at: int = start
		while at >= 0 and not seen.has(at):
			seen[at] = true
			at = _entered_next(at)
		if at == start:
			return list[start].state_id
	return &""


## The state `entered` reactions of state `at` go to (the first `then` among them), -1 for none.
func _entered_next(at: int) -> int:
	var state: PropState = list[at]
	if state == null:
		return -1
	for row in state.reactions:
		if row != null and row.when == PropReaction.When.ENTERED and row.then != &"":
			return state_at(row.then)
	return -1
