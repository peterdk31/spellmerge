extends "res://tests/support/suite.gd"
## Card rules R4c (docs/milestones/M2-rules.md, owner 2026-10-29): the moves. A dash hits every
## body its mover passes, once each, and a teleport what is where it lands, so the hit cards work
## on them as on a shot; recoil adds to a move (a teleport's is taken off its distance, a dash's
## runs with it); a shield guards whatever a move moves (the wizard by a barrier, a shot by shield
## charges), on a swap too; and a move cast by a point (its shot is gone) moves the wizard. It runs
## a real projectile manager and event bus, stepped by hand, with cards built in code; the
## wizard's body is its anchor, moved by the test as its mover would.
##
## godot --headless --path . --script res://tests/core/test_spells_move_hits.gd

const StaffKit := preload("res://tests/support/staff_kit.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

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
## Every projectile_hit as [caster, target, at, tag].
var _hits: Array = []
## Every caster_move_requested as [caster, mode, to, seconds, tag].
var _moves: Array = []
## Every wizard_shield_requested as [caster, charges, seconds, tag].
var _barriers: Array = []


func before_each() -> void:
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_cap(256)
	_mgr.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _fake
	_spells.bind(_mgr, _bus)
	_mgr.set_anchor(0, Vector2.ZERO)
	_spells.set_aim(0, Vector2.ZERO, Vector2.RIGHT)
	_hits.clear()
	_moves.clear()
	_barriers.clear()
	_bus.projectile_hit.connect(func(caster: int, target: Node, at: Vector2, tag: int, _shot: int) -> void:
		_hits.append([caster, target, at, tag]))
	_bus.caster_move_requested.connect(func(caster: int, mode: StringName, to: Vector2, seconds: float, tag: int) -> void:
		_moves.append([caster, mode, to, seconds, tag]))
	_bus.wizard_shield_requested.connect(func(caster: int, charges: int, seconds: float, tag: int) -> void:
		_barriers.append([caster, charges, seconds, tag]))
	# A dash of 48 px over 0.2 s, a teleport of 100 px, a bolt of 300 px over 1 s, a hook and a swap.
	var dash: FormBase = _form(&"dash", 240.0, 0.2)
	dash.carrier = &"dash"
	dash.ray_length = 48.0
	var teleport: FormBase = _form(&"teleport", 400.0, 0.25)
	teleport.carrier = &"teleport"
	teleport.ray_length = 100.0
	_form(&"bolt", 300.0, 1.0)
	var hook: FormBase = _form(&"hook", 300.0, 1.0)
	hook.carrier = &"hook"
	var swap: FormBase = _form(&"swap", 300.0, 1.0)
	swap.carrier = &"swap"
	_modifier(&"chain", ModifierBase.Behaviour.CHAIN, 1.0)
	_modifier(&"recoil", ModifierBase.Behaviour.RECOIL, 20.0)
	_modifier(&"kick", ModifierBase.Behaviour.RECOIL, 130.0)
	_modifier(&"shield", ModifierBase.Behaviour.SHIELD, 2.0)
	var piercing := ModifierBase.new()
	piercing.extra_pierce = 1
	_put(piercing, &"pierce")
	var timer: TriggerBase = _trigger(&"timer", TriggerBase.Event.TIMER)
	timer.interval = 0.25
	_trigger(&"on_expire", TriggerBase.Event.EXPIRE)


func _put(component: SpellComponent, id: StringName) -> void:
	component.id = id
	component.display_name = String(id).capitalize()
	component.complexity = 1
	_fake.items[id] = component


func _form(id: StringName, speed: float, lifetime: float) -> FormBase:
	var form := FormBase.new()
	form.base_damage = 5
	form.speed = speed
	form.lifetime = lifetime
	form.mana_cost = 1.0
	_put(form, id)
	return form


func _modifier(id: StringName, behaviour: ModifierBase.Behaviour, strength: float) -> void:
	var modifier := ModifierBase.new()
	modifier.behaviour = behaviour
	modifier.behaviour_strength = strength
	_put(modifier, id)


func _trigger(id: StringName, event: TriggerBase.Event) -> TriggerBase:
	var trigger := TriggerBase.new()
	trigger.event = event
	_put(trigger, id)
	return trigger


func _build(cards: Array[StringName]) -> int:
	StaffKit.build(_spells, 0, 0, cards)
	return _spells.current_tag(0, 0, 0)


func _target(position: Vector2) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = position
	own(node)
	_mgr.add_target(node, 6.0, ManagerScript.LAYER_ENEMY, EventsScript.NO_PLAYER)
	return node


func _cast() -> void:
	_spells.cast_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, 100.0)


