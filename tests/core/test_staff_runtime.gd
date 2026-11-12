extends "res://tests/support/suite.gd"
## Tests for the staff runtime in core/spells (staffs A5): a staff casts its cycle in order with
## its delays, mana and recharge; multicast groups; payload groups; Pulses asking for an area hit;
## sustained (`hold`) carriers that reserve mana until switched off; and four players with four
## staffs each, rebuilt mid-flight. A real projectile manager and event bus, stepped by
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
## Every blast (its `cue_shown`) as [player, position, radius].
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
	_bus.cue_shown.connect(func(player: int, _cue: StringName, at: Vector2, _direction: Vector2, radius: float, _tint: Color, _look: int) -> void: _areas.append([player, at, radius]))
	_bus.mana_reserved.connect(func(player: int, _at: int, amount: float) -> void: _reserved[player] = amount)
	_staff = StaffBase.new()
	_staff.id = &"test"
	_staff.slots = 20
	_staff.cooldown = 0.5
	var bolt: CarrierCard = _carrier_card(&"bolt", 300.0, 1.0)
	var pulse: CarrierCard = _carrier_card(&"pulse", 0.0, 0.5)
	pulse.carrier = Carriers.PULSE
	pulse.radius = 24.0
	bolt.wind_down = 0.2
	var halo: CarrierCard = _carrier_card(&"halo", 300.0, 1.0)
	halo.shots = 8
	halo.spread = 360.0
	var rune: CarrierCard = _carrier_card(&"rune", 0.0, 2.0)
	rune.carrier = &"rune"
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


func _carrier_card(id: StringName, speed: float, lifetime: float) -> CarrierCard:
	var carrier_card := CarrierCard.new()
	carrier_card.base_damage = 5
	carrier_card.speed = speed
	carrier_card.lifetime = lifetime
	carrier_card.mana_cost = 2.0
	_put(carrier_card, id)
	return carrier_card


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


func test_a_staff_casts_its_cycle_in_order_then_cools_down() -> void:
	_install(0, 1, "fire bolt halo")
	check_equal(_spells.cast_staff(0, 1, Vector2.ZERO, AIM, 100.0), 2.0, "cast 1 spends the bolt's mana")
	check_equal(_mgr.get_count(), 1, "one bolt")
	check(is_equal_approx(_spells.cooldown_left(0, 1), 0.2), "the bolt's wind-down, got %s" % _spells.cooldown_left(0, 1))
	check_equal(_spells.cast_staff(0, 1, Vector2.ZERO, AIM, 100.0), SpellsScript.REFUSED, "refused while it winds down")
	check_equal(_spells.cast_index(0, 1), 1, "the halo is next")
	_wait_ready(0, 1)
	_spells.cast_staff(0, 1, Vector2.ZERO, AIM, 100.0)
	check_equal(_mgr.get_count(), 9, "eight halo shots joined the bolt")
	check_equal(_spells.cast_index(0, 1), 0, "after the last card the staff starts over")
	check(_spells.cooldown_left(0, 1) >= 0.5, "after its wind-down and the staff's cooldown")


func test_a_cast_needs_its_mana() -> void:
	_install(2, 3, "bolt")
	check_equal(_spells.cast_staff(2, 3, Vector2.ZERO, AIM, 1.0), SpellsScript.REFUSED, "1 mana is not enough for 2")
	check_equal(_mgr.get_count(), 0, "nothing flew")
	check_equal(_spells.cast_index(2, 3), 0, "the cycle ended where it was: it starts over (docs/milestones/cast-timing.md, T3)")


func test_multicast_fires_two_carriers_along_the_aim() -> void:
	# The staff has no spread, so nothing sets them apart (tests/core/test_staff_spread.gd).
	_install(0, 0, "double bolt bolt")
	_spells.cast_staff(0, 0, Vector2.ZERO, AIM, 100.0)
	check_equal(_mgr.get_count(), 2, "two bolts in one cast")
	for slot in 2:
		check(_mgr.get_velocity_of(slot).normalized().is_equal_approx(AIM.normalized()), "bolt %d flies along the aim" % slot)


