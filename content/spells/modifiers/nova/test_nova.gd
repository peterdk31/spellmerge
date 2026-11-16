extends "res://tests/support/card_rig.gd"
## The Nova card (content/spells/modifiers/nova/; owner, 2026-11-09: a modifier that makes a nova of
## any carrier, in place of the old nova carrier card): the next carrier is cast eight ways at once, from
## the same place, each copy aimed out round a circle and keeping its own shots and reach. The circle
## turns on with every cast (owner, 2026-11-16), its first along the aim.
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


## The angles off `aim`, in eighths of a turn (from -0.5 up to 7.5), that the bolts of `tag` not in
## `before` fly at.
func _ways_of(tag: int, aim: Vector2, before: Array[int] = []) -> Array[float]:
	var out: Array[float] = []
	for slot in _slots(tag):
		if not before.has(slot):
			out.append(fposmod(aim.angle_to(_mgr.get_velocity_of(slot)) / (TAU / 8.0) + 0.5, 8.0) - 0.5)
	out.sort()
	return out


## The first cast's first copy goes along the aim (owner, 2026-11-09).
func test_the_first_copy_goes_along_the_aim() -> void:
	var ahead: Node2D = _target(Vector2(0.0, 60.0))
	var tag: int = _cast_with(&"bolt", [&"nova"], 0, Vector2.ZERO, Vector2.DOWN)
	var ways: Array[float] = _ways_of(tag, Vector2.DOWN)
	check_equal(ways.size(), 8, "eight bolts")
	for n in ways.size():
		check(absf(ways[n] - n) < 0.01, "bolt %d flies %.2f eighths off the aim" % [n, ways[n]])
	_tick(20)
	check(_hit_targets().has(ahead), "the bolt aimed down hits the target below")


## Each cast of the card turns on from the last (owner, 2026-11-16: "one of the nova projectiles
## always fire right back at the staff direction, hitting the wizard. Can the nova rotate for each
## cast?") by SpellLimits.RING_STEP of a gap, so casts in a row never stand the same.
func test_each_cast_turns_on_from_the_last() -> void:
	var tag: int = _cast_with(&"bolt", [&"nova"], 0, Vector2.ZERO)
	var turns: Array[float] = [_ways_of(tag, Vector2.RIGHT)[0]]
	for n in 4:
		_tick(150)
		var before: Array[int] = _slots(tag)
		check(_spells.cast_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "cast %d of the same staff" % (n + 1))
		var ways: Array[float] = _ways_of(tag, Vector2.RIGHT, before)
		check_equal(ways.size(), 8, "eight bolts on cast %d" % (n + 1))
		if ways.is_empty():
			return
		for k in ways.size():
			check(absf(ways[k] - k - ways[0]) < 0.01, "evenly round on cast %d" % (n + 1))
		turns.append(ways[0])
	for n in range(1, turns.size()):
		var step: float = fposmod(turns[n] - turns[n - 1], 1.0)
		check(absf(step - SpellLimits.RING_STEP) < 0.01, "cast %d turned on by %.3f of a gap from the last" % [n, step])
		for m in n:
			check(absf(turns[n] - turns[m]) > 0.05, "cast %d stands apart from cast %d" % [n, m])


## A firing and its mirror share the turn: the mirrored ring is the first reversed, its sixteen
## bolts two on each of the same eight ways.
func test_a_mirror_shares_the_turn() -> void:
	var tag: int = _cast_with(&"bolt", [&"mirror", &"nova"], 0, Vector2.ZERO)
	# The second cast, which stands turned off the aim.
	_tick(150)
	var before: Array[int] = _slots(tag)
	check(_spells.cast_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "cast again")
	var ways: Array[float] = _ways_of(tag, Vector2.RIGHT, before)
	check_equal(ways.size(), 16, "two rings of eight")
	check(not ways.is_empty() and absf(ways[0]) > 0.05, "turned off the aim (%s)" % [ways])
	var lines: Dictionary = {}
	for way in ways:
		lines[posmod(roundi(way * 100.0), 800)] = true
	check_equal(lines.size(), 8, "on the same eight ways, none between")


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