## Steps the world, the wizard's body going `step` px along +x each step (its mover's dash).
func _tick(steps: int, step: float = 0.0) -> void:
	for i in steps:
		_mgr.set_anchor(0, _mgr.get_anchor(0) + Vector2(step, 0.0))
		_mgr.step(DT)
		_spells.step(DT)


## How many hits `target` took from `tag`.
func _hits_on(target: Node, tag: int) -> int:
	var count: int = 0
	for hit: Array in _hits:
		if hit[1] == target and hit[3] == tag:
			count += 1
	return count


# --- A dash hits what it passes, a teleport what is where it lands -----------------------------

func test_a_dash_hits_every_body_it_passes_once_each() -> void:
	var tag: int = _build([&"dash"])
	var near: Node2D = _target(Vector2(20.0, 0.0))
	var far: Node2D = _target(Vector2(40.0, 3.0))
	var aside: Node2D = _target(Vector2(30.0, 40.0))
	var beyond: Node2D = _target(Vector2(90.0, 0.0))
	_cast()
	# 48 px over 0.2 s: 4 px a step for 12 steps, then it stands.
	_tick(12, 4.0)
	_tick(20)
	check_equal(_hits_on(near, tag), 1, "the first body on its way is hit once")
	check_equal(_hits_on(far, tag), 1, "and the second")
	check_equal(_hits_on(aside, tag), 0, "a body off its way is not")
	check_equal(_hits_on(beyond, tag), 0, "nor one past its end")


func test_a_fast_dash_misses_nothing_between_two_steps() -> void:
	var tag: int = _build([&"dash"])
	var between: Node2D = _target(Vector2(25.0, 0.0))
	_cast()
	# 48 px in one step, the body never near the target at a step's end.
	_tick(1, 48.0)
	_tick(10)
	check_equal(_hits_on(between, tag), 1, "the body passed it, so it is hit")


func test_a_chain_dash_jumps_from_what_it_hits() -> void:
	var tag: int = _build([&"chain", &"dash"])
	var first: Node2D = _target(Vector2(20.0, 0.0))
	var second: Node2D = _target(Vector2(20.0, 50.0))
	_cast()
	_tick(12, 4.0)
	check_equal(_hits_on(first, tag), 1, "the dash hits the body on its way")
	check_equal(_hits_on(second, tag), 1, "and its chain jumps on to the next")


func test_a_teleport_hits_what_is_where_it_lands() -> void:
	var tag: int = _build([&"teleport"])
	var there: Node2D = _target(Vector2(100.0, 10.0))
	var on_the_way: Node2D = _target(Vector2(50.0, 0.0))
	_cast()
	check_equal(_hits.size(), 0, "nothing before it has landed")
	_bus.caster_move_finished.emit(0, &"teleport", Vector2(100.0, 0.0), tag)
	check_equal(_hits_on(there, tag), 1, "the body where it landed is hit")
	check_equal(_hits_on(on_the_way, tag), 0, "a teleport passes nothing on its way")


