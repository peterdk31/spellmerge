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
	_test_no_demo_flag()
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
	var spell := CarrierCard.new()
	spell.id = &"fire_bolt"
	spell.display_name = "Fire Bolt"
	spell.mana_cost = 5.0
	spell.wind_down = 0.4
	spell.base_damage = 3
	spell.speed = 220.0
	spell.lifetime = 1.5
	_check(spell.id == &"fire_bolt" and spell.display_name == "Fire Bolt", "spell id and name")
	_check(spell.mana_cost == 5.0 and spell.wind_down == 0.4, "spell cost and cooldown")
	_check(spell.base_damage == 3 and spell.speed == 220.0 and spell.lifetime == 1.5, "spell damage, speed, lifetime")


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
	_check(room.scene == null, "room scene is empty by default")
	_check(room.places().player_spawns.is_empty() and room.places().zone(&"anything") == Rect2(), "no scene, no places")
	_test_room_places()


## A room's places are read from its scene (props W8a): markers in their holders (through a moved
## parent), stand-ins (`PropStandIn`) with their data, zones by name; a stand-in or zone with no data is a problem,
## and `strip` takes the editor's nodes out.
func _test_room_places() -> void:
	var layout := Node2D.new()
	var spawns := Node2D.new()
	spawns.name = "PlayerSpawns"
	spawns.position = Vector2(100, 0)
	layout.add_child(spawns)
	for x: float in [1.0, 2.0]:
		var marker := Marker2D.new()
		marker.position = Vector2(x, 5)
		spawns.add_child(marker)
	var props := Node2D.new()
	props.name = "Props"
	layout.add_child(props)
	var stand_in := PropStandIn.new()
	var data := PropBase.new()
	data.id = &"crate"
	stand_in.prop = data
	stand_in.position = Vector2(40, 50)
	props.add_child(stand_in)
	props.add_child(PropStandIn.new())
	var zones := Node2D.new()
	zones.name = "Zones"
	zones.position = Vector2(10, 10)
	layout.add_child(zones)
	var rect := RoomZone.new()
	rect.offset_left = 0
	rect.offset_top = 0
	rect.offset_right = 30
	rect.offset_bottom = 20
	rect.zone_name = &"stone"
	zones.add_child(rect)
	zones.add_child(RoomZone.new())
	var places: RoomPlaces = RoomPlaces.read(layout)
	_check(places.player_spawns == PackedVector2Array([Vector2(101, 5), Vector2(102, 5)]), "spawns through their moved holder: %s" % places.player_spawns)
	_check(places.placed == ([data] as Array[Resource]) and places.placed_at == PackedVector2Array([Vector2(40, 50)]), "a stand-in's prop where it stands")
	_check(places.zone(&"stone") == Rect2(10, 10, 30, 20), "a zone by name: %s" % places.zone(&"stone"))
	_check(places.problems().size() == 2, "a stand-in with no prop and a zone with no name: %s" % places.problems())
	# A piece of scene carries its own (props W8c): a placement and spawns deep inside it.
	var piece := Node2D.new()
	piece.position = Vector2(200, 0)
	layout.add_child(piece)
	var inner := Node2D.new()
	inner.name = "EnemySpawns"
	piece.add_child(inner)
	var marker := Marker2D.new()
	marker.position = Vector2(3, 4)
	inner.add_child(marker)
	var deep := PropStandIn.new()
	deep.prop = data
	deep.position = Vector2(10, 10)
	piece.add_child(deep)
	places = RoomPlaces.read(layout)
	_check(places.enemy_spawns == PackedVector2Array([Vector2(203, 4)]), "spawns at any depth: %s" % places.enemy_spawns)
	_check(places.placed_at == PackedVector2Array([Vector2(40, 50), Vector2(210, 10)]), "placements at any depth, in the tree's order: %s" % places.placed_at)
	_check(places.placed_of(PropBase).size() == 2 and places.placed_of(EnemyBase).is_empty(), "by kind")
	# Places are whole translations: a place under a rotated or scaled node is a problem (its spawn
	# and its placement), art with nothing placed under it is not.
	piece.rotation = 0.5
	_check(RoomPlaces.read(layout).problems().size() == 4, "the places under a rotated piece are named: %s" % RoomPlaces.read(layout).problems())
	piece.rotation = 0.0
	piece.scale = Vector2(-1, 1)
	_check(RoomPlaces.read(layout).problems().size() == 4, "and under a mirrored one")
	piece.scale = Vector2.ONE
	var art := Sprite2D.new()
	art.rotation = 1.0
	art.scale = Vector2(-1, 1)
	art.add_child(Sprite2D.new())
	layout.add_child(art)
	_check(RoomPlaces.read(layout).problems().size() == 2, "turned or mirrored art with no place under it is free: %s" % RoomPlaces.read(layout).problems())
	RoomPlaces.strip(layout)
	_check(layout.find_children("*", "RoomPlacement", true, false).is_empty() and not is_instance_valid(deep), "every placement taken out, at any depth")
	_check(layout.find_children("*", "RoomZone", true, false).is_empty(), "every zone taken out")
	_check(layout.get_node_or_null("PlayerSpawns") != null, "the spawns kept")
	layout.free()


func _test_no_demo_flag() -> void:
	# There is no demo subset (owner, 2026-11-05): no base class carries a `demo` flag.
	_check(not ("demo" in CarrierCard.new()), "spell: no demo flag")
	_check(not ("demo" in EnemyBase.new()), "enemy: no demo flag")
	_check(not ("demo" in RoomBase.new()), "room: no demo flag")
	_check(CarrierCard.new().id == &"", "spell: id is empty by default")


func _test_round_trip() -> void:
	var spell := CarrierCard.new()
	spell.id = &"fire_bolt"
	spell.base_damage = 4
	var path := "user://test_base_spell.tres"
	_check(ResourceSaver.save(spell, path) == OK, "spell saves as text")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as CarrierCard
	_check(loaded != null, "spell loads back as CarrierCard")
	if loaded != null:
		_check(loaded.id == &"fire_bolt" and loaded.base_damage == 4, "spell keeps its values")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_room_round_trip() -> void:
	var room := RoomBase.new()
	room.id = &"start_room"
	room.invincible = true
	room.ambient = 0.8
	var path := "user://test_base_room.tres"
	_check(ResourceSaver.save(room, path) == OK, "room saves as text")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as RoomBase
	_check(loaded != null, "room loads back as RoomBase")
	if loaded != null:
		_check(loaded.id == &"start_room", "room keeps its id")
		_check(loaded.invincible and is_equal_approx(loaded.ambient, 0.8), "room keeps its rules")
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
