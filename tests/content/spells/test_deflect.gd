extends "res://tests/support/suite.gd"
## The Deflect card (content/spells/modifiers/deflect/, melee I5; docs/milestones/M2-staffs.md,
## "Phase I: melee", "Deflect"): shots of another team that touch the carrier turn and become its
## caster's, 1.7 times faster, as many as touch it. The engine side is tested in
## `tests/core/test_spells_deflect.gd`; here the card's data and how it plays with other cards,
## from every seat. The combos with the card are in content/spells/combos/ (test_combos.gd plays
## them).
##
## godot --headless --path . --script res://tests/content/spells/test_deflect.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const COMBOS: Array[String] = ["deflect_swing_return", "deflect_wall_mirror"]


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/deflect/deflect.tres") as ModifierBase


func _shield() -> ModifierBase:
	return load("res://content/spells/modifiers/shield/shield.tres") as ModifierBase


## Casts `cards` from seat `seat`'s caster at the origin, then sends `count` enemy shots, one after
## another, at it from the right, 9 px apart across the aim (a wall's stones are 9 px apart).
## Returns [how many were deflected, how many of those are the seat's actor's now].
func _deflected_by(cards: Array, count: int, seat: int = 0) -> Array:
	var arena := ArenaScript.new(root)
	var enemy: int = ActorSeats.enemy(arena.projectiles.actors)
	arena.install_cards(seat, 0, cards)
	arena.cast(seat, 0)
	var shots: Array[int] = []
	for n in count:
		shots.append(arena.projectiles.spawn(enemy, Vector2(90.0, 9.0 * (n - (count - 1) * 0.5)), Vector2(-60.0, 0.0), 2.0, 3.0, ManagerScript.LAYER_PLAYER))
	arena.run(1.0)
	var turned: int = 0
	for slot: int in shots:
		if arena.projectiles.get_actor_of(slot) == seat:
			turned += 1
	var result: Array = [arena.deflects.size(), turned]
	arena.free_all()
	return result


## Health the imp at `imp_at` lost when a real enemy bolt is shot at the caster from `from` and the
## caster casts `cards` at once.
func _lost_behind(cards: Array, from: Vector2, imp_at: Vector2, seconds: float = 1.5) -> int:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(imp_at)
	arena.add_guard(0, Vector2.ZERO)
	arena.shoot_at(from, Vector2.ZERO)
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	arena.run(seconds)
	var lost: int = arena.lost(imp)
	arena.free_all()
	return lost


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "deflect.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"deflect", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.DEFLECT, "the deflect behaviour")
	check_equal(card.behaviour_strength, 1.0, "strength unused (1): it turns every shot that touches it")
	check_equal(card.complexity, 2, "complexity 2, as shield")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])
	check(not card.name_words.is_empty(), "it has name words")
	check_equal(card.look_layer, ManagerScript.LOOK_ZIG, "the zig look, shots thrown back at an angle (docs/DECISIONS.md)")


func test_it_costs_more_than_a_shield() -> void:
	# A shield blocks one shot per card for nothing; a deflect turns every shot into the caster's.
	var card: ModifierBase = _card()
	var shield: ModifierBase = _shield()
	check(card.mana_mult > shield.mana_mult, "more mana than a shield (%.2f)" % card.mana_mult)
	check(card.cooldown_mult > shield.cooldown_mult, "a longer delay than a shield, which is its price on a swing (%.2f)" % card.cooldown_mult)
	check(card.mana_mult <= 1.5 and card.cooldown_mult <= 1.5, "but not as dear as split or possess")


func test_the_combos_exist() -> void:
	var ids: PackedStringArray = ComboFiles.file_ids()
	for id: String in COMBOS:
		check(ids.has(id), "the combo %s exists (test_combos.gd plays it)" % id)


func test_a_deflecting_bolt_turns_an_enemy_shot_from_every_seat() -> void:
	for seat in 4:
		check_equal(_deflected_by(["deflect", "bolt"], 1, seat), [1, 1], "seat %d: the bolt turns the shot and it is the seat's now" % seat)
		check_equal(_deflected_by(["bolt"], 1, seat), [0, 0], "seat %d: a plain bolt turns none" % seat)


func test_one_card_turns_every_shot_that_touches_it() -> void:
	# No count (owner, 2026-10-29): a wall's stones turn all three shots, one card on the wall.
	check_equal(_deflected_by(["deflect", "wall"], 3), [3, 3], "three shots, three turned")
	check_equal(_deflected_by(["wall"], 3), [0, 0], "a plain wall turns none")


func test_a_deflecting_swing_bats_a_bolt_into_the_imp_behind_its_shooter() -> void:
	check(_lost_behind(["deflect", "swing"], Vector2(60.0, 0.0), Vector2(150.0, 0.0)) > 0, "the batted bolt hits the imp behind where it came from")
	check_equal(_lost_behind(["swing"], Vector2(60.0, 0.0), Vector2(150.0, 0.0)), 0, "a plain swing sends nothing back")


func test_a_deflected_shot_is_faster() -> void:
	var arena := ArenaScript.new(root)
	var enemy: int = ActorSeats.enemy(arena.projectiles.actors)
	arena.install_cards(0, 0, ["deflect", "wall"])
	arena.cast(0, 0)
	var shot: int = arena.projectiles.spawn(enemy, Vector2(90.0, 0.0), Vector2(-60.0, 0.0), 2.0, 3.0, ManagerScript.LAYER_PLAYER)
	arena.run(1.5)
	check_equal(arena.deflects.size(), 1, "deflected once")
	var way: Vector2 = arena.projectiles.get_velocity_of(shot)
	check(way.x > 0.0 and is_equal_approx(way.length(), 60.0 * SpellLimits.DEFLECT_SPEEDUP), "back out, 1.7 times faster: %s" % way)
	arena.free_all()


func test_it_is_wasted_where_nothing_touches_shots() -> void:
	# A rain's strike meets bodies, never shots; a hook pulls through them and keeps it, a dash
	# turns the shots it passes (rules R4c) and a decoy the shots that reach it (rules R4g).
	var arena := ArenaScript.new(root)
	check(arena.install_cards(0, 0, ["deflect", "rain"]).wasted.has(0), "a deflect on a rain is listed as wasted")
	check(not arena.install_cards(0, 0, ["deflect", "dash"]).wasted.has(0), "a dash keeps it")
	check(not arena.install_cards(0, 0, ["deflect", "decoy"]).wasted.has(0), "a decoy keeps it")
	check(not arena.install_cards(0, 0, ["deflect", "hook"]).wasted.has(0), "a hook keeps it")
	check(not arena.install_cards(0, 0, ["deflect", "swing"]).wasted.has(0), "a swing keeps it")
	arena.free_all()
