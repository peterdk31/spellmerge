extends "res://tests/support/suite.gd"
## The Swap card (content/spells/forms/swap/, staffs C): a straight shot that trades places with
## the target it hits. The engine side is tested in `tests/core/test_spells_moves.gd` and
## `tests/gameplay/player/test_player_caster.gd`; here the card's data. Its combos run in `test_combos.gd`; here they are only checked to exist.
##
## godot --headless --path . --script res://tests/content/spells/test_swap.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["swap_trade", "swap_miss", "swap_frost"]


func _card() -> FormBase:
	return load("res://content/spells/forms/swap/swap.tres") as FormBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Casts `cards` from `seat` with an imp `imp_at` away on the aim. Returns the moves asked of the
## caster as [actor, mode, to, seconds] and, in `target_moves`, those asked of targets as [actor, to].
func _moves(cards: Array, imp_at: Vector2, seat: int = 0, target_moves: Array = []) -> Array:
	var arena := ArenaScript.new(root)
	var moves: Array = []
	arena.bus.caster_move_requested.connect(func(actor: int, mode: StringName, to: Vector2, seconds: float, _tag: int) -> void:
		moves.append([actor, mode, to, seconds]))
	arena.bus.target_move_requested.connect(func(actor: int, _target: Node, to: Vector2) -> void:
		target_moves.append([actor, to]))
	arena.place_caster(seat, Vector2.ZERO)
	arena.add_imp(imp_at)
	arena.install_cards(seat, 0, cards)
	arena.cast(seat, 0)
	arena.run(1.0)
	arena.free_all()
	return moves


func test_the_card_is_a_valid_carrier() -> void:
	var card: FormBase = _card()
	check(card != null, "swap.tres loads as a FormBase")
	if card == null:
		return
	check_equal(card.id, &"swap", "its id is its folder")
	check_equal(card.kind(), &"form", "a carrier card")
	check_equal(card.motion, FormBase.Motion.SWAP, "it is a swap")
	check(card.speed > 0.0 and card.lifetime > 0.0, "it flies")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_combos_exist() -> void:
	for id: String in COMBOS:
		check(not _combo(id).is_empty(), "the combo %s exists" % id)


func test_a_hit_trades_places() -> void:
	var target_moves: Array = []
	var moves: Array = _moves(["swap"], Vector2(100, 0), 0, target_moves)
	check_equal(moves.size(), 1, "the caster is moved once")
	check_equal(target_moves.size(), 1, "and the target once")
	if moves.is_empty() or target_moves.is_empty():
		return
	check_equal(moves[0][1], &"swap", "a swap")
	var to: Vector2 = moves[0][2]
	check(to.distance_to(Vector2(100, 0)) < 30.0, "the caster goes to the imp (%s)" % [to])
	check(moves[0][3] > 0.0, "the swap takes time (%s s)" % [moves[0][3]])
	var back: Vector2 = target_moves[0][1]
	check(back.length() < 1.0, "the imp goes to where the caster stood (%s)" % [back])


func test_a_miss_trades_nobody() -> void:
	var target_moves: Array = []
	check(_moves(["swap"], Vector2(0, 100), 0, target_moves).is_empty(), "nobody is moved")
	check(target_moves.is_empty(), "and nothing else either")


func test_a_cast_without_the_card_asks_for_no_move() -> void:
	check(_moves(["fire", "bolt"], Vector2(100, 0)).is_empty(), "a bolt moves nobody")


func test_four_players_trade_each() -> void:
	for seat in 4:
		var target_moves: Array = []
		var moves: Array = _moves(["swap"], Vector2(100, 0), seat, target_moves)
		check_equal(moves.size(), 1, "player %d is moved once" % seat)
		if not moves.is_empty():
			check_equal(moves[0][0], seat, "player %d: the trade is theirs" % seat)
			check_equal(moves[0][1], &"swap", "player %d: a swap" % seat)
		check_equal(target_moves.size(), 1, "player %d: the imp is moved once" % seat)
