extends Control
## A part of the HUD drawn once and shown as one picture until something on it changes (the owner,
## 2026-11-21, after #900: a seat's corner panel was about 10 draw calls a frame; HUD README,
## "The corner panels are drawn once"). Its content (the first Control under its SubViewport child, `content()`) is
## drawn into that SubViewport only on a frame something on it changed, and this control draws the
## SubViewport's picture: one draw call while nothing changes.
##
## **What marks it for a redraw** (`mark`), for every CanvasItem in the content, the ones added
## later too (`child_entered_tree`): its `draw` (any `queue_redraw` that drew: a label's new text, a
## widget's next frame of a play, a sweep's next row), its `visibility_changed`, a Control's
## `item_rect_changed` (laid out, moved or resized), and a child added or taken away; and this
## control's own resize and showing again. A part that animates every frame (a cooldown's sweep, a
## stepped look, a flash) is drawn again for exactly its frames by its own redraw, so Smooth's
## stepped frames all show. What a draw does not tell must not change a look under it: a modulate
## changed with no redraw, a shader with TIME or a texture that changes by itself
## (`tests/hud/test_cached_view.gd` names any).
##
## **The same pixels:** the SubViewport is the size of the screen this control is drawn on, with its
## texture filter and snapping, and the content is drawn in it at this control's own place on that
## screen; this control draws back just that part (and PAD pixels round it, for what is drawn past
## the content's rect: an outline), 1:1 and nearest. So every vertex lands where it landed drawn
## live, to the bit: a card icon scaled down samples its page on a texel's edge, and a picture of
## another size picked the other texel. The SubViewport keeps alpha (transparent background,
## colours multiplied by their alpha as they are blended), so the picture is drawn with
## premultiplied alpha: an opaque pixel is the same exactly, a see-through one the same but for a
## rounding (one step in 255 at most) where it blends over what is under it. Moving the control
## (the panel to another corner or pane) draws the picture again there.
##
## While hidden it draws nothing and renders nothing; a change meanwhile waits for it to show.
## Display only: no input (`gui_disable_input`), no process, nothing allocated a frame.

## Something on the content changed (every `mark`, even one this frame's picture already covers):
## a live layer drawn over the picture from the content's places draws again.
signal marked

## Room round the content inside the picture, for what is drawn past the content's rect.
const PAD: int = 4

## How many times the picture was drawn again (tests and the benchmark's census).
var refreshes: int = 0
var _view: SubViewport = null
var _content: Control = null
## A change waits to be drawn (hidden meanwhile, or not yet asked this frame).
var _dirty: bool = true
## The process frame the picture was last asked for (`Engine.get_process_frames`), so a frame of
## many changes counts once in `refreshes`.
var _asked_frame: int = -1
var _premultiplied: CanvasItemMaterial = null
## This control's place on its screen, where the content is drawn in the picture (`_fit`).
var _origin: Vector2 = Vector2.ZERO
## Picture pixels a pixel of this control's own (its canvas's scale: the HUD's layer is drawn at the
## picture's, core/display/picture_grid.gd), so the content is drawn in the picture as finely as live.
var _scale: Vector2 = Vector2.ONE


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_premultiplied = CanvasItemMaterial.new()
	_premultiplied.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	material = _premultiplied


func _ready() -> void:
	for child in get_children():
		if child is SubViewport:
			_view = child as SubViewport
			break
	assert(_view != null, "a CachedView holds its content in a SubViewport child")
	for child in _view.get_children():
		if child is Control:
			_content = child as Control
			break
	assert(_content != null, "a CachedView's SubViewport holds one Control, its content")
	_view.transparent_bg = true
	_view.disable_3d = true
	_view.gui_disable_input = true
	_view.handle_input_locally = false
	_view.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var outer: Viewport = get_viewport()
	_view.canvas_item_default_texture_filter = outer.canvas_item_default_texture_filter
	_view.canvas_item_default_texture_repeat = outer.canvas_item_default_texture_repeat
	_view.snap_2d_transforms_to_pixel = outer.snap_2d_transforms_to_pixel
	_view.snap_2d_vertices_to_pixel = outer.snap_2d_vertices_to_pixel
	_content.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_content.minimum_size_changed.connect(update_minimum_size)
	_watch(_content)
	resized.connect(_fit)
	visibility_changed.connect(_on_visibility_changed)
	outer.size_changed.connect(_fit)
	set_notify_transform(true)
	_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_fit()


