extends "res://tests/support/suite.gd"
## The Teleport card (content/spells/forms/teleport/, staffs C): a carrier that blinks the caster a
## fixed distance along the aim. The engine side is tested in `tests/core/test_spells_moves.gd`
## and `tests/gameplay/player/test_player_caster.gd`; here the card's data and its combos.
##
## godot --headless --path . --script res://tests/content/spells/test_teleport.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["teleport_away", "teleport_and_fire", "shield_teleport"]


func _card() -> FormBase:
	return load("res://content/spells/forms/teleport/teleport.tres") as FormBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Casts `cards` from `seat` and returns the moves asked of the caster as [actor, mode, to, seconds].
func _moves(cards: Array, seat: int = 0) -> Array:
	var arena := ArenaScript.new(root)
	var moves: Array = []
	arena.bus.caster_move_requested.connect(func(actor: int, mode: StringName, to: Vector2, seconds: float, _tag: int) -> void:
		moves.append([actor, mode, to, seconds]))
	arena.place_caster(seat, Vector2.ZERO)
	arena.install_cards(seat, 0, cards)
	arena.cast(seat, 0)
	arena.run(0.5)
	arena.free_all()
	return moves


func test_the_card_is_a_valid_carrier() -> void:
	var card: FormBase = _card()
	check(card != null, "teleport.tres loads as a FormBase")
	if card == null:
		return
	check_equal(card.id, &"teleport", "its id is its folder")
	check_equal(card.kind(), &"form", "a carrier card")
	check_equal(card.carrier, &"teleport", "it is a teleport")
	check(card.ray_length > 0.0, "it has a distance")
	check_equal(card.speed, 0.0, "speed is a placeholder: the distance is ray_length alone")
	check(card.mana_cost > 0.0, "it costs mana, which a dash does not")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_combos_exist() -> void:
	for id: String in COMBOS:
		check(not _combo(id).is_empty(), "the combo %s exists" % id)


func test_a_cast_blinks_the_caster_the_card_s_distance() -> void:
	var card: FormBase = _card()
	var moves: Array = _moves(["teleport"])
	check_equal(moves.size(), 1, "one move is asked")
	if moves.is_empty() or card == null:
		return
	check_equal(moves[0][1], &"teleport", "a teleport")
	check_equal(moves[0][3], 0.0, "at once")
	var away: float = Vector2.ZERO.distance_to(moves[0][2] as Vector2)
	check(absf(away - card.ray_length) < 0.5, "the card's distance away (%s of %s)" % [away, card.ray_length])


func test_a_cast_without_the_card_asks_for_no_move() -> void:
	check(_moves(["fire", "bolt"]).is_empty(), "a bolt moves nobody")


func test_four_players_blink_each() -> void:
	for seat in 4:
		var moves: Array = _moves(["teleport"], seat)
		check_equal(moves.size(), 1, "player %d blinks once" % seat)
		if not moves.is_empty():
			check_equal(moves[0][1], &"teleport", "player %d: a teleport" % seat)
