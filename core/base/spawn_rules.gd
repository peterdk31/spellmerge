class_name SpawnRules
extends Resource
## How a room's enemies come in (enemy spawning EA4, docs/milestones/enemy-spawning.md, "The data and
## how it reaches Flow"): in groups, the next only when the room gets quiet (the owner, 2026-11-17: no
## timer), each group a share of the room's enemy budget by cost (the measure the budget already uses).
## One biome's pace: `MapRules.spawning` (null: a room's whole list spawns in at once).
##
## The shares are of the room's **scaled** budget (`RunScaling.scaled_budget`), so a bigger party or a
## deeper room gets bigger groups in the same proportion as its bigger room. The run works the costs
## out (`group_cost`, `refill_cost`) and hands Flow plain numbers (`run_room_filled`); nothing of this
## Resource sits in a run's state.

## The cost of one group, as a share of the room's scaled budget: a group takes enemies from the
## front of the room's list until its cost reaches it (always one at least).
@export_range(0.0, 1.0, 0.01) var group_share: float = 0.35
## The cost still standing (or spawning) that calls the next group, as a share of the room's scaled
## budget: at it or below, the next group comes. Below `group_share`.
@export_range(0.0, 1.0, 0.01) var refill_share: float = 0.15
## Seconds between two bodies of one group starting to spawn in, so a group ripples in.
@export_range(0.0, 2.0, 0.01, "or_greater") var stagger: float = 0.15


## The cost of one group in a room of scaled budget `budget`: rounded, 1 at least.
func group_cost(budget: int) -> int:
	return maxi(1, roundi(float(budget) * group_share))


## The cost standing at or below which the next group comes, in a room of scaled budget `budget`:
## rounded, and always below the group's cost (so a group that just came never calls the next).
func refill_cost(budget: int) -> int:
	return clampi(roundi(float(budget) * refill_share), 0, group_cost(budget) - 1)


## What is wrong with it, one line each (empty when it is fine): a share outside 0 to 1 (or not a
## number), a group share of 0, a refill share not below the group share, a stagger that is not a
## number or below 0.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if not (group_share > 0.0 and group_share <= 1.0):
		found.append("group_share is %s; above 0, at most 1." % group_share)
	if not (refill_share >= 0.0 and refill_share <= 1.0):
		found.append("refill_share is %s; 0 to 1." % refill_share)
	elif not (refill_share < group_share):
		found.append("refill_share %s is not below group_share %s: a group would call the next at once." % [refill_share, group_share])
	if not is_finite(stagger) or stagger < 0.0:
		found.append("stagger is %s; 0 or more seconds." % stagger)
	return found
