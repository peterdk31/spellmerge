extends "res://tests/support/suite.gd"
## The Return card (content/spells/modifiers/return/, owner 2026-10-27; it replaces the boomerang
## carrier): the next shot flies out for half its life, then back to its caster. A piercing one
## hits the same imp on the way out and back; its `on expire` goes off at the caster's feet; it is
## wasted on a carrier that does not fly out.
##
## godot --headless --path . --script res://tests/content/spells/test_return.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = load("res://content/spells/modifiers/return/return.tres") as ModifierBase
	check(card != null, "return.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"return", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.RETURN, "the return behaviour")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


## Health an imp at `at` loses to one cast of `cards` in `seconds`.
func _lost(cards: Array, at: Vector2, seconds: float = 1.8) -> int:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(at)
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	arena.run(seconds)
	var lost: int = arena.lost(imp)
	arena.free_all()
	return lost


func test_a_piercing_return_bolt_hits_twice() -> void:
	var once: int = _lost(["pierce", "bolt"], Vector2(60.0, 0.0))
	var twice: int = _lost(["return", "pierce", "bolt"], Vector2(60.0, 0.0))
	check(once > 0, "a piercing bolt hits")
	check_equal(twice, once * 2, "out and back: twice")


func test_its_on_expire_goes_off_at_home() -> void:
	check(_lost(["on_expire", "return", "bolt", "nova"], Vector2(-45.0, 0.0)) > 0, "the nova at the caster's feet hits the imp behind")
	check_equal(_lost(["on_expire", "bolt", "nova"], Vector2(-45.0, 0.0)), 0, "without return the nova goes off far away")


func test_it_is_wasted_on_a_carrier_that_does_not_fly_out() -> void:
	var arena := ArenaScript.new(root)
	for form: String in ["beam", "rune", "orbit"]:
		var staff: CompiledStaff = arena.install_cards(0, 0, ["return", form])
		check(staff.wasted.has(0), "return on a %s is wasted" % form)
	arena.free_all()


func test_four_players_return_at_once() -> void:
	var arena := ArenaScript.new(root)
	var imps: Array[Node2D] = []
	for player in 4:
		var at := Vector2(0.0, 150.0 * player)
		arena.place_caster(player, at)
		imps.append(arena.add_imp(at + Vector2(60.0, 0.0)))
		arena.install_cards(player, 0, ["return", "pierce", "bolt"])
	for player in 4:
		check(arena.cast(player, 0), "player %d casts" % player)
	arena.run(1.8)
	var once: int = _lost(["pierce", "bolt"], Vector2(60.0, 0.0))
	for imp in imps:
		check_equal(arena.lost(imp), once * 2, "every player's bolt hits its imp twice")
	arena.free_all()
