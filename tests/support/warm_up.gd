extends RefCounted
## Gets the screenshot scripts and the clip recorder ready the way Play does: `Flow.play_tasks()`
## (the shader warm-up, `core/projectiles/shader_warmup.gd`) run through the `Loading` autoload
## before the first thing is staged. Those runs draw with a real renderer, so every shot and clip
## is taken after the same start as a player's: the shaders compiled behind the loading screen,
## and whatever the warm-up leaves behind (it should leave nothing on the screen) in the picture.
## Their frames do not depend on how long a compile takes (`--fixed-fps`, clips stepped by hand),
## so this is about the start being the game's, not about stalls. Headless runs (the unit tests)
## have no GPU and compile nothing, so they do not need it.
##
##   if not await WarmUp.run(root):
##       fail("the warm-up did not finish")

const LoadingScript := preload("res://core/loading/loading.gd")
const LoadTask := preload("res://core/loading/load_task.gd")
## The most frames the load may take (a unit a frame; there are a few dozen).
const MAX_FRAMES: int = 600


## Runs Flow's play tasks behind the loading screen and waits until they are done (and the screen
## is gone). True when they are, or there was nothing to do; false when the Flow or Loading
## autoload is missing or the load did not finish in MAX_FRAMES.
static func run(root: Window) -> bool:
	var flow: Node = root.get_node_or_null("Flow")
	var loading := root.get_node_or_null("Loading") as LoadingScript
	if flow == null or loading == null:
		return false
	var tasks: Array[LoadTask] = []
	tasks.assign(flow.call("play_tasks"))
	var finished: Array[bool] = [false]
	if not loading.run(tasks, func() -> void: finished[0] = true):
		return not loading.is_loading()
	var tree: SceneTree = root.get_tree()
	for i in MAX_FRAMES:
		if finished[0]:
			return true
		await tree.process_frame
	loading.cancel()
	return finished[0]
