extends "res://tests/support/suite.gd"
## A slam's look in gameplay/feel (melee I8): its wind-up shows only on the staff (no ring on the
## floor: it distracted from the strike, owner 2026-10-30); at the impact (`slam`) the cue its card's impact look names, `slam`: a white-hot star (no expanding
## ring: the cracks show its reach) and the ground struck: its mark on the floor (a quake under the
## bodies that outlasts the flash), stone chips, the slammer held a moment, and a shake with a
## punch down the screen, which the screen shake setting turns off. Its flashes are all drawn on
## the floor, under the bodies (owner, 2026-11-08).

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


func test_its_card_names_its_impact_cue_and_its_wind_up_draws_no_ring() -> void:
	var card: CarrierCard = feel.registry.get_resource(&"spells", &"slam") as CarrierCard
	check_equal(card.end_cue, &"slam", "slam.tres names the cue `slam`")
	check_equal(card.shown_cue, &"", "no cue for its wind-up")


func test_its_strike_shown_is_no_cue_its_end_is() -> void:
	bus.form_shown.emit(0, &"slam", Vector2(20.0, 0.0), Vector2.RIGHT, 16.0, Color.WHITE, 0)
	check_equal(feel.flashes_of(&"quake"), 0, "showing the slam plays no cue (its card's cast look names none)")
	check_equal(feel.trauma(), 0.0, "and no shake")


func test_its_impact_is_a_star_chips_and_a_shake_with_no_ring() -> void:
	bus.carrier_ended.emit(0, &"slam", Vector2(20.0, 0.0), Vector2.RIGHT, 16.0, Color.WHITE, 0)
	check_equal(feel.flashes_of(&"burst"), 1, "a white-hot star")
	check_equal(feel.flashes_of(&"ring_out"), 0, "no expanding ring (too uniform)")
	check(feel.motes().next_row() > 0, "stone chips off the floor, as motes")
	check(is_equal_approx(feel.trauma(), feel.cue_of(&"slam").shake), "a shake")
	check(feel.kick().y > 0.0 and is_zero_approx(feel.kick().x), "a punch down the screen")


func test_it_leaves_a_mark_on_the_floor_under_the_bodies_after_the_flash() -> void:
	bus.carrier_ended.emit(0, &"slam", Vector2(20.0, 0.0), Vector2.RIGHT, 16.0, Color.WHITE, 0)
	check_equal(feel.flashes_of(&"quake"), 1, "a quake where it struck")
	check_equal(feel.flash_info(&"quake").get("zoom"), roundi(16.0 * 1.5 / feel.flash_kind(&"quake").step), "sized by its radius")
	feel.step(0.05)
	# The whole strike is on the floor, under the bodies (the owner, 2026-11-08: "the impact should be
	# drawn on the floor", not over the training dummy): the cracks, and the burst and star (`floor`).
	check_equal(feel._floor_node.multimesh.visible_instance_count, 3, "the cracks, burst and star in the floor batch")
	check_equal(feel._flash_node.multimesh.visible_instance_count, 0, "nothing drawn over the bodies (its chips are motes)")
	check(feel._floor_node.z_index < 0 and feel._floor_node.z_index > RoomBase.FLOOR_Z, "on the room's floor, under every body (the wizards and enemies draw at 0 and up): %d" % feel._floor_node.z_index)
	feel.step(0.5)
	check_equal(feel.flashes_of(&"burst"), 0, "the star is gone")
	check_equal(feel.flashes_of(&"quake"), 1, "the cracks are still there, cooling")
	feel.step(feel.flash_kind(&"quake").seconds)
	check_equal(feel.flashes_of(&"quake"), 0, "and crumble away")
	check_equal(feel._floor_node.multimesh.visible_instance_count, 0, "nothing left on the floor")


## The slammer's hold as its staff lands is the game's (`HitStop`, tests/gameplay/combat/
## test_hit_stop.gd): Feel draws the strike and holds nobody.
func test_feel_holds_nobody_as_the_staff_lands() -> void:
	bus.carrier_ended.emit(0, &"slam", Vector2(20.0, 0.0), Vector2.RIGHT, 16.0, Color.WHITE, 0)
	check_equal(feel.actors.held_count, 0, "nobody held by Feel")


func test_the_shake_setting_turns_its_shake_off() -> void:
	feel.shake_enabled = false
	bus.carrier_ended.emit(0, &"slam", Vector2(20.0, 0.0), Vector2.RIGHT, 16.0, Color.WHITE, 0)
	check_equal(feel.trauma(), 0.0, "no shake")
	check_equal(feel.kick(), Vector2.ZERO, "no punch")
	check_equal(feel.flashes_of(&"quake"), 1, "the floor mark still shows")
