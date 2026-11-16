extends "res://tests/support/suite.gd"
## The cover area on the real autoloads (ground cover GC5, gameplay/cover/cover.gd): a room's cover is
## worked out as Flow lays it out and starts at rest as the party enters it; a snapshot taken mid-fire
## in a room other than the run's first, restored into a game that is in the run's first room (a
## joining machine), keeps its fire (the restore's `room_built` never resets it, only `room_entered`
## does) and Feel draws it; a restore into the room shown keeps it too. The rooms are copies of the
## crypt arena under a stand-in grass that fills its biome (tests/support/stand_in_grass.gd), pinned
## as a run of known shape (tests/support/pinned_run.gd).
##
## godot --headless --path . --script res://tests/gameplay/cover/test_cover_rooms.gd

const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const CoverScript := preload("res://gameplay/cover/cover.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const PinnedRun := preload("res://tests/support/pinned_run.gd")
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


## The room's enemies down, and the wizard in its lit exit (a run one room wide lights the second): the party goes on.
func _go_on() -> void:
	for enemy: Node in flow.get(&"_enemies").duplicate():
		events.emit_signal("enemy_died", 0, enemy, Vector2.ZERO, -1)
	var exit: Actor = ExitRules.exits_in(flow.contents)[1]
	flow.get_wizard(0).position = HubRules.area_at(exit.prop, exit.position).get_center()
	flow.step(DT)


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
	_play(PinnedRun.pin(registry, ARENA, &"", RoomKind.FILL_ENEMIES, 16, 2, 1))
	check(cover.layout != null and cover.layout.count() > 0, "the room's cover is worked out")
	check_equal(cover.get(&"_state").size(), cover.layout.cells.size(), "its state sized to it")
	check(cover.active_cells().is_empty(), "at rest")
	var cell: int = _light(1)
	check_equal(cover.state_at(cell), BURNING, "fire lights it")
	check_equal(feel.cover().shown_state(cell), BURNING, "and Feel draws it")
	_go_on()
	check(cover.active_cells().is_empty(), "the next room starts at rest")
	check_equal(feel.cover().shown_state(cell), 0, "and is drawn so")


func test_a_snapshot_mid_fire_in_a_later_room_keeps_its_fire_in_a_joining_game() -> void:
	var run_id: StringName = PinnedRun.pin(registry, ARENA, &"", RoomKind.FILL_ENEMIES, 16, 4, 1)
	var other := ARENA.duplicate() as RoomBase
	other.id = StringName(String(run_id) + "_other")
	other.biome = ARENA.biome
	other.kinds = [run_id] as Array[StringName]
	registry.call("add", &"rooms", other)
	_play(run_id)
	var first: StringName = flow.room_id
	_go_on()
	var later: StringName = flow.room_id
	check(later != first, "the second room is the other template")
	_light(40)
	var fire: Array = _fire()
	check(not (fire[0] as Dictionary).is_empty(), "a fire burns")
	check_equal(fire[1], fire[0], "Feel draws it")
	var snapshot: Snapshot = Snapshot.take(tick.state_areas(), root)
	check_equal(snapshot.problems, PackedStringArray(), "taken without problems")
	var taken: Dictionary = SimHash.areas(tick.state_areas(), StateWalk.new())
	# A joining machine: the run starts again (another seed) until its first room is not the later one.
	for attempt in 32:
		flow.stop_run()
		events.emit_signal("play_requested", 0)
		if flow.room_id != later:
			break
	check(flow.room_id != later, "the joining machine is in the other room")
	check(cover.active_cells().is_empty(), "its cover at rest")
	check_equal(snapshot.restore(tick.state_areas(), root), PackedStringArray(), "restored without problems")
	check_equal(flow.room_id, later, "in the later room")
	check_equal(SimHash.areas(tick.state_areas(), StateWalk.new()), taken, "the game is the snapshot's")
	check_equal(_fire(), fire, "its fire kept, and Feel draws it")
	check_equal(snapshot.restore(tick.state_areas(), root), PackedStringArray(), "restored again, into the room shown")
	check_equal(_fire(), fire, "the fire kept again")
