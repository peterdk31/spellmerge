extends "res://tests/support/suite.gd"
## A biome laid out (connected biomes CB2, `BiomeWorld`, docs/milestones/connected-biomes.md, step
## CB2): the hand-made test map's three crypt rooms and two bridges at their places in one world, the
## grid laid from them (walls, the dark between them, each joined lip cut open, the bridges, a mouth
## where each bridge meets a room). A wizard walks through all three rooms; a free enemy stops at the
## first mouth; a shot stops there; sight sees through it. The grid's layers are not state: a
## snapshot holds the map, and a world that laid another map lays the restored one again, the same
## to the byte. Real actors (the actor fixture), moved as the game moves them.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")

## Where the walkers start: in the antechamber, on a line over the bridges and clear of the rooms' walls
## (the nave's sarcophagus stands on its sockets' line).
const START: Vector2 = Vector2(480.0, 208.0)

var _world: Fixture
var _into: Node2D
var _biome: BiomeWorld


func before_each() -> void:
	super.before_each()
	_world = Fixture.new(root)
	_into = Node2D.new()
	root.add_child(_into)
	_biome = _biome_world(_into)


func after_each() -> void:
	_world.free_all()
	_into.free()
	super.after_each()


func _biome_world(into: Node2D) -> BiomeWorld:
	var biome := BiomeWorld.new()
	biome.registry = _world.registry
	biome.projectiles = _world.projectiles
	check_equal(biome.lay(into, BiomeMaps.walk_through(_world.registry)), PackedStringArray(), "the test map is laid")
	return biome


func _walker(at: Vector2, seat: int) -> Actor:
	var mind := Fixture.Scripted.new()
	mind.team = ActorsScript.TEAM_WIZARDS if seat >= 0 else ActorsScript.TEAM_ENEMIES
	mind.seat = seat
	mind.move = Vector2.RIGHT
	return _world.actor(at, [&"mover"], mind)


## Step `bodies` as the game moves them for `ticks` ticks.
func _walk(bodies: Array[Actor], ticks: int) -> void:
	for _i in ticks:
		for body: Actor in bodies:
			body.tick_step(Fixture.STEP)


## The joint where bridge `bridge` meets the room of its end `end`, in world pixels.
func _joint(bridge: int, end: int) -> Vector2:
	var map: BiomeMap = _biome.map
	var shape: PieceShape = map.room_shape(map.end_room(bridge, end), _biome.shapes_of(map))
	return map.room_places[map.end_room(bridge, end)] + shape.socket_at[map.end_socket(bridge, end)]


func test_the_biome_is_laid_at_its_places_under_one_grid() -> void:
	check_equal(_into.get_child_count(), 5, "three rooms and two bridges")
	check_equal((_biome.room_layout(1) as Node2D).position, _biome.map.room_places[1], "the nave at its place")
	check(_biome.room_layout(1).find_children("*", "RoomSocket", true, false).is_empty(), "its sockets taken out")
	var bounds: Rect2 = _world.projectiles.bounds()
	check(bounds.encloses(_biome.room_rect(2)) and bounds.encloses(_biome.room_rect(0)), "the grid covers the whole biome")
	var grid: RoomGrid = _world.projectiles.grid()
	var joint: Vector2 = _joint(0, 0)
	check(grid.is_mouth(joint + Vector2(4.0, 0.0)), "a mouth just out from the antechamber's socket")
	check(grid.is_mouth(_joint(0, 1) - Vector2(4.0, 0.0)) and grid.is_mouth(_joint(1, 0) + Vector2(4.0, 0.0)), "and at every end of every bridge")
	check(not grid.is_mouth(joint + Vector2(40.0, 0.0)), "the bridge's floor between them is open")
	check_equal(grid.cell_at(joint + Vector2(40.0, -48.0)), RoomGrid.ROOM_CELL, "the bridge's side is a wall")
	check_equal(grid.cell_at(Vector2(_biome.room_rect(0).end.x + 16.0, 20.0)), RoomGrid.ROOM_CELL, "the dark between two rooms is a wall")


