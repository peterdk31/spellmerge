extends "res://tests/support/suite.gd"
## A beam's fan (+2, +3 on a beam: the owner's decisions of 2026-11-27, #972, #977): a beam a shot
## (+2 three, +3 four, both six), each from the caster, turned by its place in the fan, with the
## usual rules for its hits (no shared stem): what stands at the hand, where the beams cross, is hit
## by each of them.
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


func test_the_fan_is_a_beam_a_shot() -> void:
	for pair: Array in [[[], 1], [["plus_two"], 3], [["plus_three"], 4], [["plus_two", "plus_three"], 6], [["plus_two", "plus_two", "plus_two"], 7]]:
		var beams: CarrierBeam = _cast(pair[0])
		check_equal(beams.beam_count(), pair[1], "%s: %d beams" % [pair[0], pair[1]])
		_arena.free_all()
		_arena = null


func test_each_beam_leaves_from_the_caster() -> void:
	var beams: CarrierBeam = _cast(["plus_two", "plus_three"])
	var first: Vector2 = Vector2.INF
	var ways: Array[float] = []
	for row in beams.beam_slots():
		if not beams.beam_on(row):
			continue
		var start: Vector2 = beams.beam_point(row, 0)
		if not first.is_finite():
			first = start
		check(start.distance_to(first) < 0.01, "every beam starts at the same place (%s, %s)" % [start, first])
		ways.append(start.direction_to(beams.beam_point(row, 1)).angle())
	check_equal(ways.size(), 6, "six beams")
	for i in ways.size():
		for j in range(i + 1, ways.size()):
			check(absf(ways[i] - ways[j]) > 0.01, "each beam has its own way out")


func test_what_stands_at_the_hand_is_hit_by_each_beam() -> void:
	_arena = ArenaScript.new(root)
	var near: Node2D = _arena.add_imp(Vector2(10.0, 0.0))
	_arena.install_cards(0, 0, ["hold", "pierce", "plus_three", "beam"])
	check(_arena.cast(0, 0, Vector2.RIGHT), "cast")
	_arena.run(SpellLimits.BEAM_TICK * 2.0 - DT)
	var alone := ArenaScript.new(root)
	var near_alone: Node2D = alone.add_imp(Vector2(10.0, 0.0))
	alone.install_cards(0, 0, ["hold", "pierce", "beam"])
	check(alone.cast(0, 0, Vector2.RIGHT), "cast alone")
	alone.run(SpellLimits.BEAM_TICK * 2.0 - DT)
	check(alone.lost(near_alone) > 0, "one beam hits it")
	check(_arena.lost(near) > alone.lost(near_alone), "the fan's beams each hit it (%s against %s)" % [_arena.lost(near), alone.lost(near_alone)])
	alone.free_all()
