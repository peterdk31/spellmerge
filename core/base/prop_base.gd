class_name PropBase
extends Resource
## A prop (props W6, docs/milestones/props.md): a thing in the world that stands, blocks, takes hits
## and reacts, as data. One content folder each, `content/props/<id>/<id>.tres`; the registry finds
## it under `props` by `id`. Its body is its `scene`, for every prop the one shared body
## (`content/props/base/prop.tscn`: an actor with no controller), filled in from this by
## `PropBody.make` (gameplay/actor), so a new prop is data and art only.
##
## It is an actor's data the way an `EnemyBase` is, for a body that does not walk: its health and
## hurt shape, its ground, 1-4 staffs (what its reactions and a possessor cast), and its states, the
## first the one it starts in. What fires when is the states' (`PropState`, `PropReaction`).

## Unique name of the prop, also its folder name.
@export var id: StringName = &""
## Its name for people; empty: its id in words.
@export var display_name: String = ""
## Its body: the shared prop scene (`content/props/base/prop.tscn`), as an enemy names its own.
@export var scene: PackedScene = null

@export var max_health: float = 10.0
## True for a prop no hit hurts (the hub's): hits still land and show, its health stays.
@export var invincible: bool = false

## The hurt shape (`Hurtbox`): a circle of `radius`, or a box `size` across, round `offset` from the
## feet.
@export var radius: float = 8.0
@export var size: Vector2 = Vector2.ZERO
@export var offset: Vector2 = Vector2(0.0, -8.0)

## The ground it stands on (`Footprint`): a circle of `footprint_radius` or a box `footprint_size`
## across, round `footprint_offset` from the feet. Both zero: the base of its hurt box, or the
## kit's default circle (`Actor._find_components`). Whether it blocks is its state's (`blocks`).
@export var footprint_radius: float = 0.0
@export var footprint_size: Vector2 = Vector2.ZERO
@export var footprint_offset: Vector2 = Vector2.ZERO

## Its staffs (1-4, as an enemy's: `EnemyBase.staffs`), the cards its reactions and a possessor
## cast; a reaction names one by number (1-4). A staff's wind-up is a fuse. Empty: it casts nothing.
@export var staffs: Array[StaffCards] = []
## Its states; the first is the one it starts in.
@export var states: Array[PropState] = []

## The most staffs a prop holds (the staff buttons), as an enemy.
const MAX_STAFFS: int = EnemyBase.MAX_STAFFS


## Its name for people: `display_name`, else its id in words.
func shown_name() -> String:
	return display_name if display_name != "" else String(id).replace("_", " ").capitalize()


## The index of the state named `state_id` in `states`, -1 for none.
func state_at(state_id: StringName) -> int:
	for at in states.size():
		if states[at] != null and states[at].state_id == state_id:
			return at
	return -1


## True when a reaction of any state fires on `kind`: whether a body of it listens for that moment.
func listens(kind: PropReaction.When) -> bool:
	for state in states:
		if state != null and state.listens(kind):
			return true
	return false


## True when its own data sets a footprint (else the kit's default).
func has_footprint() -> bool:
	return footprint_radius > 0.0 or (footprint_size.x > 0.0 and footprint_size.y > 0.0)


## What is wrong with the prop's data, one line each (empty when it is fine): no scene, no state, a state with
## no name or a name twice, too many staffs or a staff's own problems, a reaction's problems (a
## staff it does not hold, a state it does not have, a name the game does not know: `known`, as
## `PropReaction.problems` takes it), and states whose `entered` reactions go round for ever.
func problems(known: Dictionary = {}) -> PackedStringArray:
	var found := PackedStringArray()
	if scene == null:
		found.append("%s has no scene (the shared content/props/base/prop.tscn)." % id)
	if states.is_empty():
		found.append("%s has no state." % id)
	if max_health <= 0.0:
		found.append("%s: max_health is %s; above 0." % [id, max_health])
	# Numbered from 1, as its reactions name them.
	found.append_array(StaffCards.list_problems(String(id), staffs, MAX_STAFFS, 1))
	var ids := PackedStringArray()
	for at in states.size():
		var state: PropState = states[at]
		if state == null:
			found.append("%s: state %d is empty." % [id, at])
			continue
		if state.state_id == &"":
			found.append("%s: state %d has no state_id." % [id, at])
		elif ids.has(String(state.state_id)):
			found.append("%s: two states are named '%s'." % [id, state.state_id])
		ids.append(String(state.state_id))
	for state in states:
		if state == null:
			continue
		for k in state.reactions.size():
			var row: PropReaction = state.reactions[k]
			if row == null:
				found.append("%s: %s: reaction %d is empty." % [id, state.state_id, k])
				continue
			for line: String in row.problems(mini(staffs.size(), MAX_STAFFS), ids, known):
				found.append("%s: %s: %s" % [id, state.state_id, line])
	var loop: StringName = _entered_loop()
	if loop != &"":
		found.append("%s: entering '%s' leads back to it through entered reactions alone, for ever." % [id, loop])
	return found


## The first state from which `entered` reactions alone lead back round (each state goes on to the
## first `then` of its `entered` rows, as a moment sets it), or &"" when none does.
func _entered_loop() -> StringName:
	for start in states.size():
		var seen: Dictionary[int, bool] = {}
		var at: int = start
		while at >= 0 and not seen.has(at):
			seen[at] = true
			at = _entered_next(at)
		if at == start:
			return states[start].state_id
	return &""


## The state `entered` reactions of state `at` go to (the first `then` among them), -1 for none.
func _entered_next(at: int) -> int:
	var state: PropState = states[at]
	if state == null:
		return -1
	for row in state.reactions:
		if row != null and row.when == PropReaction.When.ENTERED and row.then != &"":
			return state_at(row.then)
	return -1
