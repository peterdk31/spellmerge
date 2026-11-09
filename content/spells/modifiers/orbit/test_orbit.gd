extends "res://tests/support/card_rig.gd"
## The Orbit card (content/spells/modifiers/orbit/; owner, 2026-11-09; docs/milestones/
## carrier-modifiers.md Part 5): the next carrier circles its caster instead of going out. It changes
## only how the carrier moves: one of whatever it carries, starting the way it would have gone, at
## the card's radius, turning by the card's drift plus the carrier's own speed over the radius, for
## the card's 3 s (`lifetime_base`, which Slow and Reach still stretch). No special rules: room walls
## end a circling shot (ghost passes), the AI sees it, homing does nothing on it. A beam sweeps.
##
## godot --headless --path . --script res://content/spells/modifiers/orbit/test_orbit.gd

## Where the caster stands in these tests.
const AT := Vector2(200.0, 200.0)


func _orbit() -> ModifierBase:
	return _modifier(&"orbit")


## Where `player` stands: each its own place, far apart.
func _at(player: int) -> Vector2:
	return AT + Vector2(0.0, 400.0 * player)


## Every player's anchor, for `_tick`.
func _all() -> Dictionary:
	return {0: _at(0), 1: _at(1), 2: _at(2), 3: _at(3)}


func _cast(modifiers: Array, form: StringName = &"bolt", direction: Vector2 = Vector2.RIGHT, player: int = 0) -> int:
	_mgr.set_anchor(player, _at(player))
	return _cast_with(form, modifiers, player, _at(player), direction)


## The way round its caster's place `centre` the shot in `slot` is (radians).
func _angle_of(slot: int, centre: Vector2 = AT) -> float:
	return DMath.angle(_mgr.get_position_of(slot) - centre)


## Radians the first shot of each of `tags` (player n's the n-th) turns over `steps` steps, summed
## step by step so a fast one is not wrapped away.
func _turned(tags: Array[int], steps: int) -> Array[float]:
	var slots: Array[int] = []
	var last: Array[float] = []
	var total: Array[float] = []
	for n in tags.size():
		slots.append(_slots(tags[n])[0])
		last.append(_angle_of(slots[n], _at(n)))
		total.append(0.0)
	for step in steps:
		_tick(1, _all())
		for n in tags.size():
			var now: float = _angle_of(slots[n], _at(n))
			total[n] += wrapf(now - last[n], -PI, PI)
			last[n] = now
	return total


func test_the_card_is_an_orbit_modifier() -> void:
	var card: ModifierBase = _check_card(&"orbit", 2) as ModifierBase
	check(card != null, "orbit is a modifier")
	if card == null:
		return
	check_equal(card.behaviour, ModifierBase.Behaviour.ORBIT, "it circles")
	check_equal(card.behaviour_reach, 36.0, "a 36 px circle")
	check(is_equal_approx(card.behaviour_strength, 1.0 / 3.0), "a drift of a third of a turn a second")
	check_equal(card.lifetime_base, 3.0, "it circles for 3 s, through the general field")
	check_equal(card.extra_pierce, 0, "no pierce of its own")
	check_equal(card.shot_mult, 1, "no count of its own")
	check_equal(card.cue, &"orbit", "its cue is the ring of motes")


func test_it_works_for_all_four_players_at_once() -> void:
	_four_players_cast([&"orbit", &"bolt"], false)
	for player in 4:
		check(_mgr.get_count_for(player) > 0, "player %d has a circling shot" % player)


func test_one_bolt_circles_its_caster_from_the_aim() -> void:
	var tag: int = _cast([&"orbit"], &"bolt", Vector2.DOWN)
	var slots: Array[int] = _slots(tag)
	check_equal(slots.size(), 1, "one of what it carries")
	if slots.is_empty():
		return
	var start: Vector2 = _mgr.get_position_of(slots[0])
	check(start.is_equal_approx(AT + Vector2.DOWN * 36.0), "it starts on the circle the way it would have gone (%s)" % start)
	_tick(30, {0: AT})
	check(absf(_mgr.get_position_of(slots[0]).distance_to(AT) - 36.0) < 0.01, "it stays on the circle")
	check(not _mgr.get_position_of(slots[0]).is_equal_approx(start), "and turns")
	_tick(30, {0: AT + Vector2(80.0, 0.0)})
	check(absf(_mgr.get_position_of(slots[0]).distance_to(AT + Vector2(80.0, 0.0)) - 36.0) < 0.01, "it follows its caster")


