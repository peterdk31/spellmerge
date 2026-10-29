extends "res://tests/support/suite.gd"
## A local stop on a shot (`freeze_shot`, hit-stop in co-op, melee I7): the shot holds where it is
## and keeps its life while every other shot flies on; it thaws on time; a shot that is gone cannot
## be frozen. The manager is stepped by hand.
##
## godot --headless --path . --script res://tests/core/test_projectiles_freeze.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

const DT: float = 0.125

var mgr: ManagerScript
var bus: EventsScript
var table: ActorsScript
var expired: int = 0


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	table = own(ActorSeats.table(2, 0)) as ActorsScript
	mgr.actors = table
	mgr.events = bus
	mgr.set_bounds(Rect2(-1000.0, -1000.0, 2000.0, 2000.0))
	root.add_child(mgr)
	expired = 0
	bus.projectile_expired.connect(func(_caster: int, _at: Vector2, _tag: int) -> void: expired += 1)


func _run(steps: int) -> void:
	for _i in steps:
		mgr.step(DT)


func test_a_frozen_shot_holds_while_another_flies_on() -> void:
	var held: int = mgr.spawn(0, Vector2.ZERO, Vector2(80.0, 0.0), 5.0)
	var free: int = mgr.spawn(1, Vector2(0.0, 100.0), Vector2(80.0, 0.0), 5.0)
	check(mgr.freeze_shot(held, 0.5), "a live shot freezes")
	_run(2)
	check_equal(mgr.get_position_of(held), Vector2.ZERO, "the frozen shot has not moved")
	check_equal(mgr.get_position_of(free), Vector2(20.0, 100.0), "the other shot flew on")
	check(mgr.freeze_left_of(held) > 0.0, "it is still held")


func test_a_shot_thaws_and_flies_on() -> void:
	var slot: int = mgr.spawn(0, Vector2.ZERO, Vector2(80.0, 0.0), 5.0)
	mgr.freeze_shot(slot, 0.25)
	_run(2)
	check_equal(mgr.freeze_left_of(slot), 0.0, "the stop is over after its seconds")
	check_equal(mgr.get_position_of(slot), Vector2.ZERO, "and the shot has not moved yet")
	_run(2)
	check_equal(mgr.get_position_of(slot), Vector2(20.0, 0.0), "then it flies")


func test_a_stop_does_not_use_up_the_shots_life() -> void:
	var slot: int = mgr.spawn(0, Vector2.ZERO, Vector2(80.0, 0.0), 0.5)
	mgr.freeze_shot(slot, 0.5)
	_run(6)
	check_equal(expired, 0, "held for the whole of its life, it has not expired")
	_run(6)
	check_equal(expired, 1, "it expires when its life is spent after the stop")


func test_the_longer_stop_stands() -> void:
	var slot: int = mgr.spawn(0, Vector2.ZERO, Vector2(80.0, 0.0), 5.0)
	mgr.freeze_shot(slot, 0.5)
	mgr.freeze_shot(slot, 0.25)
	check_equal(mgr.freeze_left_of(slot), 0.5, "a shorter stop does not cut it")


func test_a_frozen_orbit_shot_holds_its_place() -> void:
	var slot: int = mgr.spawn_orbit(0, 40.0, 0.0, 4.0, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, 0, Vector2.ZERO)
	_run(1)
	var at: Vector2 = mgr.get_position_of(slot)
	mgr.freeze_shot(slot, 0.25)
	_run(2)
	check_equal(mgr.get_position_of(slot), at, "the orbit shot does not turn while frozen")
	_run(2)
	check(mgr.get_position_of(slot) != at, "and turns again after")


func test_a_gone_shot_cannot_be_frozen_and_a_new_one_starts_free() -> void:
	check(not mgr.freeze_shot(-1, 0.5), "no slot")
	var slot: int = mgr.spawn(0, Vector2.ZERO, Vector2(80.0, 0.0), 5.0)
	mgr.freeze_shot(slot, 5.0)
	mgr.clear()
	check(not mgr.freeze_shot(slot, 0.5), "a cleared shot is gone")
	var again: int = mgr.spawn(0, Vector2.ZERO, Vector2(80.0, 0.0), 5.0)
	check_equal(mgr.freeze_left_of(again), 0.0, "a shot in a reused slot is not held")
	check(not mgr.freeze_shot(again, 0.0), "a stop of no seconds is no stop")


func test_a_frozen_shot_hits_nothing_until_it_thaws() -> void:
	var target: Node2D = own(Node2D.new()) as Node2D
	root.add_child(target)
	target.position = Vector2(2.0, 0.0)
	mgr.add_target(target, 6.0, ManagerScript.LAYER_ENEMY)
	var hits: Array[int] = [0]
	bus.projectile_hit.connect(func(_c: int, _t: Node, _p: Vector2, _tag: int) -> void: hits[0] += 1)
	var slot: int = mgr.spawn(0, Vector2.ZERO, Vector2(160.0, 0.0), 5.0, 4.0, ManagerScript.LAYER_ENEMY)
	mgr.freeze_shot(slot, 0.25)
	_run(2)
	check_equal(hits[0], 0, "a frozen shot touching a target hits nothing")
	_run(2)
	check_equal(hits[0], 1, "it hits once it thaws")


func test_frozen_homing_returning_and_lingering_shots_neither_move_nor_expire() -> void:
	var homing: int = mgr.spawn(0, Vector2.ZERO, Vector2(80.0, 0.0), 0.25)
	mgr.set_homing(homing, 4.0, 200.0)
	var back: int = mgr.spawn(0, Vector2(0.0, 50.0), Vector2(80.0, 0.0), 0.25)
	mgr.set_return(back)
	var linger: int = mgr.spawn(0, Vector2(0.0, 100.0), Vector2(80.0, 0.0), 0.25)
	mgr.set_linger(linger, 1.0)
	var starts: Array[Vector2] = [Vector2.ZERO, Vector2(0.0, 50.0), Vector2(0.0, 100.0)]
	var slots: Array[int] = [homing, back, linger]
	for slot in slots:
		mgr.freeze_shot(slot, 0.5)
	_run(3)
	for i in 3:
		check_equal(mgr.get_position_of(slots[i]), starts[i], "frozen shot %d has not moved" % i)
	check_equal(expired, 0, "none has expired")
