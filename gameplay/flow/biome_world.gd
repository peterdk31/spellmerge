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
## map over the restored bounds, touching no state; the same map is left as it lies (the grid's layers
## are the restored world's own, `RoomGrid`). A map with problems is not laid (`lay`), and the grid
## keeps whatever was laid before.
##
## **Mirroring** (decision 6) is the map's and the collision's: a mirrored piece's walls, holes and
## sockets are mirrored in whole cells. Its layout says how it is placed (`PieceShape.GROUND_MIRROR_META`)
## for Feel, which draws a room's ground from its mirrored shape as it hears the room built (CB4);
## the pieces are announced to the view with CB3's room events, so until then a mirrored piece shows
## its template's baked art. The art never reaches the simulation.
##
## **Room life** (connected biomes CB3): each piece is announced to whoever draws or reads its layout
## as it is laid (`built`, Flow's `room_built`: its template, its number, rooms first and then the
## bridges after them, and the layout at its place, its placements and zones still in it), so Feel
## draws a mirrored piece's ground from its shape. What is where in each room is read before the
## placements go, mirrored and moved to its place (`room_places`), for Flow to stand its bodies and
## fights. The grid gets every piece as a place (`RoomGrid.add_place`, the same numbers), where a
## seal holds (`RoomGrid.set_sealed`, Flow's), and the projectile manager the biggest room's side
## as what a growing shot grows to (`set_room_size`). Room state is Flow's (`RoomLife`).

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
const DERIVED: Array[StringName] = [&"registry", &"projectiles", &"built", &"_into", &"_layouts", &"_laid", &"_shapes", &"_room_places"]

var registry: RegistryScript = null
var projectiles: ProjectileManagerScript = null
## Told each piece as it is laid (connected biomes CB3): `built.call(template, number, layout)`,
## before its placements and zones are taken out (Flow sends `room_built`). Unset: nobody is told.
var built: Callable = Callable()
## The biome's map (null: none laid). The state.
var map: BiomeMap = null
var _into: Node2D = null
var _layouts: Array[Node] = []
var _laid: BiomeMap = null
var _shapes: Dictionary = {}
## What is where in each room laid, in the world (`room_places`).
var _room_places: Array[RoomPlaces] = []


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
	_lay_now(false)
	return problems


## Take the biome's pieces out of the world and forget its map (the grid is the next room's to lay).
func clear() -> void:
	for layout: Node in _layouts:
		if is_instance_valid(layout):
			if layout.get_parent() != null:
				layout.get_parent().remove_child(layout)
			layout.free()
	_layouts.clear()
	_room_places.clear()
	_laid = null
	map = null


## Lay into `into` from now on, with these services and telling `on_built` each piece (Flow's, as a
## biome starts and after a restore into a world that laid none).
func attach(into: Node2D, with_registry: RegistryScript, with_projectiles: ProjectileManagerScript, on_built: Callable) -> void:
	_into = into
	registry = with_registry
	projectiles = with_projectiles
	built = on_built


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
		_lay_now(true)


## Room `room` laid again alone, `map` (the world's from now on) differing from the map laid only in
## that room (a room reroll's, `BiomeGenerator.reroll_room`: its template, mirroring, place, kind and
## fill; its bridges where they were, the biome's bounds the same): its layout replaced by its new one
## (told `built` under its own number, so only its looks are made again), what is where in it read
## again, and the grid's layers laid again over the cells it covered or covers now, as a whole lay
## leaves them (`_lay_cells`), its place's rectangle the new one. Nothing else is touched: the other
## pieces' nodes, the solid shots' stones and the footprints stay; the seals and shut mouths are
## Flow's to tell again. False (nothing done) when there is no laid map to change so.
func relay_room(room: int) -> bool:
	if map == null or _laid == null or room <= 0 or room >= map.rooms() or room >= _layouts.size() or map.rooms() != _laid.rooms() or map.bridges() != _laid.bridges():
		return false
	shapes_of(map)
	var old_shape: PieceShape = _laid.room_shape(room, _shapes)
	var old: Rect2 = old_shape.rect_at(_laid.room_places[room]) if old_shape != null else Rect2()
	var layout: Node = _layouts[room]
	if layout != null and is_instance_valid(layout):
		if layout.get_parent() != null:
			layout.get_parent().remove_child(layout)
		layout.free()
	_layouts[room] = _place(ROOM_NODE % room, map.room_templates[room], map.room_places[room], map.room_mirrors[room], room, room)
	if projectiles != null:
		var grid: RoomGrid = projectiles.grid()
		var region: Rect2 = old.merge(room_rect(room)) if old.has_area() else room_rect(room)
		for bridge in map.bridges():
			for end in 2:
				if map.end_room(bridge, end) == room:
					region = region.merge(mouth_rect(bridge, end))
		_lay_cells(grid, grid.cells_round(region))
		grid.set_place_rect(room, room_rect(room))
	_laid = map.copy()
	return true


