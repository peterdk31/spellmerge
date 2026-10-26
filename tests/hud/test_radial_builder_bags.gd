extends "res://tests/support/suite.gd"
## Tests for the radial builder's ring at any size (owner, 2026-10-26: "empty, single, 2 and a
## few hundred made-up cards will cover everything now and in the future"): an empty bag, one
## card, two cards (of two kinds and of one kind) and 300 made-up cards (`tests/support/
## fake_cards.gd`), on both ring layouts. Every card must be reachable with the stick and picked
## exactly, a gap or an empty ring must pick nothing and rumble nothing. The builder runs alone
## on its own bus with a stand-in registry; the staff views come from the real `Spells`.
##
## godot --headless --path . --script res://tests/hud/test_radial_builder_bags.gd

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const RadialScript := preload("res://hud/builder/radial_builder.gd")
const FakeCards := preload("res://tests/support/fake_cards.gd")

const STEP: float = 0.0625
const MANY: int = 300

var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _spells: SpellsScript
var _radial: RadialScript
## Every rumble as [device, weak, strong, seconds].
var _rumbles: Array = []
## Every staff_change_requested as [player, staff, slot, id].
var _single: Array = []


func before_each() -> void:
	_rumbles.clear()
	_single.clear()
	_bus = own(EventsScript.new()) as EventsScript
	_input = own(InputManagerScript.new()) as InputManagerScript
	_input.events = _bus
	_input.vibrator = func(device: int, weak: float, strong: float, seconds: float) -> void: _rumbles.append([device, weak, strong, seconds])
	_input.add_virtual_device(0)
	_focus = own(UIFocusScript.new()) as UIFocusScript
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	_spells = own(SpellsScript.new()) as SpellsScript
	_bus.staff_change_requested.connect(func(player: int, staff: int, slot: int, card: StringName) -> void: _single.append([player, staff, slot, card]))


## Open player 1's radial with a bag of the first `count` made-up cards (all of `kind` if set)
## and four empty 20-slot staffs.
func _open(count: int, kind: StringName = &"") -> void:
	_spells.registry = own(FakeCards.registry(count, kind))
	_radial = own(RadialScript.new()) as RadialScript
	_radial.index = 0
	root.add_child(_radial)
	_radial.bind(_bus, _focus, _spells, _input)
	_bus.bag_changed.emit(0, FakeCards.ids(count))
	var staff := StaffBase.new()
	staff.slots = 20
	var row: Array[StringName] = []
	row.resize(staff.slots)
	row.fill(&"")
	for at in 4:
		_bus.staff_changed.emit(0, at, _spells.staff_view(row, staff))
	check(_radial.open_builder(), "the radial opens")


func _aim(direction: Vector2) -> void:
	_input.send_virtual_aim(0, direction)
	_radial.step(STEP)


func _tap(action: StringName) -> void:
	_input.send_virtual(0, action, 1.0)
	_input.send_virtual(0, action, 0.0)
	_radial.step(STEP)


## Every card on the ring is picked when the stick points at it, and each landing rumbles once.
func _check_every_card_is_reachable(count: int) -> void:
	var entries: Array[Dictionary] = _radial.ring_entries()
	check_equal(entries.size(), count, "%d cards on the ring" % count)
	var picked: int = 0
	for entry in entries:
		var direction: Vector2 = _radial.direction_to(entry["id"])
		_aim(direction)
		if _radial.pointed_id() == entry["id"]:
			picked += 1
		else:
			check(false, "pointing at %s picks %s" % [entry["id"], _radial.pointed_id()])
	check_equal(picked, count, "every card can be picked")
	check_equal(_rumbles.size(), count, "each card rumbled once as the stick landed on it")


