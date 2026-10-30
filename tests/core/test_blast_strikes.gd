extends "res://tests/support/suite.gd"
## Card rules R4 F2 (docs/milestones/M2-rules.md, owner 2026-10-30): one strike for every area. A
## blast strikes every body round its end point through the one strike a swing, a slam, a dash, a
## teleport and a rain use (`Spells._strike`), so each body it catches is a hit of its carrier:
## `on hit`, chain, siphon and the rest work on it, its caster's own body is caught too, and a hit
## of a blast does not blast again. A strike keeps what relay took on and what an echo hits with.
## It runs a real projectile manager and event bus, stepped by hand, with cards built in code.
##
## godot --headless --path . --script res://tests/core/test_blast_strikes.gd

const StaffKit := preload("res://tests/support/staff_kit.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ArenaScript := preload("res://tests/content/spells/combo_arena.gd")

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
## Every projectile_hit as [caster, target, at, tag, damage of its hit].
var _hits: Array = []
## Every blast cue, every caster_move_requested and every mana refund, as their positions or amounts.
var _blasts: Array = []
var _moves: Array = []
var _refunds: Array = []


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
	_hits.clear()
	_blasts.clear()
	_moves.clear()
	_refunds.clear()
	_bus.projectile_hit.connect(func(caster: int, target: Node, at: Vector2, tag: int, shot: int) -> void:
		var hit: HitProfile = _spells.hit_profile(tag, shot)
		_hits.append([caster, target, at, tag, hit.damage if hit != null else -1]))
	_bus.cue_shown.connect(func(_caster: int, _cue: StringName, at: Vector2, _direction: Vector2, _size: float, _tint: Color, _look: int) -> void:
		_blasts.append(at))
	_bus.caster_move_requested.connect(func(_caster: int, _mode: StringName, to: Vector2, _seconds: float, _tag: int) -> void:
		_moves.append(to))
	_bus.mana_refund_requested.connect(func(_caster: int, amount: float) -> void:
		_refunds.append(amount))
	_form(&"bolt", 300.0, 1.0)
	var decoy: FormBase = _form(&"decoy", 0.0, 2.0)
	decoy.carrier = &"decoy"
	_form(&"barb", 300.0, 1.0)
	_modifier(&"pull", ModifierBase.Behaviour.PULL, 1.0)
	var slam: FormBase = _form(&"slam", 0.0, 0.12)
	slam.carrier = &"slam"
	slam.ray_length = 20.0
	slam.radius = 16.0
	_modifier(&"blast", ModifierBase.Behaviour.BLAST, 30.0)
	_modifier(&"chain", ModifierBase.Behaviour.CHAIN, 1.0)
	_modifier(&"siphon", ModifierBase.Behaviour.SIPHON, 2.0)
	_modifier(&"echo", ModifierBase.Behaviour.ECHO, 0.2)
	var on_hit := TriggerBase.new()
	on_hit.event = TriggerBase.Event.HIT
	_put(on_hit, &"on_hit")


func _put(component: SpellComponent, id: StringName) -> void:
	component.id = id
	component.display_name = String(id).capitalize()
	component.complexity = 1
	_fake.items[id] = component


func _form(id: StringName, speed: float, lifetime: float) -> FormBase:
	var form := FormBase.new()
	form.base_damage = 6
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


func _build(cards: Array[StringName]) -> int:
	StaffKit.build(_spells, 0, 0, cards)
	return _spells.current_tag(0, 0, 0)


func _target(position: Vector2, owner: int = EventsScript.NO_PLAYER) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = position
	own(node)
	_mgr.add_target(node, 6.0, ManagerScript.LAYER_ENEMY if owner == EventsScript.NO_PLAYER else ManagerScript.LAYER_PLAYER, owner)
	return node


func _cast() -> void:
	_spells.cast_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, 100.0)


func _tick(steps: int) -> void:
	for i in steps:
		_mgr.step(DT)
		_spells.step(DT)


func _hits_on(target: Node, tag: int) -> int:
	var count: int = 0
	for hit: Array in _hits:
		if hit[1] == target and hit[3] == tag:
			count += 1
	return count


# --- A blast's hits are its carrier's hits ---------------------------------------------------

