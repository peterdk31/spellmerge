extends Control
## One staff's row of the corner panel (owner, 2026-10-27): the staff's button glyph, then its
## cast sequence as small card icons in read order, one framed group per cast of the cycle, so a
## player sees which cards fire together and finds a card that does nothing, and under the cards
## a thin blue line of the staff's own mana (owner, 2026-11-19; `set_mana`, `meter_line.gd`).
##
## - The cast the staff fires next has a gold frame and full-bright icons; the other casts are
##   dimmer, so the highlight is told by brightness too, not by colour alone.
## - A wasted card (the compiler's `wasted` for that cast) is greyed and struck through.
## - The staff's delay shows one of two ways, `style` (the pause menu's Settings page switches it
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
## - A cast that winds up (docs/milestones/cast-timing.md) charges: on the glyph a shade grows up
##   from the bottom with a gold edge (`BUTTON`), or over the cast from the left (`NEXT_CAST`),
##   so a wind-up reads apart from a wait by its direction as well as its colour.
## - The gold frame is on the cast a press would fire with the staff's mana: casts before it that
##   the mana does not pay are skipped (cast-timing T3) and have a red frame, as has every cast
##   left in the cycle when the mana pays none. A press that found none (a fizzle) gives the
##   glyph a red rim for a few frames.
## - A staff longer than the row scrolls (owner, 2026-11-19): the cards are drawn in a strip
##   clipped to the row, which slides by whole pixels to keep the cast the staff fires next in
##   view, with a card of the one before it showing. It slides a third of the way each frame
##   (`set_timing`'s), so a move never jumps (docs/STYLE.md, "Smooth"), and a small arrow at
##   either end says cards are hidden that way (gold when the next cast is among them, which only
##   happens while it slides, or when the next cast is wider than the strip); an arrow slides in
##   from past its end over ARROW_FRAMES frames, and out again. A new plan or a new width starts the strip where it should be.
## - The mana line is the staff's whole mana of its pool (`staff_mana_changed`); it hides until
##   the staff's mana is told, and eases by whole pixels as the line does.
##
## Display only: no input, no focus. `set_plan` takes the plain `Spells.staff_view` and an icon
## per card (it allocates, once per plan); `set_timing` takes the cursor and the seconds left each
## frame and only redraws when they changed (or the ready rim is counting down, or the strip
## slides), allocating nothing.

const GlyphScript := preload("res://hud/widgets/action_glyph.gd")
const MeterScript := preload("res://hud/widgets/meter_line.gd")

const ICON: float = 8.0
## One icon plus the 1 px between two icons.
const ICON_STEP: float = 9.0
const BOX_HEIGHT: float = 10.0
## The mana line under the frames: 1 px of air above it, 2 px of line.
const MANA_GAP: float = 1.0
const MANA_HEIGHT: float = 2.0
## The frames, the mana line and 1 px of air, so a row never touches the next row.
const ROW_HEIGHT: float = BOX_HEIGHT + MANA_GAP + MANA_HEIGHT + 1.0
## Between two casts' frames.
const CAST_GAP: float = 2.0
## The glyph cell (the shoulder glyphs are 12 px; a wider key pushes the cards right).
const GLYPH_CELL: float = 14.0
## The arrow at an end of a strip with cards hidden that way: its width with its dark backing.
const ARROW_WIDTH: float = 4.0
## Frames an arrow takes to slide in from its end of the strip, or back out (docs/STYLE.md, "Smooth").
const ARROW_FRAMES: int = 3
## How much of the cards before the next cast stays in view: one card, and the arrow over it.
const LEAD: float = ICON_STEP
## How many frames (`set_timing` calls) the white rim stays on a glyph whose staff became ready.
const RIM_FRAMES: int = 7

