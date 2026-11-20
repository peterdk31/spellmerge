class_name ItemContent
extends Resource
## What a simple item is as content (the owner, 2026-11-19: every reward is an inventory item): an
## id, a name, what it says it does and its icon, all a reward's card or a bag shows of it
## (`ItemLooks`), and whether it is used (`usable`). A potion (`PotionBase`) and the coin (`CoinBase`) are one; each kind's folder and
## class are its row of `ItemKinds.RULES`. Read-only content.

## Unique name, also its folder's; the registry finds it by this.
@export var id: StringName = &""
## Its name for people; empty: its id in words.
@export var display_name: String = ""
## What it says it does, for people (a reward's card, the inventory).
@export_multiline var description: String = ""
## Its icon (16 by 16, drawn 2x on a reward's card).
@export var icon: Texture2D = null
## Tagged usable (the owner, 2026-11-20: "only usable items can be bound to the D-pad"): it is used
## from the bag (the inventory's A, `bag_use_requested`) and can be bound to a d-pad arm
## (`Inventory.bind_quick`, auto-bound as it is taken). Only a tagged item is; nothing infers it
## from the kind (`ItemKinds.usable`). The potions are, today: a new item becomes bindable by this
## tag alone, and what using it does is the player controller's (`_use_item`: a potion is drunk),
## so a tagged class it has no use for yet needs one there; `tests/gameplay/player/test_usable_items.gd`
## uses every tagged item and fails for one it cannot use.
@export var usable: bool = false


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
