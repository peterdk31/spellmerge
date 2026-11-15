extends "res://tests/support/suite.gd"
## Poses from states and layered bodies (boss plan OB8, docs/milestones/boss-old-broom.md, "Poses
## and layered bodies"): an enemy's look reads what its body does (`BodyPose`: transition, wall,
## hurt, wind-up, its own move, a cast, idle, the first that holds) and draws a layered body's parts
## (`BodyPart`) by it: leaning into the way it goes and swinging back past upright as it brakes,
## rearing back from its aim as it winds up, squashed and shaking at a wall, a drawn frame a pose,
## the face riding its part; a phase brings its parts' art and motes that follow the body. All of
## it is drawn only: a layered body moves exactly as a plain one. Bodies made here (the imp's scene
## with parts added), never a boss of the content (decision 28).
##
## godot --headless --path . --script res://tests/gameplay/ai/test_ai_poses.gd

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const ImpData: EnemyBase = preload("res://content/enemies/ember_imp/ember_imp.tres")
const STEP: float = 1.0 / 60.0
const Pose := BodyPose.Pose

var fx: Fixture


func before_each() -> void:
	fx = Fixture.new(root)
	# Far away: the bodies here never reach or see a wizard unless a test says so.
	fx.players[0].position = Vector2(5000.0, 5000.0)


func after_each() -> void:
	fx.free_all()


## A plain texture `size` across, `frames` frames wide.
func _art(size: Vector2i, frames: int = 1) -> Texture2D:
	var image := Image.create(size.x * frames, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color("7a7694"))
	return ImageTexture.create_from_image(image)


## The imp's data standing still (no walk) with a bolt staff, so only moves asked for move it.
func _still_data() -> EnemyBase:
	var data: EnemyBase = ImpData.duplicate() as EnemyBase
	data.move_speed = 0.0
	return data


## An enemy on the imp's scene; `layered`: its Sprite shows no art and holds a head (leaning,
## trailing, swishing, squashing, shaking, its face on it, two frames: the second for a wind-up and
## a wall) with a handle on it.
func _body(layered: bool, data: EnemyBase = null, at: Vector2 = Vector2.ZERO) -> Actor:
	var body: Actor = ImpData.scene.instantiate() as Actor
	body.data = data if data != null else _still_data()
	body.position = at
	if layered:
		var sprite := body.get_node("Sprite") as Sprite2D
		sprite.texture = null
		sprite.hframes = 1
		var head := BodyPart.new()
		head.name = "Head"
		head.texture = _art(Vector2i(16, 8), 2)
		head.hframes = 2
		head.position = Vector2(0.0, -4.0)
		head.lean = 10.0
		head.lag = 4.0
		head.swish = 5.0
		head.squash = 0.1
		head.wall_squash = 0.3
		head.shudder = 2.0
		head.fling = 2.0
		head.carries_face = true
		head.pose_frames = PackedInt32Array([0, 1, 0, 1])
		sprite.add_child(head)
		var handle := BodyPart.new()
		handle.name = "Handle"
		handle.texture = _art(Vector2i(4, 16))
		handle.position = Vector2(0.0, -6.0)
		handle.offset = Vector2(0.0, -8.0)
		handle.lean = 20.0
		head.add_child(handle)
	fx.wire(body)
	root.add_child(body)
	body.ticking = false
	fx.enemies.append(body)
	return body


func _look(body: Actor) -> CreatureLook:
	return body.get_node("CreatureLook") as CreatureLook


## The body's own dash: `move` over `seconds`, asked as its card would.
func _dash(body: Actor, move: Vector2, seconds: float) -> void:
	fx.bus.caster_move_requested.emit(body.id, &"dash", move, seconds, fx.spells.current_tag(body.id, 0))


## `count` steps of the body, moved against the walls (`Actor.move`), and the systems.
func _run(body: Actor, count: int) -> void:
	_run_all([body], count)


## `count` steps of each of `bodies`, then the systems.
func _run_all(bodies: Array, count: int) -> void:
	for i in count:
		for body: Actor in bodies:
			body.step(STEP)
			body.move(STEP)
		fx.combat.step(STEP)
		fx.projectiles.step(STEP)
		fx.spells.call("step", STEP)
		fx.board.step(STEP)


