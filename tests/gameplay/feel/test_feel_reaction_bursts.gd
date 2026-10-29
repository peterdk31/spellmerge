extends "res://tests/support/suite.gd"
## Reactions and statuses in gameplay/feel (#244, part 3): a reaction is a burst bigger than a
## plain hit (a ring, a bigger spray, a longer hit-stop, more shake and its sound together), and
## an enemy with burning, chill, freeze, shock or hex shows it on its sprite, without text.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")

const ActorSeats := preload("res://tests/support/actor_seats.gd")

const STEP: float = 0.0625


## Stands in for combat: the statuses an enemy has, as seconds left by status id.
class FakeCombat:
	extends Node
	var left: Dictionary = {}

	func status_left(enemy: Node, status_id: StringName) -> float:
		var own_left: Dictionary = left.get(enemy.get_instance_id(), {}) as Dictionary
		return own_left.get(status_id, 0.0) as float


class Enemy:
	extends Node2D
	var sprite: Sprite2D

	func _init() -> void:
		sprite = Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = preload("res://art/vfx/hit_spark.svg")
		add_child(sprite)


var _bus: EventsScript
var _feel: FeelScript
var _combat: FakeCombat
var _actors: ActorSeats.ActorsScript


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	_combat = own(FakeCombat.new()) as FakeCombat
	_feel = own(FeelScript.new()) as FeelScript
	_feel.events = _bus
	_feel.combat = _combat
	_feel.actors = _actors
	_feel.drive_engine = false
	_feel.preset = FeelPresetScript.new()
	root.add_child(_feel)


func _enemy() -> Enemy:
	var enemy: Enemy = own(Enemy.new()) as Enemy
	root.add_child(enemy)
	return enemy


func _status_on(enemy: Enemy, id: StringName, player: int = 0) -> void:
	_combat.left[enemy.get_instance_id()] = {id: 3.0}
	_bus.status_applied.emit(player, enemy, id)


func test_a_reaction_stops_longer_and_shakes_more_than_a_plain_hit() -> void:
	var preset: FeelPresetScript = _feel.preset
	check(preset.reaction_stop_seconds > preset.death_stop_seconds, "longer than a death's stop")
	check(preset.reaction_shake > preset.death_shake * 0.5, "a strong shake")
	_bus.reaction_triggered.emit(0, &"flare", Vector2.ZERO)
	check(_actors.held_left(0) >= preset.reaction_stop_seconds, "its caster is held for the reaction")
	check_equal(_feel.stop_left, 0.0, "and the game runs on")
	check(_feel.trauma() >= preset.reaction_shake, "and shake")


func test_every_reaction_has_a_power_and_a_colour() -> void:
	var preset: FeelPresetScript = FeelPresetScript.new()
	for id: StringName in preset.reaction_colors:
		check(preset.reaction_power.has(id), "%s has a power" % id)


func test_the_puff_is_bigger_than_a_hit_and_the_ring_ends() -> void:
	_bus.damage_dealt.emit(0, null, 5, Vector2(50.0, 0.0))
	var hit: int = _feel.effect_info(FeelScript.KIND_PUFF)["zoom"] as int
	_bus.reaction_triggered.emit(0, &"shatter", Vector2.ZERO)
	check((_feel.effect_info(FeelScript.KIND_PUFF)["zoom"] as int) > hit, "a reaction's puff is bigger than a hit's")
	check_equal(_feel.effects_of(FeelScript.KIND_RING_OUT), 1, "with a ring")
	for i in 40:
		_feel.step(STEP)
	check_equal(_feel.live_effects(), 0, "ring and puff end")


func test_four_players_reacting_at_once_stay_inside_the_effect_slots() -> void:
	for player in 4:
		_bus.reaction_triggered.emit(player, &"shatter", Vector2(float(player) * 20.0, 0.0))
	check_equal(_feel.effects_of(FeelScript.KIND_PUFF), 4, "four puffs")
	check(_feel.live_effects() <= _feel.effect_slots, "inside the effect slots")


