extends Node
## The camera spike's split screen (connected biomes CB1, docs/milestones/connected-biomes.md): the
## game's world drawn `count` times, once a view, each view masked to its Voronoi cell
## (`voronoi_cells.gd`), for measuring what a split costs. View only, and a test's: CB6 builds the
## game's camera.
##
## - **A view** is a SubViewport the screen's size sharing the root's World2D (so it draws the same
##   world, nothing copied), with a Camera2D of its own at zoom 1 inside the world camera's limits,
##   its wizard drawn at its cell's middle (`VoronoiCells.camera_centre`). It is shown on the root's
##   screen by a Polygon2D, the cell, textured with the view (its UVs the cell's own pixels), under
##   the HUD (LAYER). A dark line is drawn round every cell (the divider).
## - **The root stops drawing the world:** its canvas cull mask drops the world's visibility layer
##   (WORLD_LAYER, every canvas item's default), and every canvas item on a canvas layer of the root
##   (the HUD, the views' cells) gets SCREEN_LAYER, which the root keeps; so each frame draws the
##   world once a view and the HUD once, as a game split would.
## - **Light a view:** the game's light buffer (gameplay/feel/spell_light.gd) follows the root's
##   camera. A view past the first gets a buffer of its own: a SubViewport sharing the light
##   buffer's World2D, its canvas the view's scaled down, so each frame draws the light once a view.
##   Its picture is not read yet: every view's apply rect reads the game's one buffer (a shared
##   material cannot tell the views apart), so a view's light is drawn where the root's camera would
##   put it. The cost is a view's; the look is CB6's to solve.
## - **Measured** (`report`): the GPU time of each frame's views, light buffers and the root
##   (`RenderingServer` viewport timing), averaged over the frames since `start_measuring`.
##
## `place(world)` is called each drawn frame with the wizards' places (world pixels), one a view.
## With a count of 0 nothing is split: the root draws the world as in play, and only the times are
## counted (the baseline).

const CellsScript := preload("res://tests/benchmark/voronoi_cells.gd")

## The visibility layer of the world's canvas items (the default) and the one the root keeps.
const WORLD_LAYER: int = 1
const SCREEN_LAYER: int = 1 << 1
## The canvas layer the views are shown on: over the world, under the HUD's panels (10).
const LAYER: int = 5
## The farthest wizard's site is this far from the screen's edge (`VoronoiCells.sites`).
const MARGIN: float = 96.0
## A view's zoom (the game's closest, PartyCamera.MAX_ZOOM).
const ZOOM: float = 1.0
## The divider round each cell: its width (screen pixels) and colour (the void's dark).
const DIVIDER_WIDTH: float = 2.0
const DIVIDER_COLOR := Color(0.05, 0.04, 0.09)

## The views, their cameras, the cells that show them and the extra light buffers (one a view past
## the first while the game has light). Read only.
var views: Array[SubViewport] = []
var cameras: Array[Camera2D] = []
var shown: Array[Polygon2D] = []
var light_buffers: Array[SubViewport] = []
## The cells as last placed (screen pixels). Read only.
var cells: Array[PackedVector2Array] = []

var _count: int = 1
var _root: Viewport = null
var _mask_before: int = 0
var _layer: CanvasLayer = null
var _divider: Node2D = null
var _game_light: SubViewport = null
## Sums over the measured frames (milliseconds) and the frames counted.
var _measuring: bool = false
var _frames: int = 0
var _views_gpu: float = 0.0
var _views_gpu_most: float = 0.0
var _lights_gpu: float = 0.0
var _root_gpu: float = 0.0
var _views_cpu: float = 0.0


## The divider: a closed line round each cell.
class Divider:
	extends Node2D
	var owner_views: Node

	func _draw() -> void:
		var drawn: Array[PackedVector2Array] = owner_views.get(&"cells")
		if drawn.size() < 2:
			return
		for cell in drawn:
			if cell.size() < 3:
				continue
			var line: PackedVector2Array = cell.duplicate()
			line.append(cell[0])
			draw_polyline(line, DIVIDER_COLOR, DIVIDER_WIDTH)


func _init(count: int) -> void:
	_count = maxi(count, 0)
	name = "VoronoiViews"


