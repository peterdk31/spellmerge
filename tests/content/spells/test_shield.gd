extends "res://tests/support/suite.gd"
## The Shield card (content/spells/modifiers/shield/, staffs C): the next shot is a ward that blocks
## one enemy shot per shield (the shields add up). Its combos still do their work, and an enemy
## shot sent through the shielded shots is stopped.
##
## godot --headless --path . --script res://tests/content/spells/test_shield.gd

const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ComboFiles := preload("res://tests/support/combo_files.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const COMBOS: Array[String] = ["shield_wall_fire", "shield_orbit_ring"]


func _card() -> ModifierBase:
	return load("res://content/spells/modifiers/shield/shield.tres") as ModifierBase


func _combo(id: String) -> Dictionary:
	for combo: Dictionary in ComboFiles.read_all():
		if combo["id"] == id:
			return combo
	return {}


## Plays `combo` (imps only) and returns whether every status check held.
func _holds(combo: Dictionary) -> bool:
	var arena := ArenaScript.new(root)
	for at: Array in combo["imps"]:
		arena.add_imp(Vector2(float(at[0]), float(at[1])))
	var entry: Dictionary = combo["casts"][0]
	arena.install_cards(0, int(entry["staff"]), entry["cards"])
	arena.cast(0, int(entry["staff"]))
	arena.run(float(combo["seconds"]))
	var held: bool = true
	for row: Dictionary in combo["checks"]:
		for index: int in row["imps"]:
			held = held and arena.was_given(arena.imps[index], StringName(row["status"]))
	arena.free_all()
	return held


func _first(cards: Array) -> CompiledSpell:
	var arena := ArenaScript.new(root)
	var staff: CompiledStaff = arena.install_cards(0, 0, cards)
	var spell: CompiledSpell = null if staff.is_empty() else staff.casts[0].group.spells[0]
	arena.free_all()
	return spell


## Casts `cards` from the caster at the origin, then sends `count` enemy shots, one after another,
## at it from the right, 9 px apart across the aim (a wall's stones are 9 px apart). Returns how many of those shots were blocked.
func _blocked_by(cards: Array, count: int) -> int:
	var arena := ArenaScript.new(root)
	var blocked: Array = []
	arena.bus.shot_blocked.connect(func(_actor: int, _at: Vector2, _tag: int) -> void: blocked.append(1))
	var enemy: int = ActorSeats.enemy(arena.projectiles.actors)
	arena.install_cards(0, 0, cards)
	arena.cast(0, 0)
	for n in count:
		arena.projectiles.spawn(enemy, Vector2(90.0, 9.0 * (n - (count - 1) * 0.5)), Vector2(-60.0, 0.0), 2.0, 3.0, ManagerScript.LAYER_PLAYER)
	arena.run(1.0)
	arena.free_all()
	return blocked.size()


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = _card()
	check(card != null, "shield.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"shield", "its id is its folder")
	check_equal(card.behaviour, ModifierBase.Behaviour.SHIELD, "the shield behaviour")
	check(card.behaviour_strength >= 1.0, "one charge a card")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])


func test_shields_add_up_on_the_carrier() -> void:
	check_equal(_first(["bolt"]).behaviour(ModifierBase.Behaviour.SHIELD), 0.0, "a plain bolt has none")
	check_equal(_first(["shield", "bolt"]).behaviour(ModifierBase.Behaviour.SHIELD), 1.0, "one card, one charge")
	check_equal(_first(["shield", "shield", "bolt"]).behaviour(ModifierBase.Behaviour.SHIELD), 2.0, "two cards, two charges")


func test_the_combos_still_work_with_the_card() -> void:
	for id: String in COMBOS:
		var combo: Dictionary = _combo(id)
		check(not combo.is_empty(), "the combo %s exists" % id)
		if combo.is_empty():
			continue
		check(_holds(combo), "%s does what it promises" % id)


func test_a_shielded_bolt_blocks_an_enemy_shot_and_a_plain_one_does_not() -> void:
	check_equal(_blocked_by(["shield", "bolt"], 1), 1, "the shielded bolt stops the enemy shot")
	check_equal(_blocked_by(["bolt"], 1), 0, "a plain bolt lets it through (it is a hit, not a block)")


func test_each_shield_stops_one_shot() -> void:
	check_equal(_blocked_by(["shield", "wall"], 3), 3, "one shield on each stone of a wall: three shots, three blocks")
	check_equal(_blocked_by(["wall"], 3), 0, "a plain wall blocks none")
