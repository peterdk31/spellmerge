extends Node
## The 4-bot smoke test as a node: four bots join on virtual devices and play the
## first room through the real input path. Bots 1-3 fight; bot 4 opens its builder with B
## (`back`) when the room starts and idles in it the whole run (the full builder, fights
## included). Bots 1-3 also build: when the room starts each builds a seeded random staff into
## staff 1 (RB, `BotScript.BUILD_STAFF`) with `staff_change_requested`, and their brains (the enemies' AI, tests/bots/bot.gd)
## play it with their other staffs, so the run is played with built staffs.
##
## It passes only if
##  - `room_cleared` is received,
##  - players 1-3 (indices 0-2) are alive or revived at the end,
##  - at least one `spell_cast` happened (the bots really fired),
##  - bot 4's builder opened and was not seen closed afterwards (polled every frame). Bot 4
##    stands still and can be downed; it is not checked for that, and
##    a close while it was downed is printed as a note, not a failure, and
##  - every fighter's build went through (staff 1 holds the cards the bot chose) and no
##    `build_refused` arrived, and
##  - the log has no `push_error` call, no line starting `ERROR:` and no "the
##    restart failed" warning (tests/smoke/error_log.gd, which has a unit test; it
##    starts after the autoloads load, so errors during startup are not covered).
## If the run is not cleared within TIME_LIMIT game seconds the test fails.
##
## The run is played unscaled (the run definition's `scaling` off while the test runs, run
## generation RG5): three of its four seats fight, so a room scaled for four players would test
## the balance (and fail by chance), not the game's paths. The scaling's own tests:
## tests/gameplay/difficulty/test_difficulty.gd and tests/gameplay/run/test_run_generator.gd.
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
## Reproducibility: the run is the same on every start. Each bot's brain is seeded by its slot,
## each build by BUILD_SEED, the frames are fixed (`--fixed-fps 60`), and the run's seed, which
## makes the map and every roll of the fight (`Sim.chance`), is RUN_SEED: the node starts the run by
## recording it (`Frames.record`), so its seed is dealt from RUN_SEED, a restart's too. Started
## with Play alone, a run takes a random seed (`SimSeed.fresh`), and about one seed in ten makes a
## fight the bots lose a fighter in (a downed bot is never revived: the bots do not revive), which
## made this test fail by chance until the seed was pinned. The user argument `--run-seed=N` plays
## the run of seed N instead (0: a random one); the seed is printed in the result line, so any run
## can be played again:
##
## godot --headless --fixed-fps 60 --path . --script res://tests/smoke/four_bot_smoke.gd -- --run-seed=N

const BotScript := preload("res://tests/bots/bot.gd")
const ErrorLogScript := preload("res://tests/smoke/error_log.gd")
const ProbeScript := preload("res://tests/benchmark/probe.gd")

const PLAYERS: int = 4
## The index of the bot that idles in its builder (bot 4).
const IDLER: int = 3
## Bot `i` builds with the seed BUILD_SEED + i, so a failing run can be replayed.
const BUILD_SEED: int = 2026
## The seed of the replay the run is recorded into, which deals the run's seed (see the class doc).
## Changing it, or content that changes how this run's fight goes, can make the run end otherwise:
## a failure then is the same on every start, played again with `--run-seed`.
const RUN_SEED: int = 11
## The user argument that plays another seed than RUN_SEED (`--run-seed=N`; 0: a random one).
const RUN_SEED_ARGUMENT: String = "--run-seed="
## Game seconds allowed for the room to be cleared.
const TIME_LIMIT: float = 120.0
## Frames to let the world settle after the room is cleared, then the checks run.
const SETTLE_FRAMES: int = 30

var _log: Logger = ErrorLogScript.new()
var _failures: Array[String] = []
var _events: Node
var _flow: Node
var _input: Node
var _frames: Node
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
var _stopped: bool = false
var _builder_was_open: bool = false
var _builder_seen_open: bool = false
var _refusals: Array[String] = []
var _builds_failed: Array[String] = []
var _builder_closed_at: float = -1.0
var _idler_downed_at_close: bool = false
## The seed of the replay the run is recorded into (RUN_SEED unless `--run-seed` says).
var _run_seed: int = RUN_SEED
## The run played and its scaling, put back when the node goes.
var _run: RunDefinition = null
var _run_scaling: RunScaling = null


