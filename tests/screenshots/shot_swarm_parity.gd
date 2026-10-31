extends "res://tests/support/screenshot.gd"
## The swarm's look, pixel for pixel (horde swarm S2, docs/milestones/horde-swarm.md, "The idea":
## a swarmer looks exactly like a full enemy). For the `crypt_mite` and the `bone_husk`: a full
## actor of the real scene and the same kind drawn by SwarmLook (a stand-in swarm fed the actor's
## own place, velocity, aim and face seed, OFFSET to its right) play the same scripted seconds:
## walk, stop and turn, a hit (Feel's flash and squash, the worried brows), a hit-stop hold, walk
## again, stand until a blink. Every frame the two are drawn by the real renderer and compared
## pixel for pixel; a frame with more than MOST_PIXELS pixels apart by more than CHANNEL fails the
## script. Side-by-side crops of the moments (full left, swarm right, 4x) are saved as
## `swarm_parity_<kind>_<moment>`.
##
## ci/build/build.sh --quick --screenshots   (SHOTS_ONLY="shot_swarm_parity" for this one)
## godot --path . --rendering-driver opengl3 --script res://tests/screenshots/shot_swarm_parity.gd

const AiFixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const ActorFixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const FakeSwarm := preload("res://tests/gameplay/horde/fixtures/fake_swarm.gd")
const SwarmLookScript := preload("res://gameplay/horde/swarm_look.gd")
const KINDS: Array[EnemyBase] = [
	preload("res://content/enemies/crypt_mite/crypt_mite.tres"),
	preload("res://content/enemies/bone_husk/bone_husk.tres"),
]
const STEP: float = 1.0 / 60.0
## Where the full actor starts (a fractional place, so sub-pixel placing is compared too), and
## how far right its swarm twin is drawn.
const START: Vector2 = Vector2(150.37, 170.61)
const OFFSET: Vector2 = Vector2(240.0, 0.0)
## The crop round each body compared (from its place), in screen pixels.
const CROP: Rect2i = Rect2i(-22, -40, 44, 48)
## A pixel is apart when a channel differs by more than this (of 255); a frame fails with more
## than MOST_PIXELS such pixels.
const CHANNEL: int = 8
const MOST_PIXELS: int = 0
const MOST_FRAMES: int = 60 * 8

var _world: AiFixture
## A crop of the bare background, to check each crop shows its enemy.
var _background: Image = null


func _init() -> void:
	warm_first = false


func take() -> void:
	if not need(["Feel"]):
		return
	var feel: Node = root.get_node("Feel")
	# Feel's reactions are stepped by hand, in step with the look's (both real time in the game).
	feel.set_process(false)
	var back := ColorRect.new()
	back.color = Color(0.08, 0.07, 0.12)
	back.size = SCREEN
	back.z_index = -10
	root.add_child(back)
	_background = Image.create_empty(CROP.size.x, CROP.size.y, false, Image.FORMAT_RGBA8)
	_background.fill(back.color)
	var worst: PackedStringArray = PackedStringArray()
	for data in KINDS:
		var report: String = await _play(data, feel)
		if _failed:
			return
		worst.append(report)
	print("SWARM PARITY: " + "; ".join(worst))
	back.queue_free()
	feel.set_process(true)


