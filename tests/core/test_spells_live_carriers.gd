extends "res://tests/support/suite.gd"
## Tests for the live-carrier clock (rules R4d, owner 2026-10-29): every carrier that lasts keeps
## a timer and hears `on hurt` while it lives, and fires from where it is now (a shot, a beam's
## tip, a rain's spot, a decoy, the caster's body during a dash); the first timer tick and the
## first arc zap come after the interval or half the carrier's life, whichever is shorter. It
## runs a real projectile manager and event bus, stepped by hand, with cards built in code.
##
## godot --headless --path . --script res://tests/core/test_spells_live_carriers.gd

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
## Every projectile_hit as [tag, position].
var _hits: Array = []


func before_each() -> void:
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_cap(512)
	_mgr.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _fake
	_spells.bind(_mgr, _bus)
	_hits.clear()
	_bus.projectile_hit.connect(func(_caster: int, _target: Node, at: Vector2, tag: int) -> void: _hits.append([tag, at]))
	# A shot of 0.4 s, as short as a nova's.
	_form(&"short", 300.0, 0.4)
	var rune: FormBase = _form(&"rune", 0.0, 10.0)
	# The probe: a shot that does not move marks where a payload fires (a placed rune would
	# appear a step ahead of it, rules R4 F3).
	rune.motion = FormBase.Motion.STRAIGHT
	rune.radius = 6.0
	var beam: FormBase = _form(&"beam", 0.0, 0.4)
	beam.motion = FormBase.Motion.RAY
	beam.ray_length = 200.0
	var rain: FormBase = _form(&"rain", 0.0, 0.8)
	rain.motion = FormBase.Motion.RAIN
	rain.ray_length = 120.0
	var decoy: FormBase = _form(&"decoy", 0.0, 4.0)
	decoy.motion = FormBase.Motion.DECOY
	var dash: FormBase = _form(&"dash", 100.0, 0.4)
	dash.motion = FormBase.Motion.DASH
	dash.ray_length = 40.0
	var arc := ModifierBase.new()
	arc.behaviour = ModifierBase.Behaviour.ARC
	arc.behaviour_strength = 2.0
	arc.behaviour_reach = 60.0
	_put(arc, &"arc")
	var timer := TriggerBase.new()
	timer.event = TriggerBase.Event.TIMER
	timer.interval = 0.5
	_put(timer, &"on_timer")
	var hurt := TriggerBase.new()
	hurt.event = TriggerBase.Event.HURT
	_put(hurt, &"on_hurt")


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
	form.mana_cost = 2.0
	_put(form, id)
	return form


## Builds `cards` as wizard 0's staff 0 and checks none is wasted.
func _build(cards: Array[StringName]) -> void:
	var built: CompiledStaff = StaffKit.compile(_spells, cards)
	check(built.wasted.is_empty(), "%s wastes nothing: %s" % [cards, built.wasted])
	StaffKit.build(_spells, 0, 0, cards)


func _tick(steps: int) -> void:
	for i in steps:
		_mgr.step(DT)
		_spells.step(DT)


func _cast() -> void:
	_spells.cast_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, 10.0)


## Where the live runes (the payloads here) are.
func _runes() -> Array[Vector2]:
	var found: Array[Vector2] = []
	for slot in _mgr.get_cap():
		if not _mgr.is_alive(slot):
			continue
		var spell: CompiledSpell = _spells.profile(_mgr.get_tag_of(slot))
		if spell != null and spell.form_id == &"rune":
			found.append(_mgr.get_position_of(slot))
	return found


func test_a_timer_on_a_short_shot_ticks_at_half_its_life() -> void:
	_build([&"on_timer", &"short", &"rune"])
	_cast()
	_tick(11)
	check_equal(_runes().size(), 0, "no tick before 0.2 s")
	_tick(2)
	var runes: Array[Vector2] = _runes()
	check_equal(runes.size(), 1, "a 0.4 s shot ticks once, at half its life (the interval is 0.5 s)")
	check(runes.size() == 1 and absf(runes[0].x - 60.0) < 8.0, "from where the shot is then (%s)" % [runes])
	_tick(30)
	check_equal(_runes().size(), 1, "and only once: it ends before the next")


