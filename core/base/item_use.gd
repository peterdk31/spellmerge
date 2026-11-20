class_name ItemUse
extends Resource
## What using an item does (the owner, 2026-11-20): the one place that says it. **An item is usable
## exactly when it has a use** (`ItemContent.use_of()`, `ItemKinds.usable`): only then is it used
## from the bag or bound to a d-pad arm. A use says what it does (its health gift, which the player
## controller applies through Combat: `health_gift_requested`), whether it is `consumed` (one copy
## taken: a potion) or kept, and its `cooldown` (a kept active relic recharges for it, its passive
## stat changes staying with it). Read-only data; a potion's is made from its own numbers
## (`PotionBase`), a relic's is its `active_use`. A new kind of effect is a field here and its line
## in the controller.
##
##     var drink := ItemUse.health(30.0, 0.0)
##     if not drink.wasted_on(health, most): ...

## The health a use heals.
@export_range(0.0, 999.0) var heal: float = 0.0
## The most health a use adds (and as much health).
@export_range(0.0, 999.0) var more_most: float = 0.0
## Whether a use takes one copy (a potion), or keeps it (an active relic).
@export var consumed: bool = true
## Seconds after a use before it can be used again (0: at once), counted down with the simulation's
## delta (the inventory's `step`).
@export_range(0.0, 600.0) var cooldown: float = 0.0


## A use that heals `heals` and adds `adds` most health, consumed, with no cooldown (a drink).
static func health(heals: float, adds: float) -> ItemUse:
	var made := ItemUse.new()
	made.heal = heals
	made.more_most = adds
	return made


## True when it does something at all.
func does_something() -> bool:
	return heal > 0.0 or more_most > 0.0


## True when a use of it does nothing for a body at `health` of `most`: it only heals, and the body
## is whole (so a use is refused, not wasted).
func wasted_on(health: float, most: float) -> bool:
	return more_most <= 0.0 and health >= most


## What is wrong with it, one line each, `owner_name` the item it is the use of (with how to fix it).
func problems(owner_name: String) -> PackedStringArray:
	var found := PackedStringArray()
	if not does_something():
		found.append("%s has a use that does nothing: give it a heal or more_most, or remove the use so it is not usable." % owner_name)
	if cooldown < 0.0:
		found.append("%s has a use with a negative cooldown (%s): make it 0 or more." % [owner_name, cooldown])
	return found
