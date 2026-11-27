extends "res://tests/support/screenshot.gd"
## The menus' backdrops (ART4 part 2, the owner, 2026-11-27: lighter or none, the text relying on
## its outline) where they have the least contrast: the radial builder (P1, top left), the inventory
## (P2, top right) and the pause menu (P3), first over the brightest floors, then over a busy fight
## (four wizards casting in the hub). The floors are a backdrop of palette bands between the world
## and the HUD, each band one flat bright colour beside a busy checker of two, as
## `shot_hud_backdrops.gd`'s corners.
##
## Shots, `<scene>` being `fight` or `bright`: `menu_backdrops_<scene>` (the builder and the
## inventory open) with its 4x crops `menu_backdrops_<scene>_builder` and `_inventory`, and
## `menu_backdrops_<scene>_pause` with its 4x crop `menu_backdrops_<scene>_pause_rows`.

const DevHub := preload("res://tests/support/dev_hub.gd")

## The staffs every wizard starts with, as in `shot_hud_backdrops.gd`.
const CARDS: Array = [
	[&"dash"],
	[&"fire", &"bolt", &"frost", &"nova", &"bolt", &"bolt"],
	[&"fire", &"on_hit", &"on_expire", &"bolt", &"lightning", &"nova", &"bolt", &"homing"],
	[&"bolt", &"fire", &"bolt", &"frost", &"bolt", &"lightning", &"bolt", &"void", &"bolt", &"storm", &"bolt", &"pierce", &"bolt", &"chain", &"bolt", &"bigger", &"orbit"],
]
## The bands' colours, as `shot_hud_backdrops.gd`'s: the flat one, then the checker's two.
const BONE: PackedColorArray = [Color("#f4f1ea"), Color("#d4d0e0"), Color("#a39fb8")]
const SAND: PackedColorArray = [Color("#f2c230"), Color("#fff3a6"), Color("#b27a4a")]
const GRASS: PackedColorArray = [Color("#a0ad55"), Color("#8fd46a"), Color("#5b7233")]
const SPELLS: PackedColorArray = [Color("#7a7694"), Color("#c4f6f2"), Color("#e0592f")]
const BANDS: Array[PackedColorArray] = [BONE, SAND, GRASS, SPELLS]
## A band's width and the checker's square (layout pixels).
const BAND: float = 40.0
const SQUARE: float = 3.0
## The layout the bands cover (its size, as `PictureGrid` lays the HUD out).
const LAYOUT := Vector2(640.0, 360.0)
## The crops: the builder's column, the inventory's column, the pause menu's top rows (picture
## pixels, as `save_crop` takes them), and half of each crop.
const BUILDER_AT := Vector2(124, 190)
const INVENTORY_AT := Vector2(764, 130)
const PAUSE_AT := Vector2(640, 250)
const HALF := Vector2i(60, 45)


## Draws the bands over the whole layout (a Control under a layer between the world and the HUD), as
## one texture painted once: a draw call per checker square would be thousands.
class Backdrop extends Control:
	var _bands: ImageTexture = null

	func _ready() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var image := Image.create(int(LAYOUT.x), int(LAYOUT.y), false, Image.FORMAT_RGBA8)
		var half: int = int(BAND * 0.5)
		for x in int(LAYOUT.x):
			var colours: PackedColorArray = BANDS[floori(float(x) / BAND) % BANDS.size()]
			var across: int = x % int(BAND)
			for y in int(LAYOUT.y):
				var colour: Color = colours[0]
				if across >= half:
					colour = colours[1 + (floori(float(across - half) / SQUARE) + floori(float(y) / SQUARE)) % 2]
				image.set_pixel(x, y, colour)
		_bands = ImageTexture.create_from_image(image)
		queue_redraw()

	func _draw() -> void:
		if _bands != null:
			draw_texture(_bands, Vector2.ZERO)


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
		Downed.of(flow.call("get_wizard", index) as Node).protect(120.0)
	# The brightest floors first, the bands between the world and the HUD.
	var layer := CanvasLayer.new()
	layer.layer = 9
	var backdrop := Backdrop.new()
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(backdrop)
	root.add_child(layer)
	PictureGrid.keep_fitted(layer, backdrop)
	await settle(5)
	await _shoot("bright")
	layer.queue_free()
	await settle(3)
	# Then a busy fight: every wizard casting, a different way each.
	for round in 6:
		for index in 4:
			input.call("send_virtual_aim", index, Vector2.from_angle(float(index) * 1.57 + float(round) * 0.4))
			tap(index, &"staff_2" if round % 2 == 0 else &"staff_3")
		await settle(4)
	await _shoot("fight")
	flow.call("stop_run")
	await settle(3)


## The builder and the inventory open, then the pause menu, each closed after.
func _shoot(scene: String) -> void:
	tap(0, &"back")
	tap(1, &"inventory")
	await settle(20)
	var image: Image = await grab()
	save(image, "menu_backdrops_%s" % scene)
	save_crop(image, BUILDER_AT, "menu_backdrops_%s_builder" % scene, HALF, 4)
	save_crop(image, INVENTORY_AT, "menu_backdrops_%s_inventory" % scene, HALF, 4)
	tap(0, &"back")
	tap(1, &"inventory")
	await settle(10)
	tap(2, &"pause")
	await settle(10)
	var paused: Image = await grab()
	save(paused, "menu_backdrops_%s_pause" % scene)
	save_crop(paused, PAUSE_AT, "menu_backdrops_%s_pause_rows" % scene, HALF, 4)
	tap(2, &"pause")
	await settle(10)
