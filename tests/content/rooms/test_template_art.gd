extends "res://tests/support/suite.gd"
## Every room template's look (content/rooms: every room a run's map can pick, found by folder),
## only what matters to play: the floor covers the room, each wall sprite draws over a collision
## shape and each shape is drawn (a ground drawn from a shape by its wall art, or, a floating room's
## edge, by the dark round its slab), decoration never blocks anything, and a ground drawn from a
## shape keeps the fight readable (crypt rework, docs/milestones/crypt-rework.md, rule 6). Which
## tile, torch or decal goes where is free to change.

const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## The darkest a 32 px cell of a ground's floor may average in a room's middle two thirds (Stone
## shadow's luminance), and the least the whole of it may (Stone base's): rule 6, read from the art,
## so it holds with spell light off.
const FLOOR_CELL: int = 32

var templates: Array[RoomBase] = []
## Each template's layout, one instance, by id.
var layouts: Dictionary[StringName, Node] = {}


func before_each() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	templates = RoomScan.templates(registry)
	layouts.clear()
	for room in templates:
		layouts[room.id] = own(room.scene.instantiate()) as Node


func _layout(room: RoomBase) -> Node:
	return layouts[room.id]


func test_the_templates_are_found() -> void:
	check(templates.size() >= 1, "the templates are found (%d)" % templates.size())


func test_floor_covers_the_whole_room() -> void:
	for room in templates:
		var layout: Node = _layout(room)
		var floor_sprite: Sprite2D = layout.get_node_or_null("Floor") as Sprite2D
		check(floor_sprite != null, "%s has a Floor sprite" % room.id)
		if floor_sprite != null:
			check_equal(RoomScan.sprite_rect(floor_sprite), RoomScan.wall_bounds(layout), "%s: the floor covers the room inside and under its walls" % room.id)
			if _is_ground(floor_sprite):
				_check_floor_art(room, layout, floor_sprite)


## A ground drawn from a shape (tools/ground_shape.py) is its own floor: its art is opaque at the
## middle of every 8 px cell that is neither wall nor hole, so a body never stands on the dark.
func _check_floor_art(room: RoomBase, layout: Node, ground: Sprite2D) -> void:
	var art: Image = ground.texture.get_image()
	var blocked: Array[Rect2] = RoomScan.wall_rects(layout) + RoomPlaces.hole_rects(layout)
	var bare: int = 0
	for y in range(0, art.get_height(), 8):
		for x in range(0, art.get_width(), 8):
			var middle: Vector2 = Vector2(x + 4, y + 4)
			if blocked.any(func(r: Rect2) -> bool: return r.has_point(middle)):
				continue
			if art.get_pixel(x + 4, y + 4).a < 0.5:
				bare += 1
	check_equal(bare, 0, "%s: every open cell is drawn floor" % room.id)


func _is_ground(node: Node) -> bool:
	return node != null and node.has_meta(&"ground_inputs")


## Rule 6: in the middle two thirds of a room drawn from a shape, its floor's pixels average at least
## Stone base's luminance and no 32 px cell of them averages below Stone shadow's, so the fight is
## never on the dark.
func test_a_grounds_floor_is_readable() -> void:
	var stone: PackedColorArray = Palette.shades_of(&"stone")
	var checked: int = 0
	for room in templates:
		var ground: Sprite2D = _layout(room).get_node_or_null("Floor") as Sprite2D
		if not _is_ground(ground):
			continue
		checked += 1
		var art: Image = ground.texture.get_image()
		var size: Vector2i = art.get_size()
		var middle := Rect2i(size / 6, size - size / 6 * 2)
		var total: float = 0.0
		var count: int = 0
		var darkest: float = 1.0
		for cy in range(middle.position.y, middle.end.y - FLOOR_CELL + 1, FLOOR_CELL):
			for cx in range(middle.position.x, middle.end.x - FLOOR_CELL + 1, FLOOR_CELL):
				var cell_total: float = 0.0
				var cell_count: int = 0
				for y in range(cy, cy + FLOOR_CELL):
					for x in range(cx, cx + FLOOR_CELL):
						var pixel: Color = art.get_pixel(x, y)
						if pixel.a > 0.99:
							cell_total += pixel.get_luminance()
							cell_count += 1
				if cell_count > 0:
					darkest = minf(darkest, cell_total / cell_count)
					total += cell_total
					count += cell_count
		check(count > 0 and total / count >= stone[1].get_luminance(), "%s: the floor's middle averages %.3f, at least Stone base's %.3f" % [room.id, total / maxi(count, 1), stone[1].get_luminance()])
		check(darkest >= stone[0].get_luminance(), "%s: its darkest 32 px cell averages %.3f, at least Stone shadow's %.3f" % [room.id, darkest, stone[0].get_luminance()])
	check(checked >= 1, "a template is drawn from a shape (%d)" % checked)


func test_every_wall_sprite_draws_over_a_collision_shape() -> void:
	for room in templates:
		var layout: Node = _layout(room)
		var rects: Array[Rect2] = RoomScan.wall_rects(layout)
		for child in _own_walls(layout):
			if child is Sprite2D:
				check(rects.has(RoomScan.sprite_rect(child as Sprite2D)), "%s: wall sprite %s matches a collision shape" % [room.id, child.name])


func test_every_collision_shape_has_a_wall_sprite() -> void:
	for room in templates:
		var layout: Node = _layout(room)
		var drawn: Array[Rect2] = []
		for child in _own_walls(layout):
			if child is Sprite2D:
				drawn.append(RoomScan.sprite_rect(child as Sprite2D))
		# A ground drawn from a shape (tools/ground_shape.py) draws its own walls: its `WallArt`,
		# opaque over every wall cell of its `Walls` body (tools/test_ground_shape.py checks that per
		# pixel); here, at the middle of each of its rectangles.
		# A floating room's edge (the edge style draws no wall: crypt rework, the owner's second
		# round) is an invisible wall over the dark round the slab: its floor art is clear there, so
		# the wall stands where no floor is drawn.
		var ground_walls: Array[Rect2] = []
		var art: Image = null
		var floor_art: Image = null
		var ground: Node = layout.get_node_or_null("Floor/Walls")
		if ground != null:
			ground_walls = RoomScan.wall_rects(layout.get_node("Floor"))
			var art_sprite: Sprite2D = ground.get_node_or_null("WallArt") as Sprite2D
			art = art_sprite.texture.get_image() if art_sprite != null else null
			floor_art = (layout.get_node("Floor") as Sprite2D).texture.get_image()
		for rect in RoomScan.wall_rects(layout):
			if ground_walls.has(rect):
				var middle: Vector2i = Vector2i(rect.get_center())
				if art != null:
					check(art.get_pixelv(middle).a > 0.5, "%s: the ground's wall %s is drawn by its wall art" % [room.id, rect])
				else:
					check(_clear_at_cell_middles(floor_art, rect), "%s: the ground's edge %s lies off its slab, over the dark" % [room.id, rect])
				continue
			check(drawn.has(rect), "%s: the wall %s is drawn" % [room.id, rect])


func test_decoration_has_no_collision() -> void:
	for room in templates:
		for child in _layout(room).get_children():
			# The room's walls, and a ground drawn from a shape (its own walls and holes).
			if child.name != "Walls" and not child.has_meta(&"ground_inputs"):
				check_equal(_collision_nodes_below(child), 0, "%s: collision objects under %s" % [room.id, child.name])


func test_decoration_stays_inside_the_room() -> void:
	for room in templates:
		var layout: Node = _layout(room)
		var bounds: Rect2 = RoomScan.wall_bounds(layout)
		for child in layout.get_children():
			if child.name != "Walls":
				_check_sprites_inside(room, child, bounds)


## A rubble or skull lies on the floor, never over a wall or a pillar's base, which draw under it;
## so does a decal (candles, a fallen column), its every sprite but its light. A torch hangs on the
## wall and a door is in it: those are named so. Light (an additive sprite: a glow, a shaft falling
## from the top of the screen) falls on anything.
func test_floor_decoration_lies_clear_of_walls() -> void:
	for room in templates:
		var layout: Node = _layout(room)
		var walls: Array[Rect2] = RoomScan.wall_rects(layout)
		for child in layout.get_node("Decor").get_children():
			var named: String = String(child.name)
			if named.ends_with("Door") or named.begins_with("Torch"):
				continue
			for sprite: Sprite2D in _floor_sprites(child):
				var at: Rect2 = RoomScan.sprite_rect(sprite)
				if sprite != child:
					at.position += (child as Node2D).position - (at.size * 0.5 if sprite.centered else Vector2.ZERO)
				for wall in walls:
					check(not wall.intersects(at), "%s: %s at %s lies clear of the wall %s" % [room.id, named, at, wall])


## The sprites of a decoration that lie on the floor: itself, if a sprite, and an instanced decal's
## own (one level down), but for its light.
func _floor_sprites(node: Node) -> Array[Sprite2D]:
	var found: Array[Sprite2D] = []
	var all: Array[Node] = [node]
	if node.scene_file_path != "":
		all.append_array(node.get_children())
	for each in all:
		var sprite: Sprite2D = each as Sprite2D
		if sprite != null and not _is_light(sprite):
			found.append(sprite)
	return found


## True for a sprite that is light (painted light, or drawn additively: a glow, a shaft), which
## falls on anything and may spill past the room's edge.
func _is_light(sprite: Sprite2D) -> bool:
	var material: CanvasItemMaterial = sprite.material as CanvasItemMaterial
	return sprite.is_in_group(&"painted_light") or (material != null and material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD)


## True when `art` is clear at the middle of every 8 px cell of `rect` (a wall's cells: the
## generator opens a cell exactly where its middle is drawn, so off the slab every middle is dark).
func _clear_at_cell_middles(art: Image, rect: Rect2) -> bool:
	for y in range(int(rect.position.y) + 4, int(rect.end.y), 8):
		for x in range(int(rect.position.x) + 4, int(rect.end.x), 8):
			if art.get_pixel(x, y).a >= 0.5:
				return false
	return true


## The children of the room's own `Walls` body (its tiles and low walls); none in a room whose walls
## are all its ground's (a floating room).
func _own_walls(layout: Node) -> Array[Node]:
	var walls: Node = layout.get_node_or_null("Walls")
	return walls.get_children() if walls != null else []


## Every sprite under `node` lies inside the room, where it is drawn: its parents' places added
## (a decal's sprites), a centred one round its place.
func _check_sprites_inside(room: RoomBase, node: Node, bounds: Rect2, offset: Vector2 = Vector2.ZERO) -> void:
	var sprite: Sprite2D = node as Sprite2D
	if sprite != null and not _is_light(sprite):
		var at: Rect2 = RoomScan.sprite_rect(sprite)
		at.position += offset - (at.size * 0.5 if sprite.centered else Vector2.ZERO)
		check(bounds.encloses(at), "%s: %s at %s is inside the room" % [room.id, sprite.name, at])
	var here: Vector2 = offset + ((node as Node2D).position if node is Node2D else Vector2.ZERO)
	for child in node.get_children():
		_check_sprites_inside(room, child, bounds, here)


func _collision_nodes_below(node: Node) -> int:
	var count: int = 1 if node is CollisionObject2D or node is CollisionShape2D else 0
	for child in node.get_children():
		count += _collision_nodes_below(child)
	return count
