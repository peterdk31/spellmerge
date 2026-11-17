extends "res://tests/support/suite.gd"
## A step's hits merged (`ProjectileManager.merge_hits`, performance prototype 2026-11-17): the shots
## of one caster and one spell tag that hit one body in a step send one `projectile_impact` and one
## `projectile_hit`, `impact_count` the hits, in the order of their first hits; each shot is spent,
## pierces and ends as it hits; its `shot_ended` comes after the hits; Combat deals the hits' damage.
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")

const DT: float = 1.0 / 60.0

var bus: EventsScript
var mgr: ManagerScript
var table: ActorSeats.ActorsScript
## [caster, target, tag, impact_count] of every `projectile_hit`, and every event's name in order.
var hits: Array = []
var heard: Array[String] = []


func before_each() -> void:
	ManagerScript.merges_hits = true
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


func test_merging_off_sends_every_hit_at_once() -> void:
	mgr.merge_hits = false
	var body: Node2D = _target(Vector2(200.0, 100.0))
	_volley(0, 11, body.global_position, 3)
	mgr.step(DT)
	check_equal(hits, [[0, body, 11, 1], [0, body, 11, 1], [0, body, 11, 1]], "three hits of one")
	check_equal(heard.slice(0, 3), ["impact 1", "hit", "ended 11"] as Array[String], "each shot's end right after its hit")


## The damage a five-shot fan (`penta · bolt`) deals a body close by, with its hits merged or not,
## and the hit events it took.
func _fan_damage(merged: bool) -> Vector2i:
	var arena := ArenaScript.new(root)
	arena.projectiles.merge_hits = merged
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
	var one_by_one: Vector2i = _fan_damage(false)
	var merged: Vector2i = _fan_damage(true)
	check(one_by_one.x > 0, "the fan hurts the body (%d)" % one_by_one.x)
	check_equal(merged.x, one_by_one.x, "merged, the same damage")
	check(merged.y < one_by_one.y, "in fewer hits (%d against %d)" % [merged.y, one_by_one.y])


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


## A body the pass's merged hits have killed (`hit_room_asked`: its health, one hit's damage) takes
## no more of the pass's shots: they are not spent on it, and fly on to the body behind it.
func test_no_shot_is_spent_on_a_body_the_pass_has_killed() -> void:
	var front: Node2D = _target(Vector2(200.0, 100.0))
	var behind: Node2D = _target(Vector2(260.0, 100.0))
	var asked: Array[Node] = []
	bus.hit_room_asked.connect(func(_caster: int, target: Node, _tag: int, _shot: int, room: HitRoom) -> void:
		asked.append(target)
		if target == front:
			room.health = 25.0
			room.damage = 10.0)
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


## A fan whose first shots kill a body spends the shots one by one would, no more, and the same damage.
func _fan_kill(merged: bool) -> Vector3i:
	var arena := ArenaScript.new(root)
	arena.projectiles.merge_hits = merged
	arena.spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	var imp: Node2D = arena.add_imp(Vector2(14.0, 0.0), 4.0)
	arena.install_cards(0, 0, [&"penta", &"bolt"])
	check(arena.cast(0, 0), "the fan is cast")
	arena.run(0.2)
	var out := Vector3i(arena.projectiles.get_count(), 1 if arena.died(imp) else 0, 0)
	arena.free_all()
	return out


func test_a_fan_into_a_body_it_kills_spends_only_the_shots_that_kill() -> void:
	var one_by_one: Vector3i = _fan_kill(false)
	var merged: Vector3i = _fan_kill(true)
	check_equal(one_by_one.y, 1, "the body dies")
	check(one_by_one.x > 0, "some shots fly on past it (%d)" % one_by_one.x)
	check_equal(merged, one_by_one, "merged, the same shots fly on and it dies the same")


## A barrier takes each of a merged hit's shots whole, one charge each, as it did one by one.
func _fan_into_barrier(merged: bool) -> int:
	var arena := ArenaScript.new(root)
	arena.projectiles.merge_hits = merged
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
	if merged:
		check(counts.max() > 1, "the fan's shots merged (%s)" % [counts])
	arena.free_all()
	return lost


func test_a_barrier_takes_a_merged_hits_shots_one_charge_each() -> void:
	var one_by_one: int = _fan_into_barrier(false)
	var merged: int = _fan_into_barrier(true)
	check(one_by_one > 0, "the shots past the barrier's charges hurt (%d)" % one_by_one)
	check_equal(merged, one_by_one, "merged, the same damage gets through")


func after_each() -> void:
	ManagerScript.merges_hits = true
