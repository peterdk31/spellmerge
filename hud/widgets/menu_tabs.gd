extends Control
## A row of tabs for a menu page (the owner, 2026-11-18: "move the different settings groups into
## tabs ... Tabs can be moved through with RB, LB"): the tabs' names across the top, the selected
## one in a box with a gold bar under it, and the buttons that page them drawn at the ends: the
## glyph of `page_prev` (LB, L1, L; Z on the keyboard) at the left, `page_next` (RB, R1, R; C) at
## the right (`widgets/action_glyph.gd`, following the player's device as it changes). Drawn in
## code, display only: no input, no focus. The menu that holds it hears the paging (UIFocus
## `paged`) and calls `select`.
##
##     tabs.bind(input)                       # the PlayerInput node (null: the autoload)
##     tabs.set_tabs(["Graphics", "Audio"])
##     tabs.show_for(player)                  # the glyphs of that player's device
##     tabs.select(1)                         # the box slides there (`snap` puts it there at once)
##
## Smooth (docs/STYLE.md): a switch slides the box from where it is to the new tab over
## SLIDE_SECONDS, eased out, by whole pixels (6 frames at 60, and never fewer than 3 however slow
## the frames), and each tab's name steps one shade at a time (dim, plain, bright) from where it was
## toward its own, never in one jump, a switch during a slide too, which starts from where the box
## is. `remaining()` tells the holder how much of the slide is left (1 to 0, eased) and
## `travel_side()` which way the box goes, so its own content can follow. It allocates only when its
## tabs are set, the theme or the device changes, never a frame.

const ActionGlyphScript := preload("res://hud/widgets/action_glyph.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")

## The row's height, the boxes' padding round a name and the room between tabs.
const TAB_HEIGHT: float = 18.0
const TAB_PAD: float = 6.0
const TAB_GAP: float = 2.0
## Room kept for each end's glyph (the widest, "LB", "L1" or a key, fits), and between it and the tabs.
const GLYPH_ROOM: float = 20.0
const GLYPH_GAP: float = 4.0
const FONT_SIZE: int = 12
## How long the box takes to slide to a new tab.
const SLIDE_SECONDS: float = 0.1
## The colours, read from the theme (hud/theme/spellmerge_theme.tres, `_read_colors`) when it is
## known: the box a button's face (Button `normal`), its outline that style's border, the gold the
## focus style's border (Button `focus`), and the three shades a tab's name steps through (Button
## `font_disabled_color`, Label `font_color`, Button `font_color`). These are the theme's own values,
## used only where the theme has none.
const BOX: Color = Color(0.290196, 0.27451, 0.388235)
const OUTLINE: Color = Color(0.0784314, 0.0705882, 0.121569)
const GOLD: Color = Color(0.94902, 0.760784, 0.188235)
const SHADES: Array[Color] = [
	Color(0.639216, 0.623529, 0.721569), Color(0.831373, 0.815686, 0.878431), Color(0.956863, 0.945098, 0.917647),
]
## The names' outline (as the theme's labels have).
const TEXT_OUTLINE: int = 2
## The most a slide moves on in one step: a slow frame still shows at least 3 frames of it.
const MAX_STEP: float = SLIDE_SECONDS / 3.0

var _names: Array[String] = []
## Each tab's width (its name and padding), measured when the tabs are set.
var _widths: PackedFloat32Array = PackedFloat32Array()
var _selected: int = 0
## The box drawn when the slide began, and how far the slide is (0 to 1; 1 when still).
var _from_box: Rect2 = Rect2()
var _t: float = 1.0
## Each tab's name shade when the slide began, which it steps from toward its own (bright for the
## selected tab, dim for the rest).
var _from_shades: PackedInt32Array = PackedInt32Array()
## The colours drawn with (see BOX).
var _box_color: Color = BOX
var _outline_color: Color = OUTLINE
var _gold_color: Color = GOLD
var _shade_colors: Array[Color] = SHADES.duplicate()
## Sent each step of a slide with what is left of it (`remaining`), so the holder's content can
## follow the box (the pause menu's rows step in with it).
signal slide_stepped(left: float)

