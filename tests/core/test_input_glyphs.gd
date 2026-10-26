extends "res://tests/support/suite.gd"
## Tests for the glyph side of core/input: which button shows an action for each kind of
## controller (`input_glyphs.gd`), and what `PlayerInput.glyph_kind(player)` says as devices
## join and leave and the keyboard player switches between keys and the mouse.
##
## godot --headless --path . --script res://tests/core/test_input_glyphs.gd

const InputManagerScript := preload("res://core/input/input_manager.gd")
const GlyphsScript := preload("res://core/input/input_glyphs.gd")

const ACTIONS_SHOWN: Array[StringName] = [
	&"staff_1", &"staff_2", &"staff_3", &"staff_4", &"accept", &"back", &"alternate", &"pause", &"join", &"leave",
]
const FAMILIES: Array[int] = [GlyphsScript.Kind.KEYBOARD, GlyphsScript.Kind.KEYBOARD_MOUSE, GlyphsScript.Kind.XBOX, GlyphsScript.Kind.PLAYSTATION, GlyphsScript.Kind.SWITCH, GlyphsScript.Kind.GAMEPAD]

var _pad_names: Dictionary = {}
var _changes: Array[int] = []


func _manager() -> InputManagerScript:
	var manager := own(InputManagerScript.new()) as InputManagerScript
	manager.joy_name_provider = func(device: int) -> String: return String(_pad_names.get(device, ""))
	_changes.clear()
	manager.glyph_kind_changed.connect(func(player: int) -> void: _changes.append(player))
	return manager


func _click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func _cast_key() -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_J
	event.pressed = true
	return event


func test_a_pad_is_told_apart_by_its_name() -> void:
	check_equal(GlyphsScript.kind_of_pad("Xbox 360 Controller"), GlyphsScript.Kind.XBOX, "xbox")
	check_equal(GlyphsScript.kind_of_pad("PS5 Controller"), GlyphsScript.Kind.PLAYSTATION, "ps5")
	check_equal(GlyphsScript.kind_of_pad("Sony DualSense"), GlyphsScript.Kind.PLAYSTATION, "dualsense")
	check_equal(GlyphsScript.kind_of_pad("Nintendo Switch Pro Controller"), GlyphsScript.Kind.SWITCH, "switch")
	check_equal(GlyphsScript.kind_of_pad("Wireless Controller (STANDARD GAMEPAD Vendor: 054c Product: 09cc)"), GlyphsScript.Kind.PLAYSTATION, "web playstation")
	check_equal(GlyphsScript.kind_of_pad("Pro Controller (STANDARD GAMEPAD Vendor: 057e Product: 2009)"), GlyphsScript.Kind.SWITCH, "web switch")
	check_equal(GlyphsScript.kind_of_pad("Controller (STANDARD GAMEPAD Vendor: 045e Product: 028e)"), GlyphsScript.Kind.XBOX, "web xbox")
	check_equal(GlyphsScript.kind_of_pad("Some Generic Pad"), GlyphsScript.Kind.GAMEPAD, "unknown")
	check_equal(GlyphsScript.kind_of_pad(""), GlyphsScript.Kind.GAMEPAD, "no name")


func test_every_family_has_a_glyph_for_every_action_the_hints_use() -> void:
	for kind in FAMILIES:
		for action in ACTIONS_SHOWN:
			var glyph: Dictionary = GlyphsScript.glyph(kind, action)
			check(glyph != GlyphsScript.NO_GLYPH, "kind %d has a glyph for %s" % [kind, action])
			check(String(glyph["label"]) != "", "kind %d, %s has a label" % [kind, action])


func test_the_families_label_the_same_button_differently() -> void:
	var xbox: String = GlyphsScript.glyph(GlyphsScript.Kind.XBOX, &"staff_2")["label"]
	var playstation: String = GlyphsScript.glyph(GlyphsScript.Kind.PLAYSTATION, &"staff_2")["label"]
	var switch_label: String = GlyphsScript.glyph(GlyphsScript.Kind.SWITCH, &"staff_2")["label"]
	var keyboard: String = GlyphsScript.glyph(GlyphsScript.Kind.KEYBOARD, &"staff_2")["label"]
	check(xbox != playstation and xbox != switch_label and playstation != switch_label and xbox != keyboard, "cast reads %s, %s, %s, %s" % [xbox, playstation, switch_label, keyboard])


func test_the_mouse_shows_cast_as_a_click_and_nothing_else_changes() -> void:
	check_equal(GlyphsScript.glyph(GlyphsScript.Kind.KEYBOARD_MOUSE, &"staff_2"), {"shape": GlyphsScript.Shape.MOUSE, "label": "LMB", "color": GlyphsScript.PLAIN}, "staff_2 is the left mouse button")
	check_equal(GlyphsScript.glyph(GlyphsScript.Kind.KEYBOARD_MOUSE, &"staff_3")["label"], "RMB", "staff_3 is the right mouse button")
	check_equal(GlyphsScript.glyph(GlyphsScript.Kind.KEYBOARD_MOUSE, &"staff_1"), GlyphsScript.glyph(GlyphsScript.Kind.KEYBOARD, &"staff_1"), "staff_1 stays a key")