func test_the_first_state_that_holds_is_the_pose() -> void:
	check_equal(BodyPose.choose(false, false, false, false, false, false), Pose.IDLE, "nothing: idle")
	check_equal(BodyPose.choose(false, false, false, false, false, true), Pose.CAST, "a cast")
	check_equal(BodyPose.choose(false, false, false, false, true, true), Pose.MOVE, "its move over a cast")
	check_equal(BodyPose.choose(false, false, false, true, true, true), Pose.WINDUP, "a wind-up over its move")
	check_equal(BodyPose.choose(false, false, true, true, true, true), Pose.HURT, "a hit over a wind-up")
	check_equal(BodyPose.choose(false, true, true, true, true, true), Pose.WALL, "a wall over a hit")
	check_equal(BodyPose.choose(true, true, true, true, true, true), Pose.TRANSITION, "a phase change over all")


func test_its_own_move_leans_it_in_and_a_stop_swings_it_back() -> void:
	var body := _body(true)
	var look := _look(body)
	var head := body.get_node("Sprite/Head") as BodyPart
	var handle := body.get_node("Sprite/Head/Handle") as BodyPart
	_run(body, 2)
	check_equal(look.body_pose(), Pose.IDLE, "standing: idle")
	check(is_equal_approx(handle.rotation, 0.0) and head.position == head.rest_position, "upright, at rest")
	_dash(body, Vector2(120.0, 0.0), 0.6)
	_run(body, 20)
	check_equal(look.body_pose(), Pose.MOVE, "its own move: the move pose")
	check(handle.rotation > deg_to_rad(5.0), "the handle leans into the way it goes (%.1f°)" % rad_to_deg(handle.rotation))
	check(head.position.x < head.rest_position.x, "the head trails behind (%s)" % head.position)
	check(head.scale.x > 1.0 and head.scale.y < 1.0, "and squashes on the floor (%s)" % head.scale)
	var lowest: float = INF
	for i in 60:
		_run(body, 1)
		lowest = minf(lowest, handle.rotation)
	check(lowest < -deg_to_rad(0.5), "braking, it swings back past upright (%.1f°)" % rad_to_deg(lowest))
	_run(body, 120)
	check(absf(handle.rotation) < deg_to_rad(0.2), "then settles (%.2f°)" % rad_to_deg(handle.rotation))
	check_equal(look.body_pose(), Pose.IDLE, "idle again")


func test_a_move_done_to_it_is_not_its_own() -> void:
	var body := _body(true)
	fx.bus.caster_move_requested.emit(body.id, &"pull", Vector2(80.0, 0.0), 0.5, fx.spells.current_tag(body.id, 0))
	_run(body, 10)
	check(body.velocity.x > 0.0, "a pull carries it")
	check(_look(body).body_pose() != Pose.MOVE, "but it shows no move of its own")


func test_its_move_meeting_a_wall_squashes_and_shakes_it() -> void:
	var body := _body(true)
	var look := _look(body)
	var head := body.get_node("Sprite/Head") as BodyPart
	fx.projectiles.set_walls([Rect2(30.0, -40.0, 16.0, 80.0)] as Array[Rect2])
	_dash(body, Vector2(200.0, 0.0), 1.0)
	var hit: int = -1
	for i in 40:
		_run(body, 1)
		if look.body_pose() == Pose.WALL:
			hit = i
			break
	check(hit >= 0, "its move met the wall: the wall pose")
	check(body.position.x < 30.0, "the body stopped at the wall (%.1f)" % body.position.x)
	check(look.body().wall_dir.is_equal_approx(Vector2.RIGHT), "the way it went in")
	_run(body, 3)
	check(head.scale.x < 1.0, "squashed along the way it hit (%s)" % head.scale)
	check_equal(head.frame, 1, "the wall's drawn frame")
	var shook: bool = false
	for i in 6:
		_run(body, 1)
		shook = shook or absf(head.position.y - head.rest_position.y) >= 1.0
	check(shook, "and it shudders")
	_run(body, roundi(BodyPose.WALL_TIME / STEP) + 2)
	check(body.mover.is_dashing(), "its move still grinds against the wall")
	check(look.body_pose() != Pose.WALL, "but it hit once: the pose is a moment only")


