extends "res://tests/support/card_rig.gd"
## The Skyfall card (content/spells/modifiers/skyfall/; owner, 2026-11-09; docs/milestones/
## carrier-modifiers.md Part 2): a hole opens up the screen from where the cast comes from (over its
## caster, or over the point a trigger fired at), and the next carrier is cast from it straight down
## onto the floor line through that spot. Its shots touch nothing in the air, hit what stands close
## to the line (its caster too: the hole is a point, it spares no body) and end there; a placed
## carrier lands on the line. No card moves the hole: homing steers the carrier, reach lengthens it.
##
## godot --headless --path . --script res://content/spells/modifiers/skyfall/test_skyfall.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")

## Where the caster stands in these tests: the spot its casts fall onto.
const SPOT := Vector2(100.0, 100.0)
## Steps until a fall is surely over: the hole's wait and a bolt's drop.
const FALLEN: int = 75

var _holes: Array = []


func before_each() -> void:
	super()
	_holes.clear()
	_bus.cue_shown.connect(func(_caster: int, cue: StringName, at: Vector2, _direction: Vector2, _size: float, _tint: Color, _look: int) -> void:
		if cue == &"skyfall":
			_holes.append(at))


func _cast(modifiers: Array, form: StringName = &"bolt", player: int = 0) -> int:
	_mgr.set_anchor(player, SPOT)
	return _cast_with(form, modifiers, player, SPOT)


func test_the_card_is_a_skyfall_modifier() -> void:
	var card: ModifierBase = _check_card(&"skyfall", 2) as ModifierBase
	check(card != null, "skyfall is a modifier")
	if card == null:
		return
	check_equal(card.behaviour, ModifierBase.Behaviour.SKYFALL, "it falls")
	check_equal(card.cue, &"skyfall", "its hole is the skyfall cue")


func test_the_hole_opens_over_its_caster_and_the_bolt_falls_after() -> void:
	var target: Node2D = _target(SPOT)
	var tag: int = _cast([&"skyfall"])
	check_equal(_holes, [SPOT + Vector2.UP * SpellLimits.SKYFALL_HEIGHT], "the hole opens straight up the screen from the caster")
	check(_slots(tag).is_empty(), "nothing leaves the hand")
	check_equal(_spells.live_shots(tag), 1, "the waiting fall counts as one live shot, as an entity asked for does")
	_tick(roundi(SpellLimits.SKYFALL_SECONDS / DT) - 2)
	check(_hit_targets().is_empty(), "nothing is hit while the hole opens")
	_tick(FALLEN)
	check(_hit_targets().has(target), "then the bolt falls onto what stands there")


func test_only_what_stands_close_to_the_floor_is_hit() -> void:
	var in_column: Node2D = _target(SPOT + Vector2(0.0, -30.0), 8.0)
	var aside: Node2D = _target(SPOT + Vector2(60.0, 0.0))
	var at_spot: Node2D = _target(SPOT)
	_cast([&"skyfall"])
	_tick(FALLEN)
	var hit: Array = _hit_targets()
	check(hit.has(at_spot), "the target at the spot is hit")
	check(not hit.has(in_column), "one in the column, up in the air, is not")
	check(not hit.has(aside), "nor one off to the side")


func test_it_falls_over_a_wall_in_the_column() -> void:
	_mgr.set_walls([Rect2(SPOT.x - 20.0, SPOT.y - 44.0, 40.0, 8.0)] as Array[Rect2])
	var target: Node2D = _target(SPOT)
	_cast([&"skyfall"])
	_tick(FALLEN)
	check(_hit_targets().has(target), "the bolt passes over the wall in the air and lands")


func test_a_split_lands_side_by_side() -> void:
	var row: Array[Node2D] = [_target(SPOT + Vector2(-15.0, 0.0), 6.0), _target(SPOT, 6.0), _target(SPOT + Vector2(15.0, 0.0), 6.0)]
	_cast([&"skyfall", &"split"])
	_tick(FALLEN)
	for target in row:
		check(_hit_targets().has(target), "each bolt of the fan lands beside the others (%s)" % target.position)


func test_a_rune_is_placed_on_the_floor_line() -> void:
	var tag: int = _cast([&"skyfall"], &"rune")
	_tick(roundi(SpellLimits.SKYFALL_SECONDS / DT) + 2)
	var slots: Array[int] = _slots(tag)
	check_equal(slots.size(), 1, "one rune")
	if slots.size() == 1:
		check(absf(_mgr.get_position_of(slots[0]).y - SPOT.y) < 1.0, "on the caster's floor line (%s)" % _mgr.get_position_of(slots[0]))


