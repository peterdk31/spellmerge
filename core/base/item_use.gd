class_name ItemUse
extends Resource
## What using an item does (the owner, 2026-11-20: an item tagged usable is used from the bag or its
## d-pad arm): read-only data, the one description of a use, which the player controller applies
## (`PlayerController._use_item`: one copy taken, then its health gift through Combat,
## `health_gift_requested`). An item gives its use by `ItemContent.use_of()`: a potion's from its own
## numbers (`PotionBase`), a relic's `active_use`. A new kind of effect is a field here and its line
## in the controller.
##
##     var drink := ItemUse.health(30.0, 0.0)
##     if not drink.wasted_on(health, most): ...

## The health a use heals.
@export_range(0.0, 999.0) var heal: float = 0.0
## The most health a use adds (and as much health).
@export_range(0.0, 999.0) var more_most: float = 0.0


## A use that heals `heals` and adds `adds` most health.
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
