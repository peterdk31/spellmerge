extends RefCounted
## A run on the real game recorded through the Frames autoload and played back, each tick's state
## hashes captured (online-ready N2 and N2b, docs/milestones/online-ready.md). The replay test
## (tests/core/test_replay_game.gd) plays a run back in the same process; the platform runner
## (tests/platforms/replay_hashes_runner.gd) prints the hashes, so runs on Linux, Windows and the web
## can be compared (tools/platform_hashes.py).
##
## - **A scripted player** (`Scripted`: a frame source that reads nothing of the game, as a
##   person's input) walks, dashes, aims and casts its staffs (the storm on LB, the bolt) while the
##   "HUD" rebuilds a staff mid-run (a command): its replay plays with nobody watching, and its
##   frames are the same on every platform. In the hub (with no stone press) it first walks to the
##   rack and takes the storm, `rack_item` (`RackWalker`; the "HUD" sends A by it, the command
##   `item_take_requested`), onto its first free hand, LB, as a player takes it.
## - **Fighter bots** (tests/bots/bot.gd) play a run's room. A bot reads the game through
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
##     var replay: Replay = await run.record(&"hub_requested", 0, 1, recorded)
##     var played := Desync.new()
##     await run.play(replay, 0, played)
##     # run.problems: what went wrong on the way (a bot that did not join, ...)

