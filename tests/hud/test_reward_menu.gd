extends "res://tests/support/suite.gd"
## The reward menu on screen (connected biomes CB10, hud/menus/reward, hud/panels): an offer rolled
## for a seat whose wizard was there opens that seat's menu by itself, "Pick 1 of 2", one button a
## choice; A on one sends the command `reward_pick_requested` with its offer and closes it; B closes
## it with nothing sent, and the corner panel says the reward waits; the seat's A with nothing else
## for it opens it again. An offer rolled for a seat that was not there opens nothing. It closes by
## itself when its offer goes. The corner panel says the seat's coins.

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
	_hud.save = SaveFile.new("user://test_reward_menu_save.cfg")
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


func _words(seat: int) -> Array[String]:
	var found: Array[String] = []
	for button: Button in _hud.get_reward(seat).buttons():
		found.append(button.text.trim_prefix("> "))
	return found


func test_an_offer_for_a_seat_that_was_there_opens_its_menu() -> void:
	_roll(1, 4, true)
	_frame()
	var menu: Control = _hud.get_reward(1)
	check(menu.call("is_open") and menu.visible, "the seat's menu opens by itself")
	check(not _hud.get_reward(0).is_open(), "nobody else's")
	check_equal(_words(1), ["Fire", "5 coins"] as Array[String], "a button a choice")
	check_equal((menu.get_node("Rows/Title") as Label).text, "Pick 1 of 2", "pick 1 of 2")
	_tap(1, &"accept")
	_frame()
	check_equal(_picked, [[1, 4, 0]], "A picks the focused choice, naming the offer")
	check(not menu.call("is_open"), "and closes it")


func test_back_leaves_it_unspent_and_a_opens_it_again() -> void:
	var waiting: Array[Dictionary] = _roll(0, 2, true)
	_frame()
	_tap(0, &"back")
	_frame()
	check(not _hud.get_reward(0).is_open(), "B closes it")
	check(_picked.is_empty(), "with nothing sent")
	check_equal(_hud.get_panel(0).purse_text(), "1 to pick", "the corner panel says it waits")
	_frame()
	_tap(0, &"accept")
	_frame()
	check(_hud.get_reward(0).is_open(), "A with nothing else for it opens it again")
	_bus.rewards_waiting_changed.emit(0, [] as Array[Dictionary])
	check(not _hud.get_reward(0).is_open(), "it closes when its offer goes")
	check_equal(_hud.get_panel(0).purse_text(), "", "the panel's line hides")
	check_equal(waiting.size(), 1, "one was waiting")


func test_an_offer_for_a_seat_that_was_not_there_waits() -> void:
	_roll(0, 1, false)
	_frame()
	check(not _hud.get_reward(0).is_open(), "nothing opens by itself")
	check_equal(_hud.get_panel(0).purse_text(), "1 to pick", "the unspent icon (rule 4)")


func test_a_refused_pick_opens_the_menu_again_saying_so() -> void:
	_roll(0, 6, true)
	_frame()
	_tap(0, &"accept")
	_frame()
	check(not _hud.get_reward(0).is_open(), "picked and closed")
	_bus.reward_refused.emit(0, 6)
	# The poll after the one that closed it (the press that closed a menu never opens another).
	_frame()
	_frame()
	check(_hud.get_reward(0).is_open(), "a refused pick opens it again")
	check_equal((_hud.get_reward(0).get_node("Rows/Title") as Label).text, "Can't take that now", "saying so")


func test_the_panel_says_the_coins() -> void:
	_bus.wallet_changed.emit(1, 12)
	check_equal(_hud.get_panel(1).purse_text(), "12 coins", "the seat's wallet")
	_roll(1, 3, false)
	check_equal(_hud.get_panel(1).purse_text(), "12 coins  1 to pick", "and its rewards waiting")
