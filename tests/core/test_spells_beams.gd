extends "res://tests/support/suite.gd"
## Tests for live beams (owner, 2026-10-27): a beam lives its `lifetime` like a shot, hits at once
## and then every `SpellLimits.BEAM_TICK`, follows its caster (the wizard's aim from `set_aim`, or
## the shot that fired it), bends along a curve onto a target when it homes, stays on with `hold`
## until it is switched off, and ends where it got (blast, on expire). It runs a real projectile
## manager and event bus, stepped by hand, with cards built in code.
##
## godot --headless --path . --script res://tests/core/test_spells_beams.gd

const StaffKit := preload("res://tests/support/staff_kit.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")

const DT: float = 1.0 / 60.0


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


func before_each() -> void:
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_cap(512)
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _fake
	_spells.bind(_mgr, _bus)
	_mgr.set_anchor(0, Vector2.ZERO)
	_hits.clear()
	_areas.clear()
	_bus.projectile_hit.connect(func(player: int, target: Node, at: Vector2, tag: int) -> void:
		_hits.append([player, target, at, tag]))
	_bus.area_hit_requested.connect(func(player: int, at: Vector2, radius: float, tag: int) -> void:
		_areas.append([player, at, radius, tag]))
	var beam: FormBase = _form(&"beam", 0.0, 0.3)
	beam.motion = FormBase.Motion.RAY
	beam.ray_length = 200.0
	beam.radius = 6.0
	var bolt: FormBase = _form(&"bolt", 300.0, 1.0)
	bolt.radius = 2.0
	_modifier(&"bounce", ModifierBase.Behaviour.BOUNCE, 3.0)
	_modifier(&"homing", ModifierBase.Behaviour.HOMING, 3.0)
	(_fake.items[&"homing"] as ModifierBase).behaviour_reach = 160.0
	_modifier(&"far_homing", ModifierBase.Behaviour.HOMING, 3.0)
	(_fake.items[&"far_homing"] as ModifierBase).behaviour_reach = 340.0
	var piercing := ModifierBase.new()
	piercing.extra_pierce = 1
	_put(piercing, &"pierce")
	_modifier(&"hold", ModifierBase.Behaviour.HOLD, 1.0)
	_modifier(&"blast", ModifierBase.Behaviour.BLAST, 30.0)
	var timer := TriggerBase.new()
	timer.event = TriggerBase.Event.TIMER
	timer.interval = 0.25
	_put(timer, &"timer")


func _put(component: SpellComponent, id: StringName) -> void:
	component.id = id
	component.display_name = String(id).capitalize()
	component.complexity = 1
	_fake.items[id] = component


func _form(id: StringName, speed: float, lifetime: float) -> FormBase:
	var form := FormBase.new()
	form.base_damage = 2
	form.speed = speed
	form.lifetime = lifetime
	form.mana_cost = 2.0
	_put(form, id)
	return form


func _modifier(id: StringName, behaviour: ModifierBase.Behaviour, strength: float) -> void:
	var modifier := ModifierBase.new()
	modifier.behaviour = behaviour
	modifier.behaviour_strength = strength
	_put(modifier, id)


func _build(cards: Array[StringName]) -> int:
	StaffKit.build(_spells, 0, 0, cards)
	return _spells.current_tag(0, 0, 0)


func _cast(origin: Vector2 = Vector2.ZERO, direction: Vector2 = Vector2.RIGHT) -> float:
	return _spells.cast_staff(0, 0, origin, direction, 100.0)


func _target(position: Vector2) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = position
	own(node)
	_mgr.add_target(node, 10.0, ManagerScript.LAYER_ENEMY, EventsScript.NO_PLAYER)
	return node


func _tick(steps: int) -> void:
	for i in steps:
		_mgr.step(DT)
		_spells.step(DT)


## The row of the one live beam, or -1.
func _beam() -> int:
	for at in _spells.beam_slots():
		if _spells.beam_on(at):
			return at
	return -1


