extends "res://tests/support/suite.gd"
## A step's hits merged (the one hit model, the owner, 2026-11-17; hit batch A3b): the shots
## of one caster and one spell tag that hit one body in a step send one `projectile_impact` and one
## `projectile_hit`, `impact_count` the hits, in the order of their first hits; each shot is spent,
## pierces and ends as it hits; its `shot_ended` comes after the hits; Combat deals the hits' damage.
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")
const ActorFixture := preload("res://tests/gameplay/actor/actor_fixture.gd")

const DT: float = 1.0 / 60.0

var bus: EventsScript
var mgr: ManagerScript
var table: ActorSeats.ActorsScript
## [caster, target, tag, impact_count] of every `projectile_hit`, and every event's name in order.
var hits: Array = []
var heard: Array[String] = []


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	mgr = own(ManagerScript.new()) as ManagerScript
	table = own(ActorSeats.table()) as ActorSeats.ActorsScript
	mgr.actors = table
	mgr.events = bus
	mgr.set_bounds(Rect2(-100.0, -100.0, 800.0, 600.0))
	hits.clear()
	heard.clear()
	bus.projectile_impact.connect(func(_caster: int, _target: Node, _at: Vector2, _dir: Vector2) -> void: heard.append("impact %d" % mgr.impact_count))
	bus.projectile_hit.connect(func(caster: int, target: Node, _at: Vector2, tag: int, _shot: int) -> void:
		heard.append("hit")
		hits.append([caster, target, tag, mgr.impact_count]))
	mgr.shot_ended.connect(func(tag: int) -> void: heard.append("ended %d" % tag))


func _target(at: Vector2) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.global_position = at
	mgr.add_target(node, 10.0, ManagerScript.LAYER_ENEMY)
	return node


## `count` shots of `caster` with `tag`, flying into `at` from the left this step.
func _volley(caster: int, tag: int, at: Vector2, count: int) -> void:
	for i in count:
		mgr.spawn(caster, at + Vector2(-12.0, 0.4 * i), Vector2(600.0, 0.0), 2.0, 3.0, ManagerScript.LAYER_ENEMY, 0, tag)


func test_one_spells_hits_on_one_body_in_a_step_go_out_as_one() -> void:
	var body: Node2D = _target(Vector2(200.0, 100.0))
	_volley(0, 11, body.global_position, 5)
	mgr.step(DT)
	check_equal(hits, [[0, body, 11, 5]], "one hit standing for the five")
	check_equal(heard, ["impact 5", "hit", "ended 11", "ended 11", "ended 11", "ended 11", "ended 11"] as Array[String], "its impact first, and each spent shot's end after the hits")
	check_equal(mgr.impact_count, 1, "one again outside the events")
	check_equal(mgr.get_count(), 0, "every shot was spent")


func test_each_caster_and_each_spell_is_its_own_hit_in_the_order_of_their_first() -> void:
	var body: Node2D = _target(Vector2(200.0, 100.0))
	var other: Node2D = _target(Vector2(200.0, 200.0))
	_volley(1, 21, body.global_position, 2)
	_volley(0, 11, body.global_position, 3)
	_volley(0, 12, body.global_position, 1)
	_volley(0, 11, other.global_position, 2)
	mgr.step(DT)
	check_equal(hits, [[1, body, 21, 2], [0, body, 11, 3], [0, body, 12, 1], [0, other, 11, 2]], "by caster, spell and body, in the order the shots hit")


## The damage a five-shot fan (`penta · bolt`) deals a body close by, and the hit events it took.
## The fans below are held to what they did with the hits one by one, before the mode went (hit
## batch A3b, recorded on commit 3b917b6): this fan dealt 10 in 5 hits.
func _fan_damage() -> Vector2i:
	var arena := ArenaScript.new(root)
	var events: Array[int] = [0]
	arena.bus.projectile_hit.connect(func(_c: int, _t: Node, _a: Vector2, _tag: int, _s: int) -> void: events[0] += 1)
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	var imp: Node2D = arena.add_imp(Vector2(14.0, 0.0))
	arena.install_cards(0, 0, [&"penta", &"bolt"])
	check(arena.cast(0, 0), "the fan is cast")
	arena.run(1.0)
	var out := Vector2i(arena.lost(imp), events[0])
	arena.free_all()
	return out


func test_combat_deals_the_merged_hits_damage() -> void:
	var merged: Vector2i = _fan_damage()
	check_equal(merged.x, 10, "merged, the damage the hits one by one dealt")
	check(merged.y < 5, "in fewer hits than its five shots (%d)" % merged.y)


