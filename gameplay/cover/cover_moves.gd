extends RefCounted
## The moves of a room's cover kinds as tables (ground cover GC6, docs/milestones/ground-cover.md,
## "Cost"): what each state of each kind does on an element, after how long, and what it spreads,
## worked out once from the kinds' data as a room is laid out, so the cover area's step reads packed
## arrays instead of the kinds' resources (a state's triggers looked up for every cell and its four
## neighbours each tick were most of the step's cost). Derived, never state: the same kinds make the
## same tables. It names no kind, state or element; it only reads `CoverKind.states` and their
## `CoverTrigger` rows, with the area's rules (gameplay/cover/README.md, "The step"):
##
## - an element moves a cell on through its state's first `element` row naming it, to the state that
##   row names, unless its kind has no such state or it is the state the cell is in (that row renews
##   the cell instead: its seconds from 0, in a touch only, never a spread);
## - a cell moves on after a while through its state's first `after` row whose seconds have passed,
##   among the rows that would move it (to a state its kind has, other than its own);
## - a state spreads its `spreads` element when it names one and its `spread_chance` is above 0.
##
## A kind is its index in the layout's `kinds` (a cell's `CoverLayout.cells` value less one); an
## element its index in `elements`.
##
## The cover area's two hot loops (`cover.gd`'s `_apply_touches` and `_step_cells`) read the tables
## directly, with `moved_to`'s index and `after`'s scan written out there: change the layout or the
## rules here and change them there (tests/gameplay/cover/test_cover.gd plays them).

## Every element a trigger or a spread of the kinds names, in the order first met.
var elements: Array[StringName] = []
## The most states any kind has: a kind's rows are this many wide.
var width: int = 0
## The tables, read only (the cover area's step reads them directly in its loops): for each kind,
## state and element (`(kind * width + state) * elements.size() + element`), the state it moves on
## to, or -1.
var to_table: PackedInt32Array = PackedInt32Array()
## For each kind and state: the element it spreads (its index), or -1; and its chance a second.
var spread_table: PackedInt32Array = PackedInt32Array()
var chance_table: PackedFloat64Array = PackedFloat64Array()
## For each kind and state: its first `after` row (into `after_seconds` and `after_to`) and how
## many (each row's seconds and state), in its triggers' order, only those that would move it.
var after_first: PackedInt32Array = PackedInt32Array()
var after_count: PackedInt32Array = PackedInt32Array()
var after_seconds: PackedFloat64Array = PackedFloat64Array()
var after_to: PackedInt32Array = PackedInt32Array()
## For each kind and state: 1 when a body standing in it is given something, a status or a strike
## (`CoverState.gives`: what the area counts as harming, and so looks at bodies for).
var harms_table: PackedByteArray = PackedByteArray()
## For each kind and state: 1 when it is danger (`CoverState.is_danger`, GC7: what the AI's look
## marks; a `harmless` state's soak or chill is not).
var danger_table: PackedByteArray = PackedByteArray()
## For each kind, state and element (as `to_table`): 1 when that element's row names the state itself,
## which renews it (its seconds from 0, nothing moved; the floor's first slice: water on a wet cell).
var renew_table: PackedByteArray = PackedByteArray()


## The tables of `kinds` (a layout's, in its order).
static func of(kinds: Array[CoverKind]) -> RefCounted:
	var moves := new()
	moves._build(kinds)
	return moves


func _build(kinds: Array[CoverKind]) -> void:
	for kind in kinds:
		width = maxi(width, kind.states.size())
		for state in kind.states:
			if state == null:
				continue
			_name_element(state.spreads)
			for row in state.triggers:
				if row != null and row.when == CoverTrigger.When.ELEMENT:
					_name_element(row.element)
	var rows: int = kinds.size() * width
	to_table.resize(rows * elements.size())
	to_table.fill(-1)
	spread_table.resize(rows)
	spread_table.fill(-1)
	chance_table.resize(rows)
	chance_table.fill(0.0)
	after_first.resize(rows)
	after_count.resize(rows)
	after_count.fill(0)
	harms_table.resize(rows)
	harms_table.fill(0)
	danger_table.resize(rows)
	danger_table.fill(0)
	renew_table.resize(rows * elements.size())
	renew_table.fill(0)
	for k in kinds.size():
		var kind: CoverKind = kinds[k]
		for s in kind.states.size():
			var state: CoverState = kind.states[s]
			var row: int = k * width + s
			after_first[row] = after_seconds.size()
			if state == null:
				continue
			harms_table[row] = 1 if state.gives() else 0
			danger_table[row] = 1 if state.is_danger() else 0
			for e in elements.size():
				var then: StringName = state.on_element(elements[e])
				var to: int = kind.state_at(then) if then != &"" else -1
				to_table[row * elements.size() + e] = to if to != s else -1
				renew_table[row * elements.size() + e] = 1 if to == s else 0
			if state.spreads != &"" and state.spread_chance > 0.0:
				spread_table[row] = elements.find(state.spreads)
				chance_table[row] = state.spread_chance
			for trigger in state.triggers:
				if trigger == null or trigger.when != CoverTrigger.When.AFTER:
					continue
				var to: int = kind.state_at(trigger.then)
				if to >= 0 and to != s:
					after_seconds.append(trigger.seconds)
					after_to.append(to)
					after_count[row] += 1


func _name_element(element: StringName) -> void:
	if element != &"" and not elements.has(element):
		elements.append(element)


## The index of `element` in `elements` (-1: no kind moves on it).
func element(name: StringName) -> int:
	return elements.find(name)


## The state element `e` moves kind `kind`'s state `state` on to, or -1 (no kind, no element).
func moved_to(kind: int, state: int, e: int) -> int:
	if kind < 0 or e < 0:
		return -1
	return to_table[(kind * width + state) * elements.size() + e]


## The element kind `kind`'s state `state` spreads (its index), or -1.
func spread_of(kind: int, state: int) -> int:
	return spread_table[kind * width + state]


## The chance a second kind `kind`'s state `state` spreads with.
func spread_chance(kind: int, state: int) -> float:
	return chance_table[kind * width + state]


## The state kind `kind`'s state `state` moves on to after `age` seconds in it, or -1.
func after(kind: int, state: int, age: float) -> int:
	var row: int = kind * width + state
	var first: int = after_first[row]
	for at in range(first, first + after_count[row]):
		if age >= after_seconds[at]:
			return after_to[at]
	return -1
