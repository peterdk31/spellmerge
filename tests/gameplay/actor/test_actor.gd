extends "res://tests/support/suite.gd"
## The actor (actors G4, docs/milestones/M2-actors.md, "The actor"): it opens an id in the actor
## table with its ramp and its driver's team and seat and closes it when it leaves; a controller
## change (`drive`, `release`) moves the team and the seat in the table; the step reads the
## controller's intent (no controller: the body stands and keeps its aim); an enemy's data goes to
## its components; Health used up kills it (unless it can be downed); a step makes no objects.
##
## godot --headless --path . --script res://tests/gameplay/actor/test_actor.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ImpData := preload("res://content/enemies/ember_imp/ember_imp.tres")

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


func _wizard_controller(seat: int) -> Fixture.Scripted:
	var controller := Fixture.Scripted.new()
	controller.team = ActorsScript.TEAM_WIZARDS
	controller.seat = seat
	return controller


func test_an_actor_opens_its_id_with_its_drivers_team_and_seat_and_closes_it() -> void:
	# Ids taken first, so the wizard's id is not its seat.
	for i in 5:
		_world.table.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	var wizard: Actor = _world.actor(Vector2.ZERO, [&"health"], _wizard_controller(2))
	wizard.ramp = 2
	check(wizard.id >= 5, "an id that is not a seat: %d" % wizard.id)
	check_equal(_world.table.team_of(wizard.id), ActorsScript.TEAM_WIZARDS, "the controller's team")
	check_equal(_world.table.seat_of(wizard.id), 2, "the controller's seat")
	check_equal(_world.table.actor_of_seat(2), wizard.id, "the seat drives it")
	check(_world.table.node_of(wizard.id) == wizard, "the table finds its node")
	var id: int = wizard.id
	root.remove_child(wizard)
	check(not _world.table.is_open(id), "leaving the tree closes the id")
	check_equal(wizard.id, ActorsScript.NONE, "and the actor has none")
	root.add_child(wizard)
	check(_world.table.is_open(wizard.id), "back in the tree it opens one again")


func test_an_actor_with_no_controller_has_no_seat_and_its_idle_team() -> void:
	var dummy: Actor = _world.actor(Vector2.ZERO, [&"health"])
	check_equal(dummy.seat(), ActorsScript.NONE, "no seat")
	check_equal(dummy.team(), ActorsScript.NONE, "no team by default")
	check_equal(_world.table.ramp_of(dummy.id), ActorsScript.RAMP_ENEMY, "the enemy ramp by default")


func test_drive_and_release_move_the_team_and_seat_in_the_table() -> void:
	var home := Fixture.Scripted.new()
	var imp: Actor = _world.actor(Vector2.ZERO, [&"health", &"mover"], home)
	check_equal(_world.table.team_of(imp.id), ActorsScript.TEAM_ENEMIES, "an AI's team")
	check_equal(_world.table.seat_of(imp.id), ActorsScript.NONE, "and no seat")
	var guest := _wizard_controller(1)
	own(guest)
	imp.drive(guest)
	check(imp.controller == guest, "the guest drives")
	check_equal(_world.table.team_of(imp.id), ActorsScript.TEAM_WIZARDS, "the team follows the controller")
	check_equal(_world.table.seat_of(imp.id), 1, "and the seat")
	check_equal(_world.table.actor_of_seat(1), imp.id, "the seat drives the imp now")
	check_equal(home.stopped_count, 1, "the home controller was put aside")
	imp.release()
	check(imp.controller == home, "the home controller is back")
	check_equal(_world.table.team_of(imp.id), ActorsScript.TEAM_ENEMIES, "with its team")
	check_equal(_world.table.seat_of(imp.id), ActorsScript.NONE, "and no seat")
	check_equal(guest.stopped_count, 1, "the guest stopped")
	check_equal(home.started_count, 2, "the home controller started again")


func test_a_body_left_without_a_controller_stands_and_keeps_its_aim() -> void:
	var controller := _wizard_controller(0)
	var wizard: Actor = _world.actor(Vector2.ZERO, [&"mover"], controller)
	controller.move = Vector2.RIGHT
	controller.aim = Vector2.UP
	_world.run(1)
	check(wizard.velocity.x > 0.0, "the intent walks it")
	check_equal(wizard.aim, Vector2.UP, "and aims it")
	wizard.drive(null)
	check_equal(_world.table.team_of(wizard.id), ActorsScript.TEAM_WIZARDS, "it keeps its home team")
	check_equal(_world.table.seat_of(wizard.id), ActorsScript.NONE, "but no seat drives it")
	_world.run(1)
	check_equal(wizard.velocity, Vector2.ZERO, "with no controller it stands")
	check_equal(wizard.aim, Vector2.UP, "and aims where it last aimed")


