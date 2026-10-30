extends "res://tests/support/suite.gd"
## Cues in gameplay/feel (`play_cue`, `cue_shown`): a cue is a `CueBase` file in `content/cues/`
## that says a moment's flashes and weight. Blast's (the owner's picks, 2026-10-29) is the ragged
## shell, fragments and rubble flung past the radius, a scorch under the bodies, a shake and a
## punch away from the caster; the rising fireball is a barrel's; the quake is a ground strike.
## A cue made in the test checks each key on its own.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")


## The real cues, and one more made in the test.
class CuesRegistry:
	extends RegistryScript
	var extra: CueBase = null

	func get_resource(folder: StringName, id: StringName) -> Resource:
		if extra != null and folder == &"cues" and id == extra.id:
			return extra
		return super(folder, id)


var bus: EventsScript
var feel: FeelScript
var registry: CuesRegistry


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	feel = own(FeelScript.new()) as FeelScript
	feel.events = bus
	feel.actors = own(ActorSeats.table(4)) as ActorSeats.ActorsScript
	feel.drive_engine = false
	feel.preset = FeelPresetScript.new()
	registry = own(CuesRegistry.new()) as CuesRegistry
	registry.scan()
	feel.registry = registry
	root.add_child(feel)


func _cue(id: StringName, at: Vector2 = Vector2(100.0, 50.0), size: float = 40.0) -> void:
	bus.cue_shown.emit(0, id, at, Vector2.ZERO, size, Color.WHITE, 0)


func _made(parts: Array[Dictionary]) -> CueBase:
	var cue := CueBase.new()
	cue.id = &"test_cue"
	cue.parts = parts
	registry.extra = cue
	return cue


func test_a_blast_is_the_ragged_shell_fragments_and_a_scorch() -> void:
	_cue(&"blast")
	check_equal(feel.effects_of(FeelScript.KIND_SHELL), 1, "the ragged shell")
	check_equal(feel.effects_of(FeelScript.KIND_DEBRIS), 1, "fragments and rubble")
	check_equal(feel.effects_of(FeelScript.KIND_SCORCH), 1, "a scorch")
	check_equal(feel.effects_of(FeelScript.KIND_FIREBALL), 0, "no fireball")
	check_equal(feel.effect_info(FeelScript.KIND_SHELL).get("zoom"), 20, "its radius is the zoom x 2")


func test_the_scorch_is_under_the_bodies_and_the_rest_over_them() -> void:
	_cue(&"blast")
	feel.step(0.02)
	check_equal(feel._blast_node.multimesh.visible_instance_count, 2, "shell and fragments in the blast batch")
	check_equal(feel._blast_floor_node.multimesh.visible_instance_count, 1, "the scorch in the floor batch")
	check(feel._blast_floor_node.z_index < 40 and feel._blast_node.z_index > 40, "under the enemies (entities.gd DRAW_Z 40), and over them")
	check_equal(feel._effect_node.multimesh.visible_instance_count, 0, "nothing in the flares' batch")


func test_each_part_lasts_its_own_seconds() -> void:
	_cue(&"blast")
	feel.step(FeelScript.SHELL_SECONDS + 0.01)
	check_equal(feel.effects_of(FeelScript.KIND_SHELL), 0, "the shell is gone first")
	check_equal(feel.effects_of(FeelScript.KIND_DEBRIS), 1, "the fragments still lie there")
	feel.step(FeelScript.DEBRIS_SECONDS)
	check_equal(feel.effects_of(FeelScript.KIND_DEBRIS), 0, "then crumble")
	check_equal(feel.effects_of(FeelScript.KIND_SCORCH), 1, "the scorch is last")
	feel.step(FeelScript.SCORCH_SECONDS)
	check_equal(feel.effects_of(FeelScript.KIND_SCORCH), 0, "and fades")


func test_a_blast_shakes_and_punches_away_from_its_caster() -> void:
	var body := Node2D.new()
	root.add_child(body)
	own(body)
	body.global_position = Vector2(0.0, 50.0)
	feel.actors.set_node(0, body)
	_cue(&"blast")
	check(is_equal_approx(feel.trauma(), feel.cue_of(&"blast").shake), "a shake")
	check(feel.kick().x > 0.0 and is_zero_approx(feel.kick().y), "a punch away from the caster: %s" % [feel.kick()])


