extends "res://tests/support/suite.gd"
## The face (living staffs H2, docs/milestones/M2-living-staffs.md, "The face layers"): the mood
## and the look pick the right frames of the eye and brow sheets; down, a windup, a hit and
## `show_mood` win over the resting mood in that order; the layers trail the body and pop on a
## cast, and a teleport is not trailed; blinks come at each style's pace; glances and raised
## brows only while idle, and never on a stray.
##
## godot --headless --path . --script res://tests/gameplay/actor/test_face.gd

const ActorFixture := preload("res://tests/gameplay/actor/actor_fixture.gd")


## A scripted controller that is winding up a cast while `winding` is on.
class Winding:
	extends ActorFixture.Scripted
	var winding: bool = false

	func is_telegraphing() -> bool:
		return winding


var _world: ActorFixture


func before_each() -> void:
	_world = ActorFixture.new(root)


func after_each() -> void:
	_world.free_all()


## An actor wearing a face of `style` and `resting`, driven by `controller` (a Scripted by
## default), with a caster when `caster` is on.
func _wearer(style: Face.Style, resting: Face.Mood = Face.Mood.NEUTRAL, controller: ActorController = null, caster: bool = false) -> Actor:
	var body := Actor.new()
	if caster:
		var cast := Caster.new()
		cast.start_cards = [[&"bolt"]]
		body.add_child(cast)
	body.add_child(controller if controller != null else ActorFixture.Scripted.new())
	var face := Face.new()
	face.name = "Face"
	face.style = style
	face.resting_mood = resting
	body.add_child(face)
	return _world.add(body, Vector2(100.0, 100.0))


func _face(body: Actor) -> Face:
	return body.get_node(^"Face") as Face


## Steps until `seconds` have passed.
func _run(seconds: float) -> void:
	_world.run(roundi(seconds / ActorFixture.STEP))


func test_the_look_picks_the_eye_column_and_the_style_its_row() -> void:
	var body := _wearer(Face.Style.STERN)
	var controller := body.controller as ActorFixture.Scripted
	var cases: Array = [[Vector2.RIGHT, 5], [Vector2(-1.0, -1.0).normalized(), 0], [Vector2(0.2, 0.98).normalized(), 7], [Vector2.UP, 1]]
	for case: Array in cases:
		controller.aim = case[0]
		_world.run(1)
		var face := _face(body)
		if face.is_shut():
			_world.run(4)
		check_equal(face.eyes_frame(), Vector2i(case[1], Face.Style.STERN), "aiming %s" % str(case[0]))


func test_the_resting_mood_shows_and_neutral_is_the_personalitys() -> void:
	var sergeant := _wearer(Face.Style.STERN, Face.Mood.ANGRY)
	var optimist := _wearer(Face.Style.CHEER)
	_world.run(1)
	check_equal(_face(sergeant).brows_frame(), Vector2i(Face.Mood.ANGRY, 0), "the Sergeant rests angry")
	check_equal(_face(optimist).brows_frame(), Vector2i(Face.Mood.NEUTRAL, 0), "the Optimist rests neutral")


func test_a_one_eyed_stray_uses_the_single_brow_row_and_its_glow() -> void:
	var body := Actor.new()
	body.add_child(ActorFixture.Scripted.new())
	var face := Face.new()
	face.name = "Face"
	face.style = Face.Style.STRAY_ONE
	face.resting_mood = Face.Mood.ANGRY
	face.glow = Color(1.0, 0.64, 0.24)
	body.add_child(face)
	_world.add(body, Vector2.ZERO)
	_world.run(1)
	check_equal(face.brows_frame(), Vector2i(Face.Mood.ANGRY, 1), "one brow")
	check_equal(face.eyes_frame().y, int(Face.Style.STRAY_ONE), "one eye")
	check_equal((face.get_child(0) as Sprite2D).modulate, face.glow, "the eyes glow in the element colour")


func test_down_beats_a_windup_beats_a_shown_mood_beats_the_rest() -> void:
	var controller := Winding.new()
	var body := _wearer(Face.Style.STRAY, Face.Mood.ANGRY, controller)
	var face := _face(body)
	face.show_mood(Face.Mood.RAISED, 1.0)
	_world.run(1)
	check_equal(face.mood(), Face.Mood.RAISED, "a shown mood")
	controller.winding = true
	_world.run(1)
	check_equal(face.mood(), Face.Mood.FURIOUS, "a windup is furious, over a shown mood")
	body.set_down(true)
	_world.run(1)
	check_equal(face.mood(), Face.Mood.WORRIED, "down is worried")
	check(face.is_shut(), "down shuts the eyes")
	check_equal(face.eyes_frame().x, Face.BLINK_COLUMN, "shut eyes show the blink frame")
	body.set_down(false)
	controller.winding = false
	_run(1.5)
	check_equal(face.mood(), Face.Mood.ANGRY, "the shown mood ran out: back to resting")


