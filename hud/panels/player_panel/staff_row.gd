extends Control
## One staff's row under the corner panel's mana bar (owner, 2026-10-27): the staff's button
## glyph, then its cast sequence as small card icons in read order, one framed group per cast of
## the cycle, so a player sees which cards fire together and finds a card that does nothing.
##
## - The cast the staff fires next has a gold frame and full-bright icons; the other casts are
##   dimmer, so the highlight is told by brightness too, not by colour alone.
## - A wasted card (the compiler's `wasted` for that cast) is greyed and struck through.
## - The staff's delay shows one of two ways, `style` (the pause menu's Sandbox page switches it
##   for every row; owner, 2026-10-27, mockup https://claude.ai/artifact/V9Zy2uXqFbmKFATM5mhzMC):
##   - `BUTTON` (the default): the button glyph is the timer. A shade covers it after a cast and
##     pulls back up as the delay runs, so the four glyphs, one above the other, say at a glance
##     which staffs are ready. The shade's edge is cyan for a delay and orange for the recharge
##     after the last cast, when the next cast's gold frame is dashed too (a recharge reads apart
##     by shape as well as colour). The cards are never dimmed by timing.
##   - `NEXT_CAST`: the cast that fires next loads. A shade over its icons pulls back left to
##     right; during the recharge it covers the whole sequence, with an orange edge and no gold
##     frame. The glyph greys while the staff is not ready.
##   Either way the glyph gets a white rim for a few frames when the staff is ready again.
## - A staff longer than the row shows "+N" for the cards that do not fit (gold when the next
##   cast is among them).
##
## Display only: no input, no focus. `set_plan` takes the plain `Spells.staff_view` and an icon
## per card (it allocates, once per plan); `set_timing` takes the cursor and the seconds left each
## frame and only redraws when they changed (or the ready rim is counting down), allocating
## nothing.

const GlyphScript := preload("res://hud/widgets/action_glyph.gd")

const ICON: float = 8.0
## One icon plus the 1 px between two icons.
const ICON_STEP: float = 9.0
const BOX_HEIGHT: float = 10.0
## The frames plus 2 px of air, so a row's frames never touch the next row's.
const ROW_HEIGHT: float = 12.0
## Between two casts' frames.
const CAST_GAP: float = 2.0
## The glyph cell (the shoulder glyphs are 12 px; a wider key pushes the cards right).
const GLYPH_CELL: float = 14.0
const PLUS_FONT_SIZE: int = 8
## Room kept for "+N" when cards are left over.
const PLUS_WIDTH: float = 13.0
## How many frames (`set_timing` calls) the white rim stays on a glyph whose staff became ready.
const RIM_FRAMES: int = 7

## How the staff's delay shows (see the top).
enum Style { BUTTON, NEXT_CAST }

const FRAME: Color = Color("#4a4663")
const FILL: Color = Color(0.11, 0.1, 0.16, 0.85)
const NEXT_FILL: Color = Color(0.24, 0.21, 0.12, 0.95)
const GOLD: Color = Color("#f2c230")
const MUTED: Color = Color("#a39fb8")
const WASTE_TINT: Color = Color(0.45, 0.45, 0.5, 0.55)
const STRIKE: Color = Color("#e0592f")
const OTHER_TINT: Color = Color(0.72, 0.72, 0.78, 1.0)
const SHADE: Color = Color(0.04, 0.03, 0.07, 0.74)
const EDGE_DELAY: Color = Color("#7fd6f5")
const EDGE_RECHARGE: Color = Color("#f08a3c")
const RIM: Color = Color.WHITE
const GLYPH_DIM: Color = Color(0.5, 0.5, 0.58, 1.0)
const PLACEHOLDER: Color = Color("#7a7694")

## The player index 0-3 and the staff 0-3, set before adding the node.
var player: int = 0
var staff: int = 0
## Where the cards start, set by the panel to the widest glyph of its rows so every row's cards
## line up whatever its button is called (owner, 2026-10-27). 0 leaves it to this row's glyph.
var cards_left: float = 0.0:
	set(value):
		if not is_equal_approx(value, cards_left):
			cards_left = value
			_measure()
