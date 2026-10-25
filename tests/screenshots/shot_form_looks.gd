extends SceneTree
## The look of the five forms (#244, part 2), for people and for Claude to look at (it only
## checks that the shot was taken). Needs a display, so it runs only through
## `ci/build/build.sh --quick --screenshots`; the shot is saved as
## user://screenshots/form_looks.png and copied to build/screenshots/.
##
## One column per form (bolt, beam, nova, rune, orbit). Row 1: the cast flash on the wizard's
## staff (the body of a beam and a nova is drawn with it). Row 2: where a player's shot ends.
## Row 3: where an enemy's shot ends, which is the same ember mark in every column. Each column
## is its own take (a flash lasts a tenth of a second), put together into one sheet.

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 12
const WIDTH := 640
const HEIGHT := 360
const COLUMN := 128
const FORMS: Array[StringName] = [&"bolt", &"beam", &"nova", &"rune", &"orbit"]
const ROWS_Y: Array[float] = [70.0, 170.0, 270.0]

const FLOOR := preload("res://art/tilesets/crypt/floor.svg")


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var feel: Node = root.get_node_or_null("Feel")
	var events: Node = root.get_node_or_null("Events")
	if feel == null or events == null:
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
	for i in FORMS.size():
		var form: StringName = FORMS[i]
		var x: float = COLUMN * i + COLUMN * 0.5
		events.call("emit_signal", "spell_cast", 0, form, Vector2(x - 20.0, ROWS_Y[0]), Vector2.RIGHT)
		if form == &"beam":
			events.call("emit_signal", "form_shown", 0, &"beam", Vector2(x - 20.0, ROWS_Y[0]), Vector2.RIGHT, 56.0, Color("e0592f"))
		elif form == &"nova":
			events.call("emit_signal", "form_shown", 0, &"nova", Vector2(x, ROWS_Y[0]), Vector2.RIGHT, 0.0, Color("e0592f"))
		events.call("emit_signal", "projectile_impact", 0, null, Vector2(x, ROWS_Y[1]), Vector2.RIGHT)
		events.call("emit_signal", "projectile_impact", -1, null, Vector2(x, ROWS_Y[2]), Vector2.RIGHT)
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		if sheet == null:
			sheet = image
		else:
			sheet.blit_rect(image, Rect2i(COLUMN * i, 0, COLUMN, HEIGHT), Vector2i(COLUMN * i, 0))
		await _settle()
	if sheet == null:
		printerr("SHOT FAILED: nothing was drawn")
		quit(1)
		return
	var path: String = "%s/form_looks.png" % SHOTS_DIR
	if sheet.save_png(path) != OK:
		printerr("SHOT FAILED: could not save " + path)
		quit(1)
		return
	print("SHOT: form_looks (%dx%d)" % [sheet.get_width(), sheet.get_height()])
	quit(0)


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame
