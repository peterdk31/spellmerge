extends "res://tests/support/suite.gd"
## The swarm's look (horde swarm S2, docs/milestones/horde-swarm.md, "The idea"): a swarmer looks
## exactly like a full enemy of its kind. A full `crypt_mite` (and `bone_husk`) actor and the same
## kind drawn by SwarmLook (fed by a stand-in swarm with the actor's own places, velocities, aims and
## face seed) play the same scripted seconds (walk, stop, turn, a hit, a blink, a hit-stop hold), and
## at every step what SwarmLook puts in its row (the hop, Feel's squash and flash, the hurt pose, the
## eye and brow frames and where both layers sit) is what CreatureLook, the Face and Feel set on the
## actor's nodes. The pixels are compared by tests/screenshots/shot_swarm_parity.gd. Rows keep their
## look through the swarm's swap-remove; the batches hold one instance per row of each kind.
##
## godot --headless --path . --script res://tests/gameplay/horde/test_swarm_look.gd

const AiFixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const ActorFixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const FakeSwarm := preload("res://tests/gameplay/horde/fixtures/fake_swarm.gd")
const MiteData: EnemyBase = preload("res://content/enemies/crypt_mite/crypt_mite.tres")
const HuskData: EnemyBase = preload("res://content/enemies/bone_husk/bone_husk.tres")
## The game's physics step.
const STEP: float = 1.0 / 60.0
## The most steps a scripted run takes (it ends sooner once both a hit and a blink were seen).
const MOST_STEPS: int = 60 * 8
## Rows for the cost measure, and the most the look may take per physics step for them (ms; a
## loose bound so a loaded machine passes, the measure is printed).
const COST_ROWS: int = 1000
const COST_BOUND_MS: float = 12.0

var _world: AiFixture
var _feel: Node


func before_each() -> void:
	_world = AiFixture.new(root)
	_feel = root.get_node_or_null("Feel")


func after_each() -> void:
	_world.free_all()


## A look drawing `swarm`, stepped by hand.
func _look_of(swarm: FakeSwarm) -> SwarmLook:
	var look: SwarmLook = own(SwarmLook.new()) as SwarmLook
	look.real_time = false
	look.feel = _feel
	look.setup(swarm)
	swarm.look = look
	root.add_child(look)
	return look


## A full enemy of `data`, driven by a scripted controller instead of its AI.
func _full(data: EnemyBase, at: Vector2) -> Array:
	var body: Actor = _world.enemy(data.scene, data, at)
	var script := own(ActorFixture.Scripted.new()) as ActorFixture.Scripted
	body.drive(script)
	return [body, script]


## What differs between the full actor's nodes and the look's row now ("" when nothing does).
func _differences(body: Actor, rest_offset: Vector2, look: SwarmLook, row: int) -> String:
	var sprite := body.get_node(^"Sprite") as Sprite2D
	var face: Face = null
	var creature: CreatureLook = AiFixture.look(body)
	for child in body.get_children():
		if child is Face:
			face = child as Face
	var eyes := face.get_child(0) as Sprite2D
	var brows := face.get_child(1) as Sprite2D
	var shown: Dictionary = look.row_look(row)
	var flashing: bool = sprite.material != null and sprite.material == _feel.get(&"_flash_material")
	var found: PackedStringArray = PackedStringArray()
	if sprite.offset - rest_offset != shown["lift"]:
		found.append("hop %s / %s" % [sprite.offset - rest_offset, shown["lift"]])
	if not sprite.scale.is_equal_approx(shown["scale"]):
		found.append("squash %s / %s" % [sprite.scale, shown["scale"]])
	if flashing != shown["flash"]:
		found.append("flash %s / %s" % [flashing, shown["flash"]])
	if (creature.is_hurt() and creature.hurt_texture != null) != shown["hurt"]:
		found.append("hurt pose %s / %s" % [creature.is_hurt(), shown["hurt"]])
	if face.eyes_frame() != shown["eyes_frame"]:
		found.append("eyes %s / %s" % [face.eyes_frame(), shown["eyes_frame"]])
	if face.brows_frame() != shown["brows_frame"]:
		found.append("brows %s / %s" % [face.brows_frame(), shown["brows_frame"]])
	if eyes.position != shown["eyes_at"]:
		found.append("eyes at %s / %s" % [eyes.position, shown["eyes_at"]])
	if brows.position != shown["brows_at"]:
		found.append("brows at %s / %s" % [brows.position, shown["brows_at"]])
	return ", ".join(found)


