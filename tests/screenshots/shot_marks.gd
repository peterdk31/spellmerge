extends "res://tests/support/screenshot.gd"
## Screenshots of the floor marks (gameplay/feel/marks.gd; docs/milestones/spell-spectacle.md, P2a)
## as the game makes them: the crypt arena stands, the projectile manager is given its bounds and
## walls as Flow gives them, `room_entered` fits Feel's mark layer to it, and the cues are played
## through Feel: a plain blast of player 1, a fire blast and a frost blast (its cards' mark), a
## slam and a quake (cracks), and a blast against the top wall (clipped by it). Once the flashes
## and motes are gone, `marks_room` is the room at 1x and `marks_sheet` each mark at 4x, in that
## order.

const ARENA_SCENE := preload("res://content/rooms/crypt/arena_01.tscn")
const MARGIN: float = 32.0
## Each mark: its cue, where, how big, its tint and its look (layer n is bit n - 1).
const MARKS: Array[Array] = [
	[&"blast", Vector2(96.0, 230.0), 30.0, Color.WHITE, 0],
	[&"blast", Vector2(208.0, 230.0), 30.0, Color("e0592f"), 1 << 0],
	[&"blast", Vector2(320.0, 230.0), 30.0, Color("4fd6dc"), 1 << 1],
	[&"slam", Vector2(432.0, 230.0), 34.0, Color.WHITE, 0],
	[&"quake", Vector2(544.0, 230.0), 30.0, Color.WHITE, 0],
	[&"blast", Vector2(400.0, 44.0), 30.0, Color.WHITE, 0],
]
const HALF := Vector2i(28, 28)
const ZOOM: int = 4


func take() -> void:
	if not need(["Registry", "Feel", "Projectiles", "Events"]):
		return
	var feel: Node = root.get_node("Feel")
	var projectiles: Node = root.get_node("Projectiles")
	var room: Node2D = ARENA_SCENE.instantiate() as Node2D
	root.add_child(room)
	await settle(2)
	projectiles.call("set_bounds", Rect2(Vector2.ZERO, Vector2(640.0, 384.0)).grow(MARGIN))
	projectiles.call("clear_walls")
	for node: Node in room.find_children("*", "StaticBody2D", true, false):
		if ((node as StaticBody2D).collision_layer & RoomBase.WALL_LAYER) != 0:
			projectiles.call("add_wall_body", node)
	root.get_node("Events").emit_signal(&"room_entered", &"arena_01")
	if feel.call("marks") == null:
		fail("Feel has no mark layer (the Floor marks setting is off?)")
		return
	for mark: Array in MARKS:
		feel.call("play_cue", mark[0], 0, mark[1], Vector2.RIGHT, mark[2], mark[3], mark[4])
	# The flashes, the shake and the motes are gone after a few seconds; the marks stay.
	await settle(300)
	var image: Image = await grab()
	image.convert(Image.FORMAT_RGBA8)
	save(image, "marks_room")
	var scale_to_image: Vector2 = Vector2(image.get_size()) / Vector2(root.get_visible_rect().size)
	var cell: Vector2i = HALF * 2 * ZOOM
	var sheet := Image.create_empty(cell.x * MARKS.size(), cell.y, false, Image.FORMAT_RGBA8)
	for i in MARKS.size():
		var middle := Vector2i(on_screen(MARKS[i][1] as Vector2) * scale_to_image)
		var corner: Vector2i = (middle - HALF).clamp(Vector2i.ZERO, image.get_size() - HALF * 2)
		var crop: Image = image.get_region(Rect2i(corner, HALF * 2))
		crop.resize(cell.x, cell.y, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(crop, Rect2i(Vector2i.ZERO, cell), Vector2i(cell.x * i, 0))
	save(sheet, "marks_sheet")
