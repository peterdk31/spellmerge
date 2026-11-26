extends Node
## Which frames the screenshot scripts draw (`screenshot.gd`): the game steps every frame as it
## always does, but a frame no picture is taken of need not be drawn. On a software renderer
## (llvmpipe on a CI runner) drawing the 1280 x 720 picture is most of a frame's cost, and a shot
## script waits hundreds of frames for a camera, a fight or a fire to get where its picture is.
##
## - **Off** (`drawing = false`): `RenderingServer.render_loop_enabled` is false, so the engine skips
##   the frame's draw. What the game does just before a draw still happens on that frame: this node
##   runs last in the frame's process (`process_priority`, `PROCESS_MODE_ALWAYS`) and, from the end
##   of the frame's deferred calls, emits `RenderingServer.frame_pre_draw` in the draw's place (the
##   spell light's grid, the spawn look's cut and the texture uploads step there, and each lets go
##   of what the frame handed it).
## - **On:** every frame is drawn, as without this node.
##
## The simulation never reads either (it has its own tick); only the view's history can differ: a
## floor bake shows once a frame has been drawn after it was laid (`FloorBake.step`), so
## `screenshot.gd` draws the last few frames of a wait (`settle`) before its picture.

## The highest `process_priority`: this node's `_process` runs after every other's.
const LAST: int = 2147483647

## Whether frames are drawn now.
var drawing: bool:
	get:
		return RenderingServer.render_loop_enabled
	set(on):
		RenderingServer.render_loop_enabled = on


func _init() -> void:
	name = "DrawnFrames"
	process_priority = LAST
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if not drawing:
		_stand_in.call_deferred()


func _exit_tree() -> void:
	drawing = true


## The frame's `frame_pre_draw`, for a frame that is not drawn (one that is emits its own).
func _stand_in() -> void:
	if not drawing:
		RenderingServer.frame_pre_draw.emit()
