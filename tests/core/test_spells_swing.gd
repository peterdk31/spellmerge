extends "res://tests/support/suite.gd"
## Tests for swings (melee I2; docs/milestones/M2-staffs.md, "Phase I: melee"): a swing leans back
## for its wind-up, then sweeps its arc round the hand, centred on the aim locked at the cast,
## striking each body in the wedge once (also between two steps of a fast sweep), skipping only
## its caster; it turns clockwise and back by turns, chains on with no wind-up, and ends at the
## end of its arc. It runs a real projectile manager and event bus, stepped by hand, with cards
## built in code.
##
## godot --headless --path . --script res://tests/core/test_spells_swing.gd

const StaffKit := preload("res://tests/support/staff_kit.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const DT: float = 1.0 / 60.0
const REACH: float = 24.0


class FakeRegistry:
	extends Node
	var items: Dictionary = {}

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)


var _fake: FakeRegistry
var _spells: SpellsScript
var _mgr: ManagerScript
var _bus: EventsScript
## Every projectile_hit as [player, target, position, tag].
var _hits: Array = []
## Every area_hit_requested as [player, position, radius, tag].
var _areas: Array = []
var _swing: FormBase


func before_each() -> void:
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_cap(512)
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _fake
	_spells.bind(_mgr, _bus)
	_hits.clear()
	_areas.clear()
	_bus.projectile_hit.connect(func(player: int, target: Node, at: Vector2, tag: int, _shot: int) -> void:
		_hits.append([player, target, at, tag]))
	_bus.area_hit_requested.connect(func(player: int, at: Vector2, radius: float, tag: int, _shot: int) -> void:
		_areas.append([player, at, radius, tag]))
	# The playground's numbers (owner, 2026-10-29).
	_swing = FormBase.new()
	_swing.carrier = &"swing"
	_swing.base_damage = 2
	_swing.arc = 90.0
	_swing.ray_length = REACH
	_swing.lifetime = 0.06
	_swing.wind_up = 0.12
	_swing.cooldown = 0.05
	_swing.knockback = 240.0
	# The swing card's staff animation: lean back past the arc, sweep past its end, hold, settle.
	_swing.staff_pose = [{"phase": "wind", "at": 1.0, "turn": -67.5, "ease": "out"}, {"phase": "strike", "at": 1.0, "turn": 67.5}, {"phase": "after", "at": 0.08, "turn": 67.5}, {"phase": "after", "at": 0.38}] as Array[Dictionary]
	_put(_swing, &"swing")
	var blast := ModifierBase.new()
	blast.behaviour = ModifierBase.Behaviour.BLAST
	blast.behaviour_strength = 30.0
	_put(blast, &"blast")
	var hold := ModifierBase.new()
	hold.behaviour = ModifierBase.Behaviour.HOLD
	hold.behaviour_strength = 1.0
	_put(hold, &"hold")


func _put(component: SpellComponent, id: StringName) -> void:
	component.id = id
	component.display_name = String(id).capitalize()
	component.complexity = 1
	_fake.items[id] = component


func _build(cards: Array[StringName] = [&"swing"]) -> int:
	StaffKit.build(_spells, 0, 0, cards)
	return _spells.current_tag(0, 0, 0)


func _cast(origin: Vector2 = Vector2.ZERO, direction: Vector2 = Vector2.RIGHT) -> float:
	return _spells.cast_staff(0, 0, origin, direction, 100.0)


## A body of `radius` at `position`, on `layer`, owned by `owner` (NO_PLAYER for none).
func _target(position: Vector2, radius: float = 4.0, layer: int = ManagerScript.LAYER_ENEMY, owner: int = EventsScript.NO_PLAYER) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = position
	own(node)
	_mgr.add_target(node, radius, layer, owner)
	return node


## A body `distance` from the origin, `degrees` off the aim (positive clockwise on screen).
func _at(degrees: float, distance: float = 18.0, radius: float = 2.0) -> Node2D:
	return _target(Vector2.from_angle(deg_to_rad(degrees)) * distance, radius)


func _tick(steps: int) -> void:
	for i in steps:
		_mgr.step(DT)
		_spells.step(DT)


func _struck(node: Node) -> int:
	var count: int = 0
	for hit: Array in _hits:
		if hit[1] == node:
			count += 1
	return count


## The row of the one live swing, or -1.
func _row() -> int:
	for at in _spells.swing_slots():
		if _spells.swing_on(at):
			return at
	return -1


