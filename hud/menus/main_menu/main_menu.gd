extends Control
## The main menu: the name, the tagline, the build version and the Sandbox and Play buttons.
## Play only sends the intent event `hub_requested`; the flow area hears it and takes everyone
## to the hub, where players join and start a run from the teleporter stone (docs/milestones/
## online-lobby.md, L1). The menu never calls flow and never changes the scene itself.
## In every build a Sandbox button stands above Play (owner, 2026-11-05); it sends
## `sandbox_requested`. In `dev` and `preview` builds it has the focus, so those builds start in
## the sandbox with one press (staffs B7); in the others Play has it.
## Below Play, "Fullscreen: Off" (or On) asks `Display` (core) to fill the screen: on the web a
## click or key press is what lets the browser do it (owner, 2026-10-27). F11 or Alt+Enter do the
## same anywhere.
## **Host and Join** (netcode spike S4, docs/milestones/netcode-spike.md; in every build): two
## players on two machines play a sandbox together by swapping one code each way, by copy and
## paste. The menu knows no network: it sends what its player asked (`online_host_requested`,
## `online_join_requested` with the host's code, `online_answer_requested` with the code that came
## back, `online_leave_requested`) and shows what `online_changed` says: this machine's code with a
## Copy button, a box for the other player's code, and a line of plain words. A pasted code is
## only passed on, as it is; net/ checks it.
## **Pasting** (the Paste button, or the paste keys in the box) is the menu's own: it replaces
## what the box holds with the clipboard's text, so a second paste never adds to the first. In a
## browser the clipboard reaches the game a moment after it is asked for (the engine's web build
## hands over what it held before, and the browser may first ask the player to allow it), so there
## the box is filled when the text has arrived: it is asked for at once and read again
## PASTE_CHECKS times, PASTE_WAIT apart.

const EventsScript := preload("res://core/events/events.gd")

## The player index sent with `hub_requested`: the menu is used by P1 (the mouse
## and keyboard, or the gamepad that joined first).
const MENU_PLAYER: int = 0
## The build channels where the Sandbox button has the focus (`BuildInfo.channel()`); it shows in all.
const SANDBOX_FOCUS_CHANNELS: Array[String] = ["dev", "preview"]

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
## The sandbox storm (`--storm`, tests/benchmark/sandbox_storm_runner.gd): in the Web Test export it
## is the storm on a real GPU in a browser (the owner's harness, tests/benchmark/README.md).
const STORM_ARGUMENT: String = "--storm"
const STORM_RUNNER: String = "res://tests/benchmark/sandbox_storm_runner.gd"
const STORM_NODE: String = "SandboxStormRunner"
## The replay hashes (`--replay-hashes`, tests/platforms/replay_hashes_runner.gd): the same recorded
## runs on Linux, Windows and the web, every tick's state hash printed (online-ready N2b).
const REPLAY_HASHES_ARGUMENT: String = "--replay-hashes"
const REPLAY_HASHES_RUNNER: String = "res://tests/platforms/replay_hashes_runner.gd"
const REPLAY_HASHES_NODE: String = "ReplayHashesRunner"

## Two game processes linked through Host and Join (`--online`, tests/net/online_runner.gd; netcode
## spike S4).
const ONLINE_ARGUMENT: String = "--online"
const ONLINE_RUNNER: String = "res://tests/net/online_runner.gd"
const ONLINE_NODE: String = "OnlineRunner"

## The most characters of a pasted code passed on (the box's limit; net/ has its own).
const CODE_MAX_CHARS: int = 16384
## In a browser: how often the clipboard is read again after a paste, and the seconds between.
const PASTE_CHECKS: int = 4
const PASTE_WAIT: float = 0.3
## What the online box says in each phase of `online_changed`, as the host and as the joining
## player (a phase's `note`, when it has one, is shown instead or after).
const ONLINE_TEXT: Dictionary[StringName, Array] = {
	EventsScript.ONLINE_OFF: ["", "Type the room's code below (the host opens a room at the altar in their hub), or paste a host's code, then press Connect."],
	EventsScript.ONLINE_MAKING: ["Making this machine's code...", "Connecting..."],
	EventsScript.ONLINE_CODE: [
		"Copy this machine's code and send it to the other player. Paste the code they send back below, then press Connect.",
		"Copy this machine's code and send it back to the host. The game starts when the host has given it.",
	],
	EventsScript.ONLINE_LINKING: ["Looking for the other machine...", "Looking for the other machine..."],
	EventsScript.ONLINE_LINKED: ["Found each other. Starting...", "Found each other. Joining the host..."],
	EventsScript.ONLINE_PLAYING: ["", ""],
	EventsScript.ONLINE_ENDED: ["", ""],
	EventsScript.ONLINE_FAILED: ["Cancel, then press Host to try again.", "Type the room's code or paste the host's code below and press Connect to try again."],
}

