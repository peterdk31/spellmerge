extends Node
## The 4-bot smoke test as a node: four bots join on virtual devices and play the
## run's first fight through the real input path. They start in the hub (the owner, 2026-11-20,
## after #886; `Frames.record` of `hub_requested`), as players do: each bot plays its hub errand
## (bench/bots/bot_hub.gd): bots 1-3 draw their starting builds from the hub's dice
## (bench/bots/bot_builds.gd: a fighter's strong staff and a dash, and bot 2's three staffs: its
## mend, a dash and the rack's Firebolt taken with A as its attack), each staff set with
## `staff_cards_requested` from a bag stocked for it (`BuildsScript.stock`, put back when the node
## goes), and all four walk onto the teleporter stone, where bot 1 presses A once it is lit: the run
## starts from the stone and every wizard carries its loadout in. The run is the crypt's biome
## (connected biomes CB8), from its start room over a bridge to the nearest fight (the bots travel,
## bench/bots/bot.gd). Bots 1-3 fight; bot 4 opens its builder with B (`back`) as the run starts and
## idles in it the whole run (the full builder, fights included), and the fighters' brains (the
## enemies' AI, bench/bots/bot.gd) play what they built.
##
## It passes only if
##  - `room_cleared` is received for a fight room (the start room's, a shop's or a reward room's,
##    which hold none, count not: `counts_as_a_fight`),
##  - players 1-3 (indices 0-2) are alive or revived at the end,
##  - at least one `spell_cast` happened (the bots really fired),
##  - bot 4's builder opened and was not seen closed afterwards (polled every frame). Bot 4
##    stands still and can be downed; it is not checked for that, and
##    a close while it was downed is printed as a note, not a failure, and
##  - every fighter carried its build into the run (each staff holds the cards of the bot's build,
##    the mender's rack staff on a hand, as the run starts and at the end) and no `build_refused`
##    arrived, and
##  - the log has no `push_error` call, no line starting `ERROR:` and no "the
##    restart failed" warning (bench/error_log.gd, which has a unit test; it
##    starts after the autoloads load, so errors during startup are not covered), and
##  - no font drew a glyph in play that was not warmed before it (core/base/glyph_warmup.gd: on a
##    separate render thread such a glyph writes the font's atlas as the render thread reads it).
## If the run does not start within HUB_LIMIT game seconds in the hub, or is not cleared within
## TIME_LIMIT game seconds of its start, the test fails.
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
## The performance probe (bench/probe.gd) rides along and prints `BENCH:`
## lines at the end; it gates nothing.
##
## Either way the node prints `SMOKE OK` or `SMOKE FAILED` lines and quits with 0 or 1. The seed
## sweep (tests/smoke/four_bot_sweep.gd) plays many runs in one process instead: it sets
## `replay_seed_wanted` and `standalone` false before adding the node, which then sends `finished`
## with its failures instead of quitting, and rides no performance probe.
##
## Reproducibility: the fight is the same, tick by tick, on every start. Each bot's brain is
## seeded by its slot, each build drawn from the hub's dice, and the hub's and the run's seeds
## (`Sim.run_seed`), which make the builds, the map and every roll of the fight (`Sim.chance`), are
## dealt from REPLAY_SEED: the node starts the hub by recording it (`Frames.record`), and the
## replay's seed deals its runs' seeds (`ReplayTape.next_run_seed`: the hub's first, the stone's
## run's next). Frame pacing changes only how many ticks fit in TIME_LIMIT's
## game seconds (the unit runs are `--fixed-fps 60`). Started with Play alone, a run takes a random
## seed (`SimSeed.fresh`), and about one seed in eleven made a fight the bots lose (a fighter
## downed and never revived, as the bots did not revive then, or a stalemate past TIME_LIMIT), which
## made this test fail by chance until the seed was pinned (tests/smoke/test_four_bot_seed.gd). The
## bots revive since 2026-11-19 (gameplay/ai/behaviours/revive.gd): the sweep of replay seeds 1-100
## on the biome run (CB8) lost 9 before and 7 after (1, 2, 65, 66, 75, 92, 99); each of those 7 is a
## fighter downed shortly before the room was cleared, a revive (2 s) not done by the checks
## SETTLE_FRAMES later: all 7 win with a 5 s settle. A
## recorded run also skips the first-time intro (Flow), which the automated runs skip anyway. The
## argument `--replay-seed=N` plays the run of replay seed N instead (0: a random one); the result
## line prints both seeds, so any run can be played again:
##
## godot --headless --fixed-fps 60 --path . --script res://tests/smoke/four_bot_smoke.gd -- --replay-seed=N
##
## **The pinned seed** (the owner's rule, 2026-11-19): REPLAY_SEED must be a seed the bots win. If a
## content change (a card, an enemy, a room, a number) makes the bots lose it, the PR making that
## change moves REPLAY_SEED to a seed they win (the sweep lists them) and says why in its
## description; it never loosens the checks. The sweep's loss rate, not this one seed, is the
## balance signal (tests/README.md, "The seed sweep").

