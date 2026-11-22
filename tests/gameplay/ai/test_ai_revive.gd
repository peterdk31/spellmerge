extends "res://tests/support/suite.gd"
## The revive behaviour (gameplay/ai/behaviours/revive.gd): a test bot's brain (the bot profile,
## `revives` 1) walks to a downed teammate in a quiet room and stands beside it, within the coop
## rule's revive range, for longer than a revive takes; it goes with a fight on when no foe is near
## the one downed, and never walks into a crowd round it; a profile with `revives` 0 (every enemy's)
## never goes. A world of its own (tests/gameplay/ai/ai_fixture.gd): two wizards, the brain driving
## the first with a spare intent, its body moved by hand at a walk; the enemies stand, unstepped.
const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const CoopScript := preload("res://gameplay/coop/coop.gd")
const ReviveScript := preload("res://gameplay/ai/behaviours/revive.gd")
const BOT_PROFILE: AIProfile = preload("res://bench/bots/bot_profile.tres")

## The bot's walk (pixels a second) as the test moves it.
const WALK: float = 80.0
const BOT_AT: Vector2 = Vector2(100.0, 100.0)
const MATE_AT: Vector2 = Vector2(300.0, 100.0)

var _world: Fixture
var _brain: AIBrain
var _intent: ActorIntent
## What the brain did in the last drive, a line each time its behaviour changed (`_note`): shown in
## a failed check's message, so a failure says why on its own (a flaky one, 2026-11-20, left only
## "failed in its batch": its log was gone with the machine that ran it).
var _trace: PackedStringArray = PackedStringArray()
var _traced: String = ""
## The most lines a trace keeps (a brain that changed its mind every step would make a message of
## tens of kilobytes); the rest are counted.
const TRACE_LINES: int = 24
var _untraced: int = 0


func before_each() -> void:
	_world = Fixture.new(root, 2)
	_world.players[0].position = BOT_AT
	_world.players[1].position = MATE_AT
	# Downed as its Downed component downs it at 0 health (actors G7).
	_world.players[1].set_down(true)
	_brain = AIBrain.new()
	_intent = ActorIntent.new()


func after_each() -> void:
	_world.free_all()


## `steps` steps of the brain driving the bot with `profile`: it thinks, its body walks by the
## intent. Returns the longest run of steps in a row it stood within Coop's revive range of the one
## downed (Coop drains a revive that is left, so only a run in a row brings it back).
func _drive(profile: AIProfile, steps: int) -> int:
	_brain.setup(_world.players[0], profile, 4111)
	_trace.clear()
	_traced = ""
	_untraced = 0
	var run: int = 0
	var longest: int = 0
	var bot: Actor = _world.players[0]
	for i in steps:
		_world.projectiles.step(Fixture.STEP)
		_intent.begin_step()
		_brain.think(Fixture.STEP, _intent)
		bot.position += _intent.move.limit_length(1.0) * WALK * Fixture.STEP
		_note(i)
		run = run + 1 if bot.position.distance_to(MATE_AT) <= CoopScript.REVIVE_RANGE else 0
		longest = maxi(longest, run)
	return longest


## How many steps of `steps` the brain chose to revive.
func _revive_steps(profile: AIProfile, steps: int) -> int:
	_brain.setup(_world.players[0], profile, 4111)
	_trace.clear()
	_traced = ""
	_untraced = 0
	var chosen: int = 0
	var bot: Actor = _world.players[0]
	for i in steps:
		_world.projectiles.step(Fixture.STEP)
		_intent.begin_step()
		_brain.think(Fixture.STEP, _intent)
		bot.position += _intent.move.limit_length(1.0) * WALK * Fixture.STEP
		_note(i)
		if _brain.behaviour != null and _brain.behaviour.name() == "revive":
			chosen += 1
	return chosen


## Notes step `step` in the trace when the brain's behaviour or target changed: the step, the
## behaviour, whether it has a target, the bot's place and its health.
func _note(step: int) -> void:
	var doing: String = _brain.behaviour.name() if _brain.behaviour != null else "none"
	var now: String = "%s%s" % [doing, " (target)" if _brain.target != null else ""]
	if now == _traced:
		return
	_traced = now
	if _trace.size() >= TRACE_LINES:
		_untraced += 1
		return
	_trace.append("step %d: %s at %s, health %.2f" % [step, now, _world.players[0].position, _brain.health_fraction])


## The last drive's trace, for a failed check's message.
func _why() -> String:
	var more: String = "; and %d changes more" % _untraced if _untraced > 0 else ""
	return "; what it did: " + ("; ".join(_trace) if not _trace.is_empty() else "nothing") + more


func test_it_stands_well_inside_the_revive_range() -> void:
	check(ReviveScript.NEAR < CoopScript.REVIVE_RANGE * 0.5, "NEAR (%.0f) is well inside Coop's REVIVE_RANGE (%.0f)" % [ReviveScript.NEAR, CoopScript.REVIVE_RANGE])


func test_in_a_quiet_room_it_walks_to_the_downed_mate_and_stays() -> void:
	# 200 px at 80 px/s is 2.5 s; then a revive's hold (Coop's REVIVE_HOLD_TIME) and more.
	var steps: int = int((2.5 + CoopScript.REVIVE_HOLD_TIME + 1.5) / Fixture.STEP)
	var near: int = _drive(BOT_PROFILE, steps)
	var hold: int = int(CoopScript.REVIVE_HOLD_TIME / Fixture.STEP)
	check(near >= hold + 4, "it stood in revive range long enough to revive (%d steps, needs %d)%s" % [near, hold, _why()])
	var end: Vector2 = _world.players[0].position
	check(end.distance_to(MATE_AT) <= ReviveScript.NEAR + 2.0, "it stands beside the mate (at %s)%s" % [end, _why()])


