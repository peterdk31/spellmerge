extends "res://tests/support/suite.gd"
## The main menu's Host and Join (netcode spike S4, docs/milestones/netcode-spike.md): the menu
## sends only what its player asked (`online_host_requested`, `online_join_requested` and
## `online_answer_requested` with the text of the code box as it is, `online_leave_requested`) and
## shows only what `online_changed` says: this machine's code with Copy, the box for the other
## player's code while one is wanted, and a line of words. It names nothing of a network.

const OnlineLineScript := preload("res://hud/widgets/online_line.gd")
const MenuScene: PackedScene = preload("res://hud/menus/main_menu/main_menu.tscn")
const EventsScript := preload("res://core/events/events.gd")
const MENU_SCRIPT: String = "res://hud/menus/main_menu/main_menu.gd"

var _bus: EventsScript
var _menu: Control
## Every online request sent, as [name, args...].
var _sent: Array[Array] = []


func before_each() -> void:
	_sent.clear()
	_bus = own(EventsScript.new()) as EventsScript
	_bus.online_host_requested.connect(func(player: int) -> void: _sent.append([&"host", player]))
	_bus.online_join_requested.connect(func(player: int, code: String) -> void: _sent.append([&"join", player, code]))
	_bus.online_answer_requested.connect(func(player: int, code: String) -> void: _sent.append([&"answer", player, code]))
	_bus.online_leave_requested.connect(func(player: int) -> void: _sent.append([&"leave", player]))
	_menu = MenuScene.instantiate() as Control
	_menu.set("events", _bus)
	root.add_child(own(_menu))


func _button(node: String) -> Button:
	return _menu.get_node("%" + node) as Button


func _shown(node: String) -> bool:
	return (_menu.get_node("%" + node) as Control).is_visible_in_tree()


func _status() -> String:
	return (_menu.get_node("%OnlineStatus") as Label).text


func _box() -> LineEdit:
	return _menu.get_node("%Theirs") as LineEdit


func test_host_and_join_are_there_and_the_box_is_closed() -> void:
	check(_button("Host").is_visible_in_tree() and _button("Join").is_visible_in_tree(), "Host and Join show")
	check(not _shown("Online"), "the online box is closed")
	check_equal(_sent, [], "nothing is asked of anyone before a press")
	_bus.online_changed.emit(&"code", "a code", &"", {})
	check(not _shown("Online"), "and what net/ says to a closed box opens nothing")


func test_host_asks_for_a_code_shows_it_and_passes_the_answer_on() -> void:
	_button("Host").pressed.emit()
	check_equal(_sent, [[&"host", 0]], "Host asks, as seat 0")
	check(_shown("Online") and not _shown("Host") and not _shown("Join") and not _shown("Play") and not _shown("Sandbox"), "the box opens in the buttons' place")
	_bus.online_changed.emit(&"making", "", &"", {})
	check(not _shown("MineRow") and not _shown("TheirsRow"), "while the code is made there is nothing to copy or paste")
	_bus.online_changed.emit(&"code", "SM1.host", &"", {})
	check_equal((_menu.get_node("%Mine") as LineEdit).text, "SM1.host", "the code is shown")
	check(not (_menu.get_node("%Mine") as LineEdit).editable, "to copy, not to change")
	check(_shown("TheirsRow") and _status().contains("send it to the other player"), "with the box for the code that comes back, and what to do")
	_button("Connect").pressed.emit()
	check_equal(_sent.size(), 1, "Connect with an empty box asks nothing")
	_box().text = "  SM1.answer\n"
	_button("Connect").pressed.emit()
	check_equal(_sent.back(), [&"answer", 0, "  SM1.answer\n"], "the pasted text is passed on as it is")
	_bus.online_changed.emit(&"code", "SM1.host", OnlineWhy.HOSTS_CODE, {})
	check(_status().begins_with("That is a host's code") and _shown("TheirsRow"), "a refused code: why, in the HUD's words, and the box stays")
	_bus.online_changed.emit(&"linking", "SM1.host", &"", {})
	check(not _shown("TheirsRow") and _status().contains("Looking"), "linking: no box")
	_bus.online_changed.emit(&"failed", "", OnlineWhy.NO_LINK, {OnlineWhy.CAUSE: OnlineWhy.CAUSE_UNKNOWN})
	check(_status().begins_with("The two machines could not reach each other.") and _status().contains("Cancel"), "failed: why, and what to do (%s)" % _status())
	check(not _shown("MineRow") and not _shown("TheirsRow"), "the code and the box are gone")
	_button("Cancel").pressed.emit()
	check(_shown("Host") and not _button("Host").disabled, "Cancel brings Host back")


func test_join_asks_nothing_until_connect_and_then_shows_its_own_code() -> void:
	_button("Join").pressed.emit()
	check_equal(_sent, [], "Join alone asks nothing: no machine is talked to before a code is given")
	check(_shown("TheirsRow") and not _shown("MineRow") and _status().contains("host's code"), "the box for the host's code, and what to do")
	_box().text = "SM1.host"
	_box().text_submitted.emit(_box().text)
	check_equal(_sent, [[&"join", 0, "SM1.host"]], "Enter in the box is Connect: the host's code passed on")
	_bus.online_changed.emit(&"making", "", &"", {})
	check(not _shown("TheirsRow"), "the box goes while this machine's code is made")
	_bus.online_changed.emit(&"code", "SM1.mine", &"", {})
	check(_shown("MineRow") and not _shown("TheirsRow") and _status().contains("back to the host"), "its own code to send back, no box")
	_bus.online_changed.emit(&"failed", "", OnlineWhy.NO_ROOM, {OnlineWhy.ROOM: "ABCDE"})
	check(_shown("TheirsRow") and _status().begins_with("No room has the code ABCDE."), "failed: why, and the box again for another try (%s)" % _status())
	_bus.online_changed.emit(&"failed", "", &"a name the menu has never heard", {})
	check(_status().begins_with("It did not work.") and _status().contains("try again"), "a reason with no words still says it failed, never the name (%s)" % _status())
	_box().text = "SM1.other"
	_button("Connect").pressed.emit()
	check_equal(_sent.back(), [&"join", 0, "SM1.other"], "another code may be given")


