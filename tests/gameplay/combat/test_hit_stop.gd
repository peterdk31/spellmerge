extends "res://tests/support/suite.gd"
## Hit-stop, the game's rule (gameplay/combat/hit_stop.gd, online-ready N4; before it, Feel's): a
## hit or a kill holds only the bodies in it (the attacker, the target and the shot); another
## player, another enemy and an unrelated shot run on. A plain hit does not hold a body that still
## rests from its last hold. Only a downed player and a boss kill stand the whole game still, for a
## number of ticks (`Sim.hold`). No Feel here: the holds are the same without it.
##
## godot --headless --path . --script res://tests/gameplay/combat/test_hit_stop.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ImpData := preload("res://content/enemies/ember_imp/ember_imp.tres")

const STEP: float = 1.0 / 60.0

var _world: Fixture
var _stop: HitStop
var _sim: Sim


func before_each() -> void:
	_world = Fixture.new(root)
	_stop = _world.combat.hit_stop
	# The game-wide stop goes to a sim of the test's, not the game's Tick.
	_sim = Sim.new()
	_stop.sim = _sim
	# A shot's hit is a hit of 5 through Combat, by that shot (as a spell's hit is: Combat's slot is
	# the shot while it is dealt), so its stop is Combat's own.
	_world.bus.projectile_hit.connect(func(caster: int, target: Node, _at: Vector2, _tag: int, shot: int) -> void:
		_world.combat.set(&"_slot", shot)
		_world.combat.hit(caster, target, 5.0)
		_world.combat.set(&"_slot", -1))


func after_each() -> void:
	_world.free_all()


## An actor that acts (something drives it, so it is stepped: a still body takes no hold; props W2).
func _body(at: Vector2) -> Actor:
	return _world.actor(at, [&"health", &"hurtbox"] as Array[StringName], Fixture.Scripted.new())


## A shot of `caster` that flies on through what it hits.
func _shot(caster: Actor, from: Vector2) -> int:
	return _world.projectiles.spawn(caster.id, from, Vector2(120.0, 0.0), 3.0, 4.0, ManagerScript.LAYER_ENEMY | ManagerScript.LAYER_PLAYER, 5)


func _cue(id: StringName) -> CueBase:
	return _world.registry.call(&"get_resource", &"cues", id) as CueBase


func test_one_players_hit_holds_only_its_own_bodies_and_shot() -> void:
	var hitter: Actor = _body(Vector2(-60.0, 0.0))
	var target: Actor = _body(Vector2(0.0, 0.0))
	var other_player: Actor = _body(Vector2(-60.0, 300.0))
	var bystander: Actor = _body(Vector2(0.0, -300.0))
	# Teams: the hitter's shot hits what is not its own team.
	_world.table.set_driver(hitter.id, ActorsScript.TEAM_WIZARDS, 0)
	_world.table.set_driver(other_player.id, ActorsScript.TEAM_WIZARDS, 1)
	var mine: int = _shot(hitter, Vector2(-40.0, 0.0))
	var theirs: int = _shot(other_player, Vector2(-40.0, 300.0))
	var struck: bool = false
	for _i in 30:
		_world.projectiles.step(0.015625)
		if _world.table.held_left(target.id) > 0.0:
			struck = true
			break
	check(struck, "the shot hit the target (Combat's hit, no Feel)")
	check(_world.table.held_left(hitter.id) > 0.0, "the attacker is held")
	check(_world.table.held_left(target.id) > 0.0, "the target is held")
	check(_world.projectiles.freeze_left_of(mine) > 0.0, "the shot is held")
	check_equal(_world.table.held_left(other_player.id), 0.0, "another player is not held")
	check_equal(_world.table.held_left(bystander.id), 0.0, "a bystander is not held")
	check_equal(_world.projectiles.freeze_left_of(theirs), 0.0, "an unrelated shot is not held")
	var before: Vector2 = _world.projectiles.get_position_of(theirs)
	_world.projectiles.step(0.015625)
	check(_world.projectiles.get_position_of(theirs).x > before.x, "the unrelated shot flies on")
	check_equal(_sim.hold_left, 0, "the game does not stand still")