## The staffs sit on the shoulders (owner, 2026-10-26): RB, RT, LB, LT, named per family, with
## the triggers drawn as triggers.
func test_the_staffs_show_the_shoulder_buttons() -> void:
	var labels: Dictionary = {
		GlyphsScript.Kind.XBOX: ["RB", "RT", "LB", "LT"],
		GlyphsScript.Kind.PLAYSTATION: ["R1", "R2", "L1", "L2"],
		GlyphsScript.Kind.SWITCH: ["R", "ZR", "L", "ZL"],
	}
	var staffs: Array[StringName] = [&"staff_1", &"staff_2", &"staff_3", &"staff_4"]
	for kind: int in labels:
		for at in 4:
			var glyph: Dictionary = GlyphsScript.glyph(kind, staffs[at])
			check_equal(glyph["label"], labels[kind][at], "kind %d, %s" % [kind, staffs[at]])
			var shape: int = GlyphsScript.Shape.TRIGGER if at % 2 == 1 else GlyphsScript.Shape.SHOULDER
			check_equal(int(glyph["shape"]), shape, "kind %d, %s is drawn as a %s" % [kind, staffs[at], "trigger" if at % 2 == 1 else "bumper"])


func test_the_glyphs_follow_the_bindings_in_the_input_map() -> void:
	var place_of: Dictionary = {
		&"join": JOY_BUTTON_A, &"accept": JOY_BUTTON_A, &"back": JOY_BUTTON_B, &"alternate": JOY_BUTTON_X,
		&"staff_1": JOY_BUTTON_RIGHT_SHOULDER, &"staff_3": JOY_BUTTON_LEFT_SHOULDER, &"pause": JOY_BUTTON_START,
	}
	for action: StringName in place_of:
		var bound: bool = false
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == place_of[action]:
				bound = true
		check(bound, "%s is bound to joypad button %d, which the pad glyphs show" % [action, place_of[action]])
	var keys: Dictionary = {
		&"staff_2": KEY_J, &"staff_3": KEY_K, &"staff_1": KEY_SPACE, &"staff_4": KEY_Q, &"accept": KEY_ENTER,
		&"back": KEY_TAB, &"alternate": KEY_X, &"pause": KEY_ESCAPE,
	}
	for action: StringName in keys:
		var key_bound: bool = false
		for event in InputMap.action_get_events(action):
			if event is InputEventKey and (event as InputEventKey).physical_keycode == keys[action]:
				key_bound = true
		check(key_bound, "%s is bound to key %d, which the keyboard glyphs show" % [action, keys[action]])


func test_each_player_has_the_kind_of_the_pad_they_hold() -> void:
	_pad_names = {0: "Xbox One Controller", 1: "PS4 Controller", 2: "Nintendo Switch Pro Controller"}
	var manager: InputManagerScript = _manager()
	for pad in 3:
		manager.join(pad)
	check_equal(manager.glyph_kind(0), GlyphsScript.Kind.XBOX, "player 1")
	check_equal(manager.glyph_kind(1), GlyphsScript.Kind.PLAYSTATION, "player 2")
	check_equal(manager.glyph_kind(2), GlyphsScript.Kind.SWITCH, "player 3")
	check_equal(_changes, [0, 1, 2] as Array[int], "each join announces its own player only")


func test_the_keyboard_player_switches_between_keys_and_the_mouse_live() -> void:
	var manager: InputManagerScript = _manager()
	manager.join(InputManagerScript.KEYBOARD)
	check_equal(manager.glyph_kind(0), GlyphsScript.Kind.KEYBOARD, "starts on the keys")
	_changes.clear()
	manager.handle_event(_click())
	check_equal(manager.glyph_kind(0), GlyphsScript.Kind.KEYBOARD_MOUSE, "a click turns the mouse on")
	manager.handle_event(_click())
	check_equal(_changes, [0] as Array[int], "a second click changes nothing, so it announces nothing")
	manager.handle_event(_cast_key())
	check_equal(manager.glyph_kind(0), GlyphsScript.Kind.KEYBOARD, "the cast key turns it off again")
	check_equal(_changes, [0, 0] as Array[int], "each switch is announced once")


func test_a_player_who_leaves_and_joins_with_another_device_changes_kind() -> void:
	_pad_names = {0: "Xbox One Controller"}
	var manager: InputManagerScript = _manager()
	manager.join(0)
	check_equal(manager.glyph_kind(0), GlyphsScript.Kind.XBOX, "on the Xbox pad")
	manager.leave(0)
	manager.join(InputManagerScript.KEYBOARD)
	check_equal(manager.glyph_kind(0), GlyphsScript.Kind.KEYBOARD, "now on the keyboard")
	check(_changes.size() >= 3, "the leave and the join were both announced")


func test_a_bot_and_an_empty_slot_have_a_kind() -> void:
	var manager: InputManagerScript = _manager()
	manager.add_virtual_device(1)
	check_equal(manager.glyph_kind(1), GlyphsScript.Kind.GAMEPAD, "a bot draws as a plain pad")
	check_equal(manager.glyph_kind(3), GlyphsScript.Kind.KEYBOARD, "an empty slot reads as the keyboard")
	check_equal(manager.glyph_kind(9), GlyphsScript.Kind.KEYBOARD, "an invalid index does not crash")
