class_name ScreenViews
extends RefCounted
## What each part of the screen shows while it is split (connected biomes CB6,
## docs/milestones/connected-biomes.md, decision 27): up to VIEWS_MOST views, each a convex cell of
## the screen (screen pixels, the root viewport's), the world drawn in it through its own transform
## (`to_screen`: world pixels to screen pixels), the seats it holds (a bit a seat) and its anchor
## (where those seats' middle is drawn, screen pixels). The cells cover the screen without overlap.
##
## Feel's split screen (gameplay/feel/split_screen.gd) is the one writer: it publishes the views on
## the root viewport while the screen is split (`publish`), and takes them back when it merges
## (`withdraw`). What reads the picture by the screen reads them through `on(viewport)`, and only
## while it is split: the mouse's place in the world (Frames), the item hints (the HUD), whether a
## body is on screen (its looks). With one view nothing is published and the viewport's own canvas
## transform (its camera) says what is shown, as without a split. View only: nothing in the
## simulation reads it, and nothing is allocated after it is made.

## The most views (one a seat).
const VIEWS_MOST: int = 4
## The most corners a cell has (the screen's four, cut by up to three neighbours' bisectors).
const CORNERS_MOST: int = 8
## The viewport metadata the published views are kept under.
const META: StringName = &"screen_views"

## How many views there are now (0: none yet).
var count: int = 0
## The screen's size (screen pixels).
var screen: Vector2 = Vector2.ZERO
## By view: the seats it holds (a bit a seat), world to screen, its anchor (screen pixels).
var seats: PackedInt32Array = PackedInt32Array()
var to_screen: Array[Transform2D] = []
var anchor: PackedVector2Array = PackedVector2Array()
## By view: its cell's corners (`corners(view)` of them from `view * CORNERS_MOST`), clockwise on
## screen (y points down).
var cell_points: PackedVector2Array = PackedVector2Array()
var cell_counts: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	seats.resize(VIEWS_MOST)
	to_screen.resize(VIEWS_MOST)
	anchor.resize(VIEWS_MOST)
	cell_points.resize(VIEWS_MOST * CORNERS_MOST)
	cell_counts.resize(VIEWS_MOST)


## The views published on `viewport` (`publish`), or null while it shows one picture.
static func on(viewport: Viewport) -> ScreenViews:
	if viewport == null or not viewport.has_meta(META):
		return null
	return viewport.get_meta(META) as ScreenViews


## Publish `views` on `viewport` (Feel's split screen, while the screen is split).
static func publish(viewport: Viewport, views: ScreenViews) -> void:
	if viewport != null:
		viewport.set_meta(META, views)


## Nothing published on `viewport` any more (one picture again).
static func withdraw(viewport: Viewport) -> void:
	if viewport != null and viewport.has_meta(META):
		viewport.remove_meta(META)


## One view of the whole screen `screen_size` showing the world through `transform`, with the
## seats `held` and its anchor at the screen's middle (a picture that is not split).
func set_single(screen_size: Vector2, transform: Transform2D, held: int) -> void:
	screen = screen_size
	count = 1
	seats[0] = held
	to_screen[0] = transform
	anchor[0] = screen_size * 0.5
	cell_points[0] = Vector2.ZERO
	cell_points[1] = Vector2(screen_size.x, 0.0)
	cell_points[2] = screen_size
	cell_points[3] = Vector2(0.0, screen_size.y)
	cell_counts[0] = 4


## The number of corners of view `view`'s cell.
func corners(view: int) -> int:
	return cell_counts[view]


## Set corner `at` of view `view`'s cell to `point` (screen pixels), and how many it has (the
## writer's; written in place, a member of its own, so nothing is copied).
func set_corner(view: int, at: int, point: Vector2) -> void:
	cell_points[view * CORNERS_MOST + at] = point


func set_corners(view: int, n: int) -> void:
	cell_counts[view] = clampi(n, 0, CORNERS_MOST)


## Set view `view`: the seats it holds, world to screen, and its anchor (screen pixels).
func set_view(view: int, held: int, transform: Transform2D, at: Vector2) -> void:
	seats[view] = held
	to_screen[view] = transform
	anchor[view] = at


## Corner `at` of view `view`'s cell (screen pixels).
func corner(view: int, at: int) -> Vector2:
	return cell_points[view * CORNERS_MOST + at]


## True while the screen shows more than one view.
func is_split() -> bool:
	return count > 1


## The view whose cell holds the screen point `point`, or -1 (off the screen).
func view_at(point: Vector2) -> int:
	for view in count:
		if cell_holds(view, point, 0.0):
			return view
	return -1


## The view holding seat `seat`, or -1.
func view_of_seat(seat: int) -> int:
	for view in count:
		if seats[view] & (1 << seat) != 0:
			return view
	return -1


## True when view `view`'s cell holds the screen point `point`, or comes within `margin` screen
## pixels of it (a negative margin: that far inside).
func cell_holds(view: int, point: Vector2, margin: float) -> bool:
	var n: int = cell_counts[view]
	if n < 3:
		return false
	var base: int = view * CORNERS_MOST
	for i in n:
		var a: Vector2 = cell_points[base + i]
		var b: Vector2 = cell_points[base + (i + 1) % n]
		var edge: Vector2 = b - a
		var length: float = edge.length()
		if length <= 0.0:
			continue
		# Clockwise on screen (y down): the inside is to the edge's right, where the cross is >= 0.
		if edge.cross(point - a) / length < -margin:
			return false
	return true


## The view that shows the world point `world` in its own cell (`margin` screen pixels to spare,
## as `cell_holds`), or -1 when none does.
func view_showing(world: Vector2, margin: float = 0.0) -> int:
	for view in count:
		if cell_holds(view, to_screen[view] * world, margin):
			return view
	return -1


## The box round the parts of the world the views show (world pixels): each cell's corners taken
## back into the world. Empty with no view.
func world_box() -> Rect2:
	var low := Vector2.INF
	var high := -Vector2.INF
	for view in count:
		var back: Transform2D = to_screen[view].affine_inverse()
		var base: int = view * CORNERS_MOST
		for i in cell_counts[view]:
			var at: Vector2 = back * cell_points[base + i]
			low = low.min(at)
			high = high.max(at)
	if low.x > high.x:
		return Rect2()
	return Rect2(low, high - low)
