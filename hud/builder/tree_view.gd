extends Control
## The radial builder's tree view (owner, 2026-10-31, docs/milestones/M2-builder-tree.md, part
## T5): Y swaps the ring for a tree of the shown staff's whole cycle, in the ring's place. A
## header, then one row per carrier and one per trigger (19 px each), from the plain rows
## `Spells.staff_view` gives each cast (`tree`):
##
## - a carrier row: on a cast's first row the cast number ("#1"), the carrier's own cards as
##   16 px tiles (the slots' tiles: icon and kind bar), its name in the carrier colour, and on
##   a cast's first row that cast's mana share and damage on the right;
## - a trigger row, indented 12 px a payload level with a branch line from its parent: the
##   trigger's tile, a small arrow, the tiles of the first carrier it fires and the trigger
##   card's name in the trigger colour. A payload's further carriers are rows of their own.
##
## The row holding the marked slot is banded and that card's tile gets the gold marker frame;
## moving the marker scrolls its row into view. A tree taller than its space scrolls (`scroll_by`:
## the right stick, P1's mouse wheel), with a 2 px bar on its right edge. The timing replay: a
## gold frame steps through the rows, one a `TREE_BEAT`, in the tree's order, and loops. It is
## drawn here in code; nothing is cast. The radial (`radial_builder.gd`) owns it, feeds it the
## shown staff's view and the marked slot, and asks `slot_at` for P1's clicks. Its rows are
## rebuilt only when the staff changes, so drawing allocates nothing new per frame.

const NO_CARD: StringName = &""
const NONE: int = -1

const ROW_HEIGHT: float = 19.0
const HEADER_HEIGHT: float = 11.0
const INDENT: float = 12.0
## The left gutter where a cast's number sits, so every row's indent lines up.
const GUTTER: float = 15.0
const TILE_SIZE: float = 16.0
const TILE_STEP: float = 17.0
const ARROW_WIDTH: float = 7.0
const BAR_WIDTH: float = 2.0
const FONT_SIZE: int = 8
## Seconds a beat of the timing replay lasts (a first guess, owner 2026-10-31).
const TREE_BEAT: float = 0.4
## Pixels a second the right stick scrolls at full tilt, and one notch of the mouse wheel.
const SCROLL_SPEED: float = 160.0
const WHEEL_STEP: float = ROW_HEIGHT
const HEADER_TEXT: String = "Tree"
const EMPTY_TEXT: String = "No casts"

const OUTLINE: Color = Color("#14121f")
const TILE: Color = Color("#2b2840")
const LINE: Color = Color("#4a4663")
const TEXT: Color = Color("#f4f1ea")
const MUTED: Color = Color("#a39fb8")
const DIM: Color = Color("#7a7694")
const GOLD: Color = Color("#f2c230")
const WARN: Color = Color("#e0592f")
const BAND: Color = Color(0.29, 0.275, 0.39, 0.55)

## Set by the radial: the kinds' colours, the spell runtime (icons, kinds).
var kind_colors: Dictionary = {}
var spells: Node = null

## The rows of the shown staff's cycle, each {cast, depth, trigger, slots, name, mana, damage,
## first}: `cast` its cast (0 first), `first` true on a cast's first row; the rest as
## `Spells.cast_tree`, `mana` as a share of the wizard's mana in whole percent.
var _rows: Array[Dictionary] = []
## Per row, the tiles drawn: their slots and their x (from the row's left), the trigger's first.
var _tile_slots: Array[PackedInt32Array] = []
var _tile_x: Array[PackedFloat32Array] = []
## Per row, the x of its first tile and the row it branches from (NONE for none).
var _row_x: PackedFloat32Array = PackedFloat32Array()
var _parent: PackedInt32Array = PackedInt32Array()
## The shown staff's cards by slot, for the tiles' icons and kinds.
var _cards: Array[StringName] = []
var _marked: int = NONE
var _scroll: float = 0.0
var _clock: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


