extends RefCounted
## Where each seat's corner panel, builder, inventory and reward menu sit on this machine's screen
## (the owner, 2026-11-20): a spot a seat, `quarter * 2 + inner` (`hud_corners_changed`, sent by
## Feel while the equal split lays its panes: gameplay/feel/equal_panes.gd), a quarter of the screen
## for the menus and that quarter's outer side (the screen's edge) or inner side (toward the middle
## line) for the panel, at the screen's top or bottom edge by the quarter's row. Unsplit each seat's
## is its own corner's (P1 top left, P2 top right, P3 bottom left, P4 bottom right), as the panels'
## scene lays them.
##
## **Smooth** (docs/STYLE.md): a seat whose spot changes slides there by whole pixels, a third of the
## way a frame (at least 1, at most SLIDE_MOST pixels), so a move of three pixels or more takes at
## least three frames; once there it follows its spot at once again (a panel growing a row, the
## window's size). Pure: `panels.gd` hands it the view's size and each panel's size every frame and
## places the nodes. Nothing allocated after it is made.

const SEATS: int = 4
## The room between a panel and the screen's edge, or its quarter's inner side (view pixels; the
## panels' scene's offsets).
const EDGE: float = 4.0
## The most a slide moves in one frame (view pixels).
const SLIDE_MOST: float = 16.0

## By seat: its spot now (the last told).
var spots: PackedInt32Array = PackedInt32Array()
## By seat: its panel's top left and its quarter's top left as shown now (whole view pixels).
var _panel_at: PackedVector2Array = PackedVector2Array()
var _quarter_at: PackedVector2Array = PackedVector2Array()
## By seat: sliding to a new spot (1), or on its spot (0).
var _sliding: PackedByteArray = PackedByteArray()
## By seat: shown at least once (a seat's first frame is on its spot).
var _placed: PackedByteArray = PackedByteArray()


func _init() -> void:
	spots.resize(SEATS)
	_panel_at.resize(SEATS)
	_quarter_at.resize(SEATS)
	_sliding.resize(SEATS)
	_placed.resize(SEATS)
	for seat in SEATS:
		spots[seat] = home_spot(seat)


## Seat `seat`'s spot unsplit: its own corner's quarter, its outer side.
static func home_spot(seat: int) -> int:
	return seat * 2


## The spots from `hud_corners_changed` (by seat); a seat whose spot changed slides to it.
func set_spots(corners: PackedInt32Array) -> void:
	for seat in mini(SEATS, corners.size()):
		var spot: int = clampi(corners[seat], 0, SEATS * 2 - 1)
		if spot != spots[seat]:
			spots[seat] = spot
			_sliding[seat] = 1


## A frame on: seat `seat`'s panel of `panel_size` on a view of `view` pixels moves on toward its
## spot (slid, or on it), and its quarter with it.
func step(seat: int, view: Vector2, panel_size: Vector2) -> void:
	var panel: Vector2 = panel_spot(spots[seat], view, panel_size)
	var quarter: Vector2 = quarter_origin(spots[seat] >> 1, view)
	if _placed[seat] == 0 or _sliding[seat] == 0:
		_panel_at[seat] = panel
		_quarter_at[seat] = quarter
		_placed[seat] = 1
		_sliding[seat] = 0
		return
	_panel_at[seat] = slide(_panel_at[seat], panel)
	_quarter_at[seat] = slide(_quarter_at[seat], quarter)
	if _panel_at[seat] == panel and _quarter_at[seat] == quarter:
		_sliding[seat] = 0


## Seat `seat`'s panel's top left now (view pixels).
func panel_at(seat: int) -> Vector2:
	return _panel_at[seat]


## The top left of seat `seat`'s quarter now (view pixels): where its builder, inventory and reward
## menu lay themselves out.
func quarter_at(seat: int) -> Vector2:
	return _quarter_at[seat]


## True while seat `seat` slides to a new spot.
func is_sliding(seat: int) -> bool:
	return _sliding[seat] != 0


## The top left of a panel of `size` at spot `spot` on a view of `view` pixels (whole pixels).
static func panel_spot(spot: int, view: Vector2, size: Vector2) -> Vector2:
	var quarter: int = spot >> 1
	var inner: bool = spot & 1 != 0
	var right_of_quarter: bool = (quarter % 2 == 1) != inner
	var half_x: float = view.x * 0.5
	var low_x: float = half_x * float(quarter % 2)
	var high_x: float = low_x + half_x
	var x: float = high_x - EDGE - size.x if right_of_quarter else low_x + EDGE
	var y: float = view.y - EDGE - size.y if quarter >= 2 else EDGE
	return Vector2(x, y).round()


## The top left of quarter `quarter` of a view of `view` pixels (its halves floored, as the builder
## lays its quarter).
static func quarter_origin(quarter: int, view: Vector2) -> Vector2:
	var half: Vector2 = (view * 0.5).floor()
	return Vector2(half.x * float(quarter % 2), half.y * float(quarter >> 1))


## `from` moved toward `to` by whole pixels: a third of the way, at least 1 and at most SLIDE_MOST.
static func slide(from: Vector2, to: Vector2) -> Vector2:
	var way: Vector2 = to - from
	var length: float = way.length()
	if length <= 1.0:
		return to
	var step: float = clampf(ceilf(length / 3.0), 1.0, SLIDE_MOST)
	if step >= length:
		return to
	var next: Vector2 = (from + way * (step / length)).round()
	return to if next == from else next
