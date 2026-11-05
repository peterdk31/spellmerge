extends "res://tests/support/suite.gd"
## Penta (ModifierBase.Behaviour.PENTA; docs/milestones/portal.md, "Penta"): the carrier cast five
## times from a ring round its caster (the wizard, or the point or shot casting a payload), all
## aimed in at it; it reads no other card (homing steers each copy, as anywhere); more cards add
## copies; wasted where nothing leaves from a point (a dash, a swing).
##
## godot --headless --path . --script res://content/spells/modifiers/penta/test_penta.gd

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


## Homing does not move the ring (owner, 2026-11-05: Penta reads no other card): the bolts
## still start round the caster, aimed in, and each homes on its own afterwards.
func test_homing_does_not_move_the_ring_it_steers_each_copy() -> void:
	_arena = ArenaScript.new(root)
	var imp: Node2D = _arena.add_imp(Vector2(150, 30))
	_arena.install_cards(0, 0, ["homing", "penta", "bolt"])
	check(_arena.cast(0, 0), "cast")
	var shots: Array[int] = _shots()
	check_equal(shots.size(), 5, "five bolts")
	for slot in shots:
		var at: Vector2 = _arena.projectiles.get_position_of(slot)
		check(is_equal_approx(at.length(), SpellLimits.PENTA_RING), "each starts on the ring round the caster (%s)" % at)
		check(_arena.projectiles.get_velocity_of(slot).normalized().dot(-at.normalized()) > 0.99, "and leaves aimed in at it")
	_arena.run(1.5)
	check(_arena.lost(imp) > 0, "then they home on the imp")


## A payload's caster is the point it fires from (owner, 2026-11-05): `on hit · bolt · penta ·
## fire · beam` rings where the bolt hit, five beams burning in at the imp it hit.
func test_a_payload_rings_where_its_bolt_hit() -> void:
	_arena = ArenaScript.new(root)
	var imp: Node2D = _arena.add_imp(Vector2(150, 0))
	_arena.install_cards(0, 0, ["on_hit", "bolt", "penta", "fire", "beam"])
	check(_arena.cast(0, 0), "cast")
	var beams: CarrierBeam = CarrierBeam.of(_arena.spells)
	var seen: int = 0
	for _n in 60:
		_arena.run(1.0 / 60.0)
		if beams.beam_count() > 0:
			break
	check_equal(beams.beam_count(), 5, "the hit opens five beams")
	for at in beams.beam_slots():
		if not beams.beam_on(at):
			continue
		seen += 1
		var from_imp: float = beams.beam_origin(at).distance_to(imp.global_position)
		check(absf(from_imp - SpellLimits.PENTA_RING) < 20.0, "each on a ring round the hit (%s px from the imp)" % from_imp)
	check_equal(seen, 5, "five live beams")
	_arena.run(0.3)
	check(_arena.was_given(imp, &"burn"), "burning in at the imp")


## A held payload holds (M2-rules R1f), Penta's five copies too: the ring of beams round the hit
## stays on while the staff is held, and the next press switches all five off.
func test_a_held_payload_ring_stays_until_the_next_press() -> void:
	_arena = ArenaScript.new(root)
	_arena.add_imp(Vector2(150, 0), 100000)
	_arena.install_cards(0, 0, ["on_hit", "bolt", "hold", "penta", "beam"])
	check(_arena.cast(0, 0), "cast")
	var beams: CarrierBeam = CarrierBeam.of(_arena.spells)
	_arena.run(2.0)
	check_equal(_live_beams(beams), 5, "five beams outlive a beam's life")
	check(_arena.spells.is_holding(0, 0), "and hold the staff")
	check(_arena.cast(0, 0), "the next press is taken")
	_arena.run(0.5)
	check_equal(_live_beams(beams), 0, "and switches them all off")


func _live_beams(beams: CarrierBeam) -> int:
	var out: int = 0
	for at in beams.beam_slots():
		if beams.beam_on(at):
			out += 1
	return out


