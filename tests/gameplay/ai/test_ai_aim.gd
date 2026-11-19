extends "res://tests/support/suite.gd"
## Tuned enemy aim (the owner, 2026-11-19; `AimTuning`, gameplay/ai/README.md "Aim"): a profile's
## lead (0: at the target, 1: where a shot meets it, as before) and aim error, sloppier in a
## shallow room and sharper in a deep one and for an elite, both scaled by the global knobs. A test
## bot (a brain on the players' team) is never tuned.
const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")

var fx: Fixture


func before_each() -> void:
	fx = Fixture.new(root)


func after_each() -> void:
	fx.free_all()


## A tuning that changes nothing with depth (as the aim was before the tuning).
static func _flat() -> AimTuning:
	var flat := AimTuning.new()
	flat.start_lead = 1.0
	flat.start_error = 1.0
	return flat


func _profile(lead: float, accuracy: float) -> AIProfile:
	var profile: AIProfile = Fixture.exact().duplicate() as AIProfile
	profile.lead = lead
	profile.accuracy = accuracy
	return profile


## An enemy at the origin with a fire bolt, playing by `profile` under `tuning`, its wizard 200 px
## right walking down at 100 px/s.
func _enemy(profile: AIProfile, tuning: AimTuning) -> Actor:
	fx.players[0].position = Vector2(200.0, 0.0)
	fx.players[0].velocity = Vector2(0.0, 100.0)
	var body: Actor = fx.staffed_enemy([["fire", "bolt"]], Vector2.ZERO, profile)
	Fixture.ai(body).brain.aim = tuning
	return body


## Where the aim of a cast before the tuning pointed: ahead of the wizard by its flight, times `lead`.
func _old_aim(body: Actor, lead: float) -> Vector2:
	var brain: AIBrain = Fixture.ai(body).brain
	var wizard: Actor = fx.players[0]
	var point: Vector2 = wizard.global_position - body.global_position + wizard.body_offset - body.body_offset
	var sense: CastSense = body.caster.next_cast_sense(0)
	point += wizard.velocity * (point.length() / sense.speed) * lead
	check(brain != null, "it has a brain")
	return point.normalized()


func test_the_tuning_numbers() -> void:
	var tuning := AimTuning.new()
	check_equal(tuning.sharpness(1.0, false), 0.0, "the first room is the sloppiest")
	check_equal(tuning.sharpness(tuning.sharp_level, false), 1.0, "sharp at its level")
	check_equal(tuning.sharpness(9.0, false), 1.0, "and deeper")
	check_equal(tuning.sharpness(0.5, false), 0.0, "never below sloppy")
	check_equal(tuning.sharpness(NAN, false), 0.0, "a broken level is sloppy")
	var mid: float = tuning.sharpness(1.25, false)
	check(mid > 0.0 and mid < 1.0, "in between, between: %s" % mid)
	check(tuning.sharpness(1.25, true) > mid, "an elite is sharper")
	check_equal(tuning.sharpness(1.0, true), tuning.elite_sharpness, "an elite in the first room: its share of the way")
	check_equal(tuning.lead_for(0.5, 1.0), 0.5, "sharp, the profile's lead")
	check_equal(tuning.lead_for(0.5, 0.0), 0.5 * tuning.start_lead, "sloppy, its start share")
	check_equal(tuning.error_for(1.0), 1.0, "sharp, the profile's error")
	check_equal(tuning.error_for(0.0), tuning.start_error, "sloppy, its start factor")
	tuning.lead_scale = 2.0
	tuning.error_scale = 0.5
	check_equal(tuning.lead_for(0.25, 1.0), 0.5, "the global knob doubles the lead")
	check_equal(tuning.lead_for(0.8, 1.0), 1.0, "held to a full lead")
	check_equal(tuning.error_for(1.0), 0.5, "the global knob halves the error")


func test_the_shipped_tuning_starts_sloppier() -> void:
	var tuning: AimTuning = AIBrain.AIM_TUNING
	check(tuning.start_lead < 1.0 and tuning.start_error > 1.0, "early enemies lead less and err more: %s, %s" % [tuning.start_lead, tuning.start_error])
	check_equal(tuning.lead_scale, 1.0, "the global knobs ship at 1")
	check_equal(tuning.error_scale, 1.0, "the global knobs ship at 1")


func test_lead_zero_aims_where_the_target_is() -> void:
	var body: Actor = _enemy(_profile(0.0, 1.0), _flat())
	fx.run(body, 1)
	var wizard: Actor = fx.players[0]
	var at: Vector2 = (wizard.global_position + wizard.body_offset - body.global_position - body.body_offset).normalized()
	check(body.aim.distance_to(at) < 0.001, "no lead: at the wizard as it stands: %s, %s" % [body.aim, at])


func test_lead_one_aims_as_before() -> void:
	var body: Actor = _enemy(_profile(1.0, 1.0), _flat())
	fx.run(body, 1)
	var before: Vector2 = _old_aim(body, 1.0)
	check(body.aim.distance_to(before) < 0.001, "a full lead, untuned: where the shot meets it, as before: %s, %s" % [body.aim, before])
	check(body.aim.y > 0.2, "ahead of a wizard walking down")
	fx.free_all()
	fx = Fixture.new(root)
	# The shipped tuning at its sharp level is the profile as it is.
	var deep: Actor = _enemy(_profile(1.0, 1.0), AIBrain.AIM_TUNING)
	deep.room_level = AIBrain.AIM_TUNING.sharp_level
	fx.run(deep, 1)
	check(deep.aim.distance_to(_old_aim(deep, 1.0)) < 0.001, "deep, the shipped tuning leads fully")