## The event bus. Only tests set this, before adding the node; otherwise the
## "Events" autoload is used.
var events: EventsScript = null

## Only tests set this: makes the node to add instead of loading the runner script.
var runner_factory: Callable = Callable()
## The build channel; `BuildInfo.channel()` unless a test sets it before adding the node.
var channel: String = BuildInfo.channel()
## The window service (`core/display`, the `Display` autoload); tests may set their own first.
var display: Node = null

@onready var _version: Label = %Version
@onready var _play: Button = %Play
@onready var _sandbox: Button = %Sandbox
@onready var _fullscreen: Button = %Fullscreen
@onready var _hint: Label = %Hint
@onready var _host: Button = %Host
@onready var _join: Button = %Join
@onready var _online: Control = %Online
@onready var _online_status: Label = %OnlineStatus
@onready var _mine_row: Control = %MineRow
@onready var _mine: LineEdit = %Mine
@onready var _copy: Button = %Copy
@onready var _theirs_row: Control = %TheirsRow
@onready var _theirs: LineEdit = %Theirs
@onready var _paste: Button = %Paste
@onready var _connect: Button = %Connect
@onready var _cancel: Button = %Cancel

## Whether this menu's player asked to host (else to join), while the online box is open.
var _hosting: bool = false
## Reads the clipboard's text (the window service's; tests give their own).
var clipboard_reader: Callable = DisplayServer.clipboard_get
## Whether the clipboard arrives a moment after it is asked for (a browser; tests may set it).
var clipboard_is_late: bool = OS.has_feature("web")
## Clipboard reads still to make after a paste, and the seconds to the next.
var _paste_checks: int = 0
var _paste_wait: float = 0.0


func _ready() -> void:
	_version.text = BuildInfo.describe()
	if events == null:
		events = get_node_or_null("/root/Events") as EventsScript
	_play.pressed.connect(_on_play_pressed)
	_sandbox.pressed.connect(_on_sandbox_pressed)
	if display == null:
		display = get_node_or_null(^"/root/Display")
	_fullscreen.pressed.connect(_on_fullscreen_pressed)
	_fullscreen.visible = display != null
	if display != null:
		display.connect(&"fullscreen_changed", func(_on: bool) -> void: _show_fullscreen())
		_show_fullscreen()
	_host.pressed.connect(_on_host_pressed)
	_join.pressed.connect(_on_join_pressed)
	_copy.pressed.connect(_on_copy_pressed)
	_paste.pressed.connect(_on_paste_pressed)
	_connect.pressed.connect(_on_connect_pressed)
	_theirs.text_submitted.connect(func(_text: String) -> void: _on_connect_pressed())
	_cancel.pressed.connect(_on_cancel_pressed)
	_theirs.max_length = CODE_MAX_CHARS
	_theirs.gui_input.connect(_on_box_input)
	set_process(false)
	if events != null:
		events.online_changed.connect(_on_online_changed)
	_sandbox.visible = true
	if SANDBOX_FOCUS_CHANNELS.has(channel):
		_sandbox.grab_focus()
	else:
		_play.grab_focus()
	print("Spellmerge %s: main menu ready" % BuildInfo.describe())
	var args: PackedStringArray = _cmdline_arguments()
	_start_four_bot_test(args)
	_start_stress_test(args)
	_start_timing_test(args)
	_start_storm(args)
	_start_replay_hashes(args)
	_start_runner(args, ONLINE_ARGUMENT, ONLINE_NODE)


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


## The same for the sandbox storm (`--storm`).
func _start_storm(args: PackedStringArray) -> bool:
	return _start_runner(args, STORM_ARGUMENT, STORM_NODE)


## The same for the replay hashes (`--replay-hashes`).
func _start_replay_hashes(args: PackedStringArray) -> bool:
	return _start_runner(args, REPLAY_HASHES_ARGUMENT, REPLAY_HASHES_NODE)


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
		STORM_NODE:
			if ResourceLoader.exists(STORM_RUNNER):
				return load("res://tests/benchmark/sandbox_storm_runner.gd") as GDScript
		REPLAY_HASHES_NODE:
			if ResourceLoader.exists(REPLAY_HASHES_RUNNER):
				return load("res://tests/platforms/replay_hashes_runner.gd") as GDScript
		ONLINE_NODE:
			if ResourceLoader.exists(ONLINE_RUNNER):
				return load("res://tests/net/online_runner.gd") as GDScript
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
	events.hub_requested.emit(MENU_PLAYER)


