extends "res://tests/support/suite.gd"
## The cover area (ground cover GC5, gameplay/cover/cover.gd, docs/milestones/ground-cover.md rules 3
## to 6), with the test grass (tests/core/fixtures/cover_content: rest -fire-> burning 1.2 s -> ash
## -30 s-> rest; burning -frost-> rest; burning burns its standers and spreads fire): fire lights the
## cells inside its circle, spreads by the run's chance (the same seed the same fire), frost puts it
## out, burning goes to ash and ash regrows only where its kind says; a body standing in burning grass
## burns (Combat's status, again every half second), a dust heap in it blows; the state is reset only
## where a room starts in play (`room_entered`), never by a `room_built`; the view is told each tick's
## changes and, after a room built or a restore, the cells not at rest; a room with no cover keeps no
## state; a resting room is arrays of zeros.
##
## godot --headless --path . --script res://tests/gameplay/cover/test_cover.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const CoverScript := preload("res://gameplay/cover/cover.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const GRASS: CoverKind = preload("res://tests/core/fixtures/cover_content/cover/test_grass/test_grass.tres")
const HEAP: PropBase = preload("res://content/props/dust_heap/dust_heap.tres")

const DT: float = 1.0 / 60.0
const ROOM: StringName = &"cover_test_room"
## The room: at least SIZE (a room's size is never under the screen's), a wall at SIZE's last
## cell, the grass over FIELD (19×9 cells from the top left).
const SIZE: Vector2 = Vector2(320.0, 160.0)
const FIELD: Rect2 = Rect2(0.0, 0.0, 304.0, 144.0)
const BURNING: int = 1
const ASH: int = 2

var _world: Fixture
var _cover: CoverScript
var _layout: Node2D
## Every `cover_changed` heard: [cells, states] (copies).
var _changes: Array = []
## Every `status_requested` heard for a body: [target, status].
var _asked: Array = []


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_cap(512)
	_changes.clear()
	_asked.clear()
	_world.bus.cover_changed.connect(func(cells: PackedInt32Array, states: PackedInt32Array) -> void: _changes.append([cells.duplicate(), states.duplicate()]))
	_world.bus.status_requested.connect(func(_caster: int, target: Node, status: StringName, _duration: float, _strength: float) -> void: _asked.append([target, status]))
	_layout = _make_layout(FIELD)
	_cover = _make_cover(7, [GRASS])


func after_each() -> void:
	if is_instance_valid(_cover):
		_cover.free()
	_world.free_all()


## A layout of SIZE (its size fixed by a wall in its last cell) with a field of the test grass over
## `field` (none for an empty rect).
func _make_layout(field: Rect2) -> Node2D:
	var layout := own(Node2D.new()) as Node2D
	var walls := StaticBody2D.new()
	walls.collision_layer = RoomBase.WALL_LAYER
	layout.add_child(walls)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16.0, 16.0)
	shape.shape = rect
	shape.position = SIZE - Vector2(8.0, 8.0)
	walls.add_child(shape)
	if field.has_area():
		var patch := CoverField.new()
		patch.kind = GRASS.id
		patch.density = 1.0
		patch.offset_left = field.position.x
		patch.offset_top = field.position.y
		patch.offset_right = field.end.x
		patch.offset_bottom = field.end.y
		layout.add_child(patch)
	return layout


## A cover area of this world, rolling by `run_seed`, laying `kinds`, its room built and entered.
func _make_cover(run_seed: int, kinds: Array[CoverKind], layout: Node2D = _layout) -> CoverScript:
	var made := CoverScript.new()
	made.events = _world.bus
	made.actors = _world.table
	made.registry = _world.registry
	made.sim = Sim.seeded(run_seed)
	made.use_kinds(kinds)
	root.add_child(made)
	_world.bus.room_built.emit(ROOM, layout)
	_world.bus.room_entered.emit(ROOM)
	return made


func _cell(x: int, y: int) -> int:
	return y * _cover.layout.columns + x


func _middle(cell: int) -> Vector2:
	return _cover.layout.cell_rect(cell).get_center()


func _touch(element: StringName, at: Vector2, radius: float = 0.0) -> void:
	_world.bus.floor_touched.emit(0, element, at, radius)


func _steps(count: int, cover: CoverScript = _cover) -> void:
	for i in count:
		cover.step(DT)


func _burning() -> int:
	var found: int = 0
	for cell in _cover.layout.cells.size():
		if _cover.state_at(cell) == BURNING:
			found += 1
	return found