func test_a_blast_strikes_each_body_round_its_end_point_as_a_hit_of_its_carrier() -> void:
	var tag: int = _build([&"blast", &"bolt"])
	var struck: Node2D = _target(Vector2(60.0, 0.0))
	var near: Node2D = _target(Vector2(66.0, 20.0))
	var far: Node2D = _target(Vector2(60.0, 70.0))
	_cast()
	_tick(20)
	check_equal(_blasts.size(), 1, "one explosion")
	check_equal(_hits_on(struck, tag), 2, "the body the bolt hit: the bolt's hit, then its blast's")
	check_equal(_hits_on(near, tag), 1, "a body near it is hit by the blast, under the bolt's tag")
	check_equal(_hits_on(far, tag), 0, "one outside it is not")


func test_a_lone_blast_strikes_its_own_caster() -> void:
	var tag: int = _build([&"blast"])
	var body: Node2D = _target(Vector2.ZERO, 0)
	var enemy: Node2D = _target(Vector2(15.0, 0.0))
	_cast()
	check_equal(_hits_on(body, tag), 1, "the caster is inside their own blast (self-harm)")
	check_equal(_hits_on(enemy, tag), 1, "and so is the enemy next to them")


func test_on_hit_and_siphon_work_on_a_decoy_through_its_blast() -> void:
	var cards: Array[StringName] = [&"siphon", &"on_hit", &"blast", &"decoy", &"bolt"]
	var staff: CompiledStaff = StaffKit.compile(_spells, cards)
	check(staff.wasted.is_empty(), "nothing on a blasting decoy is wasted: %s" % staff.wasted)
	var tag: int = _build(cards)
	var one: Node2D = _target(Vector2(50.0, 20.0))
	var two: Node2D = _target(Vector2(60.0, 30.0))
	_cast()
	_bus.entity_ended.emit(0, &"decoy", Vector2(50.0, 25.0), tag)
	check_equal(_hits_on(one, tag) + _hits_on(two, tag), 2, "both bodies are hits of the decoy")
	check_equal(_refunds.size(), 2, "siphon refunds on each")
	check_equal(_mgr.get_count(), 2, "and on hit fires a bolt from each")


func test_a_hit_of_a_blast_does_not_blast_again_and_a_chain_runs_out() -> void:
	_build([&"chain", &"blast", &"bolt"])
	_target(Vector2(60.0, 0.0))
	_target(Vector2(70.0, 15.0))
	_target(Vector2(75.0, -15.0))
	_cast()
	_tick(240)
	check_equal(_mgr.get_count(), 0, "every jump has landed: a jump's blast jumps with the jumps it has left")
	check(_blasts.size() < 20, "a bounded number of explosions (%d)" % _blasts.size())


func test_a_pulling_shots_blast_moves_nothing_more() -> void:
	var tag: int = _build([&"blast", &"pull", &"barb"])
	_target(Vector2(60.0, 0.0))
	_target(Vector2(50.0, 10.0))
	_cast()
	_tick(20)
	check_equal(_moves.size(), 1, "the shot pulls once, to its hit")
	_bus.caster_move_finished.emit(0, &"pull", Vector2(55.0, 0.0), tag)
	check_equal(_blasts.size(), 1, "it explodes where the wizard arrives")
	check_equal(_moves.size(), 1, "what the explosion strikes pulls the wizard no more")


# --- What a strike hits with ---------------------------------------------------------------

func test_an_echoed_slam_strikes_at_the_echos_half() -> void:
	var tag: int = _build([&"echo", &"slam"])
	_target(Vector2(20.0, 0.0))
	_cast()
	_tick(60)
	var damages: Array = []
	for hit: Array in _hits:
		if hit[3] == tag:
			damages.append(hit[4])
	check_equal(damages.size(), 2, "the slam and its echo strike: %s" % [damages])
	if damages.size() == 2:
		check(int(damages[1]) < int(damages[0]), "the echo at less: %s" % [damages])


func test_a_relay_swing_keeps_what_it_took_on_for_the_rest_of_its_sweep() -> void:
	for relay: bool in [false, true]:
		var arena := ArenaScript.new(root)
		# The swing turns from above its aim to below it: the teammate first, then the imp.
		arena.add_mate(Vector2(14.0, -12.0), 1)
		var imp: Node2D = arena.add_imp(Vector2(14.0, 12.0))
		arena.install_cards(1, 0, ["frost", "bolt"])
		arena.install_cards(0, 0, ["relay", "swing"] if relay else ["swing"])
		check(arena.cast(1, 0, Vector2.UP), "the teammate casts frost, away from the imp")
		arena.run(0.1)
		check(arena.cast(0, 0), "the swing is cast")
		arena.run(0.5)
		check_equal(arena.was_given(imp, &"chill"), relay, "the imp struck after the teammate is chilled only with relay")
		arena.free_all()
