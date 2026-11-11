class_name PropBase
extends Resource
## A prop (props W6, docs/milestones/props.md): a thing in the world that stands, blocks, takes hits
## and reacts, as data. One content folder each, `content/props/<id>/<id>.tres`; the registry finds
## it under `props` by `id`. Its body is its `scene`, for every prop the one shared body
## (`content/props/base/prop.tscn`: an actor with no controller), filled in from this by
## `PropBody.make` (gameplay/actor), so a new prop is data and art only.
##
## It is an actor's data the way an `EnemyBase` is, for a body that does not walk: its health and
## hurt shape, its ground, 1-4 staffs (what its triggers and a possessor cast), and its states (a
## `PropStates` of their own: what fires when, `PropState`, `PropTrigger`).

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

## Its staffs (1-4, as an enemy's: `EnemyBase.staffs`), the cards its triggers and a possessor
## cast; a trigger names one by number (1-4). A staff's wind-up is a fuse. Empty: it casts nothing.
@export var staffs: Array[StaffCards] = []
## Its states and their triggers, a file of their own (`<id>_states.tres`; two props may share one).
@export var states: PropStates = null
## What it looks like in its states (props W7: `PropStateLook`, art layers, motes, a light, a cue),
## one a state by `state_id`, an empty `state_id` for every state with none of its own. On the prop,
## not its states, so props sharing a states file look as each wants. View only.
@export var looks: Array[PropStateLook] = []

## The most staffs a prop holds (the staff buttons), as an enemy.
const MAX_STAFFS: int = EnemyBase.MAX_STAFFS


## Its name for people: `display_name`, else its id in words.
func shown_name() -> String:
	return display_name if display_name != "" else String(id).replace("_", " ").capitalize()


## The look of the state `state_id`: its own, else the one for every state, else null.
func look_of(state_id: StringName) -> PropStateLook:
	var every: PropStateLook = null
	for look in looks:
		if look == null:
			continue
		if look.state_id == state_id:
			return look
		if look.state_id == &"" and every == null:
			every = look
	return every


## True when its own data sets a footprint (else the kit's default).
func has_footprint() -> bool:
	return footprint_radius > 0.0 or (footprint_size.x > 0.0 and footprint_size.y > 0.0)


## What is wrong with the prop's data, one line each (empty when it is fine): no scene, no states,
## its health, too many staffs or a staff's own problems, and its states' problems
## (`PropStates.problems`, with the names the game knows: `known`).
func problems(known: Dictionary = {}) -> PackedStringArray:
	var found := PackedStringArray()
	if scene == null:
		found.append("%s has no scene (the shared content/props/base/prop.tscn)." % id)
	if max_health <= 0.0:
		found.append("%s: max_health is %s; above 0." % [id, max_health])
	# Numbered from 1, as its triggers name them.
	found.append_array(StaffCards.list_problems(String(id), staffs, MAX_STAFFS, 1))
	if states == null:
		found.append("%s has no states." % id)
	else:
		found.append_array(states.problems(String(id), mini(staffs.size(), MAX_STAFFS), known))
	found.append_array(look_problems())
	return found


## What is wrong with its looks, one line each (empty when they are fine): a look's own problems, two
## for one state, one for a state it does not have, and a state with no look at all.
func look_problems() -> PackedStringArray:
	var found := PackedStringArray()
	var seen: Dictionary[StringName, bool] = {}
	for look in looks:
		if look == null:
			found.append("%s: a look is empty." % id)
			continue
		if seen.has(look.state_id):
			found.append("%s: two looks for %s." % [id, look.state_id if look.state_id != &"" else "every state"])
		seen[look.state_id] = true
		if look.state_id != &"" and states != null and states.state_at(look.state_id) < 0:
			found.append("%s: a look for the state '%s', which it does not have." % [id, look.state_id])
		found.append_array(look.problems(String(id)))
	if states != null:
		for state in states.list:
			if state != null and look_of(state.state_id) == null:
				found.append("%s: the state '%s' has no look (nor is there one for every state)." % [id, state.state_id])
	return found
