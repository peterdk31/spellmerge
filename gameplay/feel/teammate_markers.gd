extends Node2D
## The markers at the screen's edge for teammates in none of this machine's views (owner,
## 2026-11-13; connected biomes CB6, decision 28). Each machine's camera holds only the wizards
## played on it (`party_camera.gd`, and the split screen's views, `split_camera.gd`), so a teammate
## played on another machine can be in none of them; a small arrow in that wizard's hat colour then
## sits at the screen's edge, on the line from the middle of the view nearest it (where that view's
## wizards are drawn: its anchor) to where that view would draw it, pointing the way. A downed
## teammate's pulses, with a ring round it: a revive needs someone to walk there. Pixel art at the
## art's detail (ART4: `PixelShape.arrows`, in the wizard's ramp, lit from the top-left), turning by
## WAYS whole steps and pulsing by whole looks.
## (The foes of a fight out of a view have smaller markers of their own, `foe_markers.gd`.)
##
## Only the wizards of seats that are not this machine's get one (`Frames.seats_here`); with no
## seat here the camera holds everyone, so nobody does. It marks a seat's own body, where a revive
## happens, not an actor the seat drives. It sits right at the screen's edge, corners too, and is
## drawn over the HUD's panels (owner, 2026-11-13: "should not take player huds into account"): Feel
## puts it on its own canvas layer over the HUD's (`LAYER`), in layout pixels (core/display/picture_grid.gd), so it is the same size
## whatever a view's zoom. View only, on Feel's real clock: nothing in the game reads it, and nothing
## is allocated after it is made.

const ActorsScript := preload("res://core/actors/actors.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")

## The canvas layer Feel puts it on: over the HUD's (`hud/panels/panels.tscn`, layer 10), so a
## marker shows over a player's panel. Feel knows nothing of the HUD but this number.
const LAYER: int = 11
## How far inside the screen's edge a marker sits, in layout pixels (core/display/picture_grid.gd).
const INSET: float = 18.0
## A wizard this far inside its view's cell (screen pixels) needs no marker yet.
const SHOWN_MARGIN: float = 4.0
## The arrowhead: from its tip back to its two barbs, half the width between them, and how far its
## back is cut in between them (so it reads as a way, not a triangle), in layout pixels (core/display/picture_grid.gd).
const LENGTH: float = 15.0
const HALF_WIDTH: float = 4.5
const NOTCH: float = 3.0
## The ways it is drawn pointing (ART4: pixel art at the art's detail turns by whole steps, never
## between two pixels): the nearest of WAYS to the way to its wizard.
const WAYS: int = 16
## A downed teammate's marker: pulses a second, how much bigger it grows at the top of a beat, its
## ring's radius (layout pixels) and band (art pixels), and the looks a beat steps through.
const PULSE_RATE: float = 2.0
const PULSE_GROW: float = 0.35
const RING_RADIUS: float = 12.0
const RING_BAND: int = 2
const PULSE_LOOKS: int = 3

## How many markers show now, and each one's seat, place (screen pixels), way (to its wizard),
## colour and whether its wizard is down. Sized once (a marker a seat).
var count: int = 0
var _seat: PackedInt32Array = PackedInt32Array()
var _at: PackedVector2Array = PackedVector2Array()
var _way: PackedVector2Array = PackedVector2Array()
var _colour: PackedColorArray = PackedColorArray()
var _down: PackedByteArray = PackedByteArray()
## Feel's clock, for the pulse.
var _clock: float = 0.0
## The heads baked at the art's detail (`PixelShape.arrows`), by pulse look then way, and the downed
## rings by pulse look; and the four tones a marker is drawn in, filled for each one drawn.
var _heads: Array[Array] = []
var _rings: Array[PixelShape] = []
var _tones: PackedColorArray = PackedColorArray([Palette.OUTLINE, Color.WHITE, Color.WHITE, Color.WHITE])


