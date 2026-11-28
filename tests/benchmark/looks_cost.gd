extends SceneTree
## Times the bodies' looks a drawn frame (perf plan F4, docs/milestones/perf-plan.md): staffed strays
## (the imp, the Splinter, the Rime Crook, the Bone Scepter and the Storm Fork in turn) round four
## wizards in the AI fixture (tests/gameplay/ai/ai_fixture.gd), each tick stepped with its looks left
## for the frame (`Actor.tick_step` with `looks_later`), then the frame's looks pass the Tick runs
## (`Tick._process`, the looks over the actor table) timed. Prints `BENCH:` lines with the median, mean
## and p95 of one pass. Nothing is random but the AI's own seeded numbers.
##
## godot --headless --path . --script res://tests/benchmark/looks_cost.gd [-- --enemies=N --steps=N]

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const TickScript := preload("res://core/sim/tick.gd")

const DT: float = 1.0 / 60.0
const WARMUP: int = 60
const STEPS: int = 600
const ENEMIES: int = 48
const STRAYS: Array[String] = [
	"res://content/enemies/ember_imp/ember_imp.tres",
	"res://content/enemies/splinter/splinter.tres",
	"res://content/enemies/rime_crook/rime_crook.tres",
	"res://content/enemies/bone_scepter/bone_scepter.tres",
	"res://content/enemies/storm_fork/storm_fork.tres",
]


func _initialize() -> void:
	await process_frame
	var steps: int = STEPS
	var count: int = ENEMIES
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--steps="):
			steps = arg.trim_prefix("--steps=").to_int()
		elif arg.begins_with("--enemies="):
			count = arg.trim_prefix("--enemies=").to_int()
	var world := Fixture.new(root, 4)
	var kinds: Array[EnemyBase] = []
	for path in STRAYS:
		kinds.append(load(path) as EnemyBase)
	for index in 4:
		var wizard: Actor = world.players[index]
		wizard.position = Vector2(-60.0 + 40.0 * index, 0.0)
		wizard.health.protect(1.0e9)
		wizard.ticking = false
	for index in count:
		var angle: float = TAU * float(index) / float(count)
		var ring: float = 140.0 + 60.0 * float(index % 4)
		var data: EnemyBase = kinds[index % kinds.size()]
		var body: Actor = data.scene.instantiate() as Actor
		body.data = data
		body.position = Vector2.from_angle(angle) * ring
		world.wire(body)
		var mind: Node = Fixture.ai(body)
		if mind != null:
			mind.set("profile", null)
		root.add_child(body)
		body.ticking = false
		body.health.protect(1.0e9)
		world.enemies.append(body)
	# The camera on the crowd's middle, so most bodies are on screen and a few off it.
	var camera := Camera2D.new()
	root.add_child(camera)
	camera.make_current()
	# A Tick of its own over the fixture's table, in the tree (its screen is the root's) but
	# processing nothing by itself: only its frame's looks pass runs (`_process`), called here.
	var tick: TickScript = TickScript.new()
	tick.actors = world.actors
	root.add_child(tick)
	tick.set_process(false)
	tick.set_physics_process(false)
	var samples := PackedInt64Array()
	for step in WARMUP + steps:
		for index in world.players.size():
			var wizard: Actor = world.players[index]
			var next: Vector2 = Vector2.from_angle(float(step) * 0.05 + TAU * float(index) / 4.0) * 50.0
			wizard.velocity = (next - wizard.position) / DT
			wizard.position = next
			wizard.tick_step(DT, true)
		for body in world.enemies:
			if is_instance_valid(body) and body.is_inside_tree():
				body.tick_step(DT, true)
		world.combat.step(DT)
		world.projectiles.step(DT)
		world.spells.call("step", DT)
		world.board.step(DT)
		var start: int = Time.get_ticks_usec()
		tick._process(DT)
		var spent: int = Time.get_ticks_usec() - start
		if step >= WARMUP:
			samples.append(spent)
	samples.sort()
	var median: float = float(samples[samples.size() / 2]) / 1000.0
	var p95: float = float(samples[mini(samples.size() - 1, int(samples.size() * 0.95))]) / 1000.0
	var mean: float = 0.0
	for value in samples:
		mean += float(value)
	mean /= float(samples.size()) * 1000.0
	print("BENCH: looks a frame, %d strays and 4 wizards, %d frames: median %.3f ms, mean %.3f ms, p95 %.3f ms a pass" % [count, steps, median, mean, p95])
	tick.free()
	world.free_all()
	quit(0)
