extends Node
## Co-op (autoload `Coop`): joining and leaving mid-run, friendly fire and the
## shared camera. Up to four players; nobody ever waits for another player.
##
## Joining and leaving: `core/input` turns a button press (or an unplugged
## gamepad, or a bot's virtual device) into `device_joined` / `device_left`. Coop
## turns those into `player_joined(player)` / `player_left(player)`, once each
## per change, in any order and in any slots. `flow` hears them and adds or
## removes the wizard, `difficulty` counts the players. Coop knows nothing about
## wizards beyond the `players` group, so the run simply goes on.
##
## Friendly fire is off by default. `set_friendly_fire(true)` makes shots fired by
## a player also hit the other players (never the shooter): the switch is
## `Projectiles.friendly_fire` in `core/projectiles`, and `combat` turns the hits
## into damage as for any wizard. The option lives in memory; saving it waits for
## `core/save`.
##
## The shared camera: after `room_entered` Coop takes the current `Camera2D` and,
## every frame, moves it to the middle of all wizards (downed ones too, so a
## body can still be found) and zooms out until everyone is inside the view with
## CAMERA_MARGIN pixels to spare. Zoom stays between MIN_ZOOM and MAX_ZOOM, and
## the camera eases towards its target (FOLLOW_SPEED), so a join or a dodge never
## jerks the picture, and nobody leaves the view while it eases. The room's camera
## limits keep the view inside the room, so the zoom-out stops where the view
## would be bigger than the room (in a room not much bigger than the view, that
## is no zoom-out at all) and the camera is pushed in from the edge instead.
## Shake (`feel`) moves only the camera's `offset`, so the two do not clash.
##
## Nothing here allocates per frame. Timing runs in step(delta), so tests drive it
## with fixed deltas.