const BotScript := preload("res://tests/bots/bot.gd")
const FreshGame := preload("res://tests/support/fresh_game.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const TickScript := preload("res://core/sim/tick.gd")
const CoopScript := preload("res://gameplay/coop/coop.gd")
const PinnedRun := preload("res://tests/support/pinned_run.gd")

## The tick the scripted run's "HUD" rebuilds staff 0 (a command), mid-run while the wizard stands:
## a downed body's requests are refused (items I7b), so `record` says so if the wizard is down at
## this tick.
const REBUILD_AT: int = 145
const REBUILT: Array[StringName] = [&"triple", &"fire", &"bolt"]
## The ticks the scripted run's pause menu opens and closes (the command `pause_requested`): the game
## stands stopped between, and a replay stands stopped there too (online-ready N4).
const PAUSE_AT: int = 150
const RESUME_AT: int = 170
## The premade staff the hub's scripted player takes from the rack first (content/items/staffs/): the
## Frostfire Cascade, a fire nova split three times whose every shot fires a frost nova split three
## times as it ends, far past the projectile cap.
const STORM_ITEM: StringName = &"frostfire_cascade"

## Ticks recorded and played (four seconds of game by default).
var ticks: int = 240
## False runs the projectile manager's GDScript (and the maths' and moves' twins) instead of the
## native kernels.
var native: bool = true
## This machine's settings a run records with (online-ready N11: `SessionRules.machine()`; a replay
## plays by the rules in its header whatever these say): the projectile cap (0 leaves the
## platform's). The platform runner sets it, so every platform records the same game.
var cap: int = 0
## A seat moves "Max shots" in the recorded run: at tick `x` (-1: never) it asks for the cap `y`, as
## the pause menu does (`shot_cap_requested`, a command recorded with its tick; N11).
var cap_request: Vector2i = Vector2i(-1, 0)
## The run's seed (every roll of the run: `sim.chance`), or 0 for a random one. The
## platform runner fixes it, so every platform deals the same seeds.
var run_seed: int = 0
## What went wrong on the way, in words (empty when all went as asked).
var problems: PackedStringArray = PackedStringArray()
## The hub's scripted player (online-lobby L1): at 0 or more the scripted players are `StoneWalker`s,
## walking from the hub's first spawn onto the teleporter stone, and the "HUD" sends the player's A
## (`run_requested`, a command) at this tick, which starts the run; -1, the `Scripted` player.
var stone_press_at: int = -1
## A tick to snapshot the recorded run after (online-ready N10; -1 for none), and the snapshot.
var snapshot_at: int = -1
var snapshot: Snapshot = null
## The room a run of Play is in, or null for the game's own run: a run of that one room
## (tests/support/pinned_run.gd, `Flow.run_id_to_play`), pinned again in every fresh game. The
## snapshot test plays every run's room template by it (online-ready N12, run generation RG3).
var room: RoomBase = null
## The pace that room's enemies come in at (enemy spawning EA5; null: all at once), pinned with it.
var spawning: SpawnRules = null
## Called right after the snapshot is taken (with nothing), so a test can check what the snapshot
## caught (a body mid-spawn, groups still to come).
var at_snapshot: Callable = Callable()
## True: each run starts from a fresh game (every autoload made again). False: in the same game,
## after whatever ran before, as a player starts one run after another (N3b: the run starts from
## a fresh game's state all the same).
var fresh_game: bool = true
## The premade staff the first scripted player of a hub with no stone press walks to and takes
## (`RackWalker`); empty: it plays as `Scripted` from its spawn.
var rack_item: StringName = STORM_ITEM
## Cover kinds the game's cover area and Feel lay instead of the registry's (ground cover GC5; empty:
## the registry's), given again in every fresh game. The snapshot test puts cover in its rooms so.
var cover: Array[CoverKind] = []

var _tree: SceneTree
var _root: Window
var _frames: Node
var _input: Node
var _flow: Node
var _feel: FeelScript


## A player that reads nothing of the game: it walks a square, turns its aim a step each tick,
## taps the storm (staff 2) and dashes (staff 0) now and then, and holds the bolt (staff 1) in
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


## The hub's player (online-lobby L1), reading nothing of the game either: from the hub's first
## player spawn it walks towards the stone's centre at full tilt (90 px/s: 1.5 px a tick) until it
## is well onto the stone, and stands; once the run has started (`after`, the tick of the "HUD"'s A
## plus one) it plays as `Scripted` does, so the run has shots, hits and walking to replay. Where the
## spawn and the stone are is the room's data (content, never the game's state).
class StoneWalker:
	extends FrameSource
	const HUB := preload("res://content/rooms/hub/hub.tres")
	## Pixels a tick at full tilt (Mover.speed 90 at 60 ticks a second).
	const STEP: float = 1.5
	var way: Vector2
	var walk: int
	var after: int
	var tick: int = 0
	var then: Scripted = Scripted.new()

	func _init(press_at: int) -> void:
		var room: RoomBase = HUB
		var to: Vector2 = HubRules.area_of(room.places(), HubRules.ROLE_RUN_START).get_center() - room.places().player_spawns[0]
		way = to.normalized()
		walk = floori((to.length() - 8.0) / STEP)
		after = press_at + 1

	func fill_frame(frame: InputFrame, delta: float) -> void:
		if tick < walk:
			frame.set_move(way)
		elif tick > after:
			then.fill_frame(frame, delta)
		tick += 1


## The hub's player who takes a premade staff from the rack (crypt rework CR-S: the storm the
## showcase builds left there), reading nothing of the game either: from its seat's spawn in the hub
## it walks towards the item at full tilt until it is in reach (`PickupRule.REACH`) and stands; the
## "HUD" sends A by it at `take_at`, and after that it plays as `Scripted` does. Where the spawn and
## the item lie is the room's data.
class RackWalker:
	extends FrameSource
	const HUB := preload("res://content/rooms/hub/hub.tres")
	const STEP: float = 1.5
	var at: Vector2
	var way: Vector2
	var walk: int
	var take_at: int
	var tick: int = 0
	var then: Scripted = Scripted.new()

	func _init(seat: int, item: StringName) -> void:
		at = place_of(item)
		var to: Vector2 = at - (HUB as RoomBase).places().player_spawns[seat]
		way = to.normalized()
		walk = floori((to.length() - 4.0) / STEP)
		take_at = walk + 1

	## Where the hub's scene lays the premade item `item` (Vector2.INF where it lays none).
	static func place_of(item: StringName) -> Vector2:
		var places: RoomPlaces = (HUB as RoomBase).places()
		for i in places.placed.size():
			var data := places.placed[i] as StaffItem
			if data != null and data.id == item:
				return places.placed_at[i]
		return Vector2.INF

	func fill_frame(frame: InputFrame, delta: float) -> void:
		if tick < walk:
			frame.set_move(way)
		elif tick > take_at:
			then.fill_frame(frame, delta)
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
	var walker: RackWalker = null
	for at in scripted:
		_input.call("add_virtual_device", bots + at)
		var source: FrameSource = Scripted.new() if stone_press_at < 0 else StoneWalker.new(stone_press_at)
		if at == 0 and _takes_from_rack(start):
			walker = RackWalker.new(bots, rack_item)
			source = walker
		_frames.call("set_source", bots + at, source)
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
			if at_snapshot.is_valid():
				at_snapshot.call()
		if scripted > 0 and i == REBUILD_AT:
			# As the radial builder sends it: applied at the next tick's start, and recorded there.
			var standing: Actor = _flow.call("get_wizard", bots) as Actor
			if standing != null and standing.is_down():
				problems.append("%s: the scripted wizard is down at the rebuild (tick %d): move REBUILD_AT" % [start, REBUILD_AT])
			events.emit_signal("staff_cards_requested", bots, 0, REBUILT, standing.key() if standing != null else 0)
		if walker != null and i == walker.take_at:
			# As the HUD's panels send A by an item in reach: applied at the next tick's start.
			events.emit_signal("item_take_requested", bots, _item_lying_at(walker.at))
		if i == stone_press_at and scripted > 0:
			# As the HUD's panels send A on the lit stone: applied at the next tick's start.
			events.emit_signal("run_requested", bots)
		if i == cap_request.x:
			events.emit_signal("shot_cap_requested", 0, cap_request.y)
		if scripted > 0 and i == PAUSE_AT:
			events.emit_signal("pause_requested", bots, 1)
		if scripted > 0 and i == RESUME_AT:
			events.emit_signal("pause_requested", bots, 0)
		if scripted > 0:
			_check_stopped(start + " recorded", i)
	replay = _frames.call("stop_recording")
	# The hub's bag holds every card; Play's only its own.
	if scripted > 0 and ticks > REBUILD_AT + 1 and _takes_from_rack(start):
		var wizard: Actor = _flow.call("get_wizard", bots) as Actor
		if wizard == null or wizard.caster.cards_of(0).slice(0, REBUILT.size()) != REBUILT:
			problems.append("%s: the rebuild did not apply in the recorded run" % start)
	if walker != null and ticks > walker.take_at + 1:
		var taker: Actor = _flow.call("get_wizard", bots) as Actor
		var item := _root.get_node("Registry").call("get_resource", &"items", rack_item) as StaffItem
		if taker == null or item == null or taker.caster.cards_of(2).slice(0, item.cards.size()) != item.cards:
			problems.append("%s: the scripted player did not take %s onto LB" % [start, rack_item])
	if room != null and start == &"play_requested" and StringName(_flow.get(&"room_id")) != PinnedRun.room_id(room, 1, 1, spawning):
		problems.append("%s: the run is in %s, not %s" % [start, _flow.get(&"room_id"), PinnedRun.room_id(room, 1, 1, spawning)])
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
	# Played out: it ends as the next step starts (its last tick stepped with its own seats).
	if int(_frames.call("play_tick")) != replay.tick_count():
		problems.append("%s: the replay did not run out after its last tick" % replay.start)
	_check_settings(replay.start)


## `replay` played live from a fresh game (netcode spike S1: as the online client plays the host's
## run while it spawns in, `Frames.play_live`), no bot watching: its header first, then its tick `k`
## added at the physics step `arrive_at[k]` (counted from 0 at the play's start; never earlier than
## the tick before). Seat 0, the run's own player, is this machine's here (the client's): its frames
## come from `Contrary` and are sent to the feed, never played. At the start of every step (the
## feed's pump) the hashes go to `into` and the ticks played so far to `played`, so a step that ran
## several ticks is seen after its last, a step that waited is seen again unchanged, and the last
## tick is seen at the step that ends the replay. Per step,
## `steps` gets [the ticks played before it, the ticks there to play].
func play_live(replay: Replay, arrive_at: PackedInt32Array, into: Desync, played: PackedInt32Array, steps: Array[Vector2i], cushion: int = 2) -> void:
	await fresh()
	_input.call("add_virtual_device", 0)
	var contrary := Contrary.new()
	_frames.call("set_source", 0, contrary)
	await _tree.physics_frame
	var feed := LiveRun.new(1, cushion)
	feed.host = replay
	feed.replay = Replay.from_bytes(replay.header_bytes())
	feed.arrive_at = arrive_at
	feed.frames = _frames
	feed.steps = steps
	feed.capture = func(at: int) -> void:
		if at > 0:
			_capture(into)
			played.append(at)
	if not bool(_frames.call("play_live", feed)):
		problems.append("%s: the live replay did not play" % replay.start)
		return
	var limit: int = (arrive_at[arrive_at.size() - 1] if not arrive_at.is_empty() else 0) + replay.tick_count() + 10
	while bool(_frames.call("is_playing")) and feed.step < limit:
		await _tree.physics_frame
	if bool(_frames.call("is_playing")):
		problems.append("%s: the live replay did not end after its last tick" % replay.start)
	for problem in feed.problems:
		problems.append(problem)
	if feed.sent == 0 or feed.sent < feed.step - 1:
		problems.append("%s: %d frames sent in %d steps (one a step)" % [replay.start, feed.sent, feed.step])
	if contrary.tick == 0:
		problems.append("%s: the local seat's source was never asked" % replay.start)
	_check_settings(replay.start)


## The feed of `play_live`: the host's ticks as `arrive_at` lets them in, closed once all are in;
## the local seat's frames counted, never played.
class LiveRun:
	extends LiveFeed
	var host: Replay
	var arrive_at: PackedInt32Array
	var frames: Node
	var steps: Array[Vector2i]
	var capture: Callable
	var step: int = 0
	var fed: int = 0
	var sent: int = 0
	var problems: PackedStringArray = PackedStringArray()

	func pump() -> void:
		capture.call(int(frames.call("play_tick")))
		while fed < host.tick_count() and arrive_at[fed] <= step:
			var problem: String = replay.add_tick_bytes(host.tick_bytes(fed))
			if problem != "":
				problems.append("live tick %d: %s" % [fed, problem])
			fed += 1
		closed = fed == host.tick_count()
		steps.append(Vector2i(int(frames.call("play_tick")), replay.tick_count()))
		step += 1

	func send(_tick: int, frame: InputFrame) -> void:
		if frame.seat != 0:
			problems.append("a frame of seat %d sent" % frame.seat)
		sent += 1


## The live client's own player on seat 0: the other way round from `Scripted` (it walks the square
## backwards and presses every staff every tick), so a run that played its frames would part.
class Contrary:
	extends FrameSource
	var tick: int = 0

	func fill_frame(frame: InputFrame, _delta: float) -> void:
		var leg: int = (tick / 40) % 4
		frame.set_move([Vector2.LEFT, Vector2.UP, Vector2.RIGHT, Vector2.DOWN][leg])
		frame.aim = (tick * 1300) % InputFrame.AIM_STEPS
		for staff in 4:
			frame.hold(staff, true)
			frame.press(staff)
		tick += 1


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
	# Played out: it ends as the next step starts (its last tick stepped with its own seats).
	if int(_frames.call("play_tick")) != replay.tick_count():
		problems.append("%s: the replay did not run out after its last tick" % replay.start)
	_check_settings(replay.start)


## A tick inside the scripted pause stands stopped by the menu, and none outside it does (the
## commands apply at the next tick's start).
func _check_stopped(run: String, i: int) -> void:
	if i < PAUSE_AT + 2 or (i > RESUME_AT and i < RESUME_AT + 2):
		return
	var game: Sim = (_root.get_node("Tick") as TickScript).sim
	var inside: bool = i > PAUSE_AT and i <= RESUME_AT
	if CoopScript.menu_stops(game) != inside:
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


## True when the first scripted player of a run started by `start` takes `rack_item` first: in the
## hub, with no stone press.
func _takes_from_rack(start: StringName) -> bool:
	return start == &"hub_requested" and stone_press_at < 0 and rack_item != &""


## The number of the item lying at `at` (the HUD knows it from `item_near_changed`), or -1.
func _item_lying_at(at: Vector2) -> int:
	for item: GroundItem in _root.get_node("Items").call("lying"):
		if item.at.is_equal_approx(at):
			return item.number
	problems.append("no item lies at %s to take" % at)
	return -1


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
	if room != null:
		_flow.set(&"run_id_to_play", PinnedRun.pin(_root.get_node("Registry"), room, &"", RoomKind.FILL_ENEMIES, 16, 1, 1, spawning))
	var kinds: Variant = cover if not cover.is_empty() else null
	_root.get_node("Cover").call(&"use_kinds", kinds)
	_feel.cover().use_kinds(kinds)
	var machine: SessionRules = SessionRules.machine()
	machine.shot_cap = cap if cap > 0 else SessionRules.defaults().shot_cap
	if not native:
		_kernels_off()


## A problem when the run's shot cap is not its rules' (a machine setting applied in the run).
func _check_settings(start: StringName) -> void:
	var game: Sim = (_root.get_node("Tick") as TickScript).sim
	var now: int = int(_root.get_node("Projectiles").call("get_cap"))
	if game != null and now != game.rules.shot_cap:
		problems.append("%s: the shot cap is %d, not the run's %d" % [start, now, game.rules.shot_cap])


## Every native kernel off: the projectile manager on its GDScript (`native` false), the maths and the bodies' moves on their twins (`DMath`, `WallSlide`).
func _kernels_off() -> void:
	DMath.use_native(false)
	WallSlide.use_native(false)
	_root.get_node("Projectiles").set(&"native", false)

