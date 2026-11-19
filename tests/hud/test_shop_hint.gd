extends "res://tests/support/suite.gd"
## A shop's item on screen (connected biomes CB11's follow-up, the owner's answer of 2026-11-19;
## hud/panels): the item in a seat's reach (`shelf_near_changed`) is hinted "Buy" with its price, A
## buys it (`shelf_buy_requested`) whatever else waits, a ground item in reach comes first, a refused
## buy shakes the hint, and away from the shelf A opens a waiting reward. Kept apart from the reward
## menu's own tests: this is how A is routed, not how the menu looks.

const EventsScript := preload("res://core/events/events.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const HudScript := preload("res://hud/panels/panels.gd")
const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"

var _bus: EventsScript
var _input: InputManagerScript
var _focus: UIFocusScript
var _hud: HudScript
## Every `reward_pick_requested` sent, as [seat, offer, choice].
var _picked: Array = []


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_input = own(InputManagerScript.new()) as InputManagerScript
	_input.events = _bus
	_focus = own(UIFocusScript.new()) as UIFocusScript
	_focus.input = _input
	_focus.events = _bus
	_focus._ready()
	_picked = []
	_bus.reward_pick_requested.connect(func(seat: int, offer: int, choice: int) -> void: _picked.append([seat, offer, choice]))
	for seat in 2:
		_input.add_virtual_device(seat)
	_hud = (load(HUD_SCENE_PATH) as PackedScene).instantiate() as HudScript
	_hud.events = _bus
	_hud.ui_focus = _focus
	_hud.input = _input
	_hud.save = SaveFile.new("user://test_shop_hint_save.cfg")
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


## Seat `seat`'s offer `offer` rolled (`here` or not), waiting with any earlier ones in `waiting`.
func _roll(seat: int, offer: int, here: bool, waiting: Array[Dictionary] = []) -> Array[Dictionary]:
	var choices: Array[Dictionary] = [
		{"kind": &"card", "id": &"fire", "count": 1, "name": "Fire", "icon": null},
		{"kind": &"coins", "id": &"", "count": 5, "name": "5 coins", "icon": null},
	]
	var offers: Array[Dictionary] = waiting.duplicate()
	offers.append({"offer": offer, "here": here, "choices": choices})
	_bus.reward_rolled.emit(seat, offer, choices, here)
	_bus.rewards_waiting_changed.emit(seat, offers)
	return offers


## Connected biomes CB11's follow-up (the owner, 2026-11-19): what the wizard stands at decides what
## A does. A shop's item in reach (`shelf_near_changed`) is hinted "Buy" with its price, and A buys it
## (`shelf_buy_requested`), even with a reward waiting; away from it, A opens the waiting reward.
func test_a_at_a_shop_item_buys_it_and_elsewhere_opens_the_waiting_reward() -> void:
	var bought: Array = []
	_bus.shelf_buy_requested.connect(func(seat: int, item: int) -> void: bought.append([seat, item]))
	var waiting: Array[Dictionary] = _roll(0, 3, false)
	_bus.shelf_near_changed.emit(0, 5, Vector2(40, 40), {"kind": &"heal", "id": &"", "count": 30, "name": "Heal 30", "icon": null, "price": 6})
	_hud.step_hints(0.016)
	var hint: Control = _hud.get_item_hints().call("hint_of", 0) as Control
	check(hint.visible, "the shop item in reach is hinted")
	check_equal(String(hint.call("title")), "Buy Heal 30 (6)", "with what A does and its price")
	_frame()
	_tap(0, &"accept")
	_tap(0, &"take")
	_frame()
	check_equal(bought, [[0, 5]], "A buys the item the wizard stands at")
	check(not _hud.get_reward(0).is_open(), "and opens no reward")
	_bus.shelf_refused.emit(0, 5)
	check(bool(hint.call("is_refused")), "a refused buy shakes the hint red")
	_bus.item_near_changed.emit(0, 9, Vector2(60, 40), {"kind": &"card", "id": &"fire", "name": "Fire"})
	_hud.step_hints(0.016)
	check_equal(String(hint.call("title")), "Take Fire", "a ground item in reach comes first")
	check_equal(int(_hud.get_item_hints().call("shelf_of", 0)), -1, "and A buys nothing then")
	_bus.item_near_changed.emit(0, -1, Vector2.ZERO, {})
	_bus.shelf_near_changed.emit(0, -1, Vector2.ZERO, {})
	_hud.step_hints(0.016)
	check(not hint.visible, "nothing in reach: no hint")
	_frame()
	_tap(0, &"accept")
	_tap(0, &"take")
	_frame()
	check(_hud.get_reward(0).is_open(), "away from the shelf, A opens the waiting reward")
	check_equal(bought.size(), 1, "and buys nothing")
	check_equal(waiting.size(), 1, "")


## A body at a shut key door with no key of its own (the owner, 2026-11-19; `key_needed_shown`):
## "Needs a key" over the door, words alone, under any item in reach; A takes and buys nothing for it.
func test_a_shut_key_door_with_no_key_says_a_key_is_needed() -> void:
	var bought: Array = []
	_bus.shelf_buy_requested.connect(func(seat: int, item: int) -> void: bought.append([seat, item]))
	_bus.key_needed_shown.emit(1, Vector2(80, 40), true)
	_hud.step_hints(0.016)
	var hint: Control = _hud.get_item_hints().call("hint_of", 1) as Control
	check(hint.visible and bool(hint.call("is_note")), "seat 1's hint is a note")
	check_equal(String(hint.call("title")), "Needs a key", "saying a key is needed")
	check(not (_hud.get_item_hints().call("hint_of", 0) as Control).visible, "nothing for seat 0")
	check_equal(int(_hud.get_item_hints().call("item_of", 1)), -1, "A takes nothing for it")
	check_equal(int(_hud.get_item_hints().call("shelf_of", 1)), -1, "and buys nothing")
	_bus.item_near_changed.emit(1, 9, Vector2(60, 40), {"kind": &"card", "id": &"fire", "name": "Fire"})
	_hud.step_hints(0.016)
	check_equal(String(hint.call("title")), "Take Fire", "an item in reach comes first")
	_bus.item_near_changed.emit(1, -1, Vector2.ZERO, {})
	_hud.step_hints(0.016)
	check_equal(String(hint.call("title")), "Needs a key", "and the note again once it is gone")
	_bus.key_needed_shown.emit(1, Vector2.ZERO, false)
	_hud.step_hints(0.016)
	check(not hint.visible, "away from the door (or holding a key): no hint")
	check(bought.is_empty(), "nothing bought")