func test_with_a_lone_enemy_far_off_it_still_revives() -> void:
	_world.imp(Vector2(100.0, 400.0))
	var steps: int = int(6.0 / Fixture.STEP)
	var near: int = _drive(BOT_PROFILE, steps)
	check(_brain.target != null, "the bot has a target (the imp)" + _why())
	check(near >= int(CoopScript.REVIVE_HOLD_TIME / Fixture.STEP), "it went to the mate with a fight on (%d steps in range)%s" % [near, _why()])


func test_it_does_not_walk_into_a_crowd_to_revive() -> void:
	for way: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.RIGHT]:
		_world.imp(MATE_AT + way * 40.0)
	var chosen: int = _revive_steps(BOT_PROFILE, int(4.0 / Fixture.STEP))
	check_equal(chosen, 0, "steps it chose to revive with foes round the mate" + _why())


## Low after a fight, it still revives: with no foe left nothing can down it beside the one downed
## (playtest, 2026-11-20: a bot under LOW walked on to the next fight and left its teammates down).
func test_low_with_the_fight_over_it_still_revives() -> void:
	var health: Health = _world.players[0].health
	health.health = health.max_health * ReviveScript.LOW * 0.5
	var steps: int = int((2.5 + CoopScript.REVIVE_HOLD_TIME + 1.5) / Fixture.STEP)
	var near: int = _drive(BOT_PROFILE, steps)
	check(near >= int(CoopScript.REVIVE_HOLD_TIME / Fixture.STEP), "it stood in revive range long enough to revive (%d steps)%s" % [near, _why()])


func test_low_with_a_fight_on_it_does_not_go() -> void:
	_world.imp(Vector2(100.0, 400.0))
	var health: Health = _world.players[0].health
	health.health = health.max_health * ReviveScript.LOW * 0.5
	check_equal(_revive_steps(BOT_PROFILE, int(4.0 / Fixture.STEP)), 0, "steps it chose to revive, low with a foe about" + _why())


func test_a_profile_that_does_not_revive_never_goes() -> void:
	var enemy_like: AIProfile = BOT_PROFILE.duplicate() as AIProfile
	enemy_like.revives = 0.0
	check_equal(_revive_steps(enemy_like, int(4.0 / Fixture.STEP)), 0, "steps it chose to revive" + _why())
	check_equal(_world.players[0].position, BOT_AT, "it stayed where it was (no target, nothing to do)")


func test_enemies_never_revive() -> void:
	check_equal(AIProfile.fallback().revives, 0.0, "the fallback profile's revives")
	check_equal(Fixture.exact().revives, 0.0, "the AI tests' enemy profile's revives")
	var enemies: Array[Resource] = _world.registry.call("get_all", &"enemies")
	check(not enemies.is_empty(), "the registry lists the enemies")
	for data: Resource in enemies:
		var enemy: EnemyBase = data as EnemyBase
		if enemy == null:
			continue
		check_equal(enemy.profile_or_fallback().revives, 0.0, "%s's profile revives" % enemy.id)
		for phase: EnemyPhase in enemy.phases:
			if phase != null and phase.profile != null:
				check_equal(phase.profile.revives, 0.0, "a phase of %s revives" % enemy.id)


## A sense of a bolt that reaches 200 px and deals `damage`, winding up `wind_up`.
func _bolt(damage: float, wind_up: float) -> CastSense:
	var sense := CastSense.new()
	sense.empty = false
	sense.reach = 200.0
	sense.damage = damage
	sense.wind_up = wind_up
	return sense


func test_while_reviving_it_fires_only_what_keeps_it_there() -> void:
	# The brain presses on toward its target through a wind-up or a channel (`press_on`), which
	# would walk it out of the revive's range: those are left, as is a cast that moves it.
	var imp: Actor = _world.imp(Vector2(100.0, 250.0))
	_brain.setup(_world.players[0], BOT_PROFILE, 4111)
	_brain.target = imp
	_brain.distance = 150.0
	_brain.line_clear = true
	_brain.staff_count = 3
	var held: CastSense = _bolt(40.0, 0.0)
	held.repeats_held = true
	_brain.senses = [_bolt(30.0, 0.5), held, _bolt(10.0, 0.0), null]
	_brain.ready = PackedByteArray([1, 1, 1, 0])
	_brain.holding = PackedByteArray([0, 0, 0, 0])
	check_equal(ReviveScript.fire_pick(_brain), 2, "the plain bolt, not the wind-up nor the held one")
	_brain.senses[2].moves_caster = true
	check_equal(ReviveScript.fire_pick(_brain), -1, "nothing: the last moves its caster")
	_brain.senses[0].wind_up = 0.0
	check_equal(ReviveScript.fire_pick(_brain), 0, "the bolt with no wind-up")


func test_two_runs_go_the_same() -> void:
	var steps: int = int(3.0 / Fixture.STEP)
	_drive(BOT_PROFILE, steps)
	var first: Vector2 = _world.players[0].position
	_world.players[0].position = BOT_AT
	_drive(BOT_PROFILE, steps)
	check_equal(_world.players[0].position, first, "the same walk on a second run" + _why())
