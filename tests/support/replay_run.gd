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
## online-ready N3b), which the replay test proves. What still runs on real time is held to the
## tick here, as the plan leaves it to N4: Feel's stops (its clock is real time) are frozen. In an exported game Flow's loading screen and intro are off too, so a run
## starts on the tick it is asked for, as under a test script.
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

## The tick the scripted run's "HUD" rebuilds staff 0 (a command).
const REBUILD_AT: int = 100
const REBUILT: Array[StringName] = [&"triple", &"fire", &"bolt"]

## Ticks recorded and played (four seconds of game by default).
var ticks: int = 240
## False runs the projectile manager's and the swarm's GDScript instead of the native kernels.
var native: bool = true
## The per-machine settings the simulation reads (A10; N11 makes them a run's): the projectile cap
## (0 leaves the platform's) and the horde's web cap (-1 leaves the platform's, 0 desktop, 1 web).
## The platform runner sets both, so every platform plays the same game.
var cap: int = 0
var horde_web: int = -1
## The run's seed (the horde's spawns and offers, the swarm's rows), or 0 for a random one. The
## platform runner fixes it, so every platform deals the same seeds.
var run_seed: int = 0
## What went wrong on the way, in words (empty when all went as asked).
var problems: PackedStringArray = PackedStringArray()
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
## bursts. Not the decoy turret: its homing bolts keep their targets by instance id (A5, N5).
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
		if scripted > 0 and i == REBUILD_AT:
			# As the radial builder sends it: applied at the next tick's start, and recorded there.
			events.emit_signal("staff_cards_requested", bots, 0, REBUILT)
	replay = _frames.call("stop_recording")
	if scripted > 0 and ticks > REBUILD_AT + 1:
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
	for i in replay.tick_count():
		await _tree.physics_frame
		_capture(into)
	if bool(_frames.call("is_playing")):
		problems.append("%s: the replay did not run out after its last tick" % replay.start)
	_check_settings(replay.start)


## True when some tick of `replay` carries a `staff_cards_requested` command (the rebuild).
static func has_command(replay: Replay) -> bool:
	var frames: Array[InputFrame] = []
	for seat in 4:
		frames.append(InputFrame.new())
	for tick in replay.tick_count():
		replay.read_tick(tick, frames)
		for frame in frames:
			for command in frame.commands:
				if command[0] == &"staff_cards_requested":
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
	return _root.get_node("Tick").call(&"state_areas")


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
	# Feel's stops end by real time (A1): frozen, they hold the same bodies in both runs (N4).
	_feel.drive_engine = false
	_feel.set_process(false)
	# In an exported game: no loading screen and no intro before a run (real time and drawing), as
	# under a test script.
	_flow.set(&"loading_enabled", false)
	_flow.set(&"intro_enabled", false)
	if cap > 0:
		_root.get_node("Projectiles").call("set_cap", cap)
	if horde_web >= 0:
		_root.get_node("Horde").set(&"web", horde_web == 1)
	if not native:
		_kernels_off()


## A problem when a setting asked for changed during the run (a saved setting applied late).
func _check_settings(start: StringName) -> void:
	if cap > 0 and int(_root.get_node("Projectiles").call("get_cap")) != cap:
		problems.append("%s: the shot cap changed during the run (%d, not %d)" % [start, int(_root.get_node("Projectiles").call("get_cap")), cap])


## The projectile manager and the swarm on their GDScript (`native` false).
func _kernels_off() -> void:
	_root.get_node("Projectiles").set(&"native", false)
	var swarm: Object = _root.get_node("Horde").get(&"swarm")
	if swarm != null:
		swarm.set(&"native", false)

