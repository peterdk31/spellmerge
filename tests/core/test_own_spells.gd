extends "res://tests/support/suite.gd"
## A player's own spells hurt them (owner, 2026-11-06: "A players own spells should hurt the player
## if hit by them. So for example return becomes dangerous."), once they have left their body: a
## spell spares only the body it is cast from, a shot until it is clear of it (`Spells._launch`,
## `ProjectileManager.exclude`), and a carrier that never leaves it (a swing, a beam) always.
## Nothing else is spared: no team, no caster.
##
## godot --headless --path . --script res://tests/core/test_own_spells.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")


## Health the caster's body (at the caster's place) loses to one cast of `cards` in `seconds`,
## with a wall `wall` (none when empty) in the way.
func _self_lost(cards: Array, seconds: float = 2.0, wall: Rect2 = Rect2()) -> int:
	var arena := ArenaScript.new(root)
	var body: Node2D = arena.add_guard(0, Vector2.ZERO)
	if wall.has_area():
		arena.add_wall(wall)
	arena.install_cards(0, 0, cards)
	check(arena.cast(0, 0), "%s is cast" % [cards])
	arena.run(seconds)
	var lost: int = arena.lost(body)
	arena.free_all()
	return lost


func test_a_bolt_spares_the_body_it_leaves() -> void:
	check_equal(_self_lost(["bolt"]), 0, "a bolt flies off its caster without hurting them")


func test_a_return_bolt_hurts_its_caster() -> void:
	check(_self_lost(["return", "bolt"]) > 0, "a bolt that comes back hits its caster")


func test_a_bolt_back_off_a_wall_hurts_its_caster() -> void:
	check(_self_lost(["bounce", "bolt"], 2.0, Rect2(40.0, -100.0, 16.0, 200.0)) > 0, "a bolt that bounces back hits its caster")


func test_carriers_that_never_leave_spare_their_caster() -> void:
	for form: String in ["swing", "beam", "slam"]:
		check_equal(_self_lost([form], 1.0), 0, "a %s never hits the body that casts it" % form)