func test_winding_up_it_rears_back_from_its_aim() -> void:
	var body := _body(true, ImpData.duplicate() as EnemyBase)
	fx.players[0].position = Vector2(80.0, 0.0)
	var look := _look(body)
	var ai := Fixture.ai(body)
	var head := body.get_node("Sprite/Head") as BodyPart
	var steps: int = 0
	while not ai.is_telegraphing() and steps < 200:
		_run(body, 1)
		steps += 1
	check(ai.is_telegraphing(), "it winds up at the wizard")
	_run(body, 6)
	check_equal(look.body_pose(), Pose.WINDUP, "the wind-up pose")
	check(look.body().drive.x < 0.0, "rearing back from its aim (%s)" % look.body().drive)
	check_equal(head.frame, 1, "the wind-up's drawn frame")


func test_a_hit_and_a_phase_change_show_their_poses() -> void:
	var data: EnemyBase = _still_data()
	data.max_health = 100.0
	var phase := EnemyPhase.new()
	phase.health_below = 0.5
	phase.transition = 1.0
	data.phases = [phase] as Array[EnemyPhase]
	var body := _body(true, data)
	var look := _look(body)
	# Its hurt circle joins Combat at its first step.
	_run(body, 2)
	fx.combat.hit(fx.players[0].id, body, 10.0)
	_run(body, 1)
	check(fx.actors.held_count > 0, "the hit holds the body (its hit-stop)")
	check_equal(look.body_pose(), Pose.HURT, "a hit: the hurt pose, shown through the stop")
	_run(body, roundi(CreatureLook.HURT_TIME / STEP) + 2)
	check_equal(look.body_pose(), Pose.IDLE, "for a moment")
	fx.combat.hit(fx.players[0].id, body, 50.0)
	_run(body, roundi(CreatureLook.HURT_TIME / STEP) + 2)
	check_equal(body.phases.current, 0, "the phase began")
	check_equal(look.body_pose(), Pose.TRANSITION, "standing through it: the transition pose")
	var head := body.get_node("Sprite/Head") as BodyPart
	var shook: bool = false
	for i in 6:
		_run(body, 1)
		shook = shook or head.position != head.rest_position
	check(shook, "it shakes")
	_run(body, roundi(1.2 / STEP))
	check(look.body_pose() != Pose.TRANSITION, "until the transition ends")


func test_a_layered_body_shows_no_strip_of_one_sprite() -> void:
	# Its parts have the poses' frames: a hurt or wind-up strip on its Sprite would draw behind them
	# and leave Feel's death no parts to break.
	var body := _body(true)
	var look := _look(body)
	look.hurt_texture = _art(Vector2i(8, 8), 2)
	_run(body, 2)
	fx.combat.hit(fx.players[0].id, body, 5.0)
	_run(body, 1)
	check(look.is_hurt(), "it was hurt")
	check((body.get_node("Sprite") as Sprite2D).texture == null, "its Sprite still shows no art")


func test_the_face_rides_its_part() -> void:
	var body := _body(true)
	var face: Face = null
	for child in body.get_children():
		if child is Face:
			face = child as Face
	check(face != null, "the imp has a face")
	_run(body, 2)
	var resting: Vector2 = face.body_offset
	_dash(body, Vector2(120.0, 0.0), 0.6)
	_run(body, 20)
	check(face.body_offset.x < resting.x, "the face goes with the trailing head (%s, %s)" % [resting, face.body_offset])


