extends "res://tests/support/card_rig.gd"
## The Nova card (content/spells/modifiers/nova/; owner, 2026-11-09: a modifier that makes a nova of
## any carrier, in place of the old nova carrier card): the next carrier is cast eight ways at once, from
## the same place, each copy aimed out round a circle and keeping its own shots and reach.
##
## godot --headless --path . --script res://content/spells/modifiers/nova/test_nova.gd

var _cues: Array = []


func before_each() -> void:
	super()
	_cues.clear()
	_bus.cue_shown.connect(func(caster: int, cue: StringName, at: Vector2, _direction: Vector2, _size: float, _tint: Color, _look: int) -> void: _cues.append([caster, cue, at]))


func _novas_shown() -> int:
	var count: int = 0
	for cue: Array in _cues:
		if cue[1] == &"nova":
			count += 1
	return count


func test_the_card_is_a_nova_modifier() -> void:
	var card: ModifierBase = _check_card(&"nova", 2) as ModifierBase
	check(card != null, "nova is a modifier")
	if card == null:
		return
	check_equal(card.behaviour, ModifierBase.Behaviour.NOVA, "it casts a nova")
	check_equal(card.behaviour_strength, 8.0, "eight ways")
	check_equal(card.cue, &"nova", "its ring is the nova cue")
	check(_card(&"nova") is ModifierBase, "no carrier card is called nova any more")


func test_it_works_for_all_four_players_at_once() -> void:
	_four_players_cast([&"nova", &"bolt"], false)
	for player in 4:
		check_equal(_spells.live_shots(_spells.current_tag(player, 0)), 8, "player %d has eight bolts" % player)


func test_a_nova_of_bolts_throws_a_ring_in_every_direction() -> void:
	var around: Array[Node2D] = []
	for n in 8:
		around.append(_target(Vector2.from_angle(TAU * n / 8.0) * 45.0))
	var tag: int = _cast_with(&"bolt", [&"nova"], 0, Vector2.ZERO)
	check_equal(_spells.live_shots(tag), 8, "eight bolts in the air")
	_tick(30)
	var hit: Array = _hit_targets()
	for n in 8:
		check(hit.has(around[n]), "the target at %d degrees was hit" % (45 * n))
	check_equal(hit.size(), 8, "each exactly once")


func test_the_first_copy_goes_along_the_aim() -> void:
	var ahead: Node2D = _target(Vector2(0.0, 60.0))
	_cast_with(&"bolt", [&"nova"], 0, Vector2.ZERO, Vector2.DOWN)
	_tick(20)
	check(_hit_targets().has(ahead), "the bolt aimed down hits the target below")


func test_each_copy_keeps_its_carriers_reach() -> void:
	var bolt: CarrierCard = _carrier_card(&"bolt")
	var far: float = bolt.speed * bolt.lifetime * 0.7
	var target: Node2D = _target(Vector2.from_angle(TAU * 3.0 / 8.0) * far)
	_cast_with(&"bolt", [&"nova"], 0, Vector2.ZERO)
	_tick(120)
	check(_hit_targets().has(target), "a bolt of the ring flies as far as a bolt (%.0f px)" % far)


func test_the_ring_shows_once_at_its_caster() -> void:
	_mgr.set_anchor(0, Vector2(40.0, 10.0))
	_cast_with(&"bolt", [&"nova"], 0, Vector2(40.0, 10.0))
	check_equal(_novas_shown(), 1, "one ring for the whole nova, not one per copy")
	_cues.clear()
	_cast_with(&"bolt", [], 1, Vector2.ZERO)
	check_equal(_novas_shown(), 0, "a plain bolt shows none")


func test_a_split_nova_is_eight_fans() -> void:
	var tag: int = _cast_with(&"bolt", [&"split", &"nova"], 0, Vector2.ZERO)
	check_equal(_spells.live_shots(tag), 24, "eight fans of three")


func test_two_cards_add_their_ways() -> void:
	var spell: CompiledSpell = _compile_with(&"bolt", [&"nova", &"nova"])
	check_equal(spell.nova_ways(), 16, "two cards, sixteen ways")
	var tag: int = _cast_with(&"bolt", [&"nova", &"nova"], 0, Vector2.ZERO)
	check_equal(_spells.live_shots(tag), 16, "sixteen bolts")


func test_a_nova_of_runes_lays_a_ring_of_runes() -> void:
	var tag: int = _cast_with(&"rune", [&"nova"], 0, Vector2.ZERO)
	var slots: Array[int] = _slots(tag)
	check_equal(slots.size(), 8, "eight runes")
	var angles: Array[int] = []
	for slot in slots:
		var at: Vector2 = _mgr.get_position_of(slot)
		check(at.length() > 4.0, "each rune a step out (%s)" % at)
		angles.append(posmod(roundi(rad_to_deg(at.angle()) / 45.0), 8))
	angles.sort()
	check_equal(angles, [0, 1, 2, 3, 4, 5, 6, 7], "one rune each way round")


func test_its_numbers() -> void:
	var plain: CompiledSpell = _compile_with(&"bolt", [])
	var nova: CompiledSpell = _compile_with(&"bolt", [&"nova"])
	check_equal(nova.shots, plain.shots, "the shots of one copy are the carrier's own")
	check(nova.hit.damage < plain.hit.damage, "each copy hits a little softer")
	check(nova.wind_down > plain.wind_down, "and the staff rests longer after it")
	check(_spells.copies_of(nova) == 8, "the fire budget counts eight copies")


## Penta in a nova: each copy's ring is turned by its share of the turn, so the eight rings of five
## spread to forty points instead of standing on the same five.
func test_a_nova_of_penta_rings_spreads_them_out() -> void:
	var tag: int = _cast_with(&"bolt", [&"nova", &"penta"], 0, Vector2.ZERO)
	var slots: Array[int] = _slots(tag)
	check_equal(slots.size(), 40, "eight rings of five bolts")
	var spots: Dictionary = {}
	for slot in slots:
		spots[_mgr.get_position_of(slot).round()] = true
	check_equal(spots.size(), 40, "on forty points, none stacked")


## A nova of dashes (owner, 2026-11-09: as Mirror's): eight moves round a circle add up to none.
func test_a_nova_of_dashes_moves_nowhere() -> void:
	var moves: Array[Vector2] = []
	_bus.caster_move_requested.connect(func(_body: int, _mode: StringName, by: Vector2, _seconds: float, _tag: int) -> void: moves.append(by))
	_mgr.set_anchor(0, Vector2.ZERO)
	_cast_with(&"dash", [&"nova"], 0, Vector2.ZERO)
	check_equal(moves.size(), 8, "eight dashes")
	var sum := Vector2.ZERO
	for by in moves:
		sum += by
	check(sum.length() < 0.5, "that cancel out: %s" % sum)


## No cap on the ways (owner, 2026-10-29: a card's interactions are not limited): four cards are 32.
func test_more_cards_keep_adding_ways() -> void:
	var spell: CompiledSpell = _compile_with(&"bolt", [&"nova", &"nova", &"nova", &"nova"])
	check_equal(spell.nova_ways(), 32, "four cards, thirty-two ways")
	var tag: int = _cast_with(&"bolt", [&"nova", &"nova", &"nova", &"nova"], 0, Vector2.ZERO)
	check_equal(_spells.live_shots(tag), 32, "thirty-two bolts")
