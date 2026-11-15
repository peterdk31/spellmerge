extends Control
## A small map of the run (run generation RG8, docs/milestones/run-generation.md): its rows top to
## bottom, the first room at the top, each row's rooms left to right; a line for each link; in each
## room the first letter of its kind's name ("F" a fight, "B" the boss), named in a line under the
## map; the room the party is in framed in gold, with "Room 3 of 6" under it. The rooms the party can
## still reach, and the links to them, are bright; the rest (behind it, or on another branch) dim.
## The pause menu's Map page shows it (hud/menus/pause).
##
## It shows what the bus says and nothing else (`run_map_changed`, the run area's); view only: it
## sends nothing, and empty (out of a run of rooms) it has no map (`has_map`) and draws nothing. It
## has no way to ask for the map: a view made after the run began shows nothing until the party
## enters its next room (the pause menu's is made and bound as the HUD starts, before any run). Each
## kind is told apart by its letter, so the room kinds' names start with different letters
## (tests/hud/test_run_map_view.gd checks the content).

const EventsScript := preload("res://core/events/events.gd")

## A room's square, and the room between rooms of a row and between rows, in pixels.
const ROOM_SIZE: float = 14.0
const COLUMN: float = 26.0
const ROW: float = 22.0
## The frame of the party's room, outside its square.
const HERE_FRAME: float = 2.0
## The space under the map for its two lines (the kinds, and where the party is).
const LINE_HEIGHT: float = 14.0
const PADDING: float = 4.0
## The shared theme's colours (hud/theme/spellmerge_theme.tres): a room, a room out of reach, the
## gold of the party's room, a link and the words.
const ROOM_COLOR: Color = Color(0.478431, 0.462745, 0.580392, 1)
const DIM_ROOM_COLOR: Color = Color(0.290196, 0.27451, 0.388235, 1)
const HERE_COLOR: Color = Color(0.94902, 0.760784, 0.188235, 1)
const LINK_COLOR: Color = Color(0.831373, 0.815686, 0.878431, 1)
const DIM_LINK_COLOR: Color = Color(0.290196, 0.27451, 0.388235, 1)
const LETTER_COLOR: Color = Color(0.956863, 0.945098, 0.917647, 1)
const DIM_LETTER_COLOR: Color = Color(0.639216, 0.623529, 0.721569, 1)
const EDGE_COLOR: Color = Color(0.0784314, 0.0705882, 0.121569, 1)
## Behind the map, so it reads over any room (the theme's darkest colour, near opaque: the dim
## rooms and links must not blend into a room's walls behind the pause menu).
const BACKING_COLOR: Color = Color(0.0784314, 0.0705882, 0.121569, 0.95)
## The most room the pause menu's Map page leaves the map on the 640x360 screen (its title, Back
## and the panel's margins take the rest): every run definition's deepest and widest map fits
## (tests/hud/test_run_map_view.gd checks the content).
const MOST_SIZE := Vector2(600.0, 280.0)
const HERE_TEXT: String = "Room %d of %d"

## The map shown changed (or went): the pause menu shows its Map row only while there is one.
signal map_changed()

## A kind's name for people (`RoomKind.shown_name`; the pause menu reads it from the registry).
var name_of: Callable = func(kind: StringName) -> String: return String(kind).capitalize()

## The map as last told (`run_map_changed`): each room's row, kind and links, and where the party is.
var rows: PackedInt32Array = PackedInt32Array()
var kinds: Array[StringName] = []
var links: Array[PackedInt32Array] = []
var at: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit()


func bind(events: EventsScript) -> void:
	if events != null:
		events.run_map_changed.connect(show_map)


## Show the map told (`run_map_changed`); a list shorter than `rows` counts as missing rooms' (none
## of the bus's, which sends them alike).
func show_map(map_rows: PackedInt32Array, map_kinds: Array[StringName], map_links: Array[PackedInt32Array], party_at: int) -> void:
	rows = map_rows.duplicate()
	kinds = map_kinds.duplicate()
	links = map_links.duplicate()
	at = party_at
	_fit()
	queue_redraw()
	map_changed.emit()


## True while there is a map to show (a run of rooms).
func has_map() -> bool:
	return not rows.is_empty()


## How many rows deep the map is.
func depth() -> int:
	var deepest: int = -1
	for row: int in rows:
		deepest = maxi(deepest, row)
	return deepest + 1


## The rooms the party can still reach from where it is: its room and every room its links lead to,
## on to the last row (none when it is nowhere).
func reachable() -> PackedInt32Array:
	var found := PackedInt32Array()
	if at < 0 or at >= rows.size():
		return found
	found.append(at)
	var next: int = 0
	while next < found.size():
		var room: int = found[next]
		next += 1
		if room < links.size():
			for link: int in links[room]:
				if link >= 0 and link < rows.size() and not found.has(link):
					found.append(link)
	return found


