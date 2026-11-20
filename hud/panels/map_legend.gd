extends Control
## The held Y map's legend (the owner, 2026-11-20: "The map's legend shows a D-pad glyph with 'Move
## teleport target' (and A 'Teleport')"): one strip a seat, node Root/MapLegend, made by `panels.gd`.
## While a seat's map frame is fully open (`map_frame_shown`, Feel's `party_map_view.gd`) and it may
## pick a room there (`map_picker.gd`'s pick), a strip along the inside of the frame's lower edge
## shows the whole d-pad's glyph (`InputGlyphs.DPAD`: 1-4 on the keyboard) with MOVE_WORDS and the
## `take` button's (A; F) with TELEPORT_WORDS.
##
## **Smooth** (docs/STYLE.md): it rises from the frame's lower edge by STAGES heights at FPS and sinks
## back the same way, whole pixels, never a fade; a frame that moves takes it along.
##
## Display only: it reads no input (`panels.gd` says which seats pick) and sends nothing.

const InputManagerScript := preload("res://core/input/input_manager.gd")
const GlyphsScript := preload("res://core/input/input_glyphs.gd")
const ActionGlyphScript := preload("res://hud/widgets/action_glyph.gd")

const SEATS: int = 4
const MOVE_WORDS: String = "Move teleport target"
const TELEPORT_WORDS: String = "Teleport"
## The button A teleports with (the map picker's).
const TAKE_ACTION: StringName = &"take"
## The strip's height, its stages and how fast it steps (as the map's opening).
const HEIGHT: int = 14
const STAGES: int = 4
const FPS: float = 12.0
## Screen pixels between a glyph and its words, and between the two pairs.
const GAP: int = 3
const PAIR_GAP: int = 8
const FONT_SIZE: int = 8
const BACK: Color = Color(0.06, 0.06, 0.1, 0.9)
const LINE: Color = Color(0.29, 0.27, 0.39)
const TEXT: Color = Color(0.95, 0.96, 0.98)

## By seat: its frame (HUD pixels) and whether it is fully open, as told; its stage (0 hidden ...
## STAGES risen); and its strip, which clips.
var _frame: Array[Rect2i] = [Rect2i(), Rect2i(), Rect2i(), Rect2i()]
var _open: Array[bool] = [false, false, false, false]
var _stage: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _strips: Array[Strip] = []
var _clock: float = 0.0


## One seat's strip: a Control that clips, its row of two glyphs and two words drawn inside.
class Strip extends Control:
	var dpad: ActionGlyphScript = null
	var take: ActionGlyphScript = null
	## The row's full height drawn from the strip's top (it rises: its top rows show first).
	var row: Row = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		visible = false
		row = Row.new()
		add_child(row)
		dpad = ActionGlyphScript.new()
		take = ActionGlyphScript.new()
		row.add_child(dpad)
		row.add_child(take)


## The strip's row: its backing, its top line and the two words.
class Row extends Control:
	## Where each of the two words starts (row pixels).
	var words_at: PackedInt32Array = PackedInt32Array([0, 0])

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var legend: Object = get_parent().get_parent()
		legend.call(&"draw_row", self)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for seat in SEATS:
		var strip := Strip.new()
		strip.name = "Legend%d" % (seat + 1)
		add_child(strip)
		_strips.append(strip)


## Use this input manager for the glyphs (null: the "PlayerInput" autoload) and hear the frames.
func bind(events: Node, input: InputManagerScript) -> void:
	for seat in SEATS:
		_strips[seat].dpad.bind(input)
		_strips[seat].dpad.show_action(seat, GlyphsScript.DPAD)
		_strips[seat].take.bind(input)
		_strips[seat].take.show_action(seat, TAKE_ACTION)
	if events != null:
		events.map_frame_shown.connect(_on_map_frame_shown)


## Seat `seat`'s stage (0 hidden ... STAGES risen; for tests).
func stage_of(seat: int) -> int:
	return _stage[seat] if seat >= 0 and seat < SEATS else 0


## Seat `seat`'s strip (for tests and screenshots).
func strip_of(seat: int) -> Control:
	return _strips[seat]


