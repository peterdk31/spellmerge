extends "res://tests/support/suite.gd"
## A beam's fan (+2, +3 on a beam: the owner's decision of 2026-11-27, #972; `CarrierBeam.launch`):
## one trunk from the staff, SpellLimits.BEAM_TRUNK pixels along the aim, and the fan's beams from
## its end, as many as the shots (+2 three, +3 four, both six), each the trunk's length shorter. What
## stands on the trunk is hit once a beam tick, not once a beam; what stands past it, by the beams
## that reach it; a wall nearer than the trunk's end stops the fan there.
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")

const DT: float = 1.0 / 60.0

var _arena: ArenaScript = null


func after_each() -> void:
	if _arena != null:
		_arena.free_all()
		_arena = null
	super.after_each()


func _cast(cards: Array) -> CarrierBeam:
	_arena = ArenaScript.new(root)
	_arena.install_cards(0, 0, ["hold"] + cards + ["beam"])
	check(_arena.cast(0, 0, Vector2.RIGHT), "%s: cast" % [cards])
	_arena.run(DT * 2.0)
	return CarrierBeam.of(_arena.spells)


func test_the_fan_is_a_trunk_and_a_beam_a_shot() -> void:
	for pair: Array in [[[], 1], [["plus_two"], 4], [["plus_three"], 5], [["plus_two", "plus_three"], 7], [["plus_two", "plus_two", "plus_two"], 8]]:
		var beams: CarrierBeam = _cast(pair[0])
		check_equal(beams.beam_count(), pair[1], "%s: %d rows (a trunk and its beams, or one beam)" % [pair[0], pair[1]])
		_arena.free_all()
		_arena = null


func test_the_fan_leaves_from_the_trunks_end() -> void:
	var beams: CarrierBeam = _cast(["plus_two"])
	var trunk_end: Vector2 = Vector2.INF
	var starts: Array[Vector2] = []
	for row in beams.beam_slots():
		if not beams.beam_on(row):
			continue
		var start: Vector2 = beams.beam_point(row, 0)
		var reach: float = beams.beam_reach(row)
		if is_equal_approx(reach, SpellLimits.BEAM_TRUNK):
			trunk_end = start + Vector2.RIGHT * SpellLimits.BEAM_TRUNK
		else:
			starts.append(start)
	check(trunk_end.is_finite(), "a trunk BEAM_TRUNK long along the aim")
	check_equal(starts.size(), 3, "three beams in its fan")
	for start in starts:
		check(start.distance_to(trunk_end) < 0.01, "each starts at the trunk's end (%s, %s)" % [start, trunk_end])


func test_what_stands_on_the_trunk_is_hit_once_a_tick() -> void:
	_arena = ArenaScript.new(root)
	var near: Node2D = _arena.add_imp(Vector2(10.0, 0.0))
	_arena.install_cards(0, 0, ["hold", "pierce", "plus_three", "beam"])
	check(_arena.cast(0, 0, Vector2.RIGHT), "cast")
	_arena.run(SpellLimits.BEAM_TICK * 4.0 - DT)
	var alone := ArenaScript.new(root)
	var near_alone: Node2D = alone.add_imp(Vector2(10.0, 0.0))
	alone.install_cards(0, 0, ["hold", "pierce", "beam"])
	check(alone.cast(0, 0, Vector2.RIGHT), "cast alone")
	alone.run(SpellLimits.BEAM_TICK * 4.0 - DT)
	check(_arena.lost(near) > 0, "the trunk hits it")
	check_equal(_arena.lost(near), alone.lost(near_alone), "as one beam does, not once for each of the fan's four")
	alone.free_all()


func test_a_wall_before_the_trunks_end_stops_the_fan() -> void:
	_arena = ArenaScript.new(root)
	_arena.add_wall(Rect2(14.0, -60.0, 16.0, 120.0))
	var past: Node2D = _arena.add_imp(Vector2(80.0, 0.0))
	_arena.install_cards(0, 0, ["hold", "plus_two", "beam"])
	check(_arena.cast(0, 0, Vector2.RIGHT), "cast")
	_arena.run(0.5)
	check_equal(_arena.lost(past), 0, "nothing past the wall is hit")
	var beams: CarrierBeam = CarrierBeam.of(_arena.spells)
	for row in beams.beam_slots():
		if beams.beam_on(row):
			check(beams.beam_point(row, 0).x <= 14.0 + 0.01, "every row starts short of the wall (%s)" % beams.beam_point(row, 0))


## A Penta ring of fans (each copy cast by a point, turned in at the ring's centre every step): each
## fan's beams still start at the end of their own copy's trunk.
func test_a_ring_of_fans_leaves_from_each_trunks_end() -> void:
	var beams: CarrierBeam = _cast(["penta", "plus_two"])
	_arena.run(DT * 6.0)
	var trunk_ends: Array[Vector2] = []
	var starts: Array[Vector2] = []
	for row in beams.beam_slots():
		if not beams.beam_on(row) or beams.beam_point_count(row) < 2:
			continue
		var start: Vector2 = beams.beam_point(row, 0)
		var way: Vector2 = start.direction_to(beams.beam_point(row, 1))
		if is_equal_approx(beams.beam_reach(row), SpellLimits.BEAM_TRUNK):
			trunk_ends.append(start + way * SpellLimits.BEAM_TRUNK)
		else:
			starts.append(start)
	check(trunk_ends.size() >= 2, "a trunk for each copy (%d)" % trunk_ends.size())
	check_equal(starts.size(), trunk_ends.size() * 3, "three beams a trunk")
	for start in starts:
		var nearest: float = INF
		for end in trunk_ends:
			nearest = minf(nearest, start.distance_to(end))
		check(nearest < 0.05, "each beam starts at a trunk's end (%.3f px off)" % nearest)
