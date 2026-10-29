extends "res://tests/support/suite.gd"
## The Recoil card (content/spells/modifiers/recoil/, staffs C): casting pushes the caster back
## from each firing, through `caster_move_requested`. The engine side is tested in
## `tests/core/test_spells_moves.gd` and `tests/gameplay/player/test_player_caster.gd`; here the
## card's data and its combos.
##
## godot --headless --path . --script res://tests/content/spells/test_recoil.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["recoil_blast_bolt", "recoil_split_bolts"]


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/recoil/recoil.tres") as ModifierBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Casts `cards` from `seat` at the origin (aiming right) and returns the moves asked of the
## caster as [actor, mode, to, seconds].
func _moves(cards: Array, seat: int = 0) -> Array:
	var arena := ArenaScript.new(root)
	var moves: Array = []
	arena.bus.caster_move_requested.connect(func(actor: int, mode: StringName, to: Vector2, seconds: float, _tag: int) -> void:
		moves.append([actor, mode, to, seconds]))
	arena.place_caster(seat, Vector2.ZERO)
	arena.add_imp(Vector2(100, 0))
	arena.install_cards(seat, 0, cards)
	arena.cast(seat, 0)
	arena.run(0.5)
	arena.free_all()
	return moves


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "recoil.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"recoil", "its id is its folder")
	check_equal(card.kind(), &"modifier", "a modifier card")
	check_equal(card.behaviour, ModifierBase.Behaviour.RECOIL, "the recoil behaviour")
	check(card.behaviour_strength > 0.0, "with a strength")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_a_cast_pushes_the_caster_back_by_the_strength() -> void:
	var moves: Array = _moves(["recoil", "bolt"])
	check_equal(moves.size(), 1, "one push is asked")
	if moves.is_empty():
		return
	check_equal(moves[0][1], &"recoil", "a recoil")
	var to: Vector2 = moves[0][2]
	check(to.is_equal_approx(Vector2(-_card().behaviour_strength, 0.0)), "against the aim by its strength (%s)" % [to])
	check(moves[0][3] > 0.0, "over some time, not at once")


func test_a_cast_without_the_card_asks_for_no_push() -> void:
	check(_moves(["bolt"]).is_empty(), "nobody is pushed")


func test_a_split_volley_is_one_kick() -> void:
	var moves: Array = _moves(["recoil", "split", "bolt"])
	check_equal(moves.size(), 1, "the volley is one firing, so one push")


func test_mirror_cancels_the_push() -> void:
	var moves: Array = _moves(["mirror", "recoil", "bolt"])
	check_equal(moves.size(), 2, "the shot ahead and the shot behind each kick")
	if moves.size() == 2:
		var apart: Vector2 = (moves[0][2] as Vector2) - (moves[1][2] as Vector2)
		check(absf(absf(apart.x) - 2.0 * _card().behaviour_strength) < 0.01 and absf(apart.y) < 0.01, "in opposite directions, equally hard (%s)" % [apart])


func test_the_combos_hold_with_the_card() -> void:
	for id: String in COMBOS:
		check(not _combo(id).is_empty(), "the combo %s exists" % id)


func test_four_players_are_pushed_each() -> void:
	var arena := ArenaScript.new(root)
	var pushed: Dictionary = {}
	arena.bus.caster_move_requested.connect(func(actor: int, mode: StringName, _to: Vector2, _seconds: float, _tag: int) -> void:
		if mode == &"recoil":
			pushed[actor] = int(pushed.get(actor, 0)) + 1)
	for player in 4:
		var at := Vector2(0.0, 150.0 * player)
		arena.place_caster(player, at)
		arena.add_imp(at + Vector2(100.0, 0.0))
		arena.install_cards(player, 0, ["recoil", "bolt"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(0.5)
	for player in 4:
		check_equal(pushed.get(player, 0), 1, "player %d is pushed once" % player)
	arena.free_all()