func test_pierce_is_wasted_on_a_dash_that_hits_everything_it_passes() -> void:
	var staff: CompiledStaff = StaffKit.compile(_spells, [&"pierce", &"dash"])
	check(staff.wasted.has(0), "pierce is wasted on a dash: %s" % staff.wasted)
	check(String(staff.wasted.get(0, "")).contains("hits what it passes"), "because it hits what it passes already: %s" % staff.wasted)
	check(StaffCompiler.trigger_runs(TriggerBase.Event.HIT, &"dash"), "on hit fires on a dash")
	check(StaffCompiler.behaviour_runs(ModifierBase.Behaviour.HEAVY, &"teleport"), "heavy works on a teleport")


# --- Recoil adds to a move ----------------------------------------------------------------------

func test_recoil_shortens_a_teleport() -> void:
	_build([&"recoil", &"teleport"])
	_cast()
	check_equal(_moves.size(), 1, "one move, no separate push")
	check(_moves.size() == 1 and _moves[0][1] == &"teleport" and _moves[0][2].is_equal_approx(Vector2(80.0, 0.0)), "100 px less 20: %s" % [_moves])


func test_a_recoil_longer_than_the_teleport_sends_it_backwards() -> void:
	_build([&"kick", &"teleport"])
	_cast()
	check(_moves.size() == 1 and _moves[0][2].is_equal_approx(Vector2(-30.0, 0.0)), "100 px less 130 is 30 back: %s" % [_moves])


func test_recoil_on_a_dash_is_a_push_that_runs_with_it() -> void:
	_build([&"recoil", &"dash"])
	_cast()
	var modes: Array[StringName] = []
	for move: Array in _moves:
		modes.append(move[1])
	check(modes.has(&"dash") and modes.has(&"recoil"), "the dash and its push back, which the body adds up: %s" % [modes])


# --- One shield rule for every move -------------------------------------------------------------

func test_a_swap_guards_the_wizard_for_the_move() -> void:
	var tag: int = _build([&"shield", &"swap"])
	_target(Vector2(60.0, 0.0))
	_cast()
	_tick(30)
	check(_moves.size() == 1 and _moves[0][1] == &"swap", "the wizard swapped: %s" % [_moves])
	check(_barriers.size() == 1 and _barriers[0][1] == 2 and _barriers[0][3] == tag, "with a barrier of the card's charges: %s" % [_barriers])


func test_a_dash_in_a_payload_gives_the_shot_it_moves_its_shield() -> void:
	_build([&"timer", &"bolt", &"shield", &"dash"])
	_cast()
	var bolt: int = -1
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot):
			bolt = slot
	check_equal(_mgr.get_shield_of(bolt), 0, "the bolt has no shield of its own")
	_tick(16)
	check(_mgr.is_alive(bolt), "the bolt still flies")
	check_equal(_mgr.get_shield_of(bolt), 2, "its dash guards it with the card's charges")
	check_equal(_barriers.size(), 0, "the wizard is not guarded: it does not move")


# --- A point cannot move: the wizard does -------------------------------------------------------

func test_a_teleport_cast_by_a_point_blinks_the_wizard_to_it() -> void:
	_spells.set_aim(0, Vector2(10.0, 0.0), Vector2.RIGHT)
	_build([&"on_expire", &"bolt", &"teleport"])
	_cast()
	# The bolt flies 300 px and ends; its teleport is cast by that point.
	_tick(65)
	check_equal(_moves.size(), 1, "the wizard is asked to move")
	# Measured from its staff tip (10, 0), as every teleport: the body goes the 300 px to the point.
	check(_moves.size() == 1 and _moves[0][1] == &"teleport" and _moves[0][2].distance_to(Vector2(310.0, 0.0)) < 6.0, "to the point: %s" % [_moves])


func test_a_hook_cast_by_a_point_pulls_the_wizard() -> void:
	_build([&"on_expire", &"bolt", &"hook"])
	_target(Vector2(360.0, 0.0))
	_cast()
	_tick(90)
	check(_moves.size() == 1 and _moves[0][1] == &"hook" and _moves[0][2].x > 340.0, "the wizard is pulled to the hit: %s" % [_moves])