## A frame of `delta` real seconds: `picking` says, a bit a seat, which seats may pick a room on their
## map now; `to_hud` turns screen pixels into this layer's.
func step(delta: float, picking: int, to_hud: Transform2D) -> void:
	_clock += delta
	var moving: bool = false
	for seat in SEATS:
		if _stage[seat] != _wanted(seat, picking):
			moving = true
	if not moving:
		_clock = 0.0
	while _clock >= 1.0 / FPS:
		_clock -= 1.0 / FPS
		for seat in SEATS:
			_stage[seat] += signi(_wanted(seat, picking) - _stage[seat])
	for seat in SEATS:
		_place(seat, to_hud)


func _wanted(seat: int, picking: int) -> int:
	return STAGES if _open[seat] and picking & (1 << seat) != 0 and _frame[seat].size != Vector2i.ZERO else 0


## The strip of seat `seat` along the inside of its frame's lower edge, as tall as its stage.
func _place(seat: int, to_hud: Transform2D) -> void:
	var strip: Strip = _strips[seat]
	if _stage[seat] <= 0 or _frame[seat].size == Vector2i.ZERO:
		strip.visible = false
		return
	var corner: Vector2 = (to_hud * Vector2(_frame[seat].position)).round()
	var end: Vector2 = (to_hud * Vector2(_frame[seat].end)).round()
	var tall: int = (HEIGHT * _stage[seat]) / STAGES
	strip.position = Vector2(corner.x, end.y - tall)
	strip.size = Vector2(end.x - corner.x, tall)
	strip.row.position = Vector2.ZERO
	strip.row.size = Vector2(strip.size.x, HEIGHT)
	_lay_row(strip)
	strip.visible = true


## The two glyphs in the row, the pair of words centred.
func _lay_row(strip: Strip) -> void:
	var font: Font = get_theme_default_font()
	var move_width: int = ceili(font.get_string_size(MOVE_WORDS, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	var dpad_width: int = int(strip.dpad.custom_minimum_size.x)
	var take_width: int = int(strip.take.custom_minimum_size.x)
	var total: int = dpad_width + GAP + move_width + PAIR_GAP + take_width + GAP + ceili(font.get_string_size(TELEPORT_WORDS, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	var left: int = maxi((int(strip.size.x) - total) / 2, 2)
	var top: int = (HEIGHT - int(ActionGlyphScript.GLYPH_HEIGHT)) / 2 + 1
	strip.dpad.position = Vector2(left, top)
	strip.dpad.size = strip.dpad.custom_minimum_size
	strip.take.position = Vector2(left + dpad_width + GAP + move_width + PAIR_GAP, top)
	strip.take.size = strip.take.custom_minimum_size
	var first: int = left + dpad_width + GAP
	var second: int = first + move_width + PAIR_GAP + take_width + GAP
	if strip.row.words_at[0] != first or strip.row.words_at[1] != second:
		strip.row.words_at[0] = first
		strip.row.words_at[1] = second
		strip.row.queue_redraw()


## Draw `row`'s backing, its top line and its two words (called by the row).
func draw_row(row: Row) -> void:
	row.draw_rect(Rect2(Vector2.ZERO, row.size), BACK)
	row.draw_rect(Rect2(0.0, 0.0, row.size.x, 1.0), LINE)
	var at: PackedInt32Array = row.words_at
	var font: Font = get_theme_default_font()
	var base: float = roundf((HEIGHT - font.get_height(FONT_SIZE)) * 0.5 + font.get_ascent(FONT_SIZE)) + 1.0
	row.draw_string(font, Vector2(at[0], base), MOVE_WORDS, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
	row.draw_string(font, Vector2(at[1], base), TELEPORT_WORDS, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)


func _on_map_frame_shown(seat: int, frame: Rect2i, open: bool) -> void:
	if seat < 0 or seat >= SEATS:
		return
	if frame.size != Vector2i.ZERO:
		_frame[seat] = frame
	_open[seat] = open and frame.size != Vector2i.ZERO