func test_a_hits_stop_is_its_kinds() -> void:
	var a: Actor = _body(Vector2.ZERO)
	var b: Actor = _body(Vector2(100.0, 0.0))
	var c: Actor = _body(Vector2(200.0, 0.0))
	_stop.hit(ActorsScript.NONE, a.id, &"shot", -1)
	_stop.hit(ActorsScript.NONE, b.id, &"swing", -1)
	_stop.hit(ActorsScript.NONE, c.id, &"status", -1)
	var d: Actor = _body(Vector2(300.0, 0.0))
	var e: Actor = _body(Vector2(400.0, 0.0))
	var f: Actor = _body(Vector2(500.0, 0.0))
	_stop.hit(ActorsScript.NONE, d.id, &"ray", -1)
	_stop.hit(ActorsScript.NONE, e.id, &"burst", -1)
	_stop.hit(ActorsScript.NONE, f.id, &"new_kind", -1)
	check(is_equal_approx(_world.table.held_left(a.id), HitStop.SECONDS), "a shot's hit holds SECONDS")
	# The melee playground's 0.05 s (owner, 2026-10-29).
	check(is_equal_approx(_world.table.held_left(b.id), 0.05), "a swing's a little longer (%f)" % _world.table.held_left(b.id))
	check_equal(_world.table.held_left(c.id), 0.0, "a status tick holds nothing")
	check(_world.table.held_left(d.id) > 0.0 and _world.table.held_left(d.id) < HitStop.SECONDS, "a beam's shorter")
	check(_world.table.held_left(e.id) > HitStop.SECONDS, "a burst's longer")
	check(is_equal_approx(_world.table.held_left(f.id), HitStop.SECONDS), "a kind not listed as a shot's")


func test_a_plain_hit_does_not_hold_a_resting_body_until_its_rest_is_over() -> void:
	var body: Actor = _body(Vector2.ZERO)
	_stop.hit(ActorsScript.NONE, body.id, &"shot", -1)
	check(_world.table.held_left(body.id) > 0.0, "the first hit holds it")
	# Its own steps spend the hold and then the rest.
	var steps: int = 0
	while _world.table.held_left(body.id) > 0.0 and steps < 100:
		body.step(STEP)
		steps += 1
	_stop.hit(ActorsScript.NONE, body.id, &"shot", -1)
	check_equal(_world.table.held_left(body.id), 0.0, "a plain hit in its rest does not hold it")
	_stop.killed(ActorsScript.NONE, null, -1)
	for _i in ceili((HitStop.SECONDS + HitStop.REST) / STEP) + 1:
		body.step(STEP)
	_stop.hit(ActorsScript.NONE, body.id, &"shot", -1)
	check(_world.table.held_left(body.id) > 0.0, "after its rest, a plain hit holds it again")


## A stream of plain hits on one body holds it now and then, never most of the time (its rest).
func test_a_stream_of_hits_holds_a_body_under_a_third_of_the_time() -> void:
	var body: Actor = _body(Vector2.ZERO)
	var stopped: int = 0
	for _i in 256:
		_stop.hit(ActorsScript.NONE, body.id, &"shot", -1)
		if _world.table.held_left(body.id) > 0.0:
			stopped += 1
		body.step(STEP)
	check(float(stopped) / 256.0 < 0.3, "held under 30%% of the time (was %.2f)" % (float(stopped) / 256.0))
	check(stopped > 0, "and still now and then")


func test_two_downs_do_not_stack() -> void:
	_stop.downed()
	var down: int = _sim.hold_left
	check(down > 0, "a down stands the game still")
	_stop.downed()
	check_equal(_sim.hold_left, down, "a second one does not add to it")
	_sim.hold_left = 2
	_stop.downed()
	check_equal(_sim.hold_left, down, "and one later starts it over")


