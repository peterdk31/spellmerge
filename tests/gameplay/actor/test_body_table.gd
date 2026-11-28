extends "res://tests/support/suite.gd"
## The actor table's body table (perf plan change 2, C1, docs/milestones/perf-plan.md; core/actors/
## README.md, "The body table"): the columns `places`, `velocities`, `radii` and `body_flags` follow
## the nodes. Each body writes its row when its id opens, after its own tick, as the bodies' step
## starts (every open body, `Tick`) and after a restore; a closed id's row is empty. Checked on a
## real Tick stepping the bodies, through moves, a body moved from outside, spawns, downs, falls,
## deaths, a new size, and a snapshot taken and restored.

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const TickScript := preload("res://core/sim/tick.gd")
const Snapshot := preload("res://core/sim/snapshot.gd")
const BodyRows := preload("res://tests/support/body_rows.gd")

const START: Vector2 = Vector2(100.0, 100.0)

var _world: Fixture
var _tick: TickScript


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_tick = own(TickScript.new()) as TickScript
	_tick.actors = _world.table


func after_each() -> void:
	_world.free_all()


## A body the Tick steps (the fixture's are stepped by hand).
func _body(at: Vector2, kinds: Array[StringName], controller: ActorController = null) -> Actor:
	var body: Actor = _world.actor(at, kinds, controller)
	body.ticking = true
	return body


func _run(ticks: int) -> void:
	for i in ticks:
		_tick.run(TickScript.DT)


## Every open body's row is what its node says, and every other row is empty.
func _check_rows(label: String) -> void:
	check_equal(BodyRows.rows_wrong(_world.table), PackedStringArray(), label)


func test_a_body_writes_its_row_as_its_id_opens() -> void:
	var body: Actor = _body(START, [&"health", &"mover"])
	check(body.id != ActorsScript.NONE, "it has an id")
	check_equal(_world.table.places[body.id], START, "where it stands")
	check_equal(_world.table.radii[body.id], body.wall_radius(), "its radius against the walls")
	check(body.wall_radius() > 0.0, "a radius of its own")
	check_equal(_world.table.body_flags[body.id], ActorsScript.FLAG_BODY, "a body's row, standing")
	_check_rows("every row as the nodes say")


func test_the_rows_follow_a_walk_tick_by_tick() -> void:
	var walker := Fixture.Scripted.new()
	walker.move = Vector2(1.0, 0.5)
	var body: Actor = _body(START, [&"health", &"mover"], walker)
	var other: Actor = _body(START + Vector2(0.0, 60.0), [&"health", &"mover"])
	for i in 20:
		_run(1)
		_check_rows("tick %d" % i)
	check(body.global_position.x > START.x + 10.0, "it walked: %s" % body.global_position)
	check(_world.table.velocities[body.id] != Vector2.ZERO, "with a velocity")
	check_equal(_world.table.places[other.id], other.global_position, "the one standing too")


func test_a_body_moved_from_outside_is_in_its_row_at_the_next_bodies_step() -> void:
	var prop: Actor = _world.prop(START)
	prop.ticking = true
	var body: Actor = _body(START + Vector2(40.0, 0.0), [&"health", &"mover"])
	_run(1)
	# As Flow places a body, or a swap moves another: between two bodies' steps.
	prop.position = Vector2(300.0, 200.0)
	body.position = Vector2(20.0, 30.0)
	body.velocity = Vector2(5.0, 0.0)
	_run(1)
	check(_world.table.is_still(prop.id), "the prop is still: never stepped")
	_check_rows("the still prop and the body gathered as the step started")
	check_equal(_world.table.places[prop.id], Vector2(300.0, 200.0), "the still prop where it was put")


