extends Node
## The 4-bot smoke test as a node: four bots join on virtual devices and play the
## first room through the real input path. Bots 1-3 fight; bot 4 opens its builder with B
## (`back`) when the room starts and idles in it the whole run (the full builder, waves
## included). Bots 1-3 also build: when the room starts each builds a seeded random staff into
## staff 3 with `staff_change_requested`, and their brains (the enemies' AI, tests/bots/bot.gd)
## play it with their other staffs, so the run is played with built staffs.
##
## It passes only if
##  - `room_cleared` is received,
##  - players 1-3 (indices 0-2) are alive or revived at the end,
##  - at least one `spell_cast` happened (the bots really fired),
##  - bot 4's builder opened and was not seen closed afterwards (polled every frame). Bot 4
##    stands still and can be downed; it is not checked for that, and
##    a close while it was downed is printed as a note, not a failure, and
##  - every fighter's build went through (staff 3 holds the cards the bot chose) and no
##    `build_refused` arrived, and
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
## The performance probe (tests/benchmark/probe.gd) rides along and prints `BENCH:`
## lines at the end; it gates nothing.
##
## Either way the node prints `SMOKE OK` or `SMOKE FAILED` lines and quits with 0 or 1.
##
## Reproducibility: the game logic draws no random numbers (only cosmetic feel code
## does) and each bot's brain is seeded by its slot, so a run varies only with frame
## timing. There is no seed to set. The pass rate over repeated runs is in
## docs/LOG.md and, for the bots on the brain, docs/milestones/M2-enemy-ai.md (L5).

const BotScript := preload("res://tests/bots/bot.gd")
const ErrorLogScript := preload("res://tests/smoke/error_log.gd")
const ProbeScript := preload("res://tests/benchmark/probe.gd")

const PLAYERS: int = 4
## The index of the bot that idles in its builder (bot 4).
const IDLER: int = 3
## Bot `i` builds with the seed BUILD_SEED + i, so a failing run can be replayed.
const BUILD_SEED: int = 2026
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
var _probe: Node
var _cleared: int = 0
var _entered: int = 0
var _casts: int = 0
var _downed: Array[bool] = [false, false, false, false]
var _elapsed: float = 0.0
var _settle: int = -1
var _started: bool = false
var _logging: bool = false
var _builder_was_open: bool = false
var _builder_seen_open: bool = false
var _refusals: Array[String] = []
var _builds_failed: Array[String] = []
var _builder_closed_at: float = -1.0
var _idler_downed_at_close: bool = false


func _ready() -> void:
	OS.add_logger(_log)
	_logging = true
	_probe = ProbeScript.new()
	add_child(_probe)
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
	_events.connect("build_refused", _on_build_refused)
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


## Puts the global state back if the node is freed before it finished.
func _exit_tree() -> void:
	Engine.time_scale = 1.0
	_stop_logging()


func _stop_logging() -> void:
	if _logging:
		_logging = false
		OS.remove_logger(_log)


func _process(delta: float) -> void:
	if not _started:
		return
	_elapsed += delta
	_watch_builder()
	for bot in _bots:
		bot.step(delta)
	if _settle >= 0:
		_settle -= 1
		if _settle == 0:
			_finish(_check())
	elif _elapsed > TIME_LIMIT:
		_failures.append("room_cleared was not received within %d game seconds" % int(TIME_LIMIT))
		_finish(_check())


## Record that the idler's builder opened and when it was first closed again.
func _watch_builder() -> void:
	var builder := _hud.call("get_radial" if bool(_hud.call("uses_radial")) else "get_builder", IDLER) as Node
	var open: bool = builder != null and bool(builder.call("is_open"))
	if open:
		_builder_seen_open = true
		_builder_was_open = true
	elif _builder_was_open and _builder_closed_at < 0.0:
		_builder_closed_at = _elapsed
		_idler_downed_at_close = _downed[IDLER]


func _on_room_entered(_room_id: StringName) -> void:
	_entered += 1
	print("SMOKE: room_entered (%.1f game seconds)" % _elapsed)
	_bots[IDLER].open_builder()
	for index in IDLER:
		if not _bots[index].build_random(BUILD_SEED + index):
			_builds_failed.append("bot %d could not build a spell" % (index + 1))


func _on_room_cleared(_room_id: StringName) -> void:
	_cleared += 1
	if _settle < 0:
		_settle = SETTLE_FRAMES


func _on_spell_cast(_player: int, _spell_id: StringName, _origin: Vector2, _direction: Vector2) -> void:
	_casts += 1


func _on_build_refused(player: int, reason: String) -> void:
	_refusals.append("player %d was refused: %s" % [player + 1, reason])


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
		var wizard := _flow.call("get_wizard", index) as Actor
		if wizard == null or wizard.is_down() or _downed[index]:
			failed.append("player %d is down at the end (and was not revived)" % (index + 1))
	if _casts == 0:
		failed.append("no bot ever cast a spell")
	failed.append_array(_builds_failed)
	failed.append_array(_refusals)
	for index in IDLER:
		var wizard := _flow.call("get_wizard", index) as Actor
		var bot: BotScript = _bots[index]
		if wizard != null and not bot.built_cards.is_empty() and wizard.caster.cards_of(BotScript.BUILD_STAFF) != bot.built_cards:
			failed.append("bot %d: staff 3 is not the staff it built" % (index + 1))
	if not _builder_seen_open:
		failed.append("the builder of bot %d never opened" % (IDLER + 1))
	elif _builder_closed_at >= 0.0:
		var message: String = "the builder of bot %d closed at %.1f game seconds, after it had opened" % [IDLER + 1, _builder_closed_at]
		if _idler_downed_at_close:
			print("SMOKE NOTE: " + message + " (bot %d was downed; not a failure)" % (IDLER + 1))
		else:
			failed.append(message + " while it was not downed")
	return failed


## A recipe with every id a String and every array untyped, so StringName against String or a
## typed array against an untyped one cannot make equal recipes differ.
func _plain(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary = {}
		for key: Variant in value:
			out[str(key)] = _plain(value[key])
		return out
	if value is Array:
		var list: Array = []
		for item: Variant in value:
			list.append(_plain(item))
		return list
	if value is StringName:
		return str(value)
	return value


func _finish(failed: Array[String]) -> void:
	set_process(false)
	Engine.time_scale = 1.0
	_stop_logging()
	for bot in _bots:
		bot.leave()
	if _flow != null:
		_flow.call("stop_run")
	if _probe != null:
		_probe.call("report")
	failed.append_array(_errors())
	if failed.is_empty():
		print("SMOKE OK: 4 bots cleared the room in %.1f game seconds (%d casts), bot 4 idled in its builder, bots 1-3 built spells (%s), no errors logged" % [_elapsed, _casts, _built_text()])
		get_tree().quit(0)
	else:
		for reason in failed:
			printerr("SMOKE FAILED: " + reason)
		print("SMOKE builds: " + _built_text())
		get_tree().quit(1)


## The staffs the fighters built, for the OK line.
func _built_text() -> String:
	var parts: Array[String] = []
	for index in IDLER:
		parts.append(str((_bots[index] as BotScript).built_cards))
	return "; ".join(parts)


## Logged errors, as failure texts. Shown without an `ERROR:` prefix so the
## failure report itself is not mistaken for an engine error.
func _errors() -> Array[String]:
	var found: Array[String] = []
	var lines: Array[String] = _log.call("get_lines")
	for line in lines:
		found.append("the log has an error: " + line.trim_prefix("ERROR:").strip_edges())
	return found
