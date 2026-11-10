extends "res://tests/support/suite.gd"
## Asleep bodies in the real game (props W2, docs/milestones/props.md): stand-in props (the W1
## benchmark's, `tests/benchmark/prop_stand_in.tscn`: Health, a Hurtbox and a Caster of two
## `fire` + `blast` staffs, no controller, no Mover) stand in the hub and blow each other up on a
## fixed schedule: blasts, burns, hit-stop holds, deaths, a fuse winding, a body moved by hand. The
## same game is played with asleep bodies skipped and with them stepped (`Tick.sleep_bodies`), and
## every tick's state hash must be the same: sleeping never changes the game. The suite's
## `Tick.verify_sleep` checks each asleep body every tick too.
##
## godot --headless --path . --script res://tests/gameplay/actor/test_sleep_in_game.gd

const BotScript := preload("res://tests/bots/bot.gd")
const TickScript := preload("res://core/sim/tick.gd")
const StandIn: EnemyBase = preload("res://tests/benchmark/prop_stand_in.tres")

const COUNT: int = 30
## The run's seed, and the tick the stand-ins come in at.
const SEED: int = 7311
const START_TICK: int = 300
const TICKS: int = 480
const WAIT_FRAMES: int = 600
## When a stand-in casts: [tick, stand-in, staff] (staff 0 winds a one-second fuse, 1 blows now).
const CASTS: Array[Vector3i] = [
	Vector3i(60, 3, 1), Vector3i(90, 12, 0), Vector3i(150, 20, 1), Vector3i(240, 5, 0),
	Vector3i(300, 26, 1), Vector3i(330, 14, 1), Vector3i(400, 8, 0),
]
## The tick a stand-in is moved by hand (a move from outside wakes it), and which.
const MOVE_AT: int = 200
const MOVED: int = 17


func after_each() -> void:
	TickScript.sleep_bodies = true


func test_asleep_bodies_play_the_same_game_as_stepped_ones() -> void:
	var asleep: Dictionary = await _play(true)
	var stepped: Dictionary = await _play(false)
	check(not asleep.is_empty() and not stepped.is_empty(), "both games were played")
	if asleep.is_empty() or stepped.is_empty():
		return
	check(int(asleep["most_asleep"]) >= COUNT - 2, "nearly every stand-in slept at some point (%d)" % asleep["most_asleep"])
	check(int(asleep["hurt"]) > 0, "the blasts hurt stand-ins (%d)" % asleep["hurt"])
	check_equal(stepped["most_asleep"], 0, "with sleeping off, none is skipped")
	var a: Array = asleep["hashes"]
	var b: Array = stepped["hashes"]
	check_equal(a.size(), b.size(), "as many ticks")
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			check(false, "the games part at tick %d" % i)
			break


## The hub with the stand-ins, played for TICKS ticks with asleep bodies skipped (`sleeping`) or
## stepped, both recorded at SEED from START_TICK on: each tick's hash of every area and body, the
## most stand-ins
## asleep at once (counted as skipped: asleep while sleeping is on), and how many were hurt.
func _play(sleeping: bool) -> Dictionary:
	TickScript.sleep_bodies = sleeping
	var tick: TickScript = root.get_node_or_null(^"Tick") as TickScript
	var flow: Node = root.get_node_or_null(^"Flow")
	var events: Node = root.get_node_or_null(^"Events")
	var input: Node = root.get_node_or_null(^"PlayerInput")
	var frames: Node = root.get_node_or_null(^"Frames")
	if tick == null or flow == null or events == null or input == null or frames == null:
		check(false, "the game's autoloads are missing")
		return {}
	var bot := BotScript.new()
	if not bot.join(0, BotScript.Mode.IDLER, input, flow):
		check(false, "the bot could not join")
		return {}
	# Recorded at a fixed seed, so both games roll the same dice (the dummies' AI).
	frames.call("record", &"hub_requested", 0, SEED)
	var waited: int = 0
	while flow.get("world") == null or flow.call("get_wizard", 0) == null:
		waited += 1
		if waited > WAIT_FRAMES:
			check(false, "the hub did not start")
			bot.leave()
			return {}
		await physics_frame
	tick.set_physics_process(false)
	# Both games from the same tick: the hub's loading took its own number of frames.
	if tick.count > START_TICK:
		check(false, "the hub took %d ticks to start, more than %d" % [tick.count, START_TICK])
	while tick.count < START_TICK:
		tick.run(TickScript.DT)
	var world := flow.get("world") as Node2D
	var wizard := flow.call("get_wizard", 0) as Node2D
	var props: Array[Actor] = []
	for i in COUNT:
		var body := StandIn.scene.instantiate() as Actor
		body.data = StandIn
		body.position = wizard.global_position + Vector2(-60.0 + 20.0 * float(i % 6), 90.0 + 18.0 * float(i / 6))
		world.add_child(body)
		props.append(body)
	var hashes: Array[int] = []
	var most_asleep: int = 0
	for t in TICKS:
		for cast: Vector3i in CASTS:
			if cast.x == t and is_instance_valid(props[cast.y]):
				props[cast.y].caster.cast(cast.z)
		if t == MOVE_AT and is_instance_valid(props[MOVED]):
			props[MOVED].position += Vector2(6.0, 0.0)
		tick.run(TickScript.DT)
		hashes.append(SimHash.whole(SimHash.areas(tick.state_areas())))
		if sleeping:
			var now: int = 0
			for body in props:
				if is_instance_valid(body) and body.actors.asleep[body.id] != 0:
					now += 1
			most_asleep = maxi(most_asleep, now)
	var hurt: int = 0
	for body in props:
		if not is_instance_valid(body) or body.health.health < body.health.max_health:
			hurt += 1
	for body in props:
		if is_instance_valid(body):
			body.free()
	tick.set_physics_process(true)
	frames.call("stop_recording")
	bot.leave()
	flow.call("stop_run")
	await physics_frame
	return {"hashes": hashes, "most_asleep": most_asleep, "hurt": hurt}
