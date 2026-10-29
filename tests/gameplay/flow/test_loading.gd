extends "res://tests/support/suite.gd"
## The loading screen before the first room (owner, 2026-10-29): the first Play of a session
## does `Flow.play_tasks` (the shader warm-up) behind it through `Loading` (state LOADING,
## `loading_started`, `loading_progressed`, `loading_finished`), then the run starts; a later Play
## starts at once; Sandbox waits the same way; a run stopped while loading starts nothing. The
## HUD's screen shows in between. Uses the real autoloads; `Loading` is stepped by hand.
##
## godot --headless --path . --script res://tests/gameplay/flow/test_loading.gd

const FlowScript := preload("res://gameplay/flow/flow.gd")
const WarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const LoadingScript := preload("res://core/loading/loading.gd")
const ScreenScript := preload("res://hud/panels/loading/loading_screen.gd")
const WarmUp := preload("res://tests/support/warm_up.gd")

var flow: FlowScript
var input: Node
var events: Node
var screen: ScreenScript
var loading: LoadingScript
var _started: int = 0
var _progressed: int = 0
var _finished: int = 0


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	input = root.get_node("PlayerInput")
	events = root.get_node("Events")
	screen = root.get_node("Hud/Root/Loading") as ScreenScript
	loading = root.get_node("Loading") as LoadingScript
	WarmupScript.warmed = false
	flow.loading_enabled = true
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	input.add_virtual_device(0)
	_started = 0
	_progressed = 0
	_finished = 0
	events.loading_started.connect(_on_started)
	events.loading_progressed.connect(_on_progressed)
	events.loading_finished.connect(_on_finished)


func after_each() -> void:
	events.loading_started.disconnect(_on_started)
	events.loading_progressed.disconnect(_on_progressed)
	events.loading_finished.disconnect(_on_finished)
	flow.stop_run()
	flow.world_parent = null
	flow.loading_enabled = false
	WarmupScript.warmed = false
	for seat in 4:
		input.leave(seat)


func _on_started() -> void:
	_started += 1


func _on_progressed(_done: int, _total: int) -> void:
	_progressed += 1


func _on_finished() -> void:
	_finished += 1


## Step the load by hand until it is done (or `frames` have passed).
func _load(frames: int = 200) -> void:
	for i in frames:
		if not loading.is_loading():
			return
		loading.step()


func test_the_first_play_loads_then_starts_the_room() -> void:
	check(flow.play_tasks().size() == 1 and flow.play_tasks()[0] is WarmupScript, "the work before a room: the shaders")
	events.play_requested.emit(0)
	check_equal(flow.state, FlowScript.State.LOADING, "the first Play loads first")
	check(flow.world == null, "no room yet")
	check_equal(_started, 1, "the loading screen is asked for")
	check(screen.visible, "and the HUD shows it")
	_load()
	check(WarmupScript.warmed, "every shader is compiled")
	check(_progressed >= WarmupScript.shaders().size(), "the bar moved with each one: %d" % _progressed)
	check_equal(_finished, 1, "the loading is over")
	check(not screen.visible, "the screen is gone")
	check_equal(flow.state, FlowScript.State.RUNNING, "and the run is on")
	check(flow.get_wizard(0) != null, "with the player's wizard")


func test_a_later_play_starts_at_once() -> void:
	events.play_requested.emit(0)
	_load()
	flow.stop_run()
	events.play_requested.emit(0)
	check(flow.play_tasks().is_empty(), "the shaders stay compiled: nothing more to load")
	check_equal(flow.state, FlowScript.State.RUNNING, "so it starts at once")
	check_equal(_started, 1, "the screen showed once")


func test_the_sandbox_loads_too() -> void:
	events.sandbox_requested.emit(0)
	check_equal(flow.state, FlowScript.State.LOADING, "the sandbox waits for the shaders as well")
	_load()
	check(flow.sandbox and flow.state == FlowScript.State.RUNNING, "then it starts")


func test_a_run_stopped_while_loading_starts_nothing() -> void:
	events.play_requested.emit(0)
	flow.stop_run()
	check_equal(flow.state, FlowScript.State.IDLE, "idle again")
	check(not loading.is_loading(), "the load is dropped")
	check_equal(_finished, 1, "the screen is told to go")
	check(not screen.visible, "and it went")
	check(flow.world == null, "no room")


func test_presses_while_loading_are_ignored() -> void:
	events.play_requested.emit(0)
	events.play_requested.emit(0)
	events.sandbox_requested.emit(0)
	check_equal(_started, 1, "one loading")
	_load()
	check(not flow.sandbox and flow.state == FlowScript.State.RUNNING, "the first press's run starts")


## The screenshot scripts and the clip recorder compile the shaders first the same way
## (tests/support/warm_up.gd): Flow's play tasks through `Loading`, waited for, the screen gone.
func test_the_rendered_runs_warm_up_like_play() -> void:
	check(await WarmUp.run(root), "the warm-up finishes")
	check(WarmupScript.warmed, "the shaders are warmed")
	check(not loading.is_loading(), "the load is over")
	check(not screen.visible, "the loading screen is gone")
	check_equal(_started, 1, "it went through the loading screen")
	check_equal(_finished, 1, "and the screen was told it is done")
	check(await WarmUp.run(root), "a second warm-up has nothing to do and says so")
	check_equal(_started, 1, "nothing more was loaded")
