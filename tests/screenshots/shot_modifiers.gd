extends SceneTree
## A sheet of the six modifiers' placeholder icons on the crypt floor, to look at: the 16x16
## icons at 6x (split, pierce, homing, chain, bigger, faster), and again at 1x as the builder
## shows them. Needs a display, so it runs only through
## `ci/build/build.sh --quick --screenshots`; the shot is saved as
## user://screenshots/modifiers_sheet.png and copied to build/screenshots/.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 10

const FLOOR := preload("res://art/tilesets/crypt/floor.svg")
const ICONS: Array[Texture2D] = [
	preload("res://content/spells/modifiers/split/icon.svg"),
	preload("res://content/spells/modifiers/pierce/icon.svg"),
	preload("res://content/spells/modifiers/homing/icon.svg"),
	preload("res://content/spells/modifiers/chain/icon.svg"),
	preload("res://content/spells/modifiers/bigger/icon.svg"),
	preload("res://content/spells/modifiers/faster/icon.svg"),
]


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var floor_sprite := Sprite2D.new()
	floor_sprite.texture = FLOOR
	floor_sprite.centered = false
	floor_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	floor_sprite.region_enabled = true
	floor_sprite.region_rect = Rect2(0, 0, 640, 360)
	root.add_child(floor_sprite)
	var x: float = 24.0
	for icon: Texture2D in ICONS:
		_place(icon, 6.0, x, 40.0)
		_place(icon, 1.0, x + 40.0, 160.0)
		x += 104.0
	await _settle()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/modifiers_sheet.png" % SHOTS_DIR
	if image == null or image.save_png(path) != OK:
		printerr("SHOT FAILED: could not save " + path)
		quit(1)
		return
	print("SHOT: modifiers_sheet (%dx%d)" % [image.get_width(), image.get_height()])
	quit(0)


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
