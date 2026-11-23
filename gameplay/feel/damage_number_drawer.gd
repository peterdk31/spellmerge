extends Node2D
## Every actor's damage numbers, drawn in one place (props W5, docs/milestones/props.md): a child of
## Feel, top level (world space). Each actor's `DamageNumbers` look tells its hits
## (`damage_number_shown`); this keeps one pool of SLOTS numbers for the whole screen and draws them
## all in one `_draw`, so a room of 200 enemies in a storm of hits costs no node or label per number
## (the training dummy's performance fix of 2026-11-02, for every actor). When the pool is full the
## oldest number gives way.
##
## A number's text is written once, at the first step after its hit (a slot reused within the frame
## shows its last hit), and drawn glyph by glyph from a sheet of its font size's glyphs
## (`number_glyphs.gd`, made the first time a size is shown and kept): a whole string drawn is shaped
## and cached by the font as an object of its own, a glyph is not, so a storm makes no object per
## frame; and every glyph, outline and line is a region of the one sheet, so the numbers of one size
## are one draw call however they overlap (the performance pass, 2026-11-23: with the screen split
## every view draws every number, and the font's own two textures made a call a change). Each rises from where its actor said for as
## long as it said, fading out, in whole pixels. Numbers one after the other start in three lanes
## (LANES: to the side and a line up from the one before), so the hits of one moment (a multicast)
## stay apart.
## Its colour says what kind of hit it was: the element's own colour (`ElementBase.tint`, read once
## per element from the registry), white for a plain hit, HEAL_COLOR for a heal; a hit that took
## nothing (`spared`) is dim and struck through.
##
## The "Damage numbers" setting (`damage_numbers_changed`, the pause menu's) hides them all and
## shows none until it is on again. It is the view's only: nothing in the game reads this, and it
## runs on Feel's real clock (`step`).

## How many numbers may show at once on the whole screen.
const SLOTS: int = 128
## Over the shots and every flash, beside the reaction names.
const Z: int = 22
## The plain text: its font size, outline and outline colour (the dummy's labels').
const FONT_SIZE: int = 8
const OUTLINE: int = 3
const OUTLINE_COLOR: Color = Color(0.078, 0.071, 0.122, 1.0)
## The colours of a plain hit and of a heal (docs/STYLE.md; the heal cue's green).
const PLAIN_COLOR: Color = Color.WHITE
const HEAL_COLOR: Color = Color(0.42, 0.89, 0.42, 1.0)
## How bright a hit that took nothing shows.
const SPARED_ALPHA: float = 0.7
## Where numbers one after the other start, from where their actor said, in pixels of plain text
## (scaled with the text): each lane a line above the one before and to the other side.
const LANES: PackedVector2Array = [Vector2(-5.0, 0.0), Vector2(5.0, -7.0), Vector2(0.0, -14.0)]
## The registry folder the element cards are in.
const ELEMENT_FOLDER: StringName = &"spells"
## The characters a number is written in (`text_of`).
const GLYPHS: PackedStringArray = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "-"]

