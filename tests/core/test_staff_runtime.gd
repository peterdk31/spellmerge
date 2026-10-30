extends "res://tests/support/suite.gd"
## Tests for the staff runtime in core/spells (staffs A5): a staff casts its cycle in order with
## its delays, mana and recharge; multicast groups; payload groups; fallbacks asking for an area
## hit; sustained (`hold`) carriers that reserve mana until switched off; and four players with
## four staffs each, rebuilt mid-flight. A real projectile manager and event bus, stepped by
## hand; cards built in code behind a stand-in registry.
##
## godot --headless --path . --script res://tests/core/test_staff_runtime.gd

const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const DT: float = 1.0 / 60.0
const AIM: Vector2 = Vector2.RIGHT


class FakeRegistry:
	extends Node
	var items: Dictionary = {}

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)


var _fake: FakeRegistry
var _spells: SpellsScript
var _mgr: ManagerScript
var _bus: EventsScript
var _staff: StaffBase
## Every area_hit_requested as [player, position, radius, tag].
var _areas: Array = []
## The last mana_reserved per player.
var _reserved: Dictionary = {}


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
	_areas.clear()
	_reserved.clear()
	_bus.area_hit_requested.connect(func(player: int, at: Vector2, radius: float, tag: int, _shot: int) -> void: _areas.append([player, at, radius, tag]))
	_bus.mana_reserved.connect(func(player: int, amount: float) -> void: _reserved[player] = amount)
	_staff = StaffBase.new()
	_staff.id = &"test"
	_staff.slots = 20
	_staff.cast_delay = 0.1
	_staff.recharge = 0.5
	var bolt: FormBase = _form(&"bolt", 300.0, 1.0)
	bolt.cooldown = 0.2
	var nova: FormBase = _form(&"nova", 300.0, 1.0)
	nova.shots = 8
	nova.spread = 360.0
	var orbit: FormBase = _form(&"orbit", 0.0, 2.0)
	orbit.carrier = &"orbit"
	orbit.orbit_radius = 40.0
	orbit.pierce = 16
	var fire := ElementBase.new()
	fire.status_id = &"burn"
	fire.status_duration = 2.0
	_put(fire, &"fire")
	var blast := ModifierBase.new()
	blast.behaviour = ModifierBase.Behaviour.BLAST
	blast.behaviour_strength = 24.0
	_put(blast, &"blast")
	var hold := ModifierBase.new()
	hold.behaviour = ModifierBase.Behaviour.HOLD
	hold.behaviour_strength = 1.0
	_put(hold, &"hold")
	var on_hit := TriggerBase.new()
	on_hit.event = TriggerBase.Event.HIT
	_put(on_hit, &"on_hit")
	var double := MulticastBase.new()
	double.extra_draws = 1
	_put(double, &"double")


func _put(card: SpellComponent, id: StringName) -> void:
	card.id = id
	card.display_name = String(id).capitalize()
	_fake.items[id] = card


func _form(id: StringName, speed: float, lifetime: float) -> FormBase:
	var form := FormBase.new()
	form.base_damage = 5
	form.speed = speed
	form.lifetime = lifetime
	form.mana_cost = 2.0
	_put(form, id)
	return form


## Compiles and installs a staff for `player`'s `staff` from card ids written with spaces.
func _install(player: int, staff: int, cards: String) -> int:
	var ids: Array[StringName] = []
	for word in cards.split(" ", false):
		ids.append(StringName(word))
	return _spells.install_staff(player, staff, _spells.compile_staff(ids, _staff))


func _target(position: Vector2) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = position
	own(node)
	_mgr.add_target(node, 10.0, ManagerScript.LAYER_ENEMY)
	return node


func _tick(steps: int) -> void:
	for i in steps:
		_mgr.step(DT)
		_spells.step(DT)


func _wait_ready(player: int, staff: int) -> void:
	var guard: int = 0
	while _spells.cooldown_left(player, staff) > 0.0 and guard < 600:
		_tick(1)
		guard += 1


func test_a_staff_casts_its_cycle_in_order_then_recharges() -> void:
	_install(0, 1, "fire bolt nova")
	check_equal(_spells.cast_staff(0, 1, Vector2.ZERO, AIM, 100.0), 2.0, "cast 1 spends the bolt's mana")
	check_equal(_mgr.get_count(), 1, "one bolt")
	check(is_equal_approx(_spells.cooldown_left(0, 1), 0.1 + 0.2), "the staff's delay plus the bolt's cooldown, got %s" % _spells.cooldown_left(0, 1))
	check_equal(_spells.cast_staff(0, 1, Vector2.ZERO, AIM, 100.0), SpellsScript.REFUSED, "refused while in its delay")
	check_equal(_spells.cast_index(0, 1), 1, "the nova is next")
	_wait_ready(0, 1)
	_spells.cast_staff(0, 1, Vector2.ZERO, AIM, 100.0)
	check_equal(_mgr.get_count(), 9, "eight nova shots joined the bolt")
	check_equal(_spells.cast_index(0, 1), 0, "after the last card the staff starts over")
	check(_spells.cooldown_left(0, 1) >= 0.5, "and recharges")


func test_a_cast_needs_its_mana() -> void:
	_install(2, 3, "bolt")
	check_equal(_spells.cast_staff(2, 3, Vector2.ZERO, AIM, 1.0), SpellsScript.REFUSED, "1 mana is not enough for 2")
	check_equal(_mgr.get_count(), 0, "nothing flew")
	check_equal(_spells.cast_index(2, 3), 0, "a refused cast changes nothing")


func test_multicast_fires_two_carriers_along_the_aim() -> void:
	# The staff has no spread, so nothing sets them apart (tests/core/test_staff_spread.gd).
	_install(0, 0, "double bolt bolt")
	_spells.cast_staff(0, 0, Vector2.ZERO, AIM, 100.0)
	check_equal(_mgr.get_count(), 2, "two bolts in one cast")
	for slot in 2:
		check(_mgr.get_velocity_of(slot).normalized().is_equal_approx(AIM.normalized()), "bolt %d flies along the aim" % slot)


func test_a_payload_fires_on_hit_under_its_own_node() -> void:
	_target(Vector2(60, 0))
	_install(1, 2, "on_hit bolt nova")
	_spells.cast_staff(1, 2, Vector2.ZERO, AIM, 100.0)
	_tick(20)
	var nova_tag: int = _spells.current_tag(1, 2, 1)
	check(_spells.live_shots(nova_tag) > 0, "the nova flies under node 1's tag")
	check(_spells.profile(nova_tag) != null and _spells.profile(nova_tag).form_id == &"nova", "that tag is the nova's")


func test_a_lone_blast_asks_for_an_area_hit_on_the_caster() -> void:
	_install(3, 0, "blast")
	var origin := Vector2(20, 30)
	check(_spells.cast_staff(3, 0, origin, AIM, 100.0) >= 0.0, "it casts")
	check_equal(_areas.size(), 1, "one area hit")
	if _areas.size() == 1:
		check_equal(_areas[0][0], 3, "for player 4")
		check_equal(_areas[0][1], origin, "on the caster")
		check(float(_areas[0][2]) >= 24.0, "as wide as the blast")
		check(_spells.hit_profile(int(_areas[0][3])) != null, "with a profile combat can read")


func test_a_blast_in_a_payload_lands_where_the_bolt_hits() -> void:
	_target(Vector2(60, 0))
	_install(0, 0, "on_hit bolt blast")
	_spells.cast_staff(0, 0, Vector2.ZERO, AIM, 100.0)
	_tick(20)
	check_equal(_areas.size(), 1, "one area hit")
	if _areas.size() == 1:
		check((_areas[0][1] as Vector2).distance_to(Vector2(60, 0)) < 16.0, "at the hit, got %s" % _areas[0][1])


func test_hold_keeps_its_shots_and_reserves_mana_until_switched_off() -> void:
	_mgr.set_anchor(0, Vector2.ZERO)
	_install(0, 0, "hold orbit")
	check_equal(_spells.cast_staff(0, 0, Vector2.ZERO, AIM, 100.0), 2.0, "the first press casts")
	check(_spells.is_holding(0, 0), "it is on")
	check_equal(_reserved.get(0, 0.0), 2.0, "its mana is reserved")
	_tick(300)
	check_equal(_mgr.get_count(), 1, "the orbit outlives its own two seconds")
	_wait_ready(0, 0)
	check_equal(_spells.cast_staff(0, 0, Vector2.ZERO, AIM, 100.0), 0.0, "the next press switches it off and spends nothing")
	check(not _spells.is_holding(0, 0), "it is off")
	check_equal(_mgr.get_count(), 0, "its shot is gone")
	check_equal(_reserved.get(0, -1.0), 0.0, "and the mana is free")


func test_editing_a_staff_switches_its_hold_off() -> void:
	_mgr.set_anchor(1, Vector2.ZERO)
	_install(1, 3, "hold orbit")
	_spells.cast_staff(1, 3, Vector2.ZERO, AIM, 100.0)
	_install(1, 3, "bolt")
	check(not _spells.is_holding(1, 3), "the edit switched it off")
	check_equal(_mgr.get_count(), 0, "its shot is gone")
	check_equal(_reserved.get(1, -1.0), 0.0, "and its mana is free")


func test_an_empty_staff_has_no_build() -> void:
	_install(0, 2, "bolt")
	check_equal(_install(0, 2, ""), 0, "an empty staff installs nothing")
	check_equal(_spells.cast_staff(0, 2, Vector2.ZERO, AIM, 100.0), SpellsScript.REFUSED, "and casts nothing")


func test_four_players_with_four_staffs_rebuild_mid_flight_without_mixing() -> void:
	var tags: Array[int] = []
	for player in 4:
		for staff in SpellLimits.STAFFS:
			tags.append(_install(player, staff, "fire bolt" if (player + staff) % 2 == 0 else "bolt"))
			_spells.cast_staff(player, staff, Vector2(0, 40 * player), AIM, 100.0)
	var seen: Dictionary = {}
	for tag in tags:
		seen[tag] = true
	check_equal(seen.size(), 16, "sixteen staffs, sixteen tags")
	check_equal(_mgr.get_count(), 16, "sixteen bolts in the air")
	var old_tag: int = tags[5]
	var old_element: StringName = _spells.profile(old_tag).element_id
	_install(1, 1, "nova")
	check(_spells.profile(old_tag) != null, "the old build stays while its bolt flies")
	check_equal(_spells.profile(old_tag).element_id, old_element, "with its old numbers")
	_tick(120)
	check(_spells.profile(old_tag) == null, "and is freed when its bolt is gone")
	for i in tags.size():
		if i != 5:
			check(_spells.current_tag(floori(float(i) / SpellLimits.STAFFS), i % SpellLimits.STAFFS) == tags[i], "staff %d is untouched" % i)
