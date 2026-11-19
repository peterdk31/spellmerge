class_name RunStats
extends RefCounted
## The run stats (connected biomes CB10, docs/milestones/connected-biomes.md, "Run stats", decision
## 26): named numbers the run's systems read by name (`value_of`, `whole_of`), never knowing where a
## change came from. Each is worked out for one player at a time: its base (`ROWS`), then the run's
## rule changes in order (`RunRuleChange` targets of `RUN_STAT`, the run's start's unlocks), then
## that player's relics in order (`RelicBase.stat_changes`), then held to its row's range (and
## rounded for a whole number). A new stat is a row here; a new relic is a file.
##
## Plain arithmetic on the changes (`+ - *`, the same on every machine); it keeps nothing, so the
## caller holds what it is worked out from (the run's changes are state where they are kept).
##
##     var choices: int = RunStats.whole_of(&"reward_choices", run_changes, relics)

## One row a stat: its base, the range it is held to and whether it is a whole number.
## - `reward_choices`: how many choices a reward offers ("pick 1 of 3": decision 17, raised from 2 by the owner, 2026-11-19).
## - `start_coins`: the coins put into a player's coin stack as a run starts (decision 18).
## - `price_scale`: what a shop's prices are multiplied by (CB11's shop).
## - `map_reveal`: how many rooms past the seen ones the map shows (CB9's map).
## - `secret_sense`: how far from a room the party entered a secret room shows on this player's own
##   map, in pixels (rectangle to rectangle; CB9's map, the owner's answer of 2026-11-19).
## - `fountain_pool`: what a fountain's pool is multiplied by (CB11).
## - `start_room_rerolls`, `start_reward_rerolls`: the room rerolls and reward rerolls put into a
##   player's currency bag as a run starts (`RerollBase`; the owner, 2026-11-19: 1 of each for now).
const ROWS: Dictionary = {
	&"reward_choices": {"base": 3.0, "low": 1.0, "high": 4.0, "whole": true},
	&"start_coins": {"base": 0.0, "low": 0.0, "high": 999.0, "whole": true},
	&"price_scale": {"base": 1.0, "low": 0.1, "high": 10.0, "whole": false},
	&"map_reveal": {"base": 0.0, "low": 0.0, "high": 99.0, "whole": true},
	&"secret_sense": {"base": 0.0, "low": 0.0, "high": 1024.0, "whole": false},
	&"fountain_pool": {"base": 1.0, "low": 0.0, "high": 10.0, "whole": false},
	&"start_room_rerolls": {"base": 1.0, "low": 0.0, "high": 99.0, "whole": true},
	&"start_reward_rerolls": {"base": 1.0, "low": 0.0, "high": 99.0, "whole": true},
}


## True when `stat` is a row.
static func has(stat: StringName) -> bool:
	return ROWS.has(stat)


## Every stat, in the table's order.
static func names() -> Array[StringName]:
	var out: Array[StringName] = []
	for stat: StringName in ROWS:
		out.append(stat)
	return out


## The base of `stat` (0 for no row).
static func base_of(stat: StringName) -> float:
	return float((ROWS.get(stat, {}) as Dictionary).get("base", 0.0))


## `stat` for one player: its base, changed by each of `run_changes` (the run's) and then by each
## relic's changes of `relics` (the player's), each in order, held to its range (rounded when whole).
## A change of another stat, an empty one and a relic that is no `RelicBase` change nothing. 0 for a
## stat no row has (with a warning).
static func value_of(stat: StringName, run_changes: Array[StatChange] = [], relics: Array[Resource] = []) -> float:
	if not ROWS.has(stat):
		push_warning("RunStats: no run stat '%s'." % stat)
		return 0.0
	var row: Dictionary = ROWS[stat]
	var value: float = float(row["base"])
	for change: StatChange in run_changes:
		if change != null and change.stat == stat:
			value = change.changed(value)
	for relic: Resource in relics:
		var held: RelicBase = relic as RelicBase
		if held == null:
			continue
		for change: StatChange in held.stat_changes:
			if change != null and change.stat == stat:
				value = change.changed(value)
	if not is_finite(value):
		value = float(row["base"])
	value = clampf(value, float(row["low"]), float(row["high"]))
	return roundf(value) if bool(row["whole"]) else value


## Every row's value for one player (`value_of`), by name.
static func all_of(run_changes: Array[StatChange] = [], relics: Array[Resource] = []) -> Dictionary:
	var out: Dictionary = {}
	for stat: StringName in names():
		out[stat] = value_of(stat, run_changes, relics)
	return out


## `stat` for one player as a whole number (`value_of`, rounded).
static func whole_of(stat: StringName, run_changes: Array[StatChange] = [], relics: Array[Resource] = []) -> int:
	return roundi(value_of(stat, run_changes, relics))
