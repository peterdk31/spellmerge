extends "res://tests/support/suite.gd"
## A body the Tick steps has its looks stepped once a drawn frame, for every tick since
## (`Actor.tick_step` with `looks_later`, `Actor.step_looks_due`; performance, 2026-11-17), and not
## while it is off screen; a body stepped by hand steps them every step, as before.
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")

const STEP: float = 1.0 / 60.0

var _world: Fixture


## A look that counts its steps and the seconds they were given.
class CountingLook:
	extends ActorLook
	var steps: int = 0
	var seconds: float = 0.0

	func step(delta: float) -> void:
		steps += 1
		seconds += delta


func before_each() -> void:
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


func _body_with_look(at: Vector2) -> Array:
	var body: Actor = _world.actor(at, [&"health"] as Array[StringName], Fixture.Scripted.new())
	var look := CountingLook.new()
	body.add_look(look)
	return [body, look]


func test_the_ticks_looks_wait_for_the_drawn_frame_and_take_its_ticks_at_once() -> void:
	var made: Array = _body_with_look(Vector2(10.0, 10.0))
	var body: Actor = made[0]
	var look: CountingLook = made[1]
	for i in 3:
		body.tick_step(STEP, true)
	check_equal(look.steps, 0, "the ticks leave the looks")
	body.step_looks_due()
	check_equal(look.steps, 1, "the frame steps them once")
	check(is_equal_approx(look.seconds, 3.0 * STEP), "for the three ticks' seconds (%f)" % look.seconds)
	body.step_looks_due()
	check_equal(look.steps, 1, "a frame with no tick since steps nothing")
	body.step(STEP)
	check_equal(look.steps, 2, "a body stepped by hand steps its looks at once")


func test_a_body_off_screen_keeps_its_looks_waiting_then_catches_up_a_moment() -> void:
	var made: Array = _body_with_look(Vector2(-5000.0, -5000.0))
	var body: Actor = made[0]
	var look: CountingLook = made[1]
	for i in 60:
		body.tick_step(STEP, true)
		body.step_looks_due()
	check_equal(look.steps, 0, "off screen its looks wait")
	body.global_position = Vector2(10.0, 10.0)
	body.step_looks_due()
	check_equal(look.steps, 1, "back on screen they step")
	check(look.seconds <= Actor.LOOK_TIME_MOST + 0.0001, "a moment of them at most (%f)" % look.seconds)
