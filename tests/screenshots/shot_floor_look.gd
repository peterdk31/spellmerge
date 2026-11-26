extends "res://tests/support/screenshot.gd"
## Screenshots of the floor's look (docs/milestones/floor-look.md): one big lake in the crypt's first
## arena beside the first wizard, shown in each of its states (wet, live, spent, freezing, ice,
## thawing, steam, the scorch steam leaves, a puddle drying and the damp it leaves), and short frame
## strips of each animation (water's shimmer, live water's crackle, ice's twinkle, steam's wisps).
## Run in a 1920 x 1080 window (`--resolution 1920x1080` on a screen that size) it shows the picture
## stretched 1.5 times, as on a 1080p screen.
##
## Shots: `floor_look_states` (every state side by side, 2x), `floor_look_room` (the room with a live
## lake, the whole picture), `floor_look_shimmer_strip`, `floor_look_live_strip`,
## `floor_look_ice_strip`, `floor_look_steam_strip` (frames of each animation, 2x).

## The lake's touches: circles round its middle (px from it), and their radius.
const LAKE: Array[Vector2] = [Vector2(0, 0), Vector2(22, 4), Vector2(-20, 8), Vector2(6, 18), Vector2(-6, -16), Vector2(30, -12), Vector2(-32, -6)]
const LAKE_RADIUS: float = 15.0
const HALF := Vector2i(64, 44)
const STRIP_HALF := Vector2i(28, 20)
const GAP: int = 2

var _events: Node = null
var _middle: Vector2 = Vector2.ZERO
var _sheet: Array[Image] = []
var _names: PackedStringArray = PackedStringArray()


func take() -> void:
	if not need(["PlayerInput", "Flow", "Registry", "Feel", "Events"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	_events = root.get_node("Events")
	input.call("add_virtual_device", 0)
	if not flow.call("start_run", 0):
		fail("the run did not start")
		return
	await settle(30)
	var wizard: Node2D = flow.call("get_wizard", 0) as Node2D
	if wizard == null:
		fail("no wizard")
		return
	# Out of the lake's reach, so its lightning never downs it.
	wizard.global_position += Vector2(-40.0, 0.0)
	_middle = wizard.global_position + Vector2(130.0, 0.0)
	_lake()
	await settle(40)
	await _keep("wet")
	await _strip("floor_look_shimmer_strip", 8, 10)
	_touch(&"lightning", _middle + LAKE[2], 0.0)
	await settle(8)
	await _keep("live")
	await shot("floor_look_room")
	await _strip("floor_look_live_strip", 6, 2)
	await settle(30)
	await _keep("spent")
	await settle(100)
	_touch(&"frost", _middle, 50.0)
	await settle(10)
	await _keep("freezing")
	await settle(40)
	await _keep("ice")
	await _strip("floor_look_ice_strip", 8, 10)
	_touch(&"fire", _middle, 50.0)
	await settle(10)
	await _keep("thawing")
	await settle(40)
	_lake()
	await settle(30)
	_touch(&"fire", _middle, 50.0)
	await _strip("floor_look_steam_strip", 8, 1)
	await _keep("after steam")
	await settle(60)
	await _keep("scorch fades")
	# A fresh run for a puddle left to dry (12 s): the room's foes may have downed the wizard by now.
	flow.call("stop_run")
	await settle(10)
	if not flow.call("start_run", 0):
		fail("the second run did not start")
		return
	await settle(30)
	wizard = flow.call("get_wizard", 0) as Node2D
	wizard.global_position += Vector2(-40.0, 0.0)
	_middle = wizard.global_position + Vector2(130.0, 0.0)
	_lake()
	if not await wait_for(func() -> bool: return _state_here() == &"drying", 60 * 30):
		fail("the puddle did not dry (%s)" % _state_here())
		return
	await _keep("drying")
	await wait_for(func() -> bool: return _state_here() == &"dry", 120)
	await settle(20)
	await _keep("damp")
	_save_sheet()


## The state of the floor's cell at the lake's middle.
func _state_here() -> StringName:
	var cover: Node = root.get_node_or_null("Cover")
	if cover == null:
		return &""
	var state: CoverState = cover.call("cover_state_at", (cover.get("layout") as CoverLayout).cell_of(_middle))
	return state.state_id if state != null else &""


## Water over the lake's circles.
func _lake() -> void:
	for at in LAKE:
		_touch(&"water", _middle + at, LAKE_RADIUS)


func _touch(element: StringName, at: Vector2, radius: float) -> void:
	_events.emit_signal("floor_touched", -1, element, at, radius, 0)


## The lake now, kept for the states' sheet under `label_text`.
func _keep(label_text: String) -> void:
	var image: Image = await grab()
	var crop: Image = crop_round(image, on_screen(_middle), HALF)
	crop.convert(Image.FORMAT_RGBA8)
	_sheet.append(crop)
	_names.append(label_text)


func _save_sheet() -> void:
	var cell: Vector2i = _sheet[0].get_size() if not _sheet.is_empty() else HALF * 2
	var columns: int = 4
	var rows: int = (_sheet.size() + columns - 1) / columns
	var sheet := Image.create((cell.x + GAP) * columns, (cell.y + GAP) * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.05, 0.07))
	for at in _sheet.size():
		var crop: Image = _sheet[at]
		var size: Vector2i = Vector2i(mini(crop.get_width(), cell.x), mini(crop.get_height(), cell.y))
		sheet.blit_rect(crop, Rect2i(Vector2i.ZERO, size), Vector2i((at % columns) * (cell.x + GAP), (at / columns) * (cell.y + GAP)))
	sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	save(sheet, "floor_look_states")
	print("floor_look_states: ", ", ".join(_names))


## `count` frames of the lake's middle, `every` frames apart, side by side at 2x, as `shot_name`.
func _strip(shot_name: String, count: int, every: int) -> void:
	var strip: Image = null
	var cell: Vector2i = Vector2i.ZERO
	for column in count:
		var image: Image = await grab()
		var crop: Image = crop_round(image, on_screen(_middle + Vector2(-20.0, 8.0)), STRIP_HALF)
		crop.convert(Image.FORMAT_RGBA8)
		if strip == null:
			cell = crop.get_size()
			strip = Image.create((cell.x + GAP) * count, cell.y, false, Image.FORMAT_RGBA8)
			strip.fill(Color(0.05, 0.05, 0.07))
		var size: Vector2i = Vector2i(mini(crop.get_width(), cell.x), mini(crop.get_height(), cell.y))
		strip.blit_rect(crop, Rect2i(Vector2i.ZERO, size), Vector2i(column * (cell.x + GAP), 0))
		await settle(every)
	strip.resize(strip.get_width() * 2, strip.get_height() * 2, Image.INTERPOLATE_NEAREST)
	save(strip, shot_name)