func test_a_payload_fires_on_hit_under_its_own_node() -> void:
	_target(Vector2(60, 0))
	_install(1, 2, "on_hit bolt halo")
	_spells.cast_staff(1, 2, Vector2.ZERO, AIM, 100.0)
	_tick(20)
	var nova_tag: int = _spells.current_tag(1, 2, 1)
	check(_spells.live_shots(nova_tag) > 0, "the halo flies under node 1's tag")
	check(_spells.profile(nova_tag) != null and _spells.profile(nova_tag).carrier_card_id == &"halo", "that tag is the halo's")


func test_a_blast_pulse_asks_for_an_area_hit_on_the_caster() -> void:
	_install(3, 0, "blast pulse")
	var origin := Vector2(20, 30)
	check(_spells.cast_staff(3, 0, origin, AIM, 100.0) >= 0.0, "it casts")
	check_equal(_areas.size(), 1, "one area hit")
	if _areas.size() == 1:
		check_equal(_areas[0][0], 3, "for player 4")
		check_equal(_areas[0][1], origin, "on the caster")
		check(float(_areas[0][2]) >= 24.0, "as wide as the blast")


func test_a_blast_in_a_payload_lands_where_the_bolt_hits() -> void:
	_target(Vector2(60, 0))
	_install(0, 0, "on_hit bolt blast pulse")
	_spells.cast_staff(0, 0, Vector2.ZERO, AIM, 100.0)
	_tick(20)
	check_equal(_areas.size(), 1, "one area hit")
	if _areas.size() == 1:
		check((_areas[0][1] as Vector2).distance_to(Vector2(60, 0)) < 16.0, "at the hit, got %s" % _areas[0][1])


func test_hold_keeps_its_shots_and_reserves_mana_until_switched_off() -> void:
	_install(0, 0, "hold rune")
	check_equal(_spells.cast_staff(0, 0, Vector2.ZERO, AIM, 100.0), 2.0, "the first press casts")
	check(_spells.is_holding(0, 0), "it is on")
	check_equal(_reserved.get(0, 0.0), 2.0, "its mana is reserved")
	_tick(300)
	check_equal(_mgr.get_count(), 1, "the rune outlives its own two seconds")
	_wait_ready(0, 0)
	check_equal(_spells.cast_staff(0, 0, Vector2.ZERO, AIM, 100.0), 0.0, "the next press switches it off and spends nothing")
	check(not _spells.is_holding(0, 0), "it is off")
	check_equal(_mgr.get_count(), 0, "its shot is gone")
	check_equal(_reserved.get(0, -1.0), 0.0, "and the mana is free")
	check_equal(_spells.cooldown_left(0, 0), 0.0, "and the switch-off press leaves the staff free at once")
	check_equal(_spells.cast_staff(0, 0, Vector2.ZERO, AIM, 100.0), 2.0, "so the next press casts again straight away")


func test_editing_a_staff_switches_its_hold_off() -> void:
	_install(1, 3, "hold rune")
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
	_install(1, 1, "halo")
	check(_spells.profile(old_tag) != null, "the old build stays while its bolt flies")
	check_equal(_spells.profile(old_tag).element_id, old_element, "with its old numbers")
	_tick(120)
	check(_spells.profile(old_tag) == null, "and is freed when its bolt is gone")
	for i in tags.size():
		if i != 5:
			check(_spells.current_tag(floori(float(i) / SpellLimits.STAFFS), i % SpellLimits.STAFFS) == tags[i], "staff %d is untouched" % i)


# --- Wind-up (docs/milestones/cast-timing.md, part T2) -----------------------------------------

## A bolt that winds up `seconds` (its carrier card's `wind_up`), installed as `player`'s staff 0.
func _wound_bolt(player: int, seconds: float) -> void:
	var slow: CarrierCard = _carrier_card(&"slow_bolt", 300.0, 1.0)
	slow.wind_up = seconds
	slow.wind_down = 0.1
	_install(player, 0, "slow_bolt")


