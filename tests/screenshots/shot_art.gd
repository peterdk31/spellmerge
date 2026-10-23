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
const IDLE := preload("res://content/wizard/base/wizard_idle.svg")
const WALK := preload("res://content/wizard/base/wizard_walk.svg")
const DASH_STRIP := preload("res://content/wizard/base/wizard_dash.svg")
const HATS: Array[Texture2D] = [
	preload("res://content/wizard/base/wizard_hat_p1.svg"),
	preload("res://content/wizard/base/wizard_hat_p2.svg"),
	preload("res://content/wizard/base/wizard_hat_p3.svg"),
	preload("res://content/wizard/base/wizard_hat_p4.svg"),
]
const STAFF := preload("res://content/wizard/base/staff.svg")
const IMP := preload("res://content/enemies/ember_imp/idle.svg")
const IMP_WINDUP := preload("res://content/enemies/ember_imp/windup.svg")
const IMP_HURT := preload("res://content/enemies/ember_imp/hurt.svg")
const WALL_TOP := preload("res://art/tilesets/crypt/wall_top.svg")
const PILLAR := preload("res://art/tilesets/crypt/pillar.svg")
const PILLAR_TOP := preload("res://art/tilesets/crypt/pillar_top.svg")
const TORCH_FLAME := preload("res://art/tilesets/crypt/torch_flame.svg")
const DOOR := preload("res://art/tilesets/crypt/door.svg")
const TORCH := preload("res://art/tilesets/crypt/torch.svg")
const RUBBLE := preload("res://art/tilesets/crypt/rubble.svg")
const SKULL := preload("res://art/tilesets/crypt/skull.svg")
const DASH := preload("res://art/vfx/telegraph_dash.svg")
const BOLT := preload("res://art/vfx/bolt.svg")
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
	# Row 1: the wizard's idle (4: open, closed, glance left, glance right), walk (4) and
	# dash (2) frames, each under player 1's hat.
	var x: float = 4.0
	x = _strip(IDLE, x, 40.0, HATS[0])
	x = _strip(WALK, x, 40.0, HATS[0])
	x = _strip(DASH_STRIP, x, 40.0, HATS[0])
	# Row 2: the four players, the imp, the staff, the bolt and the spark.
	x = 32.0
	for hat: Texture2D in HATS:
		_frame(IDLE, 0, x, 120.0)
		_frame(hat, 0, x, 120.0)
		x += FRAME * SCALE
	x = _strip(IMP, x, 120.0)
	for texture: Texture2D in [STAFF, BOLT, SPARK]:
		_frame(texture, 0, x, 120.0)
		x += FRAME * SCALE
	# Row 3: floor and wall tiles side by side, as in the room.
	x = 32.0
	for texture: Texture2D in [WALL, WALL_TOP, PILLAR_TOP, PILLAR, DOOR, TORCH, RUBBLE, SKULL, DASH]:
		_frame(texture, 0, x, 200.0)
		x += FRAME * SCALE
	# Row 4: the imp's windup and hurt poses, then the torch flame and glow frames.
	x = _strip(IMP_WINDUP, 32.0, 266.0)
	_frame(IMP_HURT, 0, x, 266.0)
	_strip(TORCH_FLAME, x + FRAME * SCALE, 266.0)
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
func _strip(texture: Texture2D, x: float, y: float, hat: Texture2D = null) -> float:
	var frames: int = int(texture.get_width() / FRAME)
	for i in frames:
		_frame(texture, i, x, y)
		if hat != null:
			_frame(hat, 0, x, y)
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
