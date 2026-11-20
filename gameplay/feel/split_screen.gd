extends Node
## The Voronoi split screen drawn (connected biomes CB6, docs/milestones/connected-biomes.md,
## decisions 27 and 28; CB1 settled how: "CB1's numbers"). Feel owns it and steps it every drawn
## frame after the party camera; `split_camera.gd` works out the views, this draws them. View only:
## nothing in the simulation reads it.
##
## - **One picture:** with no view (everyone fits) nothing here draws; the root viewport draws the
##   world through the world's camera, as without a split.
## - **A view** is a SubViewport the size of its cell's box (`view_box`; the performance pass,
##   2026-11-20: a quarter pane draws a quarter of the screen's pixels, not the whole screen's)
##   sharing the root's World2D (the same world, nothing copied), its canvas transform the view's
##   own (`ScreenViews.to_screen`, moved by the box's corner: no camera node). It is shown on the
##   root's screen by a rect over that box on a canvas layer (LAYER, over the world and under the
##   HUD's panels), textured with the view, whose shader keeps its cell and draws the divider
##   (`split_cell.gdshader`). A view keeps its node while it lives (its slot).
## - **Each view draws the world and its own readers of the light:** its canvas cull mask is the
##   world's layer and its own (`ViewReaders.view_mask`, by its place in `views()`, which is its light
##   buffer's), so of each reader (the apply rect, the motes, the mist) it draws its own copy, whose
##   material's uniform names its buffer; the void view is one view more, after them (no buffer: no
##   light in the void).
## - **The root stops drawing the world** while there is a view: its canvas cull mask drops the
##   world's visibility layer (WORLD_LAYER, every canvas item's default) and the views' own layers, and keeps SCREEN_LAYER,
##   which every canvas item on one of the root's canvas layers gets (the HUD's panels, the markers,
##   the cells), so the HUD stays in the screen's corners, drawn once over the views.
## - **Published** (`ScreenViews.publish` on the root) while there are two views or more, for what
##   reads the picture by the screen (the mouse, the item hints, a body's looks on screen).
## - **The light, a buffer a view**, and the fallbacks: Feel hands `views()` to the spectacle every
##   frame (`Spectacle.set_split`), with the fallbacks CB1 measured as the frame-time budget asks
##   for them (`budget`, `split_budget.gd`: the owner's targets, decision 31): `mote_share()` (the
##   share of motes thrown while split) and `light_downscale()` (how much smaller the light buffers
##   past the first view's are).
##
## - **The equal split's blank quarter shows the void** (the owner, 2026-11-20): with three panes
##   the fourth is no view's (`SplitCamera.blank_count`), and over that quarter the void view draws:
##   one more SubViewport (the quarter's size) sharing the world, looking at a spot of the void
##   VOID_AWAY past the biome's corner at the views' zoom (`void_bounds`, Feel's; no room, bridge or
##   view is there), so it shows the void's black and its drifting motes (the blank's part past its
##   quarter while it moves in or out is the plain black under it)
## - **A pair's twin** (three groups of four players; the owner, 2026-11-20): when the blank is the
##   twin of a pair's half (`SplitCamera.blank_owner_view`), the twin rect shows that view's own
##   texture over the whole screen under the cells, so the blank's part is the pair's picture, no
##   divider between (nothing more is drawn: the view draws the whole screen anyway) (`void_rect`: Feel has the spectacle give them off there too,
##   `Spectacle.set_void_blank`). Outside a biome (no bounds) the blank is the plain black.
##
## Every view and cell is made the first time it is needed and kept; nothing is allocated a frame.