func test_away_with_no_body_to_push_from_punches_down() -> void:
	bus.cue_shown.emit(-1, &"blast", Vector2(10.0, 10.0), Vector2.ZERO, 40.0, Color.WHITE, 0)
	check(feel.kick().y > 0.0 and is_zero_approx(feel.kick().x), "down the screen")


func test_the_shake_setting_turns_its_weight_off() -> void:
	feel.shake_enabled = false
	_cue(&"blast")
	check_equal(feel.trauma(), 0.0, "no shake")
	check_equal(feel.kick(), Vector2.ZERO, "no punch")
	check_equal(feel.effects_of(FeelScript.KIND_SHELL), 1, "the explosion still shows")


func test_the_rising_fireball_is_a_cue_of_its_own() -> void:
	_cue(&"fireball")
	check_equal(feel.effects_of(FeelScript.KIND_FIREBALL), 1, "the rising fireball")
	check_equal(feel.effects_of(FeelScript.KIND_SHELL), 0, "not the shell")
	check_equal(feel.effects_of(FeelScript.KIND_DEBRIS), 1, "with fragments")
	check_equal(feel.effects_of(FeelScript.KIND_SCORCH), 1, "and a scorch")


func test_the_quake_strikes_the_ground_and_holds_its_caster() -> void:
	_cue(&"quake", Vector2(20.0, 0.0), 16.0)
	check_equal(feel.effects_of(FeelScript.KIND_QUAKE), 1, "a mark on the floor")
	check_equal(feel.effect_info(FeelScript.KIND_QUAKE).get("zoom"), roundi(16.0 * FeelScript.QUAKE_PAST / FeelScript.QUAKE_REACH), "out past its reach")
	check_equal(feel.effects_of(FeelScript.KIND_CHIPS), 1, "stone chips")
	check(is_equal_approx(feel.actors.held_left(0), feel.cue_of(&"quake").hold), "its caster held")
	check(feel.kick().y > 0.0, "a punch down the screen")


func test_an_unknown_cue_shows_nothing() -> void:
	_cue(&"no_such_cue")
	check_equal(feel.live_effects(), 0, "nothing")
	check_equal(feel.trauma(), 0.0, "no shake")


func test_a_new_cue_is_data_alone() -> void:
	_made([{"effect": &"fireball", "reach": 1.0}])
	_cue(&"test_cue")
	check_equal(feel.effects_of(FeelScript.KIND_FIREBALL), 1, "the part it names")
	check_equal(feel.live_effects(), 1, "only that")
	check_equal(feel.trauma(), 0.0, "no weight it does not ask for")


func test_a_part_sizes_by_zoom_or_by_the_cues_size() -> void:
	_made([{"effect": &"burst", "zoom": 3}, {"effect": &"ring_out", "reach": 1.0}])
	_cue(&"test_cue", Vector2.ZERO, 30.0)
	check_equal(feel.effect_info(FeelScript.KIND_BURST).get("zoom"), 3, "a fixed zoom")
	check_equal(feel.effect_info(FeelScript.KIND_RING_OUT).get("zoom"), 3, "a ring of 30 px: 10 px a step")


func test_a_part_can_take_an_exact_colour_or_be_plain() -> void:
	_made([{"effect": &"burst", "color": Color.RED}, {"effect": &"chips", "plain": true}])
	bus.cue_shown.emit(1, &"test_cue", Vector2.ZERO, Vector2.ZERO, 0.0, Color.BLUE, 5)
	check_equal(feel.effect_dress(FeelScript.KIND_BURST), [Color.RED, FeelScript.EXACT], "its own colour, exactly")
	check_equal(feel.effect_dress(FeelScript.KIND_CHIPS), [Color.WHITE, 0], "white, no cards")


