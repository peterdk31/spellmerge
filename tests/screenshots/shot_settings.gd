extends "res://tests/support/screenshot.gd"
## Screenshots of the pause menu's Settings page over a crypt run (hud/menus/pause/pause_menu.gd;
## docs/milestones/atmosphere.md, "Settings"): one page of tabs (owner, 2026-11-18), the LB and RB
## glyphs at the tab row's ends and the B glyph's "Back" under the rows, the panel one size on every
## tab and inside the 640 x 360 view, its text at 14 px, the focused row marked with "> ".
##
## Shots: `settings_graphics` (Fullscreen, Dynamic lighting, Shadows, Fog, Ambient particles,
## Environment interaction, Floor marks; Dynamic lighting focused), `settings_graphics_unlit`
## (Dynamic lighting off: Shadows, Fog and Ambient particles greyed), `settings_performance`,
## `settings_audio` (Ambience volume a step down, at 90%) and `settings_interface`, each reached with
## RB, then `settings_keyboard` (P2 on the keyboard: the Z and C keys at the ends, E for Back; on
## Interface after Z from Graphics, round from the first tab). Each fails if the menu does not fit
## the view or is not the size of the first. The choices are put back as they were after.

## The menu's box on the first shot, which every other shot must match in size.
var _first_box: Rect2 = Rect2()


func take() -> void:
	if not need(["PlayerInput", "Flow", "Hud", "UIFocus"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var hud: Node = root.get_node("Hud")
	var ui_focus: Node = root.get_node("UIFocus")
	input.call("add_virtual_device", 0)
	flow.call("start_run", 0)
	await settle()
	tap(0, &"pause")
	await settle()
	var menu: Control = hud.call("get_pause_menu") as Control
	if not menu.call("is_open"):
		fail("the pause menu did not open")
		return
	await _press(ui_focus, menu, "Settings")
	ui_focus.call("focus", 0, menu.call("button", "SpellLight"))
	await settle()
	if not await _shot_fitting(menu, "settings_graphics"):
		return
	await _press(ui_focus, menu, "SpellLight")
	if not await _shot_fitting(menu, "settings_graphics_unlit"):
		return
	await _press(ui_focus, menu, "SpellLight")
	for tab_name: String in ["Performance", "Audio", "Interface"]:
		tap(0, &"page_next")
		await settle()
		if tab_name == "Audio":
			tap(0, &"move_left")
			await settle()
		if not await _shot_fitting(menu, "settings_" + tab_name.to_lower()):
			return
		if tab_name == "Audio":
			tap(0, &"move_right")
			await settle()
	tap(0, &"pause")
	await settle()
	# P2 on the keyboard: Escape opens the menu, Z (`page_prev`) pages from Graphics round to Interface.
	input.call("join_as", -1, 1)
	await settle()
	await _key(input, KEY_ESCAPE)
	if not menu.call("is_open"):
		fail("Escape did not open the pause menu for P2")
		return
	ui_focus.call("focus", 1, menu.call("button", "Settings"))
	ui_focus.call("activate", 1)
	await settle()
	await _key(input, KEY_Z)
	if not await _shot_fitting(menu, "settings_keyboard"):
		return
	await _key(input, KEY_ESCAPE)


## `button_name` on the menu focused and pressed by P1.
func _press(ui_focus: Node, menu: Control, button_name: String) -> void:
	ui_focus.call("focus", 0, menu.call("button", button_name))
	tap(0, &"accept")
	await settle()


## A key pressed and let go on the keyboard.
func _key(input: Node, code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = down
		input.call("handle_event", event)
	await settle()


## The screen saved as `shot_name`, if the menu fits the view and is the first shot's size (it fails
## otherwise).
func _shot_fitting(menu: Control, shot_name: String) -> bool:
	await settle()
	var box: Rect2 = menu.get_global_rect()
	if box.position.y < 0.0 or box.end.y > SCREEN.y or box.position.x < 0.0 or box.end.x > SCREEN.x:
		fail("%s: the menu (%s) does not fit the %s view" % [shot_name, box, SCREEN])
		return false
	if _first_box.size == Vector2.ZERO:
		_first_box = box
	elif box.size != _first_box.size:
		fail("%s: the menu (%s) is not the size of the first tab's (%s)" % [shot_name, box, _first_box])
		return false
	print("%s: the menu at %s" % [shot_name, box])
	save(await grab(), shot_name)
	return true
