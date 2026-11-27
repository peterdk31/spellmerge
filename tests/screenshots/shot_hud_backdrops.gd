extends "res://tests/support/screenshot.gd"
## The corner panels with no frame and no background (the owner, 2026-11-27; ART4,
## hud/widgets/hud_art.gd) over the brightest floors they may meet: under each corner, between the
## world and the HUD, a backdrop of palette colours, its left half one flat bright colour and its
## right half a busy checker of two (the floors' and the spells' brightest), so every card, line,
## word and mark is seen where it has the least contrast.
##
## The hub with the dev staffs and four built staffs per wizard (tests/support/dev_hub.gd), four
## players each having cast: `hud_backdrops` (the whole picture) and `hud_backdrops_p1-4` (each
## corner at 4x).

const DevHub := preload("res://tests/support/dev_hub.gd")

## The staffs every wizard starts with, as in `shot_hud_staffs.gd`.
const CARDS: Array = [
	[&"dash"],
	[&"fire", &"bolt", &"frost", &"nova", &"bolt", &"bolt"],
	[&"fire", &"on_hit", &"on_expire", &"bolt", &"lightning", &"nova", &"bolt", &"homing"],
	[&"bolt", &"fire", &"bolt", &"frost", &"bolt", &"lightning", &"bolt", &"void", &"bolt", &"storm", &"bolt", &"pierce", &"bolt", &"chain", &"bolt", &"bigger", &"orbit"],
]
## Each corner's backdrop in layout pixels, and its colours: the flat one, then the checker's two.
const BACKDROPS: Array[Rect2] = [Rect2(0, 0, 144, 100), Rect2(496, 0, 144, 100), Rect2(0, 260, 144, 100), Rect2(496, 260, 144, 100)]
const BONE: PackedColorArray = [Color("#f4f1ea"), Color("#d4d0e0"), Color("#a39fb8")]
const SAND: PackedColorArray = [Color("#f2c230"), Color("#fff3a6"), Color("#b27a4a")]
const GRASS: PackedColorArray = [Color("#a0ad55"), Color("#8fd46a"), Color("#5b7233")]
const SPELLS: PackedColorArray = [Color("#7a7694"), Color("#c4f6f2"), Color("#e0592f")]
const COLOURS: Array[PackedColorArray] = [BONE, SAND, GRASS, SPELLS]
## The checker's square (layout pixels).
const SQUARE: float = 3.0
## The centre of each corner panel on the screen (picture pixels, as `save_crop` takes it), and half
## the crop round it (layout pixels).
const CORNERS: Array[Vector2] = [Vector2(136, 96), Vector2(1144, 96), Vector2(136, 624), Vector2(1144, 624)]
const HALF := Vector2i(68, 48)


## Draws the backdrops (a Control under a layer between the world and the HUD).
class Backdrop extends Control:
	func _draw() -> void:
		for corner in BACKDROPS.size():
			var rect: Rect2 = BACKDROPS[corner]
			var colours: PackedColorArray = COLOURS[corner]
			var half: float = floorf(rect.size.x * 0.5)
			draw_rect(Rect2(rect.position, Vector2(half, rect.size.y)), colours[0])
			var y: float = rect.position.y
			var row: int = 0
			while y < rect.end.y:
				var x: float = rect.position.x + half
				var column: int = 0
				while x < rect.end.x:
					draw_rect(Rect2(x, y, SQUARE, SQUARE), colours[1 + (row + column) % 2])
					x += SQUARE
					column += 1
				y += SQUARE
				row += 1


func take() -> void:
	if not need(["PlayerInput", "Hud", "Flow", "Registry", "Events"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	for index in 4:
		input.call("add_virtual_device", index)
	if not DevHub.start(flow, root.get_node("Registry"), CARDS):
		fail("the hub did not start with four wizards")
		return
	if not await wait_for(func() -> bool: return flow.call("get_wizard", 3) != null):
		fail("the hub did not start with four wizards")
		return
	for index in 4:
		Downed.of(flow.call("get_wizard", index) as Node).protect(60.0)
	var layer := CanvasLayer.new()
	layer.layer = 9
	var backdrop := Backdrop.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(backdrop)
	root.add_child(layer)
	PictureGrid.keep_fitted(layer, backdrop)
	await settle(5)
	for index in 4:
		input.call("send_virtual_aim", index, Vector2.UP)
		tap(index, &"staff_2")
	await settle(10)
	var image: Image = await grab()
	save(image, "hud_backdrops")
	for index in 4:
		save_crop(image, CORNERS[index], "hud_backdrops_p%d" % (index + 1), HALF, 4)
	layer.queue_free()
	flow.call("stop_run")
	await settle(3)
