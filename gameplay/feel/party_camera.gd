extends RefCounted
## The party's shared camera, as it is drawn (online-ready N9): Coop works out on the tick the view
## that holds every wizard and sends it with the box round them (`view_fitted(view, party)`); this
## eases the world's camera towards the view every drawn frame, on real time, so a join or a dodge
## never jerks the picture. Feel owns it and steps it; nothing in the simulation reads the camera,
## and this knows nothing of Coop but the event.
##
## While it eases it also zooms out as far as needed to keep the party's box in the picture, so
## nobody leaves it while the camera catches up (the view is fitted for where the camera is heading,
## the box is checked against where it is). It keeps to the camera's limits (the room's), never
## showing past them. After `room_entered`, or on another camera, it jumps to the view instead of
## easing. Shake (Feel) moves only the camera's `offset`, so the two do not clash.

## How fast the camera eases to its target, per second (higher is snappier).
const FOLLOW_SPEED: float = 6.0
## A camera limit this wide or more counts as "no limit" (Godot's default is 10,000,000).
const LIMIT_UNSET: float = 1000000.0

## The camera being driven (Feel's current one), or null.
var camera: Camera2D = null
## Where the camera is heading, and its zoom there (1 = no zoom).
var target_position: Vector2 = Vector2.ZERO
var target_zoom: float = 1.0

## The party's box, kept in the picture while it eases.
var _party: Rect2 = Rect2()
## The view last heard, in world pixels (Rect2() before one).
var _view: Rect2 = Rect2()
## Jump to the next view heard (a new room), instead of easing.
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
	_view = Rect2()
	_snap_next = true


## The party's view and the box round the party inside it (`view_fitted`).
func fitted(view: Rect2, party: Rect2) -> void:
	if not view.has_area():
		return
	_view = view
	_party = party
	_aim()
	if _snap_next and _valid():
		_snap_next = false
		snap()


## Put the camera on its target at once.
func snap() -> void:
	if not _valid() or not _view.has_area():
		return
	_aim()
	camera.zoom = Vector2(target_zoom, target_zoom)
	camera.position = _clamp_centre(target_position, target_zoom)


## Ease the camera towards its target by `delta` seconds of real time.
func step(delta: float) -> void:
	if not _valid() or not _view.has_area() or delta <= 0.0:
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


## The target from the view: its centre, zoomed so the picture shows all of it.
func _aim() -> void:
	target_position = _view.get_center()
	if _valid():
		target_zoom = _picture().x / _view.size.x


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
