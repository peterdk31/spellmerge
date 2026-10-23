extends SceneTree
## The art direction sheet (M2 part 27): three style samples side by side, each a wizard, a
## crypt floor and a spell icon on the 32x32 grid and the shared palette. A is Chunky, B is
## the current look (the placeholders in the game), C is Grim. Every column shows the floor
## tiled, the wizard and the icon at 4x, and both again at 1x (the size the game draws them).
## Needs a display, so it runs only through `ci/build/build.sh --quick --screenshots`; the shot
## is saved as user://screenshots/art_direction_sheet.png and copied to build/screenshots/.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 10
const COLUMN_WIDTH := 208.0
const PANEL_TOP := 22.0
const PANEL_HEIGHT := 224.0

const NAMES: Array[String] = ["A: Chunky", "B: Current", "C: Grim"]
const FLOORS: Array[Texture2D] = [
	preload("res://art/samples/a_chunky/crypt_floor.svg"),
	preload("res://art/tilesets/crypt/floor.svg"),
	preload("res://art/samples/c_grim/crypt_floor.svg"),
]
const WIZARDS: Array[Texture2D] = [
	preload("res://art/samples/a_chunky/wizard.svg"),
	preload("res://content/wizard/base/wizard_idle.svg"),
	preload("res://art/samples/c_grim/wizard.svg"),
]
const ICONS: Array[Texture2D] = [
	preload("res://art/samples/a_chunky/spell_icon.svg"),
	preload("res://content/spells/elements/fire/icon.svg"),
	preload("res://art/samples/c_grim/spell_icon.svg"),
]
## The current wizard file is a strip of frames; the first 32x32 is the idle pose.
const STRIP_FRAME := Rect2i(0, 0, 32, 32)
const HAT: Texture2D = preload("res://content/wizard/base/wizard_hat_p1.svg")


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
	var path: String = "%s/art_direction_sheet.png" % SHOTS_DIR
	if image == null or image.save_png(path) != OK:
		printerr("SHOT FAILED: could not save " + path)
		quit(1)
		return
	print("SHOT: art_direction_sheet (%dx%d)" % [image.get_width(), image.get_height()])
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
	var wizard: Texture2D = _frame(WIZARDS[index], index == 1)
	_place(wizard, 4.0, left + 8.0, PANEL_TOP + 8.0)
	_place(ICONS[index], 4.0, left + 8.0 + 128.0 + 8.0, PANEL_TOP + 8.0)
	# The same two at the size the game draws them, on the floor: four wizards close enough to overlap, as four players do in a fight.
	for n in 4:
		_place(wizard, 1.0, left + 8.0 + n * 12.0, PANEL_TOP + 150.0)
	_place(ICONS[index], 1.0, left + 8.0 + 128.0 + 8.0, PANEL_TOP + 150.0)
	_place(ICONS[index], 2.0, left + 8.0 + 128.0 + 8.0 + 24.0, PANEL_TOP + 150.0)


func _frame(texture: Texture2D, from_strip: bool) -> Texture2D:
	if not from_strip:
		return texture
	# The game's wizard is now a body strip under a separate hat: the first frame and player 1's hat.
	var image: Image = texture.get_image().get_region(STRIP_FRAME)
	var hat: Image = HAT.get_image()
	image.blend_rect(hat, Rect2i(Vector2i.ZERO, hat.get_size()), Vector2i.ZERO)
	return ImageTexture.create_from_image(image)


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
