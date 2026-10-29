extends "res://tests/support/suite.gd"
## Tests for the multicast spread of the staffs (B2b): scatter sends each carrier its own way
## (the same way for the same cast), burst fires a group again and again, echo fires a carrier
## once more at half damage, and mirror also fires it backwards. It runs a real projectile
## manager and event bus, stepped by hand, with cards built in code.
##
## godot --headless --path . --script res://tests/core/test_spells_multicast.gd

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
## Every projectile_hit as [player, target, position, tag, damage of the hit profile].
var _hits: Array = []


func before_each() -> void:
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_mgr.set_cap(512)
	# Four wizards seated 0-3 at actor ids 0-3, as the tests name their casters.
	_mgr.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _fake
	_spells.bind(_mgr, _bus)
	_hits.clear()
	_bus.projectile_hit.connect(func(player: int, target: Node, at: Vector2, tag: int) -> void:
		var profile: HitProfile = _spells.hit_profile(tag)
		_hits.append([player, target, at, tag, profile.damage if profile != null else -1]))
	var bolt: FormBase = _form(&"bolt", 300.0, 1.0)
	bolt.base_damage = 10
	var beam: FormBase = _form(&"beam", 0.0, 0.1)
	beam.motion = FormBase.Motion.RAY
	beam.ray_length = 300.0
	beam.base_damage = 10
	_multicast(&"double", MulticastBase.Mode.TOGETHER, 1)
	_multicast(&"scatter", MulticastBase.Mode.SCATTER, 2)
	var burst: MulticastBase = _multicast(&"burst", MulticastBase.Mode.BURST, 0)
	burst.repeats = 3
	burst.repeat_interval = 0.1
	var instant: MulticastBase = _multicast(&"instant_burst", MulticastBase.Mode.BURST, 0)
	instant.repeats = 3
	_modifier(&"echo", ModifierBase.Behaviour.ECHO, 0.3)
	_modifier(&"mirror", ModifierBase.Behaviour.MIRROR, 1.0)
	_modifier(&"hold", ModifierBase.Behaviour.HOLD, 1.0)


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


func _modifier(id: StringName, behaviour: ModifierBase.Behaviour, strength: float) -> void:
	var modifier := ModifierBase.new()
	modifier.behaviour = behaviour
	modifier.behaviour_strength = strength
	_put(modifier, id)


func _multicast(id: StringName, mode: MulticastBase.Mode, extra: int) -> MulticastBase:
	var card := MulticastBase.new()
	card.mode = mode
	card.extra_draws = extra
	_put(card, id)
	return card


func _build(player: int, cards: Array[StringName]) -> int:
	StaffKit.build(_spells, player, 0, cards)
	return _spells.current_tag(player, 0, 0)


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


func _cast(player: int = 0, direction: Vector2 = Vector2.RIGHT) -> float:
	return _spells.cast_staff(player, 0, Vector2.ZERO, direction, 100.0)


## Headings (unit vectors) of the live shots, in slot order.
func _headings() -> Array[Vector2]:
	var found: Array[Vector2] = []
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot):
			found.append(_mgr.get_velocity_of(slot).normalized())
	return found


func test_scatter_sends_each_carrier_its_own_way() -> void:
	_build(0, [&"scatter", &"bolt", &"bolt", &"bolt"])
	_cast()
	var headings: Array[Vector2] = _headings()
	check_equal(headings.size(), 3, "scatter makes three carriers")
	var fan_like: bool = true
	for i in headings.size():
		for j in range(i + 1, headings.size()):
			if headings[i].angle_to(headings[j]) > 0.5:
				fan_like = false
	check(not fan_like, "they do not leave as a narrow fan: %s" % [headings])


