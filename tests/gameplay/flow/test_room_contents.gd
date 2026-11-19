extends "res://tests/support/suite.gd"
## A room's placed bodies (props W8c, `RoomContents`, gameplay/flow/room_contents.gd): a biome's later
## room stands its placed props with the world and keeps its placed enemies (a dummy, a stand-in) for
## when the room is entered (`stand_more` with no enemies, then `stand_enemies`; connected biomes
## CB8: they once stood at the run's start, awake, in a room nobody had come to).

const PROP: PropBase = preload("res://content/props/crypt_pillar/crypt_pillar.tres")
const IMP: EnemyBase = preload("res://content/enemies/ember_imp/ember_imp.tres")


func test_a_later_room_s_placed_enemies_stand_as_it_is_entered() -> void:
	var places := RoomPlaces.new()
	places.placed = [PROP, IMP] as Array[Resource]
	places.placed_at = PackedVector2Array([Vector2(100.0, 100.0), Vector2(200.0, 100.0)])
	var world: Node2D = own(Node2D.new()) as Node2D
	var contents := RoomContents.new()
	contents.stand_more(world, places, null, false)
	check_equal(contents.of_kind(PropBase).size(), 1, "its prop stands with the world")
	check(contents.of_kind(EnemyBase).is_empty(), "its placed enemy waits")
	var stood: Array[Node] = contents.stand_enemies(world, places)
	check_equal(stood.size(), 1, "entered: the enemy stands")
	check_equal((stood[0] as Node2D).position, Vector2(200.0, 100.0), "at its placement")
	check_equal(contents.of_kind(EnemyBase).size(), 1, "kept among the room's bodies")
	contents.stand_more(world, places, null)
	check_equal(contents.of_kind(EnemyBase).size(), 2, "with enemies (the start room), it stands at once")
