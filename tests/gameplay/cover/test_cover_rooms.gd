extends "res://tests/support/suite.gd"
## The cover area on the real autoloads (ground cover GC5, gameplay/cover/cover.gd): a room's cover is
## worked out as Flow lays it out and starts at rest as the party enters it, a fire lit there burns
## and Feel draws it, and a snapshot restored into the room shown keeps it. The room is a copy of the
## crypt arena under a stand-in grass that fills its biome (tests/support/stand_in_grass.gd), pinned
## as a one-room biome (bench/pinned_run.gd). Every room of a biome's own cover, mirrored and
## through a snapshot into a joining game, is tests/gameplay/cover/test_cover_biome.gd's (CB3b; the
## row run's next room went with CB8).
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const CoverScript := preload("res://gameplay/cover/cover.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const PinnedRun := preload("res://bench/pinned_run.gd")
const StandInGrass := preload("res://tests/support/stand_in_grass.gd")
const ARENA: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")
const DT: float = 1.0 / 60.0
const BURNING: int = 1

var flow: FlowScript
var events: Node
var tick: TickScript
var input: Node
var registry: Node
var cover: CoverScript
var feel: FeelScript


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	events = root.get_node("Events")
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	registry = root.get_node("Registry")
	cover = root.get_node("Cover") as CoverScript
	feel = root.get_node("Feel") as FeelScript
	var grass: Array[CoverKind] = [StandInGrass.make([ARENA.biome], 0.3, 3)]
	cover.use_kinds(grass)
	feel.cover().use_kinds(grass)
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)


func after_each() -> void:
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	flow.run_id_to_play = FlowScript.DEFAULT_RUN_ID
	for seat in 4:
		input.leave(seat)
	tick.begin_run()
	cover.use_kinds(null)
	feel.cover().use_kinds(null)


func _play(run_id: StringName) -> void:
	flow.run_id_to_play = run_id
	input.add_virtual_device(0)
	events.emit_signal("play_requested", 0)


## The first covered cell from the room's middle, and a fire touched there; `steps` of the area.
func _light(steps: int) -> int:
	var middle: int = cover.layout.cell_of(Vector2(cover.layout.columns, cover.layout.rows) * float(CoverLayout.CELL) * 0.5)
	var cell: int = -1
	for at in cover.layout.cells.size():
		var near: int = (middle + at) % cover.layout.cells.size()
		if cover.layout.cells[near] != 0:
			cell = near
			break
	events.emit_signal("floor_touched", -1, &"fire", cover.layout.cell_rect(cell).get_center(), 0.0)
	for i in steps:
		cover.step(DT)
	return cell


## The cells not at rest, each with its state, as the area holds them and as Feel shows them.
func _fire() -> Array:
	var held: Dictionary = {}
	var shown: Dictionary = {}
	for cell in cover.active_cells():
		held[cell] = cover.state_at(cell)
		shown[cell] = feel.cover().shown_state(cell)
	return [held, shown]


func test_a_room_entered_starts_at_rest() -> void:
	_play(PinnedRun.pin(registry, ARENA))
	check(cover.layout != null and cover.layout.count() > 0, "the room's cover is worked out")
	check_equal(cover.cell_count(), cover.layout.cells.size(), "its state sized to it")
	check(cover.active_cells().is_empty(), "at rest")
	var cell: int = _light(1)
	check_equal(cover.state_at(cell), BURNING, "fire lights it")
	check_equal(feel.cover().shown_state(cell), BURNING, "and Feel draws it")


func test_a_snapshot_mid_fire_restored_into_the_room_shown_keeps_its_fire() -> void:
	_play(PinnedRun.pin(registry, ARENA))
	_light(40)
	var fire: Array = _fire()
	check(not (fire[0] as Dictionary).is_empty(), "a fire burns")
	check_equal(fire[1], fire[0], "Feel draws it")
	var snapshot: Snapshot = Snapshot.take(tick.state_areas(), root)
	check_equal(snapshot.problems, PackedStringArray(), "taken without problems")
	var taken: Dictionary = SimHash.areas(tick.state_areas(), StateWalk.new())
	for i in 30:
		cover.step(DT)
	check_equal(snapshot.restore(tick.state_areas(), root), PackedStringArray(), "restored without problems")
	check_equal(SimHash.areas(tick.state_areas(), StateWalk.new()), taken, "the game is the snapshot's")
	check_equal(_fire(), fire, "its fire kept, and Feel draws it")