func test_a_hit_shows_worried_for_a_moment() -> void:
	var body := _wearer(Face.Style.CHEER)
	var face := _face(body)
	body.damaged.emit(0, 5)
	_world.run(1)
	check_equal(face.mood(), Face.Mood.WORRIED, "a hit is worried")
	_run(Face.HURT_TIME + 0.25)
	check_equal(face.mood(), Face.Mood.NEUTRAL, "and then it passes")


func test_the_layers_trail_the_body_and_settle() -> void:
	var body := _wearer(Face.Style.CHEER)
	var face := _face(body)
	_world.run(1)
	check_equal(face.eye_offset(), Vector2.ZERO, "at rest the eyes sit on the anchor")
	# The body hops up 6 px: the eyes are left behind (below it), the brows further behind.
	face.body_offset = Vector2(0.0, -6.0)
	_world.run(1)
	check(face.eye_offset().y > 0.0, "the eyes trail the hop (got %s)" % str(face.eye_offset()))
	check(face.eye_offset().y <= Face.MAX_LAG, "by at most MAX_LAG")
	check(face.brow_offset().y > 0.0, "the brows trail the eyes (got %s)" % str(face.brow_offset()))
	_run(1.0)
	check_equal(face.eye_offset(), Vector2.ZERO, "the eyes settle")
	check_equal(face.brow_offset(), Vector2.ZERO, "the brows settle")


func test_a_teleport_is_not_trailed() -> void:
	var body := _wearer(Face.Style.CHEER)
	var face := _face(body)
	_world.run(1)
	body.position += Vector2(80.0, 0.0)
	_world.run(1)
	check_equal(face.eye_offset(), Vector2.ZERO, "a long jump snaps the face along")


func test_a_cast_pops_the_eyes_and_more_the_brows() -> void:
	var body := _wearer(Face.Style.CHEER, Face.Mood.NEUTRAL, null, true)
	var face := _face(body)
	_world.run(1)
	body.caster.cast_done.emit(0, body.global_position, Vector2.RIGHT)
	_world.run(1)
	check_equal(face.eye_offset().y, -Face.POP_EYES, "the eyes pop up")
	check_equal(face.brow_offset().y, -Face.POP_BROWS, "the brows pop up further")
	_run(Face.POP_TIME + 0.1)
	check_equal(face.eye_offset(), Vector2.ZERO, "and come back")


## Blinks (and their total shut time) over a minute.
func _blinks(style: Face.Style) -> Vector2:
	var face := _face(_wearer(style))
	var count: int = 0
	var shut: float = 0.0
	var was_shut: bool = false
	for i in roundi(60.0 / ActorFixture.STEP):
		_world.run(1)
		if face.is_shut():
			shut += ActorFixture.STEP
			if not was_shut:
				count += 1
		was_shut = face.is_shut()
	return Vector2(count, shut)


func test_each_style_blinks_at_its_own_pace() -> void:
	var sergeant: Vector2 = _blinks(Face.Style.STERN)
	var dozer: Vector2 = _blinks(Face.Style.SLEEPY)
	# About 60 s / 4.0 s and 60 s / 2.4 s.
	check(sergeant.x >= 10.0 and sergeant.x <= 21.0, "the Sergeant blinks about every 4 s (got %d)" % int(sergeant.x))
	check(dozer.x >= 18.0 and dozer.x <= 34.0, "the Dozer about every 2.4 s (got %d)" % int(dozer.x))
	check(dozer.y > sergeant.y * 3.0, "the Dozer's eyes are shut much longer (%.2f s, %.2f s)" % [dozer.y, sergeant.y])


func test_glances_and_raised_brows_only_while_idle_and_never_on_a_stray() -> void:
	var walker := _wearer(Face.Style.EAGER)
	(walker.controller as ActorFixture.Scripted).move = Vector2.RIGHT
	var stander := _wearer(Face.Style.EAGER)
	var stray := _wearer(Face.Style.STRAY, Face.Mood.ANGRY)
	var glances: Array[int] = [0, 0, 0]
	var raises: Array[int] = [0, 0, 0]
	var bodies: Array[Actor] = [walker, stander, stray]
	for i in roundi(30.0 / ActorFixture.STEP):
		_world.run(1)
		for k in bodies.size():
			var face := _face(bodies[k])
			glances[k] += 1 if face.is_glancing() else 0
			raises[k] += 1 if face.mood() == Face.Mood.RAISED else 0
	check(glances[1] > 0 and raises[1] > 0, "a standing Show-off glances and raises a brow")
	check(glances[0] == 0 and raises[0] == 0, "a moving one does neither")
	check(glances[2] == 0 and raises[2] == 0, "a stray does neither")