func test_a_wizard_walks_through_the_three_rooms() -> void:
	var wizard: Actor = _walker(START, 0)
	var visited: Array[int] = []
	for _i in 400:
		_walk([wizard], 1)
		for room in _biome.map.rooms():
			if _biome.room_rect(room).has_point(wizard.global_position) and not visited.has(room):
				visited.append(room)
	check_equal(visited, [0, 1, 2] as Array[int], "it stood in every room in turn")
	check(wizard.global_position.x > _biome.room_rect(2).position.x + 400.0, "deep into the last room: %s" % wizard.global_position)
	check(absf(wizard.global_position.y - START.y) < 0.01, "straight along the bridges: %s" % wizard.global_position)


func test_a_free_enemy_stops_at_the_first_mouth() -> void:
	var free: Actor = _walker(START + Vector2(0.0, 8.0), -1)
	_walk([free], 120)
	var joint: Vector2 = _joint(0, 0)
	check(absf(free.global_position.x - (joint.x - free.wall_radius())) < 0.01, "its rim on the mouth: %s" % free.global_position)
	check(_biome.room_rect(0).has_point(free.global_position), "still in its room")


func test_a_shot_stops_at_a_mouth_and_sight_sees_through_it() -> void:
	var mgr: Fixture.ProjectilesScript = _world.projectiles
	var joint: Vector2 = _joint(0, 0)
	var shot: int = mgr.spawn(0, START, Vector2(400.0, 0.0), 3.0)
	for _i in 30:
		mgr.step(Fixture.STEP)
	check(not mgr.is_alive(shot), "the shot ended")
	check(mgr.wall_hits >= 1, "on a wall: the mouth")
	check(not mgr.grid().line_clear(START, joint + Vector2(60.0, 0.0)), "no line of fire over the bridge")
	check(mgr.grid().sight_clear(START, joint + Vector2(60.0, 0.0)), "sight goes on over it")


## The grid's layers are not state: what a snapshot holds of the biome is its map, a few hundred
## bytes, and a world that laid another map (or none) lays the restored one, the grid the same to the
## byte as the host's.
func test_a_world_restored_lays_the_restored_map_again() -> void:
	var grid_bytes: Dictionary = _grid_bytes(_world.projectiles.grid())
	var snapshot := Snapshot.take({"Projectiles": _world.projectiles, "Biome": _biome})
	check_equal(snapshot.problems, PackedStringArray(), "taken without problems")
	# Another world, with another biome laid (one room): the joining machine's, or a rollback across.
	var other_into := Node2D.new()
	root.add_child(other_into)
	var other := BiomeWorld.new()
	other.registry = _world.registry
	other.projectiles = _world.projectiles
	var one := BiomeMap.new()
	one.add_room(BiomeMaps.FIRST, Vector2.ZERO)
	one.work_out_depths()
	check_equal(other.lay(other_into, one), PackedStringArray(), "a one-room biome laid")
	check(_grid_bytes(_world.projectiles.grid()) != grid_bytes, "its grid differs")
	check_equal(snapshot.restore({"Projectiles": _world.projectiles, "Biome": other}), PackedStringArray(), "restored without problems")
	check(other.map.same_as(_biome.map), "the map is the snapshot's")
	check_equal(other_into.get_child_count(), 5, "its pieces laid again")
	check_equal(_grid_bytes(_world.projectiles.grid()), grid_bytes, "the grid laid again, the same to the byte")
	other_into.free()


func _grid_bytes(grid: RoomGrid) -> Dictionary:
	var out: Dictionary = {}
	for prop: Dictionary in grid.get_property_list():
		if (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			out[prop["name"]] = var_to_bytes(grid.get(prop["name"]))
	return out
