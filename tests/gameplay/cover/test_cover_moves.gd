extends "res://tests/support/suite.gd"
## The cover kinds' moves as tables (ground cover GC6, gameplay/cover/cover_moves.gd): each state's
## move on each element, after how long and what it spreads are what its data says by the area's
## rules (a row to a state its kind lacks, or to the state itself, moves nothing; the first `after`
## row whose seconds have passed); a kind is its index in the layout's kinds, an element its index.
##
## godot --headless --path . --script res://tests/gameplay/cover/test_cover_moves.gd

const CoverMoves := preload("res://gameplay/cover/cover_moves.gd")
const GRASS: CoverKind = preload("res://tests/core/fixtures/cover_content/cover/test_grass/test_grass.tres")

const REST: int = 0
const BURNING: int = 1
const ASH: int = 2


static func _row(when: CoverTrigger.When, element: StringName, seconds: float, then: StringName) -> CoverTrigger:
	var row := CoverTrigger.new()
	row.when = when
	row.element = element
	row.seconds = seconds
	row.then = then
	return row


func test_the_test_grass_as_its_data_says() -> void:
	var moves: CoverMoves = CoverMoves.of([GRASS] as Array[CoverKind])
	var fire: int = moves.element(&"fire")
	var frost: int = moves.element(&"frost")
	check(fire >= 0 and frost >= 0, "every element named")
	check_equal(moves.element(&"storm"), -1, "one no row names: none")
	check_equal(moves.moved_to(0, REST, fire), BURNING, "rest -fire-> burning")
	check_equal(moves.moved_to(0, REST, frost), -1, "frost does nothing at rest")
	check_equal(moves.moved_to(0, BURNING, frost), REST, "burning -frost-> rest")
	check_equal(moves.moved_to(0, BURNING, fire), -1, "fire does nothing burning")
	check_equal(moves.moved_to(-1, REST, fire), -1, "no kind: nothing")
	check_equal(moves.moved_to(0, REST, -1), -1, "no element: nothing")
	check_equal(moves.after(0, BURNING, 1.1), -1, "burning, not yet")
	check_equal(moves.after(0, BURNING, 1.2), ASH, "burning -1.2 s-> ash")
	check_equal(moves.after(0, ASH, 30.0), REST, "ash -30 s-> rest")
	check_equal(moves.after(0, REST, 1.0e9), -1, "rest stays")
	check_equal(moves.spread_of(0, BURNING), fire, "burning spreads fire")
	check_equal(moves.spread_chance(0, BURNING), 0.6, "at its chance")
	check_equal(moves.spread_of(0, REST), -1, "rest spreads nothing")


func test_rows_that_would_not_move_a_cell_move_nothing() -> void:
	var kind := GRASS.duplicate(true) as CoverKind
	var burning: CoverState = kind.states[BURNING]
	burning.triggers = [
		_row(CoverTrigger.When.ELEMENT, &"fire", 0.0, &"burning"),
		_row(CoverTrigger.When.ELEMENT, &"frost", 0.0, &"nowhere"),
		_row(CoverTrigger.When.AFTER, &"", 0.5, &"nowhere"),
		_row(CoverTrigger.When.AFTER, &"", 0.8, &"burning"),
		_row(CoverTrigger.When.AFTER, &"", 2.0, &"rest"),
		_row(CoverTrigger.When.AFTER, &"", 1.0, &"ash"),
	] as Array[CoverTrigger]
	var moves: CoverMoves = CoverMoves.of([kind] as Array[CoverKind])
	check_equal(moves.moved_to(0, BURNING, moves.element(&"fire")), -1, "to itself: nothing")
	check_equal(moves.moved_to(0, BURNING, moves.element(&"frost")), -1, "to a state it lacks: nothing")
	check_equal(moves.after(0, BURNING, 0.9), -1, "the rows that would not move it are passed over")
	check_equal(moves.after(0, BURNING, 1.5), ASH, "a later row whose seconds passed, the earlier's not yet")
	check_equal(moves.after(0, BURNING, 2.0), REST, "the first in order whose seconds passed")
	var still := GRASS.duplicate(true) as CoverKind
	still.states[BURNING].spread_chance = 0.0
	check_equal(CoverMoves.of([still] as Array[CoverKind]).spread_of(0, BURNING), -1, "no chance: no spread")


func test_each_kind_its_own_rows() -> void:
	var webs := GRASS.duplicate(true) as CoverKind
	webs.id = &"webs"
	webs.states = [webs.states[REST], webs.states[BURNING]] as Array[CoverState]
	webs.states[BURNING].triggers = [_row(CoverTrigger.When.AFTER, &"", 0.3, &"rest")] as Array[CoverTrigger]
	var moves: CoverMoves = CoverMoves.of([GRASS, webs] as Array[CoverKind])
	check_equal(moves.width, 3, "rows as wide as the most states")
	check_equal(moves.after(1, BURNING, 0.3), REST, "the second kind's own")
	check_equal(moves.after(0, BURNING, 0.3), -1, "the first kind's own")
	check_equal(moves.moved_to(1, REST, moves.element(&"fire")), BURNING, "both light")