func _ready() -> void:
	OS.add_logger(_log)
	_logging = true
	_probe = ProbeScript.new()
	add_child(_probe)
	var root: Node = get_tree().root
	_events = root.get_node_or_null("Events")
	_flow = root.get_node_or_null("Flow")
	_input = root.get_node_or_null("PlayerInput")
	_frames = root.get_node_or_null("Frames")
	_hud = root.get_node_or_null("Hud")
	if _events == null or _flow == null or _input == null or _frames == null or _hud == null:
		_finish(["the Events, PlayerInput, Frames, Flow and Hud autoloads must exist"])
		return
	_play_unscaled(root)
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
	# Game time runs at real speed: the game never scales the engine's time (online-ready N4).
	# Play, recorded: the replay's seed deals the run's (the class doc, "Reproducibility").
	var replay: Replay = _frames.call("record", &"play_requested", 0, run_seed_of(OS.get_cmdline_user_args())) as Replay
	_run_seed = replay.run_seed if replay != null else 0
	print("SMOKE: run seed %d" % _run_seed)
	_started = true


## The seed `args` (the user arguments) ask for with `--run-seed=N`, else RUN_SEED. A value that
## is not a whole number is RUN_SEED too.
static func run_seed_of(args: PackedStringArray) -> int:
	for arg in args:
		if arg.begins_with(RUN_SEED_ARGUMENT):
			var value: String = arg.trim_prefix(RUN_SEED_ARGUMENT)
			if value.is_valid_int():
				return value.to_int()
			push_warning("FourBotRunner: '%s' is not a seed; the run plays RUN_SEED (%d)." % [arg, RUN_SEED])
	return RUN_SEED


## Puts the global state back if the node is freed before it finished.
func _exit_tree() -> void:
	_stop_logging()
	_stop_recording()
	if _run != null:
		_run.scaling = _run_scaling
		_run = null


## The run Play starts, with its scaling off until the node goes (see the class doc).
func _play_unscaled(root: Node) -> void:
	var registry: Node = root.get_node_or_null("Registry")
	if registry == null:
		return
	_run = registry.call("get_resource", &"runs", _flow.get(&"run_id_to_play")) as RunDefinition
	if _run != null:
		_run_scaling = _run.scaling
		_run.scaling = null


## The recording ends with the run (nothing reads it: it is how the run's seed is set).
func _stop_recording() -> void:
	if _frames != null and bool(_frames.call("is_recording")):
		_frames.call("stop_recording")


func _stop_logging() -> void:
	if _logging:
		_logging = false
		OS.remove_logger(_log)


func _process(delta: float) -> void:
	if not _started:
		return
	_elapsed += delta
	_watch_builder()
	# The bots think at each tick's start, filling their seats' frames (the Frames autoload).
	if _settle >= 0:
		_settle -= 1
		if _settle == 0:
			_finish(_check())
	elif _elapsed > TIME_LIMIT:
		_failures.append("room_cleared was not received within %d game seconds" % int(TIME_LIMIT))
		_finish(_check())


## Record that the idler's builder opened and when it was first closed again.
func _watch_builder() -> void:
	var builder := _hud.call("get_radial", IDLER) as Node
	var open: bool = builder != null and bool(builder.call("is_open"))
	if open:
		_builder_seen_open = true
		_builder_was_open = true
	elif _builder_was_open and _builder_closed_at < 0.0:
		_builder_closed_at = _elapsed
		_idler_downed_at_close = _downed[IDLER]


func _on_room_entered(_room_id: StringName, _room: int) -> void:
	_entered += 1
	print("SMOKE: room_entered (%.1f game seconds)" % _elapsed)
	_bots[IDLER].open_builder()
	for index in IDLER:
		if not _bots[index].build_random(BUILD_SEED + index):
			_builds_failed.append("bot %d could not build a spell" % (index + 1))


func _on_room_cleared(_room_id: StringName, _room: int) -> void:
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
			failed.append("bot %d: staff 1 is not the staff it built" % (index + 1))
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


## End the run without a verdict: the bots leave, the run stops and the recording ends
## (`_finish` does this first; a test that only starts the node calls it, tests/smoke/test_four_bot_seed.gd).
func stop() -> void:
	if _stopped:
		return
	_stopped = true
	set_process(false)
	_stop_logging()
	for bot in _bots:
		bot.leave()
	if _flow != null:
		_flow.call("stop_run")
	_stop_recording()


func _finish(failed: Array[String]) -> void:
	stop()
	if _probe != null:
		_probe.call("report")
	failed.append_array(_errors())
	if failed.is_empty():
		print("SMOKE OK: 4 bots cleared the room in %.1f game seconds (%d casts), bot 4 idled in its builder, bots 1-3 built spells (%s), no errors logged (run seed %d)" % [_elapsed, _casts, _built_text(), _run_seed])
		get_tree().quit(0)
	else:
		for reason in failed:
			printerr("SMOKE FAILED: " + reason)
		print("SMOKE builds: " + _built_text())
		print("SMOKE run seed: %d (played again with the user argument %s%d)" % [_run_seed, RUN_SEED_ARGUMENT, _run_seed])
		get_tree().quit(1)


## The staffs the fighters built, for the OK line.
func _built_text() -> String:
	var parts: Array[String] = []
	for index in mini(IDLER, _bots.size()):
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
