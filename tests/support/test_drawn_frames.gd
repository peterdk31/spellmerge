extends "res://tests/support/suite.gd"
## The screenshot scripts' frame switch (tests/support/drawn_frames.gd): while the screen is not
## drawn, the views redrawn and cleared every frame (a split view) are held off at the renderer, and
## no view that keeps what it drew (the floor marks' layers) or is drawn once (a bake, a cached
## panel); the nodes keep the modes the game gave them, and a view is let go as the screen is drawn.
const DrawnFramesScript := preload("res://tests/support/drawn_frames.gd")


## A SubViewport in the tree, updated and cleared as given.
func _view(update: SubViewport.UpdateMode, clear: SubViewport.ClearMode) -> SubViewport:
	var view := own(SubViewport.new()) as SubViewport
	view.size = Vector2i(8, 8)
	view.render_target_update_mode = update
	view.render_target_clear_mode = clear
	root.add_child(view)
	return view


## The switch in the tree, the screen drawn as `drawing` says.
func _switch(drawing: bool) -> DrawnFramesScript:
	var frames := own(DrawnFramesScript.new()) as DrawnFramesScript
	root.add_child(frames)
	frames.drawing = drawing
	return frames


func test_only_a_view_drawn_afresh_every_frame_is_held_off() -> void:
	var split: SubViewport = _view(SubViewport.UPDATE_ALWAYS, SubViewport.CLEAR_MODE_ALWAYS)
	var layer: SubViewport = _view(SubViewport.UPDATE_ALWAYS, SubViewport.CLEAR_MODE_NEVER)
	var bake: SubViewport = _view(SubViewport.UPDATE_ONCE, SubViewport.CLEAR_MODE_ALWAYS)
	var frames: DrawnFramesScript = _switch(false)
	var held: Array[SubViewport] = frames.held()
	check(held.has(split), "a view redrawn and cleared every frame is held off")
	check(not held.has(layer), "a view that keeps what it drew is drawn")
	check(not held.has(bake), "a view drawn once is drawn")
	check_equal(split.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "the node keeps the game's mode")


func test_a_view_added_later_is_held_off_from_the_next_frame() -> void:
	var frames: DrawnFramesScript = _switch(false)
	var split: SubViewport = _view(SubViewport.UPDATE_ALWAYS, SubViewport.CLEAR_MODE_ALWAYS)
	await process_frame
	check(frames.held().has(split), "found as it was added, held off at the frame's end")


func test_the_views_are_let_go_as_the_screen_is_drawn() -> void:
	var split: SubViewport = _view(SubViewport.UPDATE_ALWAYS, SubViewport.CLEAR_MODE_ALWAYS)
	var frames: DrawnFramesScript = _switch(false)
	frames.drawing = true
	check(frames.held().is_empty(), "nothing held while the screen is drawn")
	frames.drawing = false
	check(frames.held().has(split), "held off again once the picture is taken")
	root.remove_child(frames)
	check(frames.held().is_empty(), "let go as the switch leaves")


func test_a_drawn_switch_holds_nothing() -> void:
	_view(SubViewport.UPDATE_ALWAYS, SubViewport.CLEAR_MODE_ALWAYS)
	var frames: DrawnFramesScript = _switch(true)
	await process_frame
	check(frames.held().is_empty(), "every view drawn as the game set it")
