extends "res://tests/support/suite.gd"
## Determinism on the real game, through a replay (online-ready N2, docs/milestones/online-ready.md):
## a run on the real autoloads (Flow, Coop, the wizards' PlayerControllers, the spell runtime, the
## projectile manager, Combat, the AI) is recorded by the Frames autoload, and the replay played
## back from the same start gives the same state hash in every area at every tick. When they part,
## the desync report names the first tick, the areas and each differing member.
##
## - **A scripted player** (`Scripted`: a frame source that reads nothing of the game, as a
##   person's input) walks, dashes, aims and casts the sandbox's staffs (the storm on LB, the fire
##   bolt) at the dummies while the "HUD" rebuilds a staff mid-run (a command): its replay plays
##   with nobody watching.
## - **Fighter bots** (tests/bots/bot.gd) play a wave and a horde run. A bot reads the game through
##   queries that fill the services' caches, and those count as state (the projectile manager's
##   threat grid and target table), so its run replays exactly with the bots watching again
##   (their frames dropped; core/sim/frames.gd).
##
## The ticks are the game's own physics steps. Each run starts from a fresh game (every autoload
## made again, tests/support/fresh_game.gd) the same number of steps before its start, as a replay
## is played after the game starts: the services' clocks run from the game's start and their
## counters carry over from run to run (N3 starts the one clock with the run). What still runs on
## real time is held to the tick here, as the plan leaves it to later parts: Feel's stops (its clock
## is real time; N4 counts them in ticks) are frozen, and the `_process` timers of Flow, Coop's
## revive and the horde director (its spawns, offers and breaks) are stepped once a tick by the test
## instead of once a drawn frame, as N3's tick will step them (A2).

const BotScript := preload("res://tests/bots/bot.gd")
const FreshGame := preload("res://tests/support/fresh_game.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")

## Ticks recorded and played (four seconds of game).
const TICKS: int = 240
## A tick's seconds.
const DT: float = 1.0 / 60.0
## The most actor ids looked at for bodies.
const MAX_ACTORS: int = 1024
## The tick the scripted run's "HUD" rebuilds staff 0 (a command).
const REBUILD_AT: int = 100
const REBUILT: Array[StringName] = [&"triple", &"fire", &"bolt"]

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


func before_each() -> void:
	_find()


func after_each() -> void:
	await _fresh()


func test_a_scripted_sandbox_run_replays_tick_for_tick() -> void:
	await _check_replay(&"sandbox_requested", 0, 1)


func test_a_wave_of_bots_replays_tick_for_tick() -> void:
	await _check_replay(&"play_requested", 2, 0)


func test_a_horde_run_of_a_bot_replays_tick_for_tick() -> void:
	await _check_replay(&"horde_requested", 1, 0)


## A replay of other content is not played.
func test_a_replay_of_other_content_is_refused() -> void:
	var replay := Replay.new()
	replay.content = 12345
	check(not bool(_frames.call("play", replay)), "refused")
	check(not bool(_frames.call("is_playing")), "nothing plays")


## A run started by `start` with `bots` fighter bots and `scripted` scripted players (seats in that
## order), recorded and played back; the hashes must agree at every tick.
func _check_replay(start: StringName, bots: int, scripted: int) -> void:
	var recorded := Desync.new()
	var replay: Replay = await _record(start, bots, scripted, recorded)
	check(replay != null and replay.tick_count() == TICKS, "%s: the replay holds every tick (%d)" % [start, replay.tick_count() if replay != null else -1])
	if replay == null:
		return
	if scripted > 0:
		check(_has_command(replay), "%s: the rebuild is in the replay" % start)
	# Through its bytes, as a file would carry it.
	var again: Replay = Replay.from_bytes(replay.to_bytes())
	check(again != null, "%s: the replay reads back from its bytes" % start)
	if again == null:
		return
	var played := Desync.new()
	await _play(again, bots, played)
	for problem in recorded.problems:
		check(false, "%s: %s" % [start, problem])
	check_equal(played.hashes.size(), TICKS, "%s: the replay played every tick" % start)
	var tick: int = Desync.first_parting(recorded, played)
	if tick < 0:
		return
	# Again, keeping the parting tick's leaves, so the report names the members.
	var recorded2 := Desync.new(tick)
	var replay2: Replay = await _record(start, bots, scripted, recorded2)
	var played2 := Desync.new(tick)
	await _play(replay2, bots, played2)
	check(false, "%s: the replay parts from the run it recorded: %s" % [start, Desync.compare(recorded2, played2)])


