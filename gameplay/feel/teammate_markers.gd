extends Node2D
## The markers at the picture's edge for teammates out of it (owner, 2026-11-13). Each machine's
## camera holds only the wizards played on it (`party_camera.gd`), so a teammate played on another
## machine can be out of the picture; a small arrow in that wizard's hat colour then sits at the
## picture's edge, on the line from its middle to the wizard, pointing the way. A downed teammate's
## pulses, with a ring round it: a revive needs someone to walk there.
##
## Only the wizards of seats that are not this machine's get one (`Frames.seats_here`); with no
## seat here the camera holds everyone, so nobody does. It marks a seat's own body, where a revive
## happens, not an actor the seat drives. A child of Feel, top level (world space), drawn over
## everything Feel draws and the same size on screen whatever the camera's zoom. View only, on
## Feel's real clock: nothing in the game reads it, and nothing is allocated after it is made.

const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## Over the damage numbers.
const Z: int = 23
## How far inside the picture's edge a marker sits, in screen pixels.
const INSET: float = 18.0
## A wizard this far inside the picture's edge (screen pixels) needs no marker yet.
const SHOWN_MARGIN: float = 4.0
## The part of each corner of the screen a marker keeps out of, in screen pixels: the HUD's corner
## panels are there (a player's bars and staff rows, and the word of a seat played on another
## machine, hud/panels) and would hide it. A marker that
## would sit in a corner sits at this part's inner corner instead, still pointing at its wizard.
## Feel knows nothing of the HUD but this size.
const CORNER: Vector2 = Vector2(124.0, 104.0)
## The arrowhead: from its tip back to its two barbs, half the width between them, and how far its
## back is cut in between them (so it reads as a way, not a triangle), in screen pixels.
const LENGTH: float = 15.0
const HALF_WIDTH: float = 4.5
const NOTCH: float = 3.0
## The dark edge round the arrowhead, and its colour (the damage numbers' outline).
const OUTLINE: float = 3.0
const OUTLINE_COLOR: Color = Color(0.078, 0.071, 0.122, 1.0)
## A downed teammate's marker: pulses a second, how much bigger it grows, and its ring's radius.
const PULSE_RATE: float = 2.0
const PULSE_GROW: float = 0.35
const RING_RADIUS: float = 12.0

## How many markers show now, and each one's seat, place (world), way (to its wizard), colour and
## whether its wizard is down. Sized once (a marker a seat).
var count: int = 0
var _seat: PackedInt32Array = PackedInt32Array()
var _at: PackedVector2Array = PackedVector2Array()
var _way: PackedVector2Array = PackedVector2Array()
var _colour: PackedColorArray = PackedColorArray()
var _down: PackedByteArray = PackedByteArray()
## World pixels a screen pixel is now (1 / the camera's zoom), and Feel's clock, for the pulse.
var _scale: float = 1.0
var _clock: float = 0.0
## One half of the arrowhead (a triangle) and its whole edge (closed), filled for each marker drawn.
var _points: PackedVector2Array = PackedVector2Array()
var _outline: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	_seat.resize(ActorsScript.SEATS)
	_at.resize(ActorsScript.SEATS)
	_way.resize(ActorsScript.SEATS)
	_colour.resize(ActorsScript.SEATS)
	_down.resize(ActorsScript.SEATS)
	_points.resize(3)
	_outline.resize(5)


func _ready() -> void:
	top_level = true
	z_index = Z


## Find the teammates out of `picture` (the part of the world on screen, `PartyCamera.visible_rect`)
## at the camera's `zoom`: the wizards of the seats not in `seats_here` (a bit per seat played on
## this machine; 0: none get a marker). `clock` is Feel's, in real seconds.
func step(table: ActorsScript, seats_here: int, picture: Rect2, zoom: float, clock: float) -> void:
	var before: int = count
	count = 0
	_clock = clock
	if table != null and seats_here != 0 and picture.has_area() and zoom > 0.0:
		_scale = 1.0 / zoom
		var inner: Rect2 = picture.grow(-SHOWN_MARGIN * _scale)
		var half: Vector2 = picture.size * 0.5 - Vector2.ONE * (INSET * _scale)
		var middle: Vector2 = picture.get_center()
		for seat in ActorsScript.SEATS:
			if seats_here & (1 << seat) != 0:
				continue
			var id: int = table.home_of_seat(seat)
			var body := table.node_of(id) as Node2D
			if body == null or not body.is_inside_tree() or inner.has_point(body.global_position):
				continue
			var to: Vector2 = body.global_position - middle
			var reach: float = INF
			if absf(to.x) > 0.0:
				reach = minf(reach, half.x / absf(to.x))
			if absf(to.y) > 0.0:
				reach = minf(reach, half.y / absf(to.y))
			_seat[count] = seat
			_at[count] = _out_of_corners(middle + to * minf(reach, 1.0), picture)
			_way[count] = to.normalized()
			_colour[count] = ProjectileManagerScript.ramp_color(table.ramp_of(id))
			_down[count] = 1 if body is Actor and (body as Actor).is_down() else 0
			count += 1
	if count > 0 or before > 0:
		queue_redraw()


## `at` (world, on the edge of `picture`), moved out of the screen's corners (CORNER): one in a
## corner goes to that corner part's inner corner.
func _out_of_corners(at: Vector2, picture: Rect2) -> Vector2:
	var corner: Vector2 = CORNER * _scale
	# How far it is from the nearest side on each axis.
	var from_side: Vector2 = (at - picture.position).min(picture.end - at)
	if from_side.x >= corner.x or from_side.y >= corner.y:
		return at
	var middle: Vector2 = picture.get_center()
	var x: float = picture.position.x + corner.x if at.x < middle.x else picture.end.x - corner.x
	var y: float = picture.position.y + corner.y if at.y < middle.y else picture.end.y - corner.y
	return Vector2(x, y)


## The seat of marker `at` (0 to `count` - 1), where it is (world), the way it points, and whether
## its wizard is down.
func seat_of(at: int) -> int:
	return _seat[at]


func position_of(at: int) -> Vector2:
	return _at[at]


func way_of(at: int) -> Vector2:
	return _way[at]


func is_down(at: int) -> bool:
	return _down[at] != 0


func _draw() -> void:
	for at in count:
		var size: float = _scale
		var colour: Color = _colour[at]
		if _down[at] != 0:
			var beat: float = 0.5 + 0.5 * sin(_clock * TAU * PULSE_RATE)
			size *= 1.0 + PULSE_GROW * beat
			draw_arc(_at[at], RING_RADIUS * size, 0.0, TAU, 24, OUTLINE_COLOR, 3.0 * _scale)
			draw_arc(_at[at], RING_RADIUS * size, 0.0, TAU, 24, colour.lerp(Color.WHITE, beat), 1.0 * _scale)
		var way: Vector2 = _way[at]
		var side: Vector2 = Vector2(-way.y, way.x) * (HALF_WIDTH * size)
		var tip: Vector2 = _at[at] + way * (LENGTH * 0.5 * size)
		var back: Vector2 = _at[at] - way * (LENGTH * 0.5 * size)
		var notch: Vector2 = back + way * (NOTCH * size)
		_outline[0] = tip
		_outline[1] = back + side
		_outline[2] = notch
		_outline[3] = back - side
		_outline[4] = tip
		draw_polyline(_outline, OUTLINE_COLOR, OUTLINE * _scale)
		_points[0] = tip
		_points[1] = back + side
		_points[2] = notch
		draw_colored_polygon(_points, colour)
		_points[1] = notch
		_points[2] = back - side
		draw_colored_polygon(_points, colour)
