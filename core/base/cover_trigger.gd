@tool
class_name CoverTrigger
extends Resource
## One trigger of a cover kind's state (ground cover GC2, docs/milestones/ground-cover.md, rule 3):
## when it fires (`when` and its number) and the state it goes to then (`then`). A row of
## `CoverState.triggers`, shaped like a prop's (`PropTrigger`) on purpose. Data only: the cover area
## (gameplay/cover, GC5) fires it. It has no `id`, so the registry never takes it for content. A new
## kind of trigger (a trample that plays: `walked`) is engine work, a new `When`.

enum When {
	## An element touched the cell (`floor_touched`, GC5): fire, frost, ... (`element`, a card id).
	ELEMENT,
	## The cell has been in its state for `seconds`.
	AFTER,
}

## The names of `When`, as the problems name them.
const WHEN_NAMES: PackedStringArray = ["element", "after"]

@export var when: When = When.ELEMENT
## ELEMENT: the element that sets it off (a card id: &"fire").
@export var element: StringName = &""
## AFTER: the seconds in the state before it fires (above 0).
@export var seconds: float = 0.0
## The state it goes to (a `CoverState.state_id` of the same kind).
@export var then: StringName = &""


## A row firing on `when_kind` (`element` for ELEMENT, `after` seconds for AFTER) going to `then_state`.
static func make(when_kind: When, then_state: StringName, element_id: StringName = &"", after: float = 0.0) -> CoverTrigger:
	var made := CoverTrigger.new()
	made.when = when_kind
	made.then = then_state
	made.element = element_id
	made.seconds = after
	return made


## What is wrong with the row, one line each (empty when it is fine), given its kind's `state_ids`
## and the elements the game knows (`elements`; empty: not checked): no state to go to or one that is
## not there, an element trigger naming no element or an unknown one, a wait of no time.
func problems(state_ids: PackedStringArray, elements: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var found := PackedStringArray()
	var named: String = WHEN_NAMES[when] if when >= 0 and when < WHEN_NAMES.size() else "trigger %d" % when
	if then == &"":
		found.append("%s goes to no state (then)." % named)
	elif not state_ids.has(String(then)):
		found.append("%s goes to '%s', which is not one of its kind's states." % [named, then])
	match when:
		When.ELEMENT:
			if element == &"":
				found.append("element names no element.")
			elif not elements.is_empty() and not elements.has(String(element)):
				found.append("element '%s' is no element the game knows." % element)
		When.AFTER:
			if seconds <= 0.0:
				found.append("after waits %s seconds: give it more than 0." % seconds)
	return found