func test_the_aim_is_unit_length_and_the_muzzle_is_the_reach_from_the_hand() -> void:
	var controller := _wizard_controller(0)
	var wizard: Actor = _world.actor(Vector2(10.0, 20.0), [], controller)
	wizard.hand_offset = Vector2(0.0, -10.0)
	wizard.staff_reach = 14.0
	controller.aim = Vector2(3.0, 0.0)
	_world.run(1)
	check_equal(wizard.aim, Vector2.RIGHT, "unit length")
	check_equal(wizard.aim_pivot(), Vector2(10.0, 10.0), "the hand")
	check_equal(wizard.muzzle_position(), Vector2(24.0, 10.0), "the staff tip")


func test_enemy_data_goes_to_the_components() -> void:
	var imp := Actor.new()
	imp.data = ImpData
	for component: Node in [Health.new(), Hurtbox.new(), Contact.new(), Mover.new(), Caster.new()]:
		imp.add_child(component)
	_world.add(imp, Vector2.ZERO)
	check_equal(imp.health.max_health, ImpData.max_health, "health")
	check_equal(imp.health.health, ImpData.max_health, "full")
	check_equal(imp.mover.speed, ImpData.move_speed, "walking speed")
	check_equal(imp.contact.damage, ImpData.contact_damage, "contact damage")
	check(imp.caster != null and imp.caster.has_staff(0), "its staff is built")
	check_equal(imp.caster.cards_of(0).slice(0, ImpData.cards.size()), ImpData.cards, "with its cards")
	check_equal(imp.caster.max_mana, ImpData.max_mana, "its mana")
	check(_world.combat.is_enemy(imp), "the hurtbox registered it with Combat")
	var plain_data: EnemyBase = ImpData.duplicate() as EnemyBase
	plain_data.staff = null
	var chaser := Actor.new()
	chaser.data = plain_data
	chaser.add_child(Caster.new())
	_world.add(chaser, Vector2.ZERO)
	check(chaser.caster == null, "data without a staff leaves the actor without a caster")
	check_equal(chaser.caster_number(), -1, "and without a caster number")


func test_health_used_up_kills_the_actor_once() -> void:
	var imp: Actor = _world.actor(Vector2.ZERO, [&"health"])
	var deaths: Array[int] = []
	imp.died.connect(func(killer: int) -> void: deaths.append(killer))
	imp.health.take(imp.health.max_health, 3)
	imp.health.take(10, 1)
	check_equal(deaths, [3] as Array[int], "it died once, killed by the last hit's player")
	check(imp.is_queued_for_deletion(), "and frees itself")


func test_a_downable_actor_is_not_killed_by_its_health() -> void:
	var wizard: Actor = _world.actor(Vector2.ZERO, [&"health"], _wizard_controller(0))
	wizard.downable = true
	wizard.health.take(wizard.health.max_health)
	check(not wizard.is_dying(), "something else downs it")
	check(not wizard.is_queued_for_deletion(), "it stays")


func test_a_down_actor_is_off_the_hurtbox_and_stands() -> void:
	var controller := _wizard_controller(0)
	var wizard: Actor = _world.actor(Vector2.ZERO, [&"health", &"hurtbox", &"mover"], controller)
	controller.move = Vector2.RIGHT
	check(wizard.hurtbox.is_on(), "a standing actor can be hit")
	wizard.set_down(true)
	_world.run(1)
	check(not wizard.hurtbox.is_on(), "a down one cannot")
	check_equal(wizard.velocity, Vector2.ZERO, "and stands")
	wizard.set_down(false)
	_world.run(1)
	check(wizard.hurtbox.is_on(), "standing again it can be hit")


func test_a_step_makes_no_objects() -> void:
	var controller := _wizard_controller(0)
	var wizard: Actor = _world.actor(Vector2.ZERO, [&"health", &"hurtbox", &"contact", &"mover", &"caster"], controller, [[&"bolt"]])
	controller.move = Vector2(0.5, 0.5)
	controller.aim = Vector2.LEFT
	controller.held = [0] as Array[int]
	# Warm up (first casts fill the pools), then count.
	for i in 8:
		wizard.step(Fixture.STEP)
	var before: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for i in 30:
		wizard.step(Fixture.STEP)
	var made: float = Performance.get_monitor(Performance.OBJECT_COUNT) - before
	check_equal(made, 0.0, "objects made by 30 steps of the actor")