func test_scatter_is_the_same_for_the_same_cast() -> void:
	_build(0, [&"scatter", &"bolt", &"bolt", &"bolt"])
	_cast()
	var first: Array[Vector2] = _headings()
	_mgr.clear()
	_spells.clear()
	_build(0, [&"scatter", &"bolt", &"bolt", &"bolt"])
	_cast()
	var second: Array[Vector2] = _headings()
	check_equal(first.size(), 3, "three carriers")
	var same: bool = first.size() == second.size()
	for i in mini(first.size(), second.size()):
		same = same and first[i].is_equal_approx(second[i])
	check(same, "a replay of the cast scatters the same way")


func test_scatter_changes_from_cast_to_cast() -> void:
	_build(0, [&"scatter", &"bolt", &"bolt", &"bolt"])
	_cast()
	var first: Array[Vector2] = _headings()
	_mgr.clear()
	_tick(240)
	_cast()
	var second: Array[Vector2] = _headings()
	check(first.size() == 3 and second.size() == 3 and not first[0].is_equal_approx(second[0]), "the next cast scatters differently")


func test_burst_fires_the_group_again_after_its_interval() -> void:
	_build(0, [&"burst", &"bolt"])
	_cast()
	check_equal(_mgr.get_count(), 1, "one bolt at the cast")
	_tick(3)
	check_equal(_mgr.get_count(), 1, "still one before the interval")
	_tick(5)
	check_equal(_mgr.get_count(), 2, "the second firing at 0.1 s")
	_tick(6)
	check_equal(_mgr.get_count(), 3, "the third at 0.2 s")
	_tick(30)
	check_equal(_mgr.get_count(), 3, "and no more")


func test_a_burst_with_no_interval_fires_at_once() -> void:
	_build(0, [&"instant_burst", &"bolt"])
	_cast()
	check_equal(_mgr.get_count(), 3, "three firings in the cast")


func test_a_burst_costs_the_mana_of_one_cast() -> void:
	_build(0, [&"burst", &"bolt"])
	check_equal(_cast(), 2.0, "the later firings are free")


func test_a_burst_stops_when_the_staff_is_rebuilt() -> void:
	_build(0, [&"burst", &"bolt"])
	_cast()
	_build(0, [&"bolt"])
	_tick(30)
	check_equal(_mgr.get_count(), 1, "the old build's later firings never came")


func test_a_burst_follows_the_caster() -> void:
	_mgr.set_anchor(0, Vector2.ZERO)
	_build(0, [&"burst", &"bolt"])
	_cast()
	_mgr.set_anchor(0, Vector2(0, 50))
	_tick(7)
	var late: int = -1
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot):
			late = slot
	check(late >= 0 and _mgr.get_position_of(late).y > 40.0, "the later firing leaves from where the caster stands")


func test_burst_fires_a_scatter_group_in_new_directions() -> void:
	_build(0, [&"burst", &"scatter", &"bolt", &"bolt", &"bolt"])
	_cast()
	var first: Array[Vector2] = _headings()
	_tick(7)
	check_equal(_mgr.get_count(), 6, "two firings of three")
	check(first.size() == 3, "three at first")


func test_the_waiting_launches_are_never_dropped_for_room() -> void:
	_build(0, [&"burst", &"bolt"])
	for i in SpellLimits.PENDING_START + 10:
		_spells._delay(1.0, null, null, 0, 0, 0, Vector2.ZERO, Vector2.RIGHT, null, false)
	check_equal(_spells._pending.size(), SpellLimits.PENDING_START + 10, "all of them wait: the queue grows")


func test_echo_fires_the_carrier_again_at_half_damage() -> void:
	_target(Vector2(60, 0))
	_build(0, [&"echo", &"bolt"])
	_cast()
	_tick(12)
	check_equal(_hits.size(), 1, "the bolt hit")
	check_equal(_hits[0][4], 10, "at full damage")
	check_equal(_mgr.get_count(), 0, "nothing left in the air")
	_tick(20)
	check_equal(_hits.size(), 2, "the echo hit")
	check_equal(_hits[1][4], 5, "at half damage")
	_tick(60)
	check_equal(_hits.size(), 2, "an echo does not echo")