func test_the_room_is_laid_and_at_rest() -> void:
	check(_cover.layout.columns >= 20 and _cover.layout.rows >= 10, "the room's grid")
	check_equal(_cover.layout.count(GRASS.id), 19 * 9, "grass over the field")
	check(_cover.active_cells().is_empty(), "nothing active")
	var zeros := true
	for cell in _cover.layout.cells.size():
		zeros = zeros and _cover.state_at(cell) == 0 and _cover.age_at(cell) == 0.0
	check(zeros, "every cell at rest: the state is zeros")
	check(_changes.is_empty(), "nothing told: the view lays a room at rest")


func test_fire_lights_the_cell_it_lands_in_at_the_next_step() -> void:
	var cell: int = _cell(5, 4)
	_touch(&"fire", _middle(cell))
	check_equal(_cover.state_at(cell), 0, "queued, not yet")
	_steps(1)
	check_equal(_cover.state_at(cell), BURNING, "burning")
	check_equal(_cover.active_cells(), PackedInt32Array([cell]), "the one active cell")
	check_equal(_changes, [[PackedInt32Array([cell]), PackedInt32Array([BURNING])]], "told once")


func test_a_touch_lights_the_cells_whose_middles_are_in_its_circle() -> void:
	var at: Vector2 = _middle(_cell(8, 4))
	_touch(&"fire", at, 17.0)
	_steps(1)
	var lit := PackedInt32Array()
	for cell in _cover.layout.cells.size():
		if _cover.state_at(cell) == BURNING:
			lit.append(cell)
	check_equal(lit, PackedInt32Array([_cell(8, 3), _cell(7, 4), _cell(8, 4), _cell(9, 4), _cell(8, 5)]), "a plus of five, in cell order")
	check_equal(_changes.size(), 1, "one event for the tick")
	check_equal(_changes[0][0], lit, "its cells in cell order")


func test_an_element_with_no_trigger_and_bare_floor_change_nothing() -> void:
	_touch(&"lightning", _middle(_cell(3, 3)), 30.0)
	_touch(&"fire", _middle(_cell(19, 2)))
	_steps(1)
	check(_cover.active_cells().is_empty(), "lightning on grass and fire on bare floor: nothing")
	check(_changes.is_empty(), "nothing told")


func test_frost_puts_burning_grass_out() -> void:
	var cell: int = _cell(4, 4)
	_touch(&"fire", _middle(cell))
	_steps(1)
	_touch(&"frost", _middle(cell))
	_steps(1)
	check_equal(_cover.state_at(cell), 0, "at rest again")
	check(not _cover.active_cells().has(cell), "no longer active")


func test_burning_goes_to_ash_and_the_grass_regrows_after_its_wait() -> void:
	var still := GRASS.duplicate(true) as CoverKind
	still.states[BURNING].spread_chance = 0.0
	still.states[BURNING].spreads = &""
	_cover.free()
	_cover = _make_cover(7, [still])
	var cell: int = _cell(2, 2)
	_touch(&"fire", _middle(cell))
	_steps(1)
	_steps(70)
	check_equal(_cover.state_at(cell), BURNING, "1.2 s: still burning")
	_steps(2)
	check_equal(_cover.state_at(cell), ASH, "then ash")
	_steps(int(30.0 / DT) - 5)
	check_equal(_cover.state_at(cell), ASH, "ash for 30 s")
	_steps(10)
	check_equal(_cover.state_at(cell), 0, "then grass again: its kind says so")
	check(_cover.active_cells().is_empty(), "at rest, not active")


func test_ash_with_no_wait_never_regrows() -> void:
	var crypt := GRASS.duplicate(true) as CoverKind
	crypt.states[BURNING].spreads = &""
	crypt.states[BURNING].spread_chance = 0.0
	crypt.states[ASH].triggers = [] as Array[CoverTrigger]
	_cover.free()
	_cover = _make_cover(7, [crypt])
	var cell: int = _cell(2, 2)
	_touch(&"fire", _middle(cell))
	_steps(int(40.0 / DT))
	check_equal(_cover.state_at(cell), ASH, "ash after 40 s")


