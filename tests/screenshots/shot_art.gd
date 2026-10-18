extends SceneTree
## A sheet of the placeholder art at 2x on the crypt floor, to look at: the
## wizard's idle, walk and dash frames, the four player colours, the ember imp,
## the staff, the fire bolt, the hit spark and the two tiles. Needs a display,
## so it runs only through `ci/build/build.sh --quick --screenshots`; the shot is
## saved as user://screenshots/art_sheet.png and copied to build/screenshots/.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 10
const SCALE := 2.0
const FRAME := 32.0

const FLOOR := preload("res://art/tilesets/crypt/floor.svg")
const WALL := preload("res://art/tilesets/crypt/wall.svg")
const IDLE_1 := preload("res://content/wizard/base/wizard_p1_idle.svg")
const IDLE_2 := preload("res://content/wizard/base/wizard_p2_idle.svg")
const IDLE_3 := preload("res://content/wizard/base/wizard_p3_idle.svg")
const IDLE_4 := preload("res://content/wizard/base/wizard_p4_idle.svg")
const WALK_1 := preload("res://content/wizard/base/wizard_p1_walk.svg")
const DASH_1 := preload("res://content/wizard/base/wizard_p1_dash.svg")
const STAFF := preload("res://content/wizard/base/staff.svg")
const IMP := preload("res://content/enemies/ember_imp/idle.svg")
const BOLT := preload("res://art/vfx/fire_bolt.svg")
const SPARK := preload("res://art/vfx/hit_spark.svg")


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
	# Row 1: the wizard's idle (2), walk (4) and dash (3) frames.
	var x: float = 4.0
	x = _strip(IDLE_1, x, 40.0)
	x = _strip(WALK_1, x, 40.0)
	x = _strip(DASH_1, x, 40.0)
	# Row 2: the four players, the imp, the staff, the bolt and the spark.
	x = 32.0
	for texture: Texture2D in [IDLE_1, IDLE_2, IDLE_3, IDLE_4]:
		_frame(texture, 0, x, 120.0)
		x += FRAME * SCALE
	x = _strip(IMP, x, 120.0)
	for texture: Texture2D in [STAFF, BOLT, SPARK]:
		_frame(texture, 0, x, 120.0)
		x += FRAME * SCALE
	# Row 3: floor and wall tiles side by side, as in the room.
	for i in 4:
		_frame(WALL, 0, 32.0 + i * FRAME * SCALE, 200.0)
	await _settle()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/art_sheet.png" % SHOTS_DIR
	if image == null or image.save_png(path) != OK:
		printerr("SHOT FAILED: could not save " + path)
		quit(1)
		return
	print("SHOT: art_sheet (%dx%d)" % [image.get_width(), image.get_height()])
	quit(0)


## Every frame of a strip, left to right from `x`. Returns the x after the strip.
func _strip(texture: Texture2D, x: float, y: float) -> float:
	var frames: int = int(texture.get_width() / FRAME)
	for i in frames:
		_frame(texture, i, x, y)
		x += FRAME * SCALE
	return x + FRAME * 0.5


func _frame(texture: Texture2D, frame: int, x: float, y: float) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.hframes = maxi(int(texture.get_width() / FRAME), 1)
	sprite.frame = frame
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(SCALE, SCALE)
	sprite.position = Vector2(x, y)
	root.add_child(sprite)


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame
