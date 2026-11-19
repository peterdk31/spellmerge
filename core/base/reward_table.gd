class_name RewardTable
extends Resource
## A reward table (connected biomes CB10, docs/milestones/connected-biomes.md, decisions 16 and 17):
## what a reward offers its choices from, one weighted line each (`RewardEntry`). One file per
## table, `content/rewards/<id>.tres`, found by the registry under `rewards`; the first is
## `clear`, what a room's clear offers. The Rewards area rolls each player's choices from it, each
## choice a line other than the ones already offered (as long as lines are left). Read-only content.

## Unique name, also its folder's; the registry finds it by this.
@export var id: StringName = &""
## Its lines.
@export var entries: Array[RewardEntry] = []


## The sum of its lines' weights (lines that weigh nothing or less count nothing).
func total_weight() -> float:
	var total: float = 0.0
	for entry: RewardEntry in entries:
		if entry != null and entry.weight > 0.0:
			total += entry.weight
	return total


## What is wrong with it, one line each: no id, no line, an empty line, each line's own.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	var name: String = "The reward table '%s'" % id
	if id == &"":
		found.append("A reward table has no id.")
	if entries.is_empty():
		found.append("%s: no lines." % name)
	for entry: RewardEntry in entries:
		if entry == null:
			found.append("%s: an empty line." % name)
		else:
			found.append_array(entry.problems(name))
	return found
