extends "res://tests/support/suite.gd"
## The sandbox dummies (staffs B7; actors since G6). The training dummy (an actor with Health, a
## Hurtbox and its DummyLook, no controller) never dies or moves and shows damage numbers, damage
## per second over the last 5 s, its statuses and reactions; the shooting dummy (an actor driven by
## its AIController) stands still and fires slow, telegraphed shots at the nearest wizard (its
## staff: `slow · bolt`). Uses the real Combat, Events, Projectiles, Spells and Actors autoloads;
## time moves through the actor's step().

const TrainingData := preload("res://content/enemies/training_dummy/training_dummy.tres")
const ShootingData := preload("res://content/enemies/shooting_dummy/shooting_dummy.tres")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")

var combat: Node
var events: Node
var projectiles: Node


func before_each() -> void:
	combat = root.get_node("Combat")
	events = root.get_node("Events")
	projectiles = root.get_node("Projectiles")
	projectiles.call("clear")


func after_each() -> void:
	projectiles.call("clear")


func _training() -> Actor:
	var dummy := TrainingData.scene.instantiate() as Actor
	dummy.data = TrainingData
	dummy.position = Vector2(100.0, 100.0)
	root.add_child(own(dummy))
	dummy.set_physics_process(false)
	return dummy


## The seconds Feel's local stop still holds `dummy` for (a hit just landed on it).
func _held_seconds(dummy: Actor) -> float:
	return (root.get_node("Actors") as Node).call("held_left", dummy.id) as float


## What the training dummy shows.
func _look(dummy: Actor) -> DummyLook:
	return dummy.get_node("DummyLook") as DummyLook


func test_the_data_names_its_scene() -> void:
	check_equal(TrainingData.id, &"training_dummy", "training dummy id")
	check_equal(ShootingData.id, &"shooting_dummy", "shooting dummy id")
	check(TrainingData.demo and ShootingData.demo, "both are demo content, so the web preview has them")
	check(ShootingData.move_speed == 0.0, "the shooting dummy does not walk")


func test_the_training_dummy_never_dies() -> void:
	var dummy := _training()
	for i in 50:
		combat.call("hit", 0, dummy, 100000)
	check(combat.call("is_registered", dummy) as bool, "still a target after 5 million damage")
	check(is_instance_valid(dummy) and not dummy.is_queued_for_deletion(), "still standing")


func test_it_never_moves() -> void:
	var dummy := _training()
	combat.call("hit", 0, dummy, 5, Vector2.RIGHT, 400.0)
	events.emit_signal("target_move_requested", 0, dummy, Vector2(300.0, 300.0))
	events.emit_signal("pull_requested", 0, Vector2(140.0, 100.0), 80.0, 300.0, 0, Vector2(140.0, 100.0))
	dummy.step(0.5)
	check_equal(dummy.position, Vector2(100.0, 100.0), "knockback, a swap and a pull leave it where it is")


func test_damage_numbers_show_each_hit() -> void:
	var dummy := _training()
	combat.call("hit", 0, dummy, 12)
	combat.call("hit", 1, dummy, 7)
	check_equal(_look(dummy).shown_numbers(), PackedStringArray(["12", "7"]), "a number per hit")
	dummy.step(DummyLook.NUMBER_TIME + 0.05)
	check_equal(_look(dummy).shown_numbers().size(), 0, "numbers fade out")
	for i in DummyLook.NUMBER_COUNT + 3:
		combat.call("hit", 0, dummy, 1)
	check_equal(_look(dummy).shown_numbers().size(), DummyLook.NUMBER_COUNT, "the pool reuses the oldest label")


func test_dps_covers_the_last_five_seconds() -> void:
	var dummy := _training()
	# 10 damage every half second for 5 seconds: 20 per second.
	for i in 10:
		combat.call("hit", 0, dummy, 10)
		dummy.step(0.5)
	check(absf(_look(dummy).dps() - 20.0) < 2.5, "steady 20 a second reads about 20, got %s" % _look(dummy).dps())
	check_equal(_look(dummy).total_damage, 100, "the total")
	dummy.step(DummyLook.DPS_WINDOW + 0.5)
	check_equal(_look(dummy).dps(), 0.0, "five quiet seconds bring it back to 0")


func test_a_short_burst_is_not_watered_down() -> void:
	var dummy := _training()
	combat.call("hit", 0, dummy, 30)
	# Feel holds a body in a hit for a few hundredths of a second (a local stop): it runs the rest.
	dummy.step(1.0 + _held_seconds(dummy))
	check(absf(_look(dummy).dps() - 30.0) < 0.5, "30 in the first second reads 30, not 6, got %s" % _look(dummy).dps())


func test_burn_ticks_count() -> void:
	var dummy := _training()
	combat.call("apply_status", 0, dummy, &"burn", 2.0, 10.0)
	for i in 20:
		combat.call("step", 0.1)
		dummy.step(0.1)
	check(_look(dummy).total_damage > 0, "burn damage, which sends no damage_dealt, reaches the total")


func test_statuses_and_reactions_show() -> void:
	var dummy := _training()
	combat.call("apply_status", 0, dummy, &"chill", 2.0, 30.0)
	check(_look(dummy).status_text().contains("Chill"), "a status is named, got '%s'" % _look(dummy).status_text())
	events.emit_signal("reaction_triggered", 0, &"shatter", dummy.position + dummy.body_offset)
	check(_look(dummy).status_text().contains("Shatter!"), "a reaction on it is named")
	events.emit_signal("reaction_triggered", 0, &"thaw", Vector2(400.0, 400.0))
	check(not _look(dummy).status_text().contains("Thaw"), "a reaction elsewhere is not")
	dummy.step(DummyLook.REACTION_TIME + 0.1 + _held_seconds(dummy))
	check(not _look(dummy).status_text().contains("Shatter"), "the reaction's name goes after a while")


func test_the_shooting_dummy_fires_slow_telegraphed_shots_at_the_nearest_wizard() -> void:
	var dummy := ShootingData.scene.instantiate() as Actor
	dummy.data = ShootingData
	dummy.position = Vector2(100.0, 100.0)
	# Two wizards as the projectile manager knows them: hurt circles on the wizards' layer.
	var near := own(Node2D.new()) as Node2D
	near.position = Vector2(100.0, 300.0)
	var far := own(Node2D.new()) as Node2D
	far.position = Vector2(350.0, 100.0)
	for wizard: Node2D in [near, far]:
		root.add_child(wizard)
		projectiles.call("add_target", wizard, 8.0, ProjectileManagerScript.LAYER_PLAYER)
	root.add_child(own(dummy))
	dummy.set_physics_process(false)
	var ai := dummy.get_node("AIController") as AIController
	dummy.step(0.05)
	check(ai.is_telegraphing(), "a wizard 200 px away is in range: the telegraph shows")
	check(dummy.aim.is_equal_approx(Vector2.DOWN), "it aims at the nearest wizard")
	check(ai.windup_time >= 1.0, "the telegraph is long (%s s)" % ai.windup_time)
	dummy.step(ai.windup_time)
	check_equal(projectiles.call("get_count") as int, 1, "the shot flies")
	var speed: float = (projectiles.call("get_velocity_of", 0) as Vector2).length()
	check(speed > 0.0 and speed <= 80.0, "its staff's shot (slow · bolt) is slow (%.1f px/s)" % speed)
	check_equal(dummy.velocity, Vector2.ZERO, "it never walks")
