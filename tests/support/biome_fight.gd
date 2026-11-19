extends RefCounted
## A biome's split fight on the real game (connected biomes CB3; tests/core/test_content_determinism.gd):
## Flow starts the split test map (tests/support/biome_maps.gd: the nave the start room, a fight in
## the antechamber west of it and one in the ossuary court east), two seats stood at the nave's two
## mouths; seat 0 walks west and seat 1 east, each casting its bolt as it goes, so the party splits
## into two sealed fights at once, every room laid, sleeping and waking on the way. `play` records
## each tick's hashes (and a snapshot after one); `resume` starts the same biome, restores the snapshot
## and plays on from the next tick, as a player joining the run would.

const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")

const DT: float = 1.0 / 60.0
## The run's seed (a biome's run takes no replay's: the same in every play).
const RUN_SEED: int = 0x5eed_b10e
## The fights: the antechamber's and the court's.
const WEST: Array[StringName] = [&"ember_imp", &"ember_imp"]
const EAST: Array[StringName] = [&"spitter", &"ember_imp"]

## True once a tick had both fights sealed at once (the split the test is about).
var both_sealed: bool = false
var problems: PackedStringArray = PackedStringArray()

var _root: Window
var _flow: FlowScript
var _tick: TickScript
var _frames: Node
var _input: Node
var _walkers: Array[Walker] = []


## A seat that walks `way` from the first tick, aiming along it, its bolt (staff 1) tapped now and
## then. It reads nothing of the game.
class Walker:
	extends FrameSource
	var way: Vector2 = Vector2.ZERO
	var tick: int = 0

	func fill_frame(frame: InputFrame, _delta: float) -> void:
		frame.set_move(way)
		frame.aim = 0 if way.x > 0.0 else InputFrame.AIM_STEPS / 2
		if tick % 24 == 5:
			frame.press(1)
		tick += 1


func _init(root: Window) -> void:
	_root = root
	_flow = root.get_node("Flow") as FlowScript
	_tick = root.get_node("Tick") as TickScript
	_frames = root.get_node("Frames")
	_input = root.get_node("PlayerInput")


## `ticks` ticks of the fight from its start, each tick's hashes in `into`; the snapshot taken after
## tick `snapshot_at` (null when none).
func play(ticks: int, snapshot_at: int, into: Desync) -> Snapshot:
	var map: BiomeMap = _start()
	if map == null:
		return null
	var registry: Object = _root.get_node("Registry")
	# Stood at the nave's two mouths, each looking out at its fight.
	(_flow.get_wizard(0) as Actor).global_position = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.WEST) + Vector2(24.0, 0.0)
	(_flow.get_wizard(1) as Actor).global_position = BiomeMaps.socket_point(registry, map, 0, RoomSocket.Facing.EAST) - Vector2(24.0, 0.0)
	var snapshot: Snapshot = null
	for i in ticks:
		_tick.run(DT)
		into.capture(_tick.state_areas())
		if _flow.life.has(1, RoomLife.SEALED) and _flow.life.has(2, RoomLife.SEALED):
			both_sealed = true
		if i == snapshot_at:
			snapshot = Snapshot.take(_tick.state_areas(), _root)
	_stop()
	return snapshot


## The same fight started again, `from` restored over it (taken after tick `at`), played on to tick
## `ticks` less one, each tick's hashes in `into`.
func resume(from: Snapshot, at: int, ticks: int, into: Desync) -> void:
	if _start() == null:
		return
	for problem in from.restore(_tick.state_areas(), _root):
		problems.append("restored: %s" % problem)
	for walker in _walkers:
		walker.tick = at + 1
	for _i in range(at + 1, ticks):
		_tick.run(DT)
		into.capture(_tick.state_areas())
	_stop()


func _start() -> BiomeMap:
	_stop()
	_flow.set(&"loading_enabled", false)
	_flow.set(&"intro_enabled", false)
	_walkers.clear()
	for seat in 2:
		_input.call("add_virtual_device", seat)
		var walker := Walker.new()
		walker.way = Vector2.LEFT if seat == 0 else Vector2.RIGHT
		_walkers.append(walker)
		_frames.call("set_source", seat, walker)
	var map: BiomeMap = BiomeMaps.split(_root.get_node("Registry"))
	var fights: Array[RoomFight] = [RoomFight.new(), RoomFight.of(WEST), RoomFight.of(EAST, 2, 0, 0.25)]
	_flow.world_parent = _root
	if not _flow.start_biome(0, map, fights):
		problems.append("the biome did not start")
		return null
	_tick.sim.run_seed = RUN_SEED
	return map


func _stop() -> void:
	_flow.stop_run()
	_flow.world_parent = null
	for seat in 4:
		_frames.call("set_source", seat, null)
		_input.call("leave", seat)
	_tick.begin_run()