## How the staff's delay shows (see the top).
enum Style { BUTTON, NEXT_CAST }
## `set_timing`'s `firing` when the row is not told what the mana pays.
const FIRING_UNKNOWN: int = -2

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
## The edge of a wind-up's charge, a frame the mana does not pay, and a fizzle's rim.
const EDGE_WIND: Color = Color("#f2c230")
const SHORT: Color = Color("#d8443a")
const SHORT_TINT: Color = Color(0.6, 0.5, 0.55, 0.8)
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
## Per cast: where its frame starts in the strip, before the scroll; and the strip's whole width.
var _cast_x: PackedFloat32Array = PackedFloat32Array()
var _content_width: float = 0.0
## How far the strip is scrolled, in whole pixels, and where it slides to.
var _scroll: int = 0
var _scroll_target: int = 0
## How far each end's arrow has slid in, 0 (out) to ARROW_FRAMES (in).
var _left_in: int = 0
var _right_in: int = 0
## The cast fired next (`Spells.cast_index`), the delay left and the delay it started from.
var _cursor: int = 0
var _left: float = 0.0
var _total: float = 0.0
var _recharging: bool = false
## True while the staff winds up a cast (`Spells.is_winding`).
var _winding: bool = false
## The cast a press would fire with the staff's mana (`Spells.firing_cast`): -1 when the mana
## pays none left in the cycle, FIRING_UNKNOWN when no mana was given (then the cursor's).
var _firing: int = FIRING_UNKNOWN
## Frames left of the red rim of a fizzle.
var _fizzle_frames: int = 0
var _glyph: GlyphScript = null
## The cards, clipped to the row right of the glyph, and the mana line under them.
var _strip: Control = null
var _mana: MeterScript = null
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
	_strip = Control.new()
	_strip.name = "Strip"
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.clip_contents = true
	_strip.draw.connect(_draw_cards)
	add_child(_strip)
	_mana = MeterScript.new()
	_mana.name = "Mana"
	_mana.fill_color = MeterScript.MANA_COLOR
	_mana.visible = false
	add_child(_mana)
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
	_cast_x.clear()
	var x: float = 0.0
	for c in _cast_size.size():
		_cast_x.append(x)
		x += _cast_size[c] * ICON_STEP + 1.0 + CAST_GAP
	_content_width = maxf(x - CAST_GAP, 0.0)
	_cursor = 0
	_left = 0.0
	_total = 0.0
	_recharging = false
	_winding = false
	_firing = FIRING_UNKNOWN
	_fizzle_frames = 0
	_rim_frames = 0
	_measure()
	_redraw_all()


## The staff's next cast and its delay left, from `Spells.cast_index` and `cooldown_left`. A
## rise in the delay is a cast: the bar starts full from there, and it is a recharge when the
## cycle started over (the cursor is back at 0). It redraws whenever anything it shows changed,
## compared exactly: a delay counted down in float steps can end on a sliver (1e-7 s) for one
## frame, and the step from that sliver to 0 is the one that ends the recharge look. Reaching 0
## starts the white rim, which this call counts down a frame at a time.
##
## `winding`: the staff winds up a cast (`Spells.is_winding`; the seconds left are its wind-up's).
## `firing`: the cast a press would fire with the staff's mana (`Spells.firing_cast`, -1 for none).
func set_timing(cursor: int, left: float, winding: bool = false, firing: int = FIRING_UNKNOWN) -> void:
	left = maxf(left, 0.0)
	var was_recharging: bool = is_recharging()
	var was_waiting: bool = _left > 0.0
	if left > _left + 0.0001 or winding != _winding:
		_total = left
		_recharging = cursor == 0 and not winding
	if left <= 0.0:
		_recharging = false
	var changed: bool = cursor != _cursor or left != _left or winding != _winding or firing != _firing
	_cursor = cursor
	_left = left
	_winding = winding
	_firing = firing
	if _rim_frames > 0:
		_rim_frames -= 1
		changed = changed or _rim_frames == 0
	if _fizzle_frames > 0:
		_fizzle_frames -= 1
		changed = changed or _fizzle_frames == 0
	if was_waiting and left <= 0.0:
		_rim_frames = RIM_FRAMES
	_scroll_target = _wanted_scroll()
	if _step_scroll():
		changed = true
	if _step_arrows():
		changed = true
	if changed or is_recharging() != was_recharging:
		_redraw_all()


## Show the staff's whole mana `mana` of its pool `most` on the line under the cards; a mana not
## told (not finite) hides the line until it is.
func set_mana(mana: float, most: float) -> void:
	if _mana == null:
		return
	var known: bool = is_finite(mana) and most > 0.0
	if not known:
		_mana.reset()
		_mana.visible = false
		return
	_mana.visible = true
	_mana.set_value(mana, most)


## The mana line (for tests and screenshots).
func mana_line() -> MeterScript:
	return _mana


## The cards shown in read order (for tests): how many, and how many are greyed.
func card_count() -> int:
	return _icons.size()


func wasted_count() -> int:
	return _wasted.count(1)


## How many casts the cycle has, and which one is marked as next.
func cast_count() -> int:
	return _cast_size.size()


func next_cast() -> int:
	var at: int = _firing if _firing >= 0 else _cursor
	return clampi(at, 0, maxi(_cast_size.size() - 1, 0))


## True when the mana does not pay cast `c` of the cycle and a press would skip it: a cast from the
## cursor up to the one that fires, or every one left when none does.
func is_short(c: int) -> bool:
	if _firing == FIRING_UNKNOWN or c < _cursor:
		return false
	return _firing < 0 or c < _firing


## A press found no cast its mana pays (`cast_fizzled`): a red rim on the glyph for a few frames.
func fizzle() -> void:
	_fizzle_frames = RIM_FRAMES
	_redraw_all()


func is_fizzling() -> bool:
	return _fizzle_frames > 0


func is_winding() -> bool:
	return _winding and _left > 0.0


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


## How far the strip is scrolled and where it slides to, in pixels (0: the first cast at the
## start).
func scroll() -> int:
	return _scroll


func scroll_target() -> int:
	return _scroll_target


## The strip's width: the room right of the glyph the cards show in.
func view_width() -> float:
	return _strip.size.x if _strip != null else 0.0


## Whether cards are hidden left of the strip, or right of it.
func hides_left() -> bool:
	return _scroll > 0


func hides_right() -> bool:
	return _content_width - float(_scroll) > view_width() + 0.5


## Whether cast `c`'s whole frame is in the strip now.
func is_cast_in_view(c: int) -> bool:
	if c < 0 or c >= _cast_x.size():
		return false
	var start: float = _cast_x[c] - float(_scroll)
	return start >= 0.0 and start + _cast_size[c] * ICON_STEP + 1.0 <= view_width() + 0.5


## The room this row's own glyph needs before the cards.
func glyph_room() -> float:
	return GLYPH_CELL if _glyph == null else maxf(GLYPH_CELL, _glyph.custom_minimum_size.x + 2.0)


func _cards_left() -> float:
	return maxf(glyph_room(), cards_left)


## Lay the strip and the mana line out right of the glyph, and start the strip where it should be
## for this width (a new width is a new layout, not a move).
func _measure() -> void:
	if _strip == null:
		return
	var left: float = _cards_left()
	var width: float = maxf(size.x - left, 0.0)
	_strip.position = Vector2(left, 0.0)
	_strip.size = Vector2(width, BOX_HEIGHT)
	_mana.position = Vector2(left, BOX_HEIGHT + MANA_GAP)
	_mana.size = Vector2(width, MANA_HEIGHT)
	_scroll_target = _wanted_scroll()
	_scroll = _scroll_target
	_left_in = ARROW_FRAMES if hides_left() else 0
	_right_in = ARROW_FRAMES if hides_right() else 0
	_redraw_all()


## One frame of each arrow's slide toward in (cards hidden that way) or out; true when one moved.
func _step_arrows() -> bool:
	var left: int = clampi(_left_in + (1 if hides_left() else -1), 0, ARROW_FRAMES)
	var right: int = clampi(_right_in + (1 if hides_right() else -1), 0, ARROW_FRAMES)
	var moved: bool = left != _left_in or right != _right_in
	_left_in = left
	_right_in = right
	return moved


## How far an arrow has slid in, 0 to ARROW_FRAMES: the left one (`way` -1) or the right (for
## tests).
func arrow_in(way: int) -> int:
	return _left_in if way < 0 else _right_in


## Where the strip should be: the next cast's frame in view with LEAD of the cards before it and
## clear of the arrows, never past either end; 0 when everything fits.
func _wanted_scroll() -> int:
	var view: float = view_width()
	if _content_width <= view or _cast_x.is_empty():
		return 0
	var c: int = next_cast()
	var start: float = _cast_x[c]
	var end: float = start + _cast_size[c] * ICON_STEP + 1.0
	var at: float = start - LEAD
	if end - at > view - ARROW_WIDTH:
		at = end - view + ARROW_WIDTH
	if at > start - ARROW_WIDTH:
		# A cast wider than the strip: its start shows.
		at = start - ARROW_WIDTH
	return clampi(floori(at), 0, ceili(_content_width - view))