## The middle of room `index` in this control: its row from the top, the rooms of a row centred.
func room_middle(index: int) -> Vector2:
	var row: int = rows[index]
	var place: int = 0
	var count: int = 0
	for other in rows.size():
		if rows[other] == row:
			if other < index:
				place += 1
			count += 1
	var x: float = size.x * 0.5 + (float(place) - float(count - 1) * 0.5) * COLUMN
	var y: float = PADDING + ROOM_SIZE * 0.5 + float(row) * ROW
	return Vector2(roundf(x), roundf(y))


## The first letter of each kind on the map with its name, in the order they first stand
## ("F Fight  B Boss"): the line under the map.
func kinds_line() -> String:
	var seen: Array[StringName] = []
	var parts := PackedStringArray()
	for kind: StringName in kinds:
		if not seen.has(kind):
			seen.append(kind)
			parts.append("%s %s" % [_letter(kind), _name(kind)])
	return "  ".join(parts)


## Where the party is, under the map ("Room 3 of 6": its row of the map's rows); empty when nowhere.
func here_line() -> String:
	if at < 0 or at >= rows.size():
		return ""
	return HERE_TEXT % [rows[at] + 1, depth()]


func _draw() -> void:
	if not has_map():
		return
	var font: Font = get_theme_default_font()
	var font_size: int = get_theme_default_font_size()
	var bright: PackedInt32Array = reachable()
	draw_rect(Rect2(Vector2.ZERO, size), BACKING_COLOR)
	# The links first, under the rooms: bright where both ends can still be reached.
	for index in rows.size():
		if index >= links.size():
			continue
		for link: int in links[index]:
			if link < 0 or link >= rows.size():
				continue
			var on: bool = bright.has(index) and bright.has(link)
			draw_line(room_middle(index), room_middle(link), LINK_COLOR if on else DIM_LINK_COLOR, 1.0)
	for index in rows.size():
		var middle: Vector2 = room_middle(index)
		var square := Rect2(middle - Vector2.ONE * ROOM_SIZE * 0.5, Vector2.ONE * ROOM_SIZE)
		var on: bool = bright.has(index)
		if index == at:
			draw_rect(square.grow(HERE_FRAME), HERE_COLOR)
		draw_rect(square, ROOM_COLOR if on else DIM_ROOM_COLOR)
		draw_rect(square, EDGE_COLOR, false, 1.0)
		if font != null and index < kinds.size():
			var letter: String = _letter(kinds[index])
			var letter_size: Vector2 = font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var base: Vector2 = Vector2(middle.x - letter_size.x * 0.5, middle.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
			draw_string(font, base.round(), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LETTER_COLOR if on else DIM_LETTER_COLOR)
	if font == null:
		return
	var below: float = PADDING + float(depth() - 1) * ROW + ROOM_SIZE + PADDING
	_draw_line_of(font, font_size, kinds_line(), below)
	_draw_line_of(font, font_size, here_line(), below + LINE_HEIGHT)


## One line of words centred under the map, its top at `top`.
func _draw_line_of(font: Font, font_size: int, text: String, top: float) -> void:
	if text == "":
		return
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(roundf((size.x - width) * 0.5), roundf(top + font.get_ascent(font_size))), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LETTER_COLOR)


## As big as the map and its two lines need: the widest row (or the kinds' line) and every row.
func _fit() -> void:
	if not has_map():
		custom_minimum_size = Vector2.ZERO
		return
	var widest: int = 1
	var counts: Dictionary = {}
	for row: int in rows:
		counts[row] = int(counts.get(row, 0)) + 1
		widest = maxi(widest, int(counts[row]))
	var width: float = float(widest - 1) * COLUMN + ROOM_SIZE + HERE_FRAME * 2.0 + PADDING * 2.0
	var font: Font = get_theme_default_font() if is_inside_tree() else null
	if font != null:
		var line: float = maxf(font.get_string_size(kinds_line(), HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_default_font_size()).x,
				font.get_string_size(here_line(), HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_default_font_size()).x)
		width = maxf(width, line + PADDING * 2.0)
	var height: float = PADDING + float(depth() - 1) * ROW + ROOM_SIZE + PADDING + LINE_HEIGHT * 2.0 + PADDING
	custom_minimum_size = Vector2(ceilf(width), ceilf(height))


func _letter(kind: StringName) -> String:
	var shown: String = _name(kind)
	return shown.substr(0, 1).to_upper() if shown != "" else "?"


func _name(kind: StringName) -> String:
	return String(name_of.call(kind))
