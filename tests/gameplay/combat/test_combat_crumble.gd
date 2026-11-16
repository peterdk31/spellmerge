extends "res://tests/support/suite.gd"
## A body that crumbles (boss plan OB13: an add whose caller died, `crumble_requested`): Combat takes
## its health and tells its death as any other, nobody's kill, with no hit; protection does not keep
## it; a body something downs instead (a wizard) and one not registered are left alone.
##
## godot --headless --path . --script res://tests/support/run.gd -- res://tests/gameplay/combat/test_combat_crumble.gd
const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")

var fx: Fixture
var deaths: Array = []
var hits: int = 0
var kills: int = 0


func before_each() -> void:
	fx = Fixture.new(root)
	deaths.clear()
	hits = 0
	kills = 0
	fx.bus.enemy_died.connect(func(killer: int, enemy: Node, _at: Vector2, shot: int) -> void: deaths.append([killer, enemy, shot]))
	fx.bus.damage_dealt.connect(func(_c: int, _t: Node, _a: float, _at: Vector2) -> void: hits += 1)
	fx.bus.kill_landed.connect(func(_c: int, _t: Node, _at: Vector2, _tag: int, _shot: int) -> void: kills += 1)


func after_each() -> void:
	fx.free_all()


func test_a_body_crumbles_as_a_death_of_nobodys() -> void:
	var imp: Actor = fx.imp(Vector2(40.0, 0.0))
	imp.health.protect(5.0)
	fx.bus.crumble_requested.emit(imp.id)
	check(imp.is_dying(), "it dies, protected or not")
	check_equal(imp.health.health, 0.0, "its health gone")
	check_equal(deaths, [[-1, imp, -1]], "its death told once, nobody's, with no shot")
	check_equal(hits, 0, "no damage dealt")
	check_equal(kills, 0, "no kill landed")
	fx.bus.crumble_requested.emit(imp.id)
	check_equal(deaths.size(), 1, "a dead body crumbles once")


func test_a_downable_body_and_an_unknown_id_do_not_crumble() -> void:
	var wizard: Actor = fx.players[0]
	fx.bus.crumble_requested.emit(wizard.id)
	check(not wizard.is_dying() and wizard.health.health > 0.0, "a wizard is downed, never crumbled")
	fx.bus.crumble_requested.emit(900)
	fx.bus.crumble_requested.emit(-1)
	check_equal(deaths.size(), 0, "nothing else dies")