func test_echo_waits_its_strength_in_seconds() -> void:
	_build(0, [&"echo", &"bolt"])
	_cast()
	_mgr.clear()
	_tick(17)
	check_equal(_mgr.get_count(), 0, "not yet at 0.28 s")
	_tick(3)
	check_equal(_mgr.get_count(), 1, "there at 0.3 s")


func test_a_beams_echo_hits_at_half_damage() -> void:
	_target(Vector2(100, 0))
	_build(0, [&"echo", &"beam"])
	_cast()
	check_equal(_hits.size(), 1, "the beam hit at once")
	check_equal(_hits[0][4], 10, "at full damage")
	_tick(20)
	check_equal(_hits.size(), 2, "and again")
	check_equal(_hits[1][4], 5, "at half")
	_hits.clear()
	_tick(60)
	_cast()
	check_equal(_hits[0][4] if not _hits.is_empty() else -1, 10, "the next cast is at full damage again")


func test_an_echo_is_dropped_when_the_staff_is_rebuilt() -> void:
	_build(0, [&"echo", &"bolt"])
	_cast()
	_mgr.clear()
	_build(0, [&"bolt"])
	_tick(30)
	check_equal(_mgr.get_count(), 0, "the old build's echo never came")


func test_a_held_carrier_does_not_echo() -> void:
	_build(0, [&"echo", &"hold", &"bolt"])
	_cast()
	_tick(30)
	check_equal(_mgr.get_count(), 1, "one held shot")


func test_mirror_also_fires_backwards() -> void:
	_build(0, [&"mirror", &"bolt"])
	check_equal(_cast(), 2.0, "the mana is one bolt's")
	var headings: Array[Vector2] = _headings()
	check_equal(headings.size(), 2, "two bolts")
	check(headings.size() == 2 and headings[0].is_equal_approx(-headings[1]), "opposite ways")


func test_mirror_only_mirrors_the_carrier_it_is_on() -> void:
	_build(0, [&"mirror", &"double", &"bolt", &"bolt"])
	_cast()
	check_equal(_mgr.get_count(), 3, "two bolts, and a back shot for the first only")


func test_a_mirrored_orbit_starts_on_the_other_side() -> void:
	# Rules R4g: mirror is one rule, the carrier fired again with its aim reversed.
	var orbit: FormBase = _form(&"orbit", 0.0, 2.0)
	orbit.motion = FormBase.Motion.ORBIT
	orbit.orbit_radius = 40.0
	_mgr.set_anchor(0, Vector2.ZERO)
	_build(0, [&"mirror", &"orbit"])
	_cast()
	var found: Array[Vector2] = []
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot):
			found.append(_mgr.get_position_of(slot))
	check_equal(found.size(), 2, "two orbit shots")
	check(found.size() == 2 and found[0].is_equal_approx(-found[1]) and found[0].x > 30.0, "on opposite sides of the circle, the first along the aim: %s" % [found])


func test_a_mirrored_hook_flies_both_ways() -> void:
	var hook: FormBase = _form(&"hook", 300.0, 0.5)
	hook.motion = FormBase.Motion.HOOK
	_build(0, [&"mirror", &"hook"])
	_cast()
	var headings: Array[Vector2] = _headings()
	check_equal(headings.size(), 2, "two hooks")
	check(headings.size() == 2 and headings[0].is_equal_approx(-headings[1]), "opposite ways")


func test_echo_and_mirror_together_fire_four_shots() -> void:
	_build(0, [&"echo", &"mirror", &"bolt"])
	_cast()
	_tick(20)
	check_equal(_mgr.get_count(), 4, "two and their echoes")


func _chain_setup() -> void:
	_modifier(&"chain", ModifierBase.Behaviour.CHAIN, 1.0)