## One frame of the strip's slide to its target, a third of the way (at least a pixel); true when
## it moved.
func _step_scroll() -> bool:
	var gap: int = _scroll_target - _scroll
	if gap == 0:
		return false
	_scroll += mini(maxi(1, ceili(absi(gap) / 3.0)), absi(gap)) * signi(gap)
	return true


## The cards, in the strip (its own coordinates; the strip clips what is past its ends): each
## cast's frame from its place less the scroll, the arrows over the ends that hide cards, and the
## `NEXT_CAST` shade. What the tests read (`drawn_shade`) is kept in the row's coordinates.
func _draw_cards() -> void:
	var next: int = next_cast()
	var recharging: bool = is_recharging()
	var on_button: bool = style == Style.BUTTON
	var view: float = _strip.size.x
	_drawn_outline = -1
	_drawn_dashed = -1
	# The insides of the next cast's frame and of every frame, for the `NEXT_CAST` shade.
	var next_inside := Rect2()
	var all_inside := Rect2()
	for c in _cast_size.size():
		var first: int = _cast_first[c]
		var count: int = _cast_size[c]
		var x: float = _cast_x[c] - float(_scroll)
		var box := Rect2(x, 0.0, count * ICON_STEP + 1.0, BOX_HEIGHT)
		if box.end.x <= 0.0 or box.position.x >= view:
			continue
		var is_next: bool = c == next and _firing != -1
		var short: bool = is_short(c)
		# A recharge keeps the next cast marked on the button style (dashed), and drops the mark
		# on the next-cast style (the shade covers the whole cycle).
		var marked: bool = is_next and (on_button or not recharging)
		_strip.draw_rect(box, NEXT_FILL if marked else FILL)
		for i in count:
			var at := Rect2(x + 1.0 + i * ICON_STEP, 1.0, ICON, ICON)
			var wasted: bool = _wasted[first + i] == 1
			var tint: Color = Color.WHITE
			if wasted:
				tint = WASTE_TINT
			elif short:
				tint = SHORT_TINT
			elif not is_next:
				tint = OTHER_TINT
			var icon: Texture2D = _icons[first + i]
			if icon != null:
				_strip.draw_texture_rect(icon, at, false, tint)
			else:
				_strip.draw_rect(at.grow(-1.0), PLACEHOLDER * tint)
			if wasted:
				_strip.draw_line(at.position + Vector2(0.0, ICON), at.position + Vector2(ICON, 0.0), STRIKE, 1.0)
		if marked and recharging:
			_draw_dashed(box, GOLD)
			_drawn_dashed = c
		else:
			_strip.draw_rect(box, GOLD if marked else (SHORT if short else FRAME), false, 1.0)
			if marked:
				_drawn_outline = c
		var inside := box.grow(-1.0)
		if is_next:
			next_inside = inside
		all_inside = inside if all_inside.size.x <= 0.0 else all_inside.merge(inside)
	if not on_button:
		_drawn_shade = Rect2()
		var fill: float = cooldown_fill()
		var under: Rect2 = all_inside if recharging else next_inside
		var shade := Rect2()
		if is_winding() and under.size.x > 0.0:
			# A wind-up charges from the left: what has wound up is shaded, its edge gold.
			var charged: float = maxf(1.0, floorf(under.size.x * (1.0 - fill)))
			shade = Rect2(under.position, Vector2(charged, under.size.y))
			_strip.draw_rect(shade, SHADE)
			_strip.draw_rect(Rect2(shade.end.x - 1.0, under.position.y, 1.0, under.size.y), EDGE_WIND)
		elif fill > 0.0 and under.size.x > 0.0:
			# Pulls back left to right: what is still to wait is on the right.
			var width: float = maxf(1.0, floorf(under.size.x * fill))
			shade = Rect2(under.end.x - width, under.position.y, width, under.size.y)
			_strip.draw_rect(shade, SHADE)
			_strip.draw_rect(Rect2(shade.position, Vector2(1.0, shade.size.y)), EDGE_RECHARGE if recharging else EDGE_DELAY)
		if shade.size.x > 0.0:
			_drawn_shade = Rect2(shade.position + _strip.position, shade.size)
	var next_left: bool = next < _cast_x.size() and _cast_x[next] - float(_scroll) < 0.0
	var next_right: bool = next < _cast_x.size() and not next_left and not is_cast_in_view(next)
	# An arrow slides in from past its end, a pixel or two a frame, never popping in whole.
	if _left_in > 0:
		_draw_arrow(-_arrow_out(_left_in), -1, GOLD if next_left else MUTED)
	if _right_in > 0:
		_draw_arrow(view - ARROW_WIDTH + _arrow_out(_right_in), 1, GOLD if next_right else MUTED)


