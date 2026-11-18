extends "res://tests/support/suite.gd"
## How often an enemy thinks (`AIController.THINK_EVERY`, performance 2026-11-17): every third tick,
## each think given the seconds since the last, a crowd spread over the ticks by actor id, and a
## boss every tick. The AI's other tests think every tick (`think_every` 1, the fixture's).
const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const ImpData := preload("res://content/enemies/ember_imp/ember_imp.tres")

const STEP: float = Fixture.STEP

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root, 1)
	_world.players[0].position = Vector2(300.0, 0.0)
	AIController.think_every = AIController.THINK_EVERY


func after_each() -> void:
	_world.free_all()


func _brain(body: Actor) -> AIBrain:
	return (body.controller as AIController).brain


func test_a_crowd_thinks_every_third_tick_spread_over_the_ticks() -> void:
	var crowd: Array[Actor] = []
	for i in 6:
		crowd.append(_world.imp(Vector2(0.0, 40.0 * i)))
	var thought: Array[int] = []
	var clocks: PackedFloat64Array = PackedFloat64Array()
	for body in crowd:
		clocks.append(_brain(body).clock)
	for tick in 3:
		_world.run_all(1)
		var n: int = 0
		for i in crowd.size():
			if _brain(crowd[i]).clock != clocks[i]:
				n += 1
				clocks[i] = _brain(crowd[i]).clock
		thought.append(n)
	check_equal(thought, [2, 2, 2] as Array[int], "a third of the crowd thinks each tick")
	_world.run_all(3 * 20)
	for body in crowd:
		check(absf(_brain(body).clock - _brain(crowd[0]).clock) <= 2.0 * STEP + 0.0001, "each think takes the time since the last: no time is lost (%f)" % _brain(body).clock)


func test_a_boss_thinks_every_tick() -> void:
	var data := ImpData.duplicate() as EnemyBase
	data.boss = true
	var boss: Actor = _world.imp(Vector2.ZERO, data)
	var before: float = _brain(boss).clock
	for tick in 3:
		_world.run_all(1)
		check(_brain(boss).clock > before, "tick %d: it thinks" % tick)
		before = _brain(boss).clock
