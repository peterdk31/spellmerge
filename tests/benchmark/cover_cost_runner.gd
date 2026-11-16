extends Node
## What ground cover costs (ground cover GC6, docs/milestones/ground-cover.md, "Cost"). It finds the
## largest room of the game (the most cells a full cover lays), plays it on the real autoloads as a
## pinned run with its enemies lifted out, stands `bodies` (100) stand-ins (`prop_stand_in.tres`, with health
## enough never to die) spread over its cover, moving a little every tick so Feel's bend and trample
## always have new places, and runs, in turn:
##
## - **none:** no cover (the game as it plays before GC8's art: what main costs);
## - **rest:** a stand-in grass (tests/support/stand_in_grass.gd) over every open cell, at rest;
## - **burning:** the same grass all lit by one touch and held burning (its `after` out of reach, so
##   every cell is active and burns the bodies in it), the plan's "all of it burning at once". The tick it all catches is
##   timed alone (`catch`: the touch, every cell entering, Feel's tufts told) with the frame after it;
## - **front:** the grass as it is (burning 1.2 s, then ash), lit at the middle cell and spreading
##   by the run's chance: a real fire's front, its worst tick and how far it got.
##
## For each it prints `BENCH: cover <scene>:` lines: the tick (the Tick's own `run`, timed tick by
## tick with the Tick's physics process off; average, p95, max), the frame (Feel's `step`, and its
## cover's `step` alone), the tick's steps one by one (the Cover area's, and the costliest), the
## Cover area's state hash, and the cells and bodies in play.
##
## Started by `cover_cost.gd`. Prints `COVER COST OK` and quits 0, or `COVER COST FAILED` and 1 (no
## room, the run did not start, the scene was not as asked, or the log has an error).

