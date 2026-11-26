extends Node
## Which frames the screenshot scripts draw the screen of (`screenshot.gd`): the game steps and the
## engine draws every frame as it always does, but what is drawn afresh every frame and kept by
## nothing (the screen, a split screen's views) is drawn only on a frame a picture is taken of. On a
## software renderer (llvmpipe on a CI runner) the 1280 x 720 picture is most of a frame's cost, and
## a shot script waits hundreds of frames for a camera, a fight or a fire to get where its picture is.
##
## - **Off** (`drawing = false`): the root viewport draws no 2D (`viewport_set_disable_2d`), and each
##   SubViewport the game redraws and clears every frame (UPDATE_ALWAYS, CLEAR_MODE_ALWAYS: a split
##   view) is not updated (`viewport_set_update_mode`, at the renderer only; the node keeps the mode
##   the game gave it). Everything else in the frame's draw happens: a view that keeps a history or
##   is drawn once (the floor marks' layers, a floor's bake, a cached panel, the damage numbers'
##   sheet) is drawn when the game asks, `frame_pre_draw` is emitted and the frames drawn are counted.
## - **On:** every view is drawn as the game set it, as without this node.
##
## What is skipped is cleared before every draw, so a frame drawn after any number of frames left
## off shows what a frame drawn every time would.

## The highest `process_priority`: this node's `_process` runs after every other's.
const LAST: int = 2147483647

## Whether the screen is drawn now.
var drawing: bool = true:
	set(on):
		drawing = on
		if is_inside_tree():
			_apply()

## Whether the screen was last left drawn (`_apply`).
var _shown: bool = true
## The SubViewports in the tree (found as they are added).
var _views: Array[SubViewport] = []
## The views this node holds off at the renderer now.
var _held: Array[SubViewport] = []


func _init() -> void:
	name = "DrawnFrames"
	# After every other node's `_process`, so a view the game shows this frame is held off too.
	process_priority = LAST
	process_mode = Node.PROCESS_MODE_ALWAYS


func _enter_tree() -> void:
	var tree: SceneTree = get_tree()
	for found: Node in tree.root.find_children("*", "SubViewport", true, false):
		_views.append(found as SubViewport)
	tree.node_added.connect(_on_added)
	_apply()


func _exit_tree() -> void:
	get_tree().node_added.disconnect(_on_added)
	drawing = true
	_apply()


func _process(_delta: float) -> void:
	if not drawing:
		_hold_views()


func _on_added(node: Node) -> void:
	if node is SubViewport:
		_views.append(node as SubViewport)


## The screen drawn or not as `drawing` says; the views held off now, or let go.
func _apply() -> void:
	if drawing != _shown:
		_shown = drawing
		RenderingServer.viewport_set_disable_2d(get_tree().root.get_viewport_rid(), not drawing)
	if drawing:
		_let_go()
	else:
		_hold_views()


## Hold off every view that is redrawn and cleared every frame (none keeps it); the rest as they are.
func _hold_views() -> void:
	_let_go()
	for i in range(_views.size() - 1, -1, -1):
		var view: SubViewport = _views[i]
		if not is_instance_valid(view):
			_views.remove_at(i)
			continue
		if view.is_inside_tree() and view.render_target_update_mode == SubViewport.UPDATE_ALWAYS and view.render_target_clear_mode == SubViewport.CLEAR_MODE_ALWAYS:
			RenderingServer.viewport_set_update_mode(view.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_DISABLED)
			_held.append(view)


## Every held view back, at the renderer, to the mode its node says.
func _let_go() -> void:
	for view: SubViewport in _held:
		if is_instance_valid(view):
			RenderingServer.viewport_set_update_mode(view.get_viewport_rid(), view.render_target_update_mode as RenderingServer.ViewportUpdateMode)
	_held.clear()


## The views held off now (for tests).
func held() -> Array[SubViewport]:
	return _held.duplicate()