func test_a_held_actor_does_nothing_and_the_others_step_on() -> void:
	var held: Actor = _body(Vector2.ZERO)
	var free: Actor = _body(Vector2(50.0, 0.0))
	_world.table.hold(held.id, 0.125)
	held.intent.pressed_bits = 5
	free.intent.pressed_bits = 5
	held.step(0.0625)
	free.step(0.0625)
	check_equal(held.intent.pressed_bits, 5, "a held actor's presses wait")
	check_equal(free.intent.pressed_bits, 0, "a free actor spends its presses")
	held.step(0.0625)
	check(_world.table.held_left(held.id) == 0.0 and _world.table.held_count == 0, "the hold ran out")
	held.step(0.0625)
	check_equal(held.intent.pressed_bits, 0, "then it steps again")


func test_a_held_actors_looks_show_the_moment_it_was_stopped_then_hold_still() -> void:
	# What holds it (a hit, a slam's impact) comes after its own step, so the stop must show that
	# moment: its looks step once, with no time passing, then not again until it runs on.
	var held: Actor = _body(Vector2.ZERO)
	var probe := StepProbe.new()
	held.add_look(probe)
	held.step(0.0625)
	check_equal(probe.steps, [0.0625], "a free actor's looks step with it")
	_world.table.hold(held.id, 0.125)
	held.step(0.0625)
	check_equal(probe.steps, [0.0625, 0.0], "held, they catch up once with no time")
	held.step(0.0625)
	check_equal(probe.steps.size(), 2, "and stand still for the rest of the stop")
	held.step(0.0625)
	check_equal(probe.steps.size(), 3, "then step on")
	_world.table.hold(held.id, 0.125)
	held.step(0.0625)
	check_equal(probe.steps.back(), 0.0, "a new stop catches up again")


## A look that notes each step's time.
class StepProbe:
	extends ActorLook
	var steps: Array[float] = []

	func step(delta: float) -> void:
		steps.append(delta)


func test_a_kill_holds_its_killer_not_the_game() -> void:
	var killer: Actor = _body(Vector2.ZERO)
	var other: Actor = _body(Vector2(100.0, 0.0))
	_stop.killed(killer.id, null, -1)
	check(_world.table.held_left(killer.id) >= _cue(&"enemy_death").hold, "the killer is held for the kill")
	check_equal(_world.table.held_left(other.id), 0.0, "nobody else is")
	check_equal(_sim.hold_left, 0, "the game runs on")


func test_a_reaction_holds_its_caster_not_the_game_once_in_a_while() -> void:
	var caster: Actor = _body(Vector2.ZERO)
	var other: Actor = _body(Vector2(100.0, 0.0))
	_stop.reaction(caster.id, &"steam", -1)
	# A reaction with no cue of its own plays the plain `reaction` cue.
	var cue: CueBase = _cue(&"reaction")
	check(_world.table.held_left(caster.id) >= cue.hold * cue.power - 0.0001, "the caster is held for the reaction")
	check_equal(_world.table.held_left(other.id), 0.0, "nobody else is")
	check_equal(_sim.hold_left, 0, "the game runs on")
	# The same reaction again soon holds nobody; after REACTION_REPEAT of Combat's steps it does.
	_stop.reaction(other.id, &"steam", -1)
	check_equal(_world.table.held_left(other.id), 0.0, "the same reaction soon after holds nothing")
	for _i in roundi(CueBase.REACTION_REPEAT / STEP):
		_world.combat.step(STEP)
	_stop.reaction(other.id, &"steam", -1)
	check(_world.table.held_left(other.id) > 0.0, "later it holds again")


func test_a_reused_actor_id_starts_with_no_rest() -> void:
	var first: Actor = _body(Vector2.ZERO)
	var id: int = first.id
	_stop.hit(ActorsScript.NONE, id, &"shot", -1)
	check(_world.table.held_left(id) > 0.0, "a plain hit holds the body")
	root.remove_child(first)
	var second: Actor = _body(Vector2.ZERO)
	check_equal(second.id, id, "the id came back")
	_stop.hit(ActorsScript.NONE, id, &"shot", -1)
	check(_world.table.held_left(id) > 0.0, "the new body's first plain hit holds it")


