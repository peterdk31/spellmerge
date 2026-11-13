extends RefCounted
## The party's camera, as it is drawn: every drawn frame it finds the box round the wizards of
## this machine's seats (`look`: each seat's own body and the actor the seat drives now, so a
## possessed body and its puppet both stay in view; the downed too, so a body can be found), fits
## a view round it (CAMERA_MARGIN to spare, zoomed between MAX_ZOOM and MIN_ZOOM and never past
## the camera's limits, the room's) and eases the world's camera towards it on real time, so a
## join or a dodge never jerks the picture.
##
## **Each machine frames its own seats** (owner, 2026-11-13): players on one screen must share it,
## so the camera zooms out to hold them all, but machines playing together online each have a
## screen, and each frames only the wizards played on it. Which seats those are is the frames
## service's to say (`Frames.seats_here`); with none (a recording played, a machine still waiting
## for its seat) it frames everyone. Feel owns it and steps it; it is view only: nothing in the
## simulation reads the camera or knows which machine it runs on.
##
## While it eases it also zooms out as far as needed to keep the party's box in the picture, so
## nobody of this machine leaves it while the camera catches up (the view is fitted for where the
## camera is heading, the box is checked against where it is). It keeps to the camera's limits,
## never showing past them. After `room_entered`, or on another camera, it jumps to the view
## instead of easing. Shake (Feel) moves only the camera's `offset`, so the two do not clash.

const ActorsScript := preload("res://core/actors/actors.gd")

## Space kept between the outermost wizards and the edge of the view, in pixels.
const CAMERA_MARGIN: float = 48.0
## The view never zooms in past 1 or out past 0.5 (Camera2D zoom: smaller sees more).
const MAX_ZOOM: float = 1.0
const MIN_ZOOM: float = 0.5
## How fast the camera eases to its target, per second (higher is snappier).
const FOLLOW_SPEED: float = 6.0
## A camera limit this wide or more counts as "no limit" (Godot's default is 10,000,000).
const LIMIT_UNSET: float = 1000000.0

## The camera being driven (Feel's current one), or null.
var camera: Camera2D = null
## Where the camera is heading, and its zoom there (1 = no zoom).
var target_position: Vector2 = Vector2.ZERO
var target_zoom: float = 1.0

## The box round this machine's wizards, kept in the picture while it eases; a negative size
## before the first one found.
var _party: Rect2 = Rect2(Vector2.ZERO, -Vector2.ONE)
## Jump to the next box found (a new room), instead of easing.
var _snap_next: bool = true

## Drive `node` from now on (the viewport's current camera). Another camera (a new world's) is put
## on the target at once rather than eased from wherever it was made.
func follow(node: Camera2D) -> void:
	if node == camera:
		return
	camera = node
	snap()


## A new room: its first view is jumped to.
func room_entered() -> void:
	_party = Rect2(Vector2.ZERO, -Vector2.ONE)
	_snap_next = true


## Find this machine's wizards in the actor table `table` and head for the view that holds them.
## `seats` has a bit per seat played here (`Frames.seats_here`); with none of them standing in
## the world (0: nobody plays here; or their wizards are not made yet) everyone is held.
func look(table: ActorsScript, seats: int) -> void:
	if table == null:
		return
	var party: Rect2 = party_box(table, seats)
	if party.size.x < 0.0 and seats != 0:
		party = party_box(table, 0)
	if party.size.x >= 0.0:
		hold(party)


## Head for the view that holds the box `party` (world pixels).
func hold(party: Rect2) -> void:
	_party = party
	_aim()
	if _snap_next and _valid():
		_snap_next = false
		snap()


## The box round the wizards of `seats` (a bit per seat; 0 for every seat): each seat's own body
## and the actor it drives now. A negative size with none in the world.
static func party_box(table: ActorsScript, seats: int) -> Rect2:
	var low := Vector2.INF
	var high := -Vector2.INF
	for seat in ActorsScript.SEATS:
		if seats != 0 and seats & (1 << seat) == 0:
			continue
		for driven in 2:
			var id: int = table.actor_of_seat(seat) if driven == 1 else table.home_of_seat(seat)
			var body := table.node_of(id) as Node2D
			if body == null or not body.is_inside_tree():
				continue
			low = low.min(body.global_position)
			high = high.max(body.global_position)
	if low.x > high.x:
		return Rect2(Vector2.ZERO, -Vector2.ONE)
	return Rect2(low, high - low)