func test_a_part_faces_the_way_it_says() -> void:
	_made([{"effect": &"burst"}, {"effect": &"spray", "way": &"back"}, {"effect": &"puff", "way": &"up"}])
	bus.cue_shown.emit(0, &"test_cue", Vector2.ZERO, Vector2.LEFT, 0.0, Color.WHITE, 0)
	check_equal(feel.effect_info(FeelScript.KIND_BURST).get("dir"), Vector2.LEFT, "the cue's way")
	check_equal(feel.effect_info(FeelScript.KIND_SPRAY).get("dir"), Vector2.RIGHT, "against it")
	check_equal(feel.effect_info(FeelScript.KIND_PUFF).get("dir"), Vector2.UP, "up the screen")


func test_a_part_can_last_the_cues_size_in_seconds() -> void:
	_made([{"effect": &"ring_in", "zoom": 2, "lasts_size": true}, {"effect": &"burst"}])
	_cue(&"test_cue", Vector2.ZERO, 0.6)
	check(is_equal_approx(feel.effect_info(FeelScript.KIND_RING_IN)["seconds"], 0.6), "as long as the cue is big")
	check_equal(feel.effect_info(FeelScript.KIND_RING_IN).get("zoom"), 2, "its zoom still its own")
	check(is_equal_approx(feel.effect_info(FeelScript.KIND_BURST)["seconds"], FeelScript.BURST_SECONDS), "the other parts keep theirs")
	feel.step(FeelScript.BURST_SECONDS + 0.4)
	_cue(&"test_cue", Vector2.ZERO, 0.0)
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 0, "left out when the cue's size is 0")
	check_equal(feel.effects_of(FeelScript.KIND_BURST), 1, "the rest still shows")


func test_the_telegraph_closes_on_its_point_for_its_seconds() -> void:
	_cue(&"telegraph", Vector2(40.0, 40.0), 0.6)
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 1, "a ring closing")
	check_equal(feel.effect_info(FeelScript.KIND_RING_IN).get("zoom"), 2, "2 steps across")
	check_equal(feel.effect_info(FeelScript.KIND_RING_IN).get("dir"), Vector2.RIGHT, "upright")
	feel.step(0.5)
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 1, "still there just before")
	feel.step(0.2)
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 0, "gone when the wait is over")


func test_the_nova_is_a_ring_120_px_across_for_a_quarter_second() -> void:
	_cue(&"nova", Vector2(50.0, 60.0), 0.0)
	check_equal(feel.effects_of(FeelScript.KIND_RING_OUT), 1, "a ring flashes out")
	check_equal(feel.effect_info(FeelScript.KIND_RING_OUT).get("zoom"), 6, "6 steps of 20 px across")
	check(is_equal_approx(feel.effect_info(FeelScript.KIND_RING_OUT)["seconds"], 0.25), "a quarter second")
	check_equal(feel.trauma(), 0.0, "no weight")


func test_the_slam_is_a_star_and_the_ground_struck() -> void:
	_cue(&"slam", Vector2(20.0, 0.0), 16.0)
	check_equal(feel.effects_of(FeelScript.KIND_BURST), 1, "a white-hot star")
	check_equal(feel.effect_info(FeelScript.KIND_BURST).get("zoom"), 3, "3 steps big")
	check_equal(feel.effects_of(FeelScript.KIND_QUAKE), 1, "cracks in the floor")
	check_equal(feel.effect_info(FeelScript.KIND_QUAKE).get("zoom"), roundi(16.0 * FeelScript.QUAKE_PAST / FeelScript.QUAKE_REACH), "out past its reach")
	check_equal(feel.effects_of(FeelScript.KIND_CHIPS), 1, "stone chips")
	var quake: CueBase = feel.cue_of(&"quake")
	var slam: CueBase = feel.cue_of(&"slam")
	check(slam.shake == quake.shake and slam.kick == quake.kick and slam.hold == quake.hold and slam.kick_way == quake.kick_way, "the quake's weight")


func test_particles_off_leaves_out_the_parts_that_say_so() -> void:
	feel.particles_enabled = false
	_cue(&"blast")
	check_equal(feel.effects_of(FeelScript.KIND_DEBRIS), 0, "no fragments")
	check_equal(feel.effects_of(FeelScript.KIND_SHELL), 1, "the shell still shows")