## Show the cycle of a staff view (`Spells.staff_view`), with mana as shares of `max_mana`.
func set_plan(plan: Dictionary, max_mana: float) -> void:
	_rows.clear()
	_cards.assign(plan.get("cards", []))
	var casts: Variant = plan.get("casts", [])
	if casts is Array:
		for c in (casts as Array).size():
			var cast: Variant = (casts as Array)[c]
			if not cast is Dictionary:
				continue
			var tree: Variant = (cast as Dictionary).get("tree", [])
			if not tree is Array:
				continue
			for at in (tree as Array).size():
				var row: Dictionary = (tree as Array)[at]
				_rows.append({
					"cast": c, "first": at == 0, "depth": int(row.get("depth", 0)), "trigger": int(row.get("trigger", NONE)),
					"slots": PackedInt32Array(row.get("slots", PackedInt32Array())), "name": str(row.get("name", "")),
					"mana": roundi(float(row.get("mana", 0.0)) / maxf(max_mana, 1.0) * 100.0), "damage": float(row.get("damage", 0.0)),
				})
	_lay_out()
	_scroll = clampf(_scroll, 0.0, max_scroll())
	_scroll_to_marked()
	queue_redraw()


## The slot the marker is on: its row is banded, its tile framed, and scrolled into view.
func set_marked(slot: int) -> void:
	if slot == _marked:
		return
	_marked = slot
	_scroll_to_marked()
	queue_redraw()


## Back to the top and the replay's start (the tree opens).
func restart() -> void:
	_scroll = 0.0
	_clock = 0.0
	_scroll_to_marked()
	queue_redraw()


## Advance the replay and scroll by the right stick's push (`tilt`, -1 to 1 down).
func step(delta: float, tilt: float) -> void:
	var beat: int = replay_row()
	_clock += delta
	if absf(tilt) > 0.2:
		scroll_by(tilt * SCROLL_SPEED * delta)
	if replay_row() != beat:
		queue_redraw()


## Scroll by `pixels` (down is positive), kept inside the tree.
func scroll_by(pixels: float) -> void:
	var before: float = _scroll
	_scroll = clampf(_scroll + pixels, 0.0, max_scroll())
	if not is_equal_approx(before, _scroll):
		queue_redraw()


## Mouse wheel notches: up scrolls up.
func wheel(notches: int) -> void:
	scroll_by(float(notches) * WHEEL_STEP)


func scroll() -> float:
	return _scroll


## How far the tree scrolls: 0 when it fits.
func max_scroll() -> float:
	return maxf(HEADER_HEIGHT + _rows.size() * ROW_HEIGHT - size.y, 0.0)


## The rows as shown (copies), for tests and the screenshots.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in _rows:
		out.append(row.duplicate())
	return out


## The rows holding the marked slot (a slot read by two casts is in both).
func marked_rows() -> PackedInt32Array:
	var out := PackedInt32Array()
	for at in _rows.size():
		if _row_has(at, _marked):
			out.append(at)
	return out


## The row the replay's gold frame is on, or NONE with no rows.
func replay_row() -> int:
	if _rows.is_empty():
		return NONE
	return int(floorf(_clock / TREE_BEAT)) % _rows.size()


## The slot of the tile at `point` (in this node's parent's space: the view's pixels), or NONE.
func slot_at(point: Vector2) -> int:
	var local: Vector2 = point - position
	if not Rect2(Vector2.ZERO, size).has_point(local):
		return NONE
	for at in _rows.size():
		var top: float = _row_top(at)
		if local.y < top or local.y >= top + ROW_HEIGHT:
			continue
		var slots: PackedInt32Array = _tile_slots[at]
		var xs: PackedFloat32Array = _tile_x[at]
		for tile in slots.size():
			if Rect2(xs[tile], top + 1.0, TILE_SIZE, TILE_SIZE).grow(1.0).has_point(local):
				return slots[tile]
	return NONE


## The middle of the first tile showing `slot`, in the view's pixels (for tests and screenshots),
## or (-1, -1) when none is shown.
func tile_center(slot: int) -> Vector2:
	for at in _rows.size():
		var slots: PackedInt32Array = _tile_slots[at]
		var found: int = slots.find(slot)
		if found >= 0:
			return position + Vector2(_tile_x[at][found], _row_top(at) + 1.0) + Vector2(TILE_SIZE, TILE_SIZE) * 0.5
	return Vector2(-1.0, -1.0)


# --- Layout -----------------------------------------------------------------------------

func _row_top(at: int) -> float:
	return HEADER_HEIGHT + at * ROW_HEIGHT - _scroll


