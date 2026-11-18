extends "res://tests/support/suite.gd"
## Spawning (enemy spawning EA1, docs/milestones/enemy-spawning.md, "The simulation"): a body set to
## `spawn` before it is added is not there yet for its seconds. It can't be hurt (its hurt shape is
## never registered), targeted or possessed (`is_down`); it neither touches nor is touched; it doesn't
## think, cast, move or step its phases (no adds called); its contact damage starts only once it has
## landed; it lands on time; a snapshot mid-spawn is restored with it, and Feel's look draws it
## from that state alone; the state hash holds it. Real actors in the actor fixture's world, real
## Combat.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const Snapshot := preload("res://core/sim/snapshot.gd")

const START: Vector2 = Vector2(150.0, 100.0)
## How long the spawns here last (any length: today's `rise`'s), and the ticks one takes at the
## fixture's step (0.8 / 0.0625 = 12.8: it lands on the 13th).
const SECONDS: float = 0.8
const SPAWN_TICKS: int = 13

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)
	_world.projectiles.set_bounds(Rect2(0.0, 0.0, 640.0, 360.0))
	_world.combat.registry = _world.registry


func after_each() -> void:
	_world.free_all()


## An enemy (health, a hurt circle, contact damage 10, a Mover) driven by a scripted controller that
## walks right (none unless `controlled`), set to spawn in before it is added (as Flow does), at `at`.
## `data` (optional) is applied as an enemy's.
func _spawning(at: Vector2 = START, data: EnemyBase = null, controlled: bool = true) -> Actor:
	var body := Actor.new()
	body.name = "Spawning"
	var health := Health.new()
	health.max_health = 50
	body.add_child(health)
	body.add_child(Hurtbox.new())
	var contact := Contact.new()
	contact.damage = 10
	body.add_child(contact)
	body.add_child(Mover.new())
	if controlled:
		var controller := Fixture.Scripted.new()
		controller.team = ActorsScript.TEAM_ENEMIES
		controller.move = Vector2.RIGHT
		body.add_child(controller)
	body.data = data
	body.spawn(SECONDS)
	return _world.add(body, at)


## A wizard on seat 0 at `at`.
func _wizard(at: Vector2) -> Actor:
	var controller := Fixture.Scripted.new()
	controller.team = ActorsScript.TEAM_WIZARDS
	controller.seat = 0
	return _world.actor(at, [&"health", &"hurtbox", &"mover"], controller)


## `count` ticks as the game steps a body (`tick_step`: its step, then its move unless it spawns in),
## then the systems.
func _run(count: int) -> void:
	for i in count:
		for body in _world.actors:
			if is_instance_valid(body) and body.is_inside_tree():
				body.tick_step(Fixture.STEP)
		_world.projectiles.step(Fixture.STEP)
		_world.spells.step(Fixture.STEP)
		_world.combat.step(Fixture.STEP)


func test_it_is_down_unhittable_and_unpossessable_while_it_spawns() -> void:
	var body: Actor = _spawning()
	# Long enough to outlast the shot's flight (the fixture's `shoot` steps the world).
	body.spawn(5.0)
	check(body.is_spawning() and body.is_down() and not body.is_downed(), "spawning: down to everything, but not downed")
	check(not body.hurtbox.registered, "its hurt shape was never registered, not even on its first tick")
	check(not Possession.can_start(body), "it can't be possessed")
	check(not AIBrain.can_target(body), "nothing targets it")
	check_equal(_world.shoot(body, &""), [] as Array[StringName], "a bolt passes through it")
	check_equal(body.health.health, 50.0, "unhurt")
	check(body.is_spawning(), "still spawning")
	while body.is_spawning():
		_run(1)
	check(not body.is_spawning() and not body.is_down(), "landed")
	check(body.hurtbox.registered, "its hurt shape registered as it landed")
	check(Possession.can_start(body), "it can be possessed now")
	check(AIBrain.can_target(body), "and targeted")
	check_equal(_world.shoot(body, &"").size(), 1, "a bolt hits it now")