func test_spawns_downs_and_falls_are_in_the_flags() -> void:
	var rising: Actor = Actor.new()
	rising.add_child(Mover.new())
	rising.spawn(TickScript.DT * 3.0, &"")
	rising = _world.add(rising, START)
	rising.ticking = true
	check_equal(_world.table.body_flags[rising.id], ActorsScript.FLAG_BODY | ActorsScript.FLAG_DOWN | ActorsScript.FLAG_SPAWNING, "spawning in: down")
	_run(1)
	_check_rows("still spawning")
	_run(3)
	check(not rising.is_spawning(), "landed")
	check_equal(_world.table.body_flags[rising.id], ActorsScript.FLAG_BODY, "standing")
	rising.set_down(true)
	check_equal(_world.table.body_flags[rising.id], ActorsScript.FLAG_BODY | ActorsScript.FLAG_DOWN, "downed")
	rising.set_down(false)
	# As `_fall` starts one (a fall on a real hole: tests/gameplay/actor/test_fall.gd).
	rising.fall_left = HoleRules.FALL_SECONDS
	rising.write_row()
	check_equal(_world.table.body_flags[rising.id], ActorsScript.FLAG_BODY | ActorsScript.FLAG_DOWN | ActorsScript.FLAG_FALLING, "falling: down")
	_check_rows("every flag")


func test_a_new_size_is_in_the_radius() -> void:
	var body: Actor = _body(START, [&"health", &"mover"])
	var radius: float = body.wall_radius()
	body.set_size(2.0)
	check_equal(_world.table.radii[body.id], radius * 2.0, "twice the radius at once")
	_check_rows("after the new size")


func test_a_death_marks_the_row_and_its_end_empties_it() -> void:
	var body: Actor = _body(START, [&"health", &"mover"])
	var other: Actor = _body(START + Vector2(30.0, 0.0), [&"health", &"mover"])
	var id: int = body.id
	body.die(ActorsScript.NONE)
	check_equal(_world.table.body_flags[id], ActorsScript.FLAG_BODY | ActorsScript.FLAG_DYING, "dying at once, still in its row")
	_check_rows("dying")
	_world.actors.erase(body)
	body.free()
	check_equal(_world.table.body_flags[id], 0, "its id closed: no flags")
	check_equal(_world.table.places[id], Vector2.ZERO, "and no place")
	check_equal(_world.table.radii[id], 0.0, "nor radius")
	_run(1)
	_check_rows("the rest as the nodes say")
	var next: Actor = _body(START + Vector2(0.0, 50.0), [&"health"])
	check_equal(next.id, id, "the id handed out again")
	check_equal(_world.table.places[id], next.global_position, "the new body's row")
	check(other.is_inside_tree(), "the other stood by")


func test_a_restore_writes_the_rows_again() -> void:
	# Bodies with no controller of a test's own, so the snapshot takes them whole; moved by hand.
	var body: Actor = _body(START, [&"health", &"hurtbox", &"mover"])
	var standing: Actor = _body(START + Vector2(0.0, 80.0), [&"health", &"hurtbox", &"mover"])
	_run(5)
	var at: Vector2 = body.global_position
	var snapshot := Snapshot.take(_areas(), root)
	check_equal(snapshot.problems, PackedStringArray(), "taken")
	body.position += Vector2(40.0, 0.0)
	_run(10)
	standing.set_size(1.5)
	standing.set_down(true)
	# A body opened after the snapshot: the restore frees it, and its id's row empties.
	var late: Actor = _body(START + Vector2(200.0, 0.0), [&"health", &"hurtbox", &"mover"])
	var late_id: int = late.id
	_run(1)
	check(_world.table.places[body.id] != at, "it moved on: %s" % _world.table.places[body.id])
	check_equal(snapshot.restore(_areas(), root, _world.prepare), PackedStringArray(), "restored")
	check_equal(body.global_position, at, "back where it was")
	check_equal(_world.table.places[body.id], at, "its row back with it")
	check(not is_instance_valid(late) or not late.is_inside_tree(), "the late body is gone")
	check_equal(_world.table.body_flags[late_id], 0, "its row empty")
	_check_rows("every row as the restored nodes say")
	_run(3)
	_check_rows("and on from there")


func _areas() -> Dictionary:
	var areas: Dictionary = {"Actors": _world.table, "Projectiles": _world.projectiles, "Spells": _world.spells, "Combat": _world.combat}
	for body in _world.actors:
		if is_instance_valid(body) and body.is_inside_tree() and body.id != ActorsScript.NONE:
			areas["actor %d" % body.id] = body
	return areas