## The layout node of room `room` (null when none is laid).
func room_layout(room: int) -> Node:
	return _layouts[room] if map != null and room >= 0 and room < map.rooms() and room < _layouts.size() else null


## What is where in room `room` (spawns, placements, zones, holes), mirrored and at its place in
## the world (`RoomPlaces.placed_in`); null when none is laid.
func room_places(room: int) -> RoomPlaces:
	return _room_places[room] if room >= 0 and room < _room_places.size() else null


## How many places the biome has: its rooms, then its bridges (the grid's, `RoomGrid.add_place`).
func places() -> int:
	return map.rooms() + map.bridges() if map != null else 0


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


## The world rectangle of the mouth where bridge `bridge`'s end `end` (0 or 1) meets its room (as
## `_lay_grid` lays it; empty when none is laid): the doorway a gather door shuts (CB7).
func mouth_rect(bridge: int, end: int) -> Rect2:
	if map == null or bridge < 0 or bridge >= map.bridges():
		return Rect2()
	var room: int = map.end_room(bridge, end)
	var shape: PieceShape = map.room_shape(room, _shapes)
	return _moved(shape.mouth_rect(map.end_socket(bridge, end)), map.room_places[room]) if shape != null else Rect2()


## The biggest room's longest side (the projectile manager's room size, `set_room_size`).
func biggest_room() -> float:
	var biggest: float = 0.0
	if map != null:
		for room in map.rooms():
			biggest = maxf(biggest, maxf(room_rect(room).size.x, room_rect(room).size.y))
	return biggest


## The world's bounds for the biome: every piece (`area`), and MARGIN round them.
func bounds() -> Rect2:
	return area().grow(MARGIN)


## What the biome's pieces cover together, from the first room's corner: what the camera keeps to.
func area() -> Rect2:
	var whole := Rect2()
	var first: bool = true
	for room in map.rooms():
		whole = room_rect(room) if first else whole.merge(room_rect(room))
		first = false
	for bridge in map.bridges():
		whole = whole.merge(bridge_rect(bridge))
	return whole


## Lay the map's pieces and the grid (the class doc); `restored`: after a snapshot, over the bounds
## and the state it restored (see `_lay_grid`).
func _lay_now(restored: bool) -> void:
	for layout: Node in _layouts:
		if is_instance_valid(layout):
			if layout.get_parent() != null:
				layout.get_parent().remove_child(layout)
			layout.free()
	_layouts.clear()
	_room_places.clear()
	shapes_of(map)
	var at: int = 0
	for room in map.rooms():
		_layouts.append(_place(ROOM_NODE % room, map.room_templates[room], map.room_places[room], map.room_mirrors[room], at, room))
		at += 1
	for bridge in map.bridges():
		_layouts.append(_place(BRIDGE_NODE % bridge, map.bridge_templates[bridge], map.bridge_places[bridge], map.bridge_mirrors[bridge], at, map.rooms() + bridge))
		at += 1
	_lay_grid(restored)
	_laid = map.copy()


## One piece's layout, at `place` in the world, as the `index`-th child, piece `number` of the biome
## (a room's, else a bridge's after the rooms); null when its template is missing (the map's problems
## name it). A room's places are read first (`room_places`), and the piece is told (`built`).
func _place(named: String, template: StringName, place: Vector2, mirror: int, index: int, number: int) -> Node:
	var room: RoomBase = registry.get_resource(ROOM_FOLDER, template) as RoomBase if registry != null else null
	var layout: Node = room.build() if room != null else null
	if number < map.rooms():
		var shape: PieceShape = _shapes.get(template) as PieceShape
		var read: RoomPlaces = RoomPlaces.read(layout) if layout != null else RoomPlaces.new()
		var placed: RoomPlaces = read.placed_in(place, mirror, shape.size if shape != null else read.size)
		if number < _room_places.size():
			_room_places[number] = placed
		else:
			_room_places.append(placed)
	if layout == null:
		return null
	layout.name = named
	# How it is placed, for the view: Feel draws a room's ground mirrored from its shape as it hears
	# the room built (connected biomes CB4, `GroundShape.MIRROR_META`). The node is never flipped.
	layout.set_meta(PieceShape.GROUND_MIRROR_META, Vector2i(1 if (mirror & PieceShape.MIRROR_X) != 0 else 0, 1 if (mirror & PieceShape.MIRROR_Y) != 0 else 0))
	# A room's kind, for the view (connected biomes CB12: its music, air and light by kind).
	if number < map.rooms() and map.room_kinds[number] != &"":
		layout.set_meta(RoomKind.LAYOUT_META, map.room_kinds[number])
	# A reward room's type, for the view (its mouths' signs and the held map; the owner, 2026-11-19).
	if number < map.rooms() and not map.reward_type_of(number).is_any():
		layout.set_meta(RewardType.LAYOUT_META, map.reward_type_of(number).to_row())
	var piece := layout as Node2D
	if piece != null:
		piece.position = place
	if built.is_valid():
		built.call(template, number, layout)
	RoomPlaces.strip(layout)
	if _into != null:
		_into.add_child(layout)
		_into.move_child(layout, mini(index, _into.get_child_count() - 1))
	return layout


