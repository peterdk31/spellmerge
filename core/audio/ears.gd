extends RefCounted
## Where the world's sounds are heard from, and which are heard at all (connected biomes CB12,
## decision 29; Audio's, core/audio). View only: no state, nothing in the simulation reads it.
##
## **Heard from each view.** Godot hears a placed voice (`AudioStreamPlayer2D`) from the root
## viewport's camera. While the screen is split (`ScreenViews`, published on the root viewport by
## Feel's split screen) that camera's middle can be the void between the views, so a sound would pan
## and fall off from a place nobody looks at. `place` moves a sound to where the root camera draws
## the screen pixel its own view shows it at: the view whose wizards stand nearest it (its anchor
## taken back into the world), so it pans and falls off as it looks on screen, in that view. With one
## picture nothing moves (`place` is the identity).
##
## **Which are heard** is its caller's rule (`heard`, a Callable from a world point to a bool; Feel's
## room hearing: only the rooms this machine's wizards are in). Audio knows nothing of rooms: a voice
## asked for where `hears` is false is not played, and a held sound there is silent until it is heard.
##
## Audio refreshes it once a frame (`refresh`, from the root viewport) before its voices are stepped;
## nothing is allocated after it is made.

const ScreenViewsScript := preload("res://core/display/screen_views.gd")

## Which world points are heard (`func(at: Vector2) -> bool`); unset: every one.
var heard: Callable = Callable()

## The views this frame (0: one picture), each one's world-to-screen and its anchor in the world, and
## the root's screen-to-world.
var _count: int = 0
var _to_screen: Array[Transform2D] = []
var _anchor_world: PackedVector2Array = PackedVector2Array()
var _from_screen: Transform2D = Transform2D.IDENTITY


func _init() -> void:
	_to_screen.resize(ScreenViewsScript.VIEWS_MOST)
	_anchor_world.resize(ScreenViewsScript.VIEWS_MOST)


## Read the views published on `viewport` (none: one picture), and its own canvas transform.
func refresh(viewport: Viewport) -> void:
	var views: ScreenViewsScript = ScreenViewsScript.on(viewport)
	if views == null or views.count <= 1:
		_count = 0
		return
	use(views, viewport.get_canvas_transform())


## Hear from `views` while the root draws the world through `root_canvas` (tests call this).
func use(views: ScreenViewsScript, root_canvas: Transform2D) -> void:
	_count = mini(views.count, ScreenViewsScript.VIEWS_MOST)
	for view in _count:
		_to_screen[view] = views.to_screen[view]
		_anchor_world[view] = views.to_screen[view].affine_inverse() * views.anchor[view]
	_from_screen = root_canvas.affine_inverse()


## One picture again.
func clear_views() -> void:
	_count = 0


## How many views it hears from (0: one picture).
func views() -> int:
	return _count


## True when a sound at `at` is heard (`heard`'s answer; true without one, and for INF).
func hears(at: Vector2) -> bool:
	if not heard.is_valid() or not at.is_finite():
		return true
	return bool(heard.call(at))


## Where a sound at `at` is put for Godot to hear it (see the top): `at` itself with one picture.
func place(at: Vector2) -> Vector2:
	if _count == 0 or not at.is_finite():
		return at
	var best: int = 0
	var nearest: float = INF
	for view in _count:
		var gap: float = _anchor_world[view].distance_squared_to(at)
		if gap < nearest:
			nearest = gap
			best = view
	return _from_screen * (_to_screen[best] * at)