## How the delay shows; `BUTTON` by default (owner, 2026-10-27).
var style: Style = Style.BUTTON:
	set(value):
		if value != style:
			style = value
			_redraw_all()

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
## Drawn over the glyph (its shade and its rim), since a child draws over its parent's `_draw`.
var _cover: Control = null
## Frames left of the white rim.
var _rim_frames: int = 0
## What the last draw showed (for tests): the cast with the solid gold outline and the one with
## the dashed one (-1 for none), and the shade with its edge (empty for none).
var _drawn_outline: int = -1
var _drawn_dashed: int = -1
var _drawn_shade: Rect2 = Rect2()


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
	_cover = Control.new()
	_cover.name = "Cover"
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.draw.connect(_draw_cover)
	add_child(_cover)
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
	_rim_frames = 0
	_measure()
	_redraw_all()


## The staff's next cast and its delay left, from `Spells.cast_index` and `cooldown_left`. A
## rise in the delay is a cast: the bar starts full from there, and it is a recharge when the
## cycle started over (the cursor is back at 0). It redraws whenever anything it shows changed,
## compared exactly: a delay counted down in float steps can end on a sliver (1e-7 s) for one
## frame, and the step from that sliver to 0 is the one that ends the recharge look. Reaching 0
## starts the white rim, which this call counts down a frame at a time.
func set_timing(cursor: int, left: float) -> void:
	left = maxf(left, 0.0)
	var was_recharging: bool = is_recharging()
	var was_waiting: bool = _left > 0.0
	if left > _left + 0.0001:
		_total = left
		_recharging = cursor == 0
	if left <= 0.0:
		_recharging = false
	var changed: bool = cursor != _cursor or left != _left
	_cursor = cursor
	_left = left
	if _rim_frames > 0:
		_rim_frames -= 1
		changed = changed or _rim_frames == 0
	if was_waiting and left <= 0.0:
		_rim_frames = RIM_FRAMES
	if changed or is_recharging() != was_recharging:
		_redraw_all()


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


## The cast that had the gold outline when the row was last drawn, -1 for none (for tests: it is
## what the player saw, not what the row knows). The dashed outline of a recharge (`BUTTON`) is
## `drawn_dashed`.
func drawn_outline() -> int:
	return _drawn_outline


func drawn_dashed() -> int:
	return _drawn_dashed


## The shade at the last draw, in the row's coordinates (empty for none): over the glyph for
## `BUTTON`, over the cards for `NEXT_CAST`.
func drawn_shade() -> Rect2:
	return _drawn_shade


## Whether the glyph has the white rim of a staff that just became ready.
func is_rimmed() -> bool:
	return _rim_frames > 0


## Where this row's first card starts (for tests): the same in every row of a panel.
func cards_start() -> float:
	return _cards_left()


## How many cards fit, and the "+N" text for the rest ("" when all fit).
func shown_count() -> int:
	return _shown


func plus_text() -> String:
	return _plus_text


## The room this row's own glyph needs before the cards.
func glyph_room() -> float:
	return GLYPH_CELL if _glyph == null else maxf(GLYPH_CELL, _glyph.custom_minimum_size.x + 2.0)


