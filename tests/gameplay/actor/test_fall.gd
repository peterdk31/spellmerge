extends "res://tests/support/suite.gd"
## Falling into a hole (hub rework HR-H2, docs/milestones/hub-rework.md, "Holes" 4 and 5, question
## 10): a body that walks and ends a move over a hole with nothing crossing falls for
## `HoleRules.FALL_SECONDS`, down to everything that asks; then a wizard is back on its last ground,
## protected, having paid `HoleRules.FALL_COST` of its most health (nothing where falls are free),
## and anything else dies of it through Combat, its killer whoever last hit or pulled it. A boss
## never falls; a body downed over a hole falls and comes back still down; a long dash off the
## room's edge falls. Real actors in the actor fixture's world, real Combat.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const EventsScript := preload("res://core/events/events.gd")
const Snapshot := preload("res://core/sim/snapshot.gd")

const START: Vector2 = Vector2(150.0, 100.0)
## A crack four cells wide (from x 200 to 232), one a cell wide (x 300 to 308) and one two cells
## wide (x 400 to 416), all across the room.
const CRACK: Rect2 = Rect2(200.0, 0.0, 32.0, 360.0)
const THIN: Rect2 = Rect2(300.0, 0.0, 8.0, 360.0)
const NARROW: Rect2 = Rect2(400.0, 0.0, 16.0, 360.0)
## Ticks a fall takes at the fixture's step, and a few more.
const FALL_TICKS: int = 12

var _world: Fixture
var _fell: Array[int] = []
var _returned: Array[Vector2] = []
var _died: Array[int] = []


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_world.projectiles.set_holes([CRACK, THIN, NARROW] as Array[Rect2])
	_world.combat.registry = _world.registry
	_fell.clear()
	_returned.clear()
	_died.clear()
	_world.bus.body_fell.connect(func(actor: int) -> void: _fell.append(actor))
	_world.bus.body_returned.connect(func(_actor: int, at: Vector2) -> void: _returned.append(at))
	_world.bus.enemy_died.connect(func(killer: int, _enemy: Node, _at: Vector2, _shot: int) -> void: _died.append(killer))


func after_each() -> void:
	_world.free_all()


## A wizard on seat `seat` at `at` (health 50, a hurt circle, a Mover and a caster).
func _wizard(at: Vector2 = START, seat: int = 0) -> Actor:
	var controller := Fixture.Scripted.new()
	controller.team = ActorsScript.TEAM_WIZARDS
	controller.seat = seat
	return _world.actor(at, [&"health", &"hurtbox", &"mover", &"caster"], controller)


## An enemy at `at` (no seat).
func _enemy(at: Vector2) -> Actor:
	var controller := Fixture.Scripted.new()
	controller.team = ActorsScript.TEAM_ENEMIES
	return _world.actor(at, [&"health", &"hurtbox", &"mover", &"caster"], controller)


func _ask(body: Actor, mode: StringName, move: Vector2, seconds: float) -> void:
	_world.bus.caster_move_requested.emit(body.caster_number(), mode, move, seconds, _world.tag_of(body))


## `count` ticks as the game steps a body (its step, then its move), then the systems.
func _run(count: int) -> void:
	for i in count:
		for body in _world.actors:
			if is_instance_valid(body) and body.is_inside_tree():
				body.tick_step(Fixture.STEP)
		_world.projectiles.step(Fixture.STEP)
		_world.spells.step(Fixture.STEP)
		_world.combat.step(Fixture.STEP)


func test_a_teleport_into_a_crack_one_and_two_cells_wide_falls() -> void:
	for at: Vector2 in [Vector2(304.0, 100.0), Vector2(408.0, 100.0), Vector2(216.0, 100.0)]:
		var body: Actor = _wizard(Vector2(at.x - 40.0, 100.0))
		_run(1)
		_ask(body, &"teleport", Vector2(40.0, 0.0), 0.0)
		check(_world.projectiles.is_hole(body.global_position), "over the crack at %s" % at)
		_run(1)
		check(body.is_falling() and body.is_down() and not body.is_downed(), "it falls at once, down but not downed (%s)" % at)
		check(_fell.has(body.id), "body_fell told with its id (%s)" % at)
		_world.free_all()
		_world = Fixture.new(root)
		_world.projectiles.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
		_world.projectiles.set_holes([CRACK, THIN, NARROW] as Array[Rect2])
		_world.bus.body_fell.connect(func(actor: int) -> void: _fell.append(actor))