const BotScript := preload("res://tests/bots/bot.gd")
const ErrorLogScript := preload("res://tests/smoke/error_log.gd")
const TickScript := preload("res://core/sim/tick.gd")
const CoverScript := preload("res://gameplay/cover/cover.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FlowScript := preload("res://gameplay/flow/flow.gd")
const PinnedRun := preload("res://tests/support/pinned_run.gd")
const StandInGrass := preload("res://tests/support/stand_in_grass.gd")
const StandIn: EnemyBase = preload("res://tests/benchmark/prop_stand_in.tres")

const GROUP: StringName = &"prop_stand_in"
const SCENES: Array[String] = ["none", "rest", "burning", "front"]
const BODIES: int = 100
## Ticks run before timing, and timed (a front is timed over FRONT_TICKS: it burns out in that).
const WARM_UP: int = 30
const TICKS: int = 300
const FRONT_TICKS: int = 900
## Ticks of the per-step timing.
const AREA_TICKS: int = 100
const HASH_PASSES: int = 20
## Frames to wait for the run to start, at most.
const WAIT_FRAMES: int = 600
## A stand-in sways this far (pixels a tick), turning every SWAY_TICKS.
const SWAY_STEP: float = 0.5
const SWAY_TICKS: int = 30
const BURNING: int = 1
const DT: float = TickScript.DT
## The run's seed in every scene, so a front spreads the same way on every run of the same code.
const SEED: int = 6006

var bodies: int = BODIES
var ticks: int = TICKS
var scenes: Array[String] = SCENES.duplicate()

var _log: Logger = ErrorLogScript.new()
var _logging: bool = false
var _tick: TickScript = null
var _flow: FlowScript = null
var _events: Node = null
var _registry: Node = null
var _cover: CoverScript = null
var _feel: FeelScript = null
var _bot: BotScript = null
var _room: RoomBase = null
var _run_id: StringName = &""
var _failures: Array[String] = []
var _stand_ins: Array[Actor] = []
var _homes: PackedVector2Array = PackedVector2Array()
var _lifted: Array[Node] = []
var _ticked: int = 0
var _clock: float = 0.0


func _ready() -> void:
	OS.add_logger(_log)
	_logging = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bodies="):
			bodies = arg.trim_prefix("--bodies=").to_int()
		elif arg.begins_with("--ticks="):
			ticks = maxi(arg.trim_prefix("--ticks=").to_int(), 20)
		elif arg.begins_with("--only="):
			scenes.clear()
			for part in arg.trim_prefix("--only=").split(","):
				if part in SCENES:
					scenes.append(part)
	var root: Window = get_tree().root
	_tick = root.get_node_or_null("Tick") as TickScript
	_flow = root.get_node_or_null("Flow") as FlowScript
	_events = root.get_node_or_null("Events")
	_registry = root.get_node_or_null("Registry")
	_cover = root.get_node_or_null("Cover") as CoverScript
	_feel = root.get_node_or_null("Feel") as FeelScript
	var input: Node = root.get_node_or_null("PlayerInput")
	if _tick == null or _flow == null or _events == null or _registry == null or _cover == null or _feel == null or input == null:
		_finish(["the Tick, Flow, Events, Registry, Cover, Feel and PlayerInput autoloads must exist"])
		return
	var projectiles: Node = root.get_node_or_null("Projectiles")
	if projectiles != null:
		print("BENCH: native module %s" % ("on" if projectiles.call(&"is_native") else "off"))
	_room = _largest_room()
	if _room == null:
		_finish(["no room of a biome to cover"])
		return
	_run_id = PinnedRun.pin(_registry, _room, &"", RoomKind.FILL_ENEMIES, 1)
	_flow.run_id_to_play = _run_id
	_bot = BotScript.new()
	if not _bot.join(0, BotScript.Mode.IDLER, input, _flow):
		_finish(["the bot could not take its virtual device"])
		return
	_run.call_deferred()


func _exit_tree() -> void:
	if _logging:
		_logging = false
		OS.remove_logger(_log)


## The room of a biome whose full cover has the most cells (what the plan calls the largest room).
func _largest_room() -> RoomBase:
	var best: RoomBase = null
	var most: int = -1
	var shown: Array[String] = []
	for item: Resource in _registry.call("get_all", &"rooms"):
		var room := item as RoomBase
		if room == null or room.biome == &"" or room.scene == null:
			continue
		var built: Node = room.scene.instantiate()
		var cells: int = CoverLayout.of(built, room, [_grass(room.biome)] as Array[CoverKind]).count()
		built.free()
		shown.append("%s %d" % [room.id, cells])
		if cells > most:
			most = cells
			best = room
	print("BENCH: cover rooms (cells a full cover lays): %s" % ", ".join(shown))
	return best


## The stand-in grass over every open cell of `biome` (clumps of one, no gap from the walls).
static func _grass(biome: StringName) -> CoverKind:
	var grass: CoverKind = StandInGrass.make([biome] as Array[StringName], 1.0, 1)
	grass.wall_gap = 0
	return grass


## The grass held burning: its burning state's `after` out of reach, so every lit cell stays
## burning, active and harming the bodies in it.
static func _held(biome: StringName) -> CoverKind:
	var grass: CoverKind = _grass(biome)
	var burning: CoverState = grass.states[BURNING]
	var rows: Array[CoverTrigger] = []
	for row in burning.triggers:
		var copy := row.duplicate() as CoverTrigger
		if copy.when == CoverTrigger.When.AFTER:
			copy.seconds = 1.0e9
		rows.append(copy)
	burning.triggers = rows
	return grass


func _run() -> void:
	# A throwaway pass first, so the first scene measured is not the cold one.
	_cover.use_kinds([] as Array[CoverKind])
	_feel.cover().use_kinds([] as Array[CoverKind])
	if await _start():
		_stand()
		for i in ticks:
			_one_tick()
		_clear()
	for scene in scenes:
		var kinds: Array[CoverKind] = []
		if scene == "rest" or scene == "front":
			kinds.append(_grass(_room.biome))
		elif scene == "burning":
			kinds.append(_held(_room.biome))
		_cover.use_kinds(kinds)
		_feel.cover().use_kinds(kinds)
		if not await _start():
			break
		_stand()
		_measure(scene)
		_clear()
	_cover.use_kinds(null)
	_feel.cover().use_kinds(null)
	_tick.set_physics_process(true)
	_finish(_failures)


## The pinned run started again (its room laid with the kinds given), and settled.
func _start() -> bool:
	_tick.set_physics_process(true)
	_flow.stop_run()
	_events.emit_signal("play_requested", 0)
	var waited: int = 0
	while _flow.world == null or _flow.get_wizard(0) == null:
		waited += 1
		if waited > WAIT_FRAMES:
			_failures.append("the run did not start")
			return false
		await get_tree().physics_frame
	# Its enemies lifted out of the world (never killed: the room cleared would win the run and end
	# it), so the stand-ins are the only bodies but the wizard; freed after the scene.
	for enemy: Node in _flow.get(&"_enemies") as Array:
		if is_instance_valid(enemy) and enemy.get_parent() != null:
			enemy.get_parent().remove_child(enemy)
			_lifted.append(enemy)
	for i in 30:
		await get_tree().physics_frame
	# From here this runner runs the ticks and Feel's frames itself, so each is timed alone.
	_tick.set_physics_process(false)
	_tick.sim.run_seed = SEED
	return true


## Stand `bodies` stand-ins on cells spread over the room's open floor (`_spots`), each at home,
## with health enough never to die.
func _stand() -> void:
	var data := StandIn.duplicate() as EnemyBase
	data.max_health = 1.0e9
	var spots: PackedVector2Array = _spots(bodies)
	_stand_ins.clear()
	_homes = spots
	for i in spots.size():
		var body := data.scene.instantiate() as Actor
		body.data = data
		body.position = spots[i]
		_flow.world.add_child(body)
		_stand_ins.append(body)
	for i in WARM_UP:
		_one_tick()


## `count` places over the room's open floor, spread evenly in cell order: the middles of the cells
## a full cover lays in the room as built (the same in every scene, cover or none).
func _spots(count: int) -> PackedVector2Array:
	var layout: CoverLayout = CoverLayout.of(_flow.world, _room, [_grass(_room.biome)] as Array[CoverKind])
	var open: PackedInt32Array = PackedInt32Array()
	for cell in layout.cells.size():
		if layout.cells[cell] != 0:
			open.append(cell)
	var spots: PackedVector2Array = PackedVector2Array()
	if open.is_empty():
		return spots
	for i in count:
		spots.append(layout.cell_rect(open[int(float(i) * float(open.size()) / float(count))]).get_center())
	return spots


## One tick and one frame as the game runs them: the stand-ins sway, the Tick runs, Feel steps.
## Their times, in microseconds: [tick, frame].
func _one_tick() -> PackedInt32Array:
	_sway()
	var start: int = Time.get_ticks_usec()
	_tick.run(DT)
	var tick_took: int = Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	_feel.step(DT)
	var frame_took: int = Time.get_ticks_usec() - start
	_clock += DT
	return PackedInt32Array([tick_took, frame_took])


## Every stand-in a little off its home, the way turning every SWAY_TICKS.
func _sway() -> void:
	_ticked += 1
	var phase: int = _ticked % (SWAY_TICKS * 2)
	var off: float = SWAY_STEP * float(phase if phase < SWAY_TICKS else SWAY_TICKS * 2 - phase)
	for i in _stand_ins.size():
		var body: Actor = _stand_ins[i]
		if is_instance_valid(body):
			body.position = _homes[i] + Vector2(off, off * 0.5)


func _clear() -> void:
	for body in _stand_ins:
		if is_instance_valid(body):
			body.free()
	_stand_ins.clear()
	_tick.run(DT)
	_flow.stop_run()
	for enemy in _lifted:
		if is_instance_valid(enemy):
			enemy.free()
	_lifted.clear()


func _measure(scene: String) -> void:
	var cells: int = _cover.layout.count() if _cover.layout != null else 0
	print("BENCH: cover %s: room %s, %d covered cells of %d, %d stand-ins" % [scene, _room.id, cells, _cover.layout.cells.size() if _cover.layout != null else 0, _stand_ins.size()])
	if scene == "rest" or scene == "burning" or scene == "front":
		if cells == 0:
			_failures.append("%s: the room has no cover" % scene)
			return
	if scene == "burning":
		_catch()
	elif scene == "front":
		_front()
		return
	_time(scene, ticks)
	_time_cover_frame(scene)
	_time_areas(scene)
	_time_hash(scene)
	if scene == "burning":
		if _cover.active_cells().size() != cells:
			_failures.append("burning: %d of %d cells burning" % [_cover.active_cells().size(), cells])
		print("BENCH: cover burning: %d cells burning, %d bodies harmed, %d rolls so far" % [_cover.active_cells().size(), _cover.harmed().size(), _cover.rolls()])


## The whole room lit by one touch: the tick it catches and the frame after it, timed alone.
func _catch() -> void:
	var size := Vector2(_cover.layout.columns, _cover.layout.rows) * float(CoverLayout.CELL)
	_events.emit_signal("floor_touched", -1, &"fire", size * 0.5, size.length())
	var took: PackedInt32Array = _one_tick()
	# Feel's part of it: every lit cell's tufts told their state again, as its listener did.
	var look: Node = _feel.cover()
	var start: int = Time.get_ticks_usec()
	for cell in _cover.active_cells():
		look.call(&"show_state", cell, BURNING)
	var told: int = Time.get_ticks_usec() - start
	print("BENCH: cover burning: the tick it all catches %.3f ms (%d cells lit; Feel's tufts told, a second pass after it as an estimate of its share, %.3f ms), the frame after %.3f ms" % [float(took[0]) / 1000.0, _cover.active_cells().size(), float(told) / 1000.0, float(took[1]) / 1000.0])


## A fire lit at the middle cell, spreading by the run's chance until it burns out or FRONT_TICKS.
func _front() -> void:
	var layout: CoverLayout = _cover.layout
	var middle: int = layout.cell_of(Vector2(layout.columns, layout.rows) * float(CoverLayout.CELL) * 0.5)
	var cell: int = -1
	for at in layout.cells.size():
		var near: int = (middle + at) % layout.cells.size()
		if layout.cells[near] != 0:
			cell = near
			break
	_events.emit_signal("floor_touched", -1, &"fire", layout.cell_rect(cell).get_center(), 0.0)
	var tick_times: Array[int] = []
	var frame_times: Array[int] = []
	var most_burning: int = 0
	var most_at: int = 0
	var burnt: int = 0
	var ran: int = 0
	for t in FRONT_TICKS:
		var took: PackedInt32Array = _one_tick()
		tick_times.append(took[0])
		frame_times.append(took[1])
		ran += 1
		var burning: int = 0
		burnt = 0
		for active in _cover.active_cells():
			if _cover.state_at(active) == BURNING:
				burning += 1
			burnt += 1
		if burning > most_burning:
			most_burning = burning
			most_at = t
		if burning == 0 and t > 1:
			break
	var walk := StateWalk.new()
	walk.with_paths = false
	# The area's hash after the front: the same on two checkouts that burn the same (seed SEED).
	var ended: String = "it burnt out" if ran < FRONT_TICKS else "the cap, still burning"
	print("BENCH: cover front: %d ticks (%s), at most %d cells burning (tick %d), %d of %d cells not at rest after, %d rolls, the Cover area's hash %d" % [ran, ended, most_burning, most_at, burnt, layout.count(), _cover.rolls(), SimHash.area(walk, "Cover", _cover)])
	_print_times("front", "tick", tick_times)
	_print_times("front", "frame (Feel's step)", frame_times)
	if most_burning < 2:
		_failures.append("front: the fire did not spread")


func _time(scene: String, count: int) -> void:
	var tick_times: Array[int] = []
	var frame_times: Array[int] = []
	for i in count:
		var took: PackedInt32Array = _one_tick()
		tick_times.append(took[0])
		frame_times.append(took[1])
	_print_times(scene, "tick", tick_times)
	_print_times(scene, "frame (Feel's step)", frame_times)


func _print_times(scene: String, what: String, times: Array[int]) -> void:
	var sorted: Array[int] = times.duplicate()
	sorted.sort()
	var total: int = 0
	for t in sorted:
		total += t
	print("BENCH: cover %s: %s avg %.3f ms p95 %.3f ms max %.3f ms over %d" % [scene, what, float(total) / float(sorted.size()) / 1000.0, float(sorted[int(sorted.size() * 0.95)]) / 1000.0, float(sorted[-1]) / 1000.0, sorted.size()])


## Feel's cover's own `step` alone (the bodies found, the cells walked, the rows handed over), the
## stand-ins swaying between, over `ticks` frames.
func _time_cover_frame(scene: String) -> void:
	var look: Node = _feel.cover()
	var actors: Node = get_tree().root.get_node_or_null("Actors")
	var focus: Vector2 = _homes[0] if not _homes.is_empty() else Vector2.INF
	var times: Array[int] = []
	for i in ticks:
		_sway()
		_clock += DT
		var start: int = Time.get_ticks_usec()
		look.call(&"step", _clock, actors, focus)
		times.append(Time.get_ticks_usec() - start)
	_print_times(scene, "Feel's cover step alone", times)


## The tick's steps one by one, in its order, over AREA_TICKS ticks run as the Tick runs them.
func _time_areas(scene: String) -> void:
	_tick.call(&"_build_order")
	var order: Array = _tick.get(&"_order")
	var spent: Dictionary[String, int] = {}
	for t in AREA_TICKS:
		_sway()
		for step: SimArea.Step in order:
			var start: int = Time.get_ticks_usec()
			if step.key == TickScript.BODIES:
				_tick.call(&"_step_bodies", DT)
			elif step.call.is_valid():
				step.call.call(DT)
			var name: String = String(step.key)
			spent[name] = spent.get(name, 0) + Time.get_ticks_usec() - start
		_tick.sim.tick += 1
	var keys: Array = spent.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return spent[a] > spent[b])
	var shown: Array[String] = []
	for key: String in keys.slice(0, 5):
		shown.append("%s %.3f" % [key, float(spent[key]) / AREA_TICKS / 1000.0])
	print("BENCH: cover %s: the Cover step %.3f ms a tick; the costliest steps (ms a tick): %s" % [scene, float(spent.get("Cover", 0)) / AREA_TICKS / 1000.0, ", ".join(shown)])