## Without homing the point is the caster (owner, 2026-11-05): the copies stand round it and aim in
## at it, even though that hurts it.
func test_without_homing_it_rings_its_caster_aimed_in() -> void:
	_arena = ArenaScript.new(root)
	_arena.add_imp(Vector2(150, 0))
	_arena.install_cards(0, 0, ["penta", "bolt"])
	check(_arena.cast(0, 0), "cast")
	var shots: Array[int] = _shots()
	check_equal(shots.size(), 5, "five bolts")
	var angles: Array[float] = []
	for slot in shots:
		var at: Vector2 = _arena.projectiles.get_position_of(slot)
		check(is_equal_approx(at.length(), SpellLimits.PENTA_RING), "each starts on the ring round the caster (%s)" % at)
		check(_arena.projectiles.get_velocity_of(slot).normalized().dot(-at.normalized()) > 0.99, "and flies in at it")
		angles.append(fposmod(at.angle(), TAU))
	angles.sort()
	for n in angles.size():
		var gap: float = fposmod((angles[(n + 1) % angles.size()] - angles[n]), TAU)
		check(is_equal_approx(gap, TAU / 5.0), "evenly round it (%s)" % gap)


## The ring is turned at random each cast (owner, 2026-11-05), by the cast's seeded generator: two
## casts in a row stand differently, and the same casts again stand the same.
func test_the_ring_turns_at_random_each_cast_the_same_every_run() -> void:
	var first: Array[Vector2] = _two_rings()
	var again: Array[Vector2] = _two_rings()
	check(not first[0].is_equal_approx(first[1]), "two casts in a row turn differently (%s, %s)" % [first[0], first[1]])
	check_equal(again, first, "and the same casts turn the same")


## Where the first bolt of each of two casts stood.
func _two_rings() -> Array[Vector2]:
	_arena = ArenaScript.new(root)
	_arena.install_cards(0, 0, ["penta", "bolt"])
	var out: Array[Vector2] = []
	for n in 2:
		_arena.cast(0, 0)
		var shots: Array[int] = _shots()
		out.append(_arena.projectiles.get_position_of(shots[shots.size() - 1]).round())
		_arena.run(1.5)
	_arena.free_all()
	_arena = null
	return out


func test_beams_stay_where_their_points_are() -> void:
	_arena = ArenaScript.new(root)
	_arena.install_cards(0, 0, ["penta", "beam"])
	check(_arena.cast(0, 0), "cast")
	var beams: CarrierBeam = CarrierBeam.of(_arena.spells)
	check_equal(beams.beam_count(), 5, "five beams")
	_arena.run(0.1)
	for at in beams.beam_slots():
		if beams.beam_on(at):
			check(is_equal_approx(beams.beam_origin(at).length(), SpellLimits.PENTA_RING), "each stays on the ring, cast by its point")


func test_two_cards_cast_ten() -> void:
	_arena = ArenaScript.new(root)
	_arena.add_imp(Vector2(150, 0))
	_arena.install_cards(0, 0, ["penta", "penta", "bolt"])
	check(_arena.cast(0, 0), "cast")
	check_equal(_shots().size(), 10, "ten bolts")


func test_a_short_carrier_rings_within_its_reach() -> void:
	_arena = ArenaScript.new(root)
	var imp: Node2D = _arena.add_imp(Vector2(150, 0))
	_arena.install_cards(0, 0, ["on_hit", "bolt", "penta", "frost", "nova"])
	check(_arena.cast(0, 0), "cast")
	_arena.run(1.5)
	check(_arena.was_given(imp, &"chill"), "five novas round the hit close over the imp in the middle")


func test_wasted_where_nothing_leaves_from_a_point() -> void:
	_arena = ArenaScript.new(root)
	for carrier: String in ["dash", "teleport", "swing", "slam"]:
		var built: CompiledStaff = _arena.install_cards(0, 0, ["penta", carrier])
		check(built.wasted.has(0), "penta does nothing on a %s" % carrier)
	for carrier: String in ["bolt", "beam", "nova", "rune", "wall", "rain", "orbit", "decoy", "familiar", "swap", "portal"]:
		var built: CompiledStaff = _arena.install_cards(0, 0, ["penta", carrier])
		check(not built.wasted.has(0), "penta works on a %s" % carrier)
