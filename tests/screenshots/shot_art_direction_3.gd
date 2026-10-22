extends SceneTree
## The third art direction sheet (M2 part 27, after the owner's answer on #192): F again for
## reference, then G (brown robe), H (cream robe) and I (cream robe, warmer floor, more vivid
## player colours). In G, H and I only the hat takes the player's colour: the body is one sprite
## and the hat is drawn on top of it in the player's colour. Each column shows the floor tiled,
## the wizard at 4x, and the four players overlapping at 1x (as in a fight) next to one at 2x.
## Needs a display, so it runs only through `ci/build/build.sh --quick --screenshots`; the shot
## is saved as user://screenshots/art_direction_sheet_3.png and copied to build/screenshots/.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 10
const COLUMN_WIDTH := 160.0
const PANEL_TOP := 22.0
const PANEL_HEIGHT := 250.0

const NAMES: Array[String] = ["F: Big hat (round 2)", "G: Brown robe", "H: Cream robe", "I: Cream, new palette"]
const FLOORS: Array[Texture2D] = [
	preload("res://art/samples/f_bighat/crypt_floor.svg"),
	preload("res://art/samples/f_bighat/crypt_floor.svg"),
	preload("res://art/samples/f_bighat/crypt_floor.svg"),
	preload("res://art/samples/i_warm/floor.svg"),
]
## F is one whole sprite (blue hat for everyone); G, H and I are a body plus a hat per player.
const F_WIZARD: Texture2D = preload("res://art/samples/f_bighat/wizard.svg")
const BODIES: Array[Texture2D] = [
	null,
	preload("res://art/samples/g_brown/body.svg"),
	preload("res://art/samples/h_cream/body.svg"),
	preload("res://art/samples/h_cream/body.svg"),
]
const HATS_STD: Array[Texture2D] = [
	preload("res://art/samples/hats_std/hat_p1.svg"),
	preload("res://art/samples/hats_std/hat_p2.svg"),
	preload("res://art/samples/hats_std/hat_p3.svg"),
	preload("res://art/samples/hats_std/hat_p4.svg"),
]
const HATS_VIVID: Array[Texture2D] = [
	preload("res://art/samples/hats_vivid/hat_p1.svg"),
	preload("res://art/samples/hats_vivid/hat_p2.svg"),
	preload("res://art/samples/hats_vivid/hat_p3.svg"),
	preload("res://art/samples/hats_vivid/hat_p4.svg"),
]


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var backdrop := ColorRect.new()
	backdrop.color = Color("#14121f")
	backdrop.size = Vector2(640, 360)
	root.add_child(backdrop)
	for i in NAMES.size():
		_column(i)
	await _settle()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/art_direction_sheet_3.png" % SHOTS_DIR
	if image == null or image.save_png(path) != OK:
		printerr("SHOT FAILED: could not save " + path)
		quit(1)
		return
	print("SHOT: art_direction_sheet_3 (%dx%d)" % [image.get_width(), image.get_height()])
	quit(0)


func _column(index: int) -> void:
	var left: float = 8.0 + index * COLUMN_WIDTH
	var inner: float = COLUMN_WIDTH - 8.0
	_label(NAMES[index], left, 6.0)
	var floor_sprite := Sprite2D.new()
	floor_sprite.texture = FLOORS[index]
	floor_sprite.centered = false
	floor_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floor_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	floor_sprite.region_enabled = true
	floor_sprite.region_rect = Rect2(0, 0, inner, PANEL_HEIGHT)
	floor_sprite.position = Vector2(left, PANEL_TOP)
	root.add_child(floor_sprite)
	_wizard(index, 0, 4.0, left + 8.0, PANEL_TOP + 4.0)
	# Four players close enough to overlap, as in a fight, then one at the size the game may draw.
	for n in 4:
		_wizard(index, n, 1.0, left + 8.0 + n * 12.0, PANEL_TOP + 148.0)
	_wizard(index, 1, 2.0, left + 80.0, PANEL_TOP + 148.0)
	if index > 0:
		# All four players side by side at 1x, apart, so the palette can be judged.
		for n in 4:
			_wizard(index, n, 1.0, left + 8.0 + n * 34.0, PANEL_TOP + 216.0)


## One wizard for player `player` (0-3): the body, then the hat in the player's colour.
func _wizard(index: int, player: int, scale: float, x: float, y: float) -> void:
	if index == 0:
		_place(F_WIZARD, scale, x, y)
		return
	_place(BODIES[index], scale, x, y)
	var hats: Array[Texture2D] = HATS_VIVID if index == 3 else HATS_STD
	_place(hats[player], scale, x, y)


func _label(text: String, x: float, y: float) -> void:
	var label := Label.new()
	label.text = text
	label.position = Vector2(x, y)
	label.add_theme_font_size_override("font_size", 10)
	root.add_child(label)


func _place(texture: Texture2D, scale: float, x: float, y: float) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(scale, scale)
	sprite.position = Vector2(x, y)
	root.add_child(sprite)


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame
