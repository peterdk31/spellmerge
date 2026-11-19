extends RefCounted
## A cover area on a small room covered by one kind (ground cover GC8, docs/milestones/ground-cover.md):
## the game's cover kinds' own tests (content/cover/<id>/test_<id>.gd) play their kind's states
## through the real area (gameplay/cover/cover.gd) and Feel's look of it (gameplay/feel/cover.gd)
## with it, so a kind's test checks its data, not a copy of the engine. Not a test itself.

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const CoverScript := preload("res://gameplay/cover/cover.gd")
const FeelCoverScript := preload("res://gameplay/feel/cover.gd")
const PropNames := preload("res://tests/content/props/prop_names.gd")

const DT: float = 1.0 / 60.0
const ROOM: StringName = &"cover_kit_room"
## The room: SIZE, a wall in its last cell; the kind over FIELD (19×9 cells from the top left).
const SIZE: Vector2 = Vector2(320.0, 160.0)
const FIELD: Rect2 = Rect2(0.0, 0.0, 304.0, 144.0)

var world: Fixture
var cover: CoverScript
## Feel's look of the room, laid by the same `room_built` (its motes off: no pool).
var look: FeelCoverScript
var kind: CoverKind
## Every `status_requested` heard: [target, status, duration, strength].
var asked: Array = []
var _layout: Node2D


## The kind `of_kind` over FIELD in a room of `root`'s, rolled by `run_seed`, built and entered.
func _init(root: Node, of_kind: CoverKind, run_seed: int = 7) -> void:
	kind = of_kind
	world = Fixture.new(root)
	world.bus.status_requested.connect(func(_caster: int, target: Node, status: StringName, duration: float, strength: float) -> void: asked.append([target, status, duration, strength]))
	_layout = Node2D.new()
	var walls := StaticBody2D.new()
	walls.collision_layer = RoomBase.WALL_LAYER
	_layout.add_child(walls)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16.0, 16.0)
	shape.shape = rect
	shape.position = SIZE - Vector2(8.0, 8.0)
	walls.add_child(shape)
	var field := CoverField.new()
	field.kind = of_kind.id
	field.offset_right = FIELD.end.x
	field.offset_bottom = FIELD.end.y
	_layout.add_child(field)
	look = FeelCoverScript.new(RoomBase.FLOOR_Z + 1)
	look.events = world.bus
	look.use_kinds([of_kind] as Array[CoverKind])
	root.add_child(look)
	cover = CoverScript.new()
	cover.events = world.bus
	cover.actors = world.table
	cover.registry = world.registry
	cover.sim = Sim.seeded(run_seed)
	cover.use_kinds([of_kind] as Array[CoverKind])
	root.add_child(cover)
	world.bus.room_built.emit(ROOM, 0, _layout)
	world.bus.room_entered.emit(ROOM, 0)


func free_all() -> void:
	if is_instance_valid(cover):
		cover.free()
	if is_instance_valid(look):
		look.free()
	if is_instance_valid(_layout):
		_layout.free()
	world.free_all()


## What is wrong with the kind, given the game's elements and statuses.
func problems() -> PackedStringArray:
	return kind.problems(PropNames.known(world.registry))


func cell(x: int, y: int) -> int:
	return y * cover.layout.columns + x


func middle(at_cell: int) -> Vector2:
	return cover.layout.cell_rect(at_cell).get_center()


## `element` touches the floor at `at` within `radius` (as Spells tells it).
func touch(element: StringName, at: Vector2, radius: float = 0.0) -> void:
	world.bus.floor_touched.emit(0, element, at, radius)


## `count` ticks of the area and Combat (which applies the statuses it asks for).
func steps(count: int) -> void:
	for i in count:
		cover.step(DT)
		world.combat.step(DT)


## Ticks for `seconds`.
func wait(seconds: float) -> void:
	steps(roundi(seconds / DT))


## The name of the state cell `at_cell` is in.
func state_of(at_cell: int) -> StringName:
	return kind.states[cover.state_at(at_cell)].state_id


## How many cells are in the state named `state_id`.
func count_in(state_id: StringName) -> int:
	var found: int = 0
	for at_cell in cover.layout.cells.size():
		if cover.layout.cells[at_cell] != 0 and state_of(at_cell) == state_id:
			found += 1
	return found


## True while `body` has the status `status_id` (Combat's).
func has_status(body: Actor, status_id: StringName) -> bool:
	return world.combat.has_status(body, status_id)
