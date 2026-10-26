extends "res://tests/support/screenshot.gd"
## Screenshots of the radial builder's ring at any size (owner, 2026-10-26), with made-up cards
## (`tests/support/fake_cards.gd`).
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

const BAGS: Array[int] = [0, 1, 2, 300]
## The card each player points at (none for the empty bag).
const POINTED: Array[int] = [-1, 0, 1, 123]
const FLOOR_COLOR: Color = Color("#2b2840")

var _input: InputManagerScript = null
var _radials: Array[RadialScript] = []
## Everything made here, freed before quitting so nothing is left in use.
var _made: Array[Node] = []


func take() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	root.add_child(layer)
	_made.append(layer)
	var floor_rect := ColorRect.new()
	floor_rect.color = FLOOR_COLOR
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
			fail("the radial builder of player %d did not open" % (player + 1))
			return
		_radials.append(radial)
	await _point_all()
	await shot("radial_bags_every_card")
	for radial in _radials:
		radial.layout = RadialScript.Layout.KIND
	await _point_all()
	await shot("radial_bags_one_kind")
	for node in _made:
		node.free()
	_made.clear()
	_radials.clear()
	await process_frame


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
	await settle()
