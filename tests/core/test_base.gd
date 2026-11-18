extends "res://tests/support/suite.gd"
## Tests for core/base: the spell, enemy and room base resources have their M1 fields with safe
## defaults and no demo flag, and a saved .tres keeps the values (one test per resource). A room's
## places are read from its scene (props W8a/W8c): each test builds a small layout (`_layout`, with
## `_add_piece` for a piece of scene that carries its own places) and checks one rule of
## `RoomPlaces.read`, `problems` or `strip`. A zone read by name, a zone with no name being a
## problem and `strip` taking the zones out are tests/content/rooms/test_room_places.gd's.

const SAVED: String = "user://test_base_resource.tres"

## The prop the fixture layout's stand-ins place.
var crate: PropBase


func before_each() -> void:
	crate = PropBase.new()
	crate.id = &"crate"


func after_each() -> void:
	if FileAccess.file_exists(SAVED):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVED))


## A layout (owned) with two player spawns in a holder moved to (100, 0), a crate's stand-in at
## (40, 50) and a zone "stone" in a holder moved to (10, 10).
func _layout() -> Node2D:
	var layout: Node2D = own(Node2D.new()) as Node2D
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
	stand_in.prop = crate
	stand_in.position = Vector2(40, 50)
	props.add_child(stand_in)
	var zones := Node2D.new()
	zones.name = "Zones"
	zones.position = Vector2(10, 10)
	layout.add_child(zones)
	var rect := RoomZone.new()
	rect.offset_right = 30
	rect.offset_bottom = 20
	rect.zone_name = &"stone"
	zones.add_child(rect)
	return layout


## A piece of scene at (200, 0) in `layout` carrying its own places: an enemy spawn at (3, 4) in an
## inner holder and a crate's stand-in at (10, 10).
func _add_piece(layout: Node2D) -> Node2D:
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
	deep.name = "Deep"
	deep.prop = crate
	deep.position = Vector2(10, 10)
	piece.add_child(deep)
	return piece


func _problems(layout: Node2D) -> PackedStringArray:
	return RoomPlaces.read(layout).problems()


func _saved_and_loaded(resource: Resource) -> Resource:
	check_equal(ResourceSaver.save(resource, SAVED), OK, "the resource saves as text")
	return ResourceLoader.load(SAVED, "", ResourceLoader.CACHE_MODE_IGNORE)


# The base resources.

func test_a_spell_holds_its_m1_fields() -> void:
	var spell := CarrierCard.new()
	spell.id = &"fire_bolt"
	spell.display_name = "Fire Bolt"
	spell.mana_cost = 5.0
	spell.wind_down = 0.4
	spell.base_damage = 3
	spell.speed = 220.0
	spell.lifetime = 1.5
	check(spell.id == &"fire_bolt" and spell.display_name == "Fire Bolt", "spell id and name")
	check(spell.mana_cost == 5.0 and spell.wind_down == 0.4, "spell cost and cooldown")
	check(spell.base_damage == 3 and spell.speed == 220.0 and spell.lifetime == 1.5, "spell damage, speed, lifetime")


func test_a_spell_id_is_empty_by_default() -> void:
	check_equal(CarrierCard.new().id, &"", "spell: id is empty by default")


func test_an_enemy_holds_its_m1_fields() -> void:
	var enemy := EnemyBase.new()
	enemy.id = &"ember_imp"
	enemy.max_health = 8
	enemy.move_speed = 60.0
	enemy.contact_damage = 1
	check(enemy.id == &"ember_imp" and enemy.max_health == 8, "enemy id and health")
	check(enemy.move_speed == 60.0 and enemy.contact_damage == 1, "enemy speed and contact damage")


func test_an_enemy_scene_is_empty_by_default() -> void:
	check(EnemyBase.new().scene == null, "enemy scene is empty by default")


func test_a_room_scene_is_empty_by_default() -> void:
	check(RoomBase.new().scene == null, "room scene is empty by default")


func test_no_base_resource_has_a_demo_flag() -> void:
	# There is no demo subset (owner, 2026-11-05): no base class carries a `demo` flag.
	check(not ("demo" in CarrierCard.new()), "spell: no demo flag")
	check(not ("demo" in EnemyBase.new()), "enemy: no demo flag")
	check(not ("demo" in RoomBase.new()), "room: no demo flag")


func test_a_saved_spell_keeps_its_values() -> void:
	var spell := CarrierCard.new()
	spell.id = &"fire_bolt"
	spell.base_damage = 4
	var loaded: CarrierCard = _saved_and_loaded(spell) as CarrierCard
	check(loaded != null, "spell loads back as CarrierCard")
	if loaded != null:
		check(loaded.id == &"fire_bolt" and loaded.base_damage == 4, "spell keeps its values")


func test_a_saved_room_keeps_its_values() -> void:
	var room := RoomBase.new()
	room.id = &"start_room"
	room.stand_up_after = 2.5
	room.ambient = 0.8
	room.shade = Color(0.8, 0.9, 1.0)
	var loaded: RoomBase = _saved_and_loaded(room) as RoomBase
	check(loaded != null, "room loads back as RoomBase")
	if loaded != null:
		check_equal(loaded.id, &"start_room", "room keeps its id")
		check(is_equal_approx(loaded.stand_up_after, 2.5) and is_equal_approx(loaded.ambient, 0.8) and loaded.shade.is_equal_approx(Color(0.8, 0.9, 1.0)), "room keeps its rules")