func _ready() -> void:
	_root = get_tree().root
	RenderingServer.viewport_set_measure_render_time(_root.get_viewport_rid(), true)
	if _count == 0:
		return
	var size := Vector2i(_root.get_visible_rect().size)
	_layer = CanvasLayer.new()
	_layer.name = "Views"
	_layer.layer = LAYER
	add_child(_layer)
	for index in _count:
		var view := SubViewport.new()
		view.name = "View%d" % index
		view.size = size
		view.world_2d = _root.world_2d
		view.disable_3d = true
		view.gui_disable_input = true
		view.transparent_bg = false
		view.snap_2d_transforms_to_pixel = _root.snap_2d_transforms_to_pixel
		view.snap_2d_vertices_to_pixel = _root.snap_2d_vertices_to_pixel
		view.canvas_item_default_texture_filter = _root.canvas_item_default_texture_filter
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var camera := Camera2D.new()
		camera.zoom = Vector2(ZOOM, ZOOM)
		view.add_child(camera)
		add_child(view)
		camera.make_current()
		RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)
		views.append(view)
		cameras.append(camera)
		var cell := Polygon2D.new()
		cell.name = "Cell%d" % index
		cell.texture = view.get_texture()
		cell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_layer.add_child(cell)
		shown.append(cell)
	_divider = Divider.new()
	_divider.owner_views = self
	_layer.add_child(_divider)
	# The root draws the HUD and the views' cells, not the world.
	_mask_before = _root.canvas_cull_mask
	_root.canvas_cull_mask = (_mask_before & ~WORLD_LAYER) | SCREEN_LAYER
	_keep_on_screen(_root)
	get_tree().node_added.connect(_on_node_added)
	cells.append(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), Vector2(size), Vector2(0.0, size.y)]))


func _exit_tree() -> void:
	if _root == null:
		return
	RenderingServer.viewport_set_measure_render_time(_root.get_viewport_rid(), false)
	if _game_light != null and is_instance_valid(_game_light):
		RenderingServer.viewport_set_measure_render_time(_game_light.get_viewport_rid(), false)
	if RenderingServer.frame_pre_draw.is_connected(_follow_light_buffers):
		RenderingServer.frame_pre_draw.disconnect(_follow_light_buffers)
	if _count == 0:
		return
	_root.canvas_cull_mask = _mask_before
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


## Draw a light buffer a view past the first from now on, each sharing `game_light`'s world (the
## game's light buffer; null: none, the light is off).
func use_light(game_light: SubViewport) -> void:
	for buffer in light_buffers:
		buffer.queue_free()
	light_buffers.clear()
	_game_light = game_light
	if game_light == null:
		return
	RenderingServer.viewport_set_measure_render_time(game_light.get_viewport_rid(), true)
	for index in range(1, _count):
		var buffer := SubViewport.new()
		buffer.name = "LightBuffer%d" % index
		buffer.world_2d = game_light.world_2d
		buffer.transparent_bg = true
		buffer.disable_3d = true
		buffer.gui_disable_input = true
		buffer.size = game_light.size
		buffer.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		buffer.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		add_child(buffer)
		RenderingServer.viewport_set_measure_render_time(buffer.get_viewport_rid(), true)
		light_buffers.append(buffer)
	# Just before the draw, after the views' cameras have moved, as the game's own buffer follows.
	if not light_buffers.is_empty() and not RenderingServer.frame_pre_draw.is_connected(_follow_light_buffers):
		RenderingServer.frame_pre_draw.connect(_follow_light_buffers)


## Lay the cells out for the wizards at `world` (world pixels; one a view, the first `count` used)
## and point each view's camera at its wizard; and count the last frame's GPU times while measuring.
func place(world: PackedVector2Array) -> void:
	if not is_inside_tree():
		return
	_count_frame()
	if views.is_empty():
		return
	var screen: Vector2 = Vector2(views[0].size)
	var points: PackedVector2Array = world.slice(0, views.size())
	if points.size() < views.size():
		return
	var world_camera: Camera2D = _root.get_camera_2d()
	cells = CellsScript.cells(CellsScript.sites(points, screen, MARGIN), Rect2(Vector2.ZERO, screen))
	for index in views.size():
		var cell: PackedVector2Array = cells[index]
		shown[index].polygon = cell
		shown[index].uv = cell
		var camera: Camera2D = cameras[index]
		if world_camera != null:
			camera.limit_left = world_camera.limit_left
			camera.limit_top = world_camera.limit_top
			camera.limit_right = world_camera.limit_right
			camera.limit_bottom = world_camera.limit_bottom
			camera.offset = world_camera.offset
		camera.position = CellsScript.camera_centre(points[index], CellsScript.centroid(cell), screen, ZOOM)
	_divider.queue_redraw()


