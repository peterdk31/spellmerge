extends Control
## The main menu: the name, the tagline, the build version and the Play button.
## Play only sends the intent event `play_requested`; the flow area hears it and
## starts the arena. The menu never calls flow and never changes the scene itself.

const EventsScript := preload("res://core/events/events.gd")

## The player index sent with `play_requested`: the menu is used by P1 (the mouse
## and keyboard, or the gamepad that joined first).
const MENU_PLAYER: int = 0

## The user argument (`-- --four-bot`) that starts the 4-bot test, and its script.
const FOUR_BOT_ARGUMENT: String = "--four-bot"
const FOUR_BOT_RUNNER: String = "res://tests/smoke/four_bot_runner.gd"
const FOUR_BOT_NODE: String = "FourBotRunner"

## The event bus. Only tests set this, before adding the node; otherwise the
## "Events" autoload is used.
var events: EventsScript = null

## Only tests set this: makes the node to add instead of loading the runner script.
var runner_factory: Callable = Callable()

@onready var _version: Label = %Version
@onready var _play: Button = %Play


func _ready() -> void:
	_version.text = BuildInfo.describe()
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	_play.pressed.connect(_on_play_pressed)
	_play.grab_focus()
	print("Spellmerge %s: main menu ready" % BuildInfo.describe())
	_start_four_bot_test(OS.get_cmdline_user_args())


## Starts the 4-bot test when `args` has the 4-bot argument. Only the `Linux Test`
## export keeps tests/, so the runner is added only where its script exists; in
## every other build the argument logs a warning and does nothing. Returns true if
## a runner was queued. Only one is ever added, even if the menu is entered again.
func _start_four_bot_test(args: PackedStringArray) -> bool:
	if not FOUR_BOT_ARGUMENT in args:
		return false
	var runner: Node = null
	if runner_factory.is_valid():
		runner = runner_factory.call() as Node
	elif ResourceLoader.exists(FOUR_BOT_RUNNER):
		# A literal path (computed ones are not allowed here): keep it equal to FOUR_BOT_RUNNER.
		runner = (load("res://tests/smoke/four_bot_runner.gd") as GDScript).new() as Node
	if runner == null:
		push_warning("Main menu: %s needs a build that includes tests/; ignored." % FOUR_BOT_ARGUMENT)
		return false
	runner.name = FOUR_BOT_NODE
	# On the root, so the node outlives this menu when the flow swaps the scene.
	_add_runner.call_deferred(runner)
	return true


func _add_runner(runner: Node) -> void:
	var root: Node = get_tree().root
	if root.has_node(NodePath(FOUR_BOT_NODE)):
		runner.free()
		return
	root.add_child(runner)


func _on_play_pressed() -> void:
	if events == null:
		push_warning("Main menu: the Events autoload is missing, so Play does nothing.")
		return
	events.play_requested.emit(MENU_PLAYER)
