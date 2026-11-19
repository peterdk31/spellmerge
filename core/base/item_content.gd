class_name ItemContent
extends Resource
## What a simple item is as content (the owner, 2026-11-19: every reward is an inventory item): an
## id, a name, what it says it does and its icon, all a reward's card or a bag shows of it
## (`ItemLooks`). A potion (`PotionBase`) and the coin (`CoinBase`) are one; each kind's folder and
## class are its row of `ItemKinds.RULES`. Read-only content.

## Unique name, also its folder's; the registry finds it by this.
@export var id: StringName = &""
## Its name for people; empty: its id in words.
@export var display_name: String = ""
## What it says it does, for people (a reward's card, the inventory).
@export_multiline var description: String = ""
## Its icon (16 by 16, drawn 2x on a reward's card).
@export var icon: Texture2D = null


## Its name for people: `display_name`, else its id in words.
func shown_name() -> String:
	return display_name if display_name != "" else String(id).capitalize()


## What is wrong with it, one line each: no id, no icon, no description.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	var name: String = "The item '%s'" % id
	if id == &"":
		found.append("An item has no id.")
	if icon == null:
		found.append("%s has no icon." % name)
	if description.strip_edges() == "":
		found.append("%s says nothing of what it does." % name)
	return found
