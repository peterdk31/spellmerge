extends RefCounted
## Which button shows an action, for each kind of controller: the data behind every
## "press this" glyph. Pure lookup, no state and no nodes.
##
## A player's glyph kind (`PlayerInput.glyph_kind(player)`) says what they hold: the keyboard,
## the keyboard with the mouse aiming, or a gamepad of one family. `glyph(kind, action)`
## answers with a Dictionary the drawing widget (`hud/widgets/action_glyph.gd`) reads:
##
##     {"shape": Shape.FACE, "label": "X", "color": Color(...)}
##
## The buttons are the first binding of each action in project.godot, per family. Godot
## numbers face buttons by place (bottom, right, left, top), so one action sits on the same
## place on every pad and only the label changes: Xbox A/B/X/Y, PlayStation cross, circle,
## square, triangle, Switch B/A/Y/X. The glyph shows what is printed on the pad.

## What the player holds.
enum Kind { KEYBOARD, KEYBOARD_MOUSE, XBOX, PLAYSTATION, SWITCH, GAMEPAD }
## How a glyph is drawn: a key cap with its label, a round face button with a letter, a
## round PlayStation button with a symbol (label is `cross`, `circle`, `square` or
## `triangle`), a shoulder button, or the mouse with its left button lit.
enum Shape { KEY, FACE, SYMBOL, SHOULDER, MOUSE }

const FACE_GREEN: Color = Color(0.36, 0.72, 0.4)
const FACE_RED: Color = Color(0.86, 0.3, 0.3)
const FACE_BLUE: Color = Color(0.3, 0.52, 0.9)
const FACE_YELLOW: Color = Color(0.92, 0.76, 0.25)
const PLAIN: Color = Color(0.82, 0.84, 0.88)
const PS_CROSS: Color = Color(0.5, 0.65, 0.95)
const PS_CIRCLE: Color = Color(0.92, 0.4, 0.4)
const PS_SQUARE: Color = Color(0.88, 0.55, 0.8)
const PS_TRIANGLE: Color = Color(0.4, 0.8, 0.65)

const NO_GLYPH: Dictionary = {"shape": Shape.KEY, "label": "?", "color": PLAIN}

const _KEYS: Dictionary = {
	&"cast": "J", &"dodge": "Space", &"overlay": "E", &"swap": "Q", &"join": "Enter",
	&"leave": "Bksp", &"move_up": "W", &"move_down": "S", &"move_left": "A", &"move_right": "D",
}

## Name fragments (lower case) of a gamepad's name, per family.
## Browsers name a pad like "Wireless Controller (STANDARD GAMEPAD Vendor: 054c Product: 09cc)",
## so the vendor ids (Microsoft 045e, Sony 054c, Nintendo 057e) are matched too.
const _XBOX_NAMES: Array[String] = ["xbox", "x-box", "xinput", "microsoft", "vendor: 045e"]
const _PLAYSTATION_NAMES: Array[String] = ["playstation", "ps3", "ps4", "ps5", "dualshock", "dualsense", "sony", "vendor: 054c"]
const _SWITCH_NAMES: Array[String] = ["nintendo", "switch", "joy-con", "joycon", "pro controller", "vendor: 057e"]


## The family of a gamepad from the name the system gives it (`Input.get_joy_name`).
static func kind_of_pad(joy_name: String) -> int:
	var lower: String = joy_name.to_lower()
	for fragment in _XBOX_NAMES:
		if lower.contains(fragment):
			return Kind.XBOX
	for fragment in _PLAYSTATION_NAMES:
		if lower.contains(fragment):
			return Kind.PLAYSTATION
	for fragment in _SWITCH_NAMES:
		if lower.contains(fragment):
			return Kind.SWITCH
	return Kind.GAMEPAD


static func is_pad(kind: int) -> bool:
	return kind >= Kind.XBOX


## How to draw `action` for `kind`; NO_GLYPH for an action with no button.
static func glyph(kind: int, action: StringName) -> Dictionary:
	if kind == Kind.KEYBOARD_MOUSE and action == &"cast":
		return {"shape": Shape.MOUSE, "label": "LMB", "color": PLAIN}
	if not is_pad(kind):
		if _KEYS.has(action):
			return {"shape": Shape.KEY, "label": _KEYS[action], "color": PLAIN}
		return NO_GLYPH
	match action:
		&"cast":
			return _face(kind, 2)
		&"dodge":
			return _face(kind, 1)
		&"overlay":
			return _face(kind, 3)
		&"join":
			return _face(kind, 0)
		&"swap":
			var shoulder: String = "L1" if kind == Kind.PLAYSTATION else ("L" if kind == Kind.SWITCH else "LB")
			return {"shape": Shape.SHOULDER, "label": shoulder, "color": PLAIN}
		&"leave":
			var back: String = "Share" if kind == Kind.PLAYSTATION else ("-" if kind == Kind.SWITCH else "Back")
			return {"shape": Shape.SHOULDER, "label": back, "color": PLAIN}
	return NO_GLYPH


## A face button by place: 0 bottom, 1 right, 2 left, 3 top (Godot's JoyButton 0 to 3).
static func _face(kind: int, place: int) -> Dictionary:
	if kind == Kind.PLAYSTATION:
		var symbols: Array[String] = ["cross", "circle", "square", "triangle"]
		var colors: Array[Color] = [PS_CROSS, PS_CIRCLE, PS_SQUARE, PS_TRIANGLE]
		return {"shape": Shape.SYMBOL, "label": symbols[place], "color": colors[place]}
	if kind == Kind.SWITCH:
		var letters: Array[String] = ["B", "A", "Y", "X"]
		return {"shape": Shape.FACE, "label": letters[place], "color": PLAIN}
	var xbox_letters: Array[String] = ["A", "B", "X", "Y"]
	var xbox_colors: Array[Color] = [FACE_GREEN, FACE_RED, FACE_BLUE, FACE_YELLOW]
	return {"shape": Shape.FACE, "label": xbox_letters[place], "color": xbox_colors[place]}
