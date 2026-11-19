extends Control
## One choice of a reward offer as a card (hud/menus/reward, the owner's redesign of 2026-11-19):
## its icon (a card's own, or its kind's glyph for coins, a heal or more health), its name and what
## it does (the view's `description`: a card's builder line, or the reward kind's,
## `RewardEntry.DESCRIPTIONS`), each wrapped to the card's width at spaces (a word too long for a
## line is cut across lines, never clipped), centred. `reward_menu.gd` makes one a choice, sets its
## width (`fit_width`, which says the height its words need) and how far it is raised (`lift`, by
## whole pixels, the focused one LIFT up); it is drawn by itself, in the palette, by whole pixels.
## A UIFocus control: focus and A are the menu's.

const FONT_SIZE: int = 8
const LINE_STEP: float = 9.0
## The icon's size, and the air inside the card's frame.
const ICON: float = 32.0
const PAD: float = 4.0
## Air between the icon, the name and the description.
const SPACE: float = 3.0
## How far the focused card stands up (whole pixels; the menu raises it one a frame).
const LIFT: int = 3

const OUTLINE: Color = Color("#14121f")
const BODY: Color = Color("#2b2840")
const RIM: Color = Color("#4a4663")
const TEXT: Color = Color("#f4f1ea")
const MUTED: Color = Color("#a39fb8")

## A glyph of 16 by 16 cells drawn 2 px a cell, by a choice's kind when it has no icon of its own;
## a letter a colour, "." for none.
const GLYPH_CELL: float = 2.0
const GLYPH_COLORS: Dictionary = {
	"o": Color("#14121f"), "d": Color("#b8801f"), "g": Color("#f2c230"), "y": Color("#fff3a6"),
	"r": Color("#8f2d2a"), "h": Color("#e0592f"), "w": Color("#f4f1ea"),
}
const GLYPHS: Dictionary = {
	&"coins": [
		"................",
		".....oooooo.....",
		"...oodddddddo...",
		"..odggggggggdo..",
		"..odgyyyyyygdo..",
		".odgygggggggydo.",
		".odgyggddgggydo.",
		".odgygdggdggydo.",
		".odgygdggdggydo.",
		".odgyggddgggydo.",
		".odgygggggggydo.",
		"..odgyyyyyygdo..",
		"..odggggggggdo..",
		"...oodddddddo...",
		".....oooooo.....",
		"................",
	],
	&"heal": [
		"................",
		"................",
		"...ooo....ooo...",
		"..ohhho..ohhho..",
		".ohwwhhoohhhhro.",
		".ohwhhhhhhhhhro.",
		".ohhhhhhhhhhhro.",
		".ohhhhhhhhhhhro.",
		"..ohhhhhhhhhro..",
		"...ohhhhhhhro...",
		"....ohhhhhro....",
		".....ohhhro.....",
		"......ohro......",
		".......oo.......",
		"................",
		"................",
	],
	&"max_health": [
		"................",
		"................",
		"...ooo....ooo...",
		"..ohhho..ohhho..",
		".ohwwhhoohhhhro.",
		".ohwhhhoohhhhro.",
		".ohhhhowwohhhro.",
		".ohhhoowwoohhro.",
		"..ohowwwwwwohro.",
		"...oowwwwwwoo...",
		"....ohoowwoo....",
		".....ohowwo.....",
		"......ohoo......",
		".......oo.......",
		"................",
		"................",
	],
}

## The choice shown (the Rewards area's view: kind, id, count, name, icon, description).
var choice: Dictionary = {}
## How far it is raised now, 0 to LIFT (the menu's).
var lift: int = 0

var _name_lines: PackedStringArray = PackedStringArray()
var _text_lines: PackedStringArray = PackedStringArray()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Show `view`, one choice of an offer.
func show_choice(view: Dictionary) -> void:
	choice = view
	queue_redraw()


## Its name, as the view says.
func words() -> String:
	return String(choice.get("name", ""))


## What it does, as the view says.
func description() -> String:
	return String(choice.get("description", ""))


## Its name and description as wrapped for its width (for tests).
func name_lines() -> PackedStringArray:
	return _name_lines


func description_lines() -> PackedStringArray:
	return _text_lines


## Wrap its words for a card `width` pixels wide and say the height the card needs (its frame, the
## icon, the name and the description, and LIFT above it to stand up into).
func fit_width(width: float) -> float:
	var inner: float = width - 2.0 * PAD
	_name_lines = wrap_words(words(), inner)
	_text_lines = wrap_words(description(), inner)
	queue_redraw()
	return float(LIFT) + PAD * 2.0 + ICON + SPACE + LINE_STEP * float(_name_lines.size()) + (SPACE + LINE_STEP * float(_text_lines.size()) if not _text_lines.is_empty() else 0.0)


## The width of `text` in the HUD's font at FONT_SIZE.
func text_width(text: String) -> float:
	return _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x


## `text` broken into lines of at most `width` pixels at spaces; a word wider than a line is cut
## across lines, so nothing is ever clipped.
func wrap_words(text: String, width: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var line: String = ""
	for word in text.split(" ", false):
		var tried: String = word if line == "" else line + " " + word
		if text_width(tried) <= width:
			line = tried
			continue
		if line != "":
			lines.append(line)
		line = word
		while line.length() > 1 and text_width(line) > width:
			var cut: int = line.length() - 1
			while cut > 1 and text_width(line.left(cut)) > width:
				cut -= 1
			lines.append(line.left(cut))
			line = line.substr(cut)
	if line != "":
		lines.append(line)
	return lines


func _draw() -> void:
	var top: float = float(LIFT - lift)
	var body := Rect2(Vector2(0.0, top), Vector2(size.x, size.y - float(LIFT)))
	draw_rect(body, OUTLINE)
	draw_rect(body.grow(-1.0), RIM)
	draw_rect(body.grow(-2.0), BODY)
	var y: float = top + PAD
	var icon_at := Vector2(floorf((size.x - ICON) * 0.5), y)
	var icon: Texture2D = choice.get("icon") as Texture2D
	if icon != null:
		draw_texture_rect(icon, Rect2(icon_at, Vector2(ICON, ICON)), false)
	else:
		_draw_glyph(GLYPHS.get(StringName(choice.get("kind", &"")), []) as Array, icon_at)
	y += ICON + SPACE
	for line: String in _name_lines:
		_text(line, y, TEXT)
		y += LINE_STEP
	y += SPACE
	for line: String in _text_lines:
		_text(line, y, MUTED)
		y += LINE_STEP


func _draw_glyph(rows: Array, at: Vector2) -> void:
	for row in rows.size():
		var cells: String = rows[row]
		for column in cells.length():
			var color: Variant = GLYPH_COLORS.get(cells[column])
			if color is Color:
				draw_rect(Rect2(at + Vector2(column, row) * GLYPH_CELL, Vector2(GLYPH_CELL, GLYPH_CELL)), color as Color)


func _text(line: String, y: float, color: Color) -> void:
	var font: Font = _font()
	var x: float = floorf((size.x - text_width(line)) * 0.5)
	draw_string(font, Vector2(x, y + font.get_ascent(FONT_SIZE)).round(), line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)


func _font() -> Font:
	return get_theme_default_font()