func test_a_beam_hits_at_once_then_every_tick_until_its_life_is_over() -> void:
	_target(Vector2(100, 0))
	var tag: int = _build([&"beam"])
	_cast()
	check_equal(_hits.size(), 1, "a hit at once")
	check_equal(_spells.beam_count(), 1, "the beam stays on")
	_tick(60)
	check_equal(_hits.size(), SpellsScript.beam_hits(FormBase.Motion.RAY, 0.3), "one hit every tick of its 0.3 s life")
	check_equal(_spells.beam_count(), 0, "then it is gone")
	check_equal(_spells.live_shots(tag), 0, "and no longer counted")


func test_a_beam_follows_the_wizards_aim_while_it_lives() -> void:
	_build([&"beam"])
	_spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	_cast()
	_spells.set_aim(0, Vector2(10, 5), Vector2.DOWN)
	_tick(1)
	var at: int = _beam()
	check_equal(_spells.beam_origin(at), Vector2(10, 5), "from the staff tip where it is now")
	check(_spells.beam_origin(at).direction_to(_spells.beam_end(at)).is_equal_approx(Vector2.DOWN), "along the aim as it is now")


func test_a_downed_wizards_beam_ends() -> void:
	_build([&"beam"])
	_spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	_cast()
	_spells.clear_aim(0)
	_tick(1)
	check_equal(_spells.beam_count(), 0, "a wizard with no aim holds no beam")


func test_a_homing_beam_bends_onto_a_target_off_its_line() -> void:
	var off: Node2D = _target(Vector2(100, 45))
	_build([&"beam"])
	_cast()
	check(_hits.is_empty(), "a straight beam misses a target 45 px off its line")
	_tick(30)
	_hits.clear()
	_build([&"homing", &"beam"])
	_cast()
	var at: int = _beam()
	check(_spells.beam_end(at).is_equal_approx(off.global_position), "it ends on the target: %s" % _spells.beam_end(at))
	check(is_equal_approx(_spells.beam_bend(at).y, 0.0) and _spells.beam_bend(at).x > 0.0, "it leaves along the aim and bends: %s" % _spells.beam_bend(at))
	check(_hits.size() == 1 and _hits[0][1] == off, "and hits it")


func test_a_homing_beam_never_reaches_past_its_length() -> void:
	# The card looks 340 px; the beam is 200 px long: it bends toward the target but stops short.
	var far: Node2D = _target(Vector2(280, 40))
	_build([&"far_homing", &"beam"])
	_cast()
	var at: int = _beam()
	check(_spells.beam_end(at).is_equal_approx(far.global_position), "it bends toward a target past its end")
	check(_hits.is_empty(), "but does not hit it")
	check(_spells.beam_reach(at) <= 200.0 + 0.01, "it is cut at its 200 px: %s" % _spells.beam_reach(at))


func test_a_homing_beam_with_pierce_bends_on_to_another_target_after_a_hit() -> void:
	# The second stands outside the 45 degree bend from the staff, but inside it from the first.
	var first: Node2D = _target(Vector2(60, 20))
	var second: Node2D = _target(Vector2(80, 90))
	_build([&"homing", &"beam"])
	_cast()
	check(_hits.size() == 1 and _hits[0][1] == first, "without pierce it ends on the first: %s" % [_hits])
	_tick(30)
	_hits.clear()
	_build([&"homing", &"pierce", &"beam"])
	_cast()
	var hit: Array = []
	for h: Array in _hits:
		hit.append(h[1])
	check(hit.has(first) and hit.has(second), "with pierce it hits one, then bends on to the other: %s" % [hit])
	var at: int = _beam()
	check(_spells.beam_point_count(at) > ManagerScript.RAY_SEGMENTS + 1, "its path has a second bend (%d points)" % _spells.beam_point_count(at))


func test_a_held_beam_stays_on_until_its_staff_is_cast_again() -> void:
	var tag: int = _build([&"hold", &"beam"])
	_cast()
	_tick(300)
	check_equal(_spells.beam_count(), 1, "on after five seconds")
	check(_spells.is_holding(0, 0), "the staff holds it")
	_tick(30)
	_cast()
	check_equal(_spells.beam_count(), 0, "a second cast switches it off")
	check_equal(_spells.live_shots(tag), 0, "and it is no longer counted")


