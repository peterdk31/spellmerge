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
	check_equal(_spells.live_shots(tag), 0, "nothing leaves the hand")
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
