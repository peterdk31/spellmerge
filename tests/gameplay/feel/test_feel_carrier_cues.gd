extends "res://tests/support/suite.gd"
## The carriers' moments in gameplay/feel are cues their cards name: `form_shown` plays a card's
## `shown_cue` where the carrier shows itself (where a teleport leaves, each end of a swap,
## a decoy or familiar appearing), `carrier_ended` its `end_cue` where a carrier with no
## shot ends (a teleport landing, a rain falling, a slam's strike, a decoy going). The cues use the
## columns of light (`rise`, `fall`) drawn by `shot_effect.gdshader`.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_feel_carrier_cues.gd

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const FROST := Color(0.5, 0.75, 0.94)

var bus: EventsScript
var feel: FeelScript
var registry: RegistryScript


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	feel = own(FeelScript.new()) as FeelScript
	feel.events = bus
	feel.actors = own(ActorSeats.table(4)) as ActorSeats.ActorsScript
	feel.drive_engine = false
	feel.preset = FeelPresetScript.new()
	feel.preset.hit_sound = &""
	registry = own(RegistryScript.new()) as RegistryScript
	registry.scan()
	feel.registry = registry
	root.add_child(feel)


func _card(id: StringName) -> FormBase:
	return registry.get_resource(&"spells", id) as FormBase


func test_a_teleport_rises_off_where_it_leaves() -> void:
	check_equal(_card(&"teleport").shown_cue, &"vanish", "teleport.tres names the cue `vanish`")
	bus.form_shown.emit(0, &"teleport", Vector2(10, 10), Vector2.RIGHT, 96.0, FROST, 0)
	check_equal(feel.effects_of(FeelScript.KIND_RISE), 1, "a column of light pulled up off the spot")
	check_equal(feel.effects_of(FeelScript.KIND_RING_IN), 0, "its ring is the column's own, flat on the floor")
	check_equal(feel.effects_of(FeelScript.KIND_FALL), 0, "nothing lands yet")
	check(feel.effect_info(FeelScript.KIND_RISE)["at"].is_equal_approx(Vector2(10, 10)), "where it left")


func test_a_teleport_strikes_down_where_it_lands() -> void:
	check_equal(_card(&"teleport").end_cue, &"appear", "teleport.tres names the cue `appear`")
	bus.carrier_ended.emit(0, &"teleport", Vector2(106, 10), Vector2.RIGHT, 1.0, FROST, 0)
	check_equal(feel.effects_of(FeelScript.KIND_FALL), 1, "a column of light struck down onto the spot")
	check(feel.effect_info(FeelScript.KIND_FALL)["at"].is_equal_approx(Vector2(106, 10)), "where it landed")
	check(feel.trauma() > 0.0, "with a little shake")
	feel.step(FeelScript.FALL_SECONDS + 0.05)
	check_equal(feel.effects_of(FeelScript.KIND_FALL), 0, "and it is gone after its seconds")


func test_each_end_of_a_swap_shows() -> void:
	bus.form_shown.emit(0, &"swap", Vector2(0, 0), Vector2.RIGHT, 80.0, FROST, 0)
	bus.form_shown.emit(0, &"swap", Vector2(80, 0), Vector2.LEFT, 80.0, FROST, 0)
	check_equal(feel.effects_of(FeelScript.KIND_FALL), 2, "a column struck down at both ends of the trade")
	check_equal(feel.effects_of(FeelScript.KIND_RISE), 2, "and one pulled up, their rings crossing")


func test_a_rain_falls_where_it_lands() -> void:
	bus.carrier_ended.emit(1, &"rain", Vector2(40, 40), Vector2.DOWN, 16.0, FROST, 0)
	check_equal(feel.effects_of(FeelScript.KIND_FALL), 1, "a column struck down where it fell")
	check_equal(feel.effects_of(FeelScript.KIND_SPRAY), 1, "a splash thrown up")


