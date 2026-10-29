extends "res://tests/support/suite.gd"
## The Hook card (content/spells/forms/hook/, staffs C): a straight shot that pulls the caster to
## where it hits. The engine side is tested in `tests/core/test_spells_moves.gd` and
## `tests/gameplay/player/test_player_caster.gd`; here the card's data and its combos.
##
## godot --headless --path . --script res://tests/content/spells/test_hook.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["hook_pull", "hook_miss", "hook_and_fire", "shield_hook"]


func _card() -> FormBase:
	return load("res://content/spells/forms/hook/hook.tres") as FormBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Casts `cards` from `seat` with an imp `imp_at` away on the aim and returns the moves asked of the
## caster as [actor, mode, to, seconds].
func _moves(cards: Array, imp_at: Vector2, seat: int = 0) -> Array:
	var arena := ArenaScript.new(root)
	var moves: Array = []
	arena.bus.caster_move_requested.connect(func(actor: int, mode: StringName, to: Vector2, seconds: float, _tag: int) -> void:
		moves.append([actor, mode, to, seconds]))
	arena.place_caster(seat, Vector2.ZERO)
	arena.add_imp(imp_at)
	arena.install_cards(seat, 0, cards)
	arena.cast(seat, 0)
	arena.run(1.0)
	arena.free_all()
	return moves


func test_the_card_is_a_valid_carrier() -> void:
	var card: FormBase = _card()
	check(card != null, "hook.tres loads as a FormBase")
	if card == null:
		return
	check_equal(card.id, &"hook", "its id is its folder")
	check_equal(card.kind(), &"form", "a carrier card")
	check_equal(card.motion, FormBase.Motion.HOOK, "it is a hook")
	check(card.speed > 0.0 and card.lifetime > 0.0, "it flies")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_the_combos_exist() -> void:
	for id: String in COMBOS:
		check(not _combo(id).is_empty(), "the combo %s exists" % id)


func test_a_hit_pulls_the_caster_to_the_target() -> void:
	var moves: Array = _moves(["hook"], Vector2(100, 0))
	check_equal(moves.size(), 1, "one pull is asked")
	if moves.is_empty():
		return
	check_equal(moves[0][1], &"hook", "a hook")
	var to: Vector2 = moves[0][2]
	check(to.x > 60.0 and to.x < 110.0 and absf(to.y) < 1.0, "to the imp, along the aim (%s)" % [to])
	check(moves[0][3] > 0.0, "over some time, not at once")


func test_a_miss_pulls_nobody() -> void:
	check(_moves(["hook"], Vector2(0, 100)).is_empty(), "the barb flies past the imp and nobody moves")


func test_an_imp_beyond_the_reach_is_not_hooked() -> void:
	var card: FormBase = _card()
	if card == null:
		return
	var reach: float = card.speed * card.lifetime
	check(_moves(["hook"], Vector2(reach + 80.0, 0)).is_empty(), "an imp beyond the reach (%s px) is not hooked" % reach)


func test_a_cast_without_the_card_asks_for_no_move() -> void:
	check(_moves(["fire", "bolt"], Vector2(100, 0)).is_empty(), "a bolt moves nobody")


func test_four_players_pull_each() -> void:
	for seat in 4:
		var moves: Array = _moves(["hook"], Vector2(100, 0), seat)
		check_equal(moves.size(), 1, "player %d is pulled once" % seat)
		if not moves.is_empty():
			check_equal(moves[0][0], seat, "player %d: the pull is theirs" % seat)
			check_equal(moves[0][1], &"hook", "player %d: a hook" % seat)