## Each extra light buffer sees its view's part of the world, scaled down as the game's is.
func _follow_light_buffers() -> void:
	if not is_inside_tree() or _game_light == null or not is_instance_valid(_game_light):
		return
	for i in light_buffers.size():
		var buffer: SubViewport = light_buffers[i]
		var view: SubViewport = views[i + 1]
		if buffer.size != _game_light.size:
			buffer.size = _game_light.size
		var screen: Vector2 = Vector2(view.size)
		var scale := Vector2(float(buffer.size.x) / maxf(screen.x, 1.0), float(buffer.size.y) / maxf(screen.y, 1.0))
		buffer.canvas_transform = Transform2D(0.0, scale, 0.0, Vector2.ZERO) * view.get_canvas_transform()


## Count the last frame's times from now on.
func start_measuring() -> void:
	_measuring = true
	_frames = 0
	_views_gpu = 0.0
	_views_gpu_most = 0.0
	_lights_gpu = 0.0
	_root_gpu = 0.0
	_views_cpu = 0.0


func _count_frame() -> void:
	if not _measuring:
		return
	var views_gpu: float = 0.0
	for view in views:
		views_gpu += RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid())
		_views_cpu += RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid())
	_views_gpu += views_gpu
	_views_gpu_most = maxf(_views_gpu_most, views_gpu)
	if _game_light != null and is_instance_valid(_game_light):
		_lights_gpu += RenderingServer.viewport_get_measured_render_time_gpu(_game_light.get_viewport_rid())
	for buffer in light_buffers:
		_lights_gpu += RenderingServer.viewport_get_measured_render_time_gpu(buffer.get_viewport_rid())
	_root_gpu += RenderingServer.viewport_get_measured_render_time_gpu(_root.get_viewport_rid())
	_frames += 1


## Frames counted since `start_measuring`.
func frames_counted() -> int:
	return _frames


## The `BENCH: split views` line: the GPU time a frame of the views, the light buffers and the root;
## with a warning when every GPU time read 0 (no timer queries: a headless run, or a renderer that
## does not time the GPU), when only the frame time is a measure.
func report(label: String) -> void:
	var frames: float = maxf(1.0, float(_frames))
	if _views_gpu + _lights_gpu + _root_gpu <= 0.0:
		print("BENCH WARNING: split views %s: no GPU time was measured (headless, or no GPU timer queries here); read the frame time instead" % label)
	var buffers: int = light_buffers.size() + (1 if _game_light != null and is_instance_valid(_game_light) else 0)
	print("BENCH: split views %s: %d views over %d frames, GPU a frame avg: views %.2f ms (max %.2f, %.2f a view), light buffers %.2f ms (%d), root (cells and HUD) %.2f ms, total %.2f ms; views' render CPU avg %.2f ms a frame" % [
		label, views.size(), _frames, _views_gpu / frames, _views_gpu_most, _views_gpu / frames / maxf(1.0, float(views.size())),
		_lights_gpu / frames, buffers, _root_gpu / frames, (_views_gpu + _lights_gpu + _root_gpu) / frames, _views_cpu / frames])


## Every canvas item on a canvas layer of the root (the HUD, the views' cells), from `node` down,
## stays drawn by the root.
func _keep_on_screen(node: Node) -> void:
	_mark(node)
	for child in node.get_children():
		_keep_on_screen(child)


func _on_node_added(node: Node) -> void:
	_mark(node)


func _mark(node: Node) -> void:
	var item := node as CanvasItem
	if item == null or item.get_viewport() != _root or item.get_canvas_layer_node() == null:
		return
	item.visibility_layer |= SCREEN_LAYER
