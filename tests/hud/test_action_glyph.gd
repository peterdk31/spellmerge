extends "res://tests/support/suite.gd"
## Tests for the glyph widgets (hud/widgets/action_glyph.gd and hint_line.gd): the button of an
## action is drawn for the controller the player holds, and it changes live when that changes.
##
## godot --headless --path . --script res://tests/hud/test_action_glyph.gd

const InputManagerScript := preload("res://core/input/input_manager.gd")
const GlyphsScript := preload("res://core/input/input_glyphs.gd")
const ActionGlyphScript := preload("res://hud/widgets/action_glyph.gd")
const HintLineScript := preload("res://hud/widgets/hint_line.gd")

var _pad_names: Dictionary = {0: "Xbox One Controller", 1: "PS5 Controller"}
var _input: InputManagerScript


func before_each() -> void:
	_input = own(InputManagerScript.new()) as InputManagerScript
	_input.joy_name_provider = func(device: int) -> String: return String(_pad_names.get(device, ""))


func _glyph(player: int, action: StringName) -> ActionGlyphScript:
	var glyph: ActionGlyphScript = own(ActionGlyphScript.new()) as ActionGlyphScript
	glyph.bind(_input)
	root.add_child(glyph)
	glyph.show_action(player, action)
	return glyph


func _label(glyph: ActionGlyphScript) -> String:
	return glyph.current_glyph()["label"]


func test_it_shows_the_button_of_the_pad_in_the_players_hands() -> void:
	_input.join(0)
	_input.join(1)
	check_equal(_label(_glyph(0, &"alternate")), "X", "player 1 on an Xbox pad")
	check_equal(_label(_glyph(1, &"alternate")), "square", "player 2 on a PlayStation pad")


func test_it_changes_when_the_player_changes_controller() -> void:
	_input.join(0)
	var glyph: ActionGlyphScript = _glyph(0, &"accept")
	check_equal(_label(glyph), "A", "the Xbox pad")
	_input.leave(0)
	_input.join(InputManagerScript.KEYBOARD)
	check_equal(_label(glyph), "Enter", "the keyboard, without anyone asking the widget to look again")
	_input.leave(0)
	_input.join(1)
	check_equal(_label(glyph), "cross", "the PlayStation pad")


func test_cast_turns_into_the_mouse_and_back() -> void:
	_input.join(InputManagerScript.KEYBOARD)
	var glyph: ActionGlyphScript = _glyph(0, &"staff_2")
	check_equal(_label(glyph), "J", "keys first")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_input.handle_event(click)
	check_equal(int(glyph.current_glyph()["shape"]), int(GlyphsScript.Shape.MOUSE), "a click shows the mouse")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_J
	key.pressed = true
	_input.handle_event(key)
	check_equal(_label(glyph), "J", "the cast key shows the key again")


func test_a_change_for_one_player_leaves_the_other_glyphs_alone() -> void:
	_input.join(0)
	_input.join(1)
	var first: ActionGlyphScript = _glyph(0, &"staff_2")
	var second: ActionGlyphScript = _glyph(1, &"staff_2")
	_input.leave(0)
	_input.join(InputManagerScript.KEYBOARD)
	check_equal(_label(first), "J", "player 1's slot now holds the keyboard")
	check_equal(_label(second), "R2", "player 2 is still on the PlayStation pad")


func test_a_glyph_is_wide_enough_for_its_key() -> void:
	_input.join(InputManagerScript.KEYBOARD)
	var space: ActionGlyphScript = _glyph(0, &"staff_1")
	var letter: ActionGlyphScript = _glyph(0, &"staff_2")
	check(space.custom_minimum_size.x > letter.custom_minimum_size.x, "the Space key is wider than J")


func test_a_hint_line_says_the_verb_beside_the_glyph() -> void:
	_input.join(0)
	var line: HintLineScript = own(HintLineScript.new()) as HintLineScript
	line.bind(_input)
	root.add_child(line)
	line.show_hint(0, &"alternate", "Use", &"accept", "back")
	check_equal(line.text(), "Use, back", "both verbs")
	check_equal(line.action_of(0), &"alternate", "the first glyph is for alternate")
	check_equal(line.action_of(1), &"accept", "the second is for accept")
	line.show_hint(0, &"alternate", "Close")
	check_equal(line.text(), "Close", "one pair")
	check_equal(line.action_of(1), &"", "the second glyph is hidden")
	line.show_hint(0, &"", "")
	check_equal(line.text(), "", "no hint, no words")
	check(not line.glyph_node(0).visible, "and no glyph")


func test_a_hint_line_follows_the_controller_too() -> void:
	_input.join(0)
	var line: HintLineScript = own(HintLineScript.new()) as HintLineScript
	line.bind(_input)
	root.add_child(line)
	line.show_hint(0, &"alternate", "Close")
	var glyph: ActionGlyphScript = line.glyph_node(0) as ActionGlyphScript
	check_equal(_label(glyph), "X", "Xbox")
	_input.leave(0)
	_input.join(1)
	check_equal(_label(glyph), "square", "PlayStation, live")
