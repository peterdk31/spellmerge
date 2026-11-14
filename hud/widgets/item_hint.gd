extends Control
## The hint over an item in reach (items I6, docs/milestones/items.md, "What the players see"): one
## per player, over the item the body they drive can take (`item_near_changed`): the `accept`
## button's glyph (A; Enter or F) with "Take" and the item's name, and a small tooltip under it: for
## a staff its numbers (slots, cooldown, mana) and its row of cards, for a card its name alone. When
## a take is refused (`item_refused`: no room in its bag) it shakes and goes red for a moment; it
## names no bag (owner, 2026-11-13: the player sees what the item is).
##
## Display only: it reads no input (the HUD's panels send A as `item_take_requested`) and sends
## nothing. Its owner places it (`place_over`): over the item's place in the world as the camera
## shows it now. The shake runs on real time (`step`).
##
##     hint.bind(input, spells)
##     hint.show_item(player, item, view)    # item -1, or an empty view: hidden

const InputManagerScript := preload("res://core/input/input_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ActionGlyphScript := preload("res://hud/widgets/action_glyph.gd")

## What A is called on the hint.
const VERB: String = "Take"
const ACTION: StringName = &"accept"
const FONT_SIZE: int = 8
const PAD: float = 3.0
const GAP: float = 3.0
## A card's icon in the tooltip's row, and the gap between two.
const ICON: float = 8.0
const ICON_GAP: float = 1.0
## How far over the item's place the hint's lower edge sits, in screen pixels.
const LIFT: float = 22.0
## A refused take: how long it shakes, how far and how fast.
const SHAKE_TIME: float = 0.4
const SHAKE_PIXELS: float = 3.0
const SHAKE_RATE: float = 40.0
const BACK: Color = Color(0.06, 0.06, 0.1, 0.8)
const EDGE: Color = Color(0.85, 0.75, 0.45, 0.9)
const REFUSED: Color = Color(0.9, 0.25, 0.22, 1.0)
const TEXT: Color = Color(0.95, 0.96, 0.98)
const DIM: Color = Color(0.7, 0.72, 0.8)

var _input: InputManagerScript = null
var _spells: SpellsScript = null
var _glyph: ActionGlyphScript = null
var _player: int = 0
## The item shown (-1: none) and its view (`ground_item_changed`'s).
var _item: int = -1
var _view: Dictionary = {}
## The words and the tooltip's line, and the cards' icons, made when the item changes.
var _title: String = ""
var _line: String = ""
var _icons: Array[Texture2D] = []
## Seconds of the refused shake left.
var _shake_left: float = 0.0
## Where its owner put it, before the shake.
var _placed: Vector2 = Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	_glyph = ActionGlyphScript.new()
	_glyph.name = "Glyph"
	add_child(_glyph)


## Use this input manager (for the glyph) and Spells (the cards' icons); null: the autoloads.
func bind(input: InputManagerScript, spells: SpellsScript) -> void:
	_input = input
	_spells = spells
	_glyph.bind(input)


## Show `view` (the item `item`) for `player`; item -1 or an empty view hides it.
func show_item(player: int, item: int, view: Dictionary) -> void:
	_player = player
	_item = item if not view.is_empty() else -1
	_view = view if _item >= 0 else {}
	_shake_left = 0.0
	visible = _item >= 0
	if not visible:
		return
	if _glyph != null:
		_glyph.show_action(player, ACTION)
	_title = "%s %s" % [VERB, String(view.get("name", ""))]
	_line = tooltip_line(view)
	_icons.clear()
	for id: Variant in view.get("cards", []):
		if StringName(id) != &"" and _spells != null:
			_icons.append(_spells.component_icon(StringName(id)))
	_lay_out()
	queue_redraw()


## The item shown, -1 for none.
func item() -> int:
	return _item


## The words on it ("Take Wild star") and the tooltip's line of numbers (for tests).
func title() -> String:
	return _title


func line() -> String:
	return _line


## True while it shakes red after a refused take.
func is_refused() -> bool:
	return _shake_left > 0.0


## The tooltip's numbers for `view`: a staff's slots, cooldown and mana; nothing for anything else.
static func tooltip_line(view: Dictionary) -> String:
	if not view.has("slots"):
		return ""
	return "%d slots  %.2f s  %d mana" % [int(view["slots"]), float(view.get("cooldown", 0.0)), int(view.get("max_mana", 0.0))]


## A take of `item` was refused: shake red (nothing for another item).
func refuse(item: int) -> void:
	if item != _item or _item < 0:
		return
	_shake_left = SHAKE_TIME
	queue_redraw()


## Put it over `point` (screen pixels: the item's place as the camera shows it now), `stack`
## hints up when several players' hints share it.
func place_over(point: Vector2, stack: int = 0) -> void:
	_placed = Vector2(roundf(point.x - size.x * 0.5), roundf(point.y - LIFT - size.y - float(stack) * (size.y + GAP)))
	position = _placed + _shake_offset()


## Real time for the shake.
func step(delta: float) -> void:
	if _shake_left <= 0.0:
		return
	_shake_left = maxf(_shake_left - delta, 0.0)
	position = _placed + _shake_offset()
	queue_redraw()


func _shake_offset() -> Vector2:
	if _shake_left <= 0.0:
		return Vector2.ZERO
	return Vector2(roundf(sin(_shake_left * SHAKE_RATE) * SHAKE_PIXELS * _shake_left / SHAKE_TIME), 0.0)


func _font() -> Font:
	return get_theme_default_font()


func _lay_out() -> void:
	var font: Font = _font()
	var glyph_width: float = _glyph.custom_minimum_size.x if _glyph != null else 10.0
	var top_width: float = glyph_width + GAP + font.get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var width: float = top_width
	var height: float = float(ActionGlyphScript.GLYPH_HEIGHT)
	if _line != "":
		width = maxf(width, font.get_string_size(_line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
		height += GAP + float(FONT_SIZE)
	if not _icons.is_empty():
		width = maxf(width, float(_icons.size()) * (ICON + ICON_GAP) - ICON_GAP)
		height += GAP + ICON
	size = Vector2(ceilf(width + PAD * 2.0), ceilf(height + PAD * 2.0))
	if _glyph != null:
		_glyph.position = Vector2(PAD, PAD)


func _draw() -> void:
	if _item < 0:
		return
	var refused: bool = _shake_left > 0.0
	draw_rect(Rect2(Vector2.ZERO, size), BACK)
	draw_rect(Rect2(Vector2.ZERO, size), REFUSED if refused else EDGE, false, 1.0)
	var font: Font = _font()
	var glyph_width: float = _glyph.custom_minimum_size.x if _glyph != null else 10.0
	var y: float = PAD + float(ActionGlyphScript.GLYPH_HEIGHT) - 2.0
	draw_string(font, Vector2(PAD + glyph_width + GAP, y), _title, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, REFUSED if refused else TEXT)
	y += 2.0
	if _line != "":
		y += GAP + float(FONT_SIZE)
		draw_string(font, Vector2(PAD, y - 1.0), _line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, DIM)
	if not _icons.is_empty():
		var x: float = PAD
		y += GAP
		for icon: Texture2D in _icons:
			if icon != null:
				draw_texture_rect(icon, Rect2(Vector2(x, y), Vector2(ICON, ICON)), false)
			x += ICON + ICON_GAP