func test_it_turns_by_its_drift_plus_its_speed() -> void:
	var bolt: CompiledSpell = _compile_with(&"bolt", [&"orbit"])
	var atom: CompiledSpell = _compile_with(&"atom", [&"orbit"])
	check(atom.speed > bolt.speed, "an atom is faster than a bolt")
	var tags: Array[int] = [_cast([&"orbit"], &"bolt", Vector2.RIGHT, 0), _cast([&"orbit"], &"atom", Vector2.RIGHT, 1), _cast([&"orbit", &"slow"], &"bolt", Vector2.RIGHT, 2)]
	var turned: Array[float] = _turned(tags, 30)
	var bolt_turn: float = turned[0]
	var atom_turn: float = turned[1]
	var slow_turn: float = turned[2]
	check(bolt_turn > 0.0, "a bolt goes round (%.2f rad)" % bolt_turn)
	check(atom_turn > bolt_turn, "an atom outturns a bolt (%.2f > %.2f rad)" % [atom_turn, bolt_turn])
	check(slow_turn < bolt_turn, "slow turns it slower (%.2f < %.2f rad)" % [slow_turn, bolt_turn])


func test_it_lasts_the_cards_time_and_slow_or_reach_stretch_it() -> void:
	check(is_equal_approx(_compile_with(&"bolt", [&"orbit"]).lifetime, 3.0), "a bolt circles for 3 s")
	check(is_equal_approx(_compile_with(&"beam", [&"orbit"]).lifetime, 3.0), "and a beam sweeps for 3 s, whatever its own life")
	var slowed: float = _compile_with(&"bolt", [&"orbit", &"slow"]).lifetime
	check(is_equal_approx(slowed, _compile_with(&"bolt", [&"slow", &"orbit"]).lifetime), "in any order")
	check(slowed > 3.0, "slow stretches it (%.2f s)" % slowed)
	check(_compile_with(&"bolt", [&"reach", &"orbit"]).lifetime > 3.0, "reach on a flying shot stretches it too")
	var tag: int = _cast([&"orbit"])
	_tick(ceili(3.0 / DT) + 4, {0: AT})
	check_equal(_slots(tag).size(), 0, "it ends after its time")
	check_equal(_spells.live_shots(tag), 0, "and counts as ended")


func test_split_circles_as_a_cluster_and_nova_as_a_ring() -> void:
	var cluster: int = _cast([&"orbit", &"split"])
	var slots: Array[int] = _slots(cluster)
	check(slots.size() > 1, "split makes more of it (%d)" % slots.size())
	for slot in slots:
		check(absf(_mgr.get_position_of(slot).distance_to(AT) - 36.0) < 0.01, "each on the circle")
	var ring: int = _cast([&"orbit", &"nova"], &"bolt", Vector2.RIGHT, 1)
	var angles: Array[float] = []
	for slot in _slots(ring):
		angles.append(_angle_of(slot, _at(1)))
	check_equal(angles.size(), 8, "a nova of it is eight")
	angles.sort()
	for n in range(1, angles.size()):
		check(absf(angles[n] - angles[n - 1] - TAU / 8.0) < 0.01, "spread evenly round (%.3f)" % (angles[n] - angles[n - 1]))


func test_it_hits_what_it_passes_again_each_time_round() -> void:
	var imp: Node2D = _target(AT + Vector2(0.0, 36.0), 6.0)
	_cast([&"orbit", &"pierce", &"pierce"])
	_tick(170, {0: AT})
	var times: int = 0
	for hit: Array in _hits:
		if hit[1] == imp:
			times += 1
	check(times >= 2, "an imp on the circle is hit each time round (%d)" % times)


func test_a_room_wall_ends_it_and_ghost_passes() -> void:
	# A wall across each caster's circle, below it.
	var walls: Array[Rect2] = []
	for player in 2:
		walls.append(Rect2(_at(player).x - 6.0, _at(player).y + 20.0, 12.0, 40.0))
	_mgr.set_walls(walls)
	var plain: int = _cast([&"orbit"], &"bolt", Vector2.RIGHT, 0)
	var ghost: int = _cast([&"orbit", &"ghost"], &"bolt", Vector2.RIGHT, 1)
	_tick(90, _all())
	check_equal(_slots(plain).size(), 0, "a wall across its circle ends it, as any shot")
	check_equal(_slots(ghost).size(), 1, "a ghost one passes through")