func _cards_left() -> float:
	return maxf(glyph_room(), cards_left)


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
	var on_button: bool = style == Style.BUTTON
	_drawn_outline = -1
	_drawn_dashed = -1
	var x: float = _cards_left()
	var next_hidden: bool = next < _cast_first.size() and _cast_first[next] >= _shown
	# The insides of the next cast's frame and of every frame, for the `NEXT_CAST` shade.
	var next_inside := Rect2()
	var all_inside := Rect2()
	for c in _cast_size.size():
		var first: int = _cast_first[c]
		var count: int = mini(_cast_size[c], _shown - first)
		if count <= 0:
			continue
		var is_next: bool = c == next
		# A recharge keeps the next cast marked on the button style (dashed), and drops the mark
		# on the next-cast style (the shade covers the whole cycle).
		var marked: bool = is_next and (on_button or not recharging)
		var box := Rect2(x, 0.0, count * ICON_STEP + 1.0, BOX_HEIGHT)
		draw_rect(box, NEXT_FILL if marked else FILL)
		for i in count:
			var at := Rect2(x + 1.0 + i * ICON_STEP, 1.0, ICON, ICON)
			var wasted: bool = _wasted[first + i] == 1
			var tint: Color = Color.WHITE
			if wasted:
				tint = WASTE_TINT
			elif not is_next:
				tint = OTHER_TINT
			var icon: Texture2D = _icons[first + i]
			if icon != null:
				draw_texture_rect(icon, at, false, tint)
			else:
				draw_rect(at.grow(-1.0), PLACEHOLDER * tint)
			if wasted:
				draw_line(at.position + Vector2(0.0, ICON), at.position + Vector2(ICON, 0.0), STRIKE, 1.0)
		if marked and recharging:
			_draw_dashed(box, GOLD)
			_drawn_dashed = c
		else:
			draw_rect(box, GOLD if marked else FRAME, false, 1.0)
			if marked:
				_drawn_outline = c
		var inside := box.grow(-1.0)
		if is_next:
			next_inside = inside
		all_inside = inside if all_inside.size.x <= 0.0 else all_inside.merge(inside)
		x += box.size.x + CAST_GAP
	if _plus_text != "":
		var font: Font = get_theme_default_font()
		var color: Color = GOLD if next_hidden else MUTED
		draw_string(font, Vector2(x, BOX_HEIGHT - 2.0), _plus_text, HORIZONTAL_ALIGNMENT_LEFT, -1, PLUS_FONT_SIZE, color)
	if not on_button:
		_drawn_shade = Rect2()
		var fill: float = cooldown_fill()
		var under: Rect2 = all_inside if recharging else next_inside
		if fill > 0.0 and under.size.x > 0.0:
			# Pulls back left to right: what is still to wait is on the right.
			var width: float = maxf(1.0, floorf(under.size.x * fill))
			_drawn_shade = Rect2(under.end.x - width, under.position.y, width, under.size.y)
			draw_rect(_drawn_shade, SHADE)
			draw_rect(Rect2(_drawn_shade.position, Vector2(1.0, _drawn_shade.size.y)), EDGE_RECHARGE if recharging else EDGE_DELAY)


## Over the glyph: the `BUTTON` shade, which pulls back up as the delay runs (what is still to
## wait is on top, its last line the edge), and the white rim of a staff that just became ready.
func _draw_cover() -> void:
	var cap := Rect2(0.0, 0.0, _glyph.custom_minimum_size.x, GlyphScript.GLYPH_HEIGHT)
	if style == Style.BUTTON:
		_drawn_shade = Rect2()
		var fill: float = cooldown_fill()
		if fill > 0.0:
			var inside: Rect2 = cap.grow(-1.0)
			var height: float = maxf(1.0, ceilf(inside.size.y * fill))
			_drawn_shade = Rect2(inside.position, Vector2(inside.size.x, height))
			_cover.draw_rect(_drawn_shade, SHADE)
			var edge := Rect2(inside.position.x, _drawn_shade.end.y - 1.0, inside.size.x, 1.0)
			_cover.draw_rect(edge, EDGE_RECHARGE if is_recharging() else EDGE_DELAY)
	if _rim_frames > 0:
		_cover.draw_rect(cap, RIM, false, 1.0)


func _draw_dashed(box: Rect2, color: Color) -> void:
	var x: float = box.position.x
	while x < box.end.x:
		draw_rect(Rect2(x, box.position.y, 1.0, 1.0), color)
		draw_rect(Rect2(x, box.end.y - 1.0, 1.0, 1.0), color)
		x += 2.0
	var y: float = box.position.y
	while y < box.end.y:
		draw_rect(Rect2(box.position.x, y, 1.0, 1.0), color)
		draw_rect(Rect2(box.end.x - 1.0, y, 1.0, 1.0), color)
		y += 2.0


## Redraw the cards and the cover, and grey the glyph while a `NEXT_CAST` staff is not ready.
func _redraw_all() -> void:
	queue_redraw()
	if _cover != null:
		_cover.queue_redraw()
	if _glyph != null:
		var dim: bool = style == Style.NEXT_CAST and _left > 0.0
		_glyph.modulate = GLYPH_DIM if dim else Color.WHITE
