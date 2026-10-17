extends SceneTree
## 4-bot smoke test: four bots join on virtual devices and play the first room
## through the real input path. Bots 1-3 fight; bot 4 opens its overlay with the
## `overlay` action when the room starts and idles in it the whole run.
##
## It passes only if
##  - `room_cleared` is received,
##  - players 1-3 (indices 0-2) are alive or revived at the end,
##  - bot 4's overlay is still open at the end (it idled the whole time), and
##  - the log has no `push_error` call, no line starting `ERROR:` and no "the
##    restart failed" warning (a logger watches every message from the moment the
##    test starts).
## If the run is not cleared within TIME_LIMIT game seconds the test fails.
##
## godot --headless --path . --script res://tests/smoke/four_bot_smoke.gd

const BotScript := preload("res://tests/bots/bot.gd")
const InputManagerScript := preload("res://core/input/input_manager.gd")

const PLAYERS: int = 4
## The index of the bot that idles in its overlay (bot 4).
const IDLER: int = 3
## Game seconds allowed for the room to be cleared.
const TIME_LIMIT: float = 120.0
## Engine.time_scale during the run: game seconds pass faster than real ones.
const TIME_SCALE: float = 2.0
## Frames to let the world settle after the room is cleared, then the checks run.
const SETTLE_FRAMES: int = 30


## The text of the one warning that counts as a failure: Flow gives up a restart
## with a warning, not an error (docs/DECISIONS.md, "Flow").
const FAILED_RESTART: String = "the restart failed"


## Collects every error the engine logs: `push_error` and script errors arrive in
## _log_error (warnings have type ERROR_TYPE_WARNING and are ignored, except
## FAILED_RESTART), and a plain
## printed line is an error if it starts with `ERROR:`.
class ErrorLog:
	extends Logger

	var lines: Array[String] = []
	var _mutex: Mutex = Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var text: String = rationale if not rationale.is_empty() else code
		if error_type == ERROR_TYPE_WARNING and not text.contains(FAILED_RESTART):
			return
		_mutex.lock()
		lines.append("%s (%s:%d in %s)" % [text, file, line, function])
		_mutex.unlock()

	func _log_message(message: String, error: bool) -> void:
		if message.begins_with("ERROR:"):
			_mutex.lock()
			lines.append(message.strip_edges())
			_mutex.unlock()


var _log: ErrorLog = ErrorLog.new()
var _failures: Array[String] = []
var _events: Node
var _flow: Node
var _input: Node
var _hud: Node
var _bots: Array[BotScript] = []
var _cleared: int = 0
var _entered: int = 0
var _downed: Array[bool] = [false, false, false, false]
var _elapsed: float = 0.0
var _settle: int = -1
var _started: bool = false


func _initialize() -> void:
	OS.add_logger(_log)
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	_events = root.get_node_or_null("Events")
	_flow = root.get_node_or_null("Flow")
	_input = root.get_node_or_null("PlayerInput")
	_hud = root.get_node_or_null("Hud")
	if _events == null or _flow == null or _input == null or _hud == null:
		_finish(["the Events, PlayerInput, Flow and Hud autoloads must exist"])
		return
	_events.connect("room_entered", _on_room_entered)
	_events.connect("room_cleared", _on_room_cleared)
	_events.connect("player_downed", _on_player_downed)
	_events.connect("player_revived", _on_player_revived)
	for index in PLAYERS:
		var bot := BotScript.new()
		var mode: BotScript.Mode = BotScript.Mode.IDLER if index == IDLER else BotScript.Mode.FIGHTER
		if not bot.join(index, mode, _input, _flow):
			_finish(["bot %d could not take its virtual device" % (index + 1)])
			return
		_bots.append(bot)
	Engine.time_scale = TIME_SCALE
	_events.emit_signal("play_requested", 0)
	_started = true


func _process(delta: float) -> bool:
	if not _started:
		return false
	_elapsed += delta
	for bot in _bots:
		bot.step(delta)
	if _settle >= 0:
		_settle -= 1
		if _settle == 0:
			_finish(_check())
			return true
	elif _elapsed > TIME_LIMIT:
		_failures.append("room_cleared was not received within %d game seconds" % int(TIME_LIMIT))
		_finish(_check())
		return true
	return false


func _on_room_entered(_room_id: StringName) -> void:
	_entered += 1
	_bots[IDLER].tap_overlay()


func _on_room_cleared(_room_id: StringName) -> void:
	_cleared += 1
	if _settle < 0:
		_settle = SETTLE_FRAMES


func _on_player_downed(player: int) -> void:
	if player >= 0 and player < PLAYERS:
		_downed[player] = true


func _on_player_revived(player: int, _reviver: int) -> void:
	if player >= 0 and player < PLAYERS:
		_downed[player] = false


## The failures of the finished run.
func _check() -> Array[String]:
	var failed: Array[String] = _failures.duplicate()
	if _cleared == 0:
		if failed.is_empty():
			failed.append("room_cleared was never received")
	elif _cleared != 1:
		failed.append("room_cleared was received %d times, expected once" % _cleared)
	for index in IDLER:
		var wizard := _flow.call("get_wizard", index) as Node
		if wizard == null or bool(wizard.call("is_downed")) or _downed[index]:
			failed.append("player %d is down at the end (and was not revived)" % (index + 1))
	var overlay := _hud.call("get_overlay", IDLER) as Node
	if overlay == null or not bool(overlay.call("is_open")):
		failed.append("the overlay of bot %d is not open at the end: it did not idle in it the whole time" % (IDLER + 1))
	return failed


func _finish(failed: Array[String]) -> void:
	Engine.time_scale = 1.0
	for bot in _bots:
		bot.leave()
	if _flow != null:
		_flow.call("stop_run")
	failed.append_array(_errors())
	if failed.is_empty():
		print("SMOKE OK: 4 bots cleared the room in %.1f game seconds, bot 4 idled in its overlay, no errors logged" % _elapsed)
		quit(0)
	else:
		for reason in failed:
			printerr("SMOKE FAILED: " + reason)
		quit(1)


## Logged errors, as failure texts. Shown without an `ERROR:` prefix so the
## failure report itself is not mistaken for an engine error.
func _errors() -> Array[String]:
	var found: Array[String] = []
	for line in _log.lines:
		found.append("the log has an error: " + line.trim_prefix("ERROR:").strip_edges())
	return found
