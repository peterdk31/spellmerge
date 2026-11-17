extends "res://tests/support/suite.gd"
## Every room template's layout (content/rooms: arena_01 and every room a run's map can pick, found
## by folder), about where things are and what can be reached, never about how a room looks: spawns
## lie inside the room and clear of walls, the doors sit in the border, and every spawn can be
## reached from the first player spawn.

const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
## Clearance a spawn needs around it (a wizard is about 12 px wide).
const SPAWN_RADIUS: float = 12.0
const TILE: float = 32.0
## The part of an exit's area a wizard walks into, from its bottom: a wizard's height and a half.
const EXIT_FOOT: float = 24.0
## The walls' grid (the projectile manager's `WALL_CELL`), on which the reach is flooded.
const CELL: float = 8.0
const STEPS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var templates: Array[RoomBase] = []
var registry: RegistryScript
## Each template's layout (one instance), wall rectangles and extent, by id.
var layouts: Dictionary[StringName, Node] = {}
var walls_of: Dictionary[StringName, Array] = {}
var bounds_of: Dictionary[StringName, Rect2] = {}


func before_each() -> void:
	registry = own(RegistryScript.new()) as RegistryScript
	registry.scan()
	templates = RoomScan.templates(registry)
	layouts.clear()
	walls_of.clear()
	bounds_of.clear()
	for room in templates:
		var layout: Node = own(room.scene.instantiate()) as Node
		layouts[room.id] = layout
		walls_of[room.id] = RoomScan.wall_rects(layout)
		bounds_of[room.id] = RoomScan.wall_bounds(layout)


func _walls(room: RoomBase) -> Array[Rect2]:
	var found: Array[Rect2] = []
	found.assign(walls_of[room.id])
	return found


func _bounds(room: RoomBase) -> Rect2:
	return bounds_of[room.id]


func _spawns(room: RoomBase) -> PackedVector2Array:
	return room.places().player_spawns + room.places().enemy_spawns


func test_the_templates_are_found() -> void:
	check(templates.size() >= 4, "arena_01 and the crypt's other fight rooms are found (%d)" % templates.size())


func test_scenes_have_no_scripts() -> void:
	for room in templates:
		check_equal(RoomScan.scripts_below(layouts[room.id]), 0, "%s: scripts in the scene" % room.id)


func test_spawn_groups_hold_only_markers() -> void:
	for room in templates:
		for group: String in ["PlayerSpawns", "EnemySpawns", "Doors"]:
			check(RoomScan.only_markers(layouts[room.id], group), "%s: %s holds only Marker2D nodes" % [room.id, group])


func test_every_room_has_walls() -> void:
	for room in templates:
		check(_walls(room).size() >= 4, "%s has at least its four border walls" % room.id)


func test_spawns_are_inside_the_room() -> void:
	for room in templates:
		var inside: Rect2 = _bounds(room)
		for point in _spawns(room):
			check(inside.has_point(point), "%s: spawn %s is inside the room" % [room.id, point])


func test_spawns_are_clear_of_walls() -> void:
	for room in templates:
		var walls: Array[Rect2] = _walls(room)
		for point in _spawns(room):
			var body: Rect2 = Rect2(point - Vector2.ONE * SPAWN_RADIUS, Vector2.ONE * SPAWN_RADIUS * 2.0)
			for wall in walls:
				check(not wall.intersects(body), "%s: spawn %s is clear of the wall %s" % [room.id, point, wall])


func test_spawns_do_not_overlap() -> void:
	for room in templates:
		var spawns: PackedVector2Array = _spawns(room)
		for i in range(spawns.size()):
			for j in range(i + 1, spawns.size()):
				check(spawns[i].distance_to(spawns[j]) >= SPAWN_RADIUS * 2.0, "%s: spawns %s and %s overlap" % [room.id, spawns[i], spawns[j]])


func test_doors_lie_on_the_border() -> void:
	for room in templates:
		var size: Vector2 = _bounds(room).end
		check(room.places().doors.size() >= 1, "%s has a door" % room.id)
		for door in room.places().doors:
			var on_border: bool = door.x < TILE or door.y < TILE or door.x > size.x - TILE or door.y > size.y - TILE
			check(on_border, "%s: door %s lies on the border" % [room.id, door])


## Where each exit is stood on (a prop of the role `room_exit`, run generation RG4): its foot (the
## lowest `EXIT_FOOT` pixels of its area, where a wizard walks in) open floor clear of every wall,
## its whole area inside the room and clear of every spawn, so a wizard can step in and nobody
## starts in a way on. Above its foot an exit may rise over the edge: a crypt gate stands against a
## floating room's north edge, its arch over the dark (crypt rework CR-G).
func test_exits_are_open_floor_clear_of_spawns() -> void:
	for room in templates:
		var places: RoomPlaces = room.places()
		var props: Array[Resource] = places.placed_of(PropBase)
		var at: PackedVector2Array = places.placed_at_of(PropBase)
		for i in props.size():
			var prop: PropBase = props[i] as PropBase
			if prop.role != RoomBase.EXIT_ROLE:
				continue
			var area: Rect2 = prop.area_rect()
			area.position += at[i]
			check(_bounds(room).encloses(area), "%s: the exit at %s is inside the room" % [room.id, at[i]])
			var foot: Rect2 = Rect2(area.position.x, area.end.y - EXIT_FOOT, area.size.x, minf(EXIT_FOOT, area.size.y))
			for wall in _walls(room):
				check(not wall.intersects(foot), "%s: the exit at %s is walked into from open floor, clear of the wall %s" % [room.id, at[i], wall])
			for point in _spawns(room):
				check(not area.grow(SPAWN_RADIUS).has_point(point), "%s: the spawn %s is clear of the exit at %s" % [room.id, point, at[i]])


## No one starts in a prop: every spawn is clear of every prop the room stands (its hurt shape, its
## ground and its touch area: `_prop_box`), by a wizard's clearance.
func test_spawns_are_clear_of_props() -> void:
	for room in templates:
		var places: RoomPlaces = room.places()
		var props: Array[Resource] = places.placed_of(PropBase)
		var at: PackedVector2Array = places.placed_at_of(PropBase)
		for i in props.size():
			var box: Rect2 = _prop_box(props[i] as PropBase, at[i])
			for point in _spawns(room):
				check(not box.grow(SPAWN_RADIUS).has_point(point), "%s: the spawn %s is clear of the %s at %s" % [room.id, point, (props[i] as PropBase).id, at[i]])


## A room that hosts a boss stands it at its first enemy spawn (Flow, in turn): every boss of the
## room's biome at any depth (found by folder; none, nothing to check) fits there, its
## body (hurt shape and ground, at its data's `size`) inside the room and clear of every wall and
## every prop it stands.
func test_a_boss_room_holds_its_biomes_bosses_at_its_first_enemy_spawn() -> void:
	var content: RunContent = registry.run_content()
	for room in templates:
		if not room.hosts(&"boss"):
			continue
		var places: RoomPlaces = room.places()
		check(not places.enemy_spawns.is_empty(), "%s hosts a boss: it has an enemy spawn" % room.id)
		if places.enemy_spawns.is_empty():
			continue
		var props: Array[Resource] = places.placed_of(PropBase)
		var props_at: PackedVector2Array = places.placed_at_of(PropBase)
		for boss: EnemyBase in _bosses_of(content, room.biome):
			var body: Rect2 = _body_box(boss)
			body.position += places.enemy_spawns[0]
			check(_bounds(room).grow(-TILE).encloses(body), "%s: %s at %s is inside the walls" % [room.id, boss.id, places.enemy_spawns[0]])
			for wall in _walls(room):
				check(not wall.intersects(body), "%s: %s at %s is clear of the wall %s" % [room.id, boss.id, places.enemy_spawns[0], wall])
			for i in props.size():
				var box: Rect2 = _prop_box(props[i] as PropBase, props_at[i])
				check(not box.intersects(body), "%s: %s at %s is clear of the %s at %s" % [room.id, boss.id, places.enemy_spawns[0], (props[i] as PropBase).id, props_at[i]])


## Every boss that names biome `biome` (`EnemyBase.biomes`), whatever depth it may first stand at:
## a boss stands in a run's last row, deeper than any `min_depth`.
func _bosses_of(content: RunContent, biome: StringName) -> Array[EnemyBase]:
	var found: Array[EnemyBase] = []
	for enemy: EnemyBase in content.enemies:
		if enemy.boss and enemy.biomes.has(biome):
			found.append(enemy)
	return found


## What a prop standing at `at` takes up: its hurt shape and ground (`PropBase.extent`) and where a
## body touches it (`area_rect`: a body starting in a dust heap's would scatter it at once).
func _prop_box(prop: PropBase, at: Vector2) -> Rect2:
	var box: Rect2 = prop.extent()
	var area: Rect2 = prop.area_rect()
	if area.has_area():
		box = box.merge(area)
	box.position += at
	return box


## The box round a body's feet its hurt shape and its ground take up, as its scene sets them (its
## `Hurtbox` and `Footprint` components, found by type as the actor finds them; a scene with no
## footprint gets the kit's default circle, `Footprint`'s own), times its data's `size`
## (`Actor.set_size`).
func _body_box(data: EnemyBase) -> Rect2:
	var scene: Node = own(data.scene.instantiate()) as Node
	var hurtbox: Hurtbox = null
	var footprint: Footprint = null
	for child: Node in scene.get_children():
		if child is Hurtbox and hurtbox == null:
			hurtbox = child as Hurtbox
		elif child is Footprint and footprint == null:
			footprint = child as Footprint
	if footprint == null:
		footprint = own(Footprint.new()) as Footprint
	var box: Rect2 = _shape_box(footprint.size, footprint.radius, footprint.offset)
	if hurtbox != null:
		box = box.merge(_shape_box(hurtbox.size, hurtbox.radius, hurtbox.offset))
	var scale: float = data.size if data.size > 0.0 else 1.0
	return Rect2(box.position * scale, box.size * scale)


## A box `size` across, or a circle of `radius`'s bounds, round `offset`.
func _shape_box(size: Vector2, radius: float, offset: Vector2) -> Rect2:
	var half: Vector2 = size * 0.5 if size.x > 0.0 and size.y > 0.0 else Vector2(radius, radius)
	return Rect2(offset - half, half * 2.0)


## A template a run may pick for a room that leads on has an exit for each way a room may lead
## (`MapRules.most_ways`): with fewer the generator never picks it there (RG4), so it would stand
## only for a last room.
func test_templates_have_exits_for_every_way_on() -> void:
	var checked: int = 0
	for res: Resource in registry.get_all(&"runs"):
		for rules: MapRules in (res as RunDefinition).biomes:
			for rule: KindRule in rules.kinds:
				if not _leads_on(rules, rule):
					continue
				for room in templates:
					if room.biome == rules.biome and room.kinds.has(rule.kind):
						checked += 1
						check(room.exit_count() >= rules.most_ways(), "%s hosts %s in %s, which leads on to %d rooms: it has %d exits" % [room.id, rule.kind, rules.biome, rules.most_ways(), room.exit_count()])
	check(checked >= 4, "the crypt's fight rooms are checked (%d)" % checked)


## True if a room of `rule`'s kind may stand in a row before the last at some depth of `rules`.
func _leads_on(rules: MapRules, rule: KindRule) -> bool:
	for depth in range(rules.depth_min, rules.depth_max + 1):
		for row in depth - 1:
			if rule.takes_row(row, depth):
				return true
	return false


## Flood fill on the 8 px wall grid from the first player spawn, through the cells a wizard fits
## in (no wall or hole within a cell of it: the walls of a room drawn from a shape are 8 px steps,
## and a gap narrower than a wizard must not count as a way; crypt rework CR2). So every way a
## room's party takes is at least three cells (24 px) wide.
func test_every_spawn_can_be_reached() -> void:
	for room in templates:
		var blocked: Dictionary = _blocked_cells(room)
		var seen: Dictionary = _flood(room, blocked, _cell(room.places().player_spawns[0]))
		for point in _spawns(room):
			check(seen.has(_cell(point)), "%s: spawn %s can be reached from the first player spawn" % [room.id, point])


## No floor a wizard fits on is shut off from the party: a pocket nobody can walk into is a place an
## enemy could be pushed into and never reached, and a pit never cuts a room in two.
func test_every_floor_cell_can_be_reached() -> void:
	for room in templates:
		var blocked: Dictionary = _blocked_cells(room)
		var seen: Dictionary = _flood(room, blocked, _cell(room.places().player_spawns[0]))
		var grid: Vector2i = _grid(room)
		for y in grid.y:
			for x in grid.x:
				var cell := Vector2i(x, y)
				if _fits(blocked, cell):
					check(seen.has(cell), "%s: the floor at %s can be reached" % [room.id, Vector2(cell) * CELL])
				elif not blocked.has(cell):
					# Open floor too narrow to stand in (beside a wall or a pit): a wizard reaching the
					# cells round it reaches it, so no narrow pocket is left out of the flood.
					check(_beside(seen, cell), "%s: the narrow floor at %s lies beside floor the party reaches" % [room.id, Vector2(cell) * CELL])


func _flood(room: RoomBase, blocked: Dictionary, start: Vector2i) -> Dictionary:
	var grid: Vector2i = _grid(room)
	var seen: Dictionary = {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step in STEPS:
			var next: Vector2i = cell + step
			if next.x < 0 or next.y < 0 or next.x >= grid.x or next.y >= grid.y or seen.has(next):
				continue
			if _fits(blocked, next):
				seen[next] = true
				queue.append(next)
	return seen


## The 8 px cells whose middle lies in a wall or a hole.
func _blocked_cells(room: RoomBase) -> Dictionary:
	var found: Dictionary = {}
	var rects: Array[Rect2] = _walls(room) + RoomPlaces.hole_rects(layouts[room.id])
	for rect in rects:
		for y in range(floori(rect.position.y / CELL), ceili(rect.end.y / CELL)):
			for x in range(floori(rect.position.x / CELL), ceili(rect.end.x / CELL)):
				if rect.has_point((Vector2(x, y) + Vector2(0.5, 0.5)) * CELL):
					found[Vector2i(x, y)] = true
	return found


## True when a cell round `cell` (or `cell` itself) is in `seen`.
func _beside(seen: Dictionary, cell: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if seen.has(cell + Vector2i(dx, dy)):
				return true
	return false


## True when a wizard fits in `cell`: no wall or hole in it or in the cells round it.
func _fits(blocked: Dictionary, cell: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if blocked.has(cell + Vector2i(dx, dy)):
				return false
	return true


func _grid(room: RoomBase) -> Vector2i:
	var size: Vector2 = _bounds(room).end
	return Vector2i(int(size.x / CELL), int(size.y / CELL))


func _cell(point: Vector2) -> Vector2i:
	return Vector2i(int(point.x / CELL), int(point.y / CELL))
