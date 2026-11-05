extends "res://tests/support/suite.gd"
## Penta (ModifierBase.Behaviour.PENTA; docs/milestones/portal.md, "Penta"): the carrier cast five
## times from a ring round the nearest foe, aimed in at it, or round the point it would reach with
## no foe; more cards add copies; wasted where nothing leaves from a point (a dash, a swing).
##
## godot --headless --path . --script res://tests/core/test_penta.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")

var _arena: ArenaScript = null


func after_each() -> void:
	if _arena != null:
		_arena.free_all()
		_arena = null


func _shots() -> Array[int]:
	var out: Array[int] = []
	for slot in _arena.projectiles._high:
		if _arena.projectiles.is_alive(slot):
			out.append(slot)
	return out


func test_five_bolts_from_a_ring_round_the_foe_all_aimed_at_it() -> void:
	_arena = ArenaScript.new(root)
	var imp: Node2D = _arena.add_imp(Vector2(150, 30))
	_arena.install_cards(0, 0, ["penta", "bolt"])
	check(_arena.cast(0, 0), "cast")
	var shots: Array[int] = _shots()
	check_equal(shots.size(), 5, "five bolts")
	var nearest: float = INF
	for slot in shots:
		var at: Vector2 = _arena.projectiles.get_position_of(slot)
		var to_imp: Vector2 = at.direction_to(imp.global_position)
		check(_arena.projectiles.get_velocity_of(slot).normalized().dot(to_imp) > 0.99, "each flies at the imp")
		check(at.distance_to(imp.global_position) > SpellLimits.PENTA_RING - 1.0, "from its ring, past its edge")
		nearest = minf(nearest, at.length())
	check(nearest < Vector2(150, 30).length(), "the first on the caster's side")
	_arena.run(1.0)
	check(_arena.lost(_arena.imps[0]) > 0, "and they hit it")


func test_with_no_foe_it_rings_the_point_the_carrier_reaches() -> void:
	_arena = ArenaScript.new(root)
	_arena.install_cards(0, 0, ["penta", "beam"])
	check(_arena.cast(0, 0), "cast")
	var beams: CarrierBeam = CarrierBeam.of(_arena.spells)
	check_equal(beams.beam_count(), 5, "five beams")
	# The beam reaches 240, the card looks 200: the point is 200 ahead.
	var middle: Vector2 = Vector2(200, 0)
	for at in beams.beam_slots():
		if beams.beam_on(at):
			var origin: Vector2 = beams.beam_origin(at)
			check(is_equal_approx(origin.distance_to(middle), SpellLimits.PENTA_RING), "each beam starts on the ring (%s)" % origin)
	_arena.run(0.1)
	for at in beams.beam_slots():
		if beams.beam_on(at):
			check(is_equal_approx(beams.beam_origin(at).distance_to(middle), SpellLimits.PENTA_RING), "and stays there, cast by its point")


func test_two_cards_cast_ten() -> void:
	_arena = ArenaScript.new(root)
	_arena.add_imp(Vector2(150, 0))
	_arena.install_cards(0, 0, ["penta", "penta", "bolt"])
	check(_arena.cast(0, 0), "cast")
	check_equal(_shots().size(), 10, "ten bolts")


func test_a_short_carrier_rings_within_its_reach() -> void:
	_arena = ArenaScript.new(root)
	var imp: Node2D = _arena.add_imp(Vector2(150, 0))
	_arena.install_cards(0, 0, ["penta", "frost", "nova"])
	check(_arena.cast(0, 0), "cast")
	_arena.run(1.0)
	check(_arena.was_given(imp, &"chill"), "five novas close over the imp in the middle")


func test_wasted_where_nothing_leaves_from_a_point() -> void:
	_arena = ArenaScript.new(root)
	for carrier: String in ["dash", "teleport", "swing", "slam"]:
		var built: CompiledStaff = _arena.install_cards(0, 0, ["penta", carrier])
		check(built.wasted.has(0), "penta does nothing on a %s" % carrier)
	for carrier: String in ["bolt", "beam", "nova", "rune", "wall", "rain", "orbit", "decoy", "familiar", "swap", "portal"]:
		var built: CompiledStaff = _arena.install_cards(0, 0, ["penta", carrier])
		check(not built.wasted.has(0), "penta works on a %s" % carrier)
