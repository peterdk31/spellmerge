extends "res://tests/support/suite.gd"
## The main menu's "Fullscreen" button (owner, 2026-10-27): it asks `Display` to fill the screen
## and shows the window's own state; it follows `fullscreen_changed`, so F11 or Alt+Enter show
## too. Without a Display (no autoload) the button is hidden. The display is a stand-in: headless
## has no window.
##
## godot --headless --path . --script res://tests/hud/test_main_menu_fullscreen.gd

const MENU_SCENE_PATH: String = "res://hud/menus/main_menu/main_menu.tscn"


class FakeDisplay:
	extends Node
	signal fullscreen_changed(on: bool)
	var on: bool = false

	func is_fullscreen() -> bool:
		return on

	func toggle_fullscreen() -> void:
		on = not on
		fullscreen_changed.emit(on)


func _menu(display: Node) -> Control:
	var menu: Control = (load(MENU_SCENE_PATH) as PackedScene).instantiate() as Control
	menu.set("display", display)
	root.add_child(menu)
	own(menu)
	return menu


func _button(menu: Control) -> Button:
	return menu.get_node("%Fullscreen") as Button


func test_the_button_toggles_fullscreen() -> void:
	var display: FakeDisplay = own(FakeDisplay.new()) as FakeDisplay
	var menu: Control = _menu(display)
	check(_button(menu).visible, "shown when there is a display")
	check_equal(_button(menu).text, "Fullscreen: Off", "off in a window")
	_button(menu).pressed.emit()
	check(display.on, "it asked for fullscreen")
	check_equal(_button(menu).text, "Fullscreen: On", "and shows On")


func test_a_shortcut_shows_on_the_button() -> void:
	var display: FakeDisplay = own(FakeDisplay.new()) as FakeDisplay
	var menu: Control = _menu(display)
	display.toggle_fullscreen()
	check_equal(_button(menu).text, "Fullscreen: On", "F11 elsewhere shows here too")


func test_no_display_no_button() -> void:
	var menu: Control = (load(MENU_SCENE_PATH) as PackedScene).instantiate() as Control
	own(menu)
	# A test tree has no Display autoload, so the menu finds none.
	root.add_child(menu)
	if root.get_node_or_null(^"Display") == null:
		check(not _button(menu).visible, "hidden without a display")