## Lay the grid from the map (the class doc), over the biome's bounds. A first lay sets the projectile
## manager's bounds (its shots' area and target grid; its solid shots lay themselves again). After a
## snapshot (`restored`) the manager's bounds and its solid shots' cells are the snapshot's state,
## the biome's already: only the grid's layers are laid again over them, the footprints and the solid
## shots' stones put back (`RoomGrid.size_to`, `relay_solids`), and no state is touched.
func _lay_grid(restored: bool) -> void:
	if projectiles == null:
		return
	var grid: RoomGrid = projectiles.grid()
	if restored:
		grid.size_to(projectiles.bounds())
	else:
		projectiles.set_bounds(bounds())
	_lay_cells(grid, Rect2())
	# Every piece a place, rooms first (connected biomes CB3); the seals are Flow's to set again.
	var biggest: float = 0.0
	for room in map.rooms():
		grid.add_place(room_rect(room))
		biggest = maxf(biggest, maxf(room_rect(room).size.x, room_rect(room).size.y))
	for bridge in map.bridges():
		# Over the lips of its rooms past their mouths: a body there is on the bridge (CB8).
		grid.add_place(bridge_rect(bridge), true)
	if not restored:
		projectiles.set_room_size(biggest)
	if restored:
		projectiles.relay_solids()


## The grid's walls, holes and mouths laid from the map, in order: every room's walls and holes, the
## dark between the pieces a wall, each joined room socket cut open, the bridges' walls and holes,
## their mouths. With `within` (whole cells, not empty) only its cells, opened first (`RoomGrid.cut`:
## the solid shots' stones and the footprints kept), then laid as the whole grid lays them.
func _lay_cells(grid: RoomGrid, within: Rect2) -> void:
	if within.has_area():
		grid.cut(within)
	var pieces: Array[Rect2] = []
	for room in map.rooms():
		_lay_piece(grid, map.room_shape(room, _shapes), map.room_places[room], within)
		pieces.append(room_rect(room))
	for bridge in map.bridges():
		pieces.append(bridge_rect(bridge))
	grid.wall_outside(pieces, within)
	for bridge in map.bridges():
		for end in 2:
			var room: int = map.end_room(bridge, end)
			var shape: PieceShape = map.room_shape(room, _shapes)
			grid.cut(_clipped(_moved(shape.cut_rect(map.end_socket(bridge, end)), map.room_places[room]), within))
	for bridge in map.bridges():
		_lay_piece(grid, map.bridge_shape(bridge, _shapes), map.bridge_places[bridge], within)
	for bridge in map.bridges():
		for end in 2:
			grid.add_mouth(_clipped(mouth_rect(bridge, end), within))
	if within.has_area():
		grid.recount_holes()


func _lay_piece(grid: RoomGrid, shape: PieceShape, place: Vector2, within: Rect2 = Rect2()) -> void:
	for rect: Rect2 in shape.walls:
		grid.add_wall(_clipped(_moved(rect, place), within))
	for rect: Rect2 in shape.holes:
		grid.add_hole(_clipped(_moved(rect, place), within))


## `rect` within `within` (all of it when `within` is empty; an empty rectangle when they miss).
static func _clipped(rect: Rect2, within: Rect2) -> Rect2:
	if not within.has_area():
		return rect
	return rect.intersection(within)


static func _moved(rect: Rect2, by: Vector2) -> Rect2:
	return Rect2(rect.position + by, rect.size)