const EventsScript := preload("res://core/events/events.gd")
const NumberGlyphsScript := preload("res://gameplay/feel/number_glyphs.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

## The bus (Feel's) and the registry the element colours come from (null: every hit plain).
var events: EventsScript = null
var registry: RegistryScript = null:
	set(value):
		registry = value
		_tints.clear()
## The setting: false hides every number and shows no new one.
var shown: bool = true

var _left: PackedFloat32Array = PackedFloat32Array()
var _seconds: PackedFloat32Array = PackedFloat32Array()
var _rise: PackedFloat32Array = PackedFloat32Array()
var _font_size: PackedInt32Array = PackedInt32Array()
var _start: PackedVector2Array = PackedVector2Array()
var _amount: PackedFloat32Array = PackedFloat32Array()
var _colour: PackedColorArray = PackedColorArray()
## 1 for a number that took nothing (struck through).
var _spared: PackedByteArray = PackedByteArray()
## 1 for a number whose text is not written yet.
var _new: PackedByteArray = PackedByteArray()
var _text: PackedStringArray = PackedStringArray()
var _width: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0
## Numbers showing, and whether a new one waits for its text.
var _live: int = 0
var _fresh: bool = false
## An element's colour by its id, read once from the registry.
var _tints: Dictionary[StringName, Color] = {}
var _font: Font = null
## The glyphs' sheet of each font size shown so far (`number_glyphs.gd`), kept.
var _sheets: Dictionary[int, NumberGlyphsScript] = {}


func _ready() -> void:
	top_level = true
	z_index = Z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = ThemeDB.fallback_font
	# The sheets' pixels are premultiplied (`number_glyphs.gd`): drawn so, with `_tinted` colours.
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	material = blend
	# Packed arrays are values: each is sized where it lives.
	_left.resize(SLOTS)
	_left.fill(0.0)
	_seconds.resize(SLOTS)
	_rise.resize(SLOTS)
	_font_size.resize(SLOTS)
	_start.resize(SLOTS)
	_amount.resize(SLOTS)
	_colour.resize(SLOTS)
	_spared.resize(SLOTS)
	_new.resize(SLOTS)
	_new.fill(0)
	_text.resize(SLOTS)
	_width.resize(SLOTS)
	# The plain size's sheet before the first hit, so its first number has its glyphs.
	_sheet_of(FONT_SIZE)
	if events != null:
		events.damage_number_shown.connect(show_number)
		events.damage_numbers_changed.connect(set_shown)


## Show or hide every number (the setting). Hiding ends the numbers showing.
func set_shown(on: bool) -> void:
	shown = on
	if on:
		return
	_left.fill(0.0)
	_live = 0
	_fresh = false
	queue_redraw()


## A hit's number (`damage_number_shown`; see the bus for each value). It takes the next slot, the
## oldest number when every slot shows one.
func show_number(_actor: int, position: Vector2, amount: float, element: StringName, kind: StringName, rise: float, seconds: float, size: float) -> void:
	if not shown or amount <= 0.0 or seconds <= 0.0:
		return
	var slot: int = _next
	_next = (_next + 1) % SLOTS
	if _left[slot] <= 0.0:
		_live += 1
	_left[slot] = seconds
	_seconds[slot] = seconds
	_rise[slot] = rise
	_font_size[slot] = maxi(roundi(float(FONT_SIZE) * size), 1)
	_sheet_of(_font_size[slot])
	_start[slot] = position + LANES[slot % LANES.size()] * size
	_amount[slot] = amount
	_colour[slot] = HEAL_COLOR if kind == EventsScript.NUMBER_HEAL else _tint_of(element)
	_spared[slot] = 1 if kind == EventsScript.NUMBER_SPARED else 0
	_new[slot] = 1
	_fresh = true


## Move the numbers on by `real_delta` seconds (Feel's step): new ones get their text, old ones
## rise, fade and end. Draws again only while any shows.
func step(real_delta: float) -> void:
	if _live == 0:
		return
	if _fresh:
		_write_new()
	for slot in SLOTS:
		if _left[slot] <= 0.0:
			continue
		_left[slot] -= real_delta
		if _left[slot] <= 0.0:
			_left[slot] = 0.0
			_live -= 1
	queue_redraw()


## How many numbers show now (tests).
func live() -> int:
	return _live


## The texts of the numbers showing, oldest slot first (tests).
func shown_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for slot in SLOTS:
		if _left[slot] > 0.0:
			texts.append(_text[slot] if _new[slot] == 0 else text_of(_amount[slot]))
	return texts


## The colour the number in `slot` is drawn in, before it fades (tests).
func colour_of_slot(slot: int) -> Color:
	return _colour[slot]


## Whether the number in `slot` took nothing (tests).
func is_spared(slot: int) -> bool:
	return _spared[slot] == 1


## The slot the next number takes (tests).
func next_slot() -> int:
	return _next


## A number's text: to a tenth (an atom's speck shows 0.3, a bolt 5).
static func text_of(amount: float) -> String:
	return ("%.1f" % amount).trim_suffix(".0")


func _write_new() -> void:
	_fresh = false
	for slot in SLOTS:
		if _new[slot] == 0:
			continue
		_new[slot] = 0
		_text[slot] = text_of(_amount[slot])
		var width: float = 0.0
		for at in _text[slot].length():
			width += _font.get_char_size(_text[slot].unicode_at(at), _font_size[slot]).x
		_width[slot] = width


func _tint_of(element: StringName) -> Color:
	if element == &"":
		return PLAIN_COLOR
	if not _tints.has(element):
		var card := registry.get_resource(ELEMENT_FOLDER, element) as ElementBase if registry != null else null
		_tints[element] = Color(card.tint, 1.0) if card != null else PLAIN_COLOR
	return _tints[element]


## The numbers in slot order, each its outlines, then its glyphs (and a spared hit's line), all
## regions of its size's sheet: the same pixels as the font drawing them one by one with each glyph
## on a whole pixel, in a draw call a run of numbers of one size in slot order (`sheets_drawn_now`:
## sizes that alternate change sheet each time; every actor's numbers are the plain size today). A number whose sheet is not drawn yet (the
## frame its size is first shown) waits for it.
func _draw() -> void:
	for slot in SLOTS:
		if _left[slot] <= 0.0 or _new[slot] == 1:
			continue
		var sheet: NumberGlyphsScript = _sheets.get(_font_size[slot])
		if sheet == null or not sheet.ready_now():
			continue
		var texture: Texture2D = sheet.get_texture()
		var at: Vector2 = _at_of(slot)
		var alpha: float = _alpha_of(slot)
		var text: String = _text[slot]
		_draw_text(sheet, texture, text, at, true, _tinted(OUTLINE_COLOR, alpha))
		var colour: Color = _tinted(_colour[slot], alpha)
		_draw_text(sheet, texture, text, at, false, colour)
		if _spared[slot] == 1:
			var y: float = at.y - roundf(float(_font_size[slot]) * 0.35)
			draw_texture_rect_region(texture, Rect2(at.x - 1.0, y - 0.5, _width[slot] + 2.0, 1.0), sheet.white_region(), colour)


## How many times the numbers showing now change sheet in the order they are drawn: the draw calls
## they take (for tests; one while every number is of one size).
func sheets_drawn_now() -> int:
	var changes: int = 0
	var last: int = -1
	for slot in SLOTS:
		if _left[slot] <= 0.0 or _new[slot] == 1:
			continue
		if _font_size[slot] != last:
			last = _font_size[slot]
			changes += 1
	return changes


## The sheets made so far (for tests).
func sheets_made() -> int:
	return _sheets.size()


## The sheet of the glyphs at `size`, made the first time it is asked for.
func _sheet_of(size: int) -> NumberGlyphsScript:
	var sheet: NumberGlyphsScript = _sheets.get(size)
	if sheet == null:
		sheet = NumberGlyphsScript.new(_font, size, OUTLINE, GLYPHS)
		sheet.name = "Glyphs%d" % size
		_sheets[size] = sheet
		add_child(sheet)
	return sheet


## `colour` at `alpha`, premultiplied (the sheets are drawn with a premultiplied blend).
static func _tinted(colour: Color, alpha: float) -> Color:
	return Color(colour.r * alpha, colour.g * alpha, colour.b * alpha, alpha)


## `text`'s glyphs (`outline`: their outlines) from `at` (its baseline's left), each its region of
## `sheet`; the outlines of a number are all drawn before its glyphs, so a glyph's outline never
## covers the one before.
func _draw_text(sheet: NumberGlyphsScript, texture: Texture2D, text: String, at: Vector2, outline: bool, colour: Color) -> void:
	var x: float = at.x
	for i in text.length():
		var code: int = text.unicode_at(i)
		if not sheet.has(code):
			continue
		# On a whole pixel: the sheet holds each glyph as the font draws it there (between pixels the
		# font draws another cut of it, by quarters of a pixel).
		draw_texture_rect_region(texture, sheet.place_of(code, Vector2(roundf(x), at.y)), sheet.region_of(code, outline), colour)
		x += sheet.advance_of(code)


## Slot `slot`'s number's alpha now (it fades as it rises; a spared hit's dimmer).
func _alpha_of(slot: int) -> float:
	var age: float = 1.0 - _left[slot] / _seconds[slot]
	return (1.0 - age * age) * (SPARED_ALPHA if _spared[slot] == 1 else 1.0)


## Where slot `slot`'s number's baseline starts now, on whole pixels.
func _at_of(slot: int) -> Vector2:
	var age: float = 1.0 - _left[slot] / _seconds[slot]
	return (_start[slot] + Vector2(-_width[slot] * 0.5, -_rise[slot] * age)).round()