func test_a_dash_that_ends_in_a_crack_falls_and_one_over_it_does_not() -> void:
	var over: Actor = _wizard()
	var into: Actor = _wizard(Vector2(150.0, 200.0), 1)
	_run(1)
	_ask(over, &"dash", Vector2(130.0, 0.0), 0.5)
	_ask(into, &"dash", Vector2(66.0, 0.0), 0.25)
	for i in 4:
		_run(1)
		check(not into.is_falling(), "no fall while its dash crosses (tick %d)" % i)
	_run(2)
	check(into.is_falling(), "it falls once its dash ends over the crack")
	check(not over.is_falling(), "a dash that goes on over the crack does not fall")
	_run(6)
	check(not over.is_falling() and over.global_position.x > CRACK.end.x, "it landed past the crack: %s" % over.global_position)


func test_a_swap_and_a_portals_exit_onto_a_hole_fall() -> void:
	var swapped: Actor = _wizard()
	var ported: Actor = _wizard(Vector2(150.0, 200.0), 1)
	_run(1)
	_world.bus.target_move_requested.emit(5, swapped, Vector2(216.0, 100.0))
	_world.bus.target_move_requested.emit(5, ported, Vector2(408.0, 200.0))
	_run(1)
	check(swapped.is_falling() and ported.is_falling(), "both fall")


func test_a_wizard_comes_back_on_its_last_ground_paying_a_fifth() -> void:
	var body: Actor = _wizard()
	_run(2)
	check(body.has_ground and body.ground == START, "its last ground is where it stood clear of holes")
	_ask(body, &"teleport", Vector2(66.0, 0.0), 0.0)
	_run(1)
	check(body.is_falling(), "it falls")
	_run(1)
	check(not body.hurtbox.is_on(), "no hurt shape while it falls")
	check(not body.caster.cast(0), "it casts nothing")
	_run(FALL_TICKS)
	check(not body.is_falling() and not body.is_down(), "the fall is over")
	check_equal(body.global_position, START, "back on its last ground")
	check_equal(_returned, [START] as Array[Vector2], "body_returned told where")
	check(is_equal_approx(body.health.health, 50.0 * (1.0 - HoleRules.FALL_COST)), "it lost a fifth of its most health: %s" % body.health.health)
	check(body.health.is_protected(), "protected for a moment")
	check(body.hurtbox.is_on(), "its hurt shape back")


func test_a_fall_in_a_room_where_falls_are_free_costs_nothing() -> void:
	_world.bus.room_entered.emit(&"hub", 0)
	check_equal(_world.combat.fall_cost, 0.0, "the hub's falls are free")
	var body: Actor = _wizard()
	_run(1)
	_ask(body, &"teleport", Vector2(66.0, 0.0), 0.0)
	_run(FALL_TICKS + 1)
	check_equal(body.health.health, 50.0, "no cost")
	check_equal(body.global_position, START, "back")
	_world.bus.room_entered.emit(&"arena_01", 0)
	check_equal(_world.combat.fall_cost, HoleRules.FALL_COST, "a run's room costs a fifth")


func test_an_enemy_that_falls_dies_through_combat_put_down_to_its_last_hitter() -> void:
	var enemy: Actor = _enemy(Vector2(190.0, 100.0))
	var wizard: Actor = _wizard(Vector2(100.0, 300.0))
	_run(1)
	check(_world.combat.hit(wizard.id, enemy, 1.0, Vector2.RIGHT, 250.0), "the wizard hits it into the crack")
	for i in 30:
		if _fell.has(enemy.id):
			break
		_run(1)
	check(_fell.has(enemy.id), "it falls once the push (and the hit's stop) is spent: %s" % enemy.global_position)
	_run(FALL_TICKS)
	check(not is_instance_valid(enemy) or enemy.is_dying(), "it died of the fall")
	check_equal(_died, [wizard.id] as Array[int], "an enemy's death, the wizard's kill")


func test_a_pull_into_a_crack_is_the_pullers_kill() -> void:
	var enemy: Actor = _enemy(Vector2(190.0, 100.0))
	var wizard: Actor = _wizard(Vector2(100.0, 300.0))
	_run(1)
	_world.combat.pull(wizard.id, Vector2(216.0, 100.0), 100.0, 200.0, true)
	_run(FALL_TICKS + 6)
	check_equal(_died, [wizard.id] as Array[int], "pulled in, the puller's kill")