func test_fire_spreads_by_the_runs_chance_the_same_seed_the_same_fire() -> void:
	var first: Array[PackedByteArray] = _fire_from(_cover)
	var again: Array[PackedByteArray] = _fire_from(_make_cover(7, [GRASS]))
	var other: Array[PackedByteArray] = _fire_from(_make_cover(8, [GRASS]))
	check(first[first.size() - 1].count(BURNING) + first[first.size() - 1].count(ASH) > 1, "it spread")
	check_equal(again, first, "the same seed: the same fire, tick by tick")
	check(other != first, "another seed: another fire")


## Fire at the field's middle and 90 ticks of `cover`: each tick's states.
func _fire_from(cover: CoverScript) -> Array[PackedByteArray]:
	var seen: Array[PackedByteArray] = []
	_world.bus.floor_touched.emit(0, &"fire", cover.layout.cell_rect(_cell(9, 4)).get_center(), 0.0)
	for i in 90:
		cover.step(DT)
		var states := PackedByteArray()
		for cell in cover.layout.cells.size():
			states.append(cover.state_at(cell))
		seen.append(states)
	# Each area hears the bus: the others are taken off it.
	cover.queue_free()
	_world.bus.room_entered.emit(ROOM)
	return seen


func test_a_spread_reaches_only_a_neighbour_its_element_moves_on() -> void:
	var sure := GRASS.duplicate(true) as CoverKind
	sure.states[BURNING].spread_chance = 1.0
	# Burning for long enough that each neighbour is all but sure to catch.
	sure.states[BURNING].triggers[1].seconds = 100.0
	_cover.free()
	_cover = _make_cover(7, [sure], _make_layout(Rect2(0.0, 0.0, 64.0, 16.0)))
	_touch(&"fire", _middle(_cell(0, 0)))
	_steps(1)
	var rolled: int = _cover.rolls()
	_steps(900)
	check(_cover.rolls() > rolled, "it rolled")
	for x in 4:
		check(_cover.state_at(_cell(x, 0)) != 0, "the row of grass burnt along (%d)" % x)
	check_equal(_cover.state_at(_cell(0, 1)), 0, "bare floor below never")
	check_equal(_cover.state_at(_cell(4, 0)), 0, "nor past the grass")


func test_a_body_standing_in_burning_grass_burns_every_half_second() -> void:
	var cell: int = _cell(6, 6)
	var body: Actor = _world.actor(_middle(cell), [&"health", &"hurtbox"])
	var away: Actor = _world.actor(_middle(_cell(12, 6)), [&"health", &"hurtbox"])
	var still := GRASS.duplicate(true) as CoverKind
	still.states[BURNING].spreads = &""
	still.states[BURNING].spread_chance = 0.0
	_cover.free()
	_cover = _make_cover(7, [still])
	_touch(&"fire", _middle(cell))
	_steps(1)
	check(_world.combat.has_status(body, &"burn"), "it burns, by Combat's own rules")
	check(not _world.combat.has_status(away, &"burn"), "a body elsewhere does not")
	check_equal(_cover.harmed(), PackedInt32Array([body.id]), "kept by its actor id")
	_steps(69)
	var asked: int = _asked.filter(func(heard: Array) -> bool: return heard[0] == body).size()
	check_equal(asked, 3, "asked at once and every half second while it burns (%d)" % asked)
	_steps(5)
	check_equal(_cover.state_at(cell), ASH, "ash")
	check(_cover.harmed().is_empty(), "ash harms nobody: dropped")


func test_a_body_leaving_is_dropped_and_asked_again_on_coming_back() -> void:
	var cell: int = _cell(6, 6)
	var body: Actor = _world.actor(_middle(cell), [&"health", &"hurtbox"])
	_touch(&"fire", _middle(cell))
	_steps(1)
	body.position = _middle(_cell(15, 1))
	_steps(1)
	check(_cover.harmed().is_empty(), "out of it: dropped")
	body.position = _middle(cell)
	_asked.clear()
	_steps(1)
	check_equal(_asked.size(), 1, "back in: asked at once")


func test_a_dust_heap_standing_in_burning_grass_blows() -> void:
	var cell: int = _cell(10, 6)
	var heap: Actor = _world.add(PropBody.make(HEAP), _middle(cell))
	_touch(&"fire", _middle(cell))
	_steps(1)
	check_equal(heap.state_triggers.state_id(), &"burnt", "its own status trigger lit it")