## Sent once the run is over, when not `standalone`: its failures (empty: the bots won), and the
## replay seed and run seed it played.
signal finished(failures: Array[String], replay_seed: int, run_seed: int)

const BotScript := preload("res://bench/bots/bot.gd")
const EventsScript := preload("res://core/events/events.gd")
const ErrorLogScript := preload("res://bench/error_log.gd")
const ProbeScript := preload("res://bench/probe.gd")
const BuildsScript := preload("res://bench/bots/bot_builds.gd")

const PLAYERS: int = 4
## The index of the bot that idles in its builder (bot 4).
const IDLER: int = 3
## The seed of the replay the hub is recorded into, which deals the hub's seed and then the run's
## (see the class doc; 11: it was 8 for a while, since the crypt's longer treasure line laid seed
## 11's map with a corner walkway out of the start room the bots' travel could not cross; they walk
## every walkway since 2026-11-19, bench/bots/bot_route.gd, and win it again. Since the bots start
## in the hub, 2026-11-20, the run is the replay's second and seed 11 lays another map; the bots win
## it too, so the pin stays). Changing it, or content that changes how
## this run's fight goes, can make the run end otherwise: a failure then is the same on every start.
const REPLAY_SEED: int = 11
## The argument that plays another replay seed (`--replay-seed=N`; 0: a random one).
const REPLAY_SEED_ARGUMENT: String = "--replay-seed="
## Game seconds allowed for the room to be cleared, from the run's start (the hub's time not counted).
const TIME_LIMIT: float = 120.0
## Game seconds allowed in the hub for the bots to start the run from the stone.
const HUB_LIMIT: float = 60.0
## Frames to let the world settle after the room is cleared, then the checks run.
const SETTLE_FRAMES: int = 30

## The replay seed to play, set before the node is added (-1: as the arguments say, `--replay-seed`).
var replay_seed_wanted: int = -1
## True: the node rides the performance probe and quits the game with its result (the smoke test).
## False: it sends `finished` and leaves the game running (the sweep).
var standalone: bool = true

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
## Game seconds in the hub before the run started.
var _in_hub: float = 0.0
var _settle: int = -1
var _started: bool = false
var _logging: bool = false
var _stopped: bool = false
var _bots_left: bool = false
var _builder_was_open: bool = false
var _builder_seen_open: bool = false
var _refusals: Array[String] = []
var _builds_failed: Array[String] = []
var _builder_closed_at: float = -1.0
var _idler_downed_at_close: bool = false
## The seed of the replay the run is recorded into (REPLAY_SEED unless `--replay-seed` says), and
## the run seed it dealt.
var _replay_seed: int = REPLAY_SEED
var _run_seed: int = 0
## True once the run from the stone started (its start room entered).
var _in_run: bool = false
## The run played and its scaling, put back when the node goes.
var _run: RunDefinition = null
var _run_scaling: RunScaling = null
## Play's bag before the node stocked it for the bots' builds, put back when the node goes.
var _bag_had: Array[StringName] = []
var _bag_stocked: bool = false


func _ready() -> void:
	OS.add_logger(_log)
	_logging = true
	if standalone:
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
	_bag_had = BuildsScript.stock(_flow)
	_bag_stocked = true
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
		# The hub's errand: the fighters build for a team of IDLER, bot 1 starts the run.
		bot.plan_hub(IDLER if index != IDLER else 0, index == 0)
		_bots.append(bot)
	# Game time runs at real speed: the game never scales the engine's time (online-ready N4).
	# The hub, recorded: the replay's seed deals the hub's and the run's (the class doc,
	# "Reproducibility"). Both argument lists, as the main menu reads them (a web page's come without `--`).
	var wanted: int = replay_seed_wanted if replay_seed_wanted >= 0 else replay_seed_of(OS.get_cmdline_user_args() + OS.get_cmdline_args())
	var replay: Replay = _frames.call("record", &"hub_requested", 0, wanted) as Replay
	_replay_seed = replay.run_seed
	print("SMOKE: the hub, replay seed %d" % _replay_seed)
	_started = true


## The replay seed `args` ask for with `--replay-seed=N`, else REPLAY_SEED. A value that is not a
## whole number is REPLAY_SEED too.
static func replay_seed_of(args: PackedStringArray) -> int:
	for arg in args:
		if arg.begins_with(REPLAY_SEED_ARGUMENT):
			var value: String = arg.trim_prefix(REPLAY_SEED_ARGUMENT)
			if value.is_valid_int():
				return value.to_int()
			push_warning("FourBotRunner: '%s' is not a seed; the run plays REPLAY_SEED (%d)." % [arg, REPLAY_SEED])
	return REPLAY_SEED


## The seed of the run from the stone (0 before it started).
func run_seed() -> int:
	return _run_seed


## True once the run from the stone started.
func in_run() -> bool:
	return _in_run


## The seeds, for the result lines.
func _seeds_text() -> String:
	return "replay seed %d (run seed %d; played again with %s%d)" % [_replay_seed, _run_seed, REPLAY_SEED_ARGUMENT, _replay_seed]


## Puts the global state back if the node is freed before it finished.
## Its run is not stopped here: the tree is busy removing the node (a test that frees it calls
## `stop` first, or stops the run itself).
func _exit_tree() -> void:
	_let_go()
	if _run != null:
		_run.scaling = _run_scaling
		_run = null
	if _bag_stocked and is_instance_valid(_flow):
		_bag_stocked = false
		_flow.set(&"play_bag", _bag_had)


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
	if is_instance_valid(_frames) and bool(_frames.call("is_recording")):
		_frames.call("stop_recording")


func _stop_logging() -> void:
	if _logging:
		_logging = false
		OS.remove_logger(_log)


func _process(delta: float) -> void:
	if not _started:
		return
	if not _in_run:
		_in_hub += delta
		if _in_hub > HUB_LIMIT:
			_finish(_check())
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


func _on_room_entered(_room_id: StringName, room: int) -> void:
	# The run's start: its start room (a biome's later rooms are entered as the bots walk on; the
	# hub, entered first, is no run's).
	if _stopped or room != EventsScript.FIRST_ROOM or _flow.get(&"mode") != _flow.get(&"MODE_RUN") or _in_run:
		return
	_in_run = true
	_entered += 1
	var tick: Node = get_tree().root.get_node_or_null("Tick")
	_run_seed = int(tick.get("sim").get("run_seed")) if tick != null else 0
	print("SMOKE: room_entered from the hub's stone (after %.1f game seconds in the hub), %s" % [_in_hub, _seeds_text()])
	_bots[IDLER].open_builder()
	for index in IDLER:
		var wizard := _flow.call("get_wizard", index) as Actor
		var bot: BotScript = _bots[index]
		if bot.build.is_empty() or not bot.holds_build(wizard):
			_builds_failed.append("bot %d did not carry its build into the run (%s)" % [index + 1, bot.build.get("name", "none drawn")])