func test_a_beam_is_a_pillar_that_strikes_at_its_foot() -> void:
	var in_column: Node2D = _target(SPOT + Vector2(0.0, -30.0), 8.0)
	var at_spot: Node2D = _target(SPOT)
	_cast([&"skyfall"], &"beam")
	_tick(FALLEN)
	var hit: Array = _hit_targets()
	check(hit.has(at_spot), "the beam strikes at the floor")
	check(not hit.has(in_column), "not up its length")
	var beams: CarrierBeam = CarrierBeam.of(_spells)
	for at in beams.beam_slots():
		if beams.beam_on(at):
			check(beams.beam_origin(at).distance_to(SPOT + Vector2.UP * SpellLimits.SKYFALL_HEIGHT) < 1.0, "it comes down from the hole")


func test_a_nova_opens_its_eight_holes_over_the_same_spot() -> void:
	_cast([&"nova", &"skyfall"])
	check_equal(_holes.size(), 8, "eight holes (owner: they stack, it is fine)")
	for hole: Vector2 in _holes:
		check(hole.is_equal_approx(SPOT + Vector2.UP * SpellLimits.SKYFALL_HEIGHT), "each over the caster")


func test_penta_ring_points_are_the_spots() -> void:
	_cast([&"penta", &"skyfall"])
	check_equal(_holes.size(), 5, "a hole over each point of the ring")
	for hole: Vector2 in _holes:
		var spot: Vector2 = hole + Vector2.DOWN * SpellLimits.SKYFALL_HEIGHT
		check(absf(spot.distance_to(SPOT) - SpellLimits.PENTA_RING) < 1.0, "each spot on the ring round the caster (%s)" % spot)


func test_homing_and_reach_do_not_move_the_hole() -> void:
	_target(SPOT + Vector2(60.0, 0.0))
	_cast([&"skyfall", &"homing", &"reach"])
	check_equal(_holes, [SPOT + Vector2.UP * SpellLimits.SKYFALL_HEIGHT], "still over the caster: homing steers the bolt, reach lengthens it")


