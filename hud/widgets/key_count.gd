extends Control
## The party's key count (the owner, 2026-11-19): a small brass key and the number of keys the party
## holds, beside a corner panel's coins (`player_panel.gd`'s purse row). Keys are the party's, so
## every panel shows the same count; `panels.gd` tells each one (`party_keys_shown`).
##
## Smooth (docs/STYLE.md): the count never changes in one jump. The key and its number slide up into
## view from under the row's edge as the first key is taken, nod up as one more is taken and dip as
## one is spent, and sink out of view as the last is spent; each a play of POSE_COUNT poses held
## POSE_TIME each, moved by whole pixels and cut by the control's own edge (`clip_contents`), never
## faded. The number changes as a play starts (the last one's as its sinking ends). A change told
## while a play runs waits for it to end, then plays from where it stands. `set_count(count, true)`
## (after a snapshot is restored) draws the count as it stands at once.
##
## Display only: no input, no simulation state. It processes only while a play runs, draws in whole
## pixels and allocates nothing a frame.

## How long each pose of a play holds (seconds): POSE_COUNT poses take a fifth of a second.
const POSE_TIME: float = 0.05
const POSE_COUNT: int = 4
## The plays, each its poses' downward offsets in pixels (negative: up), the last its rest. `APPEAR`
## and `LEAVE` are fractions of the control's height (rounded to whole pixels), the others pixels.
const APPEAR: PackedFloat32Array = [0.75, 0.5, 0.25, 0.0]
const LEAVE: PackedFloat32Array = [0.25, 0.5, 0.75, 1.0]
const GAIN: PackedFloat32Array = [-1.0, -2.0, -1.0, 0.0]
const SPEND: PackedFloat32Array = [1.0, 2.0, 1.0, 0.0]
## The plays by number (`playing`).
enum Play { NONE, APPEAR, GAIN, SPEND, LEAVE }
## The key's pixels, drawn from the control's left: a ring bow, a shaft and two teeth (7 × 5).
const ICON_SIZE: Vector2i = Vector2i(7, 5)
const ICON_GAP: int = 2
## The number's font size (the panel's small font, as the coins).
const FONT_SIZE: int = 8
## The widest number it reserves room for, so it never reflows the row.
const WIDEST: String = "99"
## Gold and pickups are Spark (docs/STYLE.md, "UI"): the key's shades and its number's colour.
const SHADES: StringName = &"spark"

## The count drawn, and the count it was told last.
var _shown: int = 0
var _target: int = 0
## The play running (Play.NONE: at rest), its pose and the seconds in that pose.
var _play: int = Play.NONE
var _pose: int = 0
var _time: float = 0.0
## The colours (from the palette, once).
var _brass: PackedColorArray = PackedColorArray()
## The number's text for `_shown` (made as the count changes, never a frame).
var _text: String = ""


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brass = Palette.shades_of(SHADES)
	set_process(false)
	visible = false


func _ready() -> void:
	var font: Font = get_theme_default_font()
	var wide: float = font.get_string_size(WIDEST, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x if font != null else 10.0
	var tall: float = font.get_height(FONT_SIZE) if font != null else 9.0
	custom_minimum_size = Vector2(ICON_SIZE.x + ICON_GAP + ceilf(wide), maxf(ceilf(tall), ICON_SIZE.y))


## The party holds `count` keys. `at_once`: drawn as it stands (a restore), no play.
func set_count(count: int, at_once: bool) -> void:
	count = maxi(count, 0)
	_target = count
	if at_once:
		_play = Play.NONE
		_pose = 0
		_time = 0.0
		_show(count)
		_refresh()
		return
	if _play == Play.NONE:
		_start_next()
	_refresh()


## The count it shows now (the number drawn).
func shown_count() -> int:
	return _shown


## The play running (Play.NONE at rest).
func playing() -> int:
	return _play


## How far down (whole pixels; negative: up) the key and its number are drawn now.
func offset() -> int:
	match _play:
		Play.APPEAR:
			return roundi(APPEAR[_pose] * size_tall())
		Play.LEAVE:
			return roundi(LEAVE[_pose] * size_tall())
		Play.GAIN:
			return int(GAIN[_pose])
		Play.SPEND:
			return int(SPEND[_pose])
	return 0


## The height its plays slide by: its own (its least before it is laid out).
func size_tall() -> float:
	return maxf(size.y, custom_minimum_size.y)


## Step the play `delta` seconds on (each frame by `_process`; a test calls it itself).
func advance(delta: float) -> void:
	if _play == Play.NONE:
		return
	_time += delta
	while _play != Play.NONE and _time >= POSE_TIME:
		_time -= POSE_TIME
		_pose += 1
		if _pose >= POSE_COUNT:
			if _play == Play.LEAVE:
				_show(0)
			_play = Play.NONE
			_pose = 0
			_time = 0.0
			_start_next()
	_refresh()


func _process(delta: float) -> void:
	advance(delta)


## The play from the count shown to the count told, if they differ (the number changes now, but for
## a sinking, whose number stays until it is out of view).
func _start_next() -> void:
	if _shown == _target:
		return
	if _target == 0:
		_play = Play.LEAVE
	elif _shown == 0:
		_play = Play.APPEAR
	elif _target > _shown:
		_play = Play.GAIN
	else:
		_play = Play.SPEND
	_pose = 0
	_time = 0.0
	if _play != Play.LEAVE:
		_show(_target)


func _show(count: int) -> void:
	if count != _shown or _text == "":
		_shown = count
		_text = str(count)


func _refresh() -> void:
	visible = _shown > 0 or _play != Play.NONE
	set_process(_play != Play.NONE)
	queue_redraw()


func _draw() -> void:
	if _shown <= 0:
		return
	var tall: int = int(size_tall())
	var top: int = (tall - ICON_SIZE.y) / 2 + offset()
	var dark: Color = _brass[0]
	var mid: Color = _brass[1]
	var light: Color = _brass[2]
	# The bow: a 3 × 3 ring with its hole, then the shaft and two teeth hanging from its end.
	draw_rect(Rect2(0, top + 1, 3, 3), mid)
	draw_rect(Rect2(1, top + 2, 1, 1), dark)
	draw_rect(Rect2(1, top + 1, 1, 1), light)
	draw_rect(Rect2(3, top + 2, 4, 1), mid)
	draw_rect(Rect2(5, top + 3, 1, 1), dark)
	draw_rect(Rect2(6, top + 3, 1, 2), dark)
	var font: Font = get_theme_default_font()
	if font == null:
		return
	var baseline: float = float(offset()) + roundf((size_tall() + font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) / 2.0)
	draw_string(font, Vector2(ICON_SIZE.x + ICON_GAP, baseline), _text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, light)