func test_a_saved_enemy_keeps_its_values() -> void:
	var enemy := EnemyBase.new()
	enemy.id = &"ember_imp"
	enemy.max_health = 8
	enemy.move_speed = 60.0
	enemy.contact_damage = 2
	var loaded: EnemyBase = _saved_and_loaded(enemy) as EnemyBase
	check(loaded != null, "enemy loads back as EnemyBase")
	if loaded != null:
		check(loaded.id == &"ember_imp" and loaded.max_health == 8, "enemy keeps its id and health")
		check(loaded.move_speed == 60.0 and loaded.contact_damage == 2, "enemy keeps its speed and damage")
		check(loaded.scene == null, "enemy scene stays empty")


# A room's places.

func test_a_room_without_a_scene_has_no_places() -> void:
	var places: RoomPlaces = RoomBase.new().places()
	check(places.player_spawns.is_empty() and places.zone(&"anything") == Rect2(), "no scene, no places")


func test_spawns_are_read_through_their_moved_holder() -> void:
	var places: RoomPlaces = RoomPlaces.read(_layout())
	check_equal(places.player_spawns, PackedVector2Array([Vector2(101, 5), Vector2(102, 5)]), "spawns through their moved holder")


func test_a_stand_in_places_its_prop_where_it_stands() -> void:
	var places: RoomPlaces = RoomPlaces.read(_layout())
	check(places.placed == ([crate] as Array[Resource]), "the stand-in's prop is placed")
	check_equal(places.placed_at, PackedVector2Array([Vector2(40, 50)]), "where the stand-in stands")


func test_the_fixture_layout_has_no_problems() -> void:
	var layout: Node2D = _layout()
	_add_piece(layout)
	check_equal(_problems(layout), PackedStringArray(), "the layout the other tests bend is sound")


func test_a_stand_in_with_no_prop_is_a_problem() -> void:
	var layout: Node2D = _layout()
	layout.get_node(^"Props").add_child(PropStandIn.new())
	check_equal(_problems(layout).size(), 1, "a stand-in with no prop is named: %s" % _problems(layout))


func test_spawns_inside_a_piece_are_found_at_any_depth() -> void:
	var layout: Node2D = _layout()
	_add_piece(layout)
	check_equal(RoomPlaces.read(layout).enemy_spawns, PackedVector2Array([Vector2(203, 4)]), "spawns at any depth")


func test_placements_are_found_at_any_depth_in_tree_order() -> void:
	var layout: Node2D = _layout()
	_add_piece(layout)
	check_equal(RoomPlaces.read(layout).placed_at, PackedVector2Array([Vector2(40, 50), Vector2(210, 10)]), "placements at any depth, in the tree's order")


func test_placements_are_picked_by_kind() -> void:
	var layout: Node2D = _layout()
	_add_piece(layout)
	var places: RoomPlaces = RoomPlaces.read(layout)
	check(places.placed_of(PropBase).size() == 2 and places.placed_of(EnemyBase).is_empty(), "by kind")


func test_places_under_a_rotated_piece_are_problems() -> void:
	# Places are whole translations: a place under a rotated or scaled node is a problem (its spawn
	# and its placement).
	var layout: Node2D = _layout()
	_add_piece(layout).rotation = 0.5
	check_equal(_problems(layout).size(), 2, "the spawn and the placement under a rotated piece are named: %s" % _problems(layout))


func test_places_under_a_mirrored_piece_are_problems() -> void:
	var layout: Node2D = _layout()
	_add_piece(layout).scale = Vector2(-1, 1)
	check_equal(_problems(layout).size(), 2, "the spawn and the placement under a mirrored piece are named: %s" % _problems(layout))


func test_turned_or_mirrored_art_with_no_place_under_it_is_no_problem() -> void:
	var layout: Node2D = _layout()
	_add_piece(layout)
	var art := Sprite2D.new()
	art.rotation = 1.0
	art.scale = Vector2(-1, 1)
	art.add_child(Sprite2D.new())
	layout.add_child(art)
	check_equal(_problems(layout), PackedStringArray(), "turned or mirrored art with no place under it is free")


func test_a_moved_layout_root_is_a_problem() -> void:
	# The room starts at (0, 0) (the world draws its bodies by their feet, the layout as one piece at
	# its own place).
	var layout: Node2D = _layout()
	_add_piece(layout)
	layout.position = Vector2(0, 40)
	check_equal(_problems(layout).size(), 1, "a moved root is named: %s" % _problems(layout))


func test_places_above_the_corner_are_problems() -> void:
	var layout: Node2D = _layout()
	_add_piece(layout).position = Vector2(200, -30)
	check_equal(_problems(layout).size(), 2, "a spawn and a placement above the corner, each named: %s" % _problems(layout))


func test_places_left_of_the_corner_are_problems() -> void:
	var layout: Node2D = _layout()
	_add_piece(layout).position = Vector2(-220, 0)
	check_equal(_problems(layout).size(), 2, "a spawn and a placement left of the corner, each named: %s" % _problems(layout))


func test_strip_takes_out_every_placement_at_any_depth() -> void:
	var layout: Node2D = _layout()
	var deep: Node = _add_piece(layout).get_node(^"Deep")
	RoomPlaces.strip(layout)
	check(layout.find_children("*", "RoomPlacement", true, false).is_empty(), "every placement taken out")
	check(not is_instance_valid(deep), "the one deep in a piece too")


func test_strip_keeps_the_spawns() -> void:
	var layout: Node2D = _layout()
	_add_piece(layout)
	RoomPlaces.strip(layout)
	check(layout.get_node_or_null(^"PlayerSpawns") != null, "the spawns kept")
