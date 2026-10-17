extends Node
## The 4-bot smoke test as a node: four bots join on virtual devices and play the
## first room through the real input path. Bots 1-3 fight; bot 4 opens its overlay
## with the `overlay` action when the room starts and idles in it the whole run.
##
## It passes only if
##  - `room_cleared` is received,
##  - players 1-3 (indices 0-2) are alive or revived at the end,
##  - at least one `spell_cast` happened (the bots really fired),
##  - bot 4's overlay opened and was never seen closed afterwards (polled every
##    frame). Bot 4 stands still and can be downed; it is not checked for that, and
##    a close while it was downed is printed as a note, not a failure, and
##  - the log has no `push_error` call, no line starting `ERROR:` and no "the
##    restart failed" warning (tests/smoke/error_log.gd, which has a unit test; it
##    starts after the autoloads load, so errors during startup are not covered).
## If the run is not cleared within TIME_LIMIT game seconds the test fails.
##
## Two ways to start it. `four_bot_smoke.gd` (a SceneTree script, for
## `build.sh --quick --tests`) adds this node to the root. The main menu adds it when
## the game is started with the user argument `--four-bot` and this file is in the
## build (only the `Linux Test` export keeps tests/). An exported binary can't run a
## SceneTree script (it hangs while the autoloads start), so this is how the test
## runs there:
##
## build/linux-test/Spellmerge.x86_64 --headless -- --four-bot
##
## Either way the node prints `SMOKE OK` or `SMOKE FAILED` lines and quits with 0 or 1.
##
## Reproducibility: the game logic draws no random numbers (only cosmetic feel code
## does) and the bots decide from the world, so a run varies only with frame
## timing. There is no seed to set. The pass rate over repeated runs is in
## docs/LOG.md.

const BotScript := preload("res://tests/bots/bot.gd")
const ErrorLogScript := preload("res://tests/smoke/error_log.gd")

const PLAYERS: int = 4
## The index of the bot that idles in its overlay (bot 4).
const IDLER: int = 3
## Game seconds allowed for the room to be cleared.
const TIME_LIMIT: float = 120.0
## Engine.time_scale during the run: game seconds pass faster than real ones.
const TIME_SCALE: float = 2.0
## Frames to let the world settle after the room is cleared, then the checks run.
const SETTLE_FRAMES: int = 30

var _log: Logger = ErrorLogScript.new()
var _failures: Array[String] = []
var _events: Node
var _flow: Node
var _input: Node
var _hud: Node
var _bots: Array[BotScript] = []
var _cleared: int = 0
var _entered: int = 0
var _casts: int = 0
var _downed: Array[bool] = [false, false, false, false]
var _elapsed: float = 0.0
var _settle: int = -1
var _started: bool = false
var _overlay_seen_open: bool = false
var _overlay_closed_at: float = -1.0
var _idler_downed_at_close: bool = false


func _ready() -> void:
	OS.add_logger(_log)
	var root: Node = get_tree().root
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
	_events.connect("spell_cast", _on_spell_cast)
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


func _process(delta: float) -> void:
	if not _started:
		return
	_elapsed += delta
	_watch_overlay()
	for bot in _bots:
		bot.step(delta)
	if _settle >= 0:
		_settle -= 1
		if _settle == 0:
			_finish(_check())
	elif _elapsed > TIME_LIMIT:
		_failures.append("room_cleared was not received within %d game seconds" % int(TIME_LIMIT))
		_finish(_check())


## Record that the idler's overlay opened and when it was first closed again.
func _watch_overlay() -> void:
	var overlay := _hud.call("get_overlay", IDLER) as Node
	var open: bool = overlay != null and bool(overlay.call("is_open"))
	if open:
		_overlay_seen_open = true
	elif _overlay_seen_open and _overlay_closed_at < 0.0:
		_overlay_closed_at = _elapsed
		_idler_downed_at_close = _downed[IDLER]


func _on_room_entered(_room_id: StringName) -> void:
	_entered += 1
	_bots[IDLER].tap_overlay()


func _on_room_cleared(_room_id: StringName) -> void:
	_cleared += 1
	if _settle < 0:
		_settle = SETTLE_FRAMES


func _on_spell_cast(_player: int, _spell_id: StringName, _origin: Vector2, _direction: Vector2) -> void:
	_casts += 1


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
	if _casts == 0:
		failed.append("no bot ever cast a spell")
	if not _overlay_seen_open:
		failed.append("the overlay of bot %d never opened" % (IDLER + 1))
	elif _overlay_closed_at >= 0.0:
		var message: String = "the overlay of bot %d closed at %.1f game seconds, after it had opened" % [IDLER + 1, _overlay_closed_at]
		if _idler_downed_at_close:
			print("SMOKE NOTE: " + message + " (bot %d was downed; not a failure)" % (IDLER + 1))
		else:
			failed.append(message + " while it was not downed")
	return failed


func _finish(failed: Array[String]) -> void:
	set_process(false)
	Engine.time_scale = 1.0
	OS.remove_logger(_log)
	for bot in _bots:
		bot.leave()
	if _flow != null:
		_flow.call("stop_run")
	failed.append_array(_errors())
	if failed.is_empty():
		print("SMOKE OK: 4 bots cleared the room in %.1f game seconds (%d casts), bot 4 idled in its overlay, no errors logged" % [_elapsed, _casts])
		get_tree().quit(0)
	else:
		for reason in failed:
			printerr("SMOKE FAILED: " + reason)
		get_tree().quit(1)


## Logged errors, as failure texts. Shown without an `ERROR:` prefix so the
## failure report itself is not mistaken for an engine error.
func _errors() -> Array[String]:
	var found: Array[String] = []
	var lines: Array[String] = _log.call("get_lines")
	for line in lines:
		found.append("the log has an error: " + line.trim_prefix("ERROR:").strip_edges())
	return found
