class_name RelicBase
extends Resource
## A relic (connected biomes CB10, decision 26: only its hook for now; the relics themselves come
## with M3's relic work): a passive a player holds in their relics bag (`ItemKinds.RELIC`), found by
## the registry under `relics` (content/relics). What it does to the run's numbers is data: its list
## of stat changes (`stat_changes`), which `RunStats` applies for the player holding it, after the
## run's rule changes. A relic that changes how cards behave brings its own code with M3.

## Unique name, also its folder's; the registry finds it by this.
@export var id: StringName = &""
## Its name for people; empty: its id in words.
@export var display_name: String = ""
## What it says it does, for people.
@export_multiline var description: String = ""
## Its icon.
@export var icon: Texture2D = null
## Its changes to the holder's run stats, applied in this order.
@export var stat_changes: Array[StatChange] = []


## Its name for people: `display_name`, else its id in words.
func shown_name() -> String:
	return display_name if display_name != "" else String(id).capitalize()


## What is wrong with it, one line each: no id, an empty change, each change's own.
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
	return found
