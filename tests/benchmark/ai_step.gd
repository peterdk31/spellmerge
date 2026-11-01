extends SceneTree
## Times the enemy AI's step (enemy AI L1, docs/milestones/M2-enemy-ai.md, "What is left"): 200
## staffed strays (the imp, the Splinter, the Rime Crook, the Bone Scepter and the Storm Fork in
## turn, each with its own data and profile) round four wizards in the AI fixture, none of them ever going down,
## (tests/gameplay/ai/ai_fixture.gd), and prints `BENCH:` lines with the median and the p95 of one
## pass of `Actor.step` over the whole crowd per physics step. The wizards walk in circles and cast a bolt at the crowd every few steps, so the enemies' dodging and leading have
## shots and moving targets to read. Nothing is random but the AI's own seeded numbers.
##
## godot --headless --path . --script res://tests/benchmark/ai_step.gd [-- --enemies=N --steps=N]

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")

const DT: float = 0.0625
const WARMUP: int = 60
const STEPS: int = 400
const ENEMIES: int = 200
## Every this many steps each wizard casts a bolt at the enemy nearest the middle.
const CAST_EVERY: int = 4
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
		var caster: Caster = _caster(wizard)
		if caster != null:
			caster.set_staff(0, [&"bolt"] as Array[StringName])
	for index in count:
		var angle: float = TAU * float(index) / float(count)
		var ring: float = 140.0 + 60.0 * float(index % 4)
		var data: EnemyBase = kinds[index % kinds.size()]
		var body: Actor = data.scene.instantiate() as Actor
		body.data = data
		body.position = Vector2.from_angle(angle) * ring
		world.wire(body)
		# Each stray plays by its own data's profile, not the fixture's exact one.
		var mind: Node = Fixture.ai(body)
		if mind != null:
			mind.set("profile", null)
		root.add_child(body)
		body.set_physics_process(false)
		# The crowd stays whole: shots still hit, nobody goes down.
		body.health.protect(1.0e9)
		world.enemies.append(body)
	var samples: PackedInt64Array = PackedInt64Array()
	for step in WARMUP + steps:
		_move_wizards(world, step)
		var start: int = Time.get_ticks_usec()
		for body in world.enemies:
			if is_instance_valid(body) and body.is_inside_tree():
				body.step(DT)
		var spent: int = Time.get_ticks_usec() - start
		for body in world.enemies:
			if is_instance_valid(body):
				body.position += body.velocity * DT
		world.combat.step(DT)
		world.projectiles.step(DT)
		world.spells.call("step", DT)
		# The team board (staggered fire, spreading, the call), on the fixture since L2-L4.
		var board: Variant = world.get("board")
		if board != null:
			board.step(DT)
		if step >= WARMUP:
			samples.append(spent)
	samples.sort()
	var median: float = float(samples[samples.size() / 2]) / 1000.0
	var p95: float = float(samples[mini(samples.size() - 1, int(samples.size() * 0.95))]) / 1000.0
	var mean: float = 0.0
	for value in samples:
		mean += float(value)
	mean /= float(samples.size()) * 1000.0
	var standing: int = 0
	for body in world.enemies:
		if is_instance_valid(body) and body.is_inside_tree() and not body.is_dying():
			standing += 1
	print("BENCH: ai step, %d staffed strays (%d standing at the end), 4 wizards, %d steps: median %.3f ms, mean %.3f ms, p95 %.3f ms per pass (%.1f us an enemy)" % [count, standing, steps, median, mean, p95, median * 1000.0 / float(count)])
	world.free_all()
	quit(0)


## The wizards walk in circles round the middle and now and then cast a bolt outward.
func _move_wizards(world: Fixture, step: int) -> void:
	for index in world.players.size():
		var wizard: Actor = world.players[index]
		var angle: float = float(step) * 0.05 + TAU * float(index) / 4.0
		var next: Vector2 = Vector2.from_angle(angle) * 50.0
		wizard.velocity = (next - wizard.position) / DT
		wizard.position = next
		var caster: Caster = _caster(wizard)
		if caster == null:
			continue
		caster.step(DT)
		if step % CAST_EVERY == index % CAST_EVERY:
			wizard.aim = Vector2.from_angle(float(step) * 0.37 + float(index))
			caster.set_mana(0, 1000.0)
			caster.cast(0)


func _caster(body: Actor) -> Caster:
	for child in body.get_children():
		if child is Caster:
			return child as Caster
	return null
