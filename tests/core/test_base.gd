extends SceneTree
## Tests for core/base: the spell, enemy and room base resources have their M1
## fields with safe defaults, and a saved .tres keeps the values.
##
## godot --headless --path . --script res://tests/core/test_base.gd

var _failures: Array[String] = []


func _initialize() -> void:
	_test_spell()
	_test_enemy()
	_test_room()
	_test_demo_defaults_to_false()
	_test_round_trip()
	_test_room_round_trip()
	_test_enemy_round_trip()
	if _failures.is_empty():
		print("TEST OK: core/base")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _test_spell() -> void:
	var spell := SpellBase.new()
	spell.id = &"fire_bolt"
	spell.display_name = "Fire Bolt"
	spell.mana_cost = 5.0
	spell.cooldown = 0.4
	spell.damage = 3
	spell.speed = 220.0
	spell.lifetime = 1.5
	_check(spell.id == &"fire_bolt" and spell.display_name == "Fire Bolt", "spell id and name")
	_check(spell.mana_cost == 5.0 and spell.cooldown == 0.4, "spell cost and cooldown")
	_check(spell.damage == 3 and spell.speed == 220.0 and spell.lifetime == 1.5, "spell damage, speed, lifetime")


func _test_enemy() -> void:
	var enemy := EnemyBase.new()
	enemy.id = &"ember_imp"
	enemy.max_health = 8
	enemy.move_speed = 60.0
	enemy.contact_damage = 1
	_check(enemy.id == &"ember_imp" and enemy.max_health == 8, "enemy id and health")
	_check(enemy.move_speed == 60.0 and enemy.contact_damage == 1, "enemy speed and contact damage")
	_check(enemy.scene == null, "enemy scene is empty by default")


func _test_room() -> void:
	var room := RoomBase.new()
	room.player_spawns = PackedVector2Array([Vector2(1, 1), Vector2(2, 1), Vector2(1, 2), Vector2(2, 2)])
	room.enemy_spawns = PackedVector2Array([Vector2(8, 8)])
	room.doors = PackedVector2Array([Vector2(0, 5)])
	_check(room.player_spawns.size() == 4, "room holds four player spawns")
	_check(room.enemy_spawns.size() == 1 and room.doors.size() == 1, "room enemy spawns and doors")
	_check(room.scene == null, "room scene is empty by default")


func _test_demo_defaults_to_false() -> void:
	_check(not SpellBase.new().demo, "spell: demo is false by default")
	_check(not EnemyBase.new().demo, "enemy: demo is false by default")
	_check(not RoomBase.new().demo, "room: demo is false by default")
	_check(SpellBase.new().id == &"", "spell: id is empty by default")


func _test_round_trip() -> void:
	var spell := SpellBase.new()
	spell.id = &"fire_bolt"
	spell.demo = true
	spell.damage = 4
	var path := "user://test_base_spell.tres"
	_check(ResourceSaver.save(spell, path) == OK, "spell saves as text")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as SpellBase
	_check(loaded != null, "spell loads back as SpellBase")
	if loaded != null:
		_check(loaded.id == &"fire_bolt" and loaded.demo and loaded.damage == 4, "spell keeps its values")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_room_round_trip() -> void:
	var room := RoomBase.new()
	room.id = &"start_room"
	room.demo = true
	room.player_spawns = PackedVector2Array([Vector2(1, 1), Vector2(2, 1), Vector2(1, 2), Vector2(2, 2)])
	room.enemy_spawns = PackedVector2Array([Vector2(8, 8), Vector2(9, 8)])
	room.doors = PackedVector2Array([Vector2(0, 5)])
	var path := "user://test_base_room.tres"
	_check(ResourceSaver.save(room, path) == OK, "room saves as text")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as RoomBase
	_check(loaded != null, "room loads back as RoomBase")
	if loaded != null:
		_check(loaded.id == &"start_room" and loaded.demo, "room keeps its id and demo flag")
		_check(loaded.player_spawns == room.player_spawns, "room keeps its player spawns")
		_check(loaded.enemy_spawns == room.enemy_spawns, "room keeps its enemy spawns")
		_check(loaded.doors == room.doors, "room keeps its doors")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_enemy_round_trip() -> void:
	var enemy := EnemyBase.new()
	enemy.id = &"ember_imp"
	enemy.max_health = 8
	enemy.move_speed = 60.0
	enemy.contact_damage = 2
	var path := "user://test_base_enemy.tres"
	_check(ResourceSaver.save(enemy, path) == OK, "enemy saves as text")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as EnemyBase
	_check(loaded != null, "enemy loads back as EnemyBase")
	if loaded != null:
		_check(loaded.id == &"ember_imp" and loaded.max_health == 8, "enemy keeps its id and health")
		_check(loaded.move_speed == 60.0 and loaded.contact_damage == 2, "enemy keeps its speed and damage")
		_check(loaded.scene == null, "enemy scene stays empty")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
