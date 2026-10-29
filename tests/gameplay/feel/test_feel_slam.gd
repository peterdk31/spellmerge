extends "res://tests/support/suite.gd"
## A slam's look in gameplay/feel (melee I8): while it winds up, a ring closes on where it will
## strike for the seconds until then (`form_shown` `slam_mark`); at the impact (`slam`) a white-hot
## star, the shockwave ring out to its radius, stone chips and a shake, which the screen shake
## setting turns off.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

var bus: EventsScript
var feel: FeelScript


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	feel = own(FeelScript.new()) as FeelScript
	feel.events = bus
	feel.actors = own(ActorSeats.table(4)) as ActorSeats.ActorsScript
	feel.drive_engine = false
	feel.preset = FeelPresetScript.new()
	root.add_child(feel)


func test_its_wind_up_marks_where_it_will_strike_until_it_does() -> void:
	bus.form_shown.emit(0, &"slam_mark", Vector2(20.0, 0.0), Vector2.RIGHT, 0.25, Color.WHITE, 0)
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 1, "a ring closes on the spot")
	feel.step(0.2)
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 1, "still there just before it strikes")
	feel.step(0.1)
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 0, "gone when it strikes")


func test_its_impact_is_a_star_a_ring_chips_and_a_shake() -> void:
	bus.form_shown.emit(0, &"slam", Vector2(20.0, 0.0), Vector2.RIGHT, 16.0, Color.WHITE, 0)
	check_equal(feel.effects_of(FeelScript.KIND_BURST), 1, "a white-hot star")
	check_equal(feel.effects_of(FeelScript.KIND_RING_OUT), 1, "the shockwave ring")
	check_equal(feel.effects_of(FeelScript.KIND_CHIPS), 1, "stone chips off the floor")
	check(is_equal_approx(feel.trauma(), feel.preset.slam_shake), "a shake")


func test_the_shake_setting_turns_its_shake_off() -> void:
	feel.shake_enabled = false
	bus.form_shown.emit(0, &"slam", Vector2(20.0, 0.0), Vector2.RIGHT, 16.0, Color.WHITE, 0)
	check_equal(feel.trauma(), 0.0, "no shake")
	check_equal(feel.effects_of(FeelScript.KIND_RING_OUT), 1, "the ring still shows")
