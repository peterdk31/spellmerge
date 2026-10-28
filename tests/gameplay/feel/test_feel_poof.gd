extends "res://tests/support/suite.gd"
## The poof's cloud (living staffs H4): `staff_shown` draws a puff with the POOF look along the
## staff (its middle POOF_ALONG from the hand along the aim), POOF_SECONDS long, that moves with
## the actor.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_feel_poof.gd

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")

const STEP: float = 1.0 / 60.0

var _bus: EventsScript
var _feel: FeelScript


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_feel = own(FeelScript.new()) as FeelScript
	_feel.events = _bus
	_feel.drive_engine = false
	_feel.preset = FeelPresetScript.new()
	root.add_child(_feel)


func _staff() -> Actor:
	var body := own(Actor.new()) as Actor
	body.hand_offset = Vector2(0.0, -12.0)
	body.aim = Vector2.UP
	body.position = Vector2(50.0, 60.0)
	root.add_child(body)
	body.set_physics_process(false)
	return body


func test_a_staff_shown_draws_a_poof_on_the_staff_that_follows_it() -> void:
	var body := _staff()
	_bus.staff_shown.emit(7, body, 1)
	var shown: Dictionary = _feel.effect_info(FeelScript.KIND_PUFF)
	check(not shown.is_empty(), "a puff shows")
	if shown.is_empty():
		return
	check(((shown["look"] as int) & FeelScript.POOF) != 0, "with the poof look")
	check(is_equal_approx(shown["seconds"] as float, FeelScript.POOF_SECONDS), "for the poof's seconds")
	check_equal(shown["dir"], Vector2.UP, "along the staff")
	var middle: Vector2 = body.global_position + body.hand_offset + Vector2.UP * FeelScript.POOF_ALONG
	check_equal(shown["at"], middle.round(), "on the staff's middle")
	body.position += Vector2(20.0, 0.0)
	_feel.step(STEP)
	check_equal((_feel.effect_info(FeelScript.KIND_PUFF)["at"] as Vector2).x, middle.x + 20.0, "and moves with it")
	for i in roundi(FeelScript.POOF_SECONDS / STEP) + 2:
		_feel.step(STEP)
	check(_feel.effect_info(FeelScript.KIND_PUFF).is_empty(), "then it is gone")