func test_a_boss_kill_stands_the_game_still_for_its_ticks() -> void:
	var boss: Actor = _body(Vector2.ZERO)
	var data: EnemyBase = ImpData.duplicate() as EnemyBase
	data.boss = true
	boss.data = data
	_stop.killed(0, boss, -1)
	check_equal(_sim.hold_left, roundi(_cue(&"boss_death").stop_game * 60.0), "a boss's death stands the whole game still")
	var imp: Actor = _body(Vector2(40.0, 0.0))
	imp.data = ImpData
	_sim.hold_left = 0
	_stop.killed(0, imp, -1)
	check_equal(_sim.hold_left, 0, "an ordinary enemy's does not")


func test_a_down_stands_the_game_still() -> void:
	_world.bus.player_downed.emit(0)
	check_equal(_sim.hold_left, roundi(_cue(&"player_downed").stop_game * 60.0), "a downed player stands the game still (Combat hears it)")
	check_equal(_world.table.held_count, 0, "and holds no body of its own")


func test_a_parry_and_a_slams_strike_hold_their_caster() -> void:
	var parrier: Actor = _body(Vector2.ZERO)
	var slammer: Actor = _body(Vector2(100.0, 0.0))
	_world.projectiles.impact_form = &"swing"
	_world.bus.shot_blocked.emit(parrier.id, Vector2.ZERO, 0, -1)
	_world.projectiles.impact_form = &""
	check(_world.table.held_left(parrier.id) >= _cue(&"parry").hold - 0.0001, "a swing's block holds the parrier")
	_world.bus.carrier_ended.emit(slammer.id, &"slam", Vector2.ZERO, Vector2.RIGHT, 20.0, Color.WHITE, 0)
	check(_world.table.held_left(slammer.id) >= _cue(&"slam").hold - 0.0001, "a slam's strike holds the slammer")


func test_a_cues_holds_and_game_stop_are_its_numbers() -> void:
	var caster: Actor = _body(Vector2.ZERO)
	var other: Actor = _body(Vector2(100.0, 0.0))
	var target: Actor = _body(Vector2(200.0, 0.0))
	var cue := CueBase.new()
	cue.hold = 0.05
	cue.hold_target = 0.07
	cue.stop_game = 0.1
	cue.power = 2.0
	# Its content, as the registry would give it.
	_stop.get(&"_cues")[&"test_cue"] = cue
	_stop.cue(&"test_cue", caster.id, target.id)
	check(is_equal_approx(_world.table.held_left(caster.id), 0.1), "the caster held, times its power")
	check(is_equal_approx(_world.table.held_left(target.id), 0.14), "the target held, times its power")
	check_equal(_world.table.held_left(other.id), 0.0, "nobody else")
	check_equal(_sim.hold_left, 6, "the whole game stands still 0.1 s: 6 ticks")


func test_a_closed_actor_loses_its_hold() -> void:
	var body: Actor = _body(Vector2.ZERO)
	var id: int = body.id
	_world.table.hold(id, 1.0, HitStop.REST)
	check(_world.table.held_count == 1 and _world.table.resting_count == 1, "one held and resting")
	root.remove_child(body)
	check(_world.table.held_count == 0 and _world.table.resting_count == 0, "none when it leaves")
	check_equal(_world.table.held_left(id), 0.0, "and the id comes back free")


## The rule plays the cues of the moments it hears; a card's cast, shown and wind cues are Feel's
## alone, so none of them may hold (it would hold in Feel's old way only, which is gone).
func test_no_cast_shown_or_wind_cue_holds() -> void:
	var cards: Array = _world.registry.call(&"get_all", &"spells") as Array
	check(not cards.is_empty(), "the cards are found")
	for card: Variant in cards:
		if not card is FormBase:
			continue
		var form: FormBase = card as FormBase
		for id: StringName in [form.cast_cue, form.shown_cue, form.wind_cue]:
			var cue: CueBase = _cue(id)
			if cue == null:
				continue
			check(cue.hold <= 0.0 and cue.hold_target <= 0.0 and cue.stop_game <= 0.0, "%s's cue %s holds, but nothing plays its hold (gameplay/combat/hit_stop.gd)" % [form.id, id])