func test_a_shallow_room_leads_less() -> void:
	var body: Actor = _enemy(_profile(1.0, 1.0), AIBrain.AIM_TUNING)
	fx.run(body, 1)
	var brain: AIBrain = Fixture.ai(body).brain
	check_equal(brain.aim_lead(), AIBrain.AIM_TUNING.start_lead, "level 1: its start share of the lead")
	check(body.aim.distance_to(_old_aim(body, AIBrain.AIM_TUNING.start_lead)) < 0.001, "and aims by it")
	check(body.aim.y < _old_aim(body, 1.0).y - 0.01, "less far ahead than a full lead")


## The largest aim error (radians) over `casts` windups of an enemy of `accuracy` in a room of
## `level`, `elite` or not, and the aims at each windup's start.
func _errors(accuracy: float, tuning: AimTuning, level: float = 1.0, elite: bool = false, steps: int = 240) -> Array:
	var body: Actor = _enemy(_profile(0.0, accuracy), tuning)
	fx.players[0].velocity = Vector2.ZERO
	body.room_level = level
	if elite:
		body.elite_card = &"fire"
	var brain: AIBrain = Fixture.ai(body).brain
	var most: float = 0.0
	var aims: Array[float] = []
	var was: int = -1
	for i in steps:
		fx.run(body, 1)
		if brain.state == AIBrain.State.WINDUP:
			var off: float = absf(body.aim.angle_to((fx.players[0].global_position + fx.players[0].body_offset) - (body.global_position + body.body_offset)))
			most = maxf(most, off)
			if was != AIBrain.State.WINDUP:
				aims.append(snappedf(body.aim.angle(), 0.00001))
		was = brain.state
	return [most, brain.aim_error_most(), aims]


func test_the_aim_error_stays_in_its_bounds_and_repeats() -> void:
	var first: Array = _errors(0.5, AIBrain.AIM_TUNING)
	var bound: float = 0.5 * AIBrain.AIM_ERROR * AIBrain.AIM_TUNING.start_error
	check(absf(float(first[1]) - bound) < 0.0001, "its widest error: the profile's times the start factor: %s, %s" % [first[1], bound])
	check(float(first[0]) > 0.001 and float(first[0]) <= bound + 0.001, "it errs, within the bound: %.4f <= %.4f" % [first[0], bound])
	check((first[2] as Array).size() >= 2, "several casts: %s" % [first[2]])
	fx.free_all()
	fx = Fixture.new(root)
	var again: Array = _errors(0.5, AIBrain.AIM_TUNING)
	check_equal(again[2], first[2], "the same fight errs the same way (seeded)")


func test_depth_and_elites_sharpen_the_aim() -> void:
	var shallow: Array = _errors(0.5, AIBrain.AIM_TUNING, 1.0, false, 2)
	fx.free_all()
	fx = Fixture.new(root)
	var mid: Array = _errors(0.5, AIBrain.AIM_TUNING, 1.25, false, 2)
	fx.free_all()
	fx = Fixture.new(root)
	var elite: Array = _errors(0.5, AIBrain.AIM_TUNING, 1.25, true, 2)
	fx.free_all()
	fx = Fixture.new(root)
	var deep: Array = _errors(0.5, AIBrain.AIM_TUNING, 2.0, false, 2)
	check(float(shallow[1]) > float(mid[1]) and float(mid[1]) > float(deep[1]), "deeper, a smaller error: %s > %s > %s" % [shallow[1], mid[1], deep[1]])
	check(float(elite[1]) < float(mid[1]), "an elite errs less than its room's others: %s < %s" % [elite[1], mid[1]])
	check(absf(float(deep[1]) - 0.5 * AIBrain.AIM_ERROR) < 0.0001, "deep, the profile's own error")


func test_the_global_knob_scales_the_error() -> void:
	var tuning: AimTuning = _flat()
	tuning.error_scale = 2.0
	var doubled: Array = _errors(0.5, tuning, 1.0, false, 2)
	check(absf(float(doubled[1]) - AIBrain.AIM_ERROR) < 0.0001, "twice the profile's error: %s" % doubled[1])
	fx.free_all()
	fx = Fixture.new(root)
	var none: AimTuning = _flat()
	none.error_scale = 0.0
	none.lead_scale = 0.0
	var body: Actor = _enemy(_profile(1.0, 0.0), none)
	fx.run(body, 1)
	var brain: AIBrain = Fixture.ai(body).brain
	check_equal(brain.aim_error_most(), 0.0, "at 0, no enemy errs")
	check_equal(brain.aim_lead(), 0.0, "nor leads")


func test_a_bot_is_not_tuned() -> void:
	var bot: Actor = fx.wizard(1, Vector2(0.0, 100.0))
	var brain := AIBrain.new()
	brain.profile = _profile(0.5, 0.5)
	brain.actor = bot
	check(not brain.warns(), "a brain driving a wizard gives no warning")
	check_equal(brain.aim_sharpness(), 1.0, "and aims sharp")
	check_equal(brain.aim_lead(), 0.5, "by its profile's lead")
	check(absf(brain.aim_error_most() - 0.5 * AIBrain.AIM_ERROR) < 0.0001, "and its profile's error")
