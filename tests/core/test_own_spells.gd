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
	arena.answer_moves()
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


## A spell starts at the staff tip, off its caster's body (the wizard's tip is 14-18 px from its
## hand, its hit circle's centre, and a nova shot's reach 13): a nova's shot aimed back across its
## caster passes them (owner, 2026-11-07: "When firing the nova. Its hitting my own character with
## one of the bolts").
func test_a_nova_from_the_staff_tip_spares_its_caster() -> void:
	for off: float in [18.0, 24.0]:
		var arena := ArenaScript.new(root)
		arena.answer_moves()
		var body: Node2D = arena.add_guard(0, Vector2(-off, 0.0))
		arena.install_cards(0, 0, ["nova", "bolt"])
		check(arena.cast(0, 0), "a nova is cast")
		arena.run(1.0)
		check_equal(arena.lost(body), 0, "a nova cast %d px off its caster's body never hits it" % int(off))
		arena.free_all()


func test_a_return_bolt_hurts_its_caster() -> void:
	check(_self_lost(["return", "bolt"]) > 0, "a bolt that comes back hits its caster")


func test_a_bolt_back_off_a_wall_hurts_its_caster() -> void:
	check(_self_lost(["bounce", "bolt"], 2.0, Rect2(40.0, -100.0, 16.0, 200.0)) > 0, "a bolt that bounces back hits its caster")


## Melee is one trait (`Carrier.MELEE`): exactly the carriers held by or carried with their body.
func test_melee_is_the_carriers_that_never_leave_their_body() -> void:
	var melee: Array[String] = []
	for id: StringName in Carriers.ids():
		if Carriers.of(id).has(Carrier.MELEE):
			melee.append(String(id))
	melee.sort()
	check_equal(melee, ["dash", "slam", "swing", "teleport"] as Array[String], "the melee carriers")


## Every melee carrier never hits the body that casts it, a move's (dash, teleport) as it goes.
func test_melee_spares_its_caster() -> void:
	for form: String in ["swing", "slam", "dash", "teleport"]:
		var arena := ArenaScript.new(root)
		arena.answer_moves()
		var body: Node2D = arena.add_guard(0, Vector2.ZERO)
		arena.install_cards(0, 0, [form])
		var struck: Array[int] = [0]
		arena.bus.projectile_hit.connect(func(_caster: int, target: Node, _at: Vector2, _tag: int, _shot: int) -> void:
			if target == body:
				struck[0] += 1)
		check(arena.cast(0, 0), "%s is cast" % form)
		arena.run(1.0)
		check_equal(struck[0], 0, "a %s never hits the body that casts it" % form)
		arena.free_all()


## A beam is ranged along its length: straight it never comes back to its caster; bounced back off a
## wall it hits them.
func test_a_beam_spares_its_caster_until_it_turns_back() -> void:
	check_equal(_self_lost(["beam"], 1.0), 0, "a straight beam never hits the body it is cast from")
	check(_self_lost(["bounce", "beam"], 1.0, Rect2(40.0, -100.0, 16.0, 200.0)) > 0, "a beam bounced back off a wall hits its caster")


## A ranged strike spares nobody: a teleport's landing spares the body that lands, a blast where
## its caster stands does not.
func test_a_blast_at_the_caster_hits_them() -> void:
	check(_self_lost(["blast", "teleport"], 1.0) > 0, "the blast where the teleport lands hits its caster")