## Put the camera on its target at once.
func snap() -> void:
	if not _valid() or _party.size.x < 0.0:
		return
	_aim()
	camera.zoom = Vector2(target_zoom, target_zoom)
	camera.position = _clamp_centre(target_position, target_zoom)


## Ease the camera towards its target by `delta` seconds of real time.
func step(delta: float) -> void:
	if not _valid() or _party.size.x < 0.0 or delta <= 0.0:
		return
	_aim()
	var weight: float = 1.0 - exp(-FOLLOW_SPEED * delta)
	var at: Vector2 = camera.position.lerp(target_position, weight)
	var zoom: float = lerpf(camera.zoom.x, target_zoom, weight)
	zoom = _zoom_to_hold(at, zoom)
	camera.zoom = Vector2(zoom, zoom)
	camera.position = _clamp_centre(at, zoom)


## The part of the world the camera shows now (limits applied).
func visible_rect() -> Rect2:
	if not _valid():
		return Rect2()
	var size: Vector2 = _picture() / camera.zoom.x
	var centre: Vector2 = _clamp_centre(camera.position, camera.zoom.x)
	return Rect2(centre - size * 0.5, size)


## The target from the party's box: zoomed out until the box fits with CAMERA_MARGIN to spare
## (between MAX_ZOOM and MIN_ZOOM, and never a picture bigger than the room), centred on the box
## and pushed in from the room's edge.
func _aim() -> void:
	if not _valid():
		return
	var picture: Vector2 = _picture()
	var need: Vector2 = _party.size + Vector2.ONE * (CAMERA_MARGIN * 2.0)
	var floor_zoom: float = maxf(MIN_ZOOM, _min_zoom())
	target_zoom = clampf(minf(picture.x / need.x, picture.y / need.y), floor_zoom, maxf(MAX_ZOOM, floor_zoom))
	target_position = _clamp_centre(_party.get_center(), target_zoom)


## `zoom`, lowered if needed so the party's box is inside a picture centred on `at`.
func _zoom_to_hold(at: Vector2, zoom: float) -> float:
	var half: Vector2 = _picture() * 0.5
	var gap: Vector2 = (_party.position - at).abs().max((_party.end - at).abs())
	var fit: float = zoom
	if gap.x > 0.0:
		fit = minf(fit, half.x / gap.x * 0.999)
	if gap.y > 0.0:
		fit = minf(fit, half.y / gap.y * 0.999)
	return maxf(fit, _min_zoom())


## The smallest zoom the camera's limits allow: never a picture bigger than the room (0 for none).
func _min_zoom() -> float:
	var width: float = float(camera.limit_right - camera.limit_left)
	var height: float = float(camera.limit_bottom - camera.limit_top)
	if width <= 0.0 or height <= 0.0 or width >= LIMIT_UNSET or height >= LIMIT_UNSET:
		return 0.0
	var picture: Vector2 = _picture()
	return maxf(picture.x / width, picture.y / height)


## Move a camera centre so a picture at `zoom` stays inside the camera's limits, as Godot does when
## drawing (so the position kept is the one on screen).
func _clamp_centre(centre: Vector2, zoom: float) -> Vector2:
	var half: Vector2 = _picture() * (0.5 / zoom)
	var low := Vector2(camera.limit_left + half.x, camera.limit_top + half.y)
	var high := Vector2(camera.limit_right - half.x, camera.limit_bottom - half.y)
	var mid := Vector2((camera.limit_left + camera.limit_right) * 0.5, (camera.limit_top + camera.limit_bottom) * 0.5)
	var x: float = clampf(centre.x, low.x, high.x) if low.x <= high.x else mid.x
	var y: float = clampf(centre.y, low.y, high.y) if low.y <= high.y else mid.y
	return Vector2(x, y)


## The picture's size at zoom 1: what the camera's viewport shows (out of the tree, the project's).
func _picture() -> Vector2:
	if camera.is_inside_tree():
		return camera.get_viewport_rect().size
	return Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))


func _valid() -> bool:
	return camera != null and is_instance_valid(camera)