func _on_room_cleared(_room_id: StringName, room: int) -> void:
	if not counts_as_a_fight(_flow.get(&"life") as RoomLife, room):
		return
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


## True when room `room`'s clear is the fight's the test waits for: a room that holds a fight
## (`life`'s, `RoomFight.has_enemies`). The start room holds none (connected biomes CB8), nor does a
## shop or a reward room the bots walk through on their way to one: each is cleared as it is
## entered, and counts not (it ended the run before any fight, 2026-11-19).
static func counts_as_a_fight(life: RoomLife, room: int) -> bool:
	if room == EventsScript.FIRST_ROOM:
		return false
	return life != null and room >= 0 and room < life.fights.size() and life.fights[room].has_enemies()


## The failures of the finished run.
func _check() -> Array[String]:
	var failed: Array[String] = _failures.duplicate()
	if not _in_run:
		failed.append("the run never started from the hub's stone within %d game seconds (the bots' errands: %s)" % [int(HUB_LIMIT), _errands_text()])
	if _cleared == 0:
		if failed.is_empty() and _in_run:
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
		if wizard != null and not bot.build.is_empty() and not bot.holds_build(wizard):
			failed.append("bot %d: its staffs are not the build it drew (%s)" % [index + 1, bot.build["name"]])
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
	_let_go()
	if is_instance_valid(_flow) and _flow.is_inside_tree():
		_flow.call("stop_run")


## What the node holds goes back: its logger, the bots' seats and devices, the recording.
func _let_go() -> void:
	_stop_logging()
	if not _bots_left and is_instance_valid(_input) and _input.is_inside_tree():
		_bots_left = true
		for bot in _bots:
			bot.leave()
	_stop_recording()


func _finish(failed: Array[String]) -> void:
	stop()
	if _probe != null:
		_probe.call("report")
	failed.append_array(_errors())
	# A glyph drawn in play writes the font's atlas as a separate render thread reads it
	# (core/base/glyph_warmup.gd): every size drawn is warmed before play.
	for line: String in GlyphWarmup.drawn_since_warm():
		failed.append("a font drew glyphs in play, not warmed (list its size in GlyphWarmup): " + line)
	if not standalone:
		finished.emit(failed, _replay_seed, _run_seed)
		return
	if failed.is_empty():
		print("SMOKE OK: 4 bots cleared the room in %.1f game seconds (%d casts), bot 4 idled in its builder, bots 1-3 built spells (%s), no errors logged, %s" % [_elapsed, _casts, _built_text(), _seeds_text()])
		get_tree().quit(0)
	else:
		for reason in failed:
			printerr("SMOKE FAILED: " + reason)
		print("SMOKE builds: " + _built_text())
		print("SMOKE seeds: " + _seeds_text())
		get_tree().quit(1)


## Where each bot's hub errand stands (`bot_hub.gd`'s stage), for a run that never started.
func _errands_text() -> String:
	var parts: Array[String] = []
	for bot in _bots:
		parts.append("bot %d %s" % [bot.player + 1, BotScript.HubScript.Stage.keys()[bot.hub.stage] if bot.hub != null else "none"])
	return "; ".join(parts)


## The staffs the fighters built, for the OK line.
func _built_text() -> String:
	var parts: Array[String] = []
	for index in mini(IDLER, _bots.size()):
		parts.append(str((_bots[index] as BotScript).build.get("name", "none")))
	return "; ".join(parts)


## Logged errors, as failure texts. Shown without an `ERROR:` prefix so the
## failure report itself is not mistaken for an engine error.
func _errors() -> Array[String]:
	var found: Array[String] = []
	var lines: Array[String] = _log.call("get_lines")
	for line in lines:
		found.append("the log has an error: " + line.trim_prefix("ERROR:").strip_edges())
	return found