func test_holds_and_the_game_stop_are_the_cues() -> void:
	var cue: CueBase = _made([])
	cue.hold = 0.05
	cue.hold_target = 0.07
	cue.stop_game = 0.1
	feel.play_cue(&"test_cue", 0, Vector2.ZERO, Vector2.ZERO, 0.0, Color.WHITE, 0, 2)
	check(is_equal_approx(feel.actors.held_left(0), 0.05), "the caster held")
	check(is_equal_approx(feel.actors.held_left(2), 0.07), "the target held")
	check_equal(feel.actors.held_left(1), 0.0, "nobody else")
	check(is_equal_approx(feel.stop_left, 0.1), "the whole game stopped")


func test_kick_ways() -> void:
	var cue: CueBase = _made([])
	cue.kick = 2.0
	for row: Array in [[&"down", Vector2.DOWN], [&"back", Vector2.RIGHT], [&"aim", Vector2.LEFT]]:
		cue.kick_way = row[0]
		feel.shake_enabled = false
		feel.shake_enabled = true
		bus.cue_shown.emit(0, &"test_cue", Vector2.ZERO, Vector2.LEFT, 0.0, Color.WHITE, 0)
		check(feel.kick().normalized().is_equal_approx(row[1]), "%s: %s" % [row[0], feel.kick()])


func test_a_big_cue_draws_bigger_and_a_small_one_smaller() -> void:
	_cue(&"blast", Vector2.ZERO, 100.0)
	check_equal(feel.effect_info(FeelScript.KIND_SHELL).get("zoom"), 50, "100 px: zoom 50")
	feel.step(FeelScript.SCORCH_SECONDS + 0.1)
	_cue(&"blast", Vector2.ZERO, 1.0)
	check_equal(feel.effect_info(FeelScript.KIND_SHELL).get("zoom"), 1, "the smallest is zoom 1")


func test_every_part_name_has_an_effect() -> void:
	for effect: StringName in CueBase.EFFECTS:
		check(FeelScript.CUE_EFFECTS.has(effect), "%s is drawn" % effect)


func test_a_death_plays_its_cue() -> void:
	var cue: CueBase = feel.cue_of(&"enemy_death")
	bus.enemy_died.emit(0, null, Vector2(30.0, 30.0), -1)
	check_equal(feel.effect_dress(FeelScript.KIND_RING_OUT), [cue.parts[0]["color"], FeelScript.EXACT], "the white-hot ring, exactly its colour")
	check_equal(feel.effect_info(FeelScript.KIND_RING_OUT).get("zoom"), cue.parts[0]["zoom"], "as big as the cue says")
	check(is_equal_approx(feel.actors.held_left(0), cue.hold), "the killer held")
	check(is_equal_approx(feel.trauma(), cue.shake), "a shake")
	check_equal(feel.stop_left, 0.0, "the game runs on")
	check_equal(feel.effects_of(FeelScript.KIND_PUFF), 1, "and a puff of its own (no hit to take over)")


func test_a_downed_wizard_plays_its_cue() -> void:
	var cue: CueBase = feel.cue_of(&"player_downed")
	bus.player_downed.emit(1)
	check(is_equal_approx(feel.stop_left, cue.stop_game), "the whole game stopped")
	check(is_equal_approx(feel.trauma(), cue.shake), "a shake")
	check_equal(feel.live_effects(), 0, "nothing drawn: the event names no position")
	check_equal(feel.actors.held_count, 0, "nobody held")


func test_a_heal_plays_its_cue() -> void:
	var cue: CueBase = feel.cue_of(&"heal")
	bus.heal_dealt.emit(0, null, 5, Vector2(10.0, 10.0))
	check_equal(feel.effect_dress(FeelScript.KIND_RING_OUT), [cue.parts[0]["color"], FeelScript.EXACT], "a ring in exactly its colour")
	check_equal(feel.effect_info(FeelScript.KIND_RING_OUT).get("zoom"), cue.parts[0]["zoom"], "as big as the cue says")
	check_equal(feel.trauma(), 0.0, "no shake")
