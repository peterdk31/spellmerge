class_name ItemContent
extends Resource
## What a simple item is as content (the owner, 2026-11-19: every reward is an inventory item): an
## id, a name, what it says it does and its icon, all a reward's card or a bag shows of it
## (`ItemLooks`), and what using it does (`use_of`). A potion (`PotionBase`) and the coin (`CoinBase`) are one; each kind's folder and
## class are its row of `ItemKinds.RULES`; a relic (`RelicBase`) is one too. Read-only content.
##
## **Usable exactly when it has a use** (the owner, 2026-11-20): `use_of()` is its use (an `ItemUse`:
## what using it does, whether it is consumed, its cooldown; null: none, never used). Only an item
## with one is used from the bag or bound to a d-pad arm (`ItemKinds.usable`); a potion's is its
## drink, a relic's its `active_use`. The content validator checks the use itself (`use_problems`,
## `Registry.validate_items`).

## Unique name, also its folder's; the registry finds it by this.
@export var id: StringName = &""
## Its name for people; empty: its id in words.
@export var display_name: String = ""
## What it says it does, for people (a reward's card, the inventory).
@export_multiline var description: String = ""
## Its icon (16 by 16 world units: at 2x detail a 32 by 32 `icon@2x.svg`, ArtDetail; drawn 2x on a reward's card).
@export var icon: Texture2D = null


## Its name for people: `display_name`, else its id in words.
func shown_name() -> String:
	return display_name if display_name != "" else String(id).capitalize()


## What a use of it does (an `ItemUse`), or null for none: overridden by a kind that has one.
func use_of() -> ItemUse:
	return null


## What is wrong with its use, one line each (`ItemUse.problems`; none for an item with no use).
func use_problems() -> PackedStringArray:
	var use: ItemUse = use_of()
	return use.problems("The item '%s' (%s)" % [id, resource_path]) if use != null else PackedStringArray()


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
