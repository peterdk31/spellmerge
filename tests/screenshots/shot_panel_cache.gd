extends "res://tests/support/screenshot.gd"
## The corner panels drawn once (`hud/widgets/cached_view.gd`; the owner, 2026-11-21) against the
## same panels drawn live, in the same frame's state: each pair is the panel from its picture, then
## the content moved back out of the picture and drawn as it was before, each row drawing its own
## shade and mana line (`PlayerPanel.set_drawn_live`),
## over a fixed backdrop of every shade (the world's own pixels move from frame to frame), so the
## two differ only by how the panel is drawn. Each pair prints `PANEL CACHE: <shot>: <n> px differ,
## most <d> of 255` and saves the cached crop, the live crop and the difference (a pixel that
## differs at all in white; `panel_cache_<shot>_{cached,live,diff}`), and the whole screen
## (`panel_cache_<shot>_screen`), which a checkout from before the cache takes too, to compare.
##
## States: one player just after casting (the cooldown's sweep part way, the mana lines eased, a key,
## the purse), with a quick-use slot bound and recharging (the D-pad cross), the next-cast style, and
## four players' corners.

const DevHub := preload("res://tests/support/dev_hub.gd")
const ShotStaffs := preload("res://tests/screenshots/shot_hud_staffs.gd")
const ICON_PATH: String = "res://icon.svg"
const HALF := Vector2i(64, 52)

var _input: Node = null
var _flow: Node = null
var _hud: Node = null


func take() -> void:
	if not need(["PlayerInput", "Hud", "Flow", "Events"]):
		return
	_input = root.get_node("PlayerInput")
	_flow = root.get_node("Flow")
	_hud = root.get_node("Hud")
	for index in 4:
		_input.call("add_virtual_device", index)
	if not DevHub.start(_flow, root.get_node("Registry"), ShotStaffs.CARDS):
		fail("the hub did not start")
		return
	if not await wait_for(func() -> bool: return _flow.call("get_wizard", 3) != null):
		fail("the hub has no wizards")
		return
	_backdrop()
	await settle(5)
	for index in 4:
		_input.call("send_virtual_aim", index, Vector2.UP)
	for round in 2:
		for index in 4:
			var casts: Array = ShotStaffs.CASTS[index]
			if round < casts.size():
				tap(index, casts[round])
		await settle(8)
	await settle(6)
	var panel: Node = _hud.call("get_panel", 0)
	var icon: Texture2D = load(ICON_PATH) as Texture2D
	panel.call("set_quick", 0, icon, 3, true)
	panel.call("set_quick", 1, icon, 0, true)
	panel.call("set_quick_recharge", 0, 0.5, 1.0, true)
	panel.call("set_keys", 2, true)
	panel.call("set_purse", 14, 1)
	await settle(2)
	await _pair("cooldown_quick", [0])
	await _pair("four_corners", [0, 1, 2, 3])
	_hud.call("_on_reload_style_changed", false)
	await settle(2)
	await _pair("next_cast", [0])
	_hud.call("_on_reload_style_changed", true)
	_flow.call("stop_run")
	await create_timer(0.3).timeout


## A backdrop over the world and under the HUD, every shade of a 64-step ramp in stripes, the same
## every frame.
func _backdrop() -> void:
	var image := Image.create(640, 360, false, Image.FORMAT_RGB8)
	for y in 360:
		for x in 640:
			image.set_pixel(x, y, Color8((x * 7 + y * 3) % 256, (x * 3 + y * 11) % 256, (x * 13 + y * 5) % 256))
	var layer := CanvasLayer.new()
	layer.layer = 9
	var rect := TextureRect.new()
	rect.texture = ImageTexture.create_from_image(image)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	root.add_child(layer)


## The panels of `seats` from their pictures, then live, the HUD held still between.
func _pair(shot_name: String, seats: Array) -> void:
	_hud.set_process(false)
	await settle(2)
	var cached: Image = await grab()
	# The whole screen too, to set beside the same shot taken before the panels were cached (a
	# checkout from before has no `cache`: there this is the only shot).
	save(cached, "panel_cache_%s_screen" % shot_name)
	if not _hud.call("get_panel", 0).has_method(&"cache"):
		# The same frames pass as for the live shot, so the next state is the same.
		await settle(2)
		await grab()
		_hud.set_process(true)
		return
	for seat: int in seats:
		_hud.call("get_panel", seat).call("set_drawn_live", true)
	await settle(2)
	var live: Image = await grab()
	for seat: int in seats:
		_hud.call("get_panel", seat).call("set_drawn_live", false)
	_hud.set_process(true)
	var differ: int = 0
	var most: int = 0
	var diff := Image.create(cached.get_width(), cached.get_height(), false, Image.FORMAT_RGB8)
	for y in cached.get_height():
		for x in cached.get_width():
			var a: Color = cached.get_pixel(x, y)
			var b: Color = live.get_pixel(x, y)
			var d: int = maxi(maxi(absi(a.r8 - b.r8), absi(a.g8 - b.g8)), absi(a.b8 - b.b8))
			if d > 0:
				differ += 1
				most = maxi(most, d)
				diff.set_pixel(x, y, Color.WHITE)
	print("PANEL CACHE: %s: %d px differ, most %d of 255" % [shot_name, differ, most])
	var corner: Vector2 = ShotStaffs.CORNERS[seats[0]] if seats.size() == 1 else Vector2(320, 180)
	var half: Vector2i = HALF if seats.size() == 1 else Vector2i(320, 180)
	var zoom: int = 3 if seats.size() == 1 else 1
	save_crop(cached, corner, "panel_cache_%s_cached" % shot_name, half, zoom)
	save_crop(live, corner, "panel_cache_%s_live" % shot_name, half, zoom)
	save_crop(diff, corner, "panel_cache_%s_diff" % shot_name, half, zoom)
