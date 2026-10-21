extends "res://tests/support/suite.gd"
## Tests for what core/projectiles gives the spell runtime (M2 part 6): the `shot_ended`
## signal for every way a shot can end, `remove_by_tag`, `event_slot` and the per-slot
## readers, and `exclude`. The manager is stepped by hand.
##
## godot --headless --path . --script res://tests/core/test_projectiles_ends.gd

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const DT: float = 1.0 / 60.0
const TAG: int = 300

var _bus: EventsScript
var _mgr: ManagerScript
## Every tag shot_ended was sent with.
var _ended: Array[int] = []
## The event_slot seen in each projectile_hit and projectile_expired handler.
var _seen_slots: Array[int] = []
var _hits: int = 0


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_cap(16)
	_ended.clear()
	_seen_slots.clear()
	_hits = 0
	_mgr.shot_ended.connect(func(tag: int) -> void: _ended.append(tag))
	_bus.projectile_hit.connect(func(_p: int, _t: Node, _at: Vector2, _tag: int) -> void:
		_hits += 1
		_seen_slots.append(_mgr.event_slot))
	_bus.projectile_expired.connect(func(_p: int, _at: Vector2, _tag: int) -> void: _seen_slots.append(_mgr.event_slot))


func _target(position: Vector2, radius: float = 10.0) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = position
	own(node)
	_mgr.add_target(node, radius, ManagerScript.LAYER_ENEMY)
	return node


func _step(count: int) -> void:
	for i in count:
		_mgr.step(DT)


func test_a_spent_hit_ends_the_shot_once_after_the_handlers() -> void:
	_target(Vector2(30, 0))
	_mgr.spawn(0, Vector2.ZERO, Vector2(300, 0), 2.0, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG)
	var order: Array[String] = []
	_bus.projectile_hit.connect(func(_p: int, _t: Node, _at: Vector2, _tag: int) -> void: order.append("hit:%d" % _ended.size()))
	_step(20)
	check_equal(_ended, [TAG] as Array[int], "one end, with the shot's tag")
	check_equal(order, ["hit:0"] as Array[String], "the handler ran before the end was announced")


func test_a_piercing_shot_ends_only_when_spent() -> void:
	_target(Vector2(30, 0))
	_target(Vector2(60, 0))
	_mgr.spawn(0, Vector2.ZERO, Vector2(300, 0), 2.0, 4.0, ManagerScript.LAYER_ENEMY, 1, TAG)
	_step(8)
	check_equal(_hits, 1, "the first target was hit")
	check(_ended.is_empty(), "a shot that pierced is still flying")
	_step(12)
	check_equal(_hits, 2, "and then the second")
	check_equal(_ended.size(), 1, "now it ended, once")


func test_life_walls_bounds_the_cap_and_clear_all_end_a_shot() -> void:
	_mgr.spawn(0, Vector2.ZERO, Vector2(100, 0), 0.05, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG)
	_step(5)
	check_equal(_ended.size(), 1, "life running out ends it")
	check_equal(_seen_slots[0], 0, "and the expiry event names the slot")
	_ended.clear()
	var walls: Array[Rect2] = [Rect2(50, -20, 20, 40)]
	_mgr.set_walls(walls)
	_mgr.spawn(0, Vector2.ZERO, Vector2(600, 0), 2.0, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG + 1)
	_step(10)
	check_equal(_ended, [TAG + 1] as Array[int], "a wall ends it")
	_mgr.clear_walls()
	_ended.clear()
	_mgr.set_bounds(Rect2(-10, -10, 20, 20))
	_mgr.spawn(0, Vector2.ZERO, Vector2(6000, 0), 2.0, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG + 2)
	_step(2)
	check_equal(_ended, [TAG + 2] as Array[int], "leaving the bounds ends it")
	_ended.clear()
	_mgr.set_bounds(Rect2(-1024, -1024, 2048, 2048))
	_mgr.set_cap(2)
	_mgr.spawn(0, Vector2.ZERO, Vector2(1, 0), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG + 3)
	_mgr.spawn(0, Vector2.ZERO, Vector2(1, 0), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG + 4)
	_mgr.spawn(0, Vector2.ZERO, Vector2(1, 0), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG + 5)
	check_equal(_ended, [TAG + 3] as Array[int], "the cap dropping the oldest ends it")
	_ended.clear()
	_mgr.clear()
	check_equal(_ended.size(), 2, "clear ends every live shot")


func test_shots_without_a_tag_send_nothing() -> void:
	_mgr.spawn(0, Vector2.ZERO, Vector2(100, 0), 0.05, 4.0)
	_step(5)
	_mgr.spawn(0, Vector2.ZERO, Vector2(100, 0), 5.0)
	_mgr.clear()
	check(_ended.is_empty(), "a tag of 0 is not announced")


