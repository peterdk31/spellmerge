extends "res://tests/support/suite.gd"
## The sandbox dummies (staffs B7). The training dummy never dies or moves and shows damage
## numbers, damage per second over the last 5 s, its statuses and reactions; the shooting dummy
## stands still and fires slow, telegraphed shots at the nearest wizard. Uses the real Combat,
## Events and Projectiles autoloads; time moves through step().

const TrainingData := preload("res://content/enemies/training_dummy/training_dummy.tres")
const ShootingData := preload("res://content/enemies/shooting_dummy/shooting_dummy.tres")
const TrainingScript := preload("res://content/enemies/training_dummy/training_dummy.gd")
const AiScript := preload("res://gameplay/ai/ai.gd")

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


func _training() -> TrainingScript:
	var dummy := TrainingData.scene.instantiate() as TrainingScript
	dummy.data = TrainingData
	dummy.position = Vector2(100.0, 100.0)
	root.add_child(own(dummy))
	return dummy


func test_the_data_names_its_scene() -> void:
	check_equal(TrainingData.id, &"training_dummy", "training dummy id")
	check_equal(ShootingData.id, &"shooting_dummy", "shooting dummy id")
	check(TrainingData.demo and ShootingData.demo, "both are demo content, so the web preview has them")
	check(ShootingData.move_speed == 0.0, "the shooting dummy does not walk")


func test_the_training_dummy_never_dies() -> void:
	var dummy := _training()
	for i in 50:
		combat.call("hit", 0, dummy, 100000)
	check(combat.call("is_enemy", dummy) as bool, "still a target after 5 million damage")
	check(is_instance_valid(dummy) and not dummy.is_queued_for_deletion(), "still standing")


func test_it_never_moves() -> void:
	var dummy := _training()
	combat.call("hit", 0, dummy, 5, Vector2.RIGHT, 400.0)
	events.emit_signal("target_move_requested", 0, dummy, Vector2(300.0, 300.0))
	events.emit_signal("pull_requested", 0, Vector2(140.0, 100.0), 80.0, 300.0, 0)
	dummy.step(0.5)
	check_equal(dummy.position, Vector2(100.0, 100.0), "knockback, a swap and a pull leave it where it is")


func test_damage_numbers_show_each_hit() -> void:
	var dummy := _training()
	combat.call("hit", 0, dummy, 12)
	combat.call("hit", 1, dummy, 7)
	check_equal(dummy.shown_numbers(), PackedStringArray(["12", "7"]), "a number per hit")
	dummy.step(TrainingScript.NUMBER_TIME + 0.05)
	check_equal(dummy.shown_numbers().size(), 0, "numbers fade out")
	for i in TrainingScript.NUMBER_COUNT + 3:
		combat.call("hit", 0, dummy, 1)
	check_equal(dummy.shown_numbers().size(), TrainingScript.NUMBER_COUNT, "the pool reuses the oldest label")


func test_dps_covers_the_last_five_seconds() -> void:
	var dummy := _training()
	# 10 damage every half second for 5 seconds: 20 per second.
	for i in 10:
		combat.call("hit", 0, dummy, 10)
		dummy.step(0.5)
	check(absf(dummy.dps() - 20.0) < 2.5, "steady 20 a second reads about 20, got %s" % dummy.dps())
	check_equal(dummy.total_damage, 100, "the total")
	dummy.step(TrainingScript.DPS_WINDOW + 0.5)
	check_equal(dummy.dps(), 0.0, "five quiet seconds bring it back to 0")


func test_a_short_burst_is_not_watered_down() -> void:
	var dummy := _training()
	combat.call("hit", 0, dummy, 30)
	dummy.step(1.0)
	check(absf(dummy.dps() - 30.0) < 0.5, "30 in the first second reads 30, not 6, got %s" % dummy.dps())


func test_burn_ticks_count() -> void:
	var dummy := _training()
	combat.call("apply_status", 0, dummy, &"burn", 2.0, 10.0)
	for i in 20:
		combat.call("step", 0.1)
		dummy.step(0.1)
	check(dummy.total_damage > 0, "burn damage, which sends no damage_dealt, reaches the total")


func test_statuses_and_reactions_show() -> void:
	var dummy := _training()
	combat.call("apply_status", 0, dummy, &"chill", 2.0, 30.0)
	check(dummy.status_text().contains("Chill"), "a status is named, got '%s'" % dummy.status_text())
	events.emit_signal("reaction_triggered", 0, &"shatter", dummy.position + TrainingScript.HURT_OFFSET)
	check(dummy.status_text().contains("Shatter!"), "a reaction on it is named")
	events.emit_signal("reaction_triggered", 0, &"thaw", Vector2(400.0, 400.0))
	check(not dummy.status_text().contains("Thaw"), "a reaction elsewhere is not")
	dummy.step(TrainingScript.REACTION_TIME + 0.1)
	check(not dummy.status_text().contains("Shatter"), "the reaction's name goes after a while")


func test_the_shooting_dummy_fires_slow_telegraphed_shots_at_the_nearest_wizard() -> void:
	var dummy := ShootingData.scene.instantiate() as AiScript
	dummy.data = ShootingData
	dummy.position = Vector2(100.0, 100.0)
	var near := own(Node2D.new()) as Node2D
	near.position = Vector2(100.0, 300.0)
	var far := own(Node2D.new()) as Node2D
	far.position = Vector2(350.0, 100.0)
	dummy.targets = [far, near]
	root.add_child(own(dummy))
	dummy.step(0.05)
	check(dummy.is_telegraphing(), "a wizard 200 px away is in range: the telegraph shows")
	check(dummy.aim.is_equal_approx(Vector2.DOWN), "it aims at the nearest wizard")
	check(dummy.windup_time >= 1.0, "the telegraph is long (%s s)" % dummy.windup_time)
	check(dummy.attack_speed <= 80.0, "the shot is slow (%s px/s)" % dummy.attack_speed)
	dummy.step(dummy.windup_time)
	check_equal(projectiles.call("get_count") as int, 1, "the shot flies")
	check_equal(dummy.velocity, Vector2.ZERO, "it never walks")
