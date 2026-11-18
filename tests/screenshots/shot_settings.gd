extends "res://tests/support/screenshot.gd"
## Screenshots of the pause menu's Settings pages over a crypt run (hud/menus/pause/pause_menu.gd;
## docs/milestones/atmosphere.md, "Settings"): each page fits the 640 x 360 view and reads at its
## 14 px text, the focused row marked with "> ".
##
## Shots: `settings_pages` (the Settings page: Graphics, Performance, Audio, Interface, Back),
## `settings_graphics` (Fullscreen, Dynamic lighting, Shadows, Fog, Ambient particles, Environment
## interaction, Floor marks, Back; Dynamic lighting focused), `settings_graphics_unlit` (Dynamic
## lighting off: Shadows, Fog and Ambient particles greyed), `settings_performance`,
## `settings_audio` (Ambience volume a step down, at 90%) and `settings_interface`. Each fails if the
## menu does not fit the view. The choices are put back as they were after.


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
	if not await _shot_fitting(menu, "settings_pages"):
		return
	await _press(ui_focus, menu, "Graphics")
	ui_focus.call("focus", 0, menu.call("button", "SpellLight"))
	await settle()
	if not await _shot_fitting(menu, "settings_graphics"):
		return
	await _press(ui_focus, menu, "SpellLight")
	if not await _shot_fitting(menu, "settings_graphics_unlit"):
		return
	await _press(ui_focus, menu, "SpellLight")
	for page: String in ["Performance", "Audio", "Interface"]:
		tap(0, &"back")
		await settle()
		await _press(ui_focus, menu, page)
		if page == "Audio":
			tap(0, &"move_left")
			await settle()
		if not await _shot_fitting(menu, "settings_" + page.to_lower()):
			return
		if page == "Audio":
			tap(0, &"move_right")
			await settle()
	tap(0, &"pause")
	await settle()


## `button_name` on the menu focused and pressed by P1.
func _press(ui_focus: Node, menu: Control, button_name: String) -> void:
	ui_focus.call("focus", 0, menu.call("button", button_name))
	tap(0, &"accept")
	await settle()


## The screen saved as `shot_name`, if the menu fits the view (it fails otherwise).
func _shot_fitting(menu: Control, shot_name: String) -> bool:
	await settle()
	var box: Rect2 = menu.get_global_rect()
	if box.position.y < 0.0 or box.end.y > SCREEN.y or box.position.x < 0.0 or box.end.x > SCREEN.x:
		fail("%s: the menu (%s) does not fit the %s view" % [shot_name, box, SCREEN])
		return false
	print("%s: the menu at %s" % [shot_name, box])
	save(await grab(), shot_name)
	return true
