extends "res://tests/support/suite.gd"
## Penta (ModifierBase.Behaviour.PENTA; docs/milestones/portal.md, "Penta"): the carrier cast five
## times from a ring round its caster (the wizard, or the point or shot casting a payload), all
## aimed in at it; it reads no other card (homing steers each copy, as anywhere); more cards add
## copies; wasted where nothing leaves from a point (a dash, a swing).
##
## godot --headless --path . --script res://content/spells/modifiers/penta/test_penta.gd

const SpellsScript := preload("res://core/spells/spells.gd")
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


## The ring turns (owner, 2026-11-06: "rotate continuously"): casts in a row stand where it has
## turned to, SpellLimits.PENTA_TURN a second, not at a new random angle; the same on every run.
func test_casts_in_a_row_stand_where_the_ring_has_turned_to() -> void:
	var first: Array[float] = _ring_turns()
	check_equal(first.size(), 2, "two casts")
	var gap: float = fposmod(first[1] - first[0], TAU / 5.0)
	var want: float = fposmod(SpellLimits.PENTA_TURN * 1.5, TAU / 5.0)
	check(absf(gap - want) < 0.02, "the second stands 1.5 s of turning on (%s, want %s)" % [gap, want])
	check_equal(_ring_turns(), first, "and the same casts stand the same")


## Where the ring of each of two casts 1.5 s apart stood: the least angle of its bolts, within a
## fifth of a turn (the ring looks the same turned by a fifth).
func _ring_turns() -> Array[float]:
	_arena = ArenaScript.new(root)
	_arena.install_cards(0, 0, ["penta", "bolt"])
	var out: Array[float] = []
	for n in 2:
		_arena.cast(0, 0)
		var least: float = TAU
		for slot in _shots():
			if _arena.projectiles.get_position_of(slot).length() > SpellLimits.PENTA_RING - 1.0:
				least = minf(least, fposmod(_arena.projectiles.get_position_of(slot).angle(), TAU / 5.0))
		out.append(snappedf(least, 0.001))
		_arena.run(1.5)
	_arena.free_all()
	_arena = null
	return out


## A copy that stays on its point turns with the ring while it lasts: held beams sweep round
## their centre, still on the ring and aimed in.
func test_held_beams_turn_with_the_ring_and_stay_aimed_in() -> void:
	_arena = ArenaScript.new(root)
	_arena.install_cards(0, 0, ["hold", "penta", "beam"])
	check(_arena.cast(0, 0), "cast")
	var beams: CarrierBeam = CarrierBeam.of(_arena.spells)
	_arena.run(1.0 / 60.0)
	var before: Array[Vector2] = _beam_origins(beams)
	_arena.run(0.25)
	var after: Array[Vector2] = _beam_origins(beams)
	check_equal(after.size(), 5, "five held beams")
	for n in after.size():
		check(is_equal_approx(after[n].length(), SpellLimits.PENTA_RING), "each still on the ring (%s)" % after[n])
		var turned: float = before[n].angle_to(after[n])
		check(absf(turned - SpellLimits.PENTA_TURN * 0.25) < 0.05, "and turned with it (%s)" % turned)
	for at in beams.beam_slots():
		if beams.beam_on(at) and beams.beam_point_count(at) >= 2:
			var origin: Vector2 = beams.beam_origin(at)
			var way: Vector2 = origin.direction_to(beams.beam_point(at, 1))
			check(way.dot(-origin.normalized()) > 0.99, "aimed in at the centre (%s)" % way)


## Each cast turns the other way from the one before (owner, 2026-11-06): beams of one cast turn
## one way, the next cast's the other, and the one after that the first way again.
func test_each_cast_turns_the_other_way_from_the_one_before() -> void:
	_arena = ArenaScript.new(root)
	_arena.install_cards(0, 0, ["penta", "beam"])
	var beams: CarrierBeam = CarrierBeam.of(_arena.spells)
	var ways: Array[float] = []
	for n in 3:
		check(_arena.cast(0, 0), "cast %d" % n)
		_arena.run(1.0 / 60.0)
		var before: Array[Vector2] = _beam_origins(beams)
		_arena.run(0.1)
		var after: Array[Vector2] = _beam_origins(beams)
		check_equal(after.size(), 5, "five beams on cast %d" % n)
		ways.append(signf(before[0].angle_to(after[0])) if not after.is_empty() else 0.0)
		_arena.run(1.0)
	check_equal(ways, [1.0, -1.0, 1.0] as Array[float], "back and forth")


## Mirror is the same cast again with its aim reversed (owner, 2026-11-06), so a Penta's mirror is
## a second ring, and, as the next cast, it turns the other way: ten held beams, five turning each
## way, all on the ring round the caster.
func test_mirror_casts_a_second_ring_turning_the_other_way() -> void:
	_arena = ArenaScript.new(root)
	_arena.install_cards(0, 0, ["mirror", "hold", "penta", "beam"])
	check(_arena.cast(0, 0), "cast")
	var beams: CarrierBeam = CarrierBeam.of(_arena.spells)
	_arena.run(1.0 / 60.0)
	var before: Array[Vector2] = _beam_origins(beams)
	_arena.run(0.25)
	var after: Array[Vector2] = _beam_origins(beams)
	check_equal(after.size(), 10, "two rings of five")
	var forward: int = 0
	var back: int = 0
	for n in after.size():
		check(is_equal_approx(after[n].length(), SpellLimits.PENTA_RING), "each on the ring (%s)" % after[n])
		var turned: float = before[n].angle_to(after[n])
		if absf(turned - SpellLimits.PENTA_TURN * 0.25) < 0.05:
			forward += 1
		elif absf(turned + SpellLimits.PENTA_TURN * 0.25) < 0.05:
			back += 1
	check_equal(forward, 5, "five turn one way")
	check_equal(back, 5, "and five the other")


func _beam_origins(beams: CarrierBeam) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for at in beams.beam_slots():
		if beams.beam_on(at):
			out.append(beams.beam_origin(at))
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


## No cap on the copies (owner, 2026-11-09: cards are not limited; it was 24): six cards cast thirty.
func test_more_cards_keep_adding_copies() -> void:
	_arena = ArenaScript.new(root)
	var staff: CompiledStaff = _arena.install_cards(0, 0, ["penta", "penta", "penta", "penta", "penta", "penta", "bolt"])
	check_equal(_arena.spells.copies_of(staff.casts[0].group.spells[0]), 30, "the fire budget counts thirty")
	check(_arena.spells.cast_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, 100000.0) != SpellsScript.REFUSED, "cast with mana to spare")
	check_equal(_shots().size(), 30, "thirty bolts")


func test_a_short_carrier_rings_within_its_reach() -> void:
	_arena = ArenaScript.new(root)
	var imp: Node2D = _arena.add_imp(Vector2(150, 0))
	_arena.install_cards(0, 0, ["on_hit", "bolt", "penta", "frost", "nova", "bolt"])
	check(_arena.cast(0, 0), "cast")
	_arena.run(1.5)
	check(_arena.was_given(imp, &"chill"), "five novas round the hit close over the imp in the middle")


func test_wasted_where_nothing_leaves_from_a_point() -> void:
	_arena = ArenaScript.new(root)
	for carrier: String in ["dash", "teleport", "swing", "slam"]:
		var built: CompiledStaff = _arena.install_cards(0, 0, ["penta", carrier])
		check(built.wasted.has(0), "penta does nothing on a %s" % carrier)
	for carrier: String in ["bolt", "beam", "rune", "wall", "rain", "orbit", "decoy", "familiar", "swap", "portal"]:
		var built: CompiledStaff = _arena.install_cards(0, 0, ["penta", carrier])
		check(not built.wasted.has(0), "penta works on a %s" % carrier)