## The Cover area's part of the state hash, as `SimHash.areas` walks it.
func _time_hash(scene: String) -> void:
	var total: int = 0
	var problems: PackedStringArray = PackedStringArray()
	for i in HASH_PASSES:
		var walk := StateWalk.new()
		walk.with_paths = false
		var start: int = Time.get_ticks_usec()
		SimHash.area(walk, "Cover", _cover)
		total += Time.get_ticks_usec() - start
		problems = walk.problems
	print("BENCH: cover %s: the Cover area's state hash %.3f ms; %d problems" % [scene, float(total) / HASH_PASSES / 1000.0, problems.size()])
	for problem in problems.slice(0, 5):
		_failures.append("%s: state hash problem: %s" % [scene, problem])


func _finish(failed: Array[String]) -> void:
	if _bot != null:
		_bot.leave()
	var found: Array[String] = failed.duplicate()
	var lines: Array[String] = _log.call("get_lines")
	for line in lines:
		found.append("the log has an error: " + line.trim_prefix("ERROR:").strip_edges())
	if _logging:
		_logging = false
		OS.remove_logger(_log)
	if found.is_empty():
		print("COVER COST OK: %s measured" % ", ".join(scenes))
		get_tree().quit(0)
	else:
		for reason in found:
			printerr("COVER COST FAILED: " + reason)
		get_tree().quit(1)