## At the cap, a shot spawned in the pass (an expired shot's payload) while every free slot is held
## for hits still to send takes one back: no slot is handed out twice, and the pool stays whole.
func test_a_spawn_in_the_pass_at_the_cap_keeps_the_pool_whole() -> void:
	mgr.set_cap(4)
	var body: Node2D = _target(Vector2(200.0, 100.0))
	_volley(0, 11, body.global_position, 2)
	# Two that run out this very step, far from the body.
	for i in 2:
		mgr.spawn(0, Vector2(50.0, 300.0 + 10.0 * i), Vector2(10.0, 0.0), 0.001, 3.0, ManagerScript.LAYER_ENEMY, 0, 12)
	var made: Array[int] = []
	bus.projectile_expired.connect(func(_caster: int, at: Vector2, _tag: int, _shot: int) -> void: made.append(mgr.spawn(0, at, Vector2(5.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 13)))
	mgr.step(DT)
	check_equal(made.size(), 2, "both expired shots spawned one")
	check(made[0] >= 0 and made[1] >= 0 and made[0] != made[1], "in two slots (%s)" % [made])
	check_equal(mgr.get_count(), 2, "the two live")
	check_equal(hits, [[0, body, 11, 2]], "and the hit still sent")
	var slots: Array[int] = made.duplicate()
	for i in 2:
		slots.append(mgr.spawn(0, Vector2(50.0, 50.0), Vector2(5.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 14))
	check_equal(mgr.get_count(), 4, "the cap is filled with no drop")
	check_equal(mgr.dropped, 0, "none dropped")
	var distinct: Dictionary = {}
	for slot in slots:
		distinct[slot] = true
	check_equal(distinct.size(), 4, "four slots, each once (%s)" % [slots])


## A piercing shot that hits and then meets a wall in the same step ends after its merged hit.
func test_a_shot_that_hits_and_ends_on_a_wall_in_one_step_ends_after_its_hit() -> void:
	var body: Node2D = _target(Vector2(200.0, 100.0))
	var walls: Array[Rect2] = [Rect2(206.0, 0.0, 32.0, 300.0)]
	mgr.set_walls(walls)
	# 25 px a step: through the body and into the wall in one step.
	mgr.spawn(0, body.global_position + Vector2(-12.0, 0.0), Vector2(1500.0, 0.0), 2.0, 3.0, ManagerScript.LAYER_ENEMY, 1, 11)
	mgr.step(DT)
	check_equal(hits.size(), 1, "it hit")
	check(heard.has("ended 11"), "and ended on the wall (%s)" % [heard])
	check(heard.find("hit") >= 0 and heard.find("hit") < heard.find("ended 11"), "and ended after (%s)" % [heard])


## A shot its hit spends (no pierce) meets no wall after it in the same step: one hit, one end, no
## bounce off the wall behind the body.
func test_a_spent_shot_meets_no_wall_after_its_hit() -> void:
	var body: Node2D = _target(Vector2(200.0, 100.0))
	var walls: Array[Rect2] = [Rect2(206.0, 0.0, 32.0, 300.0)]
	mgr.set_walls(walls)
	var slot: int = mgr.spawn(0, body.global_position + Vector2(-12.0, 0.0), Vector2(1500.0, 0.0), 2.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 11)
	mgr.set_bounce(slot, 3)
	mgr.step(DT)
	mgr.step(DT)
	check_equal(heard, ["impact 1", "hit", "ended 11"] as Array[String], "its hit, its end, and nothing at the wall (%s)" % [heard])
	check_equal(mgr.get_count(), 0, "it is gone")


## At the cap, a shot spawned in the pass (a bounce's payload) while no slot is free takes the slot of
## a shot the pass's hits spent (ended at once), not a living shot's: none is dropped, the spent shot
## ends once, and the new one is not ended in its place.
func test_a_spawn_at_the_cap_takes_a_spent_shots_slot_not_a_living_ones() -> void:
	mgr.set_cap(3)
	var body: Node2D = _target(Vector2(200.0, 100.0))
	mgr.set_walls([Rect2(400.0, 0.0, 32.0, 300.0)] as Array[Rect2])
	# Spent on the body this step (first in the pass), a bounce off the wall after it, and one far off.
	mgr.spawn(0, body.global_position + Vector2(-12.0, 0.0), Vector2(600.0, 0.0), 2.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 11)
	var bouncer: int = mgr.spawn(0, Vector2(395.0, 250.0), Vector2(600.0, 0.0), 2.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 12)
	mgr.set_bounce(bouncer, 2)
	var far: int = mgr.spawn(0, Vector2(50.0, 280.0), Vector2(1.0, 0.0), 5.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 13)
	var made: Array[int] = []
	mgr.wall_met.connect(func(_caster: int, at: Vector2, _heading: Vector2, _tag: int, _shot: int) -> void:
		made.append(mgr.spawn(0, at + Vector2(-20.0, 0.0), Vector2(-5.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 14)))
	mgr.step(DT)
	check_equal(made.size(), 1, "the bounce spawned one")
	check_equal(mgr.dropped, 0, "no living shot was dropped for it")
	check(mgr.is_alive(far) and mgr.is_alive(bouncer) and mgr.is_alive(made[0]), "the far shot, the bouncer and the new one fly")
	check_equal(heard.count("ended 11"), 1, "the spent shot ended once")
	check_equal(heard.count("ended 14"), 0, "the new one is not ended in its place")
	check_equal(hits, [[0, body, 11, 1]], "and its hit was sent")


## A handler that ends a spent shot during the pass (a bounce's handler removing a spell's shots):
## the pass does not end it again, and the pool stays whole.
func test_a_spent_shot_ended_by_a_handler_is_not_ended_twice() -> void:
	mgr.set_cap(4)
	var body: Node2D = _target(Vector2(200.0, 100.0))
	mgr.set_walls([Rect2(400.0, 0.0, 32.0, 300.0)] as Array[Rect2])
	mgr.spawn(0, body.global_position + Vector2(-12.0, 0.0), Vector2(600.0, 0.0), 2.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 11)
	var bouncer: int = mgr.spawn(0, Vector2(395.0, 250.0), Vector2(600.0, 0.0), 2.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 12)
	mgr.set_bounce(bouncer, 2)
	mgr.wall_met.connect(func(_caster: int, _at: Vector2, _heading: Vector2, _tag: int, _shot: int) -> void: mgr.remove_by_tag(11))
	mgr.step(DT)
	check_equal(mgr.get_count(), 1, "only the bouncer is left")
	var slots: Dictionary = {}
	for i in 3:
		slots[mgr.spawn(0, Vector2(50.0, 280.0), Vector2(1.0, 0.0), 5.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 15)] = true
	check_equal(mgr.get_count(), 4, "the pool fills to its cap")
	check_equal(slots.size(), 3, "each in a slot of its own")
	check_equal(mgr.dropped, 0, "none dropped")


## A handler of a merged hit that strikes (a payload's ray, a swing) sends a hit of one.
func test_a_hit_a_merged_hits_handler_makes_is_one() -> void:
	var body: Node2D = _target(Vector2(200.0, 100.0))
	var other: Node2D = _target(Vector2(400.0, 100.0))
	bus.projectile_hit.connect(func(_caster: int, target: Node, _at: Vector2, _tag: int, _shot: int) -> void:
		if target == body:
			mgr.strike(0, other, other.global_position, Vector2.RIGHT, 99, &"swing"))
	_volley(0, 11, body.global_position, 3)
	mgr.step(DT)
	check_equal(hits, [[0, body, 11, 3], [0, other, 99, 1]], "the strike is one hit, the volley three")
	check_equal(mgr.impact_count, 1, "and one again after")


## A shot with a profile of its own (`set_hits_alone`: a relay's, an infusion's) is its own hit.
func test_a_shot_that_hits_alone_is_never_merged() -> void:
	var body: Node2D = _target(Vector2(200.0, 100.0))
	_volley(0, 11, body.global_position, 3)
	check(mgr.set_hits_alone(1), "the second shot hits alone")
	mgr.step(DT)
	check_equal(hits, [[0, body, 11, 2], [0, body, 11, 1]], "the two plain shots merged, the other alone")


## A body the pass's merged hits have killed (`hit_room_asked`: its health; `hit_damage_asked`: one
## hit's damage) takes no more of the pass's shots: they are not spent on it, and fly on to the body
## behind it.
func test_no_shot_is_spent_on_a_body_the_pass_has_killed() -> void:
	var front: Node2D = _target(Vector2(200.0, 100.0))
	var behind: Node2D = _target(Vector2(260.0, 100.0))
	var asked: Array[Node] = []
	bus.hit_room_asked.connect(func(target: Node, room: HitRoom) -> void:
		asked.append(target)
		if target == front:
			room.known = true
			room.health = 25.0)
	bus.hit_damage_asked.connect(func(_tag: int, _shot: int, answer: HitDamage) -> void: answer.damage = 10.0)
	# Its death, as Combat's would be: it is no target from then on.
	bus.projectile_hit.connect(func(_caster: int, target: Node, _at: Vector2, _tag: int, _shot: int) -> void:
		if target == front:
			mgr.remove_target(front))
	_volley(0, 11, front.global_position, 5)
	mgr.step(DT)
	check_equal(hits, [[0, front, 11, 3]], "three hits of 10 kill 25: the front body takes three")
	check_equal(asked, [front] as Array[Node], "asked once, at its first hit")
	check_equal(mgr.get_count(), 2, "the other two are not spent")
	for i in 10:
		mgr.step(DT)
	check_equal(hits.size(), 2, "they fly on")
	check_equal(hits[1], [0, behind, 11, 2], "and hit the body behind")


## A body hit by several spells in one pass: every spell's hits count off its one health, and a
## heal's hit first (no damage) does not keep the body from being counted dead.
func _two_spells_on(front: Node2D, first_tag: int, first_damage: float) -> void:
	bus.hit_room_asked.connect(func(target: Node, room: HitRoom) -> void:
		if target == front:
			room.known = true
			room.health = 25.0)
	bus.hit_damage_asked.connect(func(tag: int, _shot: int, answer: HitDamage) -> void:
		answer.damage = first_damage if tag == first_tag else 10.0)
	bus.projectile_hit.connect(func(_caster: int, target: Node, _at: Vector2, _tag: int, _shot: int) -> void:
		if target == front:
			mgr.remove_target(front))


func test_every_spells_hits_count_off_one_health() -> void:
	var front: Node2D = _target(Vector2(200.0, 100.0))
	_two_spells_on(front, 11, 10.0)
	_volley(0, 11, front.global_position, 2)
	_volley(0, 12, front.global_position, 3)
	mgr.step(DT)
	check_equal(hits, [[0, front, 11, 2], [0, front, 12, 1]], "two of one spell and one of the other kill 25")
	check_equal(mgr.get_count(), 2, "the last two are not spent")


func test_a_heal_first_does_not_keep_a_body_from_dying() -> void:
	var front: Node2D = _target(Vector2(200.0, 100.0))
	_two_spells_on(front, 13, 0.0)
	_volley(0, 13, front.global_position, 1)
	_volley(0, 12, front.global_position, 5)
	mgr.step(DT)
	check_equal(hits, [[0, front, 13, 1], [0, front, 12, 3]], "the heal, then three hits of 10 kill 25")
	check_equal(mgr.get_count(), 2, "the last two are not spent")


## Combat tells a body's health whatever spell hits it, and a spell that deals no damage (a heal, no
## profile) as damage 0, so the body's other spells still count off its health.
func test_combat_tells_the_health_for_a_spell_that_deals_none() -> void:
	var arena := ArenaScript.new(root)
	var imp: Node2D = arena.add_imp(Vector2(40.0, 0.0), 30.0)
	var room := HitRoom.new()
	arena.bus.hit_room_asked.emit(imp, room)
	check(room.known, "its room is known")
	check_equal(room.health, 30.0, "its health")
	var answer := HitDamage.new()
	arena.bus.hit_damage_asked.emit(0, -1, answer)
	check_equal(answer.damage, 0.0, "and a spell of no profile deals none")
	arena.free_all()


## A barrier's charges count against every spell's hits on the body, one hit each, before damage:
## 3 charges take spell A's two hits and spell B's first, and B's last two deal 2 of 20 health, so
## the body lives and every shot hits it.
func test_a_barriers_charges_count_once_whatever_spells_hit() -> void:
	var front: Node2D = _target(Vector2(200.0, 100.0))
	bus.hit_room_asked.connect(func(_target: Node, room: HitRoom) -> void:
		room.known = true
		room.health = 20.0
		room.charges = 3)
	bus.hit_damage_asked.connect(func(tag: int, _shot: int, answer: HitDamage) -> void:
		answer.damage = 10.0 if tag == 11 else 1.0)
	_volley(0, 11, front.global_position, 2)
	_volley(0, 12, front.global_position, 5)
	mgr.step(DT)
	check_equal(hits, [[0, front, 11, 2], [0, front, 12, 5]], "every shot hits: the barrier ate three, 4 damage landed")


## Combat tells a body no hit can take health from (an invincible prop) as unknown: the pass never
## counts it dead, and every shot stops on it.
func test_combat_tells_an_invincible_body_as_unknown() -> void:
	var world := ActorFixture.new(root)
	var body: Actor = world.actor(Vector2(40.0, 0.0), [&"health", &"hurtbox"] as Array[StringName], ActorFixture.Scripted.new())
	var room := HitRoom.new()
	world.bus.hit_room_asked.emit(body, room)
	check(room.known and room.health < INF, "a plain body tells its health (%s)" % room.health)
	body.health.invincible = true
	room.clear()
	world.bus.hit_room_asked.emit(body, room)
	check(not room.known and room.health == INF, "an invincible one is never counted dead")
	world.free_all()


## A handler that clears the manager while the merged hits are sent stops the rest.
func test_a_clear_while_the_hits_are_sent_stops_the_rest() -> void:
	var front: Node2D = _target(Vector2(200.0, 100.0))
	var other: Node2D = _target(Vector2(200.0, 200.0))
	bus.projectile_hit.connect(func(_caster: int, _target: Node, _at: Vector2, _tag: int, _shot: int) -> void: mgr.clear())
	_volley(0, 11, front.global_position, 2)
	_volley(0, 11, other.global_position, 2)
	mgr.step(DT)
	check_equal(hits.size(), 1, "the first hit is sent, then nothing after the clear")


## At the cap, a spawn in the pass never takes the slot of a spent shot that hits alone (its merged
## hit, still to send, reads its profile by its slot): its hit names its shot.
func test_a_spawn_at_the_cap_leaves_a_shot_that_hits_alone_its_slot() -> void:
	mgr.set_cap(2)
	var body: Node2D = _target(Vector2(200.0, 100.0))
	mgr.set_walls([Rect2(400.0, 0.0, 32.0, 300.0)] as Array[Rect2])
	var alone: int = mgr.spawn(0, body.global_position + Vector2(-12.0, 0.0), Vector2(600.0, 0.0), 2.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 11)
	mgr.set_hits_alone(alone)
	var bouncer: int = mgr.spawn(0, Vector2(395.0, 250.0), Vector2(600.0, 0.0), 2.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 12)
	mgr.set_bounce(bouncer, 2)
	mgr.wall_met.connect(func(_caster: int, at: Vector2, _heading: Vector2, _tag: int, _shot: int) -> void:
		mgr.spawn(0, at + Vector2(-20.0, 0.0), Vector2(-5.0, 0.0), 3.0, 3.0, ManagerScript.LAYER_ENEMY, 0, 14))
	var shots: Array[int] = []
	bus.projectile_hit.connect(func(_caster: int, _target: Node, _at: Vector2, _tag: int, shot: int) -> void: shots.append(shot))
	mgr.step(DT)
	check_equal(shots, [alone] as Array[int], "the alone shot's hit names its own slot")


## A fan whose first shots kill a body spends the shots one by one would, no more (one by one, 3 of
## its 5 flew on past the body, which died).
func _fan_kill() -> Vector3i:
	var arena := ArenaScript.new(root)
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	var imp: Node2D = arena.add_imp(Vector2(14.0, 0.0), 4.0)
	arena.install_cards(0, 0, [&"penta", &"bolt"])
	check(arena.cast(0, 0), "the fan is cast")
	arena.run(0.2)
	var out := Vector3i(arena.projectiles.get_count(), 1 if arena.died(imp) else 0, 0)
	arena.free_all()
	return out


func test_a_fan_into_a_body_it_kills_spends_only_the_shots_that_kill() -> void:
	var merged: Vector3i = _fan_kill()
	check_equal(merged, Vector3i(3, 1, 0), "the body dies, and the three shots one by one sent on fly on")


## A barrier takes each of a merged hit's shots whole, one charge each, as it did one by one (2 got
## through).
func _fan_into_barrier() -> int:
	var arena := ArenaScript.new(root)
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	var imp: Node2D = arena.add_imp(Vector2(14.0, 0.0))
	# Four charges: the fan's last two shots land together as one merged hit, on the last charge.
	arena.combat.give_barrier(imp, 4, 10.0, 0)
	var counts: Array[int] = []
	arena.bus.projectile_hit.connect(func(_c: int, _t: Node, _a: Vector2, _tag: int, _s: int) -> void: counts.append(arena.projectiles.impact_count))
	arena.install_cards(0, 0, [&"penta", &"bolt"])
	check(arena.cast(0, 0), "the fan is cast")
	arena.run(1.0)
	var lost: int = arena.lost(imp)
	check(counts.max() > 1, "the fan's shots merged (%s)" % [counts])
	arena.free_all()
	return lost


func test_a_barrier_takes_a_merged_hits_shots_one_charge_each() -> void:
	check_equal(_fan_into_barrier(), 2, "the damage that got through one by one")
