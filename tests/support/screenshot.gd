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
##
## Before `take()`, the shaders are compiled behind the loading screen as on Play (`warm_up.gd`).
## A script that shows the load itself sets `warm_first = false` in its `_init()`.
##
## A run a shot starts plays the crypt's first arena alone (`PINNED_ROOM`, a pinned run:
## bench/pinned_run.gd), so a shot staged by its places shows the same room every time; the
## crypt run's own first room is any of its fight rooms, by the run's seed (run generation RG3b). A
## script that shows the generated run sets `pin_room = false` in its `_init()`.
##
## **The screen is drawn only for a picture** (`drawn_frames.gd`): after the warm-up the game steps
## and the engine draws every frame (the floor marks' layers, bakes and cached panels included), but
## the screen's own 1280 x 720 picture only on a frame `grab` takes, so waiting for a camera or a
## fight costs the game's step, not a software renderer's picture. A script that needs the screen
## drawn every frame (one that times frames, or is watched) sets `draw_between = true` in its
## `_init()`; one that reads a view of its own (a SubViewport) awaits `frame_drawn()` first.
##
## **The view is on the game's clock** (`Feel.fixed_view_delta`, a tick's time a frame, as the
## benchmark's): the camera's easing, the motes, the mist and the reveals move as far a frame as the
## game does, however long the frame takes to draw or whether it is drawn, so a shot shows the same
## moment on a fast machine and a software renderer.

const WarmUp := preload("res://tests/support/warm_up.gd")
const SHOTS_DIR := "user://screenshots"
## The game's screen, which every sheet is laid out on: its layout pixels (PictureGrid.SIZE), drawn
## at the picture's scale (`sheet_scale`: 2 in the 1280 x 720 picture).
const SCREEN := Vector2(640.0, 360.0)
const FLOOR := preload("res://art/tilesets/crypt/floor@2x.svg")
const PinnedRun := preload("res://bench/pinned_run.gd")
const DrawnFramesScript := preload("res://tests/support/drawn_frames.gd")
const _SHOT_TICK := preload("res://core/sim/tick.gd")
## The room a shot's run plays while `pin_room` is on.
const PINNED_ROOM: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")

## The frames `settle()` waits when it is given none.
var settle_frames: int = 20
## Whether the screen is drawn every frame (true), or only for a picture (false, the default).
var draw_between: bool = false
## Whether the shaders are compiled (Flow's play tasks run) before `take()`.
var warm_first: bool = true
## Whether a run a shot starts plays `PINNED_ROOM` alone rather than the generated crypt run.
var pin_room: bool = true
var _failed: bool = false
var _drawn_frames: DrawnFramesScript = null


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	if warm_first and not await WarmUp.run(root):
		fail("the shaders were not compiled before the shots (Flow's play tasks through Loading)")
		return
	_drawn_frames = DrawnFramesScript.new()
	root.add_child(_drawn_frames)
	_drawn_frames.drawing = draw_between
	var flow: Node = root.get_node_or_null("Flow")
	var registry: Node = root.get_node_or_null("Registry")
	if pin_room and flow != null and registry != null:
		flow.set("run_id_to_play", PinnedRun.pin(registry, PINNED_ROOM))
	# The effects at the high row, never "Effects: Auto" (the HUD's menu tells Feel the saved setting
	# when it binds at boot): a shot must not change with how busy the machine drawing it is.
	var feel: Node = root.get_node_or_null("Feel")
	if feel != null and feel.has_method("set_effects_mode"):
		feel.call("set_effects_mode", EffectsSetting.HIGH)
	# The view on the game's clock, a tick's time a frame (as the benchmark's, bench/fixed_steps.gd),
	# never the real one: the camera's easing, the motes and the mist must not run ahead while a
	# software renderer takes a tenth of a second a frame, nor stand still while a frame is not drawn.
	if feel != null:
		feel.set(&"fixed_view_delta", _SHOT_TICK.DT)
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
## than settling for a fixed count.
func wait_for(condition: Callable, frames: int = 120) -> bool:
	for i in frames:
		if condition.call():
			return true
		await process_frame
	return condition.call()


## The screen as it is drawn this frame.
func grab() -> Image:
	await frame_drawn()
	return root.get_texture().get_image()


## Waits until this frame is drawn, the screen and every view with it.
func frame_drawn() -> void:
	_set_drawing(true)
	await RenderingServer.frame_post_draw
	_set_drawing(false)


## Draw the screen this frame (`on`), or leave it undrawn unless `draw_between` says it is drawn
## every frame.
func _set_drawing(on: bool) -> void:
	if _drawn_frames != null:
		_drawn_frames.drawing = on or draw_between


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
	var crop: Image = crop_round(image, at, half)
	if zoom != 1:
		crop.resize(crop.get_width() * zoom, crop.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	save(crop, shot_name)


## The `half` × 2 layout pixels of `image` round the screen point `at` (kept inside the image), at the
## screen's scale: `half` times the picture's scale in picture pixels, so a crop shows as much of the
## game in any picture, as finely as it is drawn.
func crop_round(image: Image, at: Vector2, half: Vector2i = Vector2i(48, 48)) -> Image:
	var scale_to_image: Vector2 = Vector2(image.get_size()) / Vector2(root.get_visible_rect().size)
	half *= sheet_scale()
	var middle := Vector2i(at * scale_to_image)
	var corner: Vector2i = (middle - half).clamp(Vector2i.ZERO, image.get_size() - half * 2)
	return image.get_region(Rect2i(corner, half * 2))


## `save_crop` of the screen as it is drawn this frame, round the world point `at`.
func snap(at: Vector2, shot_name: String, half: Vector2i = Vector2i(48, 48), zoom: int = 4) -> void:
	save_crop(await grab(), on_screen(at), shot_name, half, zoom)


## One press and release of `action` on the virtual device of `player`.
func tap(player: int, action: StringName) -> void:
	var input: Node = root.get_node("PlayerInput")
	input.call("send_virtual", player, action, 1.0)
	input.call("send_virtual", player, action, 0.0)


## Picture pixels a layout pixel (PictureGrid): what a sheet laid out on SCREEN is drawn at.
func sheet_scale() -> int:
	return PictureGrid.scale_in(root)


## The crypt floor tiled over the whole screen, behind everything a sheet adds.
func lay_floor() -> void:
	var floor_sprite := Sprite2D.new()
	floor_sprite.texture = FLOOR
	floor_sprite.centered = false
	floor_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	floor_sprite.region_enabled = true
	floor_sprite.region_rect = Rect2(Vector2.ZERO, SCREEN * float(ArtDetail.of(FLOOR)))
	floor_sprite.scale = ArtDetail.draw_scale(FLOOR) * float(sheet_scale())
	floor_sprite.z_index = -10
	root.add_child(floor_sprite)


## `texture` with its top left corner at `at` (layout pixels), `scale` times its size in the world
## (ArtDetail: a 2x texture's at half), unfiltered, at the picture's scale.
func place(texture: Texture2D, scale: float, at: Vector2, tint: Color = Color.WHITE) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(scale, scale) * float(sheet_scale()) * ArtDetail.draw_scale(texture)
	sprite.position = at * float(sheet_scale())
	sprite.modulate = tint
	root.add_child(sprite)
	return sprite


func label(text: String, at: Vector2, font_size: int = 10) -> void:
	var line := Label.new()
	line.text = text
	line.position = at * float(sheet_scale())
	line.scale = Vector2.ONE * float(sheet_scale())
	line.add_theme_font_size_override("font_size", font_size)
	root.add_child(line)