func _row_has(at: int, slot: int) -> bool:
	if slot < 0 or at < 0 or at >= _rows.size():
		return false
	return int(_rows[at]["trigger"]) == slot or (_rows[at]["slots"] as PackedInt32Array).has(slot)


## Where every row's tiles go, and the row each branches from (the nearest row before it one
## level out).
func _lay_out() -> void:
	_tile_slots.clear()
	_tile_x.clear()
	_row_x.resize(_rows.size())
	_parent.resize(_rows.size())
	for at in _rows.size():
		var row: Dictionary = _rows[at]
		var depth: int = row["depth"]
		var x: float = GUTTER + depth * INDENT
		_row_x[at] = x
		_parent[at] = NONE
		if depth > 0:
			for before in range(at - 1, -1, -1):
				if int(_rows[before]["depth"]) == depth - 1 and int(_rows[before]["cast"]) == int(row["cast"]):
					_parent[at] = before
					break
		var slots := PackedInt32Array()
		var xs := PackedFloat32Array()
		if int(row["trigger"]) >= 0:
			slots.append(int(row["trigger"]))
			xs.append(x)
			x += TILE_STEP + ARROW_WIDTH
		for slot: int in row["slots"]:
			slots.append(slot)
			xs.append(x)
			x += TILE_STEP
		_tile_slots.append(slots)
		_tile_x.append(xs)


func _scroll_to_marked() -> void:
	var rows_at: PackedInt32Array = marked_rows()
	if rows_at.is_empty():
		return
	var top: float = HEADER_HEIGHT + rows_at[0] * ROW_HEIGHT
	if top - HEADER_HEIGHT < _scroll:
		_scroll = top - HEADER_HEIGHT
	elif top + ROW_HEIGHT > _scroll + size.y:
		_scroll = top + ROW_HEIGHT - size.y
	_scroll = clampf(_scroll, 0.0, max_scroll())


# --- Drawing ----------------------------------------------------------------------------

func _font() -> Font:
	return get_theme_default_font()


func _text_width(text: String) -> float:
	return _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x


