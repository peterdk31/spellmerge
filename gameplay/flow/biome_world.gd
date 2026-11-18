class_name BiomeWorld
extends RefCounted
## A biome laid out (connected biomes CB2, docs/milestones/connected-biomes.md, "The model"): every
## room and bridge of its map (`BiomeMap`, the state) at its place in one world, and the projectile
## manager's grid laid from them, its bounds the whole biome's. Flow's, as its room's contents are
## (`RoomContents`); the row run lays no biome (CB8 switches the crypt over).
##
## **What is laid** (`lay`): each piece's layout (`RoomBase.build`, its placements, zones and sockets
## taken out, `RoomPlaces.strip`) at its place, rooms first, under everything else in the world; then
## the grid: every piece's walls and holes (mirrored as the map says, `PieceShape`), the dark between
## the pieces a wall (`RoomGrid.wall_outside`: nothing stands or flies there), each joined room socket
## cut open to its edge (`PieceShape.cut_rect`, `RoomGrid.cut`), the bridges' walls and holes over
## it, and a mouth where each bridge meets a room (`PieceShape.mouth_rect`, `RoomGrid.add_mouth`):
## shots stop there, a wizard walks through, a free enemy does not. A bridge's mouth is the doorway
## (decision 11).
##
## **Not state but the map** (connected biomes CB2, "The wall grid"): the nodes and the grid's layers
## are laid again from the map, never saved. After a snapshot (`rebuild_derived`) a world whose map
## differs from the one it laid (a joining machine, a snapshot of another biome) lays the restored
## map; the same map is left as it lies (the grid's layers are the restored world's own, `RoomGrid`).
##
## **Mirroring** (decision 6) is the map's and the collision's: a mirrored piece's walls, holes and
## sockets are mirrored in whole cells. Its art is shown flipped as a stand-in until the ground is
## drawn at layout from the mirrored shape (CB4); the art never reaches the simulation.
##
## Rooms' contents (props, enemies, items), room state and room events are room life's (CB3).

const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## The rooms' registry folder.
const ROOM_FOLDER: StringName = &"rooms"
## Extra room round the biome where shots may still fly, in pixels (Flow's PROJECTILE_MARGIN).
const MARGIN: float = 32.0
## What a laid piece's layout node is named: `Room<n>` and `Bridge<n>` (a world names its nodes the
## same on every machine).
const ROOM_NODE: String = "Room%d"
const BRIDGE_NODE: String = "Bridge%d"

## Not state: services, the world laid into, the nodes laid and the map they were laid from (a copy),
## and the templates' shapes (a cache), all laid again from the map (see the class doc).
const DERIVED: Array[StringName] = [&"registry", &"projectiles", &"_into", &"_layouts", &"_laid", &"_shapes"]

var registry: RegistryScript = null
var projectiles: ProjectileManagerScript = null
## The biome's map (null: none laid). The state.
var map: BiomeMap = null
var _into: Node2D = null
var _layouts: Array[Node] = []
var _laid: BiomeMap = null
var _shapes: Dictionary = {}


## Lay `new_map` into `into` (the world), replacing any biome laid before: the map is kept as the
## state, its pieces and the grid laid from it. Returns the map's problems (`BiomeMap.problems`); a
## map with problems is not laid (nothing is, and `map` is null).
func lay(into: Node2D, new_map: BiomeMap) -> PackedStringArray:
	_into = into
	var problems: PackedStringArray = new_map.problems(shapes_of(new_map)) if new_map != null else PackedStringArray(["No map."])
	if not problems.is_empty():
		clear()
		return problems
	map = new_map
	_lay_now()
	return problems


## Take the biome's pieces out of the world and forget its map (the grid is the next room's to lay).
func clear() -> void:
	for layout: Node in _layouts:
		if is_instance_valid(layout):
			if layout.get_parent() != null:
				layout.get_parent().remove_child(layout)
			layout.queue_free()
	_layouts.clear()
	_laid = null
	map = null


## After a snapshot was restored (core/sim/README.md, "Snapshots"): a world that laid another map, or
## none, lays the restored one (see the class doc).
func rebuild_derived() -> void:
	if _into == null or not is_instance_valid(_into):
		return
	if map == null:
		if _laid != null:
			clear()
		return
	if _laid == null or not _laid.same_as(map):
		_lay_now()


## The layout node of room `room` (null when none is laid).
func room_layout(room: int) -> Node:
	return _layouts[room] if map != null and room >= 0 and room < map.rooms() and room < _layouts.size() else null


## The unmirrored shape of every template `of_map` names (template id to `PieceShape`), from the
## registry; a template the registry lacks is left out (the map's problems name it).
func shapes_of(of_map: BiomeMap) -> Dictionary:
	var ids: Array[StringName] = []
	if of_map != null:
		ids.append_array(of_map.room_templates)
		ids.append_array(of_map.bridge_templates)
	for id: StringName in ids:
		if _shapes.has(id):
			continue
		var room: RoomBase = registry.get_resource(ROOM_FOLDER, id) as RoomBase if registry != null else null
		var shape: PieceShape = PieceShape.of_room(room)
		if shape != null:
			_shapes[id] = shape
	return _shapes


