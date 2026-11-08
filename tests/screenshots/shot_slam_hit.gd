extends "res://tests/support/screenshot.gd"
## A slam's blow as frames (the owner, 2026-11-08: "it should really look like it hits hard: start a
## bit slower, then accelerate, and a hard hit on the floor"): player 1 slams to the right and the
## crop round it is taken every FRAME_STEP frames from FIRST, side by side, left to right: the
## hammer raised and trembling, the drop barely starting and then whipping down (its key eases
## "slam"), the impact (the slam cue: burst, shockwave, dust, chips, light, shake) and the squash
## after. `slam_hit` is the strip at 3x.

const STAFF := preload("res://content/wizard/staffs/curl/curl.tres")
## The frames from the cast the strip shows (60 a second; a 0.25 s wind-up, then the impact).
const FIRST: int = 8
const FRAME_STEP: int = 2
const FRAMES: int = 10
## The crop round the wizard, half its size each way in pixels, and where it is from the wizard.
const HALF: Vector2i = Vector2i(36, 36)
const OFFSET: Vector2 = Vector2(14.0, -18.0)


func take() -> void:
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await settle()
	if not need(["PlayerInput", "Flow", "Spells", "Feel"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var spells: Node = root.get_node("Spells")
	root.get_node("Feel").set("drive_engine", false)
	input.call("add_virtual_device", 0)
	flow.call("start_run", 0)
	await settle(30)
	var wizard: Actor = flow.call("get_wizard", 0) as Actor
	if wizard == null:
		fail("there is no wizard for player 1")
		return
	var at: Vector2 = wizard.global_position + Vector2(-40.0, 20.0)
	wizard.global_position = at
	input.call("send_virtual_aim", 0, Vector2.RIGHT)
	var cards: Array[StringName] = [&"slam"]
	spells.call("install_staff", wizard.id, 3, spells.call("compile_staff", cards, STAFF))
	# The camera follows the group: let it come round.
	await settle(40)
	var strip := Image.create(HALF.x * 2 * FRAMES, HALF.y * 2, false, Image.FORMAT_RGBA8)
	wizard.global_position = at
	spells.call("cast_staff", wizard.id, 3, at, Vector2.RIGHT, 100.0)
	for frame in FIRST + FRAME_STEP * FRAMES:
		var image: Image = await grab()
		var shown: int = frame - FIRST
		if shown < 0 or shown % FRAME_STEP != 0:
			continue
		image.convert(Image.FORMAT_RGBA8)
		var scale_to_image: Vector2 = Vector2(image.get_size()) / Vector2(root.get_visible_rect().size)
		var middle := Vector2i(on_screen(at + OFFSET) * scale_to_image)
		var corner: Vector2i = (middle - HALF).clamp(Vector2i.ZERO, image.get_size() - HALF * 2)
		strip.blit_rect(image, Rect2i(corner, HALF * 2), Vector2i(HALF.x * 2 * (shown / FRAME_STEP), 0))
	strip.resize(strip.get_width() * 3, strip.get_height() * 3, Image.INTERPOLATE_NEAREST)
	save(strip, "slam_hit")