## Bounce follows its own rule on a circler (owner, 2026-11-09: "Build it"): at the wall across its
## circle it turns back round the way it came, so it swings to and fro on the open arc, never in the
## wall, until its bounces are spent; then the wall ends it, as it ends a plain one at once.
func test_bounce_swings_it_to_and_fro_on_the_open_arc() -> void:
	var walls: Array[Rect2] = []
	for player in 2:
		walls.append(Rect2(_at(player).x - 6.0, _at(player).y + 20.0, 12.0, 40.0))
	_mgr.set_walls(walls)
	var plain: int = _cast([&"orbit"], &"bolt", Vector2.RIGHT, 0)
	var bouncing: int = _cast([&"orbit", &"bounce"], &"bolt", Vector2.RIGHT, 1)
	var wall: Rect2 = walls[1]
	var lived: int = 0
	var inside: bool = false
	var way_changed: bool = false
	var last_way: float = 0.0
	for step in 120:
		_tick(1, _all())
		var slots: Array[int] = _slots(bouncing)
		if slots.is_empty():
			break
		lived = step + 1
		var at: Vector2 = _mgr.get_position_of(slots[0])
		inside = inside or wall.has_point(at)
		var way: float = signf((at - _at(1)).cross(_mgr.get_velocity_of(slots[0])))
		way_changed = way_changed or (last_way != 0.0 and way != last_way)
		last_way = way
	check_equal(_slots(plain).size(), 0, "a plain one ends on the wall")
	check(lived > 30, "a bouncing one lives on past the wall (%d steps)" % lived)
	check(way_changed, "it turned back round its circle")
	check(not inside, "never inside the wall")
	_tick(240, _all())
	check_equal(_slots(bouncing).size(), 0, "its bounces spent, the wall ends it too")


func test_the_ai_sees_a_circling_shot() -> void:
	# It starts below its caster going round to the left: the AI reads it along that tangent, as any shot.
	_cast([&"orbit"], &"bolt", Vector2.DOWN)
	var seen: float = _mgr.threat(AT + Vector2(-20.0, 36.0), 8.0, ActorSeats.ActorsScript.NONE, -1, 2.0)
	check(seen >= 0.0, "a point ahead of it on its tangent is threatened (%.2f s)" % seen)


func test_homing_does_nothing_on_it() -> void:
	check_equal(_compile_with(&"bolt", [&"orbit", &"homing"]).homing_range, 0.0, "a circling carrier has no heading to steer")
	check(_compile_with(&"bolt", [&"homing"]).homing_range > 0.0, "a bolt alone homes")


func test_a_beam_sweeps_round_its_caster() -> void:
	_cast([&"orbit"], &"beam")
	var beams: CarrierBeam = CarrierBeam.of(_spells)
	check_equal(beams.beam_count(), 1, "one beam")
	var first: Vector2 = (beams.beam_end(0) - beams.beam_origin(0)).normalized()
	_tick(60, {0: AT})
	check_equal(beams.beam_count(), 1, "still on after a second (it lasts the card's 3 s)")
	var later: Vector2 = (beams.beam_end(0) - beams.beam_origin(0)).normalized()
	var swept: float = absf(DMath.angle_to(first, later))
	check(absf(swept - TAU / 3.0) < 0.1, "it swept a third of a turn in a second (%.2f rad)" % swept)


func test_wasted_on_what_never_leaves_the_body() -> void:
	for form: StringName in [&"dash", &"teleport", &"swing", &"slam", &"decoy", &"familiar", &"portal"]:
		check(not Carriers.of(form).works(ModifierBase.Behaviour.ORBIT), "nothing of a %s circles" % form)
	for form: StringName in [&"bolt", &"atom", &"swap", &"beam"]:
		check(Carriers.of(_form(form).carrier).works(ModifierBase.Behaviour.ORBIT), "a %s circles" % form)


func test_its_cue_is_shown_round_the_caster() -> void:
	var shown: Array = []
	_bus.cue_shown.connect(func(_caster: int, cue: StringName, at: Vector2, _direction: Vector2, size: float, _tint: Color, _look: int) -> void:
		if cue == &"orbit":
			shown.append([at, size]))
	_cast([&"orbit"])
	check_equal(shown, [[AT, 36.0]], "once, at the caster, as big as the circle")
	check(ResourceLoader.exists("res://content/cues/orbit.tres"), "its cue is a file")