func test_remove_by_tag_is_quiet_and_exact() -> void:
	_mgr.spawn(0, Vector2.ZERO, Vector2(10, 0), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG)
	_mgr.spawn(1, Vector2.ZERO, Vector2(10, 0), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG)
	_mgr.spawn(2, Vector2.ZERO, Vector2(10, 0), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG + 1)
	check_equal(_mgr.remove_by_tag(TAG), 2, "both shots of the tag, of any player")
	check_equal(_mgr.get_count(), 1, "the other tag stays")
	check_equal(_mgr.get_count_for(0), 0, "the owner's count follows")
	check(_ended.is_empty() and _seen_slots.is_empty(), "no end and no event")
	check_equal(_mgr.remove_by_tag(TAG), 0, "nothing left to remove")
	_mgr.spawn(0, Vector2.ZERO, Vector2(10, 0), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG)
	check_equal(_mgr.get_count(), 2, "the freed rows can be used again")


func test_event_slot_is_set_in_handlers_only() -> void:
	_target(Vector2(30, 0))
	var slot: int = _mgr.spawn(0, Vector2.ZERO, Vector2(300, 0), 2.0, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG)
	check_equal(_mgr.event_slot, -1, "-1 outside")
	_step(20)
	check_equal(_seen_slots, [slot] as Array[int], "the hit handler saw the shot's slot")
	check_equal(_mgr.event_slot, -1, "and it is reset")
	_target(Vector2(100, 100))
	_seen_slots.clear()
	_mgr.ray(0, Vector2(0, 100), Vector2.RIGHT, 200.0, 0, ManagerScript.LAYER_ENEMY, TAG)
	check_equal(_seen_slots, [-1] as Array[int], "a ray has no slot")


func test_a_ray_inside_a_handler_does_not_inherit_its_slot() -> void:
	_target(Vector2(30, 0))
	_target(Vector2(100, 100))
	var inner: Array[int] = []
	_bus.projectile_hit.connect(func(_p: int, _t: Node, at: Vector2, tag: int) -> void:
		if tag == TAG:
			_mgr.ray(0, Vector2(0, 100), Vector2.RIGHT, 200.0, 0, ManagerScript.LAYER_ENEMY, TAG + 1)
			inner.append(_mgr.event_slot)
		elif tag == TAG + 1:
			inner.append(_mgr.event_slot))
	_mgr.spawn(0, Vector2.ZERO, Vector2(300, 0), 2.0, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG)
	_step(20)
	check_equal(inner, [-1, 0] as Array[int], "the ray's hit saw -1, the outer handler 0 again afterwards")


func test_the_readers_follow_a_slot() -> void:
	var slot: int = _mgr.spawn(0, Vector2(5, 5), Vector2(10, 20), 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG)
	var seq: int = _mgr.get_seq_of(slot)
	check_equal(_mgr.get_tag_of(slot), TAG, "tag")
	check_equal(_mgr.get_velocity_of(slot), Vector2(10, 20), "velocity")
	_mgr.remove_by_tag(TAG)
	var again: int = _mgr.spawn(0, Vector2.ZERO, Vector2.ZERO, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG)
	check_equal(again, slot, "the slot is reused")
	check(_mgr.get_seq_of(slot) != seq, "but its spawn number is new")
	check_equal(_mgr.get_seq_of(-1), -1, "a bad slot is -1")
	check_equal(_mgr.get_anchor(0), Vector2.INF, "no anchor yet")
	_mgr.set_anchor(0, Vector2(1, 2))
	check_equal(_mgr.get_anchor(0), Vector2(1, 2), "the anchor")
	var node: Node2D = _target(Vector2(40, 50))
	check_equal(_mgr.get_target_point(node), Vector2(40, 50), "a target's place, right after add_target")
	check_equal(_mgr.get_target_point(null), Vector2.INF, "null")


func test_exclude_blocks_one_target_for_a_while() -> void:
	var node: Node2D = _target(Vector2(0, 0))
	var slot: int = _mgr.spawn(0, Vector2(-5, 0), Vector2.ZERO, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG, ManagerScript.MOTION_STILL)
	_mgr.exclude(slot, node, 0.1)
	_step(5)
	check_equal(_hits, 0, "inside the circle but excluded")
	_step(3)
	check_equal(_hits, 1, "hit once the time is over")


func test_exclude_is_cleared_when_the_slot_is_reused() -> void:
	var node: Node2D = _target(Vector2(0, 0))
	var slot: int = _mgr.spawn(0, Vector2(-5, 0), Vector2.ZERO, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG, ManagerScript.MOTION_STILL)
	_mgr.exclude(slot, node, 100.0)
	_mgr.remove_by_tag(TAG)
	_mgr.spawn(0, Vector2(-5, 0), Vector2.ZERO, 5.0, 4.0, ManagerScript.LAYER_ENEMY, 0, TAG, ManagerScript.MOTION_STILL)
	_step(2)
	check_equal(_hits, 1, "the new shot in the old slot hits it")