func test_it_neither_thinks_nor_moves_while_it_spawns_and_lands_on_time() -> void:
	var body: Actor = _spawning()
	var controller := body.home_controller as Fixture.Scripted
	var shares: Array[float] = []
	for i in SPAWN_TICKS - 1:
		_run(1)
		shares.append(body.spawn_share())
		check(body.is_spawning(), "spawning after %d ticks" % (i + 1))
	check_equal(controller.thinks, 0, "its controller never thought")
	check_equal(body.global_position, START, "it stood where it rose")
	check_equal(body.velocity, Vector2.ZERO, "no velocity")
	for i in range(1, shares.size()):
		check(shares[i] > shares[i - 1], "its share grows each tick")
	check(shares[0] > 0.0 and shares[-1] < 1.0, "between 0 and 1: %s to %s" % [shares[0], shares[-1]])
	_run(1)
	check(not body.is_spawning(), "it lands on the tick its seconds run out")
	check_equal(body.spawn_share(), 1.0, "standing: its share is 1")
	check_equal(controller.thinks, 1, "and thinks on that tick")
	check(body.global_position.x > START.x, "and walks: %s" % body.global_position)


func test_it_casts_nothing_while_it_spawns() -> void:
	var body := Actor.new()
	body.add_child(Mover.new())
	var caster := Caster.new()
	caster.staff_count = 1
	caster.start_cards = [[&"bolt"]]
	body.add_child(caster)
	var controller := Fixture.Scripted.new()
	controller.team = ActorsScript.TEAM_ENEMIES
	controller.aim = Vector2.RIGHT
	# A press waits for its first think: none while it spawns in.
	controller.presses = [0] as Array[int]
	body.add_child(controller)
	body.spawn(SECONDS)
	_world.add(body, START)
	_run(SPAWN_TICKS - 1)
	check_equal(_world.projectiles.get_count(), 0, "no shot while it spawns")
	check_equal(controller.presses, [0] as Array[int], "its press not taken")
	_run(2)
	check(_world.projectiles.get_count() > 0, "it casts once it has landed")


func test_its_contact_damage_starts_only_once_it_has_landed() -> void:
	var wizard: Actor = _wizard(START + Vector2(0.0, 2.0))
	var body: Actor = _spawning()
	(body.home_controller as Fixture.Scripted).move = Vector2.ZERO
	_run(SPAWN_TICKS - 1)
	check_equal(wizard.health.health, 50.0, "a wizard on its mark is not hurt while it spawns")
	_run(2)
	check(wizard.health.health < 50.0, "it is once it has landed: %s" % wizard.health.health)


func test_it_neither_touches_nor_is_touched_while_it_spawns() -> void:
	var body: Actor = _spawning(Vector2(100.0, 100.0))
	(body.home_controller as Fixture.Scripted).move = Vector2.ZERO
	var walker: Actor = _wizard(Vector2(100.0, 100.0))
	var heard: Array[int] = []
	var walker_heard: Array[int] = []
	body.touched.connect(func(by: int) -> void: heard.append(by))
	walker.touched.connect(func(by: int) -> void: walker_heard.append(by))
	_world.table.set_touch_area(body.id, Rect2(80.0, 90.0, 40.0, 20.0))
	_world.table.set_touch_area(walker.id, Rect2(80.0, 90.0, 40.0, 20.0))
	_run(SPAWN_TICKS - 1)
	check(body.is_spawning(), "still spawning")
	check_equal(heard, [] as Array[int], "a body standing on its mark does not touch it while it spawns")
	check_equal(walker_heard, [] as Array[int], "and it touches nobody while it spawns")
	_run(2)
	check(not body.is_spawning(), "landed")
	check(heard.has(walker.id), "touched once it has landed: %s" % [heard])
	check(walker_heard.has(body.id), "and it touches: %s" % [walker_heard])