func test_the_arc_hits_what_is_in_it_and_nothing_behind_or_beside() -> void:
	var front: Node2D = _at(0.0)
	var edge: Node2D = _at(40.0)
	var behind: Node2D = _at(180.0)
	var beside: Node2D = _at(-90.0)
	var far: Node2D = _at(0.0, 40.0)
	_build()
	_cast()
	_tick(30)
	check_equal(_struck(front), 1, "the body in front is hit")
	check_equal(_struck(edge), 1, "a body near the end of the arc is hit")
	check_equal(_struck(behind), 0, "nothing behind")
	check_equal(_struck(beside), 0, "nothing beside, past the arc")
	check_equal(_struck(far), 0, "nothing past its reach")
	check_equal(_spells.swing_count(), 0, "the swing is over")
	check_equal(_spells.live_shots(_spells.current_tag(0, 0, 0)), 0, "and no longer counted")


func test_nothing_is_hit_during_the_wind_up() -> void:
	var front: Node2D = _at(0.0)
	_build()
	_cast()
	_tick(6)
	check_equal(_struck(front), 0, "0.1 s in, the staff is still leaning back")
	_tick(10)
	check_equal(_struck(front), 1, "then the sweep hits")


func test_each_body_is_hit_once_by_one_swing() -> void:
	var big: Node2D = _target(Vector2(16, 0), 12.0)
	_build()
	_cast()
	_tick(30)
	check_equal(_struck(big), 1, "a body the whole sweep touches is hit once")


func test_a_sweep_faster_than_a_step_still_hits_everything_it_turned_through() -> void:
	_swing.wind_up = 0.0
	var thin: Array[Node2D] = [_at(-30.0, 20.0, 1.0), _at(-5.0, 20.0, 1.0), _at(20.0, 20.0, 1.0), _at(44.0, 20.0, 1.0)]
	_build()
	_cast()
	# One long step: the whole 0.06 s sweep happens in it.
	_mgr.step(0.1)
	_spells.step(0.1)
	for node in thin:
		check_equal(_struck(node), 1, "a thin body at %s is hit though the sweep is over in one step" % str(node.global_position))


func test_the_caster_is_skipped_and_a_teammate_is_hit() -> void:
	var own_body: Node2D = _target(Vector2(10, 0), 6.0, ManagerScript.LAYER_PLAYER, 0)
	var mate: Node2D = _target(Vector2(18, 4), 4.0, ManagerScript.LAYER_PLAYER, 1)
	_build()
	_cast()
	_tick(30)
	check_equal(_struck(own_body), 0, "its own body is skipped")
	check_equal(_struck(mate), 1, "everything hurts everything: a teammate in the arc is hit")


func test_swings_turn_clockwise_and_back_by_turns() -> void:
	var upper: Node2D = _at(-30.0)
	var lower: Node2D = _at(30.0)
	_build()
	_cast()
	check_equal(_spells.swing_side(_row()), 1, "the first swing is a forehand (clockwise on screen)")
	_tick(30)
	check_equal(_hits.size(), 2, "it hits both")
	check(_hits[0][1] == upper and _hits[1][1] == lower, "turning clockwise it meets the upper body first")
	_hits.clear()
	_tick(30)
	_cast()
	check_equal(_spells.swing_side(_row()), -1, "the next is a backhand")
	_tick(30)
	check(_hits.size() == 2 and _hits[0][1] == lower and _hits[1][1] == upper, "turning back it meets the lower body first")


func test_a_swing_right_after_the_last_chains_on_with_no_wind_up() -> void:
	var front: Node2D = _at(0.0)
	_build()
	_cast()
	_tick(12)
	check_equal(_struck(front), 1, "the first swing hit")
	check_equal(_spells.swing_count(), 0, "and is over")
	_cast()
	_tick(5)
	check_equal(_struck(front), 2, "a swing within the chain window sweeps at once")
	_tick(60)
	_cast()
	_tick(5)
	check_equal(_struck(front), 2, "after a pause it leans back first again")
	_tick(10)
	check_equal(_struck(front), 3, "then hits")


func test_the_aim_is_locked_at_the_cast() -> void:
	var front: Node2D = _at(0.0)
	var below: Node2D = _at(90.0)
	_build()
	_spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	_cast()
	_spells.set_aim(0, Vector2.ZERO, Vector2.DOWN)
	_tick(30)
	check_equal(_struck(front), 1, "it sweeps where it was aimed at the cast")
	check_equal(_struck(below), 0, "turning the aim during the wind-up moves no arc")


func test_it_turns_round_the_hand_and_follows_it() -> void:
	# The tip is 14 px out along the aim; the swing turns round the hand.
	var near_hand: Node2D = _target(Vector2(10, 8), 2.0)
	_build()
	_spells.set_aim(0, Vector2(14, 0), Vector2.RIGHT, Vector2.ZERO)
	_cast(Vector2(14, 0))
	_tick(30)
	check_equal(_struck(near_hand), 1, "a body beside the hand, behind the tip, is in the arc")
	_hits.clear()
	var ahead: Node2D = _target(Vector2(118, 0), 2.0)
	_spells.set_aim(0, Vector2(14, 0), Vector2.RIGHT, Vector2.ZERO)
	_tick(30)
	_cast(Vector2(14, 0))
	# The wizard walks on during the wind-up: the swing goes with its hand.
	_spells.set_aim(0, Vector2(114, 0), Vector2.RIGHT, Vector2(100, 0))
	_tick(30)
	check_equal(_struck(ahead), 1, "the arc moves with the hand")


