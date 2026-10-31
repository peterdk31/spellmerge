extends SceneTree
## Times the swarm's step and its look (Horde swarm S4, docs/milestones/horde-swarm.md, "Parts")
## with 500 and 1,000 swarmers, apart from the rest of the game, and prints `BENCH:` lines: the
## swarm's whole `step` (its look's step inside it), the look's step alone, and the look's drawing
## (`step_feel`: Feel's flash and the batches' buffers). The world is the swarm tests' fixture
## (tests/gameplay/horde/swarm_fixture.gd: its own bus, actor table, projectile manager, Spells and
## Combat): four wizards standing round the middle of the stress room's enemy area, the swarmers
## (crypt mites and bone husks, every other one) spawned over it and chasing them, a wall in the
## way, and every step a few hits (with knockback, some of them frost, so chill and freeze slow
## swarmers), a local stop on a few of them (Feel's hit-stop), and a kill now and then.
##
## It also prints a fingerprint (`FINGERPRINT:`) of every row the swarm keeps and every value the
## look shows after the run, so two versions of the code can be compared: the fingerprints must
## match exactly. Nothing is random (the swarm's generator is seeded).
##
## godot --headless --path . --script res://tests/benchmark/swarm_step.gd [-- --steps=N]

const Fixture := preload("res://tests/gameplay/horde/swarm_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

const DT: float = 1.0 / 60.0
const WARMUP: int = 120
const STEPS: int = 300
const RUNS: Array[int] = [500, 1000]
## The stress room's enemy area (stress_runner.gd's ENEMY_AREA), round the fixture's origin.
const AREA: Rect2 = Rect2(-272.0, -132.0, 544.0, 264.0)
## Every step: this many hits, one in FROST_EVERY of them frost, a stop on HOLD_EVERY-th, a kill on
## the KILL_EVERY-th step.
const HITS_PER_STEP: int = 12
const FROST_EVERY: int = 3
const HOLD_EVERY: int = 4
const KILL_EVERY: int = 7


## The look, timed apart.
class TimedLook:
	extends SwarmLook
	var step_usec: PackedInt64Array = PackedInt64Array()
	var timing: bool = false

	func step(delta: float) -> void:
		var start: int = Time.get_ticks_usec()
		super.step(delta)
		if timing:
			step_usec.append(Time.get_ticks_usec() - start)


func _initialize() -> void:
	await process_frame
	var steps: int = STEPS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--steps="):
			steps = arg.trim_prefix("--steps=").to_int()
	for count in RUNS:
		_run(count, steps)
	quit(0)


func _run(count: int, steps: int) -> void:
	var run := Fixture.new(root)
	var look := TimedLook.new()
	look.real_time = false
	look.setup(run.swarm)
	run.horde.add_child(look)
	run.swarm.look = look
	for seat in 4:
		run.wizard(Vector2(-60.0 + 120.0 * float(seat % 2), -40.0 + 80.0 * float(seat / 2)), seat)
	run.wall(Rect2(-150.0, -20.0, 24.0, 90.0))
	# The wall grid is read when the swarm starts.
	run.swarm.start(run.horde, AREA)
	var frost: int = run.tag(run.wizards[0].id, &"frost")
	var plain: int = run.tag(run.wizards[1].id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in count:
		var at: Vector2 = AREA.position + Vector2(rng.randf() * AREA.size.x, rng.randf() * AREA.size.y)
		run.swarmer(at, Fixture.MiteData if i % 2 == 0 else Fixture.HuskData)
	var step_usec: PackedInt64Array = PackedInt64Array()
	var draw_usec: PackedInt64Array = PackedInt64Array()
	for n in WARMUP + steps:
		var timing: bool = n >= WARMUP
		_disturb(run, n, frost, plain)
		look.timing = timing
		var start: int = Time.get_ticks_usec()
		run.swarm.step(DT)
		var stepped: int = Time.get_ticks_usec()
		look.step_feel(DT)
		var drawn: int = Time.get_ticks_usec()
		run.combat.step(DT)
		run.projectiles.step(DT)
		run.spells.step(DT)
		if timing:
			step_usec.append(stepped - start)
			draw_usec.append(drawn - stepped)
		# Swarmers killed are made again, so the count holds.
		while run.swarm.count < count:
			run.swarmer(AREA.position + Vector2(rng.randf() * AREA.size.x, rng.randf() * AREA.size.y), Fixture.MiteData if run.swarm.count % 2 == 0 else Fixture.HuskData)
	var swarm_ms: float = _median(step_usec)
	var look_ms: float = _median(look.step_usec)
	print("BENCH: swarm step, %d swarmers (%d steps, medians): whole step %.3f ms (%.2f us a swarmer), of which its look's step %.3f ms; swarm without its look %.3f ms; look drawing %.3f ms" % [count, steps, swarm_ms, swarm_ms * 1000.0 / float(count), look_ms, swarm_ms - look_ms, _median(draw_usec)])
	print("FINGERPRINT: %d swarmers: %s" % [count, _fingerprint(run.swarm, look)])
	run.horde.remove_child(look)
	look.free()
	run.free_all()


## The scripted disturbances of step `n`: hits on rows picked by the step (knockback from the left;
## every FROST_EVERY-th a frost bolt), a local stop on some, and a kill now and then.
func _disturb(run: Fixture, n: int, frost: int, plain: int) -> void:
	var swarm: Swarm = run.swarm
	if swarm.count == 0:
		return
	for k in HITS_PER_STEP:
		var row: int = (n * 37 + k * 101) % swarm.count
		var node: Node2D = swarm.nodes[row]
		if k % FROST_EVERY == 0:
			run.bus.projectile_hit.emit(run.wizards[0].id, node, node.global_position + Vector2(-6.0, 0.0), frost, -1)
		else:
			run.combat.hit(run.wizards[1].id, node, 1, Vector2.RIGHT, 120.0)
		if k % HOLD_EVERY == 0:
			run.actors.hold(swarm.actor_ids[row], 0.05)
	if n % KILL_EVERY == 0:
		run.combat.hit(run.wizards[2].id, swarm.nodes[(n * 13) % swarm.count], 100000)


## A hash of every row and every value the look shows (see the class doc).
func _fingerprint(swarm: Swarm, look: SwarmLook) -> String:
	var parts: Array = []
	for row in swarm.count:
		parts.append([swarm.positions[row], swarm.velocities[row], swarm.aims[row], swarm.hurt_left[row], swarm.ran[row], swarm.kinds[row], swarm.seeds[row], look.row_look(row)])
	var kinds: Array = []
	for kind in swarm.kinds_list.size():
		var batch: MultiMeshInstance2D = look.batch(kind)
		kinds.append([batch.multimesh.visible_instance_count, look.instance_data(kind, 0), look.instance_data(kind, maxi(batch.multimesh.visible_instance_count - 1, 0))])
	return "%d rows, moved %d, hash %d, batches %d" % [swarm.count, swarm.moved, hash(var_to_str(parts)), hash(var_to_str(kinds))]


func _median(values: PackedInt64Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedInt64Array = values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2]) / 1000.0
