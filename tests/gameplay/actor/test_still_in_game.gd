extends "res://tests/support/suite.gd"
## Still bodies in the real game (props W2, docs/milestones/props.md): stand-in props (the W1
## benchmark's, `tests/benchmark/prop_stand_in.tscn`: Health, a Hurtbox and a Caster of two
## `fire` + `blast` staffs, no controller, no Mover) in the hub. The Tick never steps a still one,
## a blast still lands on its neighbours, and one given a driver is stepped until it is let go.
##
## godot --headless --path . --script res://tests/gameplay/actor/test_still_in_game.gd

const BotScript := preload("res://tests/bots/bot.gd")
const TickScript := preload("res://core/sim/tick.gd")
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const StandIn: EnemyBase = preload("res://tests/benchmark/prop_stand_in.tres")

const WAIT_FRAMES: int = 600
## The staff that blows at once (no wind-up).
const BLAST_NOW: int = 1


func test_the_tick_skips_still_props_and_steps_a_driven_one() -> void:
	var tick: TickScript = root.get_node_or_null(^"Tick") as TickScript
	var flow: Node = root.get_node_or_null(^"Flow")
	var events: Node = root.get_node_or_null(^"Events")
	var input: Node = root.get_node_or_null(^"PlayerInput")
	if tick == null or flow == null or events == null or input == null:
		check(false, "the game's autoloads are missing")
		return
	var bot := BotScript.new()
	check(bot.join(0, BotScript.Mode.IDLER, input, flow), "the bot joins")
	events.emit_signal("hub_requested", 0)
	var waited: int = 0
	while flow.get("world") == null or flow.call("get_wizard", 0) == null:
		waited += 1
		if waited > WAIT_FRAMES:
			check(false, "the hub did not start")
			bot.leave()
			return
		await physics_frame
	tick.set_physics_process(false)
	var world := flow.get("world") as Node2D
	var wizard := flow.call("get_wizard", 0) as Node2D
	var props: Array[Actor] = []
	for i in 3:
		var body := StandIn.scene.instantiate() as Actor
		body.data = StandIn
		body.position = wizard.global_position + Vector2(-20.0 + 20.0 * float(i), 100.0)
		world.add_child(body)
		props.append(body)
	for i in 3:
		tick.run(TickScript.DT)
	for body in props:
		check(body.actors.is_still(body.id), "a stand-in is still")

	# A move by hand is never sent to the systems: its Caster's step, which would send it, never runs.
	var moved: Actor = props[2]
	var sent: Vector2 = moved.caster.get(&"_placed_feet")
	moved.position += Vector2(4.0, 0.0)
	for i in 3:
		tick.run(TickScript.DT)
	check_equal(moved.caster.get(&"_placed_feet"), sent, "the Tick did not step it")

	# A blast still lands: Combat hurts its neighbours, stepped or not.
	check(props[1].caster.cast(BLAST_NOW), "the middle one blows")
	for i in 10:
		tick.run(TickScript.DT)
	check(not is_instance_valid(props[0]) or props[0].health.health < props[0].health.max_health, "its neighbour is hurt")

	# Driven, it is stepped (its place is sent); let go, it is still again.
	var driver := Fixture.Scripted.new()
	moved.drive(driver)
	check(not moved.actors.is_still(moved.id), "driven: stepped")
	tick.run(TickScript.DT)
	check_equal(moved.caster.get(&"_placed_feet"), moved.global_position, "the Tick stepped it")
	moved.drive(null)
	driver.free()
	check(moved.actors.is_still(moved.id), "let go: still again")

	for body in props:
		if is_instance_valid(body):
			body.free()
	tick.set_physics_process(true)
	bot.leave()
	flow.call("stop_run")
	await physics_frame
