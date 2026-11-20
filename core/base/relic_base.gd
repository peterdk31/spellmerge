class_name RelicBase
extends ItemContent
## A relic (connected biomes CB10, decision 26: only its hook for now; the relics themselves come
## with M3's relic work): a passive a player holds in their relics bag (`ItemKinds.RELIC`), found by
## the registry under `relics` (content/relics). What it does to the run's numbers is data: its list
## of stat changes (`stat_changes`), which `RunStats` applies for the player holding it, after the
## run's rule changes. A relic that changes how cards behave brings its own code with M3.
##
## An item's content (`ItemContent`: id, name, description, icon). **An active relic** (the owner,
## 2026-11-20) is one with an `active_use` (`use_of`): usable, so it binds to a d-pad arm and is used
## from there or the inventory. Its use is kept (`ItemUse.consumed` false): the relic stays in the
## bag with its stat changes, and recharges for its use's `cooldown` (the inventory's
## `recharge_left`); a use pressed while it recharges is refused.

## Its changes to the holder's run stats, applied in this order.
@export var stat_changes: Array[StatChange] = []
## What a use of it does (null: none, a passive relic): an active relic's. **Set its `consumed` to
## false** (an `ItemUse` is consumed by default, as a potion's drink is) and give it a `cooldown`, or
## a use takes the relic, its stat changes with it.
@export var active_use: ItemUse = null


## Its use: `active_use`.
func use_of() -> ItemUse:
	return active_use


## What is wrong with it, one line each: no id, an empty change, each change's own, its use's. (No
## icon or description is asked for yet: the relics themselves come with M3.)
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	var name: String = "The relic '%s'" % id
	if id == &"":
		found.append("A relic has no id.")
	for change: StatChange in stat_changes:
		if change == null:
			found.append("%s: an empty stat change." % name)
		else:
			found.append_array(change.problems(name))
	found.append_array(use_problems())
	return found