## The scripted run of `data`: a full actor and a swarm row of its kind side by side, the same
## walk, stops, turns, hits, a hold and the blinks, compared at every step.
func _play_side_by_side(data: EnemyBase) -> void:
	var made: Array = _full(data, Vector2(200.0, 200.0))
	var body: Actor = made[0]
	var script: ActorFixture.Scripted = made[1]
	var rest_offset: Vector2 = (body.get_node(^"Sprite") as Sprite2D).offset
	var face_seed: int = hash(body.get_instance_id())
	var swarm := FakeSwarm.new()
	var row: int = swarm.add(swarm.kind_of(data.scene), body.position, face_seed)
	var look: SwarmLook = _look_of(swarm)
	var hits: int = 0
	var blinks: int = 0
	var holds: int = 0
	var walked: int = 0
	var stood: int = 0
	var flashed: int = 0
	var steps: int = 0
	for i in MOST_STEPS:
		steps = i
		# The script: walk right, stop and look up-left, walk down, stand looking left; a hit at
		# 0.7 s and at 1.6 s, a hit-stop hold of 0.1 s at 1.2 s.
		var second: float = float(i) * STEP
		if second < 0.5:
			script.move = Vector2.RIGHT
			script.aim = Vector2.RIGHT
		elif second < 1.0:
			script.move = Vector2.ZERO
			script.aim = Vector2(-1.0, -1.0).normalized()
		elif second < 1.5:
			script.move = Vector2.DOWN
			script.aim = Vector2(0.2, 1.0).normalized()
		else:
			script.move = Vector2.ZERO
			script.aim = Vector2.LEFT
		if i == 72:
			_world.actors.hold(body.id, 0.1)
		# The full actor steps (its looks last), then the row is given what the swarm would give:
		# its place before the move, its velocity and aim, the seconds it ran.
		var held: float = _world.actors.held_left(body.id)
		body.step(STEP)
		swarm.positions[row] = body.position
		swarm.velocities[row] = body.velocity
		swarm.aims[row] = body.aim
		swarm.ran[row] = STEP - minf(held, STEP)
		look.step(STEP)
		holds += 1 if held > 0.0 else 0
		body.position += body.velocity * STEP
		swarm.positions[row] = body.position
		if i == 42 or i == 96:
			body.damaged.emit(0, 1)
			_feel.call(&"_react", body)
			look.on_hit(row)
			hits += 1
		_feel.call(&"_step_reactions", STEP)
		look.step_feel(STEP)
		var differences: String = _differences(body, rest_offset, look, row)
		if differences != "":
			check(false, "%s at step %d (%.3f s), full / swarm: %s" % [data.id, i, second, differences])
			return
		var shown: Dictionary = look.row_look(row)
		blinks += 1 if shown["shut"] else 0
		flashed += 1 if shown["flash"] else 0
		walked += 1 if (shown["lift"] as Vector2).y < -1.0 else 0
		stood += 1 if body.velocity.is_zero_approx() else 0
		if hits == 2 and blinks > 0 and second > 2.0:
			break
	check(walked > 0 and stood > 0, "%s walked (hopped higher than the bob) and stood" % data.id)
	check(flashed > 0 and hits == 2, "%s was hit and flashed" % data.id)
	check(holds > 0, "%s was held by a hit-stop" % data.id)
	check(blinks > 0, "%s blinked within %d steps (seed %d)" % [data.id, steps, face_seed])


func test_a_swarm_crypt_mite_looks_like_a_full_one_at_every_step() -> void:
	_play_side_by_side(MiteData)


func test_a_swarm_bone_husk_looks_like_a_full_one_at_every_step() -> void:
	_play_side_by_side(HuskData)


## Two rows stepped together; the first goes (the swarm swap-removes it) and the second, now in row
## 0, goes on exactly as a look that only ever had it.
func test_a_row_keeps_its_look_through_the_swarms_swap_remove() -> void:
	var swarm := FakeSwarm.new()
	var kind: int = swarm.kind_of(MiteData.scene)
	swarm.add(kind, Vector2(10.0, 10.0), 11)
	swarm.add(kind, Vector2(50.0, 10.0), 22)
	var look: SwarmLook = _look_of(swarm)
	var alone := FakeSwarm.new()
	alone.add(alone.kind_of(MiteData.scene), Vector2(50.0, 10.0), 22)
	var reference: SwarmLook = _look_of(alone)
	for i in 240:
		var walking: bool = (i / 30) % 2 == 0
		var row: int = 1 if i < 100 else 0
		swarm.velocities[row] = Vector2(40.0, 10.0) if walking else Vector2.ZERO
		alone.velocities[0] = swarm.velocities[row]
		swarm.aims[row] = Vector2.UP if walking else Vector2.LEFT
		alone.aims[0] = swarm.aims[row]
		swarm.run_all(STEP)
		alone.run_all(STEP)
		look.step(STEP)
		reference.step(STEP)
		swarm.move(STEP)
		alone.move(STEP)
		if i == 95:
			look.on_hit(row)
			reference.on_hit(0)
		look.step_feel(STEP)
		reference.step_feel(STEP)
		if i == 99:
			swarm.remove(0)
			check_equal(look.row_count(), 1, "the look drops a row with the swarm")
		if look.row_look(row if i < 99 else 0) != reference.row_look(0):
			check(false, "step %d: the row's look %s, alone %s" % [i, look.row_look(row if i < 99 else 0), reference.row_look(0)])
			return


