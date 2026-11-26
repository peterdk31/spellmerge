extends "res://tests/support/screenshot.gd"
## Screenshots of Oil and Spill (docs/milestones/oil-spill.md) in the crypt's first arena: a slick of
## oil shown in each of its states (oiling, oiled, catching, burning, burning down, scorched, the
## scorch fading, and a fire put out), frame strips of the oil's sheen and of its fire, an oil bolt's
## trail lit and burning, and Spill on each carrier (a water card with Spill, so the splash shows).
##
## Shots: `oil_states` (every state side by side, 2x), `oil_sheen_strip`, `oil_fire_strip`,
## `oil_catch_strip`, `oil_trail_burning` (the whole picture), `spill_carriers` (each carrier with
## Spill and a bolt without, 2x).

const STAFF := preload("res://content/wizard/staffs/curl/curl.tres")
## The slick's touches: circles round its middle (px from it), and their radius.
const SLICK: Array[Vector2] = [Vector2(0, 0), Vector2(22, 4), Vector2(-20, 8), Vector2(6, 18), Vector2(-6, -16), Vector2(30, -12), Vector2(-32, -6)]
const SLICK_RADIUS: float = 15.0
const HALF := Vector2i(64, 44)
const STRIP_HALF := Vector2i(36, 26)
const SPILL_HALF := Vector2i(52, 36)
const GAP: int = 2
## The carriers shown with Spill (and the bolt first without).
const CARRIERS: Array[StringName] = [&"bolt", &"atom", &"spray", &"pool", &"pulse", &"rune", &"beam", &"swing", &"slam", &"dash"]

var _events: Node = null
var _middle: Vector2 = Vector2.ZERO
var _sheet: Array[Image] = []
var _names: PackedStringArray = PackedStringArray()


