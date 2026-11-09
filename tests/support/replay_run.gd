extends RefCounted
## A run on the real game recorded through the Frames autoload and played back, each tick's state
## hashes captured (online-ready N2 and N2b, docs/milestones/online-ready.md). The replay test
## (tests/core/test_replay_game.gd) plays a run back in the same process; the platform runner
## (tests/platforms/replay_hashes_runner.gd) prints the hashes, so runs on Linux, Windows and the web
## can be compared (tools/platform_hashes.py).
##
## - **A scripted player** (`Scripted`: a frame source that reads nothing of the game, as a
##   person's input) walks, dashes, aims and casts the sandbox's staffs (the storm on LB, the fire
##   bolt) at the dummies while the "HUD" rebuilds a staff mid-run (a command): its replay plays
##   with nobody watching, and its frames are the same on every platform.
## - **Fighter bots** (tests/bots/bot.gd) play a wave and a horde run. A bot reads the game through
##   queries that fill the services' caches, and those count as state (the projectile manager's
##   threat grid and target table), so its run replays exactly with the bots watching again
##   (their frames dropped; core/sim/frames.gd).
##
## The ticks are the game's own physics steps. Each run starts from a fresh game (every autoload
## made again, tests/support/fresh_game.gd), or, with `fresh_game` off, in the same game after
## whatever ran before: a run starts from a fresh game's state either way (`Tick.begin_run`,
## online-ready N3b), which the replay test proves. Feel runs as in the game, on real time: since
## N4 it holds nothing (hit-stop is Combat's `HitStop`, counted on the game's steps), so it cannot
## part two runs. In an exported game Flow's loading screen and intro are off, so a run starts on
## the tick it is asked for, as under a test script.
##
##     var run := ReplayRun.new(tree)
##     var recorded := Desync.new()
##     var replay: Replay = await run.record(&"sandbox_requested", 0, 1, recorded)
##     var played := Desync.new()
##     await run.play(replay, 0, played)
##     # run.problems: what went wrong on the way (a bot that did not join, ...)

