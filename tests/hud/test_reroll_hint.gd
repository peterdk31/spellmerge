extends "res://tests/support/suite.gd"
## The room reroll's hint and X in play (the owner, 2026-11-19; hud/panels/item_hints.gd, panels.gd):
## a seat whose body stands at an unvisited room's doorway (`room_reroll_shown`) is shown X "Reroll
## room" there; X with no menu open sends `room_reroll_requested`, once a press; a refusal
## (`room_reroll_refused`) says why and shakes it; an item in reach comes first and X then sends
## nothing; away from a doorway X sends nothing.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const ItemHintScript := preload("res://hud/widgets/item_hint.gd")
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"

var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _hud: HudScript
var _asked: Array = []


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_input = own(InputManagerScript.new()) as InputManagerScript
	_input.events = _bus
	_focus = own(UIFocusScript.new()) as UIFocusScript
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	_asked = []
	_bus.room_reroll_requested.connect(func(seat: int) -> void: _asked.append(seat))
	for seat in 2:
		_input.add_virtual_device(seat)
	_hud = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	_hud.events = _bus
	_hud.ui_focus = _focus
	_hud.input = _input
	_hud.save = SaveFile.new("user://test_reroll_hint_save.cfg")
	root.add_child(_hud)
	own(_hud)
	for seat in 2:
		_bus.player_joined.emit(seat)
	_bus.room_entered.emit(&"test_room", 0)


func _tap(seat: int, action: StringName) -> void:
	_input.send_virtual(seat, action, 1.0)
	_input.send_virtual(seat, action, 0.0)


func _frame() -> void:
	_hud.poll()
	_focus.poll()
	_hud.step_hints(0.0)


func _hint(seat: int) -> ItemHintScript:
	return _hud.get_item_hints().hint_of(seat)


func test_at_a_doorway_x_asks_for_a_reroll() -> void:
	_bus.room_reroll_shown.emit(0, Vector2(100, 50), true)
	_frame()
	check(_hint(0).visible and _hint(0).is_note(), "a hint at the doorway")
	check_equal(_hint(0).title(), ItemHintScript.REROLL_ROOM, "X Reroll room")
	check(not _hint(1).visible, "the other seat's shows nothing")
	_tap(0, &"alternate")
	_frame()
	check_equal(_asked, [0], "X sends room_reroll_requested for its seat")
	_frame()
	check_equal(_asked, [0], "once a press")
	_tap(1, &"alternate")
	_frame()
	check_equal(_asked, [0], "a seat at no doorway sends nothing")


func test_a_refusal_says_why_and_shakes() -> void:
	_bus.room_reroll_shown.emit(0, Vector2(100, 50), true)
	_frame()
	_bus.room_reroll_refused.emit(0, &"none_held")
	check_equal(_hint(0).title(), ItemHintScript.NO_ROOM_REROLLS, "none held")
	check(_hint(0).is_refused(), "it shakes")
	_bus.room_reroll_refused.emit(0, &"no_room")
	check_equal(_hint(0).title(), ItemHintScript.NOTHING_FITS, "nothing valid fits there")
	_bus.room_reroll_shown.emit(0, Vector2.ZERO, false)
	_frame()
	check(not _hint(0).visible, "gone with the doorway")


func test_an_item_in_reach_comes_first() -> void:
	_bus.room_reroll_shown.emit(0, Vector2(100, 50), true)
	_bus.item_near_changed.emit(0, 3, Vector2(90, 50), {"name": "Staff", "kind": &"staff", "id": &"oak"})
	_frame()
	check_equal(_hint(0).item(), 3, "the item's hint")
	_tap(0, &"alternate")
	_frame()
	check(_asked.is_empty(), "X asks for nothing then")
	_bus.item_near_changed.emit(0, -1, Vector2.ZERO, {})
	_frame()
	check_equal(_hint(0).title(), ItemHintScript.REROLL_ROOM, "the doorway's again once the item is out of reach")


func test_with_a_menu_open_x_is_the_menus() -> void:
	_bus.room_reroll_shown.emit(0, Vector2(100, 50), true)
	_frame()
	check(_hud.get_inventory(0).open_inventory() or _hud.get_inventory(0).is_open(), "the inventory opens")
	_frame()
	_tap(0, &"alternate")
	_frame()
	check(_asked.is_empty(), "the inventory's X is its own (it drops, #864), never a reroll")