func test_an_arc_on_a_short_shot_zaps_before_it_ends() -> void:
	var target := Node2D.new()
	root.add_child(target)
	own(target)
	target.global_position = Vector2(60, 30)
	_mgr.add_target(target, 8.0, ManagerScript.LAYER_ENEMY)
	# Arc 2: every 0.5 s, so the 0.4 s shot zaps first at 0.2 s.
	_build([&"arc", &"short"])
	_cast()
	_tick(30)
	check_equal(_hits.size(), 1, "the shot zapped the body off its line once")


func test_a_timer_on_a_beam_fires_from_its_tip() -> void:
	_build([&"on_timer", &"beam", &"rune"])
	_cast()
	_tick(13)
	var runes: Array[Vector2] = _runes()
	check_equal(runes.size(), 1, "a 0.4 s beam ticks at 0.2 s")
	check(runes.size() == 1 and runes[0].distance_to(Vector2(200, 0)) < 2.0, "at its tip (%s)" % [runes])


func test_on_hurt_on_a_beam_fires_while_it_is_on() -> void:
	_build([&"on_hurt", &"beam", &"rune"])
	_cast()
	_tick(2)
	_bus.actor_hurt.emit(0, 3, Vector2(5, 5), 0, &"hit")
	var runes: Array[Vector2] = _runes()
	check_equal(runes.size(), 1, "the caster's pain fires the beam's payload")
	check(runes.size() == 1 and runes[0].is_equal_approx(Vector2(5, 5)), "from the hurt actor")
	_tick(30)
	_bus.actor_hurt.emit(0, 3, Vector2(5, 5), 0, &"hit")
	check_equal(_runes().size(), 1, "an ended beam hears nothing")


func test_a_timer_on_a_rain_fires_from_its_spot_while_it_falls() -> void:
	_build([&"on_timer", &"rain", &"rune", &"rune"])
	_cast()
	_tick(25)
	var runes: Array[Vector2] = _runes()
	check_equal(runes.size(), 1, "a 0.8 s rain ticks at 0.4 s, before it lands")
	check(runes.size() == 1 and runes[0].distance_to(Vector2(120, 0)) < 2.0, "at its spot (%s)" % [runes])


func test_a_timer_on_a_decoy_fires_from_it_until_it_ends() -> void:
	_build([&"on_timer", &"decoy", &"rune"])
	var tag: int = _spells.current_tag(0, 0, 0)
	_spells.cast_staff(0, 0, Vector2(30, 40), Vector2.RIGHT, 10.0)
	_tick(31)
	var runes: Array[Vector2] = _runes()
	check_equal(runes.size(), 1, "a decoy ticks every 0.5 s")
	# It stands a step ahead of where it was cast (rules R4 F3).
	var stands: Vector2 = Vector2(30.0 + (_fake.items[&"decoy"] as FormBase).radius * 2.0, 40.0)
	check(runes.size() == 1 and runes[0].is_equal_approx(stands), "where it stands (%s)" % [runes])
	_bus.entity_ended.emit(0, &"decoy", Vector2(30, 40), tag)
	_tick(60)
	check_equal(_runes().size(), 1, "an ended decoy ticks no more")


func test_a_timer_on_a_dash_fires_from_the_caster_as_it_moves() -> void:
	_mgr.set_anchor(0, Vector2.ZERO)
	_build([&"on_timer", &"dash", &"rune"])
	_cast()
	_tick(6)
	_mgr.set_anchor(0, Vector2(15, 0))
	_tick(7)
	var runes: Array[Vector2] = _runes()
	check_equal(runes.size(), 1, "a 0.4 s dash ticks at 0.2 s")
	check(runes.size() == 1 and runes[0].is_equal_approx(Vector2(15, 0)), "from where the caster is then (%s)" % [runes])


func test_on_hurt_on_a_dash_fires_only_while_it_moves() -> void:
	_mgr.set_anchor(0, Vector2.ZERO)
	_build([&"on_hurt", &"dash", &"rune"])
	_cast()
	_tick(2)
	_bus.actor_hurt.emit(0, 3, Vector2(5, 5), 0, &"hit")
	check_equal(_runes().size(), 1, "hurt during the dash fires")
	_tick(30)
	_bus.actor_hurt.emit(0, 3, Vector2(5, 5), 0, &"hit")
	check_equal(_runes().size(), 1, "after it, nothing")