func test_a_room_built_keeps_the_state_and_only_a_room_entered_resets_it() -> void:
	var cell: int = _cell(3, 3)
	_touch(&"fire", _middle(cell))
	_steps(1)
	_changes.clear()
	_world.bus.room_built.emit(ROOM, _layout)
	check_equal(_cover.state_at(cell), BURNING, "a room built (a restore's) keeps the fire")
	check_equal(_changes, [[PackedInt32Array([cell]), PackedInt32Array([BURNING])]], "and tells the view every cell not at rest")
	_changes.clear()
	_world.bus.room_entered.emit(ROOM)
	check_equal(_cover.state_at(cell), 0, "a room entered starts at rest")
	check(_cover.active_cells().is_empty(), "nothing active")
	check_equal(_changes, [[PackedInt32Array([cell]), PackedInt32Array([0])]], "told back to rest")


func test_a_snapshot_mid_fire_restores_its_fire_and_tells_the_view() -> void:
	var cell: int = _cell(3, 3)
	_touch(&"fire", _middle(cell))
	_steps(20)
	var snapshot: Snapshot = Snapshot.take({"cover": _cover}, root)
	check_equal(snapshot.problems, PackedStringArray(), "taken")
	var taken: Dictionary = SimHash.areas({"cover": _cover}, StateWalk.new())
	# The tick after, played on by the area the snapshot was taken of (a new area's room entered
	# resets every area on the bus).
	_cover.step(DT)
	var after: Dictionary = SimHash.areas({"cover": _cover}, StateWalk.new())
	var fresh: CoverScript = _make_cover(7, [GRASS])
	_changes.clear()
	check_equal(snapshot.restore({"cover": fresh}, root), PackedStringArray(), "restored")
	check_equal(SimHash.areas({"cover": fresh}, StateWalk.new()), taken, "the same state")
	check_equal(fresh.state_at(cell), BURNING, "still burning")
	var told: Dictionary = {}
	for heard: Array in _changes:
		for at in (heard[0] as PackedInt32Array).size():
			told[heard[0][at]] = heard[1][at]
	var shown: bool = true
	for active in fresh.active_cells():
		shown = shown and told.get(active, -1) == fresh.state_at(active)
	check(shown and not told.is_empty(), "the view told every cell not at rest")
	fresh.step(DT)
	check_equal(SimHash.areas({"cover": fresh}, StateWalk.new()), after, "and it plays on the same")
	fresh.free()


func test_a_room_with_no_cover_keeps_no_state_and_hears_no_touch() -> void:
	_cover.free()
	_cover = _make_cover(7, [GRASS], _make_layout(Rect2()))
	check_equal(_cover.layout.count(), 0, "no cover")
	_touch(&"fire", Vector2(40.0, 40.0), 40.0)
	_steps(1)
	check_equal(_cover.get(&"_state"), PackedByteArray(), "no state")
	check_equal(_cover.get(&"_touch_at"), PackedVector2Array(), "nothing queued")


func test_a_run_start_renews_it() -> void:
	_touch(&"fire", _middle(_cell(3, 3)))
	_steps(30)
	_cover.begin_run()
	check_equal(_cover.rolls(), 0, "the counter from 0")
	check(_cover.active_cells().is_empty(), "nothing active")
	check_equal(_cover.get(&"_state"), PackedByteArray(), "empty until the next room sizes it")


func test_a_cell_rolls_only_for_neighbours_its_element_moves_on() -> void:
	# One cell of grass alone: its neighbours are bare floor, so it never rolls.
	_cover.free()
	_cover = _make_cover(7, [GRASS], _make_layout(Rect2(32.0, 32.0, 16.0, 16.0)))
	_touch(&"fire", _middle(_cell(2, 2)))
	_steps(30)
	check_equal(_cover.rolls(), 0, "no roll for bare floor")
	# Two side by side, one burning: one roll a tick for the other while it is at rest.
	_cover.free()
	_cover = _make_cover(7, [GRASS], _make_layout(Rect2(32.0, 32.0, 32.0, 16.0)))
	_touch(&"fire", _middle(_cell(2, 2)))
	_steps(1)
	check_equal(_cover.rolls(), 1, "one roll in the tick it is lit, for its one neighbour of grass")
	var both: bool = _cover.state_at(_cell(3, 2)) != 0
	_steps(1)
	check_equal(_cover.rolls(), 1 if both else 2, "a roll a tick while the neighbour would catch")


