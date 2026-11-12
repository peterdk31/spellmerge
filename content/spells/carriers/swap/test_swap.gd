extends "res://tests/support/suite.gd"
## The Swap card (content/spells/carriers/swap/, staffs C): a straight shot that trades places with
## the target it hits. The engine side is tested in `tests/core/test_spells_moves.gd` and
## `tests/gameplay/player/test_player_caster.gd`; here the card's data. Its combos run in `test_combos.gd`; here they are only checked to exist.
##
## godot --headless --path . --script res://content/spells/carriers/swap/test_swap.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")

const COMBOS: Array[String] = ["swap_trade", "swap_miss", "swap_frost"]


func _card() -> FormBase:
	return load("res://content/spells/carriers/swap/swap.tres") as FormBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Casts `cards` from `seat` with an imp `imp_at` away on the aim. Returns the moves asked of the
## caster as [actor, mode, to, seconds] and, in `target_moves`, those asked of targets as [actor, to].
## `move_targets` puts the target where it is asked at once, as an actor's mover does.
func _moves(cards: Array, imp_at: Vector2, seat: int = 0, target_moves: Array = [], move_targets: bool = false) -> Array:
	var arena := ArenaScript.new(root)
	var moves: Array = []
	arena.bus.caster_move_requested.connect(func(actor: int, mode: StringName, to: Vector2, seconds: float, _tag: int) -> void:
		moves.append([actor, mode, to, seconds]))
	arena.bus.target_move_requested.connect(func(actor: int, target: Node, to: Vector2) -> void:
		target_moves.append([actor, to])
		if move_targets and target is Node2D:
			(target as Node2D).global_position = to)
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
	check_equal(card.carrier, &"swap", "it is a swap")
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


## Regression: the target was moved before its place was read, so with a target that moves at once
## (a decoy, an enemy: every actor's mover) the caster's move came out zero and the target only
## landed on the caster.
func test_a_target_that_moves_at_once_still_trades_places() -> void:
	var target_moves: Array = []
	var moves: Array = _moves(["swap"], Vector2(100, 0), 0, target_moves, true)
	check_equal(moves.size(), 1, "the caster is moved once")
	if moves.is_empty() or target_moves.is_empty():
		return
	var to: Vector2 = moves[0][2]
	check(to.distance_to(Vector2(100, 0)) < 30.0, "the caster still goes to where the imp stood (%s)" % [to])
	check((target_moves[0][1] as Vector2).length() < 1.0, "and the imp to where the caster stood")


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


## Its looks (S6 2): the cue each moment plays (every cue a card names is a cue file:
## tests/content/spells/test_carrier_looks.gd).
func test_its_moments_have_their_cues() -> void:
	var card: FormBase = load("res://content/spells/carriers/swap/swap.tres") as FormBase
	check_equal(card.shown_cue, &"trade", "its shown plays trade")


## Its look (the owner's pick, 2026-11-09: the chasing pair): its charm is drawn by its folder's own
## head shader, a copy of the plain head's with the pair for its core, in a head body of its own.
func test_its_charm_is_drawn_by_its_own_head_shader() -> void:
	var card: FormBase = _card()
	check(card.look_shader == preload("res://content/spells/carriers/swap/swap.gdshader"), "drawn by its folder's shader")
	check(card.look_problems().is_empty(), "a canvas-item shader its carrier draws: %s" % [card.look_problems()])
	check_equal(Carriers.of(card.carrier).look_drawer(), Carrier.LOOK_SHOT, "a shot in flight: a head")
	var code: String = card.look_shader.code
	check(code.contains("twinkle_px(") and code.contains("palette_count(inf)"), "its sparks are twinkling motes, one an infusion")
