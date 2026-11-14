extends "res://tests/support/screenshot.gd"
## Screenshots of the radial builder alone (items I5): one builder on its own bus over a plain
## floor, with made-up cards (`tests/support/fake_cards.gd`), no room, no wizards and no Flow, so
## nothing but the builder is in the picture and two runs of the same code give the same pixels
## (a change to the builder, or to the shared radial menu under it, is all a difference can be).
## A stand-in answers the builder's requests as the player does (`owned_staff_changed`).
##
## Shots, in P1's quarter: open with nothing pointed at, pointing at a card, two cards put in,
## one taken out, LT held half way to a clear, the tree, one kind at a time, the zoom ring locked
## and the kinds ring opened on a kind.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const RadialScript := preload("res://hud/builder/radial_builder.gd")
const RingZoomScript := preload("res://hud/builder/rings/ring_zoom.gd")
const RingKindsScript := preload("res://hud/builder/rings/ring_kinds.gd")
const FakeCards := preload("res://tests/support/fake_cards.gd")

const PLAYER: int = 0
const CARDS: int = 24
const SLOTS: int = 10
## The staffs on RB and RT (numbers 0 and 1); LB and LT are empty hands.
const STAFFS: int = 2
const FLOOR_COLOR: Color = Color("#2b2840")

var _bus: EventsScript = null
var _input: InputManagerScript = null
var _spells: SpellsScript = null
var _radial: RadialScript = null
var _base: StaffBase = null
## Each staff's cards by slot, as the stand-in holds them.
var _rows: Array = []
## Everything made here, freed before quitting so nothing is left in use.
var _made: Array[Node] = []


func take() -> void:
	_stage()
	if not _radial.open_builder():
		fail("the radial builder did not open")
		return
	await settle()
	await shot("radial_alone_open")
	await _point(5)
	await shot("radial_alone_pointing")
	await _press(&"staff_2")
	await _point(7)
	await _press(&"staff_2")
	await _let_go()
	await shot("radial_alone_built")
	_radial.mark_slot(0)
	await _press(&"staff_4")
	await shot("radial_alone_taken")
	# Two cards again, so the hold has one left to clear (its press takes one out) and the tree
	# has a cast to show.
	await _point(5)
	await _press(&"staff_2")
	await _let_go()
	_input.send_virtual(PLAYER, &"staff_4", 1.0)
	# Half the hold, counted in frames (each 1/60 s with --fixed-fps), and grabbed at once: `shot`
	# would settle on past the clear.
	await settle(int(RadialScript.CLEAR_HOLD * 0.5 * 60.0))
	save(await grab(), "radial_alone_clearing")
	_input.send_virtual(PLAYER, &"staff_4", 0.0)
	await settle()
	await _press(&"extra")
	await shot("radial_alone_tree")
	await _press(&"extra")
	_radial.layout = RadialScript.Layout.KIND
	await _point(1)
	await shot("radial_alone_one_kind")
	await _let_go()
	_radial.layout = RadialScript.Layout.ALL
	_radial.ring_picker = RingZoomScript.new()
	await _point(10)
	await shot("radial_alone_zoom")
	await _let_go()
	_radial.ring_picker = RingKindsScript.new(RingKindsScript.Enter.HOLD)
	_input.send_virtual_aim(PLAYER, Vector2.RIGHT)
	await settle(30)
	await shot("radial_alone_kinds")
	await _let_go()
	for node in _made:
		node.free()
	_made.clear()
	await process_frame


## The builder and only what it hears from: a floor, a bus, input, focus, made-up cards.
func _stage() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	root.add_child(layer)
	_made.append(layer)
	var floor_rect := ColorRect.new()
	floor_rect.color = FLOOR_COLOR
	floor_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(floor_rect)
	_bus = EventsScript.new()
	root.add_child(_bus)
	_made.append(_bus)
	_input = InputManagerScript.new()
	_input.events = _bus
	root.add_child(_input)
	_made.append(_input)
	var focus := UIFocusScript.new()
	focus.input = _input
	focus.events = _bus
	root.add_child(focus)
	_made.append(focus)
	_spells = SpellsScript.new()
	_spells.registry = FakeCards.registry(CARDS)
	root.add_child(_spells.registry)
	_made.append(_spells.registry)
	_made.append(_spells)
	_base = StaffBase.new()
	_base.slots = SLOTS
	_input.add_virtual_device(PLAYER)
	_radial = RadialScript.new()
	_radial.index = PLAYER
	layer.add_child(_radial)
	_radial.bind(_bus, focus, _spells, _input)
	_bus.staff_change_requested.connect(_on_change_requested)
	_bus.staff_cards_requested.connect(_on_cards_requested)
	FakeCards.announce_bag(_bus, PLAYER, FakeCards.ids(CARDS))
	var plans: Array[Dictionary] = []
	for staff in 4:
		var row: Array[StringName] = []
		row.resize(SLOTS)
		row.fill(&"")
		_rows.append(row)
		plans.append(_spells.staff_view(row, _base) if staff < STAFFS else {})
	FakeCards.announce_staffs(_bus, PLAYER, plans)
	_bus.player_stats_changed.emit(PLAYER, 80, 100, 60.0, 100.0)


## The stand-in for the player: apply a request and announce the staff again.
func _on_change_requested(player: int, staff: int, slot: int, card_id: StringName) -> void:
	if player != PLAYER or staff >= STAFFS:
		return
	(_rows[staff] as Array)[slot] = card_id
	_announce(staff)


func _on_cards_requested(player: int, staff: int, cards: Array[StringName]) -> void:
	if player != PLAYER or staff >= STAFFS:
		return
	var row: Array[StringName] = []
	row.assign(cards)
	row.resize(SLOTS)
	for slot in SLOTS:
		if row[slot] == null:
			row[slot] = &""
	_rows[staff] = row
	_announce(staff)


func _announce(staff: int) -> void:
	var row: Array[StringName] = []
	row.assign(_rows[staff])
	_bus.owned_staff_changed.emit(PLAYER, staff, _spells.staff_view(row, _base))


## Point the right stick at made-up card `at` (held, so the pointer line shows).
func _point(at: int) -> void:
	var direction: Vector2 = _radial.direction_to(FakeCards.id(at))
	if direction == Vector2.ZERO:
		var entries: Array[Dictionary] = _radial.ring_entries()
		direction = _radial.direction_to(entries[0]["id"]) if not entries.is_empty() else Vector2.UP
	_input.send_virtual_aim(PLAYER, direction)
	await settle()


func _let_go() -> void:
	_input.send_virtual_aim(PLAYER, Vector2.ZERO)
	await settle()


func _press(action: StringName) -> void:
	_input.send_virtual(PLAYER, action, 1.0)
	await process_frame
	_input.send_virtual(PLAYER, action, 0.0)
	await settle()
