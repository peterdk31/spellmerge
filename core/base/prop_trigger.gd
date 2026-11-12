class_name PropTrigger
extends Resource
## One trigger of a prop's state (props W6, docs/milestones/props.md, "Triggers"): when it fires
## (`when` and its numbers) and what it does then (`cast` one of the prop's staffs, `then` go to
## another state). A row of `PropState.triggers`; the `PropStateTriggers` component (gameplay/actor) fires
## it. It has no `id` on purpose, so the registry never takes it for content.
##
## Pure data, with the one question asked of it (`heard`): the component hands each moment over and
## this says whether the row fires on it, so a trigger's rule is written once, here.

## What sets it off. Each moment comes with a name and an amount (`heard`); a trigger reads only
## the numbers it names.
enum When {
	## A hit whose element is `element` lands (its first, as `Actor.damaged` names it and its damage
	## number is coloured), of at least `at_least` damage (0: any; an invincible prop's hits count
	## too). `element` empty: a plain hit (no element).
	ELEMENT_HIT,
	## The status `status` was put on it (a fire pool's burn).
	STATUS,
	## One of Combat's reactions between statuses, `reaction` (&"shatter"), happened on it.
	REACTION,
	## A hit took its health below `share` of its most (once: the hit that crossed it).
	HEALTH_BELOW,
	## Its health ran out.
	DEATH,
	## Its state was just entered (not the state it starts in).
	ENTERED,
	## Its staff `staff` (1-4) cast, by a trigger or by whoever possesses it: as the cast leaves,
	## after any wind-up.
	CAST,
	## A trigger's cast of its staff `staff` (1-4) did not go (props W9c): the staff was busy (winding
	## up, or in the delay after its last cast), it had nothing to cast (every card wasted, no aim) or,
	## `dry`, its mana pays none of its casts (a prop's pool never refills: an arc lodestone that has
	## zapped its pool's worth goes dark). With `dry` on it fires only for the mana, which is told
	## only of a staff that is free (a busy staff is refused as busy first); off, for any of them.
	REFUSED,
}

## The names of `When`, as the problems and the moments name them.
const WHEN_NAMES: PackedStringArray = ["element_hit", "status", "reaction", "health_below", "death", "entered", "cast", "refused"]
## The name a REFUSED moment comes with when the staff's mana paid none of its casts (`dry`).
const DRY: StringName = &"dry"

@export var when: When = When.ELEMENT_HIT
## ELEMENT_HIT: the hit's element (a card id: &"fire"; empty: a plain hit).
@export var element: StringName = &""
## ELEMENT_HIT: at least this much damage (0: any).
@export var at_least: float = 0.0
## STATUS: the status (&"burn").
@export var status: StringName = &""
## REACTION: the reaction (&"shatter").
@export var reaction: StringName = &""
## HEALTH_BELOW: the share of its most health (0-1).
@export_range(0.0, 1.0) var share: float = 0.0
## CAST, REFUSED: the staff (1-4) whose cast it hears.
@export_range(0, 4) var staff: int = 0
## REFUSED: only when the staff's mana pays none of its casts (off: whatever stopped it).
@export var dry: bool = false

## What it does: cast this staff of the prop's (1-4; 0: none), as the prop, along its aim.
@export_range(0, 4) var cast: int = 0
## Then go to the state with this id (empty: stay).
@export var then: StringName = &""


## A row that fires on `when_kind` (`cast` and `then` as given), for tests and code-made props.
static func make(when_kind: When, cast_staff: int = 0, then_state: StringName = &"") -> PropTrigger:
	var made := PropTrigger.new()
	made.when = when_kind
	made.cast = cast_staff
	made.then = then_state
	return made


## True when this row fires on a moment of `kind` with `name` (the element, status or reaction it
## is about, or REFUSED's `DRY`; empty for the others) and `amount` (a hit's damage, the health
## share it fell to, the staff number that cast or was refused). HEALTH_BELOW is handed the share it fell from too (`before`): it fires
## on the hit that crosses its share.
func heard(kind: When, name: StringName, amount: float, before: float = 1.0) -> bool:
	if kind != when:
		return false
	match when:
		When.ELEMENT_HIT:
			return name == element and amount >= at_least
		When.STATUS:
			return name == status
		When.REACTION:
			return name == reaction
		When.HEALTH_BELOW:
			return before >= share and amount < share
		When.CAST:
			return int(amount) == staff
		When.REFUSED:
			return int(amount) == staff and (not dry or name == DRY)
	return true


## Its trigger by name (`WHEN_NAMES`).
func when_name() -> String:
	return WHEN_NAMES[when]


## What is wrong with the row, one line each (empty when it is fine), given the prop's `staffs`
## (how many it holds), its `state_ids`, and the names the game knows (`known`: &"element",
## &"status", &"reaction", each a PackedStringArray; a kind left out is not checked). A row that
## does nothing, a staff the prop does not hold, a state that is not there, a name nobody knows, a
## number out of range.
func problems(staffs: int, state_ids: PackedStringArray, known: Dictionary = {}) -> PackedStringArray:
	var found := PackedStringArray()
	if cast == 0 and then == &"":
		found.append("%s does nothing (no cast, no then)." % when_name())
	if cast < 0 or cast > staffs:
		found.append("%s casts staff %d; the prop holds %d." % [when_name(), cast, staffs])
	if then != &"" and not state_ids.has(String(then)):
		found.append("%s goes to state '%s', which it does not have." % [when_name(), then])
	match when:
		When.ELEMENT_HIT:
			if element != &"":
				_check_known(found, known, &"element", element)
			if at_least < 0.0:
				found.append("element_hit: at_least is %s; 0 or more." % at_least)
		When.STATUS:
			if status == &"":
				found.append("status names no status.")
			else:
				_check_known(found, known, &"status", status)
		When.REACTION:
			if reaction == &"":
				found.append("reaction names no reaction.")
			else:
				_check_known(found, known, &"reaction", reaction)
		When.HEALTH_BELOW:
			if share <= 0.0 or share > 1.0:
				found.append("health_below: share is %s; above 0, at most 1." % share)
		When.CAST, When.REFUSED:
			if staff < 1 or staff > staffs:
				found.append("%s hears staff %d; the prop holds %d." % [when_name(), staff, staffs])
	return found


func _check_known(found: PackedStringArray, known: Dictionary, kind: StringName, name: StringName) -> void:
	if not known.has(kind):
		return
	var names: PackedStringArray = known[kind]
	if not names.has(String(name)):
		found.append("%s: '%s' is no %s the game knows (%s)." % [when_name(), name, kind, ", ".join(names)])