## How far past its end an arrow `slid` frames in is still, in whole pixels.
func _arrow_out(slid: int) -> float:
	return floorf(ARROW_WIDTH * float(ARROW_FRAMES - slid) / float(ARROW_FRAMES))


## A small arrow at `x` of the strip pointing `way` (-1 left, 1 right), on a dark backing over the
## cards it hides: 3 px wide, its columns 2, 4 and 6 px tall from the tip.
func _draw_arrow(x: float, way: int, color: Color) -> void:
	_strip.draw_rect(Rect2(x, 0.0, ARROW_WIDTH, BOX_HEIGHT), FILL)
	for step in 3:
		# The tip is the column furthest out; each column inward is 2 px taller.
		var column: float = x + (float(step) if way < 0 else ARROW_WIDTH - 1.0 - float(step))
		var half: float = float(step)
		_strip.draw_rect(Rect2(column, BOX_HEIGHT * 0.5 - 1.0 - half, 1.0, 2.0 + half * 2.0), color)


## Over the glyph: the `BUTTON` shade, which pulls back up as the delay runs (what is still to
## wait is on top, its last line the edge), and the white rim of a staff that just became ready.
func _draw_cover() -> void:
	var cap := Rect2(0.0, 0.0, _glyph.custom_minimum_size.x, GlyphScript.GLYPH_HEIGHT)
	if style == Style.BUTTON:
		_drawn_shade = Rect2()
		var fill: float = cooldown_fill()
		if is_winding():
			# A wind-up charges up from the bottom, its edge gold.
			var low: Rect2 = cap.grow(-1.0)
			var risen: float = maxf(1.0, ceilf(low.size.y * (1.0 - fill)))
			_drawn_shade = Rect2(low.position.x, low.end.y - risen, low.size.x, risen)
			_cover.draw_rect(_drawn_shade, SHADE)
			_cover.draw_rect(Rect2(low.position.x, _drawn_shade.position.y, low.size.x, 1.0), EDGE_WIND)
		elif fill > 0.0:
			var inside: Rect2 = cap.grow(-1.0)
			var height: float = maxf(1.0, ceilf(inside.size.y * fill))
			_drawn_shade = Rect2(inside.position, Vector2(inside.size.x, height))
			_cover.draw_rect(_drawn_shade, SHADE)
			var edge := Rect2(inside.position.x, _drawn_shade.end.y - 1.0, inside.size.x, 1.0)
			_cover.draw_rect(edge, EDGE_RECHARGE if is_recharging() else EDGE_DELAY)
	if _fizzle_frames > 0:
		_cover.draw_rect(cap, SHORT, false, 1.0)
	elif _rim_frames > 0:
		_cover.draw_rect(cap, RIM, false, 1.0)


func _draw_dashed(box: Rect2, color: Color) -> void:
	var x: float = box.position.x
	while x < box.end.x:
		_strip.draw_rect(Rect2(x, box.position.y, 1.0, 1.0), color)
		_strip.draw_rect(Rect2(x, box.end.y - 1.0, 1.0, 1.0), color)
		x += 2.0
	var y: float = box.position.y
	while y < box.end.y:
		_strip.draw_rect(Rect2(box.position.x, y, 1.0, 1.0), color)
		_strip.draw_rect(Rect2(box.end.x - 1.0, y, 1.0, 1.0), color)
		y += 2.0


## Redraw the cards and the cover, and grey the glyph while a `NEXT_CAST` staff is not ready.
func _redraw_all() -> void:
	if _strip != null:
		_strip.queue_redraw()
	if _cover != null:
		_cover.queue_redraw()
	if _glyph != null:
		var dim: bool = style == Style.NEXT_CAST and _left > 0.0
		_glyph.modulate = GLYPH_DIM if dim else Color.WHITE
