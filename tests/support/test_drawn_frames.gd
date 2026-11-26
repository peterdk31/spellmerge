extends "res://tests/support/suite.gd"
## The screenshot scripts' frame switch (tests/support/drawn_frames.gd): a frame left undrawn still
## hands out the frame's `frame_pre_draw` (once, after the frame's process), and a drawn frame is
## left to the engine's own. A headless run draws no frame, so here every frame is one the engine
## does not draw: with the switch on, nothing stands in.
const DrawnFramesScript := preload("res://tests/support/drawn_frames.gd")

var _heard: int = 0


func _count() -> void:
	_heard += 1


func _frames_heard(frames: DrawnFramesScript, drawing: bool, count: int) -> int:
	frames.drawing = drawing
	_heard = 0
	RenderingServer.frame_pre_draw.connect(_count)
	for i in count:
		await process_frame
	RenderingServer.frame_pre_draw.disconnect(_count)
	return _heard


func test_an_undrawn_frame_hands_out_its_pre_draw_once() -> void:
	var frames := own(DrawnFramesScript.new()) as DrawnFramesScript
	root.add_child(frames)
	# The first frame's stand-in comes from its end; the count is of whole frames after it.
	var heard: int = await _frames_heard(frames, false, 5)
	check(heard >= 4 and heard <= 5, "about one frame_pre_draw a frame (%d in 5 frames)" % heard)


func test_a_drawn_frame_is_left_to_the_engine() -> void:
	var frames := own(DrawnFramesScript.new()) as DrawnFramesScript
	root.add_child(frames)
	check_equal(await _frames_heard(frames, true, 4), 0, "no stand-in while frames are drawn (headless draws none)")


func test_leaving_the_tree_draws_again() -> void:
	var frames := own(DrawnFramesScript.new()) as DrawnFramesScript
	root.add_child(frames)
	frames.drawing = false
	check(not RenderingServer.render_loop_enabled, "the render loop is off while frames are not drawn")
	root.remove_child(frames)
	check(RenderingServer.render_loop_enabled, "the render loop is on again once the switch has left")


func test_it_runs_last_and_while_paused() -> void:
	var frames := own(DrawnFramesScript.new()) as DrawnFramesScript
	check_equal(frames.process_priority, DrawnFramesScript.LAST, "after every other node's _process")
	check_equal(frames.process_mode, Node.PROCESS_MODE_ALWAYS, "a paused game's frames are left undrawn too")
