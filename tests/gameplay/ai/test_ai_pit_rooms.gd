extends "res://tests/support/suite.gd"
## A room with a pit never pins an enemy (crypt rework, docs/milestones/crypt-rework.md, rule 1). The
## AI has no pathfinder: it steers with `AISight.detour` and `walk_clear` (gameplay/ai/README.md), so
## a pit beside a pillar or against a room's edge is where steering could hold an enemy against its
## lip for good. For every room template the registry finds that has holes, each of its enemy spawns
## is played against a wizard standing at each of its player spawns and at each open spot round its
## pits (`_spots_round_pits`: where a fight is pushed to its lip), in the room's own walls, holes and
## standing props: a crypt mite (the crypt's swarmer, which has no staff and must walk all the way
## to touch) starts at the spawn, and the test fails if it does not come within its reach of the
## wizard in ten seconds (a far spot round a pit: in the time its way round takes, `WAY_ROUND`). It never falls on the way. A new room with a pit is covered by its folder.
const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const MiteData: EnemyBase = preload("res://content/enemies/crypt_mite/crypt_mite.tres")

## Ten seconds: the least time a chase has. A chase longer than the mite walks in it at its speed
## has `WAY_ROUND` times its straight walk (a way round the pillars, the sarcophagus and the pit).
const SECONDS: float = 10.0
const WAY_ROUND: float = 1.6
## Within its reach: a touch, the brain's least close reach (24 px, `AIBrain.reaches`) and a body's
## width between their middles.
const REACH: float = 24.0 + 16.0
## The spots round a pit a wizard is stood at: the middles of the 16 px cells this near a hole, where
## a wizard's body (`BODY`, a square round its middle) touches no wall, hole or prop's ground.
const NEAR_PIT: float = 48.0
const SPOT_CELL: float = 16.0
const BODY: float = 24.0

var fx: Fixture


func after_each() -> void:
	if fx != null:
		fx.free_all()
		fx = null


func test_the_rooms_with_a_pit_are_found() -> void:
	var rooms: Array[RoomBase] = _pit_rooms()
	check(rooms.size() >= 1, "a template has a pit (%d)" % rooms.size())
	for room in rooms:
		check(_spots_round_pits(room).size() >= 2, "%s: a wizard is stood round its pits (%d spots)" % [room.id, _spots_round_pits(room).size()])


func test_no_enemy_is_pinned_in_a_room_with_a_pit() -> void:
	for room: RoomBase in _pit_rooms():
		var places: RoomPlaces = room.places()
		var pinned: PackedStringArray = PackedStringArray()
		var targets: PackedVector2Array = places.player_spawns + _spots_round_pits(room)
		for enemy_at: Vector2 in places.enemy_spawns:
			for player_at: Vector2 in targets:
				var missed: String = _chase(room, enemy_at, player_at)
				if missed != "":
					pinned.append(missed)
		check(pinned.is_empty(), "%s: every enemy spawn reaches every player spawn and every spot round a pit in time; not: %s" % [room.id, "; ".join(pinned)])


## The open spots round `room`'s pits a wizard may stand at (see `NEAR_PIT`), in order.
func _spots_round_pits(room: RoomBase) -> PackedVector2Array:
	var layout: Node = own(room.scene.instantiate()) as Node
	var holes: Array[Rect2] = RoomPlaces.hole_rects(layout)
	var blocked: Array[Rect2] = RoomPlaces.wall_rects(layout) + holes
	var places: RoomPlaces = room.places()
	for i in places.of_kind(PropBase):
		var prop: PropBase = places.placed[i] as PropBase
		if prop.footprint_size.x > 0.0:
			blocked.append(Rect2(places.placed_at[i] + prop.footprint_offset - prop.footprint_size * 0.5, prop.footprint_size))
	var spots := PackedVector2Array()
	for y in range(0, int(places.size.y), int(SPOT_CELL)):
		for x in range(0, int(places.size.x), int(SPOT_CELL)):
			var middle := Vector2(x, y) + Vector2.ONE * SPOT_CELL * 0.5
			var body := Rect2(middle - Vector2.ONE * BODY * 0.5, Vector2.ONE * BODY)
			if not holes.any(func(hole: Rect2) -> bool: return hole.grow(NEAR_PIT).has_point(middle)):
				continue
			if not blocked.any(func(r: Rect2) -> bool: return r.intersects(body)):
				spots.append(middle)
	return spots


## Every template the registry finds whose layout has holes.
func _pit_rooms() -> Array[RoomBase]:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var found: Array[RoomBase] = []
	for room: RoomBase in RoomScan.templates(registry):
		if not RoomPlaces.hole_rects(own(room.scene.instantiate()) as Node).is_empty():
			found.append(room)
	return found


## A world of `room` (its walls, holes and props, as Flow lays them), a wizard standing still at
## `player_at` and a crypt mite at `enemy_at`, played up to ten seconds (or its way round's time). Empty when the mite came
## within its reach of the wizard and never fell; else what went wrong.
func _chase(room: RoomBase, enemy_at: Vector2, player_at: Vector2) -> String:
	if fx != null:
		fx.free_all()
	fx = Fixture.new(root)
	var layout: Node = own(room.scene.instantiate()) as Node
	var size: Vector2 = room.places().size
	var mgr: Fixture.ProjectileManagerScript = fx.projectiles
	mgr.set_bounds(Rect2(Vector2(-64.0, -64.0), size + Vector2(128.0, 128.0)))
	mgr.set_walls(RoomPlaces.wall_rects(layout))
	mgr.set_holes(RoomPlaces.hole_rects(layout))
	mgr.set_holes_outside(Rect2(Vector2.ZERO, size))
	_stand_props(room.places())
	var wizard: Actor = fx.players[0]
	wizard.position = player_at
	var mite: Actor = MiteData.scene.instantiate() as Actor
	Fixture.ai(mite).profile = MiteData.profile
	mite.data = MiteData
	mite.position = enemy_at
	fx.wire(mite)
	root.add_child(mite)
	mite.ticking = false
	fx.enemies.append(mite)
	var closest: float = INF
	var seconds: float = maxf(SECONDS, WAY_ROUND * enemy_at.distance_to(player_at) / MiteData.move_speed)
	for i in int(seconds / Fixture.STEP):
		mite.tick_step(Fixture.STEP)
		fx.combat.step(Fixture.STEP)
		fx.projectiles.step(Fixture.STEP)
		fx.board.step(Fixture.STEP)
		if mite.is_falling():
			return "%s to %s fell at %s" % [enemy_at, player_at, mite.global_position]
		closest = minf(closest, mite.global_position.distance_to(wizard.global_position))
		if closest <= REACH:
			return ""
	return "%s to %s held at %s after %.0f s (%.0f px off)" % [enemy_at, player_at, mite.global_position, seconds, closest]


## The room's placed props stood as Flow stands them (`RoomContents.make_body`), in this world: a
## pillar's ground stops a walk as the game's does.
func _stand_props(places: RoomPlaces) -> void:
	for i in places.of_kind(PropBase):
		var body: Actor = RoomContents.make_body(places.placed[i]) as Actor
		if body == null:
			continue
		body.position = places.placed_at[i]
		fx.wire(body)
		root.add_child(body)
		body.ticking = false
		fx.enemies.append(body)