func test_a_cast_that_winds_up_leaves_when_its_wind_up_is_over() -> void:
	_wound_bolt(0, 0.1)
	var spent: Array = []
	_bus.mana_spend_requested.connect(func(caster: int, staff: int, amount: float) -> void: spent.append([caster, staff, amount]))
	check_equal(_spells.cast_staff(0, 0, Vector2.ZERO, AIM, 100.0), 0.0, "the press is taken and pays nothing yet")
	check(_spells.is_winding(0, 0), "it winds up")
	check_equal(_mgr.get_count(), 0, "nothing has left")
	check(is_equal_approx(_spells.cooldown_left(0, 0), 0.1), "the staff is busy for the wind-up")
	check_equal(_spells.cast_staff(0, 0, Vector2.ZERO, AIM, 100.0), SpellsScript.REFUSED, "a press while it winds up is refused")
	_tick(3)
	check_equal(_mgr.get_count(), 0, "still winding after 0.05 s")
	_tick(4)
	check_equal(_mgr.get_count(), 1, "the bolt left once the wind-up was over")
	check(not _spells.is_winding(0, 0), "and it winds up no more")
	check_equal(spent, [[0, 0, 2.0]], "its mana is asked for as it leaves")
	check(_spells.cooldown_left(0, 0) > 0.5, "then its wind-down and the staff's cooldown, got %s" % _spells.cooldown_left(0, 0))
	check_equal(_spells.cast_index(0, 0), 0, "a one-cast cycle starts over as it leaves")


func test_a_winding_cast_leaves_along_the_aim_it_has_then() -> void:
	_wound_bolt(1, 0.1)
	_spells.set_aim(1, Vector2.ZERO, Vector2.RIGHT)
	_spells.cast_staff(1, 0, Vector2.ZERO, Vector2.RIGHT, 100.0)
	_spells.set_aim(1, Vector2(5.0, 0.0), Vector2.DOWN)
	_tick(7)
	check_equal(_mgr.get_count(), 1, "it left")
	var velocity: Vector2 = Vector2.ZERO
	for slot in 512:
		if _mgr.is_alive(slot):
			velocity = _mgr.get_velocity_of(slot)
	check(velocity.normalized().dot(Vector2.DOWN) > 0.99, "along the aim at the release, not at the press: %s" % velocity)


func test_being_downed_or_a_rebuild_cancels_a_wind_up_for_free() -> void:
	var spent: Array = []
	_bus.mana_spend_requested.connect(func(caster: int, staff: int, amount: float) -> void: spent.append(amount))
	_wound_bolt(2, 0.1)
	_spells.cast_staff(2, 0, Vector2.ZERO, AIM, 100.0)
	_spells.clear_aim(2)
	check(not _spells.is_winding(2, 0), "down: it winds up no more")
	check_equal(_spells.cooldown_left(2, 0), 0.0, "and the staff is free")
	_spells.set_aim(2, Vector2.ZERO, AIM)
	_spells.cast_staff(2, 0, Vector2.ZERO, AIM, 100.0)
	_install(2, 0, "slow_bolt")
	check(not _spells.is_winding(2, 0), "a rebuild cancels it too")
	_tick(20)
	check_equal(_mgr.get_count(), 0, "nothing ever left")
	check(spent.is_empty(), "and nothing was paid")


func test_the_staff_s_wind_up_comes_before_every_cast() -> void:
	_staff.wind_up = 0.1
	_carrier_card(&"bolt", 300.0, 1.0).wind_down = 0.0
	_install(3, 0, "bolt bolt")
	_spells.cast_staff(3, 0, Vector2.ZERO, AIM, 100.0)
	check(_spells.is_winding(3, 0), "a plain bolt winds up on a staff that does (an enemy's telegraph)")
	_tick(7)
	check_equal(_mgr.get_count(), 1, "then leaves")
	_spells.cast_staff(3, 0, Vector2.ZERO, AIM, 100.0)
	check(_spells.is_winding(3, 0), "the next cast of the cycle winds up too")