func test_hits_push_outward_from_the_hand_with_the_cards_knockback() -> void:
	var front: Node2D = _target(Vector2(16, 6), 4.0)
	var tag: int = _build()
	_cast()
	_tick(30)
	check_equal(_hits.size(), 1, "one hit")
	var at: Vector2 = _hits[0][2]
	var outward: Vector2 = front.global_position.normalized()
	check((front.global_position - at).normalized().distance_to(outward) < 0.01, "the hit point is on the body's line from the hand, so knockback pushes it straight out")
	check_equal(_spells.hit_profile(tag).knockback, 240.0, "the card's own knockback")


func test_its_blast_goes_off_at_the_end_of_the_arc() -> void:
	_build([&"blast", &"swing"])
	_cast()
	_tick(30)
	check_equal(_areas.size(), 1, "one blast")
	var end: Vector2 = Vector2.from_angle(deg_to_rad(45.0)) * REACH
	check((_areas[0][1] as Vector2).distance_to(end) < 0.5, "where the forehand's arc ends (got %s)" % str(_areas[0][1]))


func test_the_body_pose_leans_sweeps_holds_and_settles() -> void:
	_build()
	_spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	check_equal(_spells.staff_pose_dir(0), Vector2.ZERO, "no pose before a swing")
	_cast()
	_tick(6)
	var leaning: float = _pose_angle()
	check(leaning < -45.0, "during the wind-up it leans back past the arc's start (%s)" % leaning)
	_tick(6)
	check(_pose_angle() > 45.0, "after the sweep it holds past the arc's end (%s)" % _pose_angle())
	_tick(40)
	check_equal(_spells.staff_pose_dir(0), Vector2.ZERO, "then it settles back onto the aim")


func test_a_chained_backhand_starts_where_the_forehand_ended() -> void:
	_build()
	_spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	_cast()
	_tick(12)
	var ended: float = _pose_angle()
	_tick(6)
	_cast()
	check(absf(_pose_angle() - ended) < 1.0, "no jump: %s then %s" % [ended, _pose_angle()])


## Degrees the body's staff points off right now (its animation's turn on its locked aim).
func _pose_angle() -> float:
	return rad_to_deg(_spells.staff_pose_dir(0).rotated(_spells.staff_pose(0).x).angle())


func test_the_split_swings_of_one_cast_turn_the_same_way() -> void:
	var split := ModifierBase.new()
	split.shot_mult = 2
	_put(split, &"split")
	_build([&"split", &"swing"])
	_cast()
	var sides: Array[int] = []
	for at in _spells.swing_slots():
		if _spells.swing_on(at):
			sides.append(_spells.swing_side(at))
	check_equal(sides, [1, 1] as Array[int], "both swings of a cleave are forehands")


func test_a_held_swing_sweeps_back_and_forth_until_switched_off() -> void:
	# Rules R4e (owner, 2026-10-29): a held swing used to sweep once.
	var front: Node2D = _at(0.0)
	_build([&"hold", &"swing"])
	_cast()
	check(_spells.is_holding(0, 0), "a held swing is on")
	var sides: Array[int] = []
	for step in 60:
		_tick(1)
		var at: int = _row()
		if at >= 0 and (sides.is_empty() or sides[-1] != _spells.swing_side(at)):
			sides.append(_spells.swing_side(at))
	check(sides.size() >= 4, "it swung again and again: %s" % [sides])
	for n in range(1, sides.size()):
		check(sides[n] == -sides[n - 1], "each sweep turns back the other way: %s" % [sides])
	check(_struck(front) >= 4, "and struck the body in front each time (%d)" % _struck(front))
	_cast()
	check(not _spells.is_holding(0, 0), "the next press switches it off")
	var struck: int = _struck(front)
	_tick(60)
	check_equal(_struck(front), struck, "and it swings no more")
	check_equal(_spells.swing_count(), 0, "no swing is left")


func test_a_held_swing_turns_with_the_aim() -> void:
	_build([&"hold", &"swing"])
	_spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	_cast()
	_tick(12)
	_spells.set_aim(0, Vector2.ZERO, Vector2.DOWN)
	var dirs: Array[Vector2] = []
	for step in 30:
		_tick(1)
		var at: int = _row()
		if at >= 0:
			dirs.append(_spells.swing_dir(at))
	check(not dirs.is_empty() and dirs[-1].is_equal_approx(Vector2.DOWN), "a later sweep is centred on the aim now: %s" % [dirs])
