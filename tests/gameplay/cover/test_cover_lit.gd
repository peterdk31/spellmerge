extends "res://tests/support/suite.gd"
## Who lit the floor (the floor's first slice, docs/milestones/floor.md; the owner, 2026-11-25: a
## cell remembers who lit it, so `on kill` and Siphon count): on the real autoloads and the game's own
## cover kinds, in a copy of the crypt arena. A touch's caster and tag go with each cell it moves, a
## spread hands them on, a renewal takes the newer, a cell at rest keeps none; they are state, so a
## snapshot keeps them and a game resumed from it plays the same.
const FlowScript := preload("res://gameplay/flow/flow.gd")
const TickScript := preload("res://core/sim/tick.gd")
const CoverScript := preload("res://gameplay/cover/cover.gd")
const PinnedRun := preload("res://bench/pinned_run.gd")
const ARENA: RoomBase = preload("res://content/rooms/crypt/arena_01.tres")
const DT: float = 1.0 / 60.0
const NO_PLAYER: int = -1

var flow: FlowScript
var events: Node
var tick: TickScript
var input: Node
var registry: Node
var cover: CoverScript


func before_each() -> void:
	flow = root.get_node("Flow") as FlowScript
	events = root.get_node("Events")
	tick = root.get_node("Tick") as TickScript
	input = root.get_node("PlayerInput")
	registry = root.get_node("Registry")
	cover = root.get_node("Cover") as CoverScript
	flow.world_parent = own(Node.new()) as Node
	root.add_child(flow.world_parent)
	flow.run_id_to_play = PinnedRun.pin(registry, ARENA)
	input.add_virtual_device(0)
	events.emit_signal("play_requested", 0)


func after_each() -> void:
	flow.stop_run()
	flow.world_parent = null
	flow.mode = FlowScript.MODE_RUN
	flow.run_id_to_play = FlowScript.DEFAULT_RUN_ID
	for seat in 4:
		input.leave(seat)
	tick.begin_run()


## The middle of the floor cell `dx`, `dy` cells from the room's middle floor cell.
func _at(dx: int, dy: int) -> Vector2:
	var laid: CoverLayout = cover.layout
	var middle: Vector2 = laid.origin + Vector2(laid.columns, laid.rows) * float(CoverLayout.CELL) * 0.5
	return middle + Vector2(dx, dy) * float(CoverLayout.CELL)


func _floor_state(at: Vector2) -> StringName:
	var cell: int = cover.layout.cell_of(at)
	var state: CoverState = cover.cover_state_at(cell)
	return state.state_id if state != null else &""


func _steps(count: int) -> void:
	for i in count:
		cover.step(DT)


## A 5×5 lake round the room's middle, wetted by actor 2 with `wet_tag`.
func _lake(wet_tag: int) -> void:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			events.emit_signal("floor_touched", 2, &"water", _at(dx, dy), 0.0, wet_tag)
	_steps(30)


func test_the_floor_is_on_every_open_cell() -> void:
	check(cover.layout.count(&"floor") > cover.layout.cells.size() / 3, "most cells are floor (%d of %d)" % [cover.layout.count(&"floor"), cover.layout.cells.size()])
	check_equal(_floor_state(_at(0, 0)), &"dry", "dry at rest")
	check(cover.active_cells().is_empty(), "a room at rest steps nothing")


func test_a_cell_remembers_who_lit_it_and_a_spread_hands_it_on() -> void:
	var wet_tag: int = SpellTag.make(2, 0, 0, 0)
	_lake(wet_tag)
	var room: CoverRoom = cover.room()
	var middle: int = cover.layout.cell_of(_at(0, 0))
	check_equal(_floor_state(_at(0, 0)), &"wet", "the lake is wet")
	check_equal(room.actor_at(middle), 2, "wetted by actor 2")
	check_equal(room.tag_at(middle), wet_tag, "with its spell")
	var zap_tag: int = SpellTag.make(5, 1, 0, 0)
	events.emit_signal("floor_touched", 5, &"lightning", _at(-2, -2), 0.0, zap_tag)
	_steps(20)
	var far: int = cover.layout.cell_of(_at(2, 2))
	check(_floor_state(_at(2, 2)) == &"live" or _floor_state(_at(2, 2)) == &"spent", "the lightning ran across (%s)" % _floor_state(_at(2, 2)))
	check_equal(room.actor_at(far), 5, "the far cell is the lightning's caster's")
	check_equal(room.tag_at(far), zap_tag, "and its spell's")
	events.emit_signal("floor_touched", 7, &"water", _at(6, 0), 0.0, 0)
	_steps(30)
	var renewed: int = cover.layout.cell_of(_at(6, 0))
	check_equal(room.actor_at(renewed), 7, "a new puddle apart is its waterer's")
	check_equal(room.actor_at(cover.layout.cell_of(_at(8, 8))), NO_PLAYER, "dry floor is nobody's")


func test_a_snapshot_keeps_who_lit_it_and_plays_on_the_same() -> void:
	_lake(SpellTag.make(2, 0, 0, 0))
	events.emit_signal("floor_touched", 5, &"lightning", _at(0, 0), 0.0, SpellTag.make(5, 1, 0, 0))
	_steps(3)
	var snapshot: Snapshot = Snapshot.take(tick.state_areas(), root)
	check_equal(snapshot.problems, PackedStringArray(), "taken without problems")
	var taken: Dictionary = SimHash.areas(tick.state_areas(), StateWalk.new())
	_steps(40)
	var played: Dictionary = SimHash.areas(tick.state_areas(), StateWalk.new())
	var lit: PackedInt32Array = (cover.room().get("_active_actor") as PackedInt32Array).duplicate()
	check(not lit.is_empty(), "cells are lit")
	check_equal(snapshot.restore(tick.state_areas(), root), PackedStringArray(), "restored without problems")
	check_equal(SimHash.areas(tick.state_areas(), StateWalk.new()), taken, "the game is the snapshot's")
	_steps(40)
	check_equal(SimHash.areas(tick.state_areas(), StateWalk.new()), played, "and plays on the same")
	check_equal(cover.room().get("_active_actor"), lit, "who lit each cell the same")


func test_who_lit_it_is_in_the_hash() -> void:
	_lake(SpellTag.make(2, 0, 0, 0))
	var one: Dictionary = SimHash.areas(tick.state_areas(), StateWalk.new())
	var room: CoverRoom = cover.room()
	var actors: PackedInt32Array = room.get("_active_actor")
	actors[0] = 9
	room.set("_active_actor", actors)
	check(SimHash.areas(tick.state_areas(), StateWalk.new()) != one, "another lighter hashes otherwise")
