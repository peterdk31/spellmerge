extends "res://tests/support/suite.gd"
## A slam's look in gameplay/feel (melee I8): while it winds up, a ring closes on where it will
## strike for the seconds until then (`form_shown` `slam_mark`, the cue `telegraph`); at the
## impact (`slam`) the cue its card's impact look names, `slam`: a white-hot star (no expanding
## ring: the cracks show its reach) and the ground struck: its mark on the floor (a quake under the
## bodies that outlasts the flash), stone chips, the slammer held a moment, and a shake with a
## punch down the screen, which the screen shake setting turns off.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
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
	var registry: RegistryScript = own(RegistryScript.new()) as RegistryScript
	registry.scan()
	feel.registry = registry
	root.add_child(feel)


func test_its_wind_up_marks_where_it_will_strike_until_it_does() -> void:
	bus.form_shown.emit(0, &"slam_mark", Vector2(20.0, 0.0), Vector2.RIGHT, 0.25, Color.WHITE, 0)
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 1, "a ring closes on the spot")
	feel.step(0.2)
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 1, "still there just before it strikes")
	feel.step(0.1)
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 0, "gone when it strikes")


func test_its_card_names_its_impact_cue_and_its_wind_up_is_a_telegraph() -> void:
	var card: FormBase = feel.registry.get_resource(&"spells", &"slam") as FormBase
	check_equal(card.impact_look.get("cue"), &"slam", "slam.tres names the cue `slam`")
	check_equal(FeelScript.FORM_CUES.get(&"slam_mark"), &"telegraph", "its wind-up is the telegraph")
	bus.form_shown.emit(0, &"slam_mark", Vector2(20.0, 0.0), Vector2.RIGHT, 0.0, Color.WHITE, 0)
	check_equal(feel.live_effects(), 0, "no wind-up, no mark")


func test_its_impact_is_a_star_chips_and_a_shake_with_no_ring() -> void:
	bus.form_shown.emit(0, &"slam", Vector2(20.0, 0.0), Vector2.RIGHT, 16.0, Color.WHITE, 0)
	check_equal(feel.effects_of(FeelScript.KIND_BURST), 1, "a white-hot star")
	check_equal(feel.effects_of(FeelScript.KIND_RING_OUT), 0, "no expanding ring (too uniform)")
	check_equal(feel.effects_of(FeelScript.KIND_CHIPS), 1, "stone chips off the floor")
	check(is_equal_approx(feel.trauma(), feel.cue_of(&"slam").shake), "a shake")
	check(feel.kick().y > 0.0 and is_zero_approx(feel.kick().x), "a punch down the screen")


func test_it_leaves_a_mark_on_the_floor_under_the_bodies_after_the_flash() -> void:
	bus.form_shown.emit(0, &"slam", Vector2(20.0, 0.0), Vector2.RIGHT, 16.0, Color.WHITE, 0)
	check_equal(feel.effects_of(FeelScript.KIND_QUAKE), 1, "a quake where it struck")
	check_equal(feel.effect_info(FeelScript.KIND_QUAKE).get("zoom"), roundi(16.0 * FeelScript.QUAKE_PAST / FeelScript.QUAKE_REACH), "sized by its radius")
	feel.step(0.05)
	check_equal(feel._floor_node.multimesh.visible_instance_count, 1, "drawn in the floor batch")
	check_equal(feel._effect_node.multimesh.visible_instance_count, 2, "not with the flashes (star, chips)")
	check(feel._floor_node.z_index < 40, "under the enemies (entities.gd DRAW_Z)")
	feel.step(0.5)
	check_equal(feel.effects_of(FeelScript.KIND_BURST), 0, "the star is gone")
	check_equal(feel.effects_of(FeelScript.KIND_QUAKE), 1, "the cracks are still there, cooling")
	feel.step(FeelScript.QUAKE_SECONDS)
	check_equal(feel.effects_of(FeelScript.KIND_QUAKE), 0, "and crumble away")
	check_equal(feel._floor_node.multimesh.visible_instance_count, 0, "nothing left on the floor")


func test_the_slammer_is_held_as_its_staff_lands_hit_or_miss() -> void:
	bus.form_shown.emit(0, &"slam", Vector2(20.0, 0.0), Vector2.RIGHT, 16.0, Color.WHITE, 0)
	check(is_equal_approx(feel.actors.held_left(0), feel.cue_of(&"slam").hold), "the slammer holds")
	check_equal(feel.actors.held_left(1), 0.0, "nobody else does")


func test_the_shake_setting_turns_its_shake_off() -> void:
	feel.shake_enabled = false
	bus.form_shown.emit(0, &"slam", Vector2(20.0, 0.0), Vector2.RIGHT, 16.0, Color.WHITE, 0)
	check_equal(feel.trauma(), 0.0, "no shake")
	check_equal(feel.kick(), Vector2.ZERO, "no punch")
	check_equal(feel.effects_of(FeelScript.KIND_QUAKE), 1, "the floor mark still shows")
