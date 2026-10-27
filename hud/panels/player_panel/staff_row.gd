extends Control
## One staff's row under the corner panel's mana bar (owner, 2026-10-27): the staff's button
## glyph, then its cast sequence as small card icons in read order, one framed group per cast of
## the cycle, so a player sees which cards fire together and finds a card that does nothing.
##
## - The cast the staff fires next has a gold frame and full-bright icons; the other casts are
##   dimmer, so the highlight is told by brightness too, not by colour alone.
## - A wasted card (the compiler's `wasted` for that cast) is greyed and struck through.
## - The bar under the icons (the row's width) is the staff's delay: full when it casts, empty when it is ready.
##   During the recharge after the last cast of the cycle the bar is dashed and orange and the
##   icons dim, so a recharge reads apart from a plain delay by shape as well as colour.
## - A staff longer than the row shows "+N" for the cards that do not fit (gold when the next
##   cast is among them).
##
## Display only: no input, no focus. `set_plan` takes the plain `Spells.staff_view` and an icon
## per card (it allocates, once per plan); `set_timing` takes the cursor and the seconds left each
## frame and only redraws when they changed, allocating nothing.

const GlyphScript := preload("res://hud/widgets/action_glyph.gd")

const ICON: float = 8.0
## One icon plus the 1 px between two icons.
const ICON_STEP: float = 9.0
const BOX_HEIGHT: float = 10.0
const BAR_Y: float = 11.0
const BAR_HEIGHT: float = 2.0
const ROW_HEIGHT: float = 13.0
## Between two casts' frames.
const CAST_GAP: float = 2.0
## The glyph cell (the shoulder glyphs are 12 px; a wider key pushes the cards right).
const GLYPH_CELL: float = 14.0
const PLUS_FONT_SIZE: int = 8
## Room kept for "+N" when cards are left over.
const PLUS_WIDTH: float = 13.0
const DASH: float = 2.0

const FRAME: Color = Color("#4a4663")
const FILL: Color = Color(0.11, 0.1, 0.16, 0.85)
const NEXT_FILL: Color = Color(0.24, 0.21, 0.12, 0.95)
const GOLD: Color = Color("#f2c230")
const MUTED: Color = Color("#a39fb8")
const WASTE_TINT: Color = Color(0.45, 0.45, 0.5, 0.55)
const STRIKE: Color = Color("#e0592f")
const OTHER_TINT: Color = Color(0.72, 0.72, 0.78, 1.0)
const RECHARGE_TINT: Color = Color(0.5, 0.5, 0.55, 0.9)
const BAR_BACK: Color = Color(0.0, 0.0, 0.0, 0.55)
const BAR_DELAY: Color = Color("#7fd6f5")
const BAR_RECHARGE: Color = Color("#f08a3c")
const PLACEHOLDER: Color = Color("#7a7694")

## The player index 0-3 and the staff 0-3, set before adding the node.
var player: int = 0
var staff: int = 0

## Per card shown, in read order: its icon (null draws a plain square) and whether it is wasted.
var _icons: Array[Texture2D] = []
var _wasted: PackedByteArray = PackedByteArray()
## Per cast: the index in `_icons` of its first card, and how many cards it read.
var _cast_first: PackedInt32Array = PackedInt32Array()
var _cast_size: PackedInt32Array = PackedInt32Array()
## The cast fired next (`Spells.cast_index`), the delay left and the delay it started from.
var _cursor: int = 0
var _left: float = 0.0
var _total: float = 0.0
var _recharging: bool = false
## "+N", made when the plan or the width changes, never per frame.
var _plus_text: String = ""
var _shown: int = 0
var _glyph: GlyphScript = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	_glyph = GlyphScript.new()
	_glyph.name = "Glyph"
	_glyph.position = Vector2(0.0, 0.0)
	add_child(_glyph)
	_glyph.show_action(player, StringName("staff_%d" % (staff + 1)))
	resized.connect(_measure)


## Show the plan of `Spells.staff_view` (`cards`, `casts` with `slots` and `wasted`, the staff's
## `wasted`); `icons` holds the icon of each card id of `plan["cards"]` by slot (null for none).
## A plan with no cast but cards (every card unknown) shows them as one wasted group.
func set_plan(plan: Dictionary, icons: Array[Texture2D]) -> void:
	_icons.clear()
	_wasted.clear()
	_cast_first.clear()
	_cast_size.clear()
	var casts: Array = plan.get("casts", [])
	for cast: Dictionary in casts:
		var slots: PackedInt32Array = cast.get("slots", PackedInt32Array())
		var wasted: Dictionary = cast.get("wasted", {})
		_cast_first.append(_icons.size())
		_cast_size.append(slots.size())
		for slot in slots:
			_icons.append(icons[slot] if slot >= 0 and slot < icons.size() else null)
			_wasted.append(1 if wasted.has(slot) else 0)
	if casts.is_empty():
		var cards: Array = plan.get("cards", [])
		for slot in cards.size():
			if StringName(cards[slot]) != &"":
				_icons.append(icons[slot] if slot < icons.size() else null)
				_wasted.append(1)
		if not _icons.is_empty():
			_cast_first.append(0)
			_cast_size.append(_icons.size())
	_cursor = 0
	_left = 0.0
	_total = 0.0
	_recharging = false
	_measure()


