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
##
## **At the art's detail** (ART4 part 3; docs/STYLE.md, "UI"): each glyph is pixel art at half a layout
## pixel, its body baked as the kind changes (`PixelShape`: the Outline an art pixel round it, its
## corners cut, lit from the top-left): a key cap standing on its darker lip, a bumper with its top
## rounded, a trigger with its top cut away, a round face button shaded in its colour, a PlayStation
## symbol drawn from its strokes on a stone disc, the mouse with its button lit and the d-pad's cross
## with the arm's arrow lit. It sits on the game with no box behind it, as the clean HUD.

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
const OUTLINE: Color = Palette.OUTLINE
const KEY_FACE: Color = Color("#4a4663")
const TEXT_ON_PLAIN: Color = Palette.WHITE_HOT
const TEXT_ON_COLOR: Color = Palette.OUTLINE
## The tones (`PixelShape`: Outline, light, base, shadow) of a key cap and the mouse (stone), and of
## a bumper or a trigger (a step darker, so they read apart from a key).
const STONE_TONES: PackedColorArray = [Color("#14121f"), Color("#7a7694"), Color("#4a4663"), Color("#2b2840")]
const DARK_TONES: PackedColorArray = [Color("#14121f"), Color("#4a4663"), Color("#2b2840"), Color("#14121f")]
## The art pixel, in layout pixels; a key cap's lip under its face and how far its label rises over
## it, in art pixels; how far each shape's top (and bottom) corners are cut, in art pixels.
const ART: float = PixelShape.ART_PIXEL
const LIP: int = 2
const CUT_KEY: int = 1
const CUT_SHOULDER: int = 2
const CUT_TRIGGER: int = 7
const CUT_MOUSE: int = 4
## The d-pad: its arms' width in art pixels, and the lit arrow at an arm's tip: DPAD_ARROW_ROWS rows,
## two art pixels wide at its point and two wider a row, its point DPAD_ARROW_IN art pixels in from
## the arm's end (worked out from the cross's size, so it stays centred in the arm).
const DPAD_ARM: int = 6
const DPAD_ARROW_ROWS: int = 3
const DPAD_ARROW_IN: int = 2
const DPAD_TURNS: Array[String] = ["up", "right", "down", "left"]
## The PlayStation symbols, 8 × 8 art pixels, strokes two art pixels thick (`#` lit); the circle is a
## ring of the same band.
const SYMBOL_ROWS: Dictionary = {
	"cross": ["##....##", "###..###", ".######.", "..####..", "..####..", ".######.", "###..###", "##....##"],
	"square": ["########", "########", "##....##", "##....##", "##....##", "##....##", "########", "########"],
	"triangle": ["...##...", "..####..", "..####..", ".##..##.", ".##..##.", "##....##", "########", "########"],
}
const SYMBOL_SIDE: int = 8

var _input: InputManagerScript = null
var _player: int = 0
var _action: StringName = &""
var _glyph: Dictionary = GlyphsScript.NO_GLYPH
## The glyph's body and its symbol (a PlayStation glyph's) at the art's detail, baked as the kind
## changes; and the tones a face button is drawn in.
var _body: PixelShape = null
var _symbol: PixelShape = null
var _tones: PackedColorArray = PackedColorArray(STONE_TONES)


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
	custom_minimum_size = Vector2(ceilf(_glyph_width()), GLYPH_HEIGHT)
	_bake()
	queue_redraw()


## The glyph's body at the art's detail (for tests).
func body() -> PixelShape:
	return _body


## The body (and the symbol) of the glyph shown, at the art's detail, its Outline in its own size.
func _bake() -> void:
	var wide: int = roundi(custom_minimum_size.x / ART) - 2
	var tall: int = roundi(GLYPH_HEIGHT / ART) - 2
	_symbol = null
	var color: Color = _glyph["color"]
	_tones = PackedColorArray(STONE_TONES)
	match int(_glyph["shape"]):
		GlyphsScript.Shape.KEY:
			_body = PixelShape.from_rows(cap_rows(wide, tall, CUT_KEY, CUT_KEY), true)
		GlyphsScript.Shape.SHOULDER:
			_body = PixelShape.from_rows(cap_rows(wide, tall, CUT_SHOULDER, CUT_KEY), true)
			_tones = PackedColorArray(DARK_TONES)
		GlyphsScript.Shape.TRIGGER:
			_body = PixelShape.from_rows(cap_rows(wide, tall, CUT_TRIGGER, CUT_KEY), true)
			_tones = PackedColorArray(DARK_TONES)
		GlyphsScript.Shape.MOUSE:
			_body = PixelShape.from_rows(cap_rows(wide, tall, CUT_MOUSE, CUT_MOUSE), true)
		GlyphsScript.Shape.DPAD:
			_body = PixelShape.from_rows(dpad_rows(tall), true)
		GlyphsScript.Shape.FACE:
			_body = PixelShape.disc(tall)
			_tones[PixelShape.LIGHT] = color.lightened(0.35)
			_tones[PixelShape.BASE] = color
			_tones[PixelShape.SHADOW] = color.darkened(0.4)
		GlyphsScript.Shape.SYMBOL:
			_body = PixelShape.disc(tall)
			var symbol: String = String(_glyph["label"])
			if SYMBOL_ROWS.has(symbol):
				_symbol = PixelShape.from_rows(PackedStringArray(SYMBOL_ROWS[symbol]), false, false)
			else:
				_symbol = PixelShape.ring(SYMBOL_SIDE, 2, false, false)


