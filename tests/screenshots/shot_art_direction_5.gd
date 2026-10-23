extends SceneTree
## The fifth art direction sheet (M2 part 27, after the owner's second answer on #206): J again
## for reference, then M (cream robe), N (dusk robe) and O (teal robe). The owner kept F's hat and
## asked for a robe as the clothes and a face of just two big eyes, no mouth. Each column shows the
## floor tiled, the wizard at 4x, the four players overlapping at 1x (as in a fight) next to one at
## 2x, and the four players apart at 1x. Needs a display, so it runs only through
## `ci/build/build.sh --quick --screenshots`; the shot is saved as
## user://screenshots/art_direction_sheet_5.png and copied to build/screenshots/.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 10
const COLUMN_WIDTH := 160.0
const PANEL_TOP := 22.0
const PANEL_HEIGHT := 250.0

const NAMES: Array[String] = ["J: Tiny cream (round 4)", "M: Cream robe", "N: Dusk robe", "O: Teal robe"]
const FLOOR: Texture2D = preload("res://art/samples/f_bighat/crypt_floor.svg")
const BODIES: Array[Texture2D] = [
	preload("res://art/samples/j_tiny/body.svg"),
	preload("res://art/samples/m_cream/body.svg"),
	preload("res://art/samples/n_dusk/body.svg"),
	preload("res://art/samples/o_teal/body.svg"),
]
const HATS: Array[Texture2D] = [
	preload("res://art/samples/hats_std/hat_p1.svg"),
	preload("res://art/samples/hats_std/hat_p2.svg"),
	preload("res://art/samples/hats_std/hat_p3.svg"),
	preload("res://art/samples/hats_std/hat_p4.svg"),
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
	var path: String = "%s/art_direction_sheet_5.png" % SHOTS_DIR
	if image == null or image.save_png(path) != OK:
		printerr("SHOT FAILED: could not save " + path)
		quit(1)
		return
	print("SHOT: art_direction_sheet_5 (%dx%d)" % [image.get_width(), image.get_height()])
	quit(0)


func _column(index: int) -> void:
	var left: float = 8.0 + index * COLUMN_WIDTH
	var inner: float = COLUMN_WIDTH - 8.0
	_label(NAMES[index], left, 6.0)
	var floor_sprite := Sprite2D.new()
	floor_sprite.texture = FLOOR
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
	# All four players side by side at 1x, apart.
	for n in 4:
		_wizard(index, n, 1.0, left + 8.0 + n * 34.0, PANEL_TOP + 216.0)


## One wizard for player `player` (0-3): the body, then the hat in the player's colour.
func _wizard(index: int, player: int, scale: float, x: float, y: float) -> void:
	_place(BODIES[index], scale, x, y)
	_place(HATS[player], scale, x, y)


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