## The staff's next cast and its delay left, from `Spells.cast_index` and `cooldown_left`. A
## rise in the delay is a cast: the bar starts full from there, and it is a recharge when the
## cycle started over (the cursor is back at 0).
func set_timing(cursor: int, left: float) -> void:
	if left > _left + 0.0001:
		_total = left
		_recharging = cursor == 0
	if left <= 0.0:
		_recharging = false
	if cursor == _cursor and is_equal_approx(left, _left):
		return
	_cursor = cursor
	_left = maxf(left, 0.0)
	queue_redraw()


## The cards shown in read order (for tests): how many, and how many are greyed.
func card_count() -> int:
	return _icons.size()


func wasted_count() -> int:
	return _wasted.count(1)


## How many casts the cycle has, and which one is marked as next.
func cast_count() -> int:
	return _cast_size.size()


func next_cast() -> int:
	return clampi(_cursor, 0, maxi(_cast_size.size() - 1, 0))


## The share of the delay still to run, 1 just after a cast and 0 when ready.
func cooldown_fill() -> float:
	return clampf(_left / _total, 0.0, 1.0) if _total > 0.0 else 0.0


func is_recharging() -> bool:
	return _recharging and _left > 0.0


## How many cards fit, and the "+N" text for the rest ("" when all fit).
func shown_count() -> int:
	return _shown


func plus_text() -> String:
	return _plus_text


func _cards_left() -> float:
	return GLYPH_CELL if _glyph == null else maxf(GLYPH_CELL, _glyph.custom_minimum_size.x + 2.0)


## How many cards fit in the row's width (frames and gaps counted), leaving room for "+N".
func _measure() -> void:
	var limit: float = size.x
	var x: float = _cards_left()
	var shown: int = 0
	var total: int = _icons.size()
	for c in _cast_size.size():
		x += 1.0
		for i in _cast_size[c]:
			var room: float = limit - (PLUS_WIDTH if shown + 1 < total else 0.0)
			if x + ICON_STEP + 1.0 > room:
				_set_shown(shown, total)
				return
			x += ICON_STEP
			shown += 1
		x += CAST_GAP
	_set_shown(shown, total)


func _set_shown(shown: int, total: int) -> void:
	_shown = shown
	_plus_text = "" if shown >= total else "+%d" % (total - shown)
	queue_redraw()


func _draw() -> void:
	var next: int = next_cast()
	var recharging: bool = is_recharging()
	var x: float = _cards_left()
	var start: float = x
	var next_hidden: bool = next < _cast_first.size() and _cast_first[next] >= _shown
	for c in _cast_size.size():
		var first: int = _cast_first[c]
		var count: int = mini(_cast_size[c], _shown - first)
		if count <= 0:
			continue
		var is_next: bool = c == next
		var box := Rect2(x, 0.0, count * ICON_STEP + 1.0, BOX_HEIGHT)
		draw_rect(box, NEXT_FILL if is_next else FILL)
		for i in count:
			var at := Rect2(x + 1.0 + i * ICON_STEP, 1.0, ICON, ICON)
			var wasted: bool = _wasted[first + i] == 1
			var tint: Color = Color.WHITE
			if wasted:
				tint = WASTE_TINT
			elif recharging:
				tint = RECHARGE_TINT
			elif not is_next:
				tint = OTHER_TINT
			var icon: Texture2D = _icons[first + i]
			if icon != null:
				draw_texture_rect(icon, at, false, tint)
			else:
				draw_rect(at.grow(-1.0), PLACEHOLDER * tint)
			if wasted:
				draw_line(at.position + Vector2(0.0, ICON), at.position + Vector2(ICON, 0.0), STRIKE, 1.0)
		draw_rect(box, GOLD if is_next and not recharging else FRAME, false, 1.0)
		x += box.size.x + CAST_GAP
	if _plus_text != "":
		var font: Font = get_theme_default_font()
		var color: Color = GOLD if next_hidden else MUTED
		draw_string(font, Vector2(x, BOX_HEIGHT - 2.0), _plus_text, HORIZONTAL_ALIGNMENT_LEFT, -1, PLUS_FONT_SIZE, color)
	# The bar runs the row's whole width, so the four staffs' delays compare at a glance.
	_draw_bar(start, maxf(size.x, start + ICON_STEP), recharging)


func _draw_bar(from: float, to: float, recharging: bool) -> void:
	var width: float = to - from
	draw_rect(Rect2(from, BAR_Y, width, BAR_HEIGHT), BAR_BACK)
	var fill: float = floorf(width * cooldown_fill())
	if fill <= 0.0:
		return
	if not recharging:
		draw_rect(Rect2(from, BAR_Y, fill, BAR_HEIGHT), BAR_DELAY)
		return
	var x: float = from
	while x < from + fill:
		draw_rect(Rect2(x, BAR_Y, minf(DASH, from + fill - x), BAR_HEIGHT), BAR_RECHARGE)
		x += DASH * 2.0