func test_a_beam_ends_with_its_blast_where_it_got() -> void:
	_build([&"blast", &"beam"])
	_cast()
	check(_areas.is_empty(), "no blast while it is on")
	_tick(30)
	check(_areas.size() == 1 and absf(_areas[0][1].x - 200.0) < 1.0, "one blast at its far end: %s" % [_areas])


func test_a_beam_in_a_payload_follows_the_shot_that_fired_it() -> void:
	_build([&"timer", &"bolt", &"beam"])
	_cast()
	var bolt: int = -1
	for at in _mgr.get_cap():
		if _mgr.is_alive(at):
			bolt = at
	_tick(17)
	var beam: int = _beam()
	check(beam >= 0, "the timer cast a beam")
	_tick(5)
	check(_spells.beam_origin(beam).is_equal_approx(_mgr.get_position_of(bolt)), "it leaves from the bolt as it flies: %s, %s" % [_spells.beam_origin(beam), _mgr.get_position_of(bolt)])
	check(_spells.beam_origin(beam).direction_to(_spells.beam_end(beam)).is_equal_approx(Vector2.RIGHT), "along the bolt's way")


func test_a_curved_ray_hits_a_target_on_its_curve_once() -> void:
	var on_curve: Node2D = _target(Vector2(100, 40))
	var on_line: Node2D = _target(Vector2(100, -40))
	var hits: Array = []
	_bus.projectile_hit.connect(func(_player: int, target: Node, _at: Vector2, _tag: int) -> void: hits.append(target))
	var got: float = _mgr.ray_curve(0, Vector2.ZERO, Vector2(60, 0), Vector2(100, 40), 4, ManagerScript.LAYER_ENEMY, 1, 2.0)
	check(got > 0.0, "it got somewhere")
	check(hits.has(on_curve), "the target at the curve's end is hit")
	check(not hits.has(on_line), "one off the curve is not")
	check_equal(hits.count(on_curve), 1, "a target touched by two pieces is hit once")
	check(_mgr.ray_end.is_finite(), "where it ended is known")


func test_homing_cards_stack_by_multiplying() -> void:
	var one: CompiledSpell = StaffKit.first(_spells, [&"homing", &"bolt"] as Array[StringName])
	var two: CompiledSpell = StaffKit.first(_spells, [&"homing", &"homing", &"bolt"] as Array[StringName])
	var three: CompiledSpell = StaffKit.first(_spells, [&"homing", &"homing", &"homing", &"bolt"] as Array[StringName])
	check(is_equal_approx(one.homing_turn, 3.0) and is_equal_approx(one.homing_angle, rad_to_deg(3.0 * SpellLimits.INSTANT_HOMING_SECONDS)), "one card: its own turn rate, and the bend that turns in INSTANT_HOMING_SECONDS")
	check(is_equal_approx(two.homing_turn, 3.0 * SpellLimits.HOMING_STACK), "two turn %s times faster: %s" % [SpellLimits.HOMING_STACK, two.homing_turn])
	check(is_equal_approx(three.homing_turn, 3.0 * SpellLimits.HOMING_STACK * SpellLimits.HOMING_STACK), "three faster again: %s" % three.homing_turn)
	check(is_equal_approx(two.homing_angle, rad_to_deg(two.homing_turn * SpellLimits.INSTANT_HOMING_SECONDS)), "a beam bends wider with two, as it turns faster: %s" % two.homing_angle)
	check(is_equal_approx(three.homing_angle, rad_to_deg(three.homing_turn * SpellLimits.INSTANT_HOMING_SECONDS)), "and wider with three, past 90 degrees: %s" % three.homing_angle)
	var many: CompiledSpell = StaffKit.first(_spells, [&"homing", &"homing", &"homing", &"homing", &"homing", &"bolt"] as Array[StringName])
	check(is_equal_approx(many.homing_angle, 180.0), "until it bends all the way round: %s" % many.homing_angle)