## Plays the script for `data`'s kind; fails on a frame apart. Returns a line for the report.
func _play(data: EnemyBase, feel: Node) -> String:
	_world = AiFixture.new(root)
	var body: Actor = _world.enemy(data.scene, data, START)
	var script := ActorFixture.Scripted.new()
	body.drive(script)
	var swarm := FakeSwarm.new()
	var row: int = swarm.add(swarm.kind_of(data.scene), body.position, hash(body.get_instance_id()))
	var look: SwarmLook = SwarmLookScript.new() as SwarmLook
	look.real_time = false
	look.feel = feel
	look.position = OFFSET
	look.setup(swarm)
	swarm.look = look
	root.add_child(look)
	var saved: Dictionary = {}
	var frames: int = 0
	var most_apart: int = 0
	var hits: int = 0
	var blinked: bool = false
	for i in MOST_FRAMES:
		frames = i + 1
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
		var held: float = _world.actors.held_left(body.id)
		body.step(STEP)
		swarm.positions[row] = body.position
		swarm.velocities[row] = body.velocity
		swarm.aims[row] = body.aim
		swarm.ran[row] = STEP - minf(held, STEP)
		look.step(STEP)
		body.position += body.velocity * STEP
		swarm.positions[row] = body.position
		var hit_now: bool = i == 42 or i == 96
		if hit_now:
			body.damaged.emit(0, 1)
			feel.call(&"_react", body)
			look.on_hit(row)
			hits += 1
		feel.call(&"_step_reactions", STEP)
		look.step_feel(STEP)
		var image: Image = await grab()
		var at: Vector2i = Vector2i(on_screen(body.position).floor())
		var full_crop: Image = image.get_region(Rect2i(at + CROP.position, CROP.size))
		var swarm_crop: Image = image.get_region(Rect2i(at + Vector2i(OFFSET) + CROP.position, CROP.size))
		if _apart(full_crop, _background) < MOST_PIXELS + 40:
			fail("%s: frame %d shows no enemy in its crop" % [data.id, i])
			_world.free_all()
			look.queue_free()
			return ""
		var apart: int = _apart(full_crop, swarm_crop)
		most_apart = maxi(most_apart, apart)
		var shown: Dictionary = look.row_look(row)
		var moment: String = ""
		if i == 20:
			moment = "walk"
		elif i == 60:
			moment = "stop"
		elif i == 42:
			moment = "hit"
		elif i == 74:
			moment = "hold"
		elif shown["shut"] and not blinked:
			moment = "blink"
			blinked = true
		if moment != "" and not saved.has(moment):
			saved[moment] = true
			_save_pair(full_crop, swarm_crop, "swarm_parity_%s_%s" % [data.id, moment])
		if apart > MOST_PIXELS:
			_save_pair(full_crop, swarm_crop, "swarm_parity_%s_apart" % data.id)
			fail("%s: frame %d (%.3f s) has %d pixels apart (more than %d); see swarm_parity_%s_apart" % [data.id, i, second, apart, MOST_PIXELS, data.id])
			_world.free_all()
			look.queue_free()
			return ""
		if blinked and hits == 2 and second > 2.0:
			break
	_world.free_all()
	look.queue_free()
	if not blinked:
		fail("%s: no blink within %d frames" % [data.id, frames])
		return ""
	return "%s: %d frames, at most %d pixels apart" % [data.id, frames, most_apart]


## Pixels of `a` and `b` (the same size) apart by more than CHANNEL in some channel.
func _apart(a: Image, b: Image) -> int:
	var count: int = 0
	var limit: float = float(CHANNEL) / 255.0
	for y in a.get_height():
		for x in a.get_width():
			var p: Color = a.get_pixel(x, y)
			var q: Color = b.get_pixel(x, y)
			if absf(p.r - q.r) > limit or absf(p.g - q.g) > limit or absf(p.b - q.b) > limit:
				count += 1
	return count


## The full actor's crop and the swarm's side by side, 4x, as one shot.
func _save_pair(full_crop: Image, swarm_crop: Image, shot_name: String) -> void:
	var w: int = full_crop.get_width()
	var pair := Image.create_empty(w * 2 + 2, full_crop.get_height(), false, full_crop.get_format())
	pair.fill(Color(1.0, 0.0, 1.0))
	pair.blit_rect(full_crop, Rect2i(Vector2i.ZERO, full_crop.get_size()), Vector2i.ZERO)
	pair.blit_rect(swarm_crop, Rect2i(Vector2i.ZERO, swarm_crop.get_size()), Vector2i(w + 2, 0))
	pair.resize(pair.get_width() * 4, pair.get_height() * 4, Image.INTERPOLATE_NEAREST)
	save(pair, shot_name)