## Each kind is one batch with an instance per row: at the row's place, its face layers where the
## row says, white while it flashes.
func test_the_batches_hold_an_instance_per_row_of_each_kind() -> void:
	var swarm := FakeSwarm.new()
	var mite: int = swarm.kind_of(MiteData.scene)
	var husk: int = swarm.kind_of(HuskData.scene)
	swarm.add(mite, Vector2(10.0, 20.0), 1)
	swarm.add(husk, Vector2(30.0, 40.0), 2)
	swarm.add(mite, Vector2(50.0, 60.0), 3)
	var look: SwarmLook = _look_of(swarm)
	swarm.run_all(STEP)
	look.step(STEP)
	look.on_hit(2)
	look.step_feel(STEP)
	check_equal(look.batch(mite).multimesh.visible_instance_count, 2, "two mites in the mites' batch")
	check_equal(look.batch(husk).multimesh.visible_instance_count, 1, "one husk in the husks'")
	# The buffer as written (the headless renderer keeps no instance data to read back).
	var second: PackedFloat32Array = look.instance_data(mite, 1)
	check_equal(Vector2(second[3], second[7]), Vector2(50.0, 60.0), "the second mite (row 2) at its place")
	var shown: Dictionary = look.row_look(2)
	check_equal(Vector2(second[12], second[13]), shown["eyes_at"], "its eye layer where the row says")
	check_equal(Vector2(second[14], second[15]), shown["brows_at"], "its brow layer too")
	check_equal(int(second[10]), (shown["eyes_frame"] as Vector2i).x, "its eye column")
	check(second[11] >= SwarmLook.FLAG_FLASH, "it is drawn white: it was hit")
	check(look.instance_data(mite, 0)[11] < SwarmLook.FLAG_FLASH, "the other mite is not")
	check_equal(Vector2(look.instance_data(husk, 0)[3], look.instance_data(husk, 0)[7]), Vector2(30.0, 40.0), "the husk (row 1) is the first of its batch")
	var full_husk: Node = own(HuskData.scene.instantiate()) as Node
	check_equal(look.batch(husk).texture, (full_husk.get_node(^"Sprite") as Sprite2D).texture, "the husk's batch draws the husk's body")


## Feel's numbers are read from its live preset: a longer flash there is a longer flash here.
func test_the_flash_follows_feels_preset() -> void:
	var preset: Resource = (_feel.get(&"preset") as Resource).duplicate()
	preset.set(&"flash_seconds", 0.5)
	var swarm := FakeSwarm.new()
	swarm.add(swarm.kind_of(MiteData.scene), Vector2.ZERO, 1)
	var look: SwarmLook = _look_of(swarm)
	var before: Resource = _feel.get(&"preset") as Resource
	_feel.set(&"preset", preset)
	look.on_hit(0)
	_feel.set(&"preset", before)
	for i in 20:
		look.step_feel(STEP)
	check(look.row_look(0)["flash"], "still white after 20 steps of a 0.5 s flash")
	for i in 20:
		look.step_feel(STEP)
	check(not look.row_look(0)["flash"], "and done after 0.5 s")
	check_equal(look.row_look(0)["scale"], Vector2.ONE, "back to its rest scale")


## The look's cost per physics step (its step, then Feel's part and the batches) at COST_ROWS rows of
## two kinds, walking, standing, some flashing; printed for the stress runs.
func test_the_look_stays_cheap_at_a_thousand_rows() -> void:
	var swarm := FakeSwarm.new()
	var mite: int = swarm.kind_of(MiteData.scene)
	var husk: int = swarm.kind_of(HuskData.scene)
	for i in COST_ROWS:
		swarm.add(mite if i % 3 != 0 else husk, Vector2(float(i % 40) * 16.0, float(i / 40) * 16.0), i)
	var look: SwarmLook = _look_of(swarm)
	for row in COST_ROWS:
		swarm.velocities[row] = Vector2(30.0, 0.0) if row % 2 == 0 else Vector2.ZERO
		swarm.aims[row] = Vector2.from_angle(float(row))
	swarm.run_all(STEP)
	for i in 30:
		look.step(STEP)
		look.step_feel(STEP)
	var steps: int = 120
	var step_usec: int = 0
	var draw_usec: int = 0
	for i in steps:
		if i % 4 == 0:
			look.on_hit((i * 37) % COST_ROWS)
		var start: int = Time.get_ticks_usec()
		look.step(STEP)
		var middle: int = Time.get_ticks_usec()
		look.step_feel(STEP)
		draw_usec += Time.get_ticks_usec() - middle
		step_usec += middle - start
		swarm.move(STEP)
	var step_ms: float = float(step_usec) / float(steps) / 1000.0
	var draw_ms: float = float(draw_usec) / float(steps) / 1000.0
	print("SwarmLook at %d rows: step %.3f ms, Feel's part and the batches %.3f ms, %.3f ms in all per frame" % [COST_ROWS, step_ms, draw_ms, step_ms + draw_ms])
	check(step_ms + draw_ms < COST_BOUND_MS, "the look takes %.3f ms a frame at %d rows" % [step_ms + draw_ms, COST_ROWS])