## A cap's rows, `wide` × `tall` art pixels (`#` filled), its top corners cut by `top` stepping in a
## pixel a row and its bottom ones by `bottom`.
static func cap_rows(wide: int, tall: int, top: int, bottom: int) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in tall:
		var inset: int = _inset(y, tall, top, bottom)
		rows.append(".".repeat(inset) + "#".repeat(maxi(wide - 2 * inset, 0)) + ".".repeat(inset))
	return rows


## How far row `y` of a cap `tall` rows high is cut in at each end.
static func _inset(y: int, tall: int, top: int, bottom: int) -> int:
	if y < top:
		return top - y
	if y >= tall - bottom:
		return bottom - (tall - 1 - y)
	return 0


## The d-pad's cross, `side` × `side` art pixels, its arms DPAD_ARM wide.
static func dpad_rows(side: int) -> PackedStringArray:
	var rows := PackedStringArray()
	var from: int = (side - DPAD_ARM) / 2
	for y in side:
		var row: String = ""
		for x in side:
			var in_arm: bool = (x >= from and x < from + DPAD_ARM) or (y >= from and y < from + DPAD_ARM)
			row += "#" if in_arm else "."
		rows.append(row)
	return rows


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
	if _body == null:
		return
	var area := Rect2(Vector2.ZERO, Vector2(custom_minimum_size.x, GLYPH_HEIGHT))
	var color: Color = _glyph["color"]
	_body.draw_at(self, Vector2.ZERO, _tones)
	match int(_glyph["shape"]):
		GlyphsScript.Shape.KEY:
			_draw_lip(area)
			_draw_label(Rect2(area.position, area.size - Vector2(0.0, ART)), _glyph["label"], TEXT_ON_PLAIN)
		GlyphsScript.Shape.SHOULDER, GlyphsScript.Shape.TRIGGER:
			_draw_label(area, _glyph["label"], TEXT_ON_PLAIN)
		GlyphsScript.Shape.FACE:
			_draw_label(area, _glyph["label"], TEXT_ON_COLOR)
		GlyphsScript.Shape.SYMBOL:
			if _symbol != null:
				_tones[PixelShape.BASE] = color
				_symbol.draw(self, area.get_center(), _tones)
				_tones[PixelShape.BASE] = STONE_TONES[PixelShape.BASE]
		GlyphsScript.Shape.MOUSE:
			_draw_mouse(area)
		GlyphsScript.Shape.DPAD:
			_draw_dpad()


## A key cap's lip: the LIP art rows above its bottom one in the stone's shadow, so the cap stands on
## it (its bottom row is in shadow already).
func _draw_lip(area: Rect2) -> void:
	var tall: int = roundi(area.size.y / ART)
	var wide: int = roundi(area.size.x / ART)
	draw_rect(Rect2(2.0 * ART, (tall - 2 - LIP) * ART, (wide - 4) * ART, LIP * ART), STONE_TONES[PixelShape.SHADOW])


func _draw_label(area: Rect2, text: String, text_color: Color) -> void:
	var font: Font = _font()
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var ascent: float = font.get_ascent(FONT_SIZE)
	var height: float = font.get_height(FONT_SIZE)
	var origin := Vector2(area.position.x + (area.size.x - width) * 0.5, area.position.y + (area.size.y - height) * 0.5 + ascent)
	draw_string(font, origin.round(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, text_color)


## The d-pad's lit arm (its label: `up`, `right`, `down`, `left`), or every arm (`all`): an arrow at
## its tip in Bone's white heat, pointing out.
func _draw_dpad() -> void:
	draw_dpad_arrows(self, String(_glyph["label"]), roundi(GLYPH_HEIGHT / ART) - 2)


## The d-pad's arrows for `label` on `target` (anything with `draw_rect`), the cross `side` art pixels
## square inside its Outline: each arrow's rows mirrored about the cross's middle for each arm, so
## every arm's is the up arm's turned.
static func draw_dpad_arrows(target: Object, label: String, side: int) -> void:
	for turn in DPAD_TURNS.size():
		if label != DPAD_TURNS[turn] and label != "all":
			continue
		for row in DPAD_ARROW_ROWS:
			var length: int = 2 + 2 * row
			var x: int = side / 2 - 1 - row
			var y: int = DPAD_ARROW_IN + row
			var run := Rect2(x, y, length, 1)
			match turn:
				1:
					run = Rect2(side - 1 - y, x, 1, length)
				2:
					run = Rect2(side - x - length, side - 1 - y, length, 1)
				3:
					run = Rect2(y, side - x - length, 1, length)
			# The cross sits inside its Outline, an art pixel in.
			target.draw_rect(Rect2((run.position + Vector2.ONE) * ART, run.size * ART), TEXT_ON_PLAIN)


## The mouse: its body with the button of its label lit (LMB the left, RMB the right), split down
## the middle and from the palm by the Outline, the way a player reads "click".
func _draw_mouse(area: Rect2) -> void:
	var wide: int = roundi(area.size.x / ART) - 2
	var tall: int = roundi(area.size.y / ART) - 2
	var half: int = wide / 2
	var right: bool = String(_glyph["label"]) == "RMB"
	var rows: int = tall / 2 - 1
	for y in rows:
		var inset: int = _inset(y, tall, CUT_MOUSE, CUT_MOUSE)
		var from: int = half + 1 if right else inset
		var to: int = wide - inset if right else half
		if to > from:
			draw_rect(Rect2((from + 1) * ART, (y + 1) * ART, (to - from) * ART, ART), GlyphsScript.FACE_YELLOW)
	draw_rect(Rect2((half + 1) * ART, ART, ART, rows * ART), OUTLINE)
	draw_rect(Rect2(2.0 * ART, (rows + 1) * ART, (wide - 2) * ART, ART), OUTLINE)
