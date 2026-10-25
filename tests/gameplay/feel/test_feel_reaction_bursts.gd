extends "res://tests/support/suite.gd"
## Reactions and statuses in gameplay/feel (#244, part 3): a reaction is a burst bigger than a
## plain hit (a ring, a bigger spray, a longer hit-stop, more shake and its sound together), and
## an enemy with burning, chill, freeze, shock or hex shows it on its sprite, without text.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")

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


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_combat = own(FakeCombat.new()) as FakeCombat
	_feel = own(FeelScript.new()) as FeelScript
	_feel.events = _bus
	_feel.combat = _combat
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
	check(_feel.stop_left >= preset.reaction_stop_seconds, "hit-stop began with the reaction")
	check(_feel.trauma() >= preset.reaction_shake, "and shake")


func test_every_reaction_has_a_power_and_a_colour() -> void:
	var preset: FeelPresetScript = FeelPresetScript.new()
	for id: StringName in preset.reaction_colors:
		check(preset.reaction_power.has(id), "%s has a power" % id)


func test_the_burst_is_bigger_than_a_hit_and_the_ring_ends() -> void:
	_bus.reaction_triggered.emit(0, &"shatter", Vector2.ZERO)
	check(_feel.live_particles() > 0, "particles fly")
	check(_feel.live_particles() <= FeelScript.PARTICLE_LIMIT, "inside the particle limit")
	for i in 40:
		_feel.step(STEP)
	check_equal(_feel.live_flashes(), 0, "ring and flash end")


func test_four_players_reacting_at_once_stay_inside_the_particle_limit() -> void:
	for player in 4:
		_bus.reaction_triggered.emit(player, &"shatter", Vector2(float(player) * 20.0, 0.0))
	check(_feel.live_particles() <= FeelScript.PARTICLE_LIMIT, "inside the particle limit")


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


func test_the_overlay_follows_the_enemy_and_ends_with_the_status() -> void:
	var enemy: Enemy = _enemy()
	enemy.global_position = Vector2(40.0, 30.0)
	_status_on(enemy, &"burn")
	_feel.step(STEP)
	check_equal(_feel.live_statuses(), 1, "one overlay")
	enemy.global_position = Vector2(80.0, 30.0)
	_feel.step(STEP)
	var overlay: Sprite2D = null
	for child in _feel.get_children():
		var sprite := child as Sprite2D
		if sprite != null and sprite.visible and sprite.z_index == enemy.sprite.z_index + FeelScript.STATUS_Z:
			overlay = sprite
	check(overlay != null, "the overlay is drawn above the enemy")
	if overlay != null:
		check_equal(overlay.global_position.x, 80.0, "it moved with the enemy")
	_combat.left.clear()
	for i in 4:
		_feel.step(STEP)
	check_equal(_feel.live_statuses(), 0, "it ends when the status does")


func test_a_frozen_enemy_wins_over_its_other_statuses() -> void:
	var enemy: Enemy = _enemy()
	_combat.left[enemy.get_instance_id()] = {&"burn": 2.0, &"freeze": 1.0}
	_bus.status_applied.emit(0, enemy, &"freeze")
	check_equal(_feel.status_shown(enemy), &"freeze", "freeze first")


func test_the_hit_flash_hides_the_overlay() -> void:
	var enemy: Enemy = _enemy()
	_status_on(enemy, &"hex")
	check_equal(_feel.live_statuses(), 1, "shown")
	_bus.damage_dealt.emit(0, enemy, 3, Vector2.ZERO)
	_feel.step(STEP * 0.1)
	check_equal(_feel.live_statuses(), 0, "hidden while the sprite flashes white")
	for i in 10:
		_feel.step(STEP)
	check_equal(_feel.live_statuses(), 1, "and back after")


func test_a_freed_enemy_loses_its_overlay() -> void:
	var enemy: Enemy = _enemy()
	_status_on(enemy, &"shock")
	enemy.free()
	_feel.step(STEP)
	check_equal(_feel.live_statuses(), 0, "no overlay for a freed enemy")


func test_a_crowd_of_statuses_stays_inside_the_slots() -> void:
	for i in FeelScript.STATUS_SLOTS + 8:
		_status_on(_enemy(), &"burn", i % 4)
	check(_feel.live_statuses() <= FeelScript.STATUS_SLOTS, "no more overlays than slots")


func test_without_combat_there_are_no_overlays() -> void:
	_feel.combat = null
	var enemy: Enemy = _enemy()
	_bus.status_applied.emit(0, enemy, &"burn")
	check_equal(_feel.live_statuses(), 0, "nothing to read, nothing shown")