func test_a_body_downed_over_a_hole_falls_and_comes_back_down() -> void:
	var body: Actor = _wizard()
	_run(2)
	body.set_down(true)
	body.health.reset(0.0)
	_world.bus.target_move_requested.emit(5, body, Vector2(216.0, 100.0))
	_run(1)
	check(body.is_falling(), "a downed body over a hole falls (it would hover there)")
	_run(FALL_TICKS)
	check_equal(body.global_position, START, "back on its last ground")
	check(body.is_downed() and body.is_down(), "still down, to be revived on the ground")


func test_the_boss_never_falls() -> void:
	var boss: Actor = _enemy(Vector2(150.0, 100.0))
	var data := EnemyBase.new()
	data.boss = true
	boss.data = data
	_run(1)
	_ask(boss, &"teleport", Vector2(66.0, 0.0), 0.0)
	_run(1)
	check(not boss.is_falling(), "it does not fall")
	check(not _world.projectiles.circle_blocked(boss.global_position, boss.wall_radius(), true), "put on the nearest ground: %s" % boss.global_position)
	_world.bus.target_move_requested.emit(5, boss, Vector2(408.0, 100.0))
	_run(1)
	check(not boss.is_falling() and not _world.projectiles.is_hole(boss.global_position), "a swap toward a hole too: %s" % boss.global_position)


## The move takes its room from the walk's end (perf plan C2, `RoomGrid.walk_place`); a boss the
## move then puts on the nearest ground has the room of where it stands, not of where the walk ended.
func test_a_boss_put_on_ground_has_the_room_it_stands_in() -> void:
	var grid: RoomGrid = _world.projectiles.grid()
	# Two places split inside the crack, left of its middle: a walk ending at x 212 is in the right one,
	# and the nearest ground (the crack's left lip) is in the left one.
	var left: int = grid.add_place(Rect2(0.0, 0.0, 208.0, 360.0))
	var right: int = grid.add_place(Rect2(208.0, 0.0, 432.0, 360.0))
	var boss: Actor = _enemy(Vector2(150.0, 100.0))
	var data := EnemyBase.new()
	data.boss = true
	boss.data = data
	_run(1)
	check_equal(boss.room, left, "in the left place")
	for way in [Vector2(62.0, 0.0), Vector2(70.0, 0.0)]:
		_ask(boss, &"teleport", way - (boss.global_position - Vector2(150.0, 100.0)), 0.0)
		_run(1)
		check(not grid.is_hole(boss.global_position), "put on ground: %s" % boss.global_position)
		check_equal(boss.room, grid.place_at(boss.global_position), "its room is where it stands: %s" % boss.global_position)
		check_equal(boss.room, left if way.x < 66.0 else right, "on the near lip's side: %s" % boss.global_position)


func test_a_body_something_ends_at_no_health_is_ended_by_its_fall() -> void:
	# A decoy (Entities ends it at 0, `downable`) falls as any body.
	var decoy: Actor = _enemy(Vector2(150.0, 100.0))
	decoy.downable = true
	var emptied: Array[int] = []
	decoy.health.depleted.connect(func(killer: int) -> void: emptied.append(killer))
	_run(1)
	_ask(decoy, &"teleport", Vector2(66.0, 0.0), 0.0)
	_run(FALL_TICKS + 1)
	check_equal(emptied.size(), 1, "its health is emptied, so what owns it ends it")


func test_a_local_stop_over_a_hole_is_no_fall() -> void:
	var body: Actor = _wizard()
	_run(1)
	_ask(body, &"dash", Vector2(66.0, 0.0), 0.25)
	_run(3)
	_world.table.hold(body.id, 0.5)
	_run(4)
	check(not body.is_falling(), "held mid-dash over the crack: no fall")


func test_a_long_dash_off_the_rooms_edge_falls() -> void:
	_world.projectiles.set_holes([Rect2(560.0, 0.0, 80.0, 360.0)] as Array[Rect2])
	var body: Actor = _wizard(Vector2(500.0, 200.0))
	_run(2)
	_ask(body, &"dash", Vector2(200.0, 0.0), 0.5)
	_run(10)
	check(body.is_falling(), "out of the bounds, over the void, it falls: %s" % body.global_position)
	var ground: Vector2 = body.ground
	check(ground.x > 500.0 and ground.x < 560.0 - 6.0 - HoleRules.GROUND_MARGIN, "its last ground is the last place clear of the edge it dashed over: %s" % ground)
	_run(FALL_TICKS)
	check_equal(body.global_position, ground, "and it is back there")


