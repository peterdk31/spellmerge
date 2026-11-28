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
	check(_world.table.is_still(prop.id), "the prop is still: never stepped, so only the gather writes its row")
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
	check_equal(_world.table.body_flags[rising.id], ActorsScript.FLAG_BODY, "up again at once")
	_check_rows("every flag")


## A fall on a real hole (tests/gameplay/actor/test_fall.gd's crack): the row is the node's on
## every tick, as it falls (`_fall`), lands and, a body no seat owns, dies of it (`_land`).
func test_a_fall_and_its_end_are_in_the_row_every_tick() -> void:
	_world.projectiles.set_holes([Rect2(200.0, 0.0, 32.0, 360.0)] as Array[Rect2])
	_world.combat.registry = _world.registry
	var body: Actor = _body(Vector2(150.0, 100.0), [&"health", &"hurtbox", &"mover", &"caster"])
	_run(2)
	_world.bus.caster_move_requested.emit(body.caster_number(), &"teleport", Vector2(66.0, 0.0), 0.0, _world.tag_of(body))
	var id: int = body.id
	var fell: bool = false
	for i in 40:
		_run(1)
		if not is_instance_valid(body) or not body.is_inside_tree():
			break
		fell = fell or body.is_falling()
		if body.is_falling():
			check_equal(_world.table.body_flags[id] & ActorsScript.FLAG_FALLING, ActorsScript.FLAG_FALLING, "falling, tick %d" % i)
		_check_rows("tick %d" % i)
	check(fell, "it fell")
	check(not is_instance_valid(body) or body.is_dying(), "and died of it")


## A swap moves another body in the middle of the bodies' step (`Mover`): its row hears it at once.
func test_a_swap_is_in_the_moved_bodys_row_at_once() -> void:
	var body: Actor = _body(START, [&"health", &"mover"])
	_run(1)
	_world.bus.target_move_requested.emit(0, body, Vector2(220.0, 140.0))
	check_equal(body.global_position, Vector2(220.0, 140.0), "swapped there")
	_check_rows("its row at once")


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


## The gather as the bodies' step starts (perf plan C2): the native module's `BodyKernel.gather` when
## it is loaded writes the bits `Actor.gd_gather_rows` writes, for actors moved and pushed by hand,
## a plain node on an id (no actor: its row left) and an open id with no node. The bodies' rows are
## emptied between the two, so each pass's rows are its own writes.
func test_the_native_gather_writes_the_twins_rows() -> void:
	if not WallSlide.native_on() and OS.get_environment("SPELLMERGE_NATIVE") == "required":
		check(false, "SPELLMERGE_NATIVE=required, but the native module is not loaded (ci/build/native.sh)")
	var table: ActorsScript = _world.table
	var bodies: Array[Actor] = []
	for i in 5:
		bodies.append(_body(START + Vector2(30.0 * i, 7.0 * i), [&"health", &"mover"]))
	var plain := Node2D.new()
	root.add_child(plain)
	plain.position = Vector2(77.0, 88.0)
	var plain_id: int = table.open(0, 0)
	table.set_node(plain_id, plain)
	var empty_id: int = table.open(0, 0)
	for i in bodies.size():
		bodies[i].position = Vector2(12.5 + i * 41.25, 300.0 - i * 3.125)
		bodies[i].velocity = Vector2(i * 1.5 - 3.0, 0.1 * i)
	var ids := PackedInt32Array()
	var n: int = table.open_ids(ids)
	var marked := Vector2(-999.0, -999.0)
	for i in bodies.size():
		table.places[bodies[i].id] = Vector2.ZERO
		table.velocities[bodies[i].id] = Vector2.ZERO
	for native in [false, true]:
		for id in [plain_id, empty_id]:
			table.places[id] = marked
			table.velocities[id] = marked
		if native:
			check(WallSlide.native_on() == false or WallSlide.kernel().call(&"gather", table.nodes(), ids, n, table.places, table.velocities), "the kernel gathered")
			if not WallSlide.native_on():
				Actor.gd_gather_rows(table, ids, n)
		else:
			Actor.gd_gather_rows(table, ids, n)
		for i in bodies.size():
			check_equal(var_to_bytes(table.places[bodies[i].id]), var_to_bytes(bodies[i].global_position), "body %d's place (native %s)" % [i, native])
			check_equal(var_to_bytes(table.velocities[bodies[i].id]), var_to_bytes(bodies[i].velocity), "body %d's velocity (native %s)" % [i, native])
		check_equal(table.places[plain_id], marked, "a plain node's row is left (native %s)" % native)
		check_equal(table.velocities[empty_id], marked, "an id with no node is left (native %s)" % native)
		for i in bodies.size():
			table.places[bodies[i].id] = Vector2.ZERO
			table.velocities[bodies[i].id] = Vector2.ZERO
	table.close(plain_id)
	table.close(empty_id)
	plain.free()
