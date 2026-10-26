extends Control
## The main menu: the name, the tagline, the build version and the Play button.
## Play only sends the intent event `play_requested`; the flow area hears it and
## starts the arena. The menu never calls flow and never changes the scene itself.
## In `dev` and `preview` builds a Sandbox button stands above Play and has the focus, so
## those builds start in the sandbox with one press (staffs B7); it sends `sandbox_requested`.

const EventsScript := preload("res://core/events/events.gd")

## The player index sent with `play_requested`: the menu is used by P1 (the mouse
## and keyboard, or the gamepad that joined first).
const MENU_PLAYER: int = 0
## The build channels that show the Sandbox button (`BuildInfo.channel()`).
const SANDBOX_CHANNELS: Array[String] = ["dev", "preview"]

## The user argument (`-- --four-bot`) that starts the 4-bot test, and its script.
const FOUR_BOT_ARGUMENT: String = "--four-bot"
const FOUR_BOT_RUNNER: String = "res://tests/smoke/four_bot_runner.gd"
const FOUR_BOT_NODE: String = "FourBotRunner"
## The user arguments that start the stress run and the projectile timings (tests/benchmark/),
## with the scripts and node names of their runners. Same rules as the 4-bot test.
const STRESS_ARGUMENT: String = "--stress"
const STRESS_RUNNER: String = "res://tests/benchmark/stress_runner.gd"
const STRESS_NODE: String = "StressRunner"
const TIMING_ARGUMENT: String = "--projectile-timing"
const TIMING_RUNNER: String = "res://tests/benchmark/projectile_timing_runner.gd"
const TIMING_NODE: String = "ProjectileTimingRunner"

## The event bus. Only tests set this, before adding the node; otherwise the
## "Events" autoload is used.
var events: EventsScript = null

## Only tests set this: makes the node to add instead of loading the runner script.
var runner_factory: Callable = Callable()
## The build channel; `BuildInfo.channel()` unless a test sets it before adding the node.
var channel: String = BuildInfo.channel()

@onready var _version: Label = %Version
@onready var _play: Button = %Play
@onready var _sandbox: Button = %Sandbox


func _ready() -> void:
	_version.text = BuildInfo.describe()
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	_play.pressed.connect(_on_play_pressed)
	_sandbox.pressed.connect(_on_sandbox_pressed)
	_sandbox.visible = SANDBOX_CHANNELS.has(channel)
	if _sandbox.visible:
		_sandbox.grab_focus()
	else:
		_play.grab_focus()
	print("Spellmerge %s: main menu ready" % BuildInfo.describe())
	var args: PackedStringArray = _cmdline_arguments()
	_start_four_bot_test(args)
	_start_stress_test(args)
	_start_timing_test(args)


## Every command line argument, with or without a "--" before it. The web page
## config (`args`) may pass `--four-bot` without one, so look in both lists.
func _cmdline_arguments() -> PackedStringArray:
	return OS.get_cmdline_user_args() + OS.get_cmdline_args()


## Starts the 4-bot test when `args` has the 4-bot argument. Only the `Linux Test`
## export keeps tests/, so the runner is added only where its script exists; in
## every other build the argument logs a warning and does nothing. Returns true if
## a runner was queued. Only one is ever added, even if the menu is entered again.
func _start_four_bot_test(args: PackedStringArray) -> bool:
	return _start_runner(args, FOUR_BOT_ARGUMENT, FOUR_BOT_NODE)


## The same for the stress run (`--stress`, tests/benchmark/stress_runner.gd).
func _start_stress_test(args: PackedStringArray) -> bool:
	return _start_runner(args, STRESS_ARGUMENT, STRESS_NODE)


## The same for the projectile timings (`--projectile-timing`).
func _start_timing_test(args: PackedStringArray) -> bool:
	return _start_runner(args, TIMING_ARGUMENT, TIMING_NODE)


func _start_runner(args: PackedStringArray, argument: String, node_name: String) -> bool:
	if not argument in args:
		return false
	var runner: Node = null
	if runner_factory.is_valid():
		runner = runner_factory.call() as Node
	else:
		runner = _make_runner(node_name)
	if runner == null:
		push_warning("Main menu: %s needs a build that includes tests/; ignored." % argument)
		return false
	runner.name = node_name
	# On the root, so the node outlives this menu when the flow swaps the scene.
	_add_runner.call_deferred(runner)
	return true


## The runner of a node name, or null when its script is not in the build.
func _make_runner(node_name: String) -> Node:
	var script: GDScript = _runner_script(node_name)
	return script.new() as Node if script != null else null


## The script of a runner, or null. Literal paths only (computed ones are not allowed
## here): the main menu test checks each equals its *_RUNNER constant.
func _runner_script(node_name: String) -> GDScript:
	match node_name:
		FOUR_BOT_NODE:
			if ResourceLoader.exists(FOUR_BOT_RUNNER):
				return load("res://tests/smoke/four_bot_runner.gd") as GDScript
		STRESS_NODE:
			if ResourceLoader.exists(STRESS_RUNNER):
				return load("res://tests/benchmark/stress_runner.gd") as GDScript
		TIMING_NODE:
			if ResourceLoader.exists(TIMING_RUNNER):
				return load("res://tests/benchmark/projectile_timing_runner.gd") as GDScript
	return null


## Only one runner is ever added with a name, even if the menu is entered again.
func _add_runner(runner: Node) -> void:
	var root: Node = get_tree().root
	if root.has_node(NodePath(runner.name)):
		runner.free()
		return
	root.add_child(runner)


func _on_play_pressed() -> void:
	if events == null:
		push_warning("Main menu: the Events autoload is missing, so Play does nothing.")
		return
	events.play_requested.emit(MENU_PLAYER)


func _on_sandbox_pressed() -> void:
	if events == null:
		push_warning("Main menu: the Events autoload is missing, so Sandbox does nothing.")
		return
	events.sandbox_requested.emit(MENU_PLAYER)
