extends Control
## A thin meter line (owner, 2026-11-19): the corner panel's red health line and each staff row's
## blue mana line. A dark track the whole width, the fill from the left in `fill_color`, both in
## whole pixels and no taller than the control.
##
## Smooth (docs/STYLE.md): the fill never jumps. `set_value` sets where it is going, and each
## frame the drawn fill steps a third of the way there (at least one pixel), so a change of three
## pixels or more takes at least three frames and ends where it was going. The first value it is
## told after `reset` is drawn at once: a line that appears starts where it is.
##
## Display only: no input. It processes only while the fill is on its way, and allocates nothing.

## The HUD's health and mana colours, everywhere a health or a mana is drawn: a strong red and a
## clear blue (owner, 2026-11-19), and the dark track behind a line.
const HEALTH_COLOR: Color = Color("#e01a2b")
const MANA_COLOR: Color = Color("#3d8bff")
const TRACK_COLOR: Color = Color(0.07, 0.06, 0.1, 0.9)

## The fill's colour, and the track's behind it.
@export var fill_color: Color = HEALTH_COLOR
@export var track_color: Color = TRACK_COLOR

## The share of the width the fill goes to, 0 to 1; -1 before any value.
var _share: float = -1.0
## The drawn fill and the fill it goes to, in whole pixels.
var _shown: int = 0
var _target: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func _ready() -> void:
	resized.connect(_on_resized)


## Show `value` of `most` (a `most` of 0 or less shows an empty line).
func set_value(value: float, most: float) -> void:
	var share: float = clampf(value / most, 0.0, 1.0) if most > 0.0 else 0.0
	var first: bool = _share < 0.0
	_share = share
	_target = _pixels(share)
	if first:
		_shown = _target
	_go()


## Forget the value: the next `set_value` is drawn at once.
func reset() -> void:
	_share = -1.0
	_shown = 0
	_target = 0
	set_process(false)
	queue_redraw()


## The share of the width the value is, 0 to 1 (-1 before any value; for tests).
func share() -> float:
	return _share


## The fill drawn now and the fill it goes to, in pixels (for tests and screenshots).
func shown_pixels() -> int:
	return _shown


func target_pixels() -> int:
	return _target


## One frame of the fill's way to its target (called by `_process`; tests call it directly).
func step() -> void:
	var gap: int = _target - _shown
	if gap == 0:
		set_process(false)
		return
	var move: int = maxi(1, ceili(absi(gap) / 3.0))
	_shown += mini(move, absi(gap)) * signi(gap)
	queue_redraw()
	if _shown == _target:
		set_process(false)


func _process(_delta: float) -> void:
	step()


func _draw() -> void:
	var height: float = floorf(size.y)
	var width: float = floorf(size.x)
	if height <= 0.0 or width <= 0.0:
		return
	draw_rect(Rect2(0.0, 0.0, width, height), track_color)
	if _shown > 0:
		draw_rect(Rect2(0.0, 0.0, float(_shown), height), fill_color)


func _pixels(share: float) -> int:
	# Rounded up, so a sliver left still shows one pixel and only none is empty.
	# (Less a hair, so a share that is a whole pixel in floats does not round up past it.)
	return clampi(ceili(share * floorf(size.x) - 0.001), 0, floori(size.x))


func _on_resized() -> void:
	if _share >= 0.0:
		_target = _pixels(_share)
		_go()


func _go() -> void:
	set_process(_shown != _target)
	queue_redraw()
