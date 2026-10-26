extends Control
## The button that does an action, drawn in code: a key cap, the mouse, a round face button
## with a letter or a PlayStation symbol, or a shoulder button, whatever `player` holds right
## now. It replaces writing the action's name: "Use (Cast)" becomes the verb with this glyph
## beside it. Display only: no input, no focus.
##
##     glyph.bind(input)              # the PlayerInput node (null: the "PlayerInput" autoload)
##     glyph.show_action(player, &"cast")
##
## It redraws on the input manager's `glyph_kind_changed(player)`, so it follows the player
## from an Xbox pad to a PlayStation pad or to the keyboard (a leave and a join) and from the
## keyboard to the mouse (the mouse aim turning on) as it happens. It allocates only when the
## kind changes, never per frame.

const InputManagerScript := preload("res://core/input/input_manager.gd")
const GlyphsScript := preload("res://core/input/input_glyphs.gd")

const GLYPH_HEIGHT: float = 10.0
const FONT_SIZE: int = 8
## A key cap is at least this wide, and each letter adds its own width plus a margin.
const KEY_MIN_WIDTH: float = 10.0
const KEY_MARGIN: float = 4.0
const ROUND_WIDTH: float = 10.0
const SHOULDER_MIN_WIDTH: float = 12.0
const MOUSE_WIDTH: float = 8.0
const OUTLINE: Color = Color(0.05, 0.05, 0.08)
const KEY_FACE: Color = Color(0.22, 0.24, 0.3)
const TEXT_ON_PLAIN: Color = Color(0.95, 0.96, 0.98)
const TEXT_ON_COLOR: Color = Color(0.06, 0.06, 0.1)

var _input: InputManagerScript = null
var _player: int = 0
var _action: StringName = &""
var _glyph: Dictionary = GlyphsScript.NO_GLYPH


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(ROUND_WIDTH, GLYPH_HEIGHT)


## Use this input manager; null uses the "PlayerInput" autoload.
func bind(input: InputManagerScript) -> void:
	if _input != null and _input.glyph_kind_changed.is_connected(_on_kind_changed):
		_input.glyph_kind_changed.disconnect(_on_kind_changed)
	_input = input
	if _input != null:
		_input.glyph_kind_changed.connect(_on_kind_changed)
	_refresh()


## Draw the button of `action` for `player`.
func show_action(player: int, action: StringName) -> void:
	_player = player
	_action = action
	if _input == null:
		bind(get_node_or_null("/root/PlayerInput") as InputManagerScript)
	else:
		_refresh()


func action() -> StringName:
	return _action


## What is drawn, as GlyphsScript.glyph answers: shape, label and colour.
func current_glyph() -> Dictionary:
	return _glyph


func _notification(what: int) -> void:
	# The HUD theme's font is known only inside the tree, so measure again there.
	if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_THEME_CHANGED:
		_refresh()


func _on_kind_changed(player: int) -> void:
	if player == _player:
		_refresh()


func _refresh() -> void:
	var kind: int = GlyphsScript.Kind.KEYBOARD if _input == null else _input.glyph_kind(_player)
	_glyph = GlyphsScript.glyph(kind, _action)
	custom_minimum_size = Vector2(_glyph_width(), GLYPH_HEIGHT)
	queue_redraw()


func _glyph_width() -> float:
	var label: String = _glyph["label"]
	match int(_glyph["shape"]):
		GlyphsScript.Shape.KEY:
			return maxf(KEY_MIN_WIDTH, _text_width(label) + KEY_MARGIN)
		GlyphsScript.Shape.SHOULDER, GlyphsScript.Shape.TRIGGER:
			return maxf(SHOULDER_MIN_WIDTH, _text_width(label) + KEY_MARGIN)
		GlyphsScript.Shape.MOUSE:
			return MOUSE_WIDTH
	return ROUND_WIDTH


func _text_width(text: String) -> float:
	return _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x


func _font() -> Font:
	return get_theme_default_font()


func _draw() -> void:
	var color: Color = _glyph["color"]
	var area := Rect2(Vector2.ZERO, Vector2(custom_minimum_size.x, GLYPH_HEIGHT))
	match int(_glyph["shape"]):
		GlyphsScript.Shape.KEY:
			_draw_cap(area, KEY_FACE, TEXT_ON_PLAIN)
		GlyphsScript.Shape.SHOULDER:
			_draw_cap(area, color.darkened(0.55), TEXT_ON_PLAIN)
		GlyphsScript.Shape.TRIGGER:
			_draw_trigger(area, color.darkened(0.55))
		GlyphsScript.Shape.FACE:
			_draw_disc(area, color)
			_draw_label(area, _glyph["label"], TEXT_ON_COLOR)
		GlyphsScript.Shape.SYMBOL:
			_draw_disc(area, KEY_FACE)
			_draw_symbol(area, String(_glyph["label"]), color)
		GlyphsScript.Shape.MOUSE:
			_draw_mouse(area)
		GlyphsScript.Shape.DPAD:
			_draw_dpad(area)


