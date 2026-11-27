extends Control
## A thin meter line (owner, 2026-11-19): the corner panel's red health line and each staff row's
## blue mana line. A dark track the whole width, the fill from the left in `fill_color`, both in
## whole pixels and no taller than the control; drawn at the art's detail (`hud_art.gd`): the track
## sunk under an Outline art row, the fill with its shade along its bottom art row.
##
## Smooth (docs/STYLE.md): the fill never jumps. `set_value` sets where it is going, and each
## frame the drawn fill steps a third of the way there (at least one pixel), so a change of three
## pixels or more takes at least three frames and ends where it was going. The first value it is
## told after `reset` is drawn at once: a line that appears starts where it is.
##
## Display only: no input. It processes only while the fill is on its way, and allocates nothing.

## The HUD's health and mana colours, everywhere a bar or line of health or mana is drawn (the
## corner panel, the builder's and the inventory's bars), and the dark track behind a line. Health
## is a strong red, the one colour outside the palette, by the owner's word ("a very red line",
## 2026-11-19; docs/STYLE.md, "UI"); mana is the palette's Mana light, an ultramarine built to read
## apart from Player 1's blue.
const HudArt := preload("res://hud/widgets/hud_art.gd")

const HEALTH_COLOR: Color = Color("#e01a2b")
const MANA_COLOR: Color = Color("#6f86f0")
const TRACK_COLOR: Color = Color(0.07, 0.06, 0.1, 0.9)
## The shade under each fill, its bottom art row (ART4: drawn at the art's detail, `hud_art.gd`):
## health's in the Fire shadow, the nearest red of the palette; mana's in the Mana base under its light.
const HEALTH_SHADE: Color = Color("#8f2d2a")
const MANA_SHADE: Color = Color("#2c3aa8")

## The fill's colour, the shade along its bottom art row, and the track's behind it.
@export var fill_color: Color = HEALTH_COLOR
@export var fill_shade: Color = HEALTH_SHADE
@export var track_color: Color = TRACK_COLOR

## Drawn by another (`draw_onto`, over a cached panel's picture: `player_panel.gd`): its own
## `_draw` draws nothing, and a change of what it shows is told by `looks_changed`, not a redraw.
var live: bool = false:
	set(value):
		if value != live:
			live = value
			queue_redraw()
			looks_changed.emit()

## What `draw_onto` draws changed (while `live`).
signal looks_changed

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
	set_process(_shown != _target)
	if first and _shown != _target:
		_shown = _target
		set_process(false)
		_redraw()
	# Else only `step` changes what is drawn: a value told again (a mana regained every frame, a
	# pixel short of the next) draws nothing, so a cached panel is not drawn again for it.


## Forget the value: the next `set_value` is drawn at once.
func reset() -> void:
	_share = -1.0
	_shown = 0
	_target = 0
	set_process(false)
	_redraw()


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
	_redraw()
	if _shown == _target:
		set_process(false)


func _process(_delta: float) -> void:
	step()


func _draw() -> void:
	if not live:
		draw_onto(self, Vector2.ZERO)


## Draw the line on `target` with its top left at `at` (its own `_draw`, or a cached panel's live
## layer while `live`).
func draw_onto(target: CanvasItem, at: Vector2) -> void:
	var height: float = floorf(size.y)
	var width: float = floorf(size.x)
	if height <= 0.0 or width <= 0.0:
		return
	var track := Rect2(at.x, at.y, width, height)
	HudArt.trough(target, track, track_color)
	if _shown > 0:
		HudArt.line_fill(target, HudArt.under_lip(Rect2(at.x, at.y, float(_shown), height)), fill_color, fill_shade)


func _redraw() -> void:
	if live:
		looks_changed.emit()
	else:
		queue_redraw()


func _pixels(share: float) -> int:
	# Rounded up, so a sliver left still shows one pixel and only none is empty.
	# (Less a hair, so a share that is a whole pixel in floats does not round up past it.)
	return clampi(ceili(share * floorf(size.x) - 0.001), 0, floori(size.x))


func _on_resized() -> void:
	if _share >= 0.0:
		var had_width: bool = _target > 0 or _shown > 0
		_target = _pixels(_share)
		if not had_width:
			# Told its value before it had a width (a row shown after its mana came): it starts
			# where it is, as a line that appears does.
			_shown = _target
		_go()


func _go() -> void:
	set_process(_shown != _target)
	_redraw()
