extends RefCounted
## What "Bag" (M2 part 18) can offer: the components of the bag that fit a free
## slot of a recipe without the full builder. A free slot is the empty element slot or the
## first free modifier slot (the form and the trigger are built in the full builder). Shared
## by the overlay and the quick view, so both offer the same and ask for the same slot.
##
## It only reads ids and kinds that a HUD node already has (the recipe from `recipe_changed`,
## the bag from `bag_changed`, kinds from `Spells.component_kind`); it creates nothing the
## player has not announced, and it sends nothing.

const SpellsScript := preload("res://core/spells/spells.gd")

## The slot numbers of `build_change_requested` (the contract of `gameplay/player`).
const SLOT_ELEMENT: int = 1
const SLOT_FIRST_MODIFIER: int = 2
const MAX_MODIFIERS: int = 3


## The free slot that takes a component of `kind` in `recipe`, or -1 if there is none.
static func free_slot_for(recipe: Dictionary, kind: StringName) -> int:
	if kind == &"element":
		return SLOT_ELEMENT if not recipe.has("element") else -1
	if kind == &"modifier":
		var modifiers: Variant = recipe.get("modifiers")
		var count: int = (modifiers as Array).size() if modifiers is Array else 0
		return SLOT_FIRST_MODIFIER + count if count < MAX_MODIFIERS else -1
	return -1


## The bag components that fit a free slot of `recipe`, in bag order, as ids and the slot each
## would go to (`ids[i]` goes to `slots[i]`).
static func choices(recipe: Dictionary, bag: Array[StringName], spells: SpellsScript) -> Dictionary:
	var ids: Array[StringName] = []
	var slots: Array[int] = []
	if spells != null:
		for id in bag:
			var slot: int = free_slot_for(recipe, spells.component_kind(id))
			if slot >= 0:
				ids.append(id)
				slots.append(slot)
	return {"ids": ids, "slots": slots}
