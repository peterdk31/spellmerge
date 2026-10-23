extends SceneTree
## The button glyphs, one row per kind of controller (keyboard, keyboard with the mouse, Xbox,
## PlayStation, Switch and a plain gamepad) and one column per action (cast, dodge, overlay,
## swap, join, leave), at 3x, with the builder's hint line under them at 1x for each kind.
## Needs a display, so it runs only through `ci/build/build.sh --quick --screenshots`; the shot
## is saved as user://screenshots/glyphs_sheet.png and copied to build/screenshots/.

const InputManagerScript := preload("res://core/input/input_manager.gd")
const ActionGlyphScript := preload("res://hud/widgets/action_glyph.gd")
const HintLineScript := preload("res://hud/widgets/hint_line.gd")

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 10
const ACTIONS: Array[StringName] = [&"cast", &"dodge", &"overlay", &"swap", &"join", &"leave"]
const PAD_NAMES: Dictionary = {0: "Xbox One Controller", 1: "PS5 Controller", 2: "Nintendo Switch Pro Controller", 3: "Generic Pad"}
const ROW_HEIGHT: float = 44.0


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var background := ColorRect.new()
	background.color = Color(0.1, 0.11, 0.16)
	background.size = Vector2(640, 360)
	root.add_child(background)
	var pads := InputManagerScript.new()
	pads.joy_name_provider = func(device: int) -> String: return String(PAD_NAMES.get(device, ""))
	var keys := InputManagerScript.new()
	for device in 4:
		pads.join(device)
	keys.join(InputManagerScript.KEYBOARD)
	var mouse := InputManagerScript.new()
	mouse.join(InputManagerScript.KEYBOARD)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	mouse.handle_event(click)
	var rows: Array = [[keys, 0], [mouse, 0], [pads, 0], [pads, 1], [pads, 2], [pads, 3]]
	for row in rows.size():
		var manager: InputManagerScript = rows[row][0]
		var player: int = rows[row][1]
		var line := Control.new()
		line.position = Vector2(12.0, 8.0 + ROW_HEIGHT * row)
		line.scale = Vector2(3.0, 3.0)
		root.add_child(line)
		var x: float = 0.0
		for action in ACTIONS:
			var glyph: ActionGlyphScript = ActionGlyphScript.new()
			glyph.bind(manager)
			line.add_child(glyph)
			glyph.show_action(player, action)
			glyph.position = Vector2(x, 0.0)
			x += glyph.custom_minimum_size.x + 8.0
		var hint: HintLineScript = HintLineScript.new()
		hint.bind(manager)
		hint.position = Vector2(540.0, 8.0 + ROW_HEIGHT * row)
		root.add_child(hint)
		hint.show_hint(player, &"cast", "Use", &"dodge", "back")
	await _settle()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	for manager: Node in [pads, keys, mouse]:
		manager.free()
	var path: String = "%s/glyphs_sheet.png" % SHOTS_DIR
	if image == null or image.save_png(path) != OK:
		printerr("SHOT FAILED: could not save " + path)
		quit(1)
		return
	print("SHOT: glyphs_sheet (%dx%d)" % [image.get_width(), image.get_height()])
	quit(0)


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame
