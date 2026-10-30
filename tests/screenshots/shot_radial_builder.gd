extends "res://tests/support/screenshot.gd"
## Screenshots of the radial builder, the default builder (owner, 2026-10-26).
##
## Card sheets first: every real card the registry found (so a new card adds itself), pointed at
## in turn, its ring and hub cropped into sheets of eight (radial_cards_1, radial_cards_2, ...).
## Then shots, in the sandbox with the radial builder picked: one player pointing at a nova (the hub
## shows its numbers, the marked slot its ghost, the numbers what RT would change), then after
## two cards were put in, the one-kind ring on the modifiers, a clear held half way, and all four
## players with their radials open at once.

## A card sheet: crops of SHEET_CROP px round the ring's middle, SHEET_COLUMNS by SHEET_ROWS.
const SHEET_CROP := 150
const SHEET_COLUMNS := 4
const SHEET_ROWS := 2
const SHEET_FRAMES := 8

var _input: Node = null
var _hud: Node = null


func take() -> void:
	if not need(["PlayerInput", "Hud", "Flow", "Events"]):
		return
	_input = root.get_node("PlayerInput")
	_hud = root.get_node("Hud")
	var flow: Node = root.get_node("Flow")
	var events: Node = root.get_node("Events")
	for index in 4:
		_input.call("add_virtual_device", index)
	events.emit_signal("sandbox_requested", 0)
	if not await wait_for(func() -> bool: return flow.call("get_wizard", 3) != null):
		fail("the sandbox did not start with four wizards")
		return
	_hud.call("_on_builder_options_changed", true, 0, true)
	if not await _open([0]):
		return
	var radial: Node = _hud.call("get_radial", 0)
	await _card_sheets(radial)
	await _point(0, &"nova", true)
	await shot("radial_pointing")
	tap(0, &"staff_2")
	await _point(0, &"split", true)
	tap(0, &"staff_2")
	await _point(0, &"homing", true)
	await shot("radial_built")
	_hud.call("_on_builder_options_changed", true, 1, true)
	tap(0, &"kind_next")
	await settle(SHEET_FRAMES)
	await _point(0, &"pierce", true)
	await shot("radial_one_kind")
	_input.call("send_virtual", 0, &"extra", 1.0)
	await create_timer(0.3).timeout
	await shot("radial_clearing")
	_input.call("send_virtual", 0, &"extra", 0.0)
	_hud.call("_on_builder_options_changed", true, 0, true)
	if not await _open([1, 2, 3]):
		return
	var cards: Array[StringName] = [&"bolt", &"frost", &"orbit", &"chain"]
	for index in 4:
		_input.call("send_virtual_aim", index, _hud.call("get_radial", index).call("direction_to", cards[index]))
	await shot("radial_four_players")
	for index in 4:
		tap(index, &"back")
	await settle(SHEET_FRAMES)
	flow.call("stop_run")
	await create_timer(0.3).timeout


## B for each of `players`, as a person opens the radial; fails unless every one opened.
func _open(players: Array[int]) -> bool:
	for player in players:
		tap(player, &"back")
	var opened: bool = await wait_for(func() -> bool: return players.all(func(player: int) -> bool: return _hud.call("get_radial", player).call("is_open")))
	if not opened:
		fail("the radial builders of players %s did not all open" % str(players.map(func(player: int) -> int: return player + 1)))
	return opened


## Point `player`'s right stick at `id`, held (the card stays picked) or let go again (nothing picked).
func _point(player: int, id: StringName, hold: bool) -> void:
	var direction: Vector2 = _hud.call("get_radial", player).call("direction_to", id)
	_input.call("send_virtual_aim", player, direction)
	await settle(SHEET_FRAMES)
	if not hold:
		_input.call("send_virtual_aim", player, Vector2.ZERO)
		await settle(SHEET_FRAMES)


## Point at every card on the ring in turn and crop the ring with its hub into sheets.
func _card_sheets(radial: Node) -> void:
	var entries: Array = radial.call("ring_entries")
	var per_page: int = SHEET_COLUMNS * SHEET_ROWS
	var sheet: Image = null
	var page: int = 0
	await settle()
	for at in entries.size():
		var spot: int = at % per_page
		if spot == 0:
			sheet = Image.create(SHEET_CROP * SHEET_COLUMNS, SHEET_CROP * SHEET_ROWS, false, Image.FORMAT_RGBA8)
			sheet.fill(Color.BLACK)
		_input.call("send_virtual_aim", 0, radial.call("direction_to", entries[at]["id"]))
		await settle(SHEET_FRAMES)
		var image: Image = await grab()
		image.convert(Image.FORMAT_RGBA8)
		var center := Vector2i(radial.call("ring_center"))
		var half: int = floori(SHEET_CROP * 0.5)
		var crop := Rect2i(center - Vector2i(half, half), Vector2i(SHEET_CROP, SHEET_CROP))
		var row: int = floori(float(spot) / float(SHEET_COLUMNS))
		sheet.blit_rect(image, crop, Vector2i((spot % SHEET_COLUMNS) * SHEET_CROP, row * SHEET_CROP))
		if spot == per_page - 1 or at == entries.size() - 1:
			page += 1
			if not save(sheet, "radial_cards_%d" % page):
				return
	_input.call("send_virtual_aim", 0, Vector2.ZERO)
	await settle()
