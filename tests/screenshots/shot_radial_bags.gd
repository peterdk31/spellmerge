extends SceneTree
## Screenshots of the radial builder's ring at any size (owner, 2026-10-26), with made-up cards
## (`tests/support/fake_cards.gd`), for people and for Claude to look at (not a test: it only
## checks that each staged state happened). Needs a display, so it runs only through
## `ci/build/build.sh --quick --screenshots`; each shot is saved as user://screenshots/<name>.png
## and copied to build/screenshots/.
##
## The four builders run on their own bus over a plain floor, one per quarter: P1 an empty bag,
## P2 one card, P3 two cards, P4 300 cards. Shots: every card on the ring (each player pointing at
## a card, P4 at one among hundreds), then one kind at a time.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const RadialScript := preload("res://hud/builder/radial_builder.gd")
const FakeCards := preload("res://tests/support/fake_cards.gd")

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 20
const BAGS: Array[int] = [0, 1, 2, 300]
## The card each player points at (none for the empty bag).
const POINTED: Array[int] = [-1, 0, 1, 123]
const FLOOR: Color = Color("#2b2840")

var _input: InputManagerScript = null
var _radials: Array[RadialScript] = []
## Everything made here, freed before quitting so nothing is left in use.
var _made: Array[Node] = []


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	var layer := CanvasLayer.new()
	layer.layer = 20
	root.add_child(layer)
	_made.append(layer)
	var floor_rect := ColorRect.new()
	floor_rect.color = FLOOR
	floor_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(floor_rect)
	var bus := EventsScript.new()
	root.add_child(bus)
	_made.append(bus)
	_input = InputManagerScript.new()
	_input.events = bus
	root.add_child(_input)
	_made.append(_input)
	var focus := UIFocusScript.new()
	focus.input = _input
	focus.events = bus
	root.add_child(focus)
	_made.append(focus)
	var spells := SpellsScript.new()
	spells.registry = FakeCards.registry(BAGS.max())
	root.add_child(spells.registry)
	_made.append(spells.registry)
	_made.append(spells)
	var staff := StaffBase.new()
	staff.slots = 20
	var row: Array[StringName] = []
	row.resize(staff.slots)
	row.fill(&"")
	for player in 4:
		_input.add_virtual_device(player)
		var radial := RadialScript.new()
		radial.index = player
		layer.add_child(radial)
		radial.bind(bus, focus, spells, _input)
		bus.bag_changed.emit(player, FakeCards.ids(BAGS[player]))
		for at in 4:
			bus.staff_changed.emit(player, at, spells.staff_view(row, staff))
		bus.player_stats_changed.emit(player, 100, 100, 100.0, 100.0)
		if not radial.open_builder():
			_fail("the radial builder of player %d did not open" % (player + 1))
			return
		_radials.append(radial)
	await _point_all()
	await _shot("radial_bags_every_card")
	for radial in _radials:
		radial.layout = RadialScript.Layout.KIND
	await _point_all()
	await _shot("radial_bags_one_kind")
	for node in _made:
		node.free()
	_made.clear()
	_radials.clear()
	await process_frame
	quit(0)


## Each player points at their card (held, so the pointer line shows); P1's empty ring has none.
func _point_all() -> void:
	for player in 4:
		if POINTED[player] < 0:
			_input.send_virtual_aim(player, Vector2.UP)
			continue
		var id: StringName = FakeCards.id(POINTED[player])
		var direction: Vector2 = _radials[player].direction_to(id)
		if direction == Vector2.ZERO:
			# Not on the one-kind ring shown: point at that ring's first card instead.
			var entries: Array[Dictionary] = _radials[player].ring_entries()
			direction = _radials[player].direction_to(entries[0]["id"]) if not entries.is_empty() else Vector2.UP
		_input.send_virtual_aim(player, direction)
	await _settle()


func _fail(message: String) -> void:
	printerr("SHOT FAILED: " + message)
	quit(1)


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame


func _shot(shot_name: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = "%s/%s.png" % [SHOTS_DIR, shot_name]
	if image == null or image.save_png(path) != OK:
		printerr("SHOT FAILED: could not save " + path)
		return
	print("SHOT: %s (%dx%d)" % [shot_name, image.get_width(), image.get_height()])