const EventsScript := preload("res://core/events/events.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const PLAYER_SLOTS: int = 4
## The group every wizard is in (set by the player script).
const PLAYERS_GROUP: StringName = &"players"
## Space kept between the outermost wizards and the edge of the view, in pixels.
const CAMERA_MARGIN: float = 48.0
## The camera never zooms in past 1 or out past 0.5 (Camera2D zoom: smaller sees more).
const MAX_ZOOM: float = 1.0
const MIN_ZOOM: float = 0.5
## How fast the camera eases to its target, per second (higher is snappier).
const FOLLOW_SPEED: float = 6.0
## A camera limit this wide or more counts as "no limit" (Godot's default is 10,000,000).
const LIMIT_UNSET: float = 1000000.0

## The services. Only tests set these, before adding the node; otherwise the
## autoloads are used.
var events: EventsScript = null
var projectiles: ProjectileManagerScript = null
## The size of the view in pixels. Only tests set this; otherwise the viewport's.
var view_size: Vector2 = Vector2.ZERO

## Whether shots of players also hit other players (default off).
var friendly_fire: bool = false:
	set = set_friendly_fire

## The camera being driven (null before the first `room_entered`).
var camera: Camera2D = null
## Where the camera is heading, and how far it zooms out (1 = no zoom).
var target_position: Vector2 = Vector2.ZERO
var target_zoom: float = MAX_ZOOM

var _joined: Array[bool] = [false, false, false, false]
var _joined_count: int = 0
var _wizards: Array[Node2D] = []


func _ready() -> void:
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	if projectiles == null:
		projectiles = get_node_or_null("/root/Projectiles") as ProjectileManagerScript
	if events == null:
		push_warning("Coop: the Events autoload is missing, so nobody can join.")
		return
	events.device_joined.connect(_on_device_joined)
	events.device_left.connect(_on_device_left)
	events.room_entered.connect(_on_room_entered)
	if projectiles != null:
		projectiles.friendly_fire = friendly_fire


func _process(delta: float) -> void:
	step(delta)


## Number of players who are in right now.
func joined_count() -> int:
	return _joined_count


func is_joined(player: int) -> bool:
	return player >= 0 and player < PLAYER_SLOTS and _joined[player]


## Turn friendly fire on or off. Takes effect for shots fired from now on.
func set_friendly_fire(enabled: bool) -> void:
	friendly_fire = enabled
	if projectiles != null:
		projectiles.friendly_fire = enabled


## Use `node` as the shared camera (normally found by itself after `room_entered`).
## Tests use this; it also remembers the wizards that exist now.
func set_camera(node: Camera2D) -> void:
	camera = node
	refresh_wizards()


## Read the wizards in the `players` group again. Done by itself after a join, a
## leave and `room_entered`.
func refresh_wizards() -> void:
	_wizards.clear()
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(PLAYERS_GROUP):
		if node is Node2D:
			_wizards.append(node as Node2D)


## Work out where the camera should be and how far out, from the wizards now.
## Does nothing with no wizards. Returns false in that case.
func fit_camera() -> bool:
	var low := Vector2.INF
	var high := -Vector2.INF
	var seen: int = 0
	for wizard: Node2D in _wizards:
		if not is_instance_valid(wizard) or not wizard.is_inside_tree():
			continue
		var at: Vector2 = wizard.global_position
		low = low.min(at)
		high = high.max(at)
		seen += 1
	if seen == 0:
		return false
	var view: Vector2 = _view_size()
	var need: Vector2 = high - low + Vector2.ONE * (CAMERA_MARGIN * 2.0)
	var floor_zoom: float = _min_zoom()
	target_zoom = clampf(minf(view.x / need.x, view.y / need.y), floor_zoom, maxf(MAX_ZOOM, floor_zoom))
	target_position = _clamp_centre((low + high) * 0.5, target_zoom)
	return true


## The smallest zoom allowed: MIN_ZOOM, but never so far out that the view is
## bigger than the camera's limits (the room), which would show empty space.
func _min_zoom() -> float:
	if camera == null or not is_instance_valid(camera):
		return MIN_ZOOM
	var width: float = float(camera.limit_right - camera.limit_left)
	var height: float = float(camera.limit_bottom - camera.limit_top)
	if width <= 0.0 or height <= 0.0 or width >= LIMIT_UNSET or height >= LIMIT_UNSET:
		return MIN_ZOOM
	var view: Vector2 = _view_size()
	return maxf(MIN_ZOOM, maxf(view.x / width, view.y / height))


## Move a camera centre so a view at `zoom` stays inside the camera's limits, as
## Godot does when drawing (so the position we keep is the one on screen).
func _clamp_centre(centre: Vector2, zoom: float) -> Vector2:
	if camera == null or not is_instance_valid(camera):
		return centre
	var half: Vector2 = _view_size() * (0.5 / zoom)
	var low := Vector2(camera.limit_left + half.x, camera.limit_top + half.y)
	var high := Vector2(camera.limit_right - half.x, camera.limit_bottom - half.y)
	var mid := Vector2((camera.limit_left + camera.limit_right) * 0.5, (camera.limit_top + camera.limit_bottom) * 0.5)
	var x: float = clampf(centre.x, low.x, high.x) if low.x <= high.x else mid.x
	var y: float = clampf(centre.y, low.y, high.y) if low.y <= high.y else mid.y
	return Vector2(x, y)


## The part of the world the camera shows now (limits applied).
func visible_rect() -> Rect2:
	if camera == null or not is_instance_valid(camera):
		return Rect2()
	var size: Vector2 = _view_size() / camera.zoom.x
	var centre: Vector2 = _clamp_centre(camera.position, camera.zoom.x)
	return Rect2(centre - size * 0.5, size)


## Ease the camera towards its target by `delta` seconds. Call `snap()` to jump.
func step(delta: float) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	if not _all_valid():
		refresh_wizards()
	if not fit_camera():
		return
	var weight: float = 1.0 - exp(-FOLLOW_SPEED * maxf(delta, 0.0))
	var at: Vector2 = camera.position.lerp(target_position, weight)
	var zoom: float = lerpf(camera.zoom.x, target_zoom, weight)
	# The target was fitted for where the camera is heading; fit against where it
	# is, so nobody is outside the view while it eases.
	zoom = _zoom_to_hold_everyone(at, zoom)
	camera.zoom = Vector2(zoom, zoom)
	camera.position = _clamp_centre(at, zoom)


## `zoom`, lowered if needed so every wizard is inside a view centred on `at`.
func _zoom_to_hold_everyone(at: Vector2, zoom: float) -> float:
	var half: Vector2 = _view_size() * 0.5
	var fit: float = zoom
	for wizard: Node2D in _wizards:
		if not is_instance_valid(wizard) or not wizard.is_inside_tree():
			continue
		var gap: Vector2 = (wizard.global_position - at).abs()
		if gap.x > 0.0:
			fit = minf(fit, half.x / gap.x * 0.999)
		if gap.y > 0.0:
			fit = minf(fit, half.y / gap.y * 0.999)
	return maxf(fit, _min_zoom())


## Put the camera on its target at once.
func snap() -> void:
	if camera == null or not is_instance_valid(camera) or not fit_camera():
		return
	camera.zoom = Vector2(target_zoom, target_zoom)
	camera.position = target_position


func _view_size() -> Vector2:
	if view_size != Vector2.ZERO:
		return view_size
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector2(640.0, 360.0)
	return viewport.get_visible_rect().size


func _all_valid() -> bool:
	for wizard: Node2D in _wizards:
		if not is_instance_valid(wizard):
			return false
	return true


func _on_device_joined(player: int, _device: int) -> void:
	if player < 0 or player >= PLAYER_SLOTS or _joined[player]:
		return
	_joined[player] = true
	_joined_count += 1
	if events != null:
		events.player_joined.emit(player)
	# `flow` added the wizard while the event was going out.
	refresh_wizards()


func _on_device_left(player: int, _device: int) -> void:
	if player < 0 or player >= PLAYER_SLOTS or not _joined[player]:
		return
	_joined[player] = false
	_joined_count -= 1
	if events != null:
		events.player_left.emit(player)
	refresh_wizards()


## The camera of the world `flow` built; the current scene's and then the
## viewport's only if there is none.
func _find_camera() -> Camera2D:
	var flow: Node = get_node_or_null("/root/Flow")
	var world: Variant = flow.get("world") if flow != null else null
	var tree: SceneTree = get_tree()
	var roots: Array[Node] = []
	if world is Node and is_instance_valid(world as Node):
		roots.append(world as Node)
	if tree != null and tree.current_scene != null:
		roots.append(tree.current_scene)
	for root: Node in roots:
		var found: Array[Node] = root.find_children("*", "Camera2D", true, false)
		if not found.is_empty():
			return found[0] as Camera2D
	var viewport: Viewport = get_viewport()
	return viewport.get_camera_2d() if viewport != null else null


## A new world is up: find its camera and put it on the players.
func _on_room_entered(_room_id: StringName) -> void:
	camera = _find_camera()
	refresh_wizards()
	snap()