func test_an_id_handed_out_again_is_asked_at_once() -> void:
	var cell: int = _cell(6, 6)
	var body: Actor = _world.actor(_middle(cell), [&"health", &"hurtbox"])
	var id: int = body.id
	_touch(&"fire", _middle(cell))
	_steps(1)
	check_equal(_cover.harmed(), PackedInt32Array([id]), "harmed")
	# The body goes and another opens under its id the same tick, standing in the same fire.
	_world.actors.erase(body)
	body.free()
	var other: Actor = _world.actor(_middle(cell), [&"health", &"hurtbox"])
	check_equal(other.id, id, "the id handed out again")
	_asked.clear()
	_steps(1)
	check_equal(_asked.size(), 1, "the new body is asked at once, not after the old one's wait")


func test_touches_in_one_tick_apply_in_the_order_heard() -> void:
	var cell: int = _cell(4, 4)
	_touch(&"fire", _middle(cell))
	_touch(&"frost", _middle(cell))
	_steps(1)
	check_equal(_cover.state_at(cell), 0, "lit, then put out")
	_touch(&"frost", _middle(cell))
	_touch(&"fire", _middle(cell))
	_steps(1)
	check_equal(_cover.state_at(cell), BURNING, "frost on grass does nothing, then fire lights it")


func test_a_restore_with_less_fire_tells_the_view_back_to_rest() -> void:
	var snapshot: Snapshot = Snapshot.take({"cover": _cover}, root)
	var cell: int = _cell(4, 4)
	_touch(&"fire", _middle(cell))
	_steps(1)
	_changes.clear()
	check_equal(snapshot.restore({"cover": _cover}, root), PackedStringArray(), "restored to before the fire")
	check_equal(_cover.state_at(cell), 0, "at rest")
	check_equal(_changes, [[PackedInt32Array([cell]), PackedInt32Array([0])]], "the view told it is at rest again")


func test_no_roll_for_a_neighbour_its_element_leaves_in_the_state_it_is_in() -> void:
	# Regression (GC6): a state whose element row names the state itself moves nothing, so a burning
	# neighbour of such grass costs no roll (the area rolled four a cell a tick with every cell lit).
	var again := GRASS.duplicate(true) as CoverKind
	var row := CoverTrigger.new()
	row.when = CoverTrigger.When.ELEMENT
	row.element = &"fire"
	row.then = &"burning"
	again.states[BURNING].triggers.append(row)
	_cover.free()
	_cover = _make_cover(7, [again], _make_layout(Rect2(32.0, 32.0, 32.0, 16.0)))
	_touch(&"fire", _middle(_cell(2, 2)), 24.0)
	_steps(1)
	check_equal(_cover.state_at(_cell(2, 2)), BURNING, "both lit")
	check_equal(_cover.state_at(_cell(3, 2)), BURNING, "both lit (2)")
	_steps(30)
	check_equal(_cover.rolls(), 0, "neither rolls for the other, already burning")


func test_cover_harmful_at_rest_harms_with_nothing_burning() -> void:
	# The step looks at no body while every cell is at rest and none harms at rest (GC6); cover that
	# does (cobwebs) still harms whoever stands in it.
	var webs := GRASS.duplicate(true) as CoverKind
	webs.states[0].status = &"chill"
	webs.states[0].status_strength = 0.5
	webs.states[0].status_duration = 1.0
	webs.states[0].status_every = 0.5
	var body: Actor = _world.actor(_middle(_cell(6, 6)), [&"health", &"hurtbox"])
	_cover.free()
	_cover = _make_cover(7, [webs])
	_steps(1)
	check(_cover.active_cells().is_empty(), "nothing out of rest")
	check_equal(_cover.harmed(), PackedInt32Array([body.id]), "the body in it is harmed")
	check_equal(_asked.filter(func(heard: Array) -> bool: return heard[0] == body and heard[1] == &"chill").size(), 1, "asked its status")
	# The test grass harms nobody at rest: a body in it is never asked, and nothing is kept.
	_cover.free()
	_asked.clear()
	_cover = _make_cover(7, [GRASS])
	_steps(30)
	check(_cover.harmed().is_empty(), "nobody harmed by grass at rest")
	check(_asked.is_empty(), "nobody asked")
	# Lit, then gone back to rest: the body that was harmed is dropped all the same.
	_touch(&"fire", _middle(_cell(6, 6)))
	_steps(1)
	check_equal(_cover.harmed(), PackedInt32Array([body.id]), "burning: harmed")
	_touch(&"frost", _middle(_cell(6, 6)))
	_steps(1)
	check(_cover.active_cells().is_empty(), "put out: every cell at rest")
	check(_cover.harmed().is_empty(), "and the body dropped")