func take() -> void:
	if not need(["PlayerInput", "Flow", "Registry", "Feel", "Events", "Spells"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var spells: Node = root.get_node("Spells")
	_events = root.get_node("Events")
	input.call("add_virtual_device", 0)
	if not flow.call("start_run", 0):
		fail("the run did not start")
		return
	await settle(30)
	var wizard: Actor = flow.call("get_wizard", 0) as Actor
	if wizard == null:
		fail("no wizard")
		return
	# Kept from the room's foes while the slick plays out (it shows translucent).
	Downed.of(wizard).protect(120.0)
	var home: Vector2 = wizard.global_position
	wizard.global_position += Vector2(-40.0, 0.0)
	_middle = home + Vector2(90.0, 0.0)
	# The states of one slick.
	_slick(&"oil")
	await settle(2)
	await _keep("oiling")
	await settle(30)
	await _keep("oiled")
	await _strip("oil_sheen_strip", 8, 10)
	_touch(&"fire", _middle + SLICK[6], 0.0)
	await _strip("oil_catch_strip", 6, 3, STRIP_HALF, SLICK[6])
	await _keep("catching")
	await settle(40)
	await _keep("burning")
	await _strip("oil_fire_strip", 6, 2)
	if not await wait_for(func() -> bool: return _state_here() == &"burning_down", 60 * 8):
		fail("the fire did not burn down (%s)" % _state_here())
		return
	await _keep("burning down")
	await settle(40)
	await _keep("scorched")
	if not await wait_for(func() -> bool: return _state_here() == &"dry", 60 * 12):
		fail("the scorch stayed (%s)" % _state_here())
		return
	await settle(30)
	await _keep("scorch fading")
	# A fresh run (the room's foes may have downed the wizard by now), the slick laid again.
	wizard = await _fresh_run(flow)
	if wizard == null:
		return
	home = wizard.global_position
	wizard.global_position += Vector2(-40.0, 0.0)
	_middle = home + Vector2(90.0, 0.0)
	_slick(&"oil")
	await settle(30)
	_touch(&"fire", _middle, 0.0)
	await settle(30)
	_touch(&"water", _middle, 60.0)
	await settle(6)
	await _keep("put out")
	await settle(30)
	await _keep("oil again")
	_save_sheet()
	wizard = await _fresh_run(flow)
	if wizard == null:
		return
	home = wizard.global_position
	# An oil trail, a cell wide, as an oil bolt passing leaves one (a touch every 16 px along its way),
	# lit at its start: a line of fire.
	var from: Vector2 = home + Vector2(-60.0, -70.0)
	for n in 14:
		_touch(&"oil", from + Vector2(16.0 * float(n), 0.0), 0.0)
	await settle(90)
	_touch(&"fire", from + Vector2(24.0, 0.0), 0.0)
	await settle(45)
	_middle = from + Vector2(110.0, 0.0)
	await _strip("oil_trail_strip", 4, 20, Vector2i(140, 30))
	await shot("oil_trail_burning")
	wizard = await _fresh_run(flow)
	if wizard == null:
		return
	await _spills(spells, wizard, wizard.global_position)


## Each carrier with Spill (and a bolt without), Water on it so its splash shows, each cast from a
## place of its own, cropped where it lands.
func _spills(spells: Node, wizard: Actor, home: Vector2) -> void:
	var crops: Array[Image] = []
	var names := PackedStringArray()
	var at: int = 0
	for n in CARRIERS.size() + 1:
		var carrier: StringName = CARRIERS[maxi(n - 1, 0)]
		var cards: Array[StringName] = [&"water", carrier]
		if n > 0:
			cards = [&"water", &"spill", carrier]
		var from: Vector2 = home + Vector2(-150.0 + 120.0 * float(at % 4), -100.0 + 70.0 * float(at / 4))
		at += 1
		wizard.global_position = from
		spells.call("install_staff", wizard.id, 3, spells.call("compile_staff", cards, STAFF))
		await settle(6)
		wizard.global_position = from
		spells.call("cast_staff", wizard.id, 3, from, Vector2.RIGHT, 100.0)
		await settle(50)
		wizard.global_position = from + Vector2(0.0, 30.0)
		await settle(2)
		var image: Image = await grab()
		var crop: Image = crop_round(image, on_screen(from + Vector2(48.0, 0.0)), SPILL_HALF)
		crop.convert(Image.FORMAT_RGBA8)
		crops.append(crop)
		names.append(("%s, Spill" if n > 0 else "%s, no Spill") % carrier)
		if at >= 8:
			# The floor dries before the next row is cast over it.
			await settle(60 * 13)
			at = 0
	_save(crops, "spill_carriers", 4)
	print("spill_carriers: ", ", ".join(names))


## A new run, its first wizard (null, and the script failed, when there is none).
func _fresh_run(flow: Node) -> Actor:
	flow.call("stop_run")
	await settle(10)
	if not flow.call("start_run", 0):
		fail("a run did not start")
		return null
	await settle(30)
	var wizard: Actor = flow.call("get_wizard", 0) as Actor
	if wizard == null:
		fail("no wizard")
		return null
	Downed.of(wizard).protect(120.0)
	return wizard


## The state of the floor's cell at the slick's middle.
func _state_here() -> StringName:
	var cover: Node = root.get_node_or_null("Cover")
	if cover == null:
		return &""
	var state: CoverState = cover.call("cover_state_at", (cover.get("layout") as CoverLayout).cell_of(_middle))
	return state.state_id if state != null else &""


func _slick(element: StringName) -> void:
	for at in SLICK:
		_touch(element, _middle + at, SLICK_RADIUS)


func _touch(element: StringName, at: Vector2, radius: float) -> void:
	_events.emit_signal("floor_touched", -1, element, at, radius, 0)


func _keep(label_text: String) -> void:
	var image: Image = await grab()
	var crop: Image = crop_round(image, on_screen(_middle), HALF)
	crop.convert(Image.FORMAT_RGBA8)
	_sheet.append(crop)
	_names.append(label_text)


func _save_sheet() -> void:
	_save(_sheet, "oil_states", 4)
	print("oil_states: ", ", ".join(_names))


func _save(crops: Array[Image], shot_name: String, columns: int) -> void:
	var cell: Vector2i = crops[0].get_size() if not crops.is_empty() else HALF * 2
	var rows: int = (crops.size() + columns - 1) / columns
	var sheet := Image.create((cell.x + GAP) * columns, (cell.y + GAP) * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.05, 0.07))
	for at in crops.size():
		var crop: Image = crops[at]
		var size: Vector2i = Vector2i(mini(crop.get_width(), cell.x), mini(crop.get_height(), cell.y))
		sheet.blit_rect(crop, Rect2i(Vector2i.ZERO, size), Vector2i((at % columns) * (cell.x + GAP), (at / columns) * (cell.y + GAP)))
	sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	save(sheet, shot_name)


## `count` frames round the slick's middle (and `offset`), `every` frames apart, side by side at 2x.
func _strip(shot_name: String, count: int, every: int, half: Vector2i = STRIP_HALF, offset: Vector2 = Vector2.ZERO) -> void:
	var strip: Image = null
	var cell: Vector2i = Vector2i.ZERO
	for column in count:
		var image: Image = await grab()
		var crop: Image = crop_round(image, on_screen(_middle + offset), half)
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