var _prev: ActionGlyphScript = null
var _next: ActionGlyphScript = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prev = _make_glyph("PrevGlyph")
	_next = _make_glyph("NextGlyph")


func _ready() -> void:
	# Steps only while the box slides.
	set_process(false)
	_measure()


func _make_glyph(node_name: String) -> ActionGlyphScript:
	var glyph: ActionGlyphScript = ActionGlyphScript.new()
	glyph.name = node_name
	glyph.minimum_size_changed.connect(_lay_out_glyphs)
	add_child(glyph)
	return glyph


## Use this input manager for the glyphs; null uses the "PlayerInput" autoload.
func bind(input: InputManagerScript) -> void:
	_prev.bind(input)
	_next.bind(input)


## Draw the glyphs of `player`'s device.
func show_for(player: int) -> void:
	_prev.show_action(player, &"page_prev")
	_next.show_action(player, &"page_next")
	_lay_out_glyphs()


## The tabs' names, left to right; the first is selected.
func set_tabs(names: Array[String]) -> void:
	_names = names.duplicate()
	_selected = 0
	_t = 1.0
	_from_shades.resize(_names.size())
	_measure()


func tab_count() -> int:
	return _names.size()


## The tabs' names, left to right.
func names() -> Array[String]:
	return _names.duplicate()


func selected() -> int:
	return _selected


## Select `index` (inside the tabs): the box slides there from where it is drawn now.
func select(index: int) -> void:
	var next: int = clampi(index, 0, maxi(_names.size() - 1, 0))
	if next == _selected:
		return
	_from_box = box()
	for at in _names.size():
		_from_shades[at] = shade_of(at)
	_selected = next
	_t = 0.0
	set_process(true)
	queue_redraw()


## Put the box on the selected tab at once (a page shown afresh has nothing to slide from).
func snap() -> void:
	_t = 1.0
	queue_redraw()
	slide_stepped.emit(0.0)


## Which way the box goes on its slide: +1 right, -1 left, 0 still (a page's content steps in from
## the side it goes toward, so the two agree when paging wraps round).
func travel_side() -> int:
	if _t >= 1.0:
		return 0
	return signi(int(tab_rect(_selected).position.x - _from_box.position.x))


## Whether the box is still sliding.
func is_sliding() -> bool:
	return _t < 1.0


## How much of the slide is left, eased: 1 as it begins, 0 once still.
func remaining() -> float:
	return 1.0 - _eased(_t)


## The glyphs at the ends (for tests and screenshots).
func prev_glyph() -> ActionGlyphScript:
	return _prev


func next_glyph() -> ActionGlyphScript:
	return _next


func _process(delta: float) -> void:
	step(delta)


## Move the slide on by `delta` seconds (`_process` calls it; tests call it directly).
func step(delta: float) -> void:
	if _t >= 1.0:
		set_process(false)
		return
	_t = minf(1.0, _t + minf(delta, MAX_STEP) / SLIDE_SECONDS)
	queue_redraw()
	slide_stepped.emit(remaining())


## Where tab `index` sits in the row, in whole pixels.
func tab_rect(index: int) -> Rect2:
	var x: float = _tabs_left()
	for at in index:
		x += _widths[at] + TAB_GAP
	return Rect2(roundf(x), 0.0, _widths[index], TAB_HEIGHT)


## The box as drawn now: on the selected tab, or on its way there, in whole pixels.
func box() -> Rect2:
	if _names.is_empty():
		return Rect2()
	var to: Rect2 = tab_rect(_selected)
	if _t >= 1.0:
		return to
	var e: float = _eased(_t)
	var left: float = roundf(lerpf(_from_box.position.x, to.position.x, e))
	var right: float = roundf(lerpf(_from_box.end.x, to.end.x, e))
	return Rect2(left, 0.0, right - left, TAB_HEIGHT)


## The shade (0 dim, 1 plain, 2 bright) tab `index`'s name is drawn in now: each steps one shade at
## a time from where it was when the slide began toward its own, the selected one up as the box
## arrives, the others down, so paging again mid-slide never skips a shade.
func shade_of(index: int) -> int:
	var target: int = 2 if index == _selected else 0
	if _t >= 1.0:
		return target
	var from: int = _from_shades[index]
	var e: float = _eased(_t)
	var moved: int = 2 if e >= 0.66 else (1 if e >= 0.33 else 0)
	return from + signi(target - from) * mini(moved, absi(target - from))