func _init() -> void:
	_seat.resize(ActorsScript.SEATS)
	_at.resize(ActorsScript.SEATS)
	_way.resize(ActorsScript.SEATS)
	_colour.resize(ActorsScript.SEATS)
	_down.resize(ActorsScript.SEATS)
	var art: float = 1.0 / PixelShape.ART_PIXEL
	for look in PULSE_LOOKS:
		var grow: float = 1.0 + PULSE_GROW * look / float(PULSE_LOOKS - 1)
		_heads.append(PixelShape.arrows(roundf(LENGTH * grow * art), roundf(HALF_WIDTH * grow * art), roundf(NOTCH * grow * art), WAYS))
		_rings.append(PixelShape.ring(2 * roundi(RING_RADIUS * grow * art), RING_BAND))


## Find the teammates in none of `views` (this machine's views: one picture, or the split
## screen's; `ScreenViews`): the wizards of the seats not in `seats_here` (a bit per seat played on
## this machine; 0: none get a marker). `clock` is Feel's, in real seconds.
func step(table: ActorsScript, seats_here: int, views: ScreenViewsScript, clock: float) -> void:
	var before: int = count
	count = 0
	_clock = clock
	if table != null and seats_here != 0 and views != null and views.count > 0:
		for seat in ActorsScript.SEATS:
			if seats_here & (1 << seat) != 0:
				continue
			var id: int = table.home_of_seat(seat)
			var body := table.node_of(id) as Node2D
			if body == null or not body.is_inside_tree():
				continue
			var world: Vector2 = body.global_position
			if views.view_showing(world, -SHOWN_MARGIN) >= 0:
				continue
			var view: int = _nearest_view(views, world)
			var from: Vector2 = views.anchor[view]
			var to: Vector2 = views.to_screen[view] * world - from
			var reach: float = views.reach_inside(view, from, to, INSET)
			_seat[count] = seat
			_at[count] = from + to * reach
			_way[count] = to.normalized()
			_colour[count] = ProjectileManagerScript.ramp_color(table.ramp_of(id))
			_down[count] = 1 if body is Actor and (body as Actor).is_downed() else 0
			count += 1
	if count > 0 or before > 0:
		queue_redraw()


## The view of `views` whose wizards stand nearest `world` (its anchor taken back into the world).
static func _nearest_view(views: ScreenViewsScript, world: Vector2) -> int:
	var best: int = 0
	var nearest: float = INF
	for view in views.count:
		var at: Vector2 = views.to_screen[view].affine_inverse() * views.anchor[view]
		var gap: float = at.distance_squared_to(world)
		if gap < nearest:
			nearest = gap
			best = view
	return best


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


## Its arrowhead at the art's detail, shaded in its wizard's ramp with the Outline round it (the
## nearest of WAYS); a downed wizard's pulses by whole looks (PULSE_LOOKS: bigger, its ring lit up
## to Bone's white heat at the top of a beat), never a scale between pixels or a fade.
func _draw() -> void:
	for at in count:
		var colour: Color = _colour[at]
		_tones[PixelShape.LIGHT] = PixelShape.light_of(colour)
		_tones[PixelShape.BASE] = colour
		_tones[PixelShape.SHADOW] = PixelShape.shadow_of(colour)
		var look: int = pulse_look(at)
		if _down[at] != 0:
			var ring: PixelShape = _rings[look]
			if look > 0:
				_tones[PixelShape.BASE] = Palette.WHITE_HOT if look == PULSE_LOOKS - 1 else _tones[PixelShape.LIGHT]
			ring.draw(self, _at[at], _tones)
			_tones[PixelShape.BASE] = colour
		var head: PixelShape = (_heads[look] as Array)[PixelShape.way_index(_way[at], WAYS)]
		head.draw(self, _at[at], _tones)


## The pulse look marker `at` is drawn in: 0 standing, up to PULSE_LOOKS - 1 at the top of a downed
## wizard's beat.
func pulse_look(at: int) -> int:
	if _down[at] == 0:
		return 0
	var beat: float = 0.5 + 0.5 * sin(_clock * TAU * PULSE_RATE)
	return clampi(int(beat * PULSE_LOOKS), 0, PULSE_LOOKS - 1)