func test_a_phase_brings_its_parts_art_and_motes_that_follow() -> void:
	var data: EnemyBase = _still_data()
	data.max_health = 100.0
	var phase := EnemyPhase.new()
	phase.health_below = 0.5
	phase.transition = 0.0
	phase.look = PhaseLook.new()
	var burning: Texture2D = _art(Vector2i(16, 8), 2)
	phase.look.parts = {&"Head": burning} as Dictionary[StringName, Texture2D]
	phase.look.motes = MoteSource.new()
	phase.look.motes.kind = &"ember"
	phase.look.motes.colours = [&"fire"] as Array[StringName]
	phase.look.motes_on = &"Head"
	phase.look.face_row = 1
	data.phases = [phase] as Array[EnemyPhase]
	var body := _body(true, data)
	var look := _look(body)
	var face := body.get_node("Face") as Face
	var head := body.get_node("Sprite/Head") as BodyPart
	var handle := body.get_node("Sprite/Head/Handle") as BodyPart
	var handle_art: Texture2D = handle.texture
	var first_art: Texture2D = head.texture
	check(look.phase_motes() == null, "no motes before")
	_run(body, 2)
	fx.combat.hit(fx.players[0].id, body, 60.0)
	# Past the hit's stop, the phase begins.
	var steps: int = 0
	while body.phases.current < 0 and steps < 60:
		_run(body, 1)
		steps += 1
	check(head.texture == burning, "the phase's art on the part it names")
	check(handle.texture == handle_art, "a part it does not name keeps its art")
	var motes: Node2D = look.phase_motes()
	check(motes != null and motes.get_parent() == head, "its motes come off the part it names")
	check(motes.is_in_group(MoteSource.GROUP) and MoteSource.of(motes) == phase.look.motes and MoteSource.follows(motes), "a source that follows the body")
	check_equal(face.art_row, 1, "the phase's row of the face's own art (boss plan OB9)")
	# After a snapshot the look shows the phase the body is in, from the scene's art on.
	head.texture = first_art
	face.art_row = 0
	look.sync()
	check(head.texture == burning, "sync shows the phase again")
	check_equal(face.art_row, 1, "and its face's row")
	check(look.phase_motes() != null and look.phase_motes() != motes, "with its motes, once")
	body.phases.current = -1
	look.sync()
	check(head.texture == first_art and look.phase_motes() == null, "and the scene's own look before any phase")
	check_equal(face.art_row, 0, "its face's own row too")


func test_a_tapping_part_lifts_while_the_body_stands_only() -> void:
	var body := _body(true)
	var head := body.get_node("Sprite/Head") as BodyPart
	head.tap = 2.0
	head.taps = 2
	head.tap_every = 1.0
	check(is_equal_approx(head.tap_lift(BodyPart.TAP_TIME * 0.5), 1.0), "a tap is at its top half way through")
	check_equal(head.tap_lift(0.5), 0.0, "and none between the taps")
	var lifted: int = 0
	var highest: float = 0.0
	for i in 60:
		_run(body, 1)
		var up: float = head.rest_position.y - head.position.y
		highest = maxf(highest, up)
		if up > 0.0:
			lifted += 1
	check(highest >= 2.0, "standing, it lifts its tap's pixels (%.0f)" % highest)
	check(lifted > 0 and lifted <= roundi(BodyPart.TAP_TIME * 2.0 / STEP) + 1, "twice quickly, then rests (%d steps up)" % lifted)
	_dash(body, Vector2(160.0, 0.0), 0.8)
	_run(body, 15)
	var tapped: bool = false
	for i in 30:
		_run(body, 1)
		tapped = tapped or head.position.y != head.rest_position.y
	check(not tapped, "going at full speed, it never taps")


func test_a_layered_body_moves_as_a_plain_one() -> void:
	# The look is drawn only: the same moves give the same body to the bit, parts or none.
	fx.projectiles.set_walls([Rect2(60.0, -40.0, 16.0, 80.0)] as Array[Rect2])
	var plain: PackedVector2Array = _dash_path(false)
	var layered: PackedVector2Array = _dash_path(true)
	check_equal(layered, plain, "the same path and velocities, step by step")
	check(plain[plain.size() - 2].x > 10.0, "it moved (%s)" % plain[plain.size() - 2])


## Where a body (layered or not) is and how fast it goes each step of a dash into a wall and a hit.
func _dash_path(layered: bool) -> PackedVector2Array:
	var body := _body(layered)
	var path := PackedVector2Array()
	_run(body, 2)
	_dash(body, Vector2(150.0, 20.0), 0.8)
	for i in 90:
		if i == 30:
			fx.combat.hit(fx.players[0].id, body, 5.0)
		_run(body, 1)
		path.append(body.position)
		path.append(body.velocity)
	fx.enemies.erase(body)
	body.free()
	return path