func test_two_homing_cards_bend_a_beam_onto_a_target_one_cannot_reach() -> void:
	# 60 degrees off the aim: past one card's 43, inside two cards' 64.
	var off: Node2D = _target(Vector2.from_angle(deg_to_rad(60.0)) * 100.0)
	_build([&"homing", &"beam"])
	_cast()
	check(not _spells.beam_end(_beam()).is_equal_approx(off.global_position), "one homing card does not reach it")
	_tick(30)
	_build([&"homing", &"homing", &"beam"])
	_cast()
	check(_spells.beam_end(_beam()).is_equal_approx(off.global_position), "two do: %s" % _spells.beam_end(_beam()))


## A wall the beam meets on its way down to the right, at x = 80: a beam that turns off it comes
## back down to the left, over (40, 120).
func _turning_room() -> void:
	_mgr.set_walls([Rect2(80.0, -200.0, 16.0, 400.0)] as Array[Rect2])


func test_a_bouncing_beam_turns_at_a_wall_and_hits_what_is_past_the_turn() -> void:
	_turning_room()
	var behind: Node2D = _target(Vector2(40.0, 120.0))
	_build([&"beam"])
	_cast(Vector2.ZERO, Vector2(1.0, 1.0).normalized())
	check_equal(_hits.size(), 0, "a plain beam stops at the wall")
	_tick(60)
	_build([&"bounce", &"beam"])
	_cast(Vector2.ZERO, Vector2(1.0, 1.0).normalized())
	check_equal(_hits.size(), 1, "the bouncing beam hits it")
	if not _hits.is_empty():
		check(_hits[0][1] == behind, "the target past the turn")
	var at: int = _beam()
	check(at >= 0, "the beam is on")
	if at < 0:
		return
	check(_spells.beam_reach(at) > 114.0, "it got past the turn, to the target that spends it (%s)" % str(_spells.beam_reach(at)))
	check(_spells.beam_point_count(at) >= 3, "its path has the turn, so it is drawn along it")
	var turn: Vector2 = _spells.beam_point(at, 1)
	check(turn.x > 79.0 and turn.x < 80.0, "the turn is at the wall (%s)" % str(turn))
	_tick(30)
	check_equal(_hits.size(), SpellsScript.beam_hits(FormBase.Motion.RAY, 0.3), "it hits it every tick of its life, along the same turn")


func test_a_bouncing_beam_ends_its_blast_past_the_turn() -> void:
	_turning_room()
	_build([&"bounce", &"blast", &"beam"])
	_cast(Vector2.ZERO, Vector2(1.0, 1.0).normalized())
	_tick(30)
	check_equal(_areas.size(), 1, "one blast at its end")
	if not _areas.is_empty():
		var at: Vector2 = _areas[0][1]
		check(at.x < 80.0 and at.y > 80.0, "back off the wall, where it got (%s)" % str(at))


## The general rule (owner, 2026-10-29): a turn at a wall takes none of a beam's cards away, so a
## homing beam homes again from the wall, as a homing shot does after it bounces. The target is
## outside the beam's homing cone from the staff (52 degrees off its aim) and inside it from the
## turn, off the straight line back.
func test_a_homing_beam_homes_again_after_it_turns_at_a_wall() -> void:
	_turning_room()
	var long: FormBase = _form(&"long_beam", 0.0, 0.3)
	long.motion = FormBase.Motion.RAY
	long.ray_length = 300.0
	long.radius = 6.0
	var behind: Node2D = _target(Vector2(-5.0, 120.0))
	_build([&"bounce", &"long_beam"])
	_cast(Vector2.ZERO, Vector2(1.0, 1.0).normalized())
	check_equal(_hits.size(), 0, "without homing it turns and goes straight, past the target")
	_tick(60)
	_build([&"homing", &"bounce", &"long_beam"])
	_cast(Vector2.ZERO, Vector2(1.0, 1.0).normalized())
	check_equal(_hits.size(), 1, "with homing it bends onto it after the turn")
	if not _hits.is_empty():
		check(_hits[0][1] == behind, "the target past the turn")
	var at: int = _beam()
	if at >= 0:
		check(_spells.beam_point_count(at) > 3, "its drawn path bends after the turn (%d points)" % _spells.beam_point_count(at))
