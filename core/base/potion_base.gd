class_name PotionBase
extends ItemContent
## A potion (the owner, 2026-11-19): an item kept in the potions bag (`ItemKinds.POTION`) and drunk
## when its player likes (the inventory's A, the command `bag_use_requested`; the player
## controller, gameplay/player). Nothing happens until it is drunk: then its wizard gains
## `more_most` most health (and as much health) and is healed `heal`, through Combat
## (`health_gift_requested`). One folder each, `content/potions/<id>/`, found by the registry under
## `potions`. Every potion is tagged `usable`; its use (`use_of`) is its own two numbers.

## The health a drink heals.
@export_range(0.0, 999.0) var heal: float = 0.0
## The most health a drink adds (and as much health).
@export_range(0.0, 999.0) var more_most: float = 0.0


## A drink: its heal and its most health (`ItemUse`).
func use_of() -> ItemUse:
	return ItemUse.health(heal, more_most)


## True when a drink of it does nothing for a body at `health` of `most` (`ItemUse.wasted_on`).
func wasted_on(health: float, most: float) -> bool:
	return use_of().wasted_on(health, most)


## What is wrong with it, one line each: its item's, and a potion that does nothing (said once: a
## tagged one's use already says it).
func problems() -> PackedStringArray:
	var found: PackedStringArray = super.problems()
	if heal <= 0.0 and more_most <= 0.0 and not usable:
		found.append("The potion '%s' neither heals nor adds most health." % id)
	return found
