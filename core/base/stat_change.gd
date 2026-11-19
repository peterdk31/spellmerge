class_name StatChange
extends Resource
## One change to a run stat (connected biomes CB10, docs/milestones/connected-biomes.md, "Run
## stats"): the stat it names (`RunStats.ROWS`), set to, raised by or multiplied by `amount`. A
## relic's list holds these (`RelicBase.stat_changes`), and a run's rule change that targets a stat
## becomes one (`RunRuleChange.as_stat_change`). Read-only content, shared like a card.

## How `amount` changes the number.
enum How {
	## The number becomes `amount`.
	SET,
	## The number grows by `amount` (below 0: shrinks).
	ADD,
	## The number is multiplied by `amount`.
	TIMES,
}

## The stat it changes (a row of `RunStats.ROWS`).
@export var stat: StringName = &""
## How `amount` changes it.
@export var how: How = How.ADD
## The amount.
@export var amount: float = 0.0


## A change of `of_stat` by `of_amount` (`by`).
static func make(of_stat: StringName, of_amount: float, by: How = How.ADD) -> StatChange:
	var made := StatChange.new()
	made.stat = of_stat
	made.amount = of_amount
	made.how = by
	return made


## The number `value` changed by it.
func changed(value: float) -> float:
	match how:
		How.ADD:
			return value + amount
		How.TIMES:
			return value * amount
	return amount


## What is wrong with it, one line each, named by `what`: a stat no row of `RunStats` has, an
## amount that is not a number.
func problems(what: String) -> PackedStringArray:
	var found := PackedStringArray()
	if not RunStats.has(stat):
		found.append("%s: no run stat '%s' (RunStats.ROWS)." % [what, stat])
	if not is_finite(amount):
		found.append("%s: the change of '%s' has an amount %s that is not a number." % [what, stat, amount])
	return found