func _on_sandbox_pressed() -> void:
	if events == null:
		push_warning("Main menu: the Events autoload is missing, so Sandbox does nothing.")
		return
	events.sandbox_requested.emit(MENU_PLAYER)


func _on_host_pressed() -> void:
	if events == null:
		push_warning("Main menu: the Events autoload is missing, so Host does nothing.")
		return
	_hosting = true
	_open_online()
	events.online_host_requested.emit(MENU_PLAYER)


## Join opens the box for the host's code; nothing is asked of anyone until Connect.
func _on_join_pressed() -> void:
	if events == null:
		push_warning("Main menu: the Events autoload is missing, so Join does nothing.")
		return
	_hosting = false
	_open_online()
	_show_online(EventsScript.ONLINE_OFF, "", "")
	_theirs.grab_focus()


## The online box takes the place of the menu's buttons (the two do not fit the screen together).
func _open_online() -> void:
	_set_online_open(true)
	_mine.text = ""
	_theirs.text = ""


func _set_online_open(open: bool) -> void:
	_online.visible = open
	for button: Control in [_sandbox, _play, _fullscreen, _host.get_parent() as Control, _hint]:
		button.visible = not open
	if not open:
		_fullscreen.visible = display != null


func _on_copy_pressed() -> void:
	if _mine.text != "":
		DisplayServer.clipboard_set(_mine.text)
		_copy.text = "Copied"


## The box's own paste keys are the menu's (see the top): the box never pastes by itself.
func _on_box_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_paste"):
		_theirs.accept_event()
		_on_paste_pressed()


## Paste: the box holds what the clipboard holds. In a browser that text arrives a moment later.
func _on_paste_pressed() -> void:
	var text: String = String(clipboard_reader.call())
	if not clipboard_is_late:
		_fill_box(text)
		return
	_paste_checks = PASTE_CHECKS
	_paste_wait = PASTE_WAIT
	set_process(true)


func _process(delta: float) -> void:
	_paste_wait -= delta
	if _paste_wait > 0.0 or _paste_checks <= 0:
		return
	_paste_wait = PASTE_WAIT
	_paste_checks -= 1
	_fill_box(String(clipboard_reader.call()))
	if _paste_checks <= 0:
		set_process(false)


func _fill_box(text: String) -> void:
	if text != "":
		_theirs.text = text.substr(0, CODE_MAX_CHARS)
		_theirs.caret_column = _theirs.text.length()


## The other player's code is passed on as it is: the host's to Join, the one sent back to Host.
func _on_connect_pressed() -> void:
	if events == null or _theirs.text.strip_edges() == "":
		return
	if _hosting:
		events.online_answer_requested.emit(MENU_PLAYER, _theirs.text)
	else:
		events.online_join_requested.emit(MENU_PLAYER, _theirs.text)


func _on_cancel_pressed() -> void:
	_set_online_open(false)
	if events != null:
		events.online_leave_requested.emit(MENU_PLAYER)
	_host.grab_focus()


func _on_online_changed(phase: StringName, code: String, note: String) -> void:
	if _online.visible:
		_show_online(phase, code, note)


## The online box for `phase`: its line of words, this machine's code once made, and the box for
## the other's code while one is wanted (the host: once its own is made; Join: before any).
func _show_online(phase: StringName, code: String, note: String) -> void:
	var words: Array = ONLINE_TEXT.get(phase, ["", ""])
	var text: String = words[0 if _hosting else 1]
	if note != "":
		text = note if text == "" else "%s %s" % [note, text]
	elif phase == EventsScript.ONLINE_FAILED:
		text = "It did not work. " + text
	_online_status.text = text
	if _mine.text != code:
		_mine.text = code
		_copy.text = "Copy"
	_mine_row.visible = code != ""
	var wants_code: bool = phase == EventsScript.ONLINE_CODE if _hosting else (phase == EventsScript.ONLINE_OFF or phase == EventsScript.ONLINE_FAILED)
	_theirs_row.visible = wants_code


func _on_fullscreen_pressed() -> void:
	if display != null:
		display.call("toggle_fullscreen")
	_show_fullscreen()


## Writes the switch's word from the window itself.
func _show_fullscreen() -> void:
	var on: bool = display != null and bool(display.call("is_fullscreen"))
	_fullscreen.text = "Fullscreen: %s" % ("On" if on else "Off")