func test_its_phases_and_their_adds_wait_until_it_lands() -> void:
	var data := EnemyBase.new()
	data.id = &"test_spawning_caller"
	data.max_health = 50.0
	var called := EnemyAdds.new()
	called.enemy = &"ember_imp"
	called.count = 1
	var phase := EnemyPhase.new()
	phase.after_seconds = 0.1
	phase.transition = 0.0
	phase.adds = [called] as Array[EnemyAdds]
	data.phases = [phase] as Array[EnemyPhase]
	var asked: Array[int] = []
	_world.bus.adds_requested.connect(func(actor: int, _entry: EnemyAdds, _key: int, _wave: bool) -> void: asked.append(actor))
	var body: Actor = _spawning(START, data)
	check(body.phases != null, "it has phases")
	_run(SPAWN_TICKS - 1)
	check_equal(body.phases.current, -1, "no phase began while it spawned")
	check_equal(body.phases.elapsed, 0.0, "its phases' clock did not run")
	check_equal(asked, [] as Array[int], "no adds were called")
	_run(3)
	check_equal(body.phases.current, 0, "its phase began after it landed")
	check_equal(asked, [body.id] as Array[int], "and called its adds")


func test_spawn_with_no_time_stands_at_once() -> void:
	var body := Actor.new()
	body.add_child(Hurtbox.new())
	body.spawn(0.0)
	_world.add(body, START)
	check(not body.is_spawning() and not body.is_down(), "0 seconds: standing")
	check(body.hurtbox.registered, "registered as it was added")
	body.spawn(NAN)
	check(not body.is_spawning(), "not a number: standing")


func test_a_snapshot_mid_spawn_is_restored_and_drawn() -> void:
	# A body with no controller of a test's own, so the snapshot takes it whole.
	var body: Actor = _spawning(START, null, false)
	_run(8)
	var left: float = body.spawn_left
	var id: int = body.id
	var snapshot := Snapshot.take(_areas(), root)
	check_equal(snapshot.problems, PackedStringArray(), "taken")
	_run(1)
	body.spawn_left = 0.0
	body.spawn_seconds = 0.0
	check_equal(snapshot.restore(_areas(), root, _world.prepare), PackedStringArray(), "restored")
	check_equal(_world.table.node_of(id), body, "the same body")
	check(body.is_spawning() and is_equal_approx(body.spawn_left, left), "mid-spawn again: %s" % body.spawn_left)
	check(is_equal_approx(body.spawn_seconds, SECONDS), "with its whole spawn's seconds")
	check(not body.hurtbox.registered, "its hurt shape still off")
	# Feel's look reads the state alone: a machine that joins mid-spawn draws it.
	var look := SpawnLook.new()
	root.add_child(look)
	look.step(_world.table, 0.0)
	look.cut()
	check_equal(look.drawn(), 1, "drawn spawning")
	check_equal(body.clip_children, CanvasItem.CLIP_CHILDREN_ONLY, "cut at its feet")
	check_equal(look.marks(), 1, "its mark on the floor")
	_run(SPAWN_TICKS)
	look.step(_world.table, 0.0)
	look.cut()
	check_equal(look.drawn(), 0, "nothing drawn spawning once it has landed")
	check_equal(body.clip_children, CanvasItem.CLIP_CHILDREN_DISABLED, "its own drawing back")
	look.free()


func test_the_state_hash_holds_the_spawn() -> void:
	var body: Actor = _spawning()
	_run(3)
	var before: int = SimHash.area(StateWalk.new(), "body", body)
	body.spawn_left -= 0.0625
	check(SimHash.area(StateWalk.new(), "body", body) != before, "a spawn further on hashes otherwise")


func _areas() -> Dictionary:
	var areas: Dictionary = {"Actors": _world.table, "Projectiles": _world.projectiles, "Spells": _world.spells, "Combat": _world.combat}
	for body in _world.actors:
		if is_instance_valid(body) and body.is_inside_tree() and body.id != ActorsScript.NONE:
			areas["actor %d" % body.id] = body
	return areas


## A body that would be still (no controller, no Mover) is stepped while it spawns in, so it lands.
func test_a_body_with_nothing_to_drive_it_is_not_still_while_it_spawns() -> void:
	var body := Actor.new()
	body.add_child(Hurtbox.new())
	body.spawn(SECONDS)
	_world.add(body, START)
	check(not body.is_still(), "not still while it spawns")
	check(not _world.table.is_still(body.id), "the actor table steps it")
	_run(SPAWN_TICKS)
	check(not body.is_spawning() and body.is_still(), "landed, it is still")
	check(_world.table.is_still(body.id), "and the actor table says so")