func test_an_echoed_chain_keeps_half_damage_on_its_jump() -> void:
	_chain_setup()
	_target(Vector2(60, 0))
	_target(Vector2(110, 0))
	_build(0, [&"echo", &"chain", &"bolt"])
	_cast()
	_tick(120)
	var damage: Array = []
	for hit in _hits:
		damage.append(hit[4])
	check_equal(damage, [10, 10, 5, 5], "the cast hits twice at full damage, its echo twice at half")


func test_a_mirrored_beam_hits_both_ways() -> void:
	_target(Vector2(100, 0))
	_target(Vector2(-100, 0))
	_build(0, [&"mirror", &"beam"])
	_cast()
	check_equal(_hits.size(), 2, "one beam each way")


func test_a_mirrored_returning_shot_goes_both_ways() -> void:
	_modifier(&"return", ModifierBase.Behaviour.RETURN, 1.0)
	_build(0, [&"mirror", &"return", &"bolt"])
	_cast()
	var headings: Array[Vector2] = _headings()
	check_equal(headings.size(), 2, "two returning shots")
	check(headings.size() == 2 and headings[0].is_equal_approx(-headings[1]), "opposite ways")


func test_releasing_a_hold_drops_the_waiting_firings() -> void:
	_build(0, [&"burst", &"bolt"])
	_cast()
	_spells._release_hold(0)
	_tick(30)
	check_equal(_mgr.get_count(), 1, "the later firings never came")


func _trigger_card(id: StringName, event: TriggerBase.Event) -> void:
	var trigger := TriggerBase.new()
	trigger.event = event
	_put(trigger, id)


func test_an_echoed_carrier_fires_its_on_cast_payload_again() -> void:
	_trigger_card(&"on_cast", TriggerBase.Event.CAST)
	_build(0, [&"echo", &"on_cast", &"bolt", &"bolt"])
	_cast()
	check_equal(_mgr.get_count(), 2, "the carrier and its payload at the cast")
	_tick(20)
	check_equal(_mgr.get_count(), 4, "and both again in the echo")


func test_waiting_launches_stay_with_their_own_player() -> void:
	StaffKit.build(_spells, 0, 0, [&"burst", &"bolt"])
	StaffKit.build(_spells, 1, 0, [&"burst", &"bolt"])
	_spells.cast_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, 100.0)
	_spells.cast_staff(1, 0, Vector2.ZERO, Vector2.LEFT, 100.0)
	StaffKit.build(_spells, 1, 0, [&"bolt"])
	_mgr.clear()
	_tick(30)
	check_equal(_mgr.get_count(), 2, "player 0's two later firings came, player 1's did not")


func test_scatter_works_for_a_later_player() -> void:
	StaffKit.build(_spells, 2, 0, [&"scatter", &"bolt", &"bolt", &"bolt"])
	_spells.cast_staff(2, 0, Vector2.ZERO, Vector2.RIGHT, 100.0)
	check_equal(_mgr.get_count(), 3, "three carriers for player 2")


func test_a_later_firing_scatters_the_same_whatever_else_was_cast() -> void:
	_build(0, [&"burst", &"scatter", &"bolt", &"bolt", &"bolt"])
	_cast()
	_tick(7)
	var alone: Array[Vector2] = _headings().slice(3)
	_mgr.clear()
	_spells.clear()
	_build(0, [&"burst", &"scatter", &"bolt", &"bolt", &"bolt"])
	_cast()
	StaffKit.build(_spells, 1, 0, [&"scatter", &"bolt", &"bolt", &"bolt"])
	_spells.cast_staff(1, 0, Vector2.ZERO, Vector2.RIGHT, 100.0)
	_tick(7)
	var busy: Array[Vector2] = _headings().slice(6)
	var same: bool = alone.size() == 3 and busy.size() == 3
	for i in mini(alone.size(), busy.size()):
		same = same and alone[i].is_equal_approx(busy[i])
	check(same, "the burst's second firing points the same way: %s vs %s" % [alone, busy])