func test_each_status_shows_a_different_colour() -> void:
	var seen: Array[Color] = []
	for id: StringName in [&"burn", &"chill", &"freeze", &"shock", &"hex"]:
		var enemy: Enemy = _enemy()
		_status_on(enemy, id)
		check_equal(_feel.status_shown(enemy), id, "%s shows" % id)
		var preset: FeelPresetScript = _feel.preset
		var color: Color = (preset.status_looks[id] as Dictionary)["color"] as Color
		for other in seen:
			var apart: float = Vector3(color.r - other.r, color.g - other.g, color.b - other.b).length()
			check(apart >= 0.3, "%s differs from the others (%.2f)" % [id, apart])
		seen.append(color)


func test_the_status_follows_the_enemy_and_ends_with_the_status() -> void:
	var enemy: Enemy = _enemy()
	enemy.global_position = Vector2(40.0, 30.0)
	_status_on(enemy, &"burn")
	_feel.step(STEP)
	check_equal(_feel.live_statuses(), 1, "one status effect")
	var shown: Dictionary = _feel.effect_info(FeelScript.KIND_STATUS)
	var preset: FeelPresetScript = _feel.preset
	var look: Dictionary = preset.status_looks[&"burn"] as Dictionary
	check_equal(shown["core"], look["color"], "in the status's colour")
	check(ProjectileManagerScript.look_has(shown["look"] as int, look["look"] as int), "giving off the element's particles (fire's embers)")
	enemy.global_position = Vector2(80.0, 30.0)
	_feel.step(STEP)
	check_equal((_feel.effect_info(FeelScript.KIND_STATUS)["at"] as Vector2).x, 80.0, "it moved with the enemy")
	_combat.left.clear()
	for i in 4:
		_feel.step(STEP)
	check_equal(_feel.live_statuses(), 0, "it ends when the status does")


func test_a_frozen_enemy_wins_over_its_other_statuses() -> void:
	var enemy: Enemy = _enemy()
	_combat.left[enemy.get_instance_id()] = {&"burn": 2.0, &"freeze": 1.0}
	_bus.status_applied.emit(0, enemy, &"freeze")
	check_equal(_feel.status_shown(enemy), &"freeze", "freeze first")


func test_a_status_shows_through_a_hit() -> void:
	var enemy: Enemy = _enemy()
	_status_on(enemy, &"hex")
	check_equal(_feel.live_statuses(), 1, "shown")
	_bus.damage_dealt.emit(0, enemy, 3, Vector2.ZERO)
	_feel.step(STEP * 0.1)
	check_equal(_feel.live_statuses(), 1, "its particles go on while the sprite flashes")


func test_a_status_comes_back_when_a_crowd_of_effects_took_its_slot() -> void:
	_feel.set_effect_slots(EffectSlots.MIN)
	var enemy: Enemy = _enemy()
	_status_on(enemy, &"static")
	for i in _feel.effect_slots:
		_bus.damage_dealt.emit(0, null, 5, Vector2(float(i), 0.0))
	check_equal(_feel.live_statuses(), 0, "the crowd took the oldest slot, the status's")
	_feel.step(STEP)
	check_equal(_feel.live_statuses(), 1, "the next step shows it again")


func test_a_sprite_with_its_own_material_still_shows_a_status() -> void:
	var enemy: Enemy = _enemy()
	(enemy.get_node("Sprite") as Sprite2D).material = ShaderMaterial.new()
	_status_on(enemy, &"burn")
	check_equal(_feel.live_statuses(), 1, "an own material is not the hit flash")


func test_a_freed_enemy_loses_its_overlay() -> void:
	var enemy: Enemy = _enemy()
	_status_on(enemy, &"shock")
	enemy.free()
	_feel.step(STEP)
	check_equal(_feel.live_statuses(), 0, "no overlay for a freed enemy")


func test_a_crowd_of_statuses_stays_inside_the_slots() -> void:
	for i in FeelScript.STATUS_SLOTS + 8:
		_status_on(_enemy(), &"burn", i % 4)
	check(_feel.live_statuses() <= FeelScript.STATUS_SLOTS, "no more statuses than slots")


func test_without_combat_there_are_no_overlays() -> void:
	_feel.combat = null
	var enemy: Enemy = _enemy()
	_bus.status_applied.emit(0, enemy, &"burn")
	check_equal(_feel.live_statuses(), 0, "nothing to read, nothing shown")
