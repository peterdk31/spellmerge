extends "res://tests/support/suite.gd"
## Explosions in gameplay/feel (`explode`, `explosion_shown`): a style of `explosion_looks` says
## what one is made of. Blast's (the owner's picks, 2026-10-29) is the ragged shell, fragments
## and rubble flung past the radius, a scorch under the bodies, a shake and a punch away from the
## caster; the rising fireball is another style for anything else that explodes (a barrel).

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


func _blast(style: StringName = &"blast", at: Vector2 = Vector2(100.0, 50.0)) -> void:
	bus.explosion_shown.emit(0, at, 40.0, style, Color.WHITE, 0)


func test_a_blast_is_the_ragged_shell_fragments_and_a_scorch() -> void:
	_blast()
	check_equal(feel.effects_of(FeelScript.KIND_SHELL), 1, "the ragged shell")
	check_equal(feel.effects_of(FeelScript.KIND_DEBRIS), 1, "fragments and rubble")
	check_equal(feel.effects_of(FeelScript.KIND_SCORCH), 1, "a scorch")
	check_equal(feel.effects_of(FeelScript.KIND_FIREBALL), 0, "no fireball")
	check_equal(feel.effect_info(FeelScript.KIND_SHELL).get("zoom"), 20, "its radius is the zoom x 2")


func test_the_scorch_is_under_the_bodies_and_the_rest_over_them() -> void:
	_blast()
	feel.step(0.02)
	check_equal(feel._blast_node.multimesh.visible_instance_count, 2, "shell and fragments in the blast batch")
	check_equal(feel._blast_floor_node.multimesh.visible_instance_count, 1, "the scorch in the floor batch")
	check(feel._blast_floor_node.z_index < 40 and feel._blast_node.z_index > 40, "under the enemies (entities.gd DRAW_Z 40), and over them")
	check_equal(feel._effect_node.multimesh.visible_instance_count, 0, "nothing in the flares' batch")


func test_each_part_lasts_its_own_seconds() -> void:
	_blast()
	feel.step(FeelScript.SHELL_SECONDS + 0.01)
	check_equal(feel.effects_of(FeelScript.KIND_SHELL), 0, "the shell is gone first")
	check_equal(feel.effects_of(FeelScript.KIND_DEBRIS), 1, "the fragments still lie there")
	feel.step(FeelScript.DEBRIS_SECONDS)
	check_equal(feel.effects_of(FeelScript.KIND_DEBRIS), 0, "then crumble")
	check_equal(feel.effects_of(FeelScript.KIND_SCORCH), 1, "the scorch is last")
	feel.step(FeelScript.SCORCH_SECONDS)
	check_equal(feel.effects_of(FeelScript.KIND_SCORCH), 0, "and fades")
	check_equal(feel._blast_floor_node.multimesh.visible_instance_count, 0, "nothing left on the floor")


func test_it_shakes_and_punches_away_from_its_caster() -> void:
	var body := Node2D.new()
	root.add_child(body)
	own(body)
	body.global_position = Vector2(0.0, 50.0)
	feel.actors.set_node(0, body)
	_blast()
	check(is_equal_approx(feel.trauma(), feel.preset.explosion_looks[&"blast"]["shake"] as float), "a shake")
	check(feel.kick().x > 0.0 and is_zero_approx(feel.kick().y), "a punch away from the caster: %s" % [feel.kick()])


func test_a_caster_caught_in_its_own_blast_punches_down() -> void:
	bus.explosion_shown.emit(-1, Vector2(10.0, 10.0), 40.0, &"blast", Color.WHITE, 0)
	check(feel.kick().y > 0.0 and is_zero_approx(feel.kick().x), "no caster to push from: down the screen")


func test_the_shake_setting_turns_its_weight_off() -> void:
	feel.shake_enabled = false
	_blast()
	check_equal(feel.trauma(), 0.0, "no shake")
	check_equal(feel.kick(), Vector2.ZERO, "no punch")
	check_equal(feel.effects_of(FeelScript.KIND_SHELL), 1, "the explosion still shows")


func test_the_rising_fireball_is_a_style_of_its_own() -> void:
	_blast(&"fireball")
	check_equal(feel.effects_of(FeelScript.KIND_FIREBALL), 1, "the rising fireball")
	check_equal(feel.effects_of(FeelScript.KIND_SHELL), 0, "not the shell")
	check_equal(feel.effects_of(FeelScript.KIND_DEBRIS), 1, "with fragments")
	check_equal(feel.effects_of(FeelScript.KIND_SCORCH), 1, "and a scorch")


func test_a_style_is_data_and_an_unknown_one_shows_nothing() -> void:
	feel.preset.explosion_looks[&"puff"] = {"shape": &"fireball"}
	_blast(&"puff")
	check_equal(feel.effects_of(FeelScript.KIND_FIREBALL), 1, "a new style from the preset alone")
	check_equal(feel.effects_of(FeelScript.KIND_DEBRIS), 0, "only what it names")
	check_equal(feel.trauma(), 0.0, "no shake it does not ask for")
	_blast(&"no_such_style")
	check_equal(feel.effects_of(FeelScript.KIND_SHELL) + feel.effects_of(FeelScript.KIND_SCORCH), 0, "an unknown style shows nothing")


func test_particles_off_leaves_out_the_fragments() -> void:
	feel.particles_enabled = false
	_blast()
	check_equal(feel.effects_of(FeelScript.KIND_DEBRIS), 0, "no fragments")
	check_equal(feel.effects_of(FeelScript.KIND_SHELL), 1, "the shell still shows")


func test_a_big_blast_draws_bigger_and_a_small_one_smaller() -> void:
	bus.explosion_shown.emit(0, Vector2.ZERO, 100.0, &"blast", Color.WHITE, 0)
	check_equal(feel.effect_info(FeelScript.KIND_SHELL).get("zoom"), 50, "100 px: zoom 50")
	feel.step(FeelScript.SCORCH_SECONDS + 0.1)
	bus.explosion_shown.emit(0, Vector2.ZERO, 1.0, &"blast", Color.WHITE, 0)
	check_equal(feel.effect_info(FeelScript.KIND_SHELL).get("zoom"), 1, "the smallest is zoom 1")