func test_being_placed_forgets_the_last_ground_and_ends_a_fall() -> void:
	var body: Actor = _wizard()
	_run(2)
	_ask(body, &"teleport", Vector2(66.0, 0.0), 0.0)
	_run(1)
	check(body.is_falling() and body.has_ground, "falling, with a last ground")
	body.placed()
	check(not body.is_falling() and not body.has_ground, "a new room: no fall and no last ground")
	body.position = Vector2(150.0, 300.0)
	_run(1)
	check(body.has_ground and body.ground == Vector2(150.0, 300.0), "its ground is where it stands next")


func test_with_no_ground_yet_it_comes_back_at_the_nearest_ground() -> void:
	var body: Actor = _wizard(Vector2(216.0, 100.0))
	_run(1)
	check(body.is_falling() and not body.has_ground, "placed over the crack, it falls with no ground")
	_run(FALL_TICKS)
	check(not _world.projectiles.circle_blocked(body.global_position, body.wall_radius(), true), "back at the nearest ground: %s" % body.global_position)


func test_a_snapshot_mid_fall_is_restored_and_drawn() -> void:
	# A body with no controller of a test's own, so the snapshot takes it whole.
	var body: Actor = _world.actor(START, [&"health", &"hurtbox", &"mover", &"caster"])
	_run(2)
	_ask(body, &"teleport", Vector2(66.0, 0.0), 0.0)
	_run(4)
	var left: float = body.fall_left
	var id: int = body.id
	var snapshot := Snapshot.take(_areas(), root)
	check_equal(snapshot.problems, PackedStringArray(), "taken")
	_run(1)
	body.fall_left = 0.0
	body.fell_by = 3
	check_equal(snapshot.restore(_areas(), root, _world.prepare), PackedStringArray(), "restored")
	check_equal(_world.table.node_of(id), body, "the same body")
	check(body.is_falling() and is_equal_approx(body.fall_left, left), "mid-fall again: %s" % body.fall_left)
	# Feel's look reads the state alone: a machine that joins mid-fall draws it.
	var look := FallLook.new()
	look.step(_world.table, 0.0)
	check_equal(body.scale, FallLook.scale_at(body.size, body.fall_share()), "drawn as far through its fall as it is")
	check(body.scale.x < body.size and body.modulate.a < 1.0, "smaller and fading")
	body.fall_left = 0.0
	look.step(_world.table, 0.0)
	check_equal(body.scale, Vector2.ONE * body.size, "its own size back once the fall is over")
	check_equal(body.modulate, Color.WHITE, "and its colour")
	check_equal(look.drawn(), 0, "nothing drawn falling")


func _areas() -> Dictionary:
	var areas: Dictionary = {"Actors": _world.table, "Projectiles": _world.projectiles, "Spells": _world.spells, "Combat": _world.combat}
	for body in _world.actors:
		if is_instance_valid(body) and body.is_inside_tree() and body.id != ActorsScript.NONE:
			areas["actor %d" % body.id] = body
	return areas


## The review's case: a second fall soon after the return (inside its protection) costs a fifth again.
func test_a_second_fall_while_protected_costs_again() -> void:
	var body: Actor = _wizard()
	_run(2)
	for n in 2:
		_ask(body, &"teleport", Vector2(66.0, 0.0), 0.0)
		_run(FALL_TICKS + 1)
		check(body.health.is_protected(), "protected after fall %d" % (n + 1))
	check(is_equal_approx(body.health.health, 50.0 * (1.0 - 2.0 * HoleRules.FALL_COST)), "two falls, two fifths: %s" % body.health.health)


## An enemy with no hurt shape (no row in Combat) that falls still dies as a foe of the wizards.
func test_an_enemy_with_no_hurt_shape_dies_of_a_fall_as_a_foe() -> void:
	var controller := Fixture.Scripted.new()
	controller.team = ActorsScript.TEAM_ENEMIES
	var enemy: Actor = _world.actor(Vector2(150.0, 100.0), [&"health", &"mover", &"caster"], controller)
	_run(1)
	_ask(enemy, &"teleport", Vector2(66.0, 0.0), 0.0)
	_run(FALL_TICKS + 1)
	check_equal(_died.size(), 1, "its death told")