## A dash's moments are cues its card names (spell-spectacle-2.md, S5): `dash_start` where it
## leaves (dust kicked up at its feet, and lightning arcs along its way), `dash_land` where it lands
## (a ring in its caster's ramp, a flare of its element, its cards' motes). Its path is the caster's
## trail and its streaks are motes (the projectile manager's births), so Feel keeps no dash state.
func test_a_dash_kicks_up_dust_and_lands_in_a_ring() -> void:
	const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
	var sparks: int = 1 << (ProjectilesScript.LOOK_SPARKS - 1)
	check_equal(_card(&"dash").shown_cue, &"dash_start", "dash.tres names the cue `dash_start`")
	check_equal(_card(&"dash").end_cue, &"dash_land", "and `dash_land`")
	# The dust is in the room's colours: a room is entered.
	bus.room_entered.emit(&"arena_01")
	var motes: Node = feel.motes()
	var written: int = int(motes.get(&"written"))
	bus.form_shown.emit(2, &"dash", Vector2(10, 20), Vector2.DOWN, 80.0, FROST, sparks)
	check(int(motes.get(&"written")) > written, "dust where player 3 left (motes)")
	check_equal(feel.effects_of(FeelScript.KIND_DASH), 0, "no dust flash of its own")
	check_equal(feel.effects_of(FeelScript.KIND_ARC, 2), 1, "lightning (its sparks) arcs along its way")
	check(feel.effect_info(FeelScript.KIND_ARC)["at"].is_equal_approx(Vector2(10, 20)), "from where it left")
	feel.step(1.0)
	bus.form_shown.emit(2, &"dash", Vector2(10, 20), Vector2.DOWN, 80.0, FROST, 0)
	check_equal(feel.effects_of(FeelScript.KIND_ARC), 0, "a dash with no lightning arcs nowhere")
	written = int(motes.get(&"written"))
	bus.carrier_ended.emit(2, &"dash", Vector2(60, 30), Vector2.DOWN, 1.0, FROST, sparks)
	check_equal(feel.effects_of(FeelScript.KIND_RING_OUT, 2), 1, "a ring in its caster's ramp where it landed")
	check_equal(feel.effect_info(FeelScript.KIND_RING_OUT)["look"], 0, "without its cards")
	check_equal(feel.effects_of(FeelScript.KIND_BURST, 2), 1, "an infused dash lands in a flare of its element")
	check(int(motes.get(&"written")) > written, "and throws its cards' motes")
	feel.step(1.0)
	bus.carrier_ended.emit(2, &"dash", Vector2(60, 30), Vector2.DOWN, 1.0, FROST, 0)
	check_equal(feel.effects_of(FeelScript.KIND_RING_OUT, 2), 1, "a plain dash lands in its ring")
	check_equal(feel.effects_of(FeelScript.KIND_BURST), 0, "with no flare")
	bus.carrier_ended.emit(ActorSeats.enemy(feel.actors), &"dash", Vector2(60, 30), Vector2.DOWN, 1.0, FROST, 0)
	check_equal(feel.effect_info(FeelScript.KIND_RING_OUT)["ramp"], ActorSeats.ActorsScript.RAMP_ENEMY, "an enemy's dash lands in the enemy ramp (staffs F7)")


func test_a_decoy_and_a_familiar_come_and_go() -> void:
	for id: StringName in [&"decoy", &"familiar"]:
		feel.step(1.0)
		bus.form_shown.emit(0, id, Vector2(30, 30), Vector2.RIGHT, 0.0, FROST, 0)
		check_equal(feel.effects_of(FeelScript.KIND_FALL), 1, "%s: conjured in a column" % id)
		check_equal(feel.effects_of(FeelScript.KIND_PUFF), 1, "%s: in a puff" % id)
		bus.carrier_ended.emit(0, id, Vector2(30, 30), Vector2.RIGHT, 8.0, FROST, 0)
		check_equal(feel.effects_of(FeelScript.KIND_RISE), 1, "%s: dismissed up a column" % id)


