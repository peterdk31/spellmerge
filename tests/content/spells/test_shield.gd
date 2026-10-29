extends "res://tests/support/suite.gd"
## The Shield card (content/spells/modifiers/shield/, staffs C): the next shot is a ward that blocks
## one enemy shot per shield (the shields add up); on a dash, a teleport or the caster itself it is
## a barrier on the caster. The combos with the card are in content/spells/combos/ (test_combos.gd
## plays them); here an enemy shot is sent through each shielded thing, from every seat.
##
## godot --headless --path . --script res://tests/content/spells/test_shield.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const COMBOS: Array[String] = ["shield_dash", "shield_wall_fire", "shield_orbit_ring"]


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/shield/shield.tres") as ModifierBase


func _first(cards: Array) -> CompiledSpell:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, cards)
	var spell: CompiledSpell = null if staff.is_empty() else staff.casts[0].group.spells[0]
	arena.free_all()
	return spell


## Casts `cards` from seat `seat`'s caster at the origin, then sends `count` enemy shots, one after
## another, at it from the right, 9 px apart across the aim (a wall's stones are 9 px apart).
## Returns how many of those shots were blocked.
func _blocked_by(cards: Array, count: int, seat: int = 0) -> int:
	var arena := ArenaScript.new(root)
	var blocked: Array = []
	arena.bus.shot_blocked.connect(func(_actor: int, _at: Vector2, _tag: int) -> void: blocked.append(1))
	var enemy: int = ActorSeats.enemy(arena.projectiles.actors)
	arena.install_cards(seat, 0, cards)
	arena.cast(seat, 0)
	for n in count:
		arena.projectiles.spawn(enemy, Vector2(90.0, 9.0 * (n - (count - 1) * 0.5)), Vector2(-60.0, 0.0), 2.0, 3.0, ManagerScript.LAYER_PLAYER)
	arena.run(1.0)
	arena.free_all()
	return blocked.size()


## Casts `cards` from seat `seat`, whose body stands at the origin, with an enemy shot flying at it.
## Returns the arena's `blocks` (the actors whose barrier stopped a shot) and how much health the
## body lost.
func _guarded(cards: Array, seat: int, shot: bool = true) -> Array:
	var arena := ArenaScript.new(root)
	var guard: Node2D = arena.add_guard(seat, Vector2.ZERO)
	arena.install_cards(seat, 0, cards)
	if shot:
		arena.shoot_at(Vector2(30.0, 0.0), Vector2.ZERO)
	arena.cast(seat, 0)
	arena.run(1.5)
	var result: Array = [arena.blocks.duplicate(), arena.lost(guard)]
	arena.free_all()
	return result


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "shield.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"shield", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.SHIELD, "the shield behaviour")
	check_equal(card.behaviour_strength, 1.0, "one charge a card")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_shields_add_up_on_the_carrier() -> void:
	check_equal(_first(["bolt"]).behaviour(ModifierBase.Behaviour.SHIELD), 0.0, "a plain bolt has none")
	check_equal(_first(["shield", "bolt"]).behaviour(ModifierBase.Behaviour.SHIELD), 1.0, "one card, one charge")
	check_equal(_first(["shield", "shield", "bolt"]).behaviour(ModifierBase.Behaviour.SHIELD), 2.0, "two cards, two charges")


func test_the_combos_exist() -> void:
	var ids: PackedStringArray = ComboFiles.file_ids()
	for id: String in COMBOS:
		check(ids.has(id), "the combo %s exists (test_combos.gd plays it)" % id)


func test_a_shielded_bolt_blocks_an_enemy_shot_and_a_plain_one_does_not() -> void:
	check_equal(_blocked_by(["shield", "bolt"], 1), 1, "the shielded bolt stops the enemy shot")
	check_equal(_blocked_by(["bolt"], 1), 0, "a plain bolt lets it through (it is a hit, not a block)")


func test_a_shielded_bolt_blocks_from_every_seat() -> void:
	for seat in range(1, 4):
		check_equal(_blocked_by(["shield", "bolt"], 1, seat), 1, "seat %d: the shielded bolt stops the enemy shot" % seat)
		check_equal(_blocked_by(["bolt"], 1, seat), 0, "seat %d: a plain bolt blocks none" % seat)


func test_each_shield_stops_one_shot() -> void:
	check_equal(_blocked_by(["shield", "wall"], 3), 3, "one shield on each stone of a wall: three shots, three blocks")
	check_equal(_blocked_by(["wall"], 3), 0, "a plain wall blocks none")


func test_a_shield_on_a_dash_is_a_barrier_on_the_caster() -> void:
	for seat in 4:
		var shielded: Array = _guarded(["shield", "dash"], seat)
		check_equal(shielded[0], [seat], "seat %d: the barrier stops the shot, and names the caster" % seat)
		check_equal(shielded[1], 0, "seat %d: the caster is not hurt" % seat)
		var plain: Array = _guarded(["dash"], seat)
		check_equal(plain[0], [], "seat %d: a plain dash blocks nothing" % seat)


func test_a_shield_on_the_caster_is_a_barrier() -> void:
	# Cards with no carrier land on the caster (a fallback).
	var spell: CompiledSpell = _first(["shield"])
	check(spell != null and spell.fallback == CompiledSpell.FALLBACK_CASTER, "a lone shield lands on the caster")
	var shielded: Array = _guarded(["shield"], 0)
	check_equal(shielded[0], [0], "the barrier stops the shot")
	# The cards' own area hit lands on the caster before the barrier is up; the shot costs nothing more.
	check_equal(shielded[1], _guarded(["shield"], 0, false)[1], "the caster loses only what the landing itself does")


func test_two_shields_on_a_dash_stop_two_shots() -> void:
	var arena := ArenaScript.new(root)
	arena.add_guard(0, Vector2.ZERO)
	arena.install_cards(0, 0, ["shield", "shield", "dash"])
	arena.shoot_at(Vector2(30.0, 0.0), Vector2.ZERO)
	arena.shoot_at(Vector2(36.0, 0.0), Vector2.ZERO)
	arena.cast(0, 0)
	arena.run(2.0)
	check_equal(arena.blocks.size(), 2, "two charges, two blocks")
	arena.free_all()
