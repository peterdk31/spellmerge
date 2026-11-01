extends "res://tests/support/suite.gd"
## What an AI dodges (enemy AI AI3, docs/milestones/M2-enemy-ai.md): `Projectiles.threat` finds
## the shot of another team that will come within a radius of a point soonest, and the way off
## its line. Enemies at ids 0-6, wizards at 7-10, as in test_projectiles_actors.gd.
##
## godot --headless --path . --script res://tests/core/test_projectiles_threat.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

const IMP: int = 2
const OTHER_IMP: int = 3
const WIZ: int = 7

var mgr: ManagerScript


func before_each() -> void:
	var bus := own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	mgr.actors = own(ActorSeats.table(4, 7)) as ActorsScript
	mgr.events = bus
	mgr.set_bounds(Rect2(-1000.0, -1000.0, 2000.0, 2000.0))
	root.add_child(mgr)


func test_nothing_coming() -> void:
	check_equal(mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP), -1.0, "no shot, no threat")
	check_equal(mgr.threat_slot, -1, "and no slot")


func test_a_shot_coming_straight() -> void:
	var slot: int = mgr.spawn(WIZ, Vector2(-200.0, 0.0), Vector2(200.0, 0.0), 3.0, 4.0, ManagerScript.ACTOR_LAYERS)
	var when: float = mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP)
	check(absf(when - 1.0) < 0.1, "a wizard's shot 200 px away at 200 px/s arrives in about 1 s: %s" % when)
	check_equal(mgr.threat_slot, slot, "that shot")
	check(absf(mgr.threat_away.dot(Vector2.RIGHT)) < 0.01 and is_equal_approx(mgr.threat_away.length(), 1.0), "the way off is across its line: %s" % mgr.threat_away)


func test_the_side_it_is_already_on() -> void:
	mgr.spawn(WIZ, Vector2(-200.0, 0.0), Vector2(200.0, 0.0), 3.0, 4.0, ManagerScript.ACTOR_LAYERS)
	mgr.threat(Vector2(0.0, 6.0), 10.0, ActorsScript.TEAM_ENEMIES, IMP)
	check(mgr.threat_away.y > 0.9, "a body a little below the line steps further down: %s" % mgr.threat_away)
	mgr.threat(Vector2(0.0, -6.0), 10.0, ActorsScript.TEAM_ENEMIES, IMP)
	check(mgr.threat_away.y < -0.9, "and one above steps up: %s" % mgr.threat_away)


func test_shots_that_miss_or_fly_away_are_no_threat() -> void:
	mgr.spawn(WIZ, Vector2(-200.0, 100.0), Vector2(200.0, 0.0), 3.0, 4.0, ManagerScript.ACTOR_LAYERS)
	mgr.spawn(WIZ, Vector2(50.0, 0.0), Vector2(200.0, 0.0), 3.0, 4.0, ManagerScript.ACTOR_LAYERS)
	check_equal(mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP), -1.0, "one passes far off, one flies away")


func test_too_far_or_dying_first() -> void:
	mgr.spawn(WIZ, Vector2(-900.0, 0.0), Vector2(200.0, 0.0), 10.0, 4.0, ManagerScript.ACTOR_LAYERS)
	check_equal(mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP, 1.0), -1.0, "4.5 s away is past the horizon")
	mgr.spawn(WIZ, Vector2(-200.0, 0.0), Vector2(200.0, 0.0), 0.5, 4.0, ManagerScript.ACTOR_LAYERS)
	check_equal(mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP, 2.0), -1.0, "a shot that ends before it arrives is none")


func test_own_team_and_own_shots_are_skipped() -> void:
	mgr.spawn(OTHER_IMP, Vector2(-200.0, 0.0), Vector2(200.0, 0.0), 3.0, 4.0, ManagerScript.ACTOR_LAYERS)
	check_equal(mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP), -1.0, "a teammate's shot is not dodged")
	check(mgr.threat(Vector2.ZERO, 10.0, ActorsScript.NONE, IMP) > 0.0, "with no team every other actor's shot counts")
	check_equal(mgr.threat(Vector2.ZERO, 10.0, ActorsScript.NONE, OTHER_IMP), -1.0, "but never one's own")


func test_the_soonest_wins() -> void:
	mgr.spawn(WIZ, Vector2(-300.0, 0.0), Vector2(200.0, 0.0), 3.0, 4.0, ManagerScript.ACTOR_LAYERS)
	var near: int = mgr.spawn(WIZ, Vector2(0.0, 100.0), Vector2(0.0, -200.0), 3.0, 4.0, ManagerScript.ACTOR_LAYERS)
	var when: float = mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP)
	check_equal(mgr.threat_slot, near, "the one from below arrives first")
	check(when < 0.6, "in about half a second: %s" % when)


func test_a_still_shot_on_the_point() -> void:
	mgr.spawn(WIZ, Vector2(5.0, 0.0), Vector2.ZERO, 3.0, 6.0, ManagerScript.ACTOR_LAYERS, 0, 0, ManagerScript.MOTION_STILL)
	check_equal(mgr.threat(Vector2.ZERO, 10.0, ActorsScript.TEAM_ENEMIES, IMP), 0.0, "standing on a rune is a threat now")
	check(mgr.threat_away.x < -0.9, "step away from it: %s" % mgr.threat_away)