func test_an_enemys_moments_show_in_the_enemy_ramp() -> void:
	var enemy: int = ActorSeats.enemy(feel.actors)
	bus.form_shown.emit(enemy, &"teleport", Vector2(10, 10), Vector2.RIGHT, 96.0, FROST, 0)
	bus.carrier_ended.emit(enemy, &"teleport", Vector2(106, 10), Vector2.RIGHT, 1.0, FROST, 0)
	check_equal(feel.effects_of(FeelScript.KIND_RISE), 1, "an enemy's teleport leaves")
	check_equal(feel.effects_of(FeelScript.KIND_FALL), 1, "and lands, as a wizard's does")


func test_a_card_without_a_cue_plays_none() -> void:
	bus.form_shown.emit(0, &"bolt", Vector2.ZERO, Vector2.RIGHT, 0.0, FROST, 0)
	bus.carrier_ended.emit(0, &"bolt", Vector2.ZERO, Vector2.RIGHT, 5.0, FROST, 0)
	bus.carrier_ended.emit(0, &"no_such_card", Vector2.ZERO, Vector2.RIGHT, 5.0, FROST, 0)
	for kind: int in [FeelScript.KIND_RISE, FeelScript.KIND_FALL, FeelScript.KIND_RING_OUT, FeelScript.KIND_RING_IN, FeelScript.KIND_BURST]:
		check_equal(feel.effects_of(kind), 0, "nothing of kind %d" % kind)


func test_a_bad_moment_is_ignored() -> void:
	bus.carrier_ended.emit(0, &"teleport", Vector2(INF, 0.0), Vector2.RIGHT, 1.0, FROST, 0)
	bus.carrier_ended.emit(-5, &"teleport", Vector2.ZERO, Vector2.RIGHT, 1.0, FROST, 0)
	check_equal(feel.effects_of(FeelScript.KIND_FALL), 0, "no column for a point off the map or a caster that is none")


func test_a_zap_plays_its_cards_cue_as_long_as_the_zap() -> void:
	# A modifier that shows itself names its own cue (S6 item 8): `form_shown` `zap` names the zap
	# card, and its cue draws the arc in the shot's colours, for 0.25 s.
	var card: ModifierBase = registry.get_resource(&"spells", &"zap") as ModifierBase
	check_equal(card.cue, &"zap", "zap.tres names the cue `zap`")
	bus.form_shown.emit(1, &"zap", Vector2(10, 20), Vector2.RIGHT, 60.0, FROST, 0)
	check_equal(feel.effects_of(FeelScript.KIND_ARC, 1), 1, "one arc in the caster's ramp")
	var arc: Dictionary = feel.effect_info(FeelScript.KIND_ARC)
	check(arc["at"].is_equal_approx(Vector2(10, 20)), "from where it zapped")
	check_equal(arc["core"], FROST, "in its shot's colour")
	check_equal(arc["zoom"], 15, "as long as the zap: 60 px is 15 steps of 4")
	check(is_equal_approx(arc["seconds"] as float, 0.25), "a zap's seconds")


func test_a_zaps_spark_into_the_air_burns_out_sooner() -> void:
	bus.form_shown.emit(0, &"zap", Vector2.ZERO, Vector2.UP, 16.0, FROST, 0)
	check_equal(feel.effects_of(FeelScript.KIND_ARC), 1, "one spark (`if_size_upto` 22), not both parts")
	check(is_equal_approx(feel.effect_info(FeelScript.KIND_ARC)["seconds"] as float, 0.15), "0.6 of a zap's seconds, as before the cue")
	bus.form_shown.emit(0, &"zap", Vector2.ZERO, Vector2.UP, 0.0, FROST, 0)
	check_equal(feel.effects_of(FeelScript.KIND_ARC), 1, "a zap of no length shows nothing")