func test_an_on_hit_fall_opens_over_the_hit_and_strikes_what_was_hit() -> void:
	var imp: Node2D = _target(SPOT + Vector2(100.0, 0.0))
	StaffKit.build(_spells, 0, 0, [&"on_hit", &"bolt", &"skyfall", &"bolt"] as Array[StringName])
	_mgr.set_anchor(0, SPOT)
	check(_spells.cast_staff(0, 0, SPOT, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "cast")
	_tick(30)
	check_equal(_hit_targets().count(imp), 1, "the bolt hit the imp")
	check_equal(_holes.size(), 1, "and a hole opened")
	if _holes.size() == 1:
		# The hit point is where the bolt met the imp's edge: its radius and the bolt's short of its middle.
		check(absf((_holes[0] as Vector2).x - imp.position.x) <= 16.0, "over where it hit (%s)" % _holes[0])
	_tick(FALLEN)
	check_equal(_hit_targets().count(imp), 2, "the fall strikes the imp it came from too: a point spares no body")


func test_a_payload_of_a_falling_shot_falls_too() -> void:
	# A piercing falling bolt flies on through the target under it, so it casts its `on hit`
	# payload itself: what an airborne shot casts falls to the same floor line (owner, 2026-11-09).
	_target(SPOT)
	StaffKit.build(_spells, 0, 0, [&"on_hit", &"skyfall", &"pierce", &"bolt", &"bolt"] as Array[StringName])
	_mgr.set_anchor(0, SPOT)
	check(_spells.cast_staff(0, 0, SPOT, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "cast")
	var payload: int = _spells.current_tag(0, 0, 1)
	var seen: bool = false
	for step in FALLEN:
		_tick(1)
		var slots: Array[int] = _slots(payload)
		if not slots.is_empty():
			seen = true
			for slot in slots:
				check(is_equal_approx(_mgr.get_floor_of(slot), SPOT.y), "the payload bolt falls onto the same floor line")
			break
	check(seen, "the hit cast its payload")


func test_an_echoed_fall_falls_again_at_half() -> void:
	# The rain's echo, kept for the fall that replaced it (carrier-modifiers.md Part 4).
	var target: Node2D = _target(SPOT)
	var damage: Array[float] = []
	_bus.projectile_hit.connect(func(_caster: int, hit: Node, _at: Vector2, tag: int, shot: int) -> void:
		if hit == target:
			damage.append(_spells.hit_profile(tag, shot).damage))
	_cast([&"skyfall", &"echo"])
	_tick(FALLEN * 3)
	check_equal(damage.size(), 2, "the fall and its echo strike")
	check(damage.size() == 2 and damage[1] < damage[0], "the echo at half: %s" % [damage])


func test_its_on_expire_fires_on_the_floor_line() -> void:
	# The rain's `on expire` as it landed, kept for the fall: the floor ends the bolt as the end of
	# its life does, so its payload is cast there.
	StaffKit.build(_spells, 0, 0, [&"on_expire", &"skyfall", &"bolt", &"bolt"] as Array[StringName])
	_mgr.set_anchor(0, SPOT)
	check(_spells.cast_staff(0, 0, SPOT, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "cast")
	var payload: int = _spells.current_tag(0, 0, 1)
	var at: Vector2 = Vector2.INF
	for step in FALLEN * 2:
		_tick(1)
		var slots: Array[int] = _slots(payload)
		if not slots.is_empty():
			at = _mgr.get_position_of(slots[0])
			break
	check(at.is_finite(), "the bolt's end cast its payload")
	check(at.is_finite() and absf(at.y - SPOT.y) < 8.0, "on the floor line, where it landed (%s)" % at)


func _beams_on() -> int:
	var on: int = 0
	var beams: CarrierBeam = CarrierBeam.of(_spells)
	for at in beams.beam_slots():
		if beams.beam_on(at):
			on += 1
	return on


func test_a_held_fall_holds_by_its_carriers_own_rule() -> void:
	# Hold works on the carrier, wherever it comes from (owner, 2026-11-09: no special case): a held
	# falling beam is a pillar until the staff is pressed again.
	StaffKit.build(_spells, 0, 0, [&"hold", &"skyfall", &"beam"] as Array[StringName])
	_mgr.set_anchor(0, SPOT)
	var mana: float = _spells.cast_staff(0, 0, SPOT, Vector2.RIGHT, 100.0)
	check(_spells.is_holding(0, 0), "the hold is on from the press, while the hole opens")
	check_equal(_spells.reserved_mana(0, 0), mana, "and keeps its cast's mana")
	_tick(FALLEN * 3)
	check_equal(_beams_on(), 1, "long after a beam's life the pillar still stands")
	check_equal(_holes.size(), 1, "one hole: it is held, not cast again")
	_spells.cast_staff(0, 0, SPOT, Vector2.RIGHT, 100.0)
	_tick(2)
	check(not _spells.is_holding(0, 0), "the next press switches it off")
	check_equal(_beams_on(), 0, "and the pillar goes")
	check_equal(_spells.reserved_mana(0, 0), 0.0, "its mana is free")


func test_a_press_while_the_hole_opens_calls_the_fall_off() -> void:
	var target: Node2D = _target(SPOT)
	StaffKit.build(_spells, 0, 0, [&"hold", &"skyfall", &"bolt"] as Array[StringName])
	_mgr.set_anchor(0, SPOT)
	var tag: int = _spells.current_tag(0, 0, 0)
	_spells.cast_staff(0, 0, SPOT, Vector2.RIGHT, 100.0)
	# A press switches a hold off once the staff is ready again (its wind-down, shorter than the wait).
	for step in 60:
		if _spells.cooldown_left(0, 0) <= 0.0:
			break
		_tick(1)
	check(_slots(tag).is_empty() and _spells.live_shots(tag) == 1, "the hole is still opening")
	check_equal(_spells.cast_staff(0, 0, SPOT, Vector2.RIGHT, 100.0), 0.0, "the press switches it off")
	check(not _spells.is_holding(0, 0), "switched off before it fell")
	check_equal(_spells.live_shots(tag), 0, "its wait no longer counts")
	_tick(FALLEN)
	check(not _hit_targets().has(target), "and nothing falls")


func test_a_held_bolt_falls_once_and_its_hold_ends_on_the_floor() -> void:
	# A held bolt's hold ends with its last shot; a falling bolt's ends at its floor line.
	StaffKit.build(_spells, 0, 0, [&"hold", &"skyfall", &"bolt"] as Array[StringName])
	_mgr.set_anchor(0, SPOT)
	var tag: int = _spells.current_tag(0, 0, 0)
	_spells.cast_staff(0, 0, SPOT, Vector2.RIGHT, 100.0)
	check(_spells.is_holding(0, 0), "held while it waits and falls")
	_tick(FALLEN * 2)
	check_equal(_holes.size(), 1, "it fell once")
	check_equal(_spells.live_shots(tag), 0, "it landed")
	check(not _spells.is_holding(0, 0), "and its hold ended with it")


func test_its_caster_is_hit_if_still_under_it() -> void:
	var arena := ArenaScript.new(root)
	var body: Node2D = arena.add_guard(0, Vector2.ZERO)
	arena.install_cards(0, 0, ["skyfall", "bolt"])
	check(arena.cast(0, 0), "cast")
	arena.run(1.5)
	check(arena.lost(body) > 0, "the wizard standing under the hole is hit by its own fall (owner: the general rule)")
	arena.free_all()


func test_wasted_on_what_never_leaves_the_body() -> void:
	for carrier: StringName in [&"swing", &"slam", &"dash", &"teleport"]:
		var staff: CompiledStaff = StaffKit.compile(_spells, [&"skyfall", carrier] as Array[StringName])
		check(staff != null and staff.wasted.has(0), "skyfall is wasted on %s" % carrier)
	var bolt: CompiledStaff = StaffKit.compile(_spells, [&"skyfall", &"bolt"] as Array[StringName])
	check(bolt != null and not bolt.wasted.has(0), "and counts on a bolt")
