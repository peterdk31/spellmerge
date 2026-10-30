extends "res://tests/support/suite.gd"
## Freezes in co-op (melee I7, docs/milestones/M2-staffs.md): a hit or a kill holds only the bodies
## in it (the attacker, the target and the shot); another player, another enemy and an unrelated
## shot run on, and the game's clock (`Engine.time_scale`) is used only for a downed player and a
## boss kill.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_feel_local_stop.gd

const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const ImpData := preload("res://content/enemies/ember_imp/ember_imp.tres")

var _world: Fixture
var _feel: FeelScript


func before_each() -> void:
	_world = Fixture.new(root)
	_feel = own(FeelScript.new()) as FeelScript
	_feel.events = _world.bus
	_feel.projectiles = _world.projectiles
	_feel.actors = _world.table
	_feel.combat = _world.combat
	_feel.drive_engine = false
	var preset: FeelPresetScript = FeelPresetScript.new()
	preset.hit_sound = &""
	_feel.preset = preset
	root.add_child(_feel)
	# Stands in for combat: a shot's hit is a hit of 5 damage, announced as combat does (`hit_landed`
	# naming the shot, then `damage_dealt`).
	_world.bus.projectile_hit.connect(func(caster: int, target: Node, at: Vector2, _tag: int, shot: int) -> void:
		_world.bus.hit_landed.emit(caster, target, 5, at, &"shot", shot)
		_world.bus.damage_dealt.emit(caster, target, 5, at))


func after_each() -> void:
	_world.free_all()


func _body(at: Vector2) -> Actor:
	return _world.actor(at, [&"health", &"hurtbox"] as Array[StringName])


## A shot of `caster` that flies on through what it hits.
func _shot(caster: Actor, from: Vector2) -> int:
	return _world.projectiles.spawn(caster.id, from, Vector2(120.0, 0.0), 3.0, 4.0, ManagerScript.LAYER_ENEMY | ManagerScript.LAYER_PLAYER, 5)


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
	check(struck, "the shot hit the target")
	check(_world.table.held_left(hitter.id) > 0.0, "the attacker is held")
	check(_world.table.held_left(target.id) > 0.0, "the target is held")
	check(_world.projectiles.freeze_left_of(mine) > 0.0, "the shot is held")
	check_equal(_world.table.held_left(other_player.id), 0.0, "another player is not held")
	check_equal(_world.table.held_left(bystander.id), 0.0, "a bystander is not held")
	check_equal(_world.projectiles.freeze_left_of(theirs), 0.0, "an unrelated shot is not held")
	var before: Vector2 = _world.projectiles.get_position_of(theirs)
	_world.projectiles.step(0.015625)
	check(_world.projectiles.get_position_of(theirs).x > before.x, "the unrelated shot flies on")
	check_equal(_feel.stop_left, 0.0, "the game's clock is not stopped")


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
	_world.bus.enemy_died.emit(killer.id, null, Vector2.ZERO, -1)
	check(_world.table.held_left(killer.id) >= _feel.cue_of(&"enemy_death").hold, "the killer is held for the kill")
	check_equal(_world.table.held_left(other.id), 0.0, "nobody else is")
	check_equal(_feel.stop_left, 0.0, "the game runs on")


func test_a_reaction_holds_its_caster_not_the_game() -> void:
	var caster: Actor = _body(Vector2.ZERO)
	var other: Actor = _body(Vector2(100.0, 0.0))
	_world.bus.reaction_triggered.emit(caster.id, &"steam", Vector2.ZERO, -1)
	var power: float = _feel.preset.reaction_power.get(&"steam", 1.0) as float
	check(_world.table.held_left(caster.id) >= _feel.preset.reaction_stop_seconds * power - 0.0001, "the caster is held for the reaction")
	check_equal(_world.table.held_left(other.id), 0.0, "nobody else is")
	check_equal(_feel.stop_left, 0.0, "the game runs on")


func test_a_reused_actor_id_starts_with_no_rest() -> void:
	var first: Actor = _body(Vector2.ZERO)
	var id: int = first.id
	_world.bus.damage_dealt.emit(ActorsScript.NONE, first, 5, Vector2.ZERO)
	check(_world.table.held_left(id) > 0.0, "a plain hit holds the body")
	root.remove_child(first)
	var second: Actor = _body(Vector2.ZERO)
	check_equal(second.id, id, "the id came back")
	_world.bus.damage_dealt.emit(ActorsScript.NONE, second, 5, Vector2.ZERO)
	check(_world.table.held_left(id) > 0.0, "the new body's first plain hit holds it")


func test_a_boss_kill_stops_the_game() -> void:
	var boss: Actor = _body(Vector2.ZERO)
	var data: EnemyBase = ImpData.duplicate() as EnemyBase
	data.boss = true
	boss.data = data
	_world.bus.enemy_died.emit(0, boss, Vector2.ZERO, -1)
	check(_feel.stop_left > 0.0, "a boss's death stops the whole game")
	var imp: Actor = _body(Vector2(40.0, 0.0))
	imp.data = ImpData
	_feel.stop_left = 0.0
	_world.bus.enemy_died.emit(0, imp, Vector2.ZERO, -1)
	check_equal(_feel.stop_left, 0.0, "an ordinary enemy's does not")


func test_a_down_still_stops_the_game() -> void:
	_world.bus.player_downed.emit(0)
	check(_feel.stop_left > 0.0, "a downed player stops the game")
	check_equal(_world.table.held_count, 0, "and holds no body of its own")


func test_a_closed_actor_loses_its_hold() -> void:
	var body: Actor = _body(Vector2.ZERO)
	var id: int = body.id
	_world.table.hold(id, 1.0)
	check_equal(_world.table.held_count, 1, "one held")
	root.remove_child(body)
	check_equal(_world.table.held_count, 0, "none when it leaves")
	check_equal(_world.table.held_left(id), 0.0, "and the id comes back free")