func test_the_open_box_hushes_the_huds_online_line() -> void:
	var line := OnlineLineScript.new()
	root.add_child(own(line))
	line.bind(_bus)
	_button("Join").pressed.emit()
	_bus.online_changed.emit(&"failed", "", OnlineWhy.NO_SERVER, {})
	check(_status().begins_with("The room server could not be reached.") and not line.visible, "the box says why it failed; the line over the menu does not say it again")
	_button("Cancel").pressed.emit()
	_bus.online_changed.emit(&"failed", "", OnlineWhy.NO_SERVER, {})
	check(line.visible, "the box closed: the line speaks again")
	_button("Host").pressed.emit()
	check(not line.visible, "open again: hushed")
	root.remove_child(_menu)
	check(line.visible, "the menu gone (a run starts): the line speaks")
	root.add_child(_menu)


func test_cancel_closes_the_box_and_says_so() -> void:
	_button("Host").pressed.emit()
	_bus.online_changed.emit(&"code", "SM1.host", &"", {})
	_button("Cancel").pressed.emit()
	check_equal(_sent.back(), [&"leave", 0], "Cancel says the player gave up")
	check(not _shown("Online") and _shown("Host") and _shown("Join") and _shown("Play") and _shown("Sandbox"), "the box closes; the buttons are back")
	_button("Join").pressed.emit()
	check_equal((_menu.get_node("%Mine") as LineEdit).text, "", "the next try starts without the old code")


func test_copy_puts_the_code_on_the_clipboard() -> void:
	_button("Host").pressed.emit()
	_bus.online_changed.emit(&"code", "SM1.copied", &"", {})
	_button("Copy").pressed.emit()
	check_equal(_button("Copy").text, "Copied", "Copy says it did")
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		check_equal(DisplayServer.clipboard_get(), "SM1.copied", "the code is on the clipboard")
	_bus.online_changed.emit(&"code", "SM1.another", &"", {})
	check_equal(_button("Copy").text, "Copy", "a new code is not yet copied")


func _paste_keys() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_V
	event.ctrl_pressed = true
	event.pressed = true
	return event


func test_a_paste_replaces_what_the_box_holds() -> void:
	var clipboard: Array[String] = ["SM1.first"]
	_menu.set("clipboard_reader", func() -> String: return clipboard[0])
	_menu.set("clipboard_is_late", false)
	_button("Join").pressed.emit()
	_button("Paste").pressed.emit()
	check_equal(_box().text, "SM1.first", "Paste fills the box from the clipboard")
	clipboard[0] = "SM1.second"
	_box().gui_input.emit(_paste_keys())
	check_equal(_box().text, "SM1.second", "the paste keys in the box replace it: a second paste never adds to the first")
	clipboard[0] = ""
	_button("Paste").pressed.emit()
	check_equal(_box().text, "SM1.second", "an empty clipboard leaves the box as it is")
	clipboard[0] = "x".repeat(40000)
	_button("Paste").pressed.emit()
	check_equal(_box().text.length(), _box().max_length, "a huge clipboard is cut to the box's limit")


## A browser hands the clipboard over a moment after it is asked for: the box is filled when it
## has come, from one press.
func test_a_paste_in_a_browser_fills_the_box_when_the_text_arrives() -> void:
	var asked: Array[int] = [0]
	var arrived: Array[String] = ["what was copied before"]
	_menu.set("clipboard_reader", func() -> String:
		asked[0] += 1
		# The first ask only starts the read; the text is there from the second.
		return arrived[0] if asked[0] == 1 else "SM1.fresh")
	_menu.set("clipboard_is_late", true)
	_button("Join").pressed.emit()
	_box().gui_input.emit(_paste_keys())
	check_equal([asked[0], _box().text], [1, ""], "asked for at once, and the stale text is not shown")
	var wait: float = float(_menu.get("PASTE_WAIT"))
	_menu.call("_process", wait * 0.5)
	check_equal(_box().text, "", "not yet")
	_menu.call("_process", wait * 0.6)
	check_equal(_box().text, "SM1.fresh", "a moment later the box holds the pasted code")
	for i in 10:
		_menu.call("_process", wait)
	check(asked[0] <= 1 + int(_menu.get("PASTE_CHECKS")) and not _menu.is_processing(), "and the clipboard is read only a few times (%d)" % asked[0])


func test_the_box_holds_no_more_than_a_code_could_be() -> void:
	check(_box().max_length > 0 and _box().max_length >= NetCode.MAX_CHARS, "the code box has a limit, and a code fits it (%d)" % _box().max_length)


func test_the_menu_names_nothing_of_a_network() -> void:
	var source: String = FileAccess.get_file_as_string(MENU_SCRIPT)
	for word: String in ["NetPlay", "NetRtc", "NetHost", "NetClient", "WebRTC", "res://net/"]:
		check(not source.contains(word), "the main menu does not name %s" % word)