## The content drawn into the picture.
func content() -> Control:
	return _content


## The SubViewport the content is drawn in (for tests).
func view() -> SubViewport:
	return _view


## Something on the content changed: draw the picture again this frame (or, while hidden, as it
## shows).
func mark() -> void:
	marked.emit()
	_dirty = true
	if _view == null or not is_visible_in_tree():
		return
	_dirty = false
	# Asked again on every mark (one call to the renderer): a mark after this frame's render (a
	# `frame_post_draw` callback) asks for the next frame's, never lost to a frame already asked.
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	var frame: int = Engine.get_process_frames()
	if frame != _asked_frame:
		_asked_frame = frame
		refreshes += 1


## Draw the content live (`on`: moved out of the SubViewport into this control, where it was
## drawn before it was cached) or back into its picture. A diagnostic: the screenshots compare
## the two (`tests/screenshots/shot_panel_cache.gd`).
func set_live(on: bool) -> void:
	if on == is_live():
		return
	_content.reparent(self if on else _view, false)
	if on:
		# Under any live layer of this control's own, as in the picture.
		move_child(_content, 0)
	_fit()


## True while the content is drawn live (`set_live`).
func is_live() -> bool:
	return _content != null and _content.get_parent() == self


## The process frame the picture was last drawn on (for tests).
func drawn_frame() -> int:
	return _asked_frame


## True while a change waits to be drawn (hidden meanwhile; for tests).
func is_dirty() -> bool:
	return _dirty


func _get_minimum_size() -> Vector2:
	return _content.get_combined_minimum_size() if _content != null else Vector2.ZERO


func _draw() -> void:
	# Its canvas scaled since it was fitted (the HUD's layer is fitted to the picture after its
	# children are ready, and a layer's scale tells them nothing): fitted again next.
	if _view != null and get_global_transform_with_canvas().get_scale() != _scale:
		_fit.call_deferred()
	if _view != null and not is_live():
		# The picture's pixels under this control, drawn 1:1 through its scale (a layer drawn at the
		# picture's scale, PictureGrid: `_scale` picture pixels a layout pixel).
		var room := Rect2(Vector2(-PAD, -PAD), size + Vector2(PAD * 2, PAD * 2))
		draw_texture_rect_region(_view.get_texture(), room, Rect2(_origin + room.position * _scale, room.size * _scale))


## Where this control is on its screen: where the content is drawn in the picture (picture pixels;
## the content's own position is that in its canvas's pixels, the picture's divided by its scale).
func screen_origin() -> Vector2:
	return _origin


## The content takes this control's size, at its place on the screen inside a picture the screen's
## size (or here, drawn live).
func _fit() -> void:
	if _content == null:
		return
	_content.size = size
	if is_live():
		_content.position = Vector2.ZERO
		queue_redraw()
		return
	var screen := Vector2i(get_viewport().get_visible_rect().size)
	if _view.size != screen:
		_view.size = screen
	var on_screen: Transform2D = get_global_transform_with_canvas()
	var origin: Vector2 = on_screen.origin
	var by: Vector2 = on_screen.get_scale()
	if by != _scale:
		_scale = by
		_view.canvas_transform = Transform2D(0.0, by, 0.0, Vector2.ZERO)
	if origin != _origin or _content.position != origin / by:
		_origin = origin
		_content.position = origin / by
	queue_redraw()
	mark()


func _on_visibility_changed() -> void:
	if is_visible_in_tree() and _dirty:
		mark()


func _watch(node: Node) -> void:
	var item := node as CanvasItem
	if item != null:
		if not item.draw.is_connected(mark):
			item.draw.connect(mark)
		if not item.visibility_changed.is_connected(mark):
			item.visibility_changed.connect(mark)
	var control := node as Control
	if control != null and not control.item_rect_changed.is_connected(mark):
		control.item_rect_changed.connect(mark)
	if not node.child_entered_tree.is_connected(_on_child_entered):
		node.child_entered_tree.connect(_on_child_entered)
		node.child_exiting_tree.connect(_on_child_exiting)
	for child in node.get_children():
		_watch(child)


func _on_child_entered(child: Node) -> void:
	_watch(child)
	mark()


func _on_child_exiting(_child: Node) -> void:
	mark()
