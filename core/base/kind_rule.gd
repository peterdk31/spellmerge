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


## Rule `kind` from `first` to `last` (rows; below 0 from the end) at `of_weight`.
static func make(of_kind: StringName, first: int = 0, last: int = -1, of_weight: float = 1.0) -> KindRule:
	var rule := KindRule.new()
	rule.kind = of_kind
	rule.first_row = first
	rule.last_row = last
	rule.weight = of_weight
	return rule


## The row `row` as counted from the start of a map `depth` rows deep (a row below 0 counts from
## its end).
static func row_at(row: int, depth: int) -> int:
	return row if row >= 0 else depth + row


## True when it may stand in row `row` of a map `depth` rows deep.
func takes_row(row: int, depth: int) -> bool:
	return row >= 0 and row < depth and row >= row_at(first_row, depth) and row <= row_at(last_row, depth)


## True when a room of it may be led to from a room of kind `before`.
func may_follow(before: StringName) -> bool:
	return not not_after.has(before)


## What is wrong with the line, one line each (empty when it is fine): no kind, a kind not in
## `known` (when given: the room kinds there are), a weight of 0 or less, a negative limit.
func problems(known: Array[StringName] = []) -> PackedStringArray:
	var found := PackedStringArray()
	if kind == &"":
		found.append("A kind rule names no kind.")
	elif not known.is_empty() and not known.has(kind):
		found.append("Kind rule '%s': no room kind of that id." % kind)
	if weight <= 0.0:
		found.append("Kind rule '%s': its weight is %s; above 0." % [kind, weight])
	if max_per_row < 0 or max_per_run < 0:
		found.append("Kind rule '%s': a limit below 0 (0 is no limit)." % kind)
	for before: StringName in not_after:
		if not known.is_empty() and not known.has(before):
			found.append("Kind rule '%s': not_after names '%s', no room kind of that id." % [kind, before])
	return found
