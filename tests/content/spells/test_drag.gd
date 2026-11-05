extends "res://tests/support/suite.gd"
## The Drag card (content/spells/modifiers/drag/): the next shot bursts out fast and slows down
## over its life, easing out to a stop where it ends, as far as a plain shot goes. It strikes near
## things sooner than a plain shot, its `on expire` goes off where it stopped, more cards
## multiply, and it is wasted on a carrier that does not fly out.
##
## godot --headless --path . --script res://tests/content/spells/test_drag.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/drag/drag.tres") as ModifierBase


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "drag.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"drag", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.NONE, "numbers only: no behaviour of its own")
	check(card.speed_start > 1.0 and card.speed_end == 0.0 and card.speed_ease > 1.0, "it bursts out and eases to a stop")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


## Health an imp at `at` loses to one cast of `cards` in `seconds`.
func _lost(cards: Array, at: Vector2, seconds: float) -> int:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(at)
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	arena.run(seconds)
	var lost: int = arena.lost(imp)
	arena.free_all()
	return lost


func test_it_strikes_sooner_than_a_plain_bolt() -> void:
	check_equal(_lost(["bolt"], Vector2(150.0, 0.0), 0.5), 0, "a plain bolt has not got there yet")
	check(_lost(["drag", "bolt"], Vector2(150.0, 0.0), 0.5) > 0, "a drag bolt has")


func test_it_goes_as_far_as_a_plain_bolt() -> void:
	# A bolt flies 220 px/s for 1.2 s: 264 px. Its nova goes off where it ended, either way.
	for cards: Array in [["on_expire", "bolt", "nova"], ["on_expire", "drag", "bolt", "nova"]]:
		check(_lost(cards, Vector2(262.0, 30.0), 1.8) > 0, "%s ends where a bolt does" % str(cards))
		check_equal(_lost(cards, Vector2(140.0, 30.0), 1.8), 0, "%s does not end short" % str(cards))


func test_drag_cards_multiply() -> void:
	var arena := ArenaScript.new(root)
	var card: ModifierBase = _card()
	var staff: CompiledStaff = arena.install_cards(0, 0, ["drag", "drag", "bolt"])
	var spell: CompiledSpell = staff.casts[0].group.spells[0]
	arena.free_all()
	check_equal(spell.speed_start, card.speed_start * card.speed_start, "two cards multiply the start")
	check_equal(spell.speed_ease, card.speed_ease * card.speed_ease, "and the ease")


func test_it_is_wasted_on_a_carrier_that_does_not_fly_out() -> void:
	var arena := ArenaScript.new(root)
	for form: String in ["beam", "rune", "orbit"]:
		var staff: CompiledStaff = arena.install_cards(0, 0, ["drag", form])
		check(staff.wasted.has(0), "drag on a %s is wasted" % form)
	var bolt: CompiledStaff = arena.install_cards(0, 0, ["drag", "bolt"])
	check(not bolt.wasted.has(0), "but not on a bolt")
	arena.free_all()


func test_four_players_drag_at_once() -> void:
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 150.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(150.0, 0.0)))
		arena.install_cards(player, 0, ["drag", "bolt"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(0.5)
	for player in 4:
		check(arena.lost(imps[player]) > 0, "player %d's drag bolt strikes its imp first" % player)
	arena.free_all()
