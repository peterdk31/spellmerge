extends Control
## The mini-preview of the builder (M2 part 17): the shot pattern of one spell, drawn by code
## in the element's tint: a fan or a single line of shots, a ring, an orbit circle, a still
## rune dot or a ray. It draws only what `show_view` gives it (a `Spells.builder_view`),
## redraws only when that changes and never creates anything per frame.

const MAX_DRAWN: int = 24
const MARGIN: float = 6.0
const WIZARD_RADIUS: float = 2.0
const SHOT_RADIUS: float = 1.5
const OUTLINE: Color = Color("#14121f")
const WIZARD: Color = Color("#d4d0e0")

var _pattern: StringName = &""
var _shots: int = 1
var _spread: float = 0.0
var _tint: Color = Color.WHITE
var _pierce: int = 0


## Draw the pattern of a `Spells.builder_view`; one with no spell draws only the wizard.
func show_view(view: Dictionary) -> void:
	if bool(view.get("shown", false)):
		_pattern = StringName(str(view["pattern"]))
		_shots = clampi(int(view["shots"]), 1, MAX_DRAWN)
		_spread = float(view["spread"])
		_tint = view["tint"] as Color
		_pierce = int(view["pierce"])
	else:
		_pattern = &""
	queue_redraw()


## What is drawn, in words, for tests: "none", "fan", "ring", "orbit", "rune" or "ray".
func pattern() -> String:
	return String(_pattern) if _pattern != &"" else "none"


func _draw() -> void:
	var middle: float = size.y * 0.5
	var origin := Vector2(MARGIN, middle)
	var reach: float = maxf(size.x - MARGIN * 2.0, 1.0)
	match _pattern:
		&"fan", &"ring":
			_draw_fan(origin, reach)
		&"ray":
			draw_line(origin, origin + Vector2(reach, 0.0), _tint, 2.0)
			for notch in _pierce:
				var at: float = reach * float(notch + 1) / float(_pierce + 2)
				draw_line(origin + Vector2(at, -3.0), origin + Vector2(at, 3.0), WIZARD, 1.0)
		&"orbit":
			var ring: float = minf(middle - 2.0, reach * 0.5)
			var centre: Vector2 = origin + Vector2(ring + 8.0, 0.0)
			draw_arc(centre, ring, 0.0, TAU, 24, _tint, 1.0)
			for shot in _shots:
				var angle: float = TAU * float(shot) / float(_shots)
				draw_circle(centre + Vector2.from_angle(angle) * ring, SHOT_RADIUS + 0.5, _tint)
		&"rune":
			var spot: Vector2 = origin + Vector2(reach * 0.5, 0.0)
			draw_circle(spot, 4.0, _tint)
			draw_arc(spot, 6.0, 0.0, TAU, 16, WIZARD, 1.0)
	draw_circle(origin, WIZARD_RADIUS + 1.0, OUTLINE)
	draw_circle(origin, WIZARD_RADIUS, WIZARD)


## Straight shots: the fan the spell spreads over, as lines with a dot at the end; the "ring"
## pattern (a spread of 360 degrees) is a ring around the wizard.
func _draw_fan(origin: Vector2, reach: float) -> void:
	var ring: bool = _pattern == &"ring"
	var length: float = minf(reach, size.y * 0.5 - 2.0) if ring else reach
	for shot in _shots:
		var angle: float = 0.0
		if ring:
			angle = TAU * float(shot) / float(_shots)
		elif _shots > 1:
			angle = deg_to_rad(_spread) * (float(shot) / float(_shots - 1) - 0.5)
		var tip: Vector2 = origin + Vector2.from_angle(angle) * length
		draw_line(origin, tip, _tint, 1.0)
		draw_circle(tip, SHOT_RADIUS, _tint)