func test_a_payload_winds_up_where_its_trigger_fired() -> void:
	_target(Vector2(30.0, 0.0))
	_carrier_card(&"bolt", 300.0, 1.0).wind_down = 0.1
	var halo: CarrierCard = _carrier_card(&"slow_halo", 0.0, 0.2)
	halo.carrier = &"atom"
	halo.shots = 8
	halo.spread = 360.0
	halo.speed = 200.0
	halo.wind_up = 0.2
	_install(0, 2, "on_hit bolt slow_halo")
	_spells.cast_staff(0, 2, Vector2.ZERO, AIM, 100.0)
	check(not _spells.is_winding(0, 2), "the cast itself winds up nothing: the halo is a payload's")
	var hit_at: int = -1
	for step in 30:
		_tick(1)
		if hit_at < 0 and _mgr.get_count() == 0:
			hit_at = step
		if _mgr.get_count() > 1:
			check(hit_at >= 0 and step - hit_at >= 10, "the halo left about 0.2 s after the hit (steps %d to %d)" % [hit_at, step])
			check_equal(_mgr.get_count(), 8, "all eight of its shots")
			return
	check(false, "the halo never left (hit at step %d)" % hit_at)


# --- Skipping (docs/milestones/cast-timing.md, part T3) ----------------------------------------

## A staff whose first cast is a dear halo (`dear`, 10 mana) and then two bolts (2 each).
func _dear_then_bolts(player: int) -> void:
	var dear: CarrierCard = _carrier_card(&"dear", 0.0, 0.3)
	dear.mana_cost = 10.0
	dear.wind_down = 0.0
	_carrier_card(&"bolt", 300.0, 1.0).wind_down = 0.0
	_install(player, 0, "dear bolt bolt")


func test_a_cast_the_mana_does_not_pay_is_skipped() -> void:
	_dear_then_bolts(0)
	check_equal(_spells.cast_staff(0, 0, Vector2.ZERO, AIM, 5.0), 2.0, "with 5 mana the press skips the dear cast and fires a bolt")
	check_equal(_spells.cast_index(0, 0), 2, "the cycle moved on past the bolt it fired")
	_tick(1)
	check_equal(_spells.cast_staff(0, 0, Vector2.ZERO, AIM, 100.0), 2.0, "the last bolt; skipping is no rebuild")
	_tick(40)
	check_equal(_spells.cast_staff(0, 0, Vector2.ZERO, AIM, 100.0), 10.0, "the next cycle starts with the dear cast again, now it is paid")


func test_with_no_cast_left_to_pay_the_cycle_ends_and_nothing_leaves() -> void:
	var fizzled: Array = []
	_bus.cast_fizzled.connect(func(caster: int, staff: int) -> void: fizzled.append([caster, staff]))
	_dear_then_bolts(1)
	_spells.cast_staff(1, 0, Vector2.ZERO, AIM, 100.0)
	_tick(1)
	check_equal(_spells.cast_index(1, 0), 1, "the dear cast left; a bolt is next")
	check_equal(_spells.cast_staff(1, 0, Vector2.ZERO, AIM, 1.0), SpellsScript.REFUSED, "1 mana pays no cast left in the cycle")
	check_equal(fizzled, [[1, 0]], "it fizzled")
	check_equal(_spells.cast_index(1, 0), 0, "the cycle ended")
	check(is_equal_approx(_spells.cooldown_left(1, 0), 0.5), "and the staff's cooldown runs, got %s" % _spells.cooldown_left(1, 0))
	check_equal(_mgr.get_count(), 1, "nothing left but the dear cast's shot")


func test_the_ai_reads_the_cast_a_press_would_fire() -> void:
	_dear_then_bolts(2)
	check(_spells.cast_ready(2, 0, 0.0, 5.0), "5 mana is ready: it pays a bolt")
	check_equal(_spells.next_cast_mana(2, 0, 5.0), 2.0, "and the cast it would fire is a bolt's")
	check_equal(_spells.next_cast_mana(2, 0), 10.0, "with no mana given, the cast at the cursor")
	check(not _spells.cast_ready(2, 0, 0.0, 1.0), "1 mana pays none")
