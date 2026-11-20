class_name ItemContent
extends Resource
## What a simple item is as content (the owner, 2026-11-19: every reward is an inventory item): an
## id, a name, what it says it does and its icon, all a reward's card or a bag shows of it
## (`ItemLooks`), and whether it is used (`usable`). A potion (`PotionBase`) and the coin (`CoinBase`) are one; each kind's folder and
## class are its row of `ItemKinds.RULES`; a relic (`RelicBase`) is one too. Read-only content.
##
## **Usable** (the owner, 2026-11-20): the one place that says whether an item is used and what its
## use does. `usable` tags it; `use_of()` is what a use does (an `ItemUse`; null: none). Only a tagged
## item is used from the bag or bound to a d-pad arm (`ItemKinds.usable`), and a tagged one must have
## a use, or the content validator rejects it (`use_problems`, `Registry.validate_items`).

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
## from the kind (`ItemKinds.usable`). The potions are, today; a relic can be (its `active_use`).
## `tests/gameplay/player/test_usable_items.gd` uses every tagged item.
@export var usable: bool = false


## Its name for people: `display_name`, else its id in words.
func shown_name() -> String:
	return display_name if display_name != "" else String(id).capitalize()


## What a use of it does (an `ItemUse`), or null for none: overridden by a kind that has one.
func use_of() -> ItemUse:
	return null


## What is wrong with its use, one line each: tagged usable with no use that does something, or a
## use that does something without the tag (it would never be used).
func use_problems() -> PackedStringArray:
	var found := PackedStringArray()
	var use: ItemUse = use_of()
	var has_use: bool = use != null and use.does_something()
	if usable and not has_use:
		found.append("The item '%s' (%s) is tagged usable but has no use: give it one (a potion's heal or more_most, a relic's active_use) or clear its usable tag." % [id, resource_path])
	elif has_use and not usable:
		found.append("The item '%s' (%s) has a use but is not tagged usable, so it is never used: set its usable tag, or remove the use." % [id, resource_path])
	return found


## What is wrong with it, one line each: no id, no icon, no description, its use's.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	var name: String = "The item '%s'" % id
	if id == &"":
		found.append("An item has no id.")
	if icon == null:
		found.append("%s has no icon." % name)
	if description.strip_edges() == "":
		found.append("%s says nothing of what it does." % name)
	found.append_array(use_problems())
	return found