## Ease out (cubic): quick away, settling in.
static func _eased(t: float) -> float:
	var left: float = 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - left * left * left


## The tabs' row, centred between the glyphs' room.
func _tabs_left() -> float:
	var room: float = size.x - 2.0 * (GLYPH_ROOM + GLYPH_GAP)
	return GLYPH_ROOM + GLYPH_GAP + maxf(0.0, floorf((room - _tabs_width()) / 2.0))


func _tabs_width() -> float:
	var total: float = 0.0
	for width in _widths:
		total += width
	return total + TAB_GAP * maxf(0.0, _widths.size() - 1.0)


func _measure() -> void:
	_read_colors()
	_widths.clear()
	var font: Font = get_theme_default_font()
	for tab_name in _names:
		_widths.append(ceilf(font.get_string_size(tab_name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x) + 2.0 * TAB_PAD)
	custom_minimum_size = Vector2(_tabs_width() + 2.0 * (GLYPH_ROOM + GLYPH_GAP), TAB_HEIGHT)
	_lay_out_glyphs()
	queue_redraw()


## The colours from the theme (see BOX), each kept at its fallback where the theme has none.
func _read_colors() -> void:
	var face: StyleBoxFlat = get_theme_stylebox(&"normal", &"Button") as StyleBoxFlat
	if face != null:
		_box_color = face.bg_color
		_outline_color = face.border_color
	var focus: StyleBoxFlat = get_theme_stylebox(&"focus", &"Button") as StyleBoxFlat
	if focus != null:
		_gold_color = focus.border_color
	if has_theme_color(&"font_disabled_color", &"Button"):
		_shade_colors[0] = get_theme_color(&"font_disabled_color", &"Button")
	if has_theme_color(&"font_color", &"Label"):
		_shade_colors[1] = get_theme_color(&"font_color", &"Label")
	if has_theme_color(&"font_color", &"Button"):
		_shade_colors[2] = get_theme_color(&"font_color", &"Button")


## Each glyph in the middle of its end's room, at the row's middle.
func _lay_out_glyphs() -> void:
	if _prev == null or _next == null:
		return
	var top: float = floorf((TAB_HEIGHT - ActionGlyphScript.GLYPH_HEIGHT) / 2.0)
	_prev.position = Vector2(floorf((GLYPH_ROOM - _prev.custom_minimum_size.x) / 2.0), top)
	_next.position = Vector2(floorf(size.x - GLYPH_ROOM + (GLYPH_ROOM - _next.custom_minimum_size.x) / 2.0), top)
	_prev.size = _prev.custom_minimum_size
	_next.size = _next.custom_minimum_size


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_lay_out_glyphs()
		queue_redraw()
	elif what == NOTIFICATION_THEME_CHANGED and is_inside_tree():
		_measure()


func _draw() -> void:
	if _names.is_empty():
		return
	# The thin line under the whole row, in the box's face colour.
	draw_rect(Rect2(0.0, TAB_HEIGHT - 1.0, size.x, 1.0), _box_color)
	var at: Rect2 = box()
	draw_rect(at, _outline_color)
	draw_rect(at.grow(-1.0), _box_color)
	draw_rect(Rect2(at.position.x + 1.0, TAB_HEIGHT - 3.0, at.size.x - 2.0, 2.0), _gold_color)
	var font: Font = get_theme_default_font()
	var baseline: float = roundf((TAB_HEIGHT - 3.0 - font.get_height(FONT_SIZE)) / 2.0 + font.get_ascent(FONT_SIZE))
	for index in _names.size():
		var tab: Rect2 = tab_rect(index)
		var at_text := Vector2(tab.position.x + TAB_PAD, baseline)
		draw_string_outline(font, at_text, _names[index], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_OUTLINE, _outline_color)
		draw_string(font, at_text, _names[index], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, _shade_colors[shade_of(index)])
