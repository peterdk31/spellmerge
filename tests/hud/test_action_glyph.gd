extends "res://tests/support/suite.gd"
## Tests for the glyph widget (hud/widgets/action_glyph.gd): the button of an
## action is drawn for the controller the player holds, and it changes live when that changes.
const InputManagerScript := preload("res://core/input/input_manager.gd")
const GlyphsScript := preload("res://core/input/input_glyphs.gd")
const ActionGlyphScript := preload("res://hud/widgets/action_glyph.gd")

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


## ART4 part 3: every glyph is pixel art at the art's detail, its body as big as the glyph (in art
## pixels, half a layout pixel), its Outline round it with the corners cut, on whole art pixels.
func test_every_glyph_is_drawn_at_the_arts_detail_in_its_outline() -> void:
	_input.join(0)
	_input.join(1)
	var actions: Array[StringName] = [&"accept", &"back", &"alternate", &"staff_1", &"staff_2", &"staff_3", &"staff_4", &"pause", &"inventory", &"quick_up", &"quick_left"]
	var shapes: Dictionary = {}
	for player in 2:
		for action in actions:
			var glyph: ActionGlyphScript = _glyph(player, action)
			var body: PixelShape = glyph.body()
			var name: String = "%s for player %d" % [action, player + 1]
			check(body != null, "%s has a body" % name)
			if body == null:
				continue
			shapes[int(glyph.current_glyph()["shape"])] = true
			check_equal([body.width, body.height], [roundi(glyph.custom_minimum_size.x * 2.0), roundi(ActionGlyphScript.GLYPH_HEIGHT * 2.0)], "%s fills its glyph in art pixels" % name)
			check_equal(body.tone_at(0, 0), -1, "%s has its corner cut" % name)
			check_equal(body.tone_at(body.width / 2, 0), PixelShape.OUTLINE, "%s has its Outline along its top" % name)
	check(shapes.size() >= 4, "round buttons, symbols, shoulders and triggers among them (%d shapes)" % shapes.size())


func test_a_cap_is_cut_by_steps_at_its_corners() -> void:
	var rows: PackedStringArray = ActionGlyphScript.cap_rows(10, 8, 3, 1)
	check_equal(rows[0], "...####...", "the top row cut three in")
	check_equal(rows[2], ".########.", "a step a row")
	check_equal(rows[3], "##########", "then whole")
	check_equal(rows[7], ".########.", "the bottom cut one in")


## Notes the art pixels a drawing sets (two a layout pixel).
class GlyphPixels extends RefCounted:
	var lit: Dictionary = {}

	func draw_rect(rect: Rect2, _color: Color) -> void:
		var art := Rect2i(Vector2i((rect.position * 2.0).round()), Vector2i((rect.size * 2.0).round()))
		for y in range(art.position.y, art.end.y):
			for x in range(art.position.x, art.end.x):
				lit[Vector2i(x, y)] = true


func _arrow(label: String, side: int) -> Dictionary:
	var pixels := GlyphPixels.new()
	ActionGlyphScript.draw_dpad_arrows(pixels, label, side)
	return pixels.lit


## The d-pad's arrows: each arm's is the up arm's turned about the cross's middle, inside its arm.
func test_each_dpad_arm_lights_the_up_arms_arrow_turned() -> void:
	var side: int = roundi(ActionGlyphScript.GLYPH_HEIGHT * 2.0) - 2
	var up: Dictionary = _arrow("up", side)
	check(up.size() >= 6, "the up arrow is drawn (%d art pixels)" % up.size())
	var from: int = (side - ActionGlyphScript.DPAD_ARM) / 2
	for pixel: Vector2i in up:
		check(pixel.x - 1 >= from and pixel.x - 1 < from + ActionGlyphScript.DPAD_ARM and pixel.y - 1 < from, "up's arrow inside the up arm (%s)" % pixel)
	# Turning a pixel of the cross (inside its Outline) a quarter clockwise about its middle.
	var turned: Dictionary = up
	for label: String in ["right", "down", "left"]:
		var next: Dictionary = {}
		for pixel: Vector2i in turned:
			var x: int = pixel.x - 1
			var y: int = pixel.y - 1
			next[Vector2i(side - 1 - y + 1, x + 1)] = true
		turned = next
		var drawn: Dictionary = _arrow(label, side)
		check_equal(drawn.keys().size(), turned.keys().size(), "%s: as many pixels as up's" % label)
		var same: bool = true
		for pixel: Vector2i in turned:
			same = same and drawn.has(pixel)
		check(same, "%s's arrow is up's turned" % label)
	check_equal(_arrow("all", side).size(), up.size() * 4, "all four for the whole d-pad")