## `TICKS` ticks of a run, recorded from a fresh game; each tick's hashes go to `into`.
func _record(start: StringName, bots: int, scripted: int, into: Desync) -> Replay:
	await _fresh()
	var players: Array[BotScript] = _join_bots(bots)
	for at in scripted:
		_input.call("add_virtual_device", bots + at)
		_frames.call("set_source", bots + at, Scripted.new())
	# As many physics steps from the fresh game to the run's start as `_play` takes: the services'
	# clocks run from the game's start, not the run's (N3 starts the one clock with the run).
	await physics_frame
	# At the start of a physics step, before the tick: the run starts and its first tick is this step's.
	var replay: Replay = _frames.call("record", start, 0)
	var events: Node = root.get_node("Events")
	for i in TICKS:
		await physics_frame
		into.capture(_areas())
		_step_timers()
		if scripted > 0 and i == REBUILD_AT:
			# As the radial builder sends it: applied at the next tick's start, and recorded there.
			events.emit_signal("staff_cards_requested", bots, 0, REBUILT)
	replay = _frames.call("stop_recording")
	if scripted > 0:
		var wizard: Actor = _flow.call("get_wizard", bots) as Actor
		check(wizard != null and wizard.caster.cards_of(0).slice(0, REBUILT.size()) == REBUILT, "the rebuild applied in the recorded run")
	for bot in players:
		bot.leave()
	return replay


## `replay` played from a fresh game, `bots` bots watching (their seats' frames dropped), each
## tick's hashes to `into`.
func _play(replay: Replay, bots: int, into: Desync) -> void:
	await _fresh()
	_join_bots(bots)
	await physics_frame
	check(bool(_frames.call("play", replay)), "the replay plays")
	for i in TICKS:
		await physics_frame
		into.capture(_areas())
		_step_timers()
	check(not bool(_frames.call("is_playing")), "the replay ran out after its last tick")


func _join_bots(count: int) -> Array[BotScript]:
	var out: Array[BotScript] = []
	for seat in count:
		var bot := BotScript.new()
		check(bot.join(seat, BotScript.Mode.FIGHTER, _input, _flow), "bot %d joins" % seat)
		out.append(bot)
	return out


## True when some tick of `replay` carries the rebuild.
func _has_command(replay: Replay) -> bool:
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


## The autoloads of the game now.
func _find() -> void:
	_frames = root.get_node("Frames")
	_input = root.get_node("PlayerInput")
	_flow = root.get_node("Flow")
	_feel = root.get_node("Feel") as FeelScript
	# Feel's stops end by real time (A1): frozen, they hold the same bodies in both runs (N4).
	_feel.drive_engine = false
	_feel.set_process(false)
	# The timers that run in `_process` (A2) run once a tick instead (`_step_timers`; N3).
	for area: String in ["Flow", "Coop", "Horde"]:
		root.get_node(area).set_process(false)


## The `_process` timers, once a tick at its start, as N3's tick will run them: Flow's waves and
## restarts, Coop's revive, the horde director.
func _step_timers() -> void:
	_flow.call("step", DT)
	root.get_node("Coop").call("step_revive", DT)
	root.get_node("Horde").call("step", DT)


## Whatever runs stops, and the game starts afresh.
func _fresh() -> void:
	_frames.call("stop_recording")
	_frames.call("stop_playing")
	_flow.call("stop_run")
	for seat in 4:
		_frames.call("set_source", seat, null)
		_input.call("leave", seat)
	await process_frame
	await process_frame
	FreshGame.restart(root)
	_find()
	await physics_frame


## The game's areas by name: the autoloads that simulate, and every actor's body by actor id.
func _areas() -> Dictionary:
	var out: Dictionary = {}
	for area: String in ["Actors", "Projectiles", "Spells", "Combat", "Entities", "Flow", "Coop"]:
		out[area] = root.get_node(area)
	# The horde director only in a horde run: outside one its generator holds the seed it was made
	# with (random in each game; a run deals it a new one).
	if bool(root.get_node("Horde").call("is_running")):
		out["Horde"] = root.get_node("Horde")
	var actors: Node = root.get_node("Actors")
	for id in MAX_ACTORS:
		if not bool(actors.call("is_open", id)):
			continue
		# Actor bodies only: a swarm row's target node holds an id too, and is the swarm's.
		var body: Actor = actors.call("node_of", id) as Actor
		if body != null:
			out["actor %d" % id] = body
	return out