const SplitCameraScript := preload("res://gameplay/feel/split_camera.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const CloseFoesScript := preload("res://gameplay/feel/close_foes.gd")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const SplitBudgetScript := preload("res://gameplay/feel/split_budget.gd")
const VoidBackdropScript := preload("res://gameplay/feel/void_backdrop.gd")
const ViewReadersScript := preload("res://gameplay/feel/view_readers.gd")
const CELL_SHADER: Shader = preload("res://gameplay/feel/split_cell.gdshader")

## The visibility layer of the world's canvas items (the default), and the one the root keeps
## (`view_readers.gd`'s, which also names each view's own layer: its copies of what reads the light).
const WORLD_LAYER: int = ViewReadersScript.WORLD_LAYER
const SCREEN_LAYER: int = ViewReadersScript.SCREEN_LAYER
## The canvas layer the views are shown on: over the world, under the HUD's panels (10).
const LAYER: int = 5
## The divider's colour (the void's dark).
const DIVIDER_COLOUR := Color(0.05, 0.04, 0.09)
## The uniforms of the cell shader naming the other views and the divider towards each.
## Up to four: three other views and the equal split's blank quarter (or a fourth view merging).
const OTHER_UNIFORMS: Array[StringName] = [&"other_0", &"other_1", &"other_2", &"other_3"]
const DIVIDER_UNIFORMS: Array[StringName] = [&"divider_0", &"divider_1", &"divider_2", &"divider_3"]
## How far past the biome's top left corner (each way, world pixels) the void view looks: inside the
## void's black (`VoidBackdrop.GROW`) and past any view's limits.
const VOID_AWAY: float = 1024.0
## A view's box is snapped out to this many screen pixels (`view_box`): a multiple of every light
## buffer's downscale (SpellLight.DOWNSCALE and the budget's), so a view's light buffer texels lie
## where the whole screen's would, and the light looks the same in a box as on the screen.
const BOX_SNAP: int = 8
## A view's box reaches this many screen pixels past its cell's corners (`view_box`): the light
## readers sample a light buffer linearly, so a cell pixel near the box's edge reads texels up to
## half a texel past it; a texel is at most the budget's largest downscale (8) screen pixels.
const BOX_PAD: int = 8
## How much larger a view's box may be than its cell's needs, each way, before it is made again
## (`kept_box`): a box resized makes its view's and its light buffer's render targets anew, so it
## keeps its size while the dividers slide a few pixels, and is made with this much room.
const BOX_SLACK: int = 32

## The frame-time budget: which of CB1's fallbacks the split's frames need now.
var budget: SplitBudgetScript = SplitBudgetScript.new()

## The views worked out (read only; `camera.views` is what is drawn).
var camera: SplitCameraScript = SplitCameraScript.new()

var _root: Viewport = null
var _layer: CanvasLayer = null
## Under the cells, over the whole screen: what the equal split's blank quarter shows (no view
## draws there), the void's black. Shown only while there is a blank.
var _blank: ColorRect = null
## The bounds of the biome the views are in (Feel's, every frame; empty: none, the blank is black).
var void_bounds: Rect2 = Rect2()
## The view of the void the blank quarter shows, and its rect (made the first time).
var _void_view: SubViewport = null
var _void_cell: TextureRect = null
## Under the cells: the picture of the view the blank is the twin of (made the first time).
var _twin_cell: TextureRect = null
## By slot: its view and the rect that shows it (made as needed).
var _views: Array[SubViewport] = []
var _cells: Array[TextureRect] = []
## The box each slot's view drew last (`kept_box`).
var _boxes: Array[Rect2i] = []
## The views drawn now, in order (`views()`), kept while they are the same.
var _shown: Array[Viewport] = []
## True while the views draw the world (the root does not); the root's cull mask before.
var _drawing: bool = false
var _mask_before: int = 0


func _init() -> void:
	name = "SplitScreen"
	ShaderWarmupScript.want(CELL_SHADER, ShaderWarmupScript.RECT)
	_views.resize(ScreenViewsScript.VIEWS_MOST)
	_cells.resize(ScreenViewsScript.VIEWS_MOST)
	_boxes.resize(ScreenViewsScript.VIEWS_MOST)


func _ready() -> void:
	_root = get_tree().root
	_layer = CanvasLayer.new()
	_layer.name = "Views"
	_layer.layer = LAYER
	add_child(_layer)
	_blank = ColorRect.new()
	_blank.name = "Blank"
	_blank.color = VoidBackdropScript.COLOUR
	_blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blank.visibility_layer = SCREEN_LAYER
	_blank.visible = false
	_layer.add_child(_blank)


func _exit_tree() -> void:
	_stop()


## What `split_cell.gdshader` draws at the pixel whose middle is `p` (screen pixels) for a view
## anchored at `own`, the others at `others` with dividers `widths` (whole pixels) and `before` (a
## bit each: those coming before it): -1 not its pixel, 0 its picture, 1 the divider. The shader's
## rule on the CPU, line for line, for the tests.
static func cell_pixel(p: Vector2, own: Vector2, others: PackedVector2Array, widths: PackedFloat32Array, before: int) -> int:
	var line: bool = false
	for k in others.size():
		var normal: Vector2 = others[k] - own
		var length: float = normal.length()
		if length < 0.0001:
			continue
		var unit: Vector2 = normal / length
		var side: float = (p - (own + others[k]) * 0.5).dot(unit)
		var first: bool = (before >> k) & 1 != 0
		if side > 0.0 or (side == 0.0 and first):
			return -1
		var steps: float = -side / maxf(absf(unit.x), absf(unit.y))
		var share: float = floorf(widths[k] * 0.5) if first else ceilf(widths[k] * 0.5)
		if steps <= share if first else steps < share:
			line = true
	return 1 if line else 0


## The views drawn now, in the order of `camera.views` (empty with one picture). Read only.
func views() -> Array[Viewport]:
	return _shown


## The share of motes thrown now (1: all; the budget's fallback while split).
func mote_share() -> float:
	return budget.mote_share()


## How many times smaller than its view a light buffer past the first view's is now (the budget's).
func light_downscale() -> int:
	return budget.light_downscale()


## True while the views draw the world instead of the root.
func is_drawing() -> bool:
	return _drawing


## The view in slot `slot` (null before it was first needed; for tests).
func view_in_slot(slot: int) -> SubViewport:
	return _views[slot]


## The box of the screen view `view` of `laid` needs (screen pixels): its cell's corners' box,
## grown by BOX_PAD (no pixel the cell's shader keeps is outside it, nor the light texels it reads)
## and snapped out to BOX_SNAP pixels, within `screen`; the whole screen when `whole` (the twin's view, whose picture
## is shown over the blank's quarter too) or for a cell of fewer than 3 corners. A view draws only
## its box, so a quarter pane draws a quarter of the screen's pixels, not all of them; its picture
## is the same, the box's part of the whole screen's.
static func view_box(laid: ScreenViewsScript, view: int, screen: Vector2, whole: bool = false) -> Rect2i:
	var full := Rect2i(Vector2i.ZERO, Vector2i(screen))
	var n: int = laid.corners(view)
	if whole or n < 3:
		return full
	var low: Vector2 = laid.corner(view, 0)
	var high: Vector2 = low
	for at in range(1, n):
		var point: Vector2 = laid.corner(view, at)
		low = low.min(point)
		high = high.max(point)
	var start := Vector2i((low - Vector2.ONE * BOX_PAD).floor())
	var end := Vector2i((high + Vector2.ONE * BOX_PAD).ceil())
	start = Vector2i(floori(float(start.x) / BOX_SNAP) * BOX_SNAP, floori(float(start.y) / BOX_SNAP) * BOX_SNAP)
	end = Vector2i(ceili(float(end.x) / BOX_SNAP) * BOX_SNAP, ceili(float(end.y) / BOX_SNAP) * BOX_SNAP)
	var box := Rect2i(start, end - start).intersection(full)
	return box if box.has_area() else full


## The box a view draws, given the box it drew last (`current`; empty for none) and the one its cell
## needs now (`needed`, `view_box`): the last one while it holds the needed one with at most
## BOX_SLACK more on each side, else the needed one grown by half BOX_SLACK each way (snapped, within
## `screen`), so a view is resized only now and then while the dividers slide.
static func kept_box(current: Rect2i, needed: Rect2i, screen: Vector2) -> Rect2i:
	var full := Rect2i(Vector2i.ZERO, Vector2i(screen))
	if current.has_area() and current.encloses(needed) and needed.position.x - current.position.x <= BOX_SLACK and needed.position.y - current.position.y <= BOX_SLACK and current.end.x - needed.end.x <= BOX_SLACK and current.end.y - needed.end.y <= BOX_SLACK:
		return current
	if needed == full:
		return full
	var grown: Rect2i = needed.grow(BOX_SLACK / 2).intersection(full)
	return grown if grown.has_area() else full


## A drawn frame, `delta` real seconds on: the views for this machine's wizards (`seats`, a bit a
## seat) in `table`, split from the world's camera `world_camera`, laid out and drawn.
func step(delta: float, table: ActorsScript, seats: int, world_camera: Camera2D, foes: CloseFoesScript = null) -> void:
	if _root == null:
		return
	var screen: Vector2 = _root.get_visible_rect().size
	camera.step(delta, table, seats, world_camera, screen, foes)
	var laid: ScreenViewsScript = camera.views
	budget.step(delta, laid.count)
	if laid.count == 0:
		_stop()
		return
	_start()
	var used: int = 0
	var twin_of: int = camera.blank_owner_view() if camera.blank_count() > 0 else -1
	for view in laid.count:
		var slot: int = camera.slot_of(view)
		used |= 1 << slot
		_boxes[slot] = kept_box(_boxes[slot], view_box(laid, view, screen, view == twin_of), screen)
		_show(slot, view, laid, screen, _boxes[slot])
	for slot in ScreenViewsScript.VIEWS_MOST:
		if used & (1 << slot) == 0 and _views[slot] != null:
			_views[slot].render_target_update_mode = SubViewport.UPDATE_DISABLED
			_cells[slot].visible = false
	_blank.visible = camera.blank_count() > 0
	if _blank.visible:
		_blank.size = screen
	var owner: int = camera.blank_owner_view() if _blank.visible else -1
	_show_twin(owner, screen)
	_show_void(camera.blank_quarter() if _blank.visible and owner < 0 and void_bounds.has_area() else -1, screen)
	_keep_shown(laid)
	if laid.is_split():
		ScreenViewsScript.publish(_root, laid)
	else:
		ScreenViewsScript.withdraw(_root)


## Draw view `view` (in slot `slot`) of `laid` over `box` of the screen (`view_box`): its world
## transform, and its cell's place, anchors and dividers.
func _show(slot: int, view: int, laid: ScreenViewsScript, screen: Vector2, box: Rect2i) -> void:
	var shown: SubViewport = _view(slot)
	if shown.size != box.size:
		shown.size = box.size
	shown.canvas_transform = laid.to_screen[view].translated(-Vector2(box.position))
	# The world and this view's own readers of the light (its light buffer is the view's place in
	# `views()`, as the light is handed them).
	var mask: int = ViewReadersScript.view_mask(view)
	if shown.canvas_cull_mask != mask:
		shown.canvas_cull_mask = mask
	shown.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cell: TextureRect = _cells[slot]
	cell.visible = true
	cell.position = Vector2(box.position)
	cell.size = Vector2(box.size)
	var material := cell.material as ShaderMaterial
	material.set_shader_parameter(&"screen_size", Vector2(box.size))
	material.set_shader_parameter(&"cell_origin", Vector2(box.position))
	material.set_shader_parameter(&"own", laid.anchor[view])
	var others: int = 0
	var before: int = 0
	for other in laid.count:
		if other == view or others >= OTHER_UNIFORMS.size():
			continue
		material.set_shader_parameter(OTHER_UNIFORMS[others], laid.anchor[other])
		material.set_shader_parameter(DIVIDER_UNIFORMS[others], float(camera.divider_between(view, other)))
		if other < view:
			before |= 1 << others
		others += 1
	# The equal split's blank quarter: a site no view owns, its part of the screen left to the
	# root's dark (the world is not drawn there while split).
	for blank in camera.blank_count():
		if others >= OTHER_UNIFORMS.size():
			break
		material.set_shader_parameter(OTHER_UNIFORMS[others], camera.blank_anchor(blank))
		material.set_shader_parameter(DIVIDER_UNIFORMS[others], float(camera.blank_divider(view)))
		if camera.blank_before(view):
			before |= 1 << others
		others += 1
	material.set_shader_parameter(&"others", others)
	material.set_shader_parameter(&"before_mask", before)


## The world rect the void view shows now (empty while it does not draw).
func void_rect() -> Rect2:
	if _void_view == null or not _void_cell.visible:
		return Rect2()
	var zoom: float = _void_view.canvas_transform.x.x
	return Rect2(-_void_view.canvas_transform.origin / zoom, Vector2(_void_view.size) / zoom)


## The void view (null before it was first needed; for tests).
func void_view() -> SubViewport:
	return _void_view


## The twin rect showing view `view`'s picture under the cells over the whole screen (-1: hidden).
func _show_twin(view: int, screen: Vector2) -> void:
	if view < 0:
		if _twin_cell != null:
			_twin_cell.visible = false
		return
	var shown: SubViewport = _views[camera.slot_of(view)]
	if _twin_cell == null:
		_twin_cell = _new_cell("TwinCell", shown)
		var made := ShaderMaterial.new()
		made.shader = CELL_SHADER
		made.set_shader_parameter(&"divider_colour", DIVIDER_COLOUR)
		_twin_cell.material = made
		# Over the blank's black, under every view's cell.
		_layer.move_child(_twin_cell, _blank.get_index() + 1)
	var texture: Texture2D = shown.get_texture()
	if _twin_cell.texture != texture:
		_twin_cell.texture = texture
	_twin_cell.size = screen
	_twin_cell.visible = true
	# Cut as a pane of its own about the twin's site: none toward its pair, toward the others the
	# pair's own lines, split as the pair splits them (its share drawn here).
	var laid: ScreenViewsScript = camera.views
	var material := _twin_cell.material as ShaderMaterial
	material.set_shader_parameter(&"screen_size", screen)
	material.set_shader_parameter(&"own", camera.blank_anchor(0))
	var others: int = 0
	var before: int = 0
	for other in laid.count:
		if others >= OTHER_UNIFORMS.size():
			break
		material.set_shader_parameter(OTHER_UNIFORMS[others], laid.anchor[other])
		material.set_shader_parameter(DIVIDER_UNIFORMS[others], 0.0 if other == view else float(camera.divider_between(view, other)))
		if other < view:
			before |= 1 << others
		others += 1
	material.set_shader_parameter(&"others", others)
	material.set_shader_parameter(&"before_mask", before)


## The twin rect (null before it was first needed; for tests).
func twin_cell() -> TextureRect:
	return _twin_cell


## The void view drawn under the cells over quarter `quarter` of the screen (-1: not drawn),
## looking VOID_AWAY past the biome's corner at the views' zoom.
func _show_void(quarter: int, screen: Vector2) -> void:
	if quarter < 0:
		if _void_view != null:
			_void_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_void_cell.visible = false
		return
	if _void_view == null:
		_void_view = _new_view("VoidView")
		_void_cell = _new_cell("VoidCell", _void_view)
		# Over the blank's black, under every view's cell.
		_layer.move_child(_void_cell, _blank.get_index() + 1)
	var half := Vector2i(screen * 0.5)
	if _void_view.size != half:
		_void_view.size = half
	var zoom: float = maxf(camera.view_zoom(), 0.0001)
	var origin: Vector2 = ((void_bounds.position - Vector2.ONE * VOID_AWAY) * zoom - Vector2(half) * 0.5).round()
	_void_view.canvas_transform = Transform2D(0.0, Vector2(zoom, zoom), 0.0, -origin)
	# One view more than those drawn (its readers after theirs: the light reads none there, and the
	# motes cull by what it shows; Feel's spectacle hands the light its box after the views').
	var mask: int = ViewReadersScript.view_mask(mini(camera.views.count, ViewReadersScript.VIEWS_MOST - 1))
	if _void_view.canvas_cull_mask != mask:
		_void_view.canvas_cull_mask = mask
	_void_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_void_cell.position = Vector2(float(half.x * (quarter % 2)), float(half.y * (quarter >> 1)))
	_void_cell.size = Vector2(half)
	_void_cell.visible = true


## The view and cell of slot `slot`, made the first time.
func _view(slot: int) -> SubViewport:
	if _views[slot] != null:
		return _views[slot]
	var view: SubViewport = _new_view("View%d" % slot)
	_views[slot] = view
	var cell: TextureRect = _new_cell("Cell%d" % slot, view)
	var material := ShaderMaterial.new()
	material.shader = CELL_SHADER
	material.set_shader_parameter(&"divider_colour", DIVIDER_COLOUR)
	cell.material = material
	_cells[slot] = cell
	return view


## A view (the screen's size until its first box) sharing the root's world and its pixel settings, drawing only the world.
func _new_view(named: String) -> SubViewport:
	var view := SubViewport.new()
	view.name = named
	view.world_2d = _root.world_2d
	view.disable_3d = true
	view.gui_disable_input = true
	view.transparent_bg = false
	view.snap_2d_transforms_to_pixel = _root.snap_2d_transforms_to_pixel
	view.snap_2d_vertices_to_pixel = _root.snap_2d_vertices_to_pixel
	view.canvas_item_default_texture_filter = _root.canvas_item_default_texture_filter
	view.canvas_cull_mask = ViewReadersScript.view_mask(0)
	view.size = Vector2i(_root.get_visible_rect().size)
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(view)
	return view


## A rect on the views' layer showing `view` pixel for pixel.
func _new_cell(named: String, view: SubViewport) -> TextureRect:
	var cell := TextureRect.new()
	cell.name = named
	cell.texture = view.get_texture()
	cell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.stretch_mode = TextureRect.STRETCH_SCALE
	cell.visibility_layer = SCREEN_LAYER
	cell.visible = false
	_layer.add_child(cell)
	return cell


## The views draw the world from now on: the root keeps only the screen's layer.
func _start() -> void:
	if _drawing:
		return
	_drawing = true
	_mask_before = _root.canvas_cull_mask
	_keep_on_screen(_root)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	_root.canvas_cull_mask = (_mask_before & ~(WORLD_LAYER | ViewReadersScript.ALL_VIEW_LAYERS)) | SCREEN_LAYER


## One picture again: the root draws the world, no view draws, nothing published.
func _stop() -> void:
	if _root != null:
		ScreenViewsScript.withdraw(_root)
	if not _drawing:
		return
	_drawing = false
	_root.canvas_cull_mask = _mask_before
	if _blank != null:
		_blank.visible = false
	_show_void(-1, Vector2.ZERO)
	_show_twin(-1, Vector2.ZERO)
	if is_inside_tree() and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	for slot in ScreenViewsScript.VIEWS_MOST:
		if _views[slot] != null:
			_views[slot].render_target_update_mode = SubViewport.UPDATE_DISABLED
			_cells[slot].visible = false
	if not _shown.is_empty():
		_shown = []


## `_shown` the views of `laid` in order; a new list only when they changed.
func _keep_shown(laid: ScreenViewsScript) -> void:
	var same: bool = _shown.size() == laid.count
	for view in laid.count:
		same = same and _shown[view] == _views[camera.slot_of(view)]
	if same:
		return
	var next: Array[Viewport] = []
	for view in laid.count:
		next.append(_views[camera.slot_of(view)])
	_shown = next


## Every canvas item on a canvas layer of the root (the HUD, the markers, the cells), from `node`
## down, stays drawn by the root.
func _keep_on_screen(node: Node) -> void:
	_mark(node)
	for child in node.get_children():
		_keep_on_screen(child)


func _on_node_added(node: Node) -> void:
	_mark(node)


func _mark(node: Node) -> void:
	var item := node as CanvasItem
	if item == null or item.get_canvas_layer_node() == null or item.get_viewport() != _root:
		return
	item.visibility_layer |= SCREEN_LAYER