const BotScript := preload("res://tests/bots/bot.gd")
const FreshGame := preload("res://tests/support/fresh_game.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const TickScript := preload("res://core/sim/tick.gd")

## The tick the scripted run's "HUD" rebuilds staff 0 (a command).
const REBUILD_AT: int = 100
const REBUILT: Array[StringName] = [&"triple", &"fire", &"bolt"]
## The ticks the scripted run's pause menu opens and closes (the command `pause_requested`): the game
## stands stopped between, and a replay stands stopped there too (online-ready N4).
const PAUSE_AT: int = 150
const RESUME_AT: int = 170

## Ticks recorded and played (four seconds of game by default).
var ticks: int = 240
## False runs the projectile manager's and the swarm's GDScript instead of the native kernels.
var native: bool = true
## This machine's settings a run records with (online-ready N11: `SessionRules.machine()`; a replay
## plays by the rules in its header whatever these say): the projectile cap (0 leaves the
## platform's) and the horde's web cap (-1 leaves the platform's, 0 desktop, 1 web). The platform
## runner sets both, so every platform records the same game.
var cap: int = 0
var horde_web: int = -1
## A seat moves "Max shots" in the recorded run: at tick `x` (-1: never) it asks for the cap `y`, as
## the pause menu does (`shot_cap_requested`, a command recorded with its tick; N11).
var cap_request: Vector2i = Vector2i(-1, 0)
## The run's seed (the horde's spawns and offers, the swarm's rows), or 0 for a random one. The
## platform runner fixes it, so every platform deals the same seeds.
var run_seed: int = 0
## What went wrong on the way, in words (empty when all went as asked).
var problems: PackedStringArray = PackedStringArray()
## A tick to snapshot the recorded run after (online-ready N10; -1 for none), and the snapshot.
var snapshot_at: int = -1
var snapshot: Snapshot = null
## True: each run starts from a fresh game (every autoload made again). False: in the same game,
## after whatever ran before, as a player starts one run after another (N3b: the run starts from
## a fresh game's state all the same).
var fresh_game: bool = true

var _tree: SceneTree
var _root: Window
var _frames: Node
var _input: Node
var _flow: Node
var _feel: FeelScript


## A player that reads nothing of the game: it walks a square, turns its aim a step each tick,
## taps the storm (staff 2) and dashes (staff 0) now and then, and holds the fire bolt (staff 1) in
## bursts. Homing and chains, kept by key since N5, are played twice by test_determinism's storm.
class Scripted:
	extends FrameSource
	var tick: int = 0

	func fill_frame(frame: InputFrame, _delta: float) -> void:
		var leg: int = (tick / 40) % 4
		frame.set_move([Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP][leg] * 0.75)
		frame.aim = (tick * 700) % InputFrame.AIM_STEPS
		if tick % 90 == 2:
			frame.press(2)
		if tick % 120 == 30:
			frame.press(0)
		var burst: bool = tick % 50 < 20
		frame.hold(1, burst)
		if burst and tick % 50 == 0:
			frame.press(1)
		tick += 1


func _init(tree: SceneTree) -> void:
	_tree = tree
	_root = tree.root
	_find()


## `ticks` ticks of a run started by `start` with `bots` fighter bots and `scripted` scripted
## players (seats in that order), recorded from a fresh game; each tick's hashes go to `into`.
func record(start: StringName, bots: int, scripted: int, into: Desync) -> Replay:
	await fresh()
	var players: Array[BotScript] = _join_bots(bots)
	for at in scripted:
		_input.call("add_virtual_device", bots + at)
		_frames.call("set_source", bots + at, Scripted.new())
	# One physics step after the game is fresh, as `play` takes.
	await _tree.physics_frame
	# At the start of a physics step, before the tick: the run starts and its first tick is this step's.
	var replay: Replay = _frames.call("record", start, 0, run_seed)
	var events: Node = _root.get_node("Events")
	for i in ticks:
		await _tree.physics_frame
		_capture(into)
		if i == snapshot_at:
			snapshot = Snapshot.take(areas(), _root)
		if scripted > 0 and i == REBUILD_AT:
			# As the radial builder sends it: applied at the next tick's start, and recorded there.
			events.emit_signal("staff_cards_requested", bots, 0, REBUILT)
		if i == cap_request.x:
			events.emit_signal("shot_cap_requested", 0, cap_request.y)
		if scripted > 0 and i == PAUSE_AT:
			events.emit_signal("pause_requested", bots, 1)
		if scripted > 0 and i == RESUME_AT:
			events.emit_signal("pause_requested", bots, 0)
		if scripted > 0:
			_check_stopped(start + " recorded", i)
	replay = _frames.call("stop_recording")
	# The sandbox's staffs take any card; Play's and the horde's only their bag's.
	if scripted > 0 and ticks > REBUILD_AT + 1 and start == &"sandbox_requested":
		var wizard: Actor = _flow.call("get_wizard", bots) as Actor
		if wizard == null or wizard.caster.cards_of(0).slice(0, REBUILT.size()) != REBUILT:
			problems.append("%s: the rebuild did not apply in the recorded run" % start)
	_check_settings(start)
	for bot in players:
		bot.leave()
	return replay


## `replay` played from a fresh game, `bots` bots watching (their seats' frames dropped), each
## tick's hashes to `into`.
func play(replay: Replay, bots: int, into: Desync) -> void:
	await fresh()
	_join_bots(bots)
	await _tree.physics_frame
	if not bool(_frames.call("play", replay)):
		problems.append("%s: the replay did not play" % replay.start)
	var paused_run: bool = has_command(replay, &"pause_requested")
	for i in replay.tick_count():
		await _tree.physics_frame
		_capture(into)
		if paused_run:
			_check_stopped(replay.start + " played", i)
	if bool(_frames.call("is_playing")):
		problems.append("%s: the replay did not run out after its last tick" % replay.start)
	_check_settings(replay.start)


## `replay`'s run started in a fresh game and made as `from` says (a snapshot taken after its tick
## `tick`: a player joining it, online-ready N10), then played on from the next tick, `bots` bots
## watching; each tick's hashes from there to `into`. The snapshot's problems go to `problems`.
func resume(replay: Replay, from: Snapshot, tick: int, bots: int, into: Desync) -> void:
	await fresh()
	_join_bots(bots)
	await _tree.physics_frame
	if not bool(_frames.call("play", replay)):
		problems.append("%s: the replay did not play" % replay.start)
	for problem in from.restore(areas(), _root):
		problems.append("%s restored: %s" % [replay.start, problem])
	if not bool(_frames.call("seek", tick + 1)):
		problems.append("%s: the replay cannot go on from tick %d" % [replay.start, tick + 1])
	for i in range(tick + 1, replay.tick_count()):
		await _tree.physics_frame
		_capture(into)
	if bool(_frames.call("is_playing")):
		problems.append("%s: the replay did not run out after its last tick" % replay.start)
	_check_settings(replay.start)


## A tick inside the scripted pause stands stopped by the menu, and none outside it does (the
## commands apply at the next tick's start).
func _check_stopped(run: String, i: int) -> void:
	if i < PAUSE_AT + 2 or (i > RESUME_AT and i < RESUME_AT + 2):
		return
	var game: Sim = (_root.get_node("Tick") as TickScript).sim
	var inside: bool = i > PAUSE_AT and i <= RESUME_AT
	if game.stopped_for(&"menu") != inside:
		problems.append("%s: tick %d %s by the pause menu" % [run, i, "is not stopped" if inside else "is stopped"])


## True when some tick of `replay` carries the command `command` (the rebuild by default).
static func has_command(replay: Replay, command_name: StringName = &"staff_cards_requested") -> bool:
	var frames: Array[InputFrame] = []
	for seat in 4:
		frames.append(InputFrame.new())
	for tick in replay.tick_count():
		replay.read_tick(tick, frames)
		for frame in frames:
			for command in frame.commands:
				if command[0] == command_name:
					return true
	return false


## Whatever runs stops, and the game starts afresh (with `fresh_game`; else it goes on in the same
## game, idle).
func fresh() -> void:
	_frames.call("stop_recording")
	_frames.call("stop_playing")
	_flow.call("stop_run")
	for seat in 4:
		_frames.call("set_source", seat, null)
		_input.call("leave", seat)
	await _tree.process_frame
	await _tree.process_frame
	if fresh_game:
		FreshGame.restart(_root)
	_find()
	await _tree.physics_frame


## The game's areas by name, as the Tick names them (`state_areas`): the run's time and chance,
## the autoloads that simulate, and every actor's body by actor id.
func areas() -> Dictionary:
	return (_root.get_node("Tick") as TickScript).state_areas()


## One tick: its hashes to `into`.
func _capture(into: Desync) -> void:
	if not native:
		_kernels_off()
	into.capture(areas())


func _join_bots(count: int) -> Array[BotScript]:
	var out: Array[BotScript] = []
	for seat in count:
		var bot := BotScript.new()
		if not bot.join(seat, BotScript.Mode.FIGHTER, _input, _flow):
			problems.append("bot %d did not join" % seat)
		out.append(bot)
	return out


## The autoloads of the game now, held to the tick.
func _find() -> void:
	_frames = _root.get_node("Frames")
	_input = _root.get_node("PlayerInput")
	_flow = _root.get_node("Flow")
	_feel = _root.get_node("Feel") as FeelScript
	# In an exported game: no loading screen and no intro before a run (real time and drawing), as
	# under a test script.
	_flow.set(&"loading_enabled", false)
	_flow.set(&"intro_enabled", false)
	var machine: SessionRules = SessionRules.machine()
	machine.shot_cap = cap if cap > 0 else SessionRules.defaults().shot_cap
	if horde_web >= 0:
		machine.horde_alive = SessionRules.HORDE_ALIVE_WEB if horde_web == 1 else SessionRules.HORDE_ALIVE_DESKTOP
	else:
		machine.horde_alive = SessionRules.defaults().horde_alive
	if not native:
		_kernels_off()


## A problem when the run's shot cap is not its rules' (a machine setting applied in the run).
func _check_settings(start: StringName) -> void:
	var game: Sim = (_root.get_node("Tick") as TickScript).sim
	var now: int = int(_root.get_node("Projectiles").call("get_cap"))
	if game != null and now != game.rules.shot_cap:
		problems.append("%s: the shot cap is %d, not the run's %d" % [start, now, game.rules.shot_cap])


## Every native kernel off: the projectile manager and the swarm on their GDScript (`native`
## false), the maths and the bodies' moves on their twins (`DMath`, `WallSlide`).
func _kernels_off() -> void:
	DMath.use_native(false)
	WallSlide.use_native(false)
	_root.get_node("Projectiles").set(&"native", false)
	var swarm: Object = _root.get_node("Horde").get(&"swarm")
	if swarm != null:
		swarm.set(&"native", false)

