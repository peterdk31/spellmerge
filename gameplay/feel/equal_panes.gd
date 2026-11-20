extends RefCounted
## The panes of the equal split screen (the owner, 2026-11-19; `SplitScreenSetting.EQUAL`): pure
## geometry, nothing drawn. `split_camera.gd` lays its views on these panes in place of the Voronoi
## sites, and the same bisector cut (`voronoi_cells.gd`) between the panes' middles gives exactly
## the panes, so the drawing and every reader of `ScreenViews` work unchanged.
##
## A seat's pane is where its corner panel is (the HUD's P1 top left, P2 top right, P3 bottom
## left, P4 bottom right), so each player's panel, builder and menus sit in their own pane:
## - **Two seats:** the screen's halves. Left and right when their panels are on either side (the
##   usual P1 and P2); top and bottom when both are on one side (P1 and P3, or P2 and P4), so
##   neither panel stands in the other's pane.
## - **Three or four seats:** the 2×2 grid of quarters, each seat its own corner's. With three, the
##   fourth quarter is a blank: no view's, the void's dark (`blank_site`).
## - **One seat** (or none): the whole screen.

const ActorsScript := preload("res://core/actors/actors.gd")


## The number of seats in `present` (a bit a seat).
static func count_of(present: int) -> int:
	var n: int = 0
	var mask: int = present
	while mask != 0:
		mask &= mask - 1
		n += 1
	return n


## Seat `seat`'s pane among the seats `present` on a screen of `screen` pixels (screen pixels);
## an empty rect for a seat not present.
static func pane_of(seat: int, present: int, screen: Vector2) -> Rect2:
	if present & (1 << seat) == 0:
		return Rect2()
	var n: int = count_of(present)
	if n <= 1:
		return Rect2(Vector2.ZERO, screen)
	var column: int = seat % 2
	var row: int = seat >> 1
	if n == 2:
		var other: int = 0
		for s in ActorsScript.SEATS:
			if s != seat and present & (1 << s) != 0:
				other = s
		if column != other % 2:
			return Rect2(Vector2(screen.x * 0.5 * column, 0.0), Vector2(screen.x * 0.5, screen.y))
		var top: bool = row < (other >> 1)
		return Rect2(Vector2(0.0, 0.0 if top else screen.y * 0.5), Vector2(screen.x, screen.y * 0.5))
	return _quarter(seat, screen)


## The middle of seat `seat`'s pane (where its view draws its wizard and its anchor stands).
static func site_of(seat: int, present: int, screen: Vector2) -> Vector2:
	return pane_of(seat, present, screen).get_center()


## The seat whose quarter is the blank with three seats `present` (no view's), or -1 (no blank).
static func blank_seat(present: int) -> int:
	if count_of(present) != 3:
		return -1
	for seat in ActorsScript.SEATS:
		if present & (1 << seat) == 0:
			return seat
	return -1


## The middle of the blank quarter with three seats `present`, or Vector2.INF (none).
static func blank_site(present: int, screen: Vector2) -> Vector2:
	var seat: int = blank_seat(present)
	return quarter_site(seat, screen) if seat >= 0 else Vector2.INF


## The middle of seat `seat`'s quarter of the screen (where a blank of that quarter settles).
static func quarter_site(seat: int, screen: Vector2) -> Vector2:
	return _quarter(seat, screen).get_center()


## Where a blank's site rests while it is not shown: past its quarter's corner of the screen, so far
## that no point of the screen is nearer it than any view's anchor (half again the screen's
## diagonal past the corner); it moves in from there and back out, so the blank grows and shrinks
## from its corner, never appearing at once.
static func blank_rest(seat: int, screen: Vector2) -> Vector2:
	var corner := Vector2(screen.x * float(seat % 2), screen.y * float(seat >> 1))
	return corner + (corner - screen * 0.5) * 3.0


## Seat `seat`'s quarter of the screen (its corner's).
static func _quarter(seat: int, screen: Vector2) -> Rect2:
	var half: Vector2 = screen * 0.5
	return Rect2(Vector2(half.x * float(seat % 2), half.y * float(seat >> 1)), half)