func test_an_empty_bag_shows_an_empty_ring_that_picks_nothing() -> void:
	_open(0)
	check_equal(_radial.ring_entries().size(), 0, "no cards on the ring")
	for direction: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		_aim(direction)
	check_equal(_radial.pointed_id(), &"", "the stick picks nothing")
	check_equal(_rumbles.size(), 0, "and rumbles nothing")
	_tap(&"staff_2")
	check_equal(_single.size(), 0, "RT asks for nothing")
	check_equal(_radial.note_text(), RadialScript.POINT_NOTE, "and says why")
	_tap(&"staff_4")
	check_equal(_radial.note_text(), RadialScript.EMPTY_NOTE, "LT has nothing to take out")
	check_equal(_radial.hub_lines()[0], "Staff 2", "the hub still shows the staff")
	_radial.layout = RadialScript.Layout.KIND
	check_equal(_radial.shown_kind(), &"", "the one-kind ring has no kind to show")
	_tap(&"kind_next")
	check_equal(_radial.ring_entries().size(), 0, "and flipping it changes nothing")


func test_a_single_card_fills_the_ring_and_is_picked_from_any_direction() -> void:
	_open(1)
	check_equal(_radial.ring_entries().size(), 1, "one card")
	for degrees in range(0, 360, 45):
		_aim(Vector2.UP.rotated(deg_to_rad(float(degrees))))
		check_equal(_radial.pointed_id(), FakeCards.id(0), "pointing at %d degrees picks it" % degrees)
	check_equal(_rumbles.size(), 1, "it rumbled once, on landing")
	_tap(&"staff_2")
	check_equal(_single, [[0, 1, 0, FakeCards.id(0)]], "RT puts it in the first slot")
	_radial.layout = RadialScript.Layout.KIND
	check_equal(_radial.ring_entries().size(), 1, "the one-kind ring shows it too")


func test_two_cards_of_two_kinds_each_have_their_side_with_gaps_between() -> void:
	_open(2)
	_check_every_card_is_reachable(2)
	var first: Vector2 = _radial.direction_to(FakeCards.id(0))
	var second: Vector2 = _radial.direction_to(FakeCards.id(1))
	_aim(first.lerp(second, 0.5).normalized())
	check_equal(_radial.pointed_id(), &"", "the gap between the kinds picks nothing")
	_radial.layout = RadialScript.Layout.KIND
	check_equal(_radial.ring_entries().size(), 1, "one kind at a time: one card")
	_tap(&"kind_next")
	check_equal(_radial.ring_entries()[0]["id"], FakeCards.id(1), "the d-pad shows the other kind")
	_tap(&"kind_next")
	check_equal(_radial.ring_entries()[0]["id"], FakeCards.id(0), "and wraps back")


func test_two_cards_of_one_kind_share_the_ring_with_no_gap() -> void:
	_open(2, &"modifier")
	_check_every_card_is_reachable(2)
	_aim(Vector2.UP)
	check_equal(_radial.pointed_id(), FakeCards.id(0), "the first card is at the top")
	_aim(Vector2.DOWN)
	check_equal(_radial.pointed_id(), FakeCards.id(1), "the second opposite it")


func test_a_few_hundred_cards_are_each_reachable_in_kind_order() -> void:
	_open(MANY)
	_check_every_card_is_reachable(MANY)
	var last: int = 0
	for entry in _radial.ring_entries():
		var order: int = RadialScript.KINDS.find(entry["kind"])
		check(order >= last, "%s is in kind order" % entry["id"])
		last = order
	_aim(_radial.direction_to(FakeCards.id(123)))
	_tap(&"staff_2")
	check_equal(_single.back(), [0, 1, 0, FakeCards.id(123)], "RT puts in the card picked among hundreds")


func test_a_few_hundred_cards_one_kind_at_a_time() -> void:
	_open(MANY)
	_radial.layout = RadialScript.Layout.KIND
	for page in RadialScript.KINDS.size():
		var kind: StringName = _radial.shown_kind()
		var entries: Array[Dictionary] = _radial.ring_entries()
		check_equal(entries.size(), MANY / RadialScript.KINDS.size(), "%s: its share of the cards" % kind)
		check(entries.all(func(entry: Dictionary) -> bool: return entry["kind"] == kind), "%s: only that kind" % kind)
		for entry in entries:
			_aim(_radial.direction_to(entry["id"]))
			check_equal(_radial.pointed_id(), entry["id"], "%s: %s can be picked" % [kind, entry["id"]])
		_tap(&"kind_next")
	check_equal(_radial.shown_kind(), RadialScript.KINDS[0], "five flips come back to the carriers")