func _draw_cap(area: Rect2, face: Color, text_color: Color) -> void:
	draw_rect(area, OUTLINE)
	draw_rect(area.grow(-1.0), face)
	_draw_label(area, _glyph["label"], text_color)


func _draw_disc(area: Rect2, face: Color) -> void:
	var center: Vector2 = area.get_center()
	var radius: float = minf(area.size.x, area.size.y) * 0.5
	draw_circle(center, radius, OUTLINE)
	draw_circle(center, radius - 1.0, face)


func _draw_label(area: Rect2, text: String, text_color: Color) -> void:
	var font: Font = _font()
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var ascent: float = font.get_ascent(FONT_SIZE)
	var height: float = font.get_height(FONT_SIZE)
	var origin := Vector2(area.position.x + (area.size.x - width) * 0.5, area.position.y + (area.size.y - height) * 0.5 + ascent)
	draw_string(font, origin.round(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, text_color)


## The four PlayStation symbols, each in its own colour inside the dark disc.
func _draw_symbol(area: Rect2, symbol: String, color: Color) -> void:
	var c: Vector2 = area.get_center()
	var r: float = 2.5
	match symbol:
		"cross":
			draw_line(c + Vector2(-r, -r), c + Vector2(r, r), color, 1.0)
			draw_line(c + Vector2(-r, r), c + Vector2(r, -r), color, 1.0)
		"circle":
			draw_arc(c, r, 0.0, TAU, 12, color, 1.0)
		"square":
			draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), color, false, 1.0)
		"triangle":
			var points := PackedVector2Array([c + Vector2(0.0, -r), c + Vector2(r, r * 0.8), c + Vector2(-r, r * 0.8), c + Vector2(0.0, -r)])
			draw_polyline(points, color, 1.0)


## A trigger: a shoulder cap with its top corners cut, so LT and RT read apart from LB and RB
## by shape too, not only by their label.
func _draw_trigger(area: Rect2, face: Color) -> void:
	_draw_cap(area, face, TEXT_ON_PLAIN)
	draw_rect(Rect2(area.position, Vector2(2.0, 2.0)), OUTLINE)
	draw_rect(Rect2(Vector2(area.end.x - 2.0, area.position.y), Vector2(2.0, 2.0)), OUTLINE)
	draw_line(Vector2(area.position.x + 2.0, area.position.y + 2.5), Vector2(area.end.x - 2.0, area.position.y + 2.5), TEXT_ON_PLAIN.darkened(0.3), 1.0)


## The d-pad: a cross with the arm of its label (`left` or `right`) lit.
func _draw_dpad(area: Rect2) -> void:
	var c: Vector2 = area.get_center().floor()
	draw_rect(Rect2(c.x - 5.0, c.y - 2.0, 10.0, 4.0), OUTLINE)
	draw_rect(Rect2(c.x - 2.0, c.y - 5.0, 4.0, 10.0), OUTLINE)
	draw_rect(Rect2(c.x - 4.0, c.y - 1.0, 8.0, 2.0), KEY_FACE)
	draw_rect(Rect2(c.x - 1.0, c.y - 4.0, 2.0, 8.0), KEY_FACE)
	var lit: float = -4.0 if String(_glyph["label"]) == "left" else 2.0
	draw_rect(Rect2(c.x + lit, c.y - 1.0, 2.0, 2.0), TEXT_ON_PLAIN)


## The mouse: a body with the button of its label lit (LMB the left, RMB the right), the way a
## player reads "click".
func _draw_mouse(area: Rect2) -> void:
	draw_rect(area, OUTLINE)
	draw_rect(area.grow(-1.0), KEY_FACE)
	var left: float = 1.0 if String(_glyph["label"]) != "RMB" else area.size.x * 0.5
	draw_rect(Rect2(area.position + Vector2(left, 1.0), Vector2(area.size.x * 0.5 - 1.0, 4.0)), GlyphsScript.FACE_YELLOW)
	draw_line(Vector2(area.size.x * 0.5, 1.0), Vector2(area.size.x * 0.5, 5.0), OUTLINE, 1.0)
