extends SceneTree
## The marks of the five combo classes (#244, round 2), for people and for Claude to look at (it
## only checks that the shot was taken). Needs a display, so it runs only through
## `ci/build/build.sh --quick --screenshots`; the shot is saved as user://screenshots/combo_marks.png.
##
## One column per class (boosted, on_hit, on_expire, timer, stacked). Row 1: the mark as it
## appears, at its own size, in fire. Rows 2 to 4: the same mark swelled, in frost, void and
## lightning, so the class reads from its shape and the element from its colour. A mark lasts a
## third of a second, so the two takes of each column are put together into one sheet.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 30
const WIDTH := 640
const HEIGHT := 360
const COLUMN := 128
const LOWER := 95
const CLASSES: Array[StringName] = [&"boosted", &"on_hit", &"on_expire", &"timer", &"stacked"]
const ROWS_Y: Array[float] = [50.0, 140.0, 220.0, 300.0]
const TINTS: Array[Color] = [Color("e0592f"), Color("4fd6dc"), Color("a0309a"), Color("b4e82a")]

const FLOOR := preload("res://art/tilesets/crypt/floor.svg")


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var events: Node = root.get_node_or_null("Events")
	if root.get_node_or_null("Feel") == null or events == null:
		printerr("SHOT FAILED: the Feel and Events autoloads must exist")
		quit(1)
		return
	var floor_sprite := Sprite2D.new()
	floor_sprite.texture = FLOOR
	floor_sprite.centered = false
	floor_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	floor_sprite.region_enabled = true
	floor_sprite.region_rect = Rect2(0, 0, WIDTH, HEIGHT)
	floor_sprite.z_index = -10
	root.add_child(floor_sprite)
	await _settle()
	var sheet: Image = null
	for i in CLASSES.size():
		var x: float = COLUMN * i + COLUMN * 0.5
		for row in ROWS_Y.size():
			events.call("emit_signal", "combo_cast", row, CLASSES[i], Vector2(x, ROWS_Y[row]), Vector2.RIGHT, TINTS[row])
		await process_frame
		await RenderingServer.frame_post_draw
		var early: Image = root.get_texture().get_image()
		if sheet == null:
			sheet = early
		else:
			sheet.blit_rect(early, Rect2i(COLUMN * i, 0, COLUMN, HEIGHT), Vector2i(COLUMN * i, 0))
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		var late: Image = root.get_texture().get_image()
		sheet.blit_rect(late, Rect2i(COLUMN * i, LOWER, COLUMN, HEIGHT - LOWER), Vector2i(COLUMN * i, LOWER))
		await _settle()
	var path: String = "%s/combo_marks.png" % SHOTS_DIR
	if sheet == null or sheet.save_png(path) != OK:
		printerr("SHOT FAILED: could not save " + path)
		quit(1)
		return
	print("SHOT: combo_marks (%dx%d)" % [sheet.get_width(), sheet.get_height()])
	quit(0)


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame
