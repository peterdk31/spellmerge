class_name KindRule
extends Resource
## One line of a biome's room-kind table (run generation RG1, docs/milestones/run-generation.md,
## "The model"): a kind of room (`RoomKind` id), the rows of the map it may stand in, how often
## against the other kinds there (`weight`), how many at most in a row and in the run, and which
## kinds may not lead to it. A sub-resource of `MapRules.kinds`. The generator (RG2) follows the
## table as it is, so a new kind of room placed somewhere is one more line here and no code.
##
## Rows count from 0, the map's first room; a negative row counts from the end of the map, so -1
## is its last row whatever its depth (the boss's), -2 the one before.
##
## **On a biome's map** (connected biomes CB5, docs/milestones/connected-biomes.md, decision 1;
## `BiomeGenerator`) a row is a depth, the fewest bridges from the start room (0), and -1 the
## deepest: the line that takes only it (`stands_deepest`, the boss) is the way's end, and every
## other room stands shallower. A biome holds `least` rooms of a line (its fixed kinds), each room
## past those up to `max_per_run` by `chance` (its chance kinds), and the rest of its rooms are the
## lines with no `max_per_run`, by `weight`. A `dead_end` line's rooms are reached by one bridge and
## lead nowhere (a secret room, the boss). `max_per_row` means nothing there.

## The most its weight and limits may be (the editor's ranges; a rule change, run generation RG6,
## may not pass them either).
const MOST_WEIGHT: float = 100.0
const MOST_PER_ROW: int = 16
const MOST_PER_RUN: int = 64

## The kind (`RoomKind.id`).
@export var kind: StringName = &""
## The first row it may stand in (0: the first room; below 0 from the end, -1 the last).
@export var first_row: int = 0
## The last row it may stand in (below 0 from the end: -1 the map's last row).
@export var last_row: int = -1
## How often it is picked against the other kinds that may stand in a row (above 0).
@export_range(0.01, 100.0, 0.01) var weight: float = 1.0
## How many rooms of it a row may hold at most (0: no limit).
@export_range(0, 16) var max_per_row: int = 0
## How many rooms of it the run may hold at most (0: no limit).
@export_range(0, 64) var max_per_run: int = 0
## The kinds that may not lead to it (a room of one of them never links to a room of this one).
@export var not_after: Array[StringName] = []
## True (the default): the run needs it, and content that cannot fill it is a problem. False: when
## the biome's content cannot fill it (no template hosts it, or its pool is empty) the line is left
## out, and a row only it could take is left out of the map (the crypt's boss: until a boss names
## the crypt, the run ends at its deepest fight).
@export var required: bool = true
## How many rooms of it every biome's map holds (connected biomes CB5: the fixed kinds, decision 1;
## the row map ignores it). At most `max_per_run` where that is set.
@export_range(0, 64) var least: int = 0
## The chance of each room of it past `least`, up to `max_per_run`, on a biome's map (the chance
## kinds, decision 1: a fountain, a second secret room). 0: none past `least`; a line with no
## `max_per_run` fills by `weight` instead.
@export_range(0.0, 1.0, 0.01) var chance: float = 0.0
## True when a room of it on a biome's map is a dead end: one bridge leads to it and none on (a
## secret room, the boss).
@export var dead_end: bool = false


## Rule `kind` from `first` to `last` (rows; below 0 from the end) at `of_weight`.
static func make(of_kind: StringName, first: int = 0, last: int = -1, of_weight: float = 1.0) -> KindRule:
	var rule := KindRule.new()
	rule.kind = of_kind
	rule.first_row = first
	rule.last_row = last
	rule.weight = of_weight
	return rule


## A copy of its own, its `not_after` too (run generation RG6, `MapRules.copied`).
func copied() -> KindRule:
	var made: KindRule = duplicate(false)
	made.not_after = not_after.duplicate()
	return made


## The row `row` as counted from the start of a map `depth` rows deep (a row below 0 counts from
## its end).
static func row_at(row: int, depth: int) -> int:
	return row if row >= 0 else depth + row


## True when it may stand in row `row` of a map `depth` rows deep.
func takes_row(row: int, depth: int) -> bool:
	return row >= 0 and row < depth and row >= row_at(first_row, depth) and row <= row_at(last_row, depth)


## True when it stands only at the deepest of a map (its first and last row -1): on a biome's map,
## the way's end (the boss).
func stands_deepest() -> bool:
	return first_row == -1 and last_row == -1


## True when a room of it may be led to from a room of kind `before`.
func may_follow(before: StringName) -> bool:
	return not not_after.has(before)


## What is wrong with the line, one line each (empty when it is fine): no kind, a kind not in
## `known` (the room kinds there are), rows out of order, a weight of 0 or less, a negative limit.
func problems(known: Array[StringName]) -> PackedStringArray:
	var found := PackedStringArray()
	if kind == &"":
		found.append("A kind rule names no kind.")
	elif not known.has(kind):
		found.append("Kind rule '%s': no room kind of that id." % kind)
	if (first_row >= 0) == (last_row >= 0) and first_row > last_row:
		found.append("Kind rule '%s': rows %d to %d, the first after the last." % [kind, first_row, last_row])
	if not (weight > 0.0) or weight > MOST_WEIGHT:
		found.append("Kind rule '%s': its weight is %s; above 0, %s at most." % [kind, weight, MOST_WEIGHT])
	if max_per_row < 0 or max_per_run < 0:
		found.append("Kind rule '%s': a limit below 0 (0 is no limit)." % kind)
	if max_per_row > MOST_PER_ROW or max_per_run > MOST_PER_RUN:
		found.append("Kind rule '%s': limits %d a row and %d a run; %d and %d at most." % [kind, max_per_row, max_per_run, MOST_PER_ROW, MOST_PER_RUN])
	if least < 0 or least > MOST_PER_RUN or (max_per_run > 0 and least > max_per_run):
		found.append("Kind rule '%s': least %d; 0 to %d, and max_per_run (%d) at most where that is set." % [kind, least, MOST_PER_RUN, max_per_run])
	if not (chance >= 0.0 and chance <= 1.0):
		found.append("Kind rule '%s': its chance is %s; 0 to 1." % [kind, chance])
	elif chance > 0.0 and max_per_run == 0:
		found.append("Kind rule '%s': a chance of %s but no max_per_run: a line with no limit fills by weight, so its chance does nothing; set max_per_run." % [kind, chance])
	for before: StringName in not_after:
		if not known.has(before):
			found.append("Kind rule '%s': not_after names '%s', no room kind of that id." % [kind, before])
	return found