func _text(text: String, at: Vector2, color: Color) -> void:
	var font: Font = _font()
	draw_string(font, Vector2(at.x, at.y + font.get_ascent(FONT_SIZE)).round(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)


func _fit(text: String, width: float) -> String:
	if width <= 0.0:
		return ""
	if _text_width(text) <= width:
		return text
	var cut: String = text
	while cut.length() > 1 and _text_width(cut + "..") > width:
		cut = cut.left(cut.length() - 1)
	return cut + ".."


func _draw() -> void:
	var width: float = size.x - BAR_WIDTH - 2.0
	var replay: int = replay_row()
	for at in _rows.size():
		var top: float = _row_top(at)
		if top + ROW_HEIGHT < HEADER_HEIGHT or top > size.y:
			continue
		var row: Dictionary = _rows[at]
		if _row_has(at, _marked):
			draw_rect(Rect2(0.0, top, width, ROW_HEIGHT), BAND)
		_draw_branch(at, top)
		var slots: PackedInt32Array = _tile_slots[at]
		var xs: PackedFloat32Array = _tile_x[at]
		var trigger: bool = int(row["trigger"]) >= 0
		var right: float = width - 2.0
		var numbers: String = ""
		if bool(row["first"]):
			_text("#%d" % (int(row["cast"]) + 1), Vector2(1.0, top + 5.0), MUTED)
			numbers = "%d%% %sdmg" % [int(row["mana"]), _short(float(row["damage"]))]
			right -= _text_width(numbers) + 3.0
			_text(numbers, Vector2(width - 1.0 - _text_width(numbers), top + 5.0), WARN if int(row["mana"]) > 100 else MUTED)
		var end_x: float = _row_x[at]
		for tile in slots.size():
			var x: float = xs[tile]
			if x + TILE_SIZE > right:
				_text("+%d" % (slots.size() - tile), Vector2(x, top + 5.0), DIM)
				end_x = x + _text_width("+%d" % (slots.size() - tile))
				break
			_draw_tile(slots[tile], Rect2(x, top + 1.0, TILE_SIZE, TILE_SIZE))
			end_x = x + TILE_SIZE
			if trigger and tile == 0:
				_draw_arrow(Vector2(x + TILE_SIZE + 1.0, top + 1.0 + TILE_SIZE * 0.5))
		var color: Color = kind_colors.get(&"trigger" if trigger else &"form", TEXT)
		_text(_fit(String(row["name"]), right - end_x - 4.0), Vector2(end_x + 4.0, top + 5.0), color)
		if at == replay:
			draw_rect(Rect2(0.0, top, width, ROW_HEIGHT), GOLD, false, 1.0)
	# The header over the rows, so a scrolled row slides under it.
	draw_rect(Rect2(0.0, 0.0, size.x, HEADER_HEIGHT), OUTLINE)
	_text(HEADER_TEXT, Vector2(1.0, 1.0), TEXT)
	if _rows.is_empty():
		_text(EMPTY_TEXT, Vector2(GUTTER, HEADER_HEIGHT + 4.0), DIM)
	_draw_bar()


## The line from the row's parent: down from under the parent's first tile, then across to it.
func _draw_branch(at: int, top: float) -> void:
	var parent: int = _parent[at]
	if parent == NONE:
		return
	var x: float = _row_x[parent] + TILE_SIZE * 0.5
	var from_y: float = _row_top(parent) + 1.0 + TILE_SIZE
	var mid: float = top + 1.0 + TILE_SIZE * 0.5
	draw_rect(Rect2(x, from_y, 1.0, mid - from_y + 1.0), LINE)
	draw_rect(Rect2(x, mid, _row_x[at] - x - 1.0, 1.0), LINE)


func _draw_arrow(tip_from: Vector2) -> void:
	var x: float = roundf(tip_from.x + 1.0)
	var y: float = roundf(tip_from.y)
	draw_rect(Rect2(x, y, 4.0, 1.0), LINE.lightened(0.3))
	draw_rect(Rect2(x + 2.0, y - 2.0, 1.0, 5.0), LINE.lightened(0.3))
	draw_rect(Rect2(x + 3.0, y - 1.0, 1.0, 3.0), LINE.lightened(0.3))


func _draw_tile(slot: int, rect: Rect2) -> void:
	var id: StringName = _card_of(slot)
	draw_rect(rect, TILE)
	var icon: Texture2D = spells.call("component_icon", id) if spells != null and id != NO_CARD else null
	if icon != null:
		draw_texture_rect(icon, rect, false)
	var kind: StringName = spells.call("component_kind", id) if spells != null and id != NO_CARD else &""
	draw_rect(Rect2(rect.position.x, rect.end.y - 2.0, rect.size.x, 2.0), kind_colors.get(kind, DIM))
	if slot == _marked:
		var frame: Rect2 = rect.grow(1.0)
		draw_rect(frame, GOLD, false, 1.0)
		draw_rect(Rect2(frame.position - Vector2(1.0, 1.0), Vector2(3.0, 1.0)), GOLD)
		draw_rect(Rect2(frame.position - Vector2(1.0, 1.0), Vector2(1.0, 3.0)), GOLD)
		draw_rect(Rect2(frame.end - Vector2(2.0, 0.0), Vector2(3.0, 1.0)), GOLD)
		draw_rect(Rect2(frame.end - Vector2(0.0, 2.0), Vector2(1.0, 3.0)), GOLD)


func _draw_bar() -> void:
	var total: float = HEADER_HEIGHT + _rows.size() * ROW_HEIGHT
	if total <= size.y:
		return
	var track := Rect2(size.x - BAR_WIDTH, HEADER_HEIGHT, BAR_WIDTH, size.y - HEADER_HEIGHT)
	draw_rect(track, LINE)
	var share: float = size.y / total
	var height: float = maxf(roundf(track.size.y * share), 4.0)
	var y: float = track.position.y + roundf((track.size.y - height) * (_scroll / maxf(max_scroll(), 1.0)))
	draw_rect(Rect2(track.position.x, y, BAR_WIDTH, height), TEXT)


func _card_of(slot: int) -> StringName:
	return _cards[slot] if slot >= 0 and slot < _cards.size() else NO_CARD


static func _short(value: float) -> String:
	var rounded: float = snappedf(value, 0.1)
	return str(int(rounded)) if is_equal_approx(rounded, roundf(rounded)) else str(rounded)
