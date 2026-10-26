extends SceneTree
## Base class for the screenshot scripts, `tests/screenshots/shot_*.gd`.
##
## A shot script extends this file and stages what it shows in `take()`. Each picture is saved
## as user://screenshots/<name>.png and `ci/build/build.sh --quick --screenshots` copies it to
## build/screenshots/. A shot script is not a test: it only checks that each staged state
## happened, and `fail()` stops it with the reason (exit 1). It needs a display, so the build
## runs it on a virtual one.
##
##   extends "res://tests/support/screenshot.gd"
##   func take() -> void:
##       if not need(["Flow"]):
##           return
##       root.get_node("Flow").call("start_run", 0)
##       await shot("arena")
##
## godot --path . --script res://tests/screenshots/shot_<name>.gd

const SHOTS_DIR := "user://screenshots"
## The game's screen, which every sheet is laid out on.
const SCREEN := Vector2(640.0, 360.0)
const FLOOR := preload("res://art/tilesets/crypt/floor.svg")

## The frames `settle()` waits when it is given none.
var settle_frames: int = 20
var _failed: bool = false


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	await take()
	if not _failed:
		quit(0)


## Stages and saves the shots. Override it.
func take() -> void:
	pass


## Stops the script with exit code 1 and says why. The caller returns right after.
func fail(message: String) -> void:
	printerr("SHOT FAILED: " + message)
	_failed = true
	quit(1)


## True when every autoload in `names` exists; otherwise fails, naming them all.
func need(names: Array[String]) -> bool:
	for name in names:
		if root.get_node_or_null(name) == null:
			var listed: String = names[0]
			if names.size() > 1:
				listed = "%s and %s autoloads" % [", ".join(PackedStringArray(names.slice(0, -1))), names[-1]]
			else:
				listed += " autoload"
			fail("the %s must exist" % listed)
			return false
	return true


func settle(frames: int = -1) -> void:
	for i in (settle_frames if frames < 0 else frames):
		await process_frame


## Waits until `condition` returns true, at most `frames` frames. Returns whether it did. Faster
## than settling for a fixed count, since a software-rendered frame can take 30 ms.
func wait_for(condition: Callable, frames: int = 120) -> bool:
	for i in frames:
		if condition.call():
			return true
		await process_frame
	return condition.call()


## The screen as it is drawn this frame.
func grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


## Saves `image` as the shot `shot_name`; fails when it cannot.
func save(image: Image, shot_name: String) -> bool:
	var path: String = "%s/%s.png" % [SHOTS_DIR, shot_name]
	if image == null or image.save_png(path) != OK:
		fail("could not save " + path)
		return false
	print("SHOT: %s (%dx%d)" % [shot_name, image.get_width(), image.get_height()])
	return true


## Settles, then saves the whole screen.
func shot(shot_name: String) -> void:
	await settle()
	save(await grab(), shot_name)


## Where the world point `at` is on the screen (the camera moves the canvas).
func on_screen(at: Vector2) -> Vector2:
	return root.get_canvas_transform() * at


## Saves the `half` × 2 pixels of `image` round the screen point `at`, `zoom` times bigger.
func save_crop(image: Image, at: Vector2, shot_name: String, half: Vector2i = Vector2i(48, 48), zoom: int = 4) -> void:
	var scale_to_image: Vector2 = Vector2(image.get_size()) / Vector2(root.get_visible_rect().size)
	var middle := Vector2i(at * scale_to_image)
	var corner: Vector2i = (middle - half).clamp(Vector2i.ZERO, image.get_size() - half * 2)
	var crop: Image = image.get_region(Rect2i(corner, half * 2))
	if zoom != 1:
		crop.resize(crop.get_width() * zoom, crop.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	save(crop, shot_name)


## `save_crop` of the screen as it is drawn this frame, round the world point `at`.
func snap(at: Vector2, shot_name: String, half: Vector2i = Vector2i(48, 48), zoom: int = 4) -> void:
	save_crop(await grab(), on_screen(at), shot_name, half, zoom)


## One press and release of `action` on the virtual device of `player`.
func tap(player: int, action: StringName) -> void:
	var input: Node = root.get_node("PlayerInput")
	input.call("send_virtual", player, action, 1.0)
	input.call("send_virtual", player, action, 0.0)


## The crypt floor tiled over the whole screen, behind everything a sheet adds.
func lay_floor() -> void:
	var floor_sprite := Sprite2D.new()
	floor_sprite.texture = FLOOR
	floor_sprite.centered = false
	floor_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	floor_sprite.region_enabled = true
	floor_sprite.region_rect = Rect2(Vector2.ZERO, SCREEN)
	floor_sprite.z_index = -10
	root.add_child(floor_sprite)


## `texture` with its top left corner at `at`, `scale` times its size, unfiltered.
func place(texture: Texture2D, scale: float, at: Vector2, tint: Color = Color.WHITE) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(scale, scale)
	sprite.position = at
	sprite.modulate = tint
	root.add_child(sprite)
	return sprite


func label(text: String, at: Vector2, font_size: int = 10) -> void:
	var line := Label.new()
	line.text = text
	line.position = at
	line.add_theme_font_size_override("font_size", font_size)
	root.add_child(line)