## The world rectangle of room `room` and of bridge `bridge` in the map laid (empty when none).
func room_rect(room: int) -> Rect2:
	var shape: PieceShape = map.room_shape(room, _shapes) if map != null else null
	return shape.rect_at(map.room_places[room]) if shape != null else Rect2()


func bridge_rect(bridge: int) -> Rect2:
	var shape: PieceShape = map.bridge_shape(bridge, _shapes) if map != null else null
	return shape.rect_at(map.bridge_places[bridge]) if shape != null else Rect2()


## The world's bounds for the biome: every piece, and MARGIN round them.
func bounds() -> Rect2:
	var whole := Rect2()
	var first: bool = true
	for room in map.rooms():
		whole = room_rect(room) if first else whole.merge(room_rect(room))
		first = false
	for bridge in map.bridges():
		whole = whole.merge(bridge_rect(bridge))
	return whole.grow(MARGIN)


## Lay the map's pieces and the grid (the class doc).
func _lay_now() -> void:
	for layout: Node in _layouts:
		if is_instance_valid(layout):
			if layout.get_parent() != null:
				layout.get_parent().remove_child(layout)
			layout.queue_free()
	_layouts.clear()
	shapes_of(map)
	var at: int = 0
	for room in map.rooms():
		_layouts.append(_place(ROOM_NODE % room, map.room_templates[room], map.room_places[room], map.room_mirrors[room], at))
		at += 1
	for bridge in map.bridges():
		_layouts.append(_place(BRIDGE_NODE % bridge, map.bridge_templates[bridge], map.bridge_places[bridge], map.bridge_mirrors[bridge], at))
		at += 1
	_lay_grid()
	_laid = map.copy()


## One piece's layout, at `place` in the world, as the `index`-th child (null when its template is
## missing: the map's problems name it).
func _place(named: String, template: StringName, place: Vector2, mirror: int, index: int) -> Node:
	var room: RoomBase = registry.get_resource(ROOM_FOLDER, template) as RoomBase if registry != null else null
	var layout: Node = room.build() if room != null else null
	if layout == null:
		return null
	RoomPlaces.strip(layout)
	layout.name = named
	var shape: PieceShape = _shapes.get(template) as PieceShape
	var piece := layout as Node2D
	if piece != null:
		# The art's stand-in for a mirrored piece (view only; the ground is drawn mirrored at layout
		# from CB4): flipped about its own middle.
		var flip := Vector2(-1.0 if (mirror & PieceShape.MIRROR_X) != 0 else 1.0, -1.0 if (mirror & PieceShape.MIRROR_Y) != 0 else 1.0)
		piece.scale = flip
		piece.position = place + Vector2(shape.size.x if flip.x < 0.0 else 0.0, shape.size.y if flip.y < 0.0 else 0.0)
	if _into != null:
		_into.add_child(layout)
		_into.move_child(layout, mini(index, _into.get_child_count() - 1))
	return layout


## Lay the grid from the map (the class doc), over the biome's bounds.
func _lay_grid() -> void:
	if projectiles == null:
		return
	projectiles.set_bounds(bounds())
	var grid: RoomGrid = projectiles.grid()
	var pieces: Array[Rect2] = []
	for room in map.rooms():
		var shape: PieceShape = map.room_shape(room, _shapes)
		_lay_piece(grid, shape, map.room_places[room])
		pieces.append(room_rect(room))
	for bridge in map.bridges():
		pieces.append(bridge_rect(bridge))
	grid.wall_outside(pieces)
	for bridge in map.bridges():
		for end in 2:
			var room: int = map.end_room(bridge, end)
			var shape: PieceShape = map.room_shape(room, _shapes)
			grid.cut(_moved(shape.cut_rect(map.end_socket(bridge, end)), map.room_places[room]))
	for bridge in map.bridges():
		_lay_piece(grid, map.bridge_shape(bridge, _shapes), map.bridge_places[bridge])
	for bridge in map.bridges():
		for end in 2:
			var room: int = map.end_room(bridge, end)
			var shape: PieceShape = map.room_shape(room, _shapes)
			grid.add_mouth(_moved(shape.mouth_rect(map.end_socket(bridge, end)), map.room_places[room]))


func _lay_piece(grid: RoomGrid, shape: PieceShape, place: Vector2) -> void:
	for rect: Rect2 in shape.walls:
		grid.add_wall(_moved(rect, place))
	for rect: Rect2 in shape.holes:
		grid.add_hole(_moved(rect, place))


static func _moved(rect: Rect2, by: Vector2) -> Rect2:
	return Rect2(rect.position + by, rect.size)
