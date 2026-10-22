extends SceneTree
## The second art direction sheet (M2 part 27, after the owner's answer on #190): A again for
## reference, then D (A's proportions with a hooded robe), E (soft, no black outline) and F (big
## hat, cobble tiles). Each column shows the floor tiled, the wizard and the icon at 4x, and
## four overlapping wizards plus the icon at 1x and 2x (the sizes the game draws them).
## Needs a display, so it runs only through `ci/build/build.sh --quick --screenshots`; the shot
## is saved as user://screenshots/art_direction_sheet_2.png and copied to build/screenshots/.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 10
const COLUMN_WIDTH := 160.0
const PANEL_TOP := 22.0
const PANEL_HEIGHT := 224.0

const NAMES: Array[String] = ["A: Chunky", "D: Chunky hood", "E: Soft", "F: Big hat"]
const FLOORS: Array[Texture2D] = [
	preload("res://art/samples/a_chunky/crypt_floor.svg"),
	preload("res://art/samples/a_chunky/crypt_floor.svg"),
	preload("res://art/samples/e_soft/crypt_floor.svg"),
	preload("res://art/samples/f_bighat/crypt_floor.svg"),
]
const WIZARDS: Array[Texture2D] = [
	preload("res://art/samples/a_chunky/wizard.svg"),
	preload("res://art/samples/d_hood/wizard.svg"),
	preload("res://art/samples/e_soft/wizard.svg"),
	preload("res://art/samples/f_bighat/wizard.svg"),
]
const ICONS: Array[Texture2D] = [
	preload("res://art/samples/a_chunky/spell_icon.svg"),
	preload("res://art/samples/a_chunky/spell_icon.svg"),
	preload("res://art/samples/e_soft/spell_icon.svg"),
	preload("res://art/samples/f_bighat/spell_icon.svg"),
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
	var path: String = "%s/art_direction_sheet_2.png" % SHOTS_DIR
	if image == null or image.save_png(path) != OK:
		printerr("SHOT FAILED: could not save " + path)
		quit(1)
		return
	print("SHOT: art_direction_sheet_2 (%dx%d)" % [image.get_width(), image.get_height()])
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
	_place(WIZARDS[index], 4.0, left + 8.0, PANEL_TOP + 4.0)
	_place(ICONS[index], 4.0, left + 8.0, PANEL_TOP + 148.0)
	# Four wizards close enough to overlap, as four players are in a fight.
	for n in 4:
		_place(WIZARDS[index], 1.0, left + 80.0 + n * 12.0, PANEL_TOP + 148.0)
	_place(ICONS[index], 1.0, left + 80.0, PANEL_TOP + 188.0)
	_place(ICONS[index], 2.0, left + 104.0, PANEL_TOP + 188.0)


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
