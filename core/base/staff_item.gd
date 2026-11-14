class_name StaffItem
extends Resource
## A premade staff (items I6, docs/milestones/items.md, "The model"): a staff and the cards in it,
## as data, lying in a room for anyone to take (the hub's rack). One folder each under
## `content/items/staffs/<id>/` with its own test; the registry finds it under `items` by `id`
## (`ItemKinds.premade_of`). Taken, it is a staff like any other: its stack's id is its staff's
## (`stack()`), so nothing downstream knows it was premade.

## Unique name, also the folder name.
@export var id: StringName = &""
## The name a player reads near it; empty: its staff's.
@export var display_name: String = ""
## The staff (`StaffBase`, content/wizard/staffs: its slots, numbers and head).
@export var staff: StaffBase = null
## Card ids by slot (`&""` for an empty slot); no more than the staff's slots.
@export var cards: Array[StringName] = []


## The name shown: its own, else its staff's.
func shown_name() -> String:
	if display_name != "":
		return display_name
	return staff.shown_name() if staff != null else String(id)


## What it is as a stack: its staff holding its cards, the pool full (null with no staff).
func stack() -> ItemStack:
	if staff == null:
		return null
	return ItemStack.of_staff(staff, cards)


## What is wrong with it, one line each (empty when it is fine): an id, a staff, and no more cards
## than the staff has slots.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if id == &"":
		found.append("It has no id.")
	found.append_array(StaffCards.make(staff, cards).problems())
	return found
