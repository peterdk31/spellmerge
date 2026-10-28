extends "res://tests/support/suite.gd"
## Tests for the trigger events of the staffs (B2a): on block, on kill, on cast, on wall, on hurt
## and on reaction fire their payload from where the event happened, each shot only as often as
## its trigger allows, and a `relay` shot that hits an actor takes on that actor's last infusion
## (owner, 2026-10-28; `on ally` is gone). It runs a real projectile manager and event bus,
## stepped by hand, with cards built in code, and a table of four wizards at actor ids 0-3.
##
## godot --headless --path . --script res://tests/core/test_spells_triggers.gd

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
## Every projectile_hit as [caster, target, position, tag, hit profile at that moment].
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
	# Connected after Spells, as Combat is: it sees the profile a relay has already changed.
	_bus.projectile_hit.connect(func(caster: int, target: Node, at: Vector2, tag: int) -> void: _hits.append([caster, target, at, tag, _spells.hit_profile(tag)]))
	_form(&"bolt", 300.0, 1.0)
	_form(&"short", 300.0, 0.1)
	var rune: FormBase = _form(&"rune", 0.0, 10.0)
	rune.motion = FormBase.Motion.STILL
	rune.radius = 6.0
	var fire: ElementBase = ElementBase.new()
	fire.status_id = &"burn"
	fire.status_duration = 3.0
	fire.tint = Color(0.88, 0.35, 0.18)
	_put(fire, &"fire")
	var frost: ElementBase = ElementBase.new()
	frost.status_id = &"chill"
	frost.status_duration = 2.0
	_put(frost, &"frost")
	_modifier(&"shield", ModifierBase.Behaviour.SHIELD, 1.0)
	_modifier(&"relay", ModifierBase.Behaviour.RELAY, 1.0)
	var pierce := ModifierBase.new()
	pierce.extra_pierce = 1
	_put(pierce, &"pierce")
	_trigger(&"on_block", TriggerBase.Event.BLOCK, 1)
	_trigger(&"on_kill", TriggerBase.Event.KILL, 1)
	_trigger(&"on_cast", TriggerBase.Event.CAST, 1)
	_trigger(&"on_wall", TriggerBase.Event.WALL, 1)
	_trigger(&"on_hurt", TriggerBase.Event.HURT, 2)
	_trigger(&"on_reaction", TriggerBase.Event.REACTION, 1)


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


func _trigger(id: StringName, event: TriggerBase.Event, max_fires: int) -> void:
	var trigger := TriggerBase.new()
	trigger.event = event
	trigger.max_fires = max_fires
	_put(trigger, id)


## Builds `cards` as `caster`'s staff 0; returns the tag of the payload's first spell (node 1).
func _build(caster: int, cards: Array[StringName]) -> int:
	StaffKit.build(_spells, caster, 0, cards)
	return _spells.current_tag(caster, 0, 1)


## A body at `position`, the body of the actor `owner_actor` (none: -1).
func _target(position: Vector2, layer: int = ManagerScript.LAYER_ENEMY, owner_actor: int = EventsScript.NO_PLAYER) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = position
	own(node)
	_mgr.add_target(node, 10.0, layer, owner_actor)
	return node


func _tick(steps: int) -> void:
	for i in steps:
		_mgr.step(DT)
		_spells.step(DT)


func _slots(tag: int) -> Array[int]:
	var found: Array[int] = []
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot) and _mgr.get_tag_of(slot) == tag:
			found.append(slot)
	return found


func _cast(caster: int, direction: Vector2 = Vector2.RIGHT) -> void:
	_spells.cast_staff(caster, 0, Vector2.ZERO, direction, 10.0)


## The first live shot of `tag` (the carrier's), or -1.
func _first(tag: int) -> int:
	var found: Array[int] = _slots(tag)
	return -1 if found.is_empty() else found[0]


func test_on_cast_fires_at_once_from_the_caster() -> void:
	var held: int = _build(0, [&"on_cast", &"bolt", &"rune"])
	_spells.cast_staff(0, 0, Vector2(30, 40), Vector2.RIGHT, 10.0)
	var runes: Array[int] = _slots(held)
	check_equal(runes.size(), 1, "the payload is there before a single step")
	check(runes.size() == 1 and _mgr.get_position_of(runes[0]).is_equal_approx(Vector2(30, 40)), "from the caster")
	check_equal(_slots(_spells.current_tag(0, 0, 0)).size(), 1, "and the carrier flew as well")


func test_on_wall_fires_at_a_wall_only() -> void:
	var walls: Array[Rect2] = [Rect2(100, -50, 50, 100)]
	_mgr.set_walls(walls)
	var held: int = _build(0, [&"on_wall", &"short", &"rune"])
	_cast(0)
	_tick(20)
	check_equal(_spells.live_shots(held), 0, "a shot that runs out of life in the open does not fire it")
	held = _build(0, [&"on_wall", &"bolt", &"rune"])
	_tick(90)
	_cast(0)
	_tick(30)
	var runes: Array[int] = _slots(held)
	check_equal(runes.size(), 1, "a shot that hits the wall fires it once")
	check(runes.size() == 1 and _mgr.get_position_of(runes[0]).x < 100.0, "in front of the wall")


func test_on_block_fires_where_the_shield_stopped_the_shot() -> void:
	var held: int = _build(0, [&"shield", &"on_block", &"bolt", &"rune"])
	_cast(0, Vector2.RIGHT)
	_mgr.spawn(EventsScript.NO_PLAYER, Vector2(160, 0), Vector2(-100, 0), 3.0, 3.0, ManagerScript.LAYER_PLAYER, 0, 0)
	_mgr.spawn(EventsScript.NO_PLAYER, Vector2(200, 0), Vector2(-100, 0), 3.0, 3.0, ManagerScript.LAYER_PLAYER, 0, 0)
	_tick(60)
	check_equal(_slots(held).size(), 1, "one block, one payload (a shield of one charge)")


func test_on_block_respects_max_fires_with_a_bigger_shield() -> void:
	_modifier(&"shield2", ModifierBase.Behaviour.SHIELD, 2.0)
	var held: int = _build(0, [&"shield2", &"on_block", &"bolt", &"rune"])
	_cast(0, Vector2.RIGHT)
	_mgr.spawn(EventsScript.NO_PLAYER, Vector2(160, 0), Vector2(-100, 0), 3.0, 3.0, ManagerScript.LAYER_PLAYER, 0, 0)
	_mgr.spawn(EventsScript.NO_PLAYER, Vector2(200, 0), Vector2(-100, 0), 3.0, 3.0, ManagerScript.LAYER_PLAYER, 0, 0)
	_tick(60)
	check_equal(_slots(held).size(), 1, "two blocks of a two-charge shield, but max_fires 1: one payload")


func test_a_beam_on_kill_respects_max_fires() -> void:
	var beam: FormBase = _form(&"beam", 0.0, 0.1)
	beam.motion = FormBase.Motion.RAY
	beam.ray_length = 300.0
	beam.pierce = 3
	_bus.projectile_hit.connect(func(player: int, target: Node, at: Vector2, tag: int) -> void:
		_bus.kill_landed.emit(player, target, at, tag))
	_target(Vector2(100, 0))
	_target(Vector2(150, 0))
	var killed: int = _build(0, [&"on_kill", &"beam", &"rune"])
	_cast(0)
	_tick(30)
	var from_kill: int = 0
	for hit: Array in _hits:
		if hit[3] == killed:
			from_kill += 1
	check(_hits.size() >= 2, "the beam hit both targets")
	check_equal(from_kill, 1, "a beam that kills two targets fires an on kill of max_fires 1 once")


func test_on_kill_and_on_reaction_fire_from_the_hit() -> void:
	# What combat does: tell about the kill and the reaction while the hit is being sent.
	_bus.projectile_hit.connect(func(player: int, target: Node, at: Vector2, tag: int) -> void:
		if player == 0:
			_bus.kill_landed.emit(player, target, at, tag)
		else:
			_bus.reaction_landed.emit(player, &"steam", target, at, tag))
	_target(Vector2(100, 0))
	var killed: int = _build(0, [&"on_kill", &"bolt", &"rune"])
	var reacted: int = _build(1, [&"on_reaction", &"bolt", &"rune"])
	_cast(0)
	_spells.cast_staff(1, 0, Vector2.ZERO, Vector2.RIGHT, 10.0)
	_tick(30)
	# The payload is a rune born on the target, so it hits at once: count those hits.
	var from_kill: int = 0
	var from_reaction: int = 0
	for hit: Array in _hits:
		if hit[3] == killed:
			from_kill += 1
			check(absf((hit[2] as Vector2).x - 100.0) < 20.0, "on kill fired from the target")
		elif hit[3] == reacted:
			from_reaction += 1
	check_equal(from_kill, 1, "on kill fired once")
	check_equal(from_reaction, 1, "on reaction fired once")


func test_a_trigger_that_does_not_match_stays_quiet() -> void:
	var held: int = _build(0, [&"on_kill", &"bolt", &"rune"])
	var carrier: int = _spells.current_tag(0, 0, 0)
	_cast(0)
	var slot: int = _first(carrier)
	_bus.reaction_landed.emit(0, &"steam", null, Vector2(10, 0), carrier)
	_bus.shot_blocked.emit(0, Vector2(10, 0), carrier)
	_bus.kill_landed.emit(0, null, Vector2(10, 0), 77)
	_bus.projectile_expired.emit(0, Vector2(10, 0), carrier)
	check(slot >= 0, "the carrier flew")
	check_equal(_spells.live_shots(held), 0, "no other event, a bad tag or a null target fired the kill payload")


func test_on_hurt_fires_from_the_hurt_actor_for_each_live_carrier_up_to_its_limit() -> void:
	var long_held: int = _build(0, [&"on_hurt", &"bolt", &"rune"])
	_cast(0)
	_tick(2)
	_bus.actor_hurt.emit(1, 3, Vector2(5, 5), 0, &"hit")
	check_equal(_slots(long_held).size(), 0, "another actor's pain fires nothing")
	_bus.actor_hurt.emit(0, 3, Vector2(5, 5), 0, &"hit")
	var runes: Array[int] = _slots(long_held)
	check_equal(runes.size(), 1, "the caster's pain fires the payload")
	check(runes.size() == 1 and _mgr.get_position_of(runes[0]).is_equal_approx(Vector2(5, 5)), "from the hurt actor")
	_tick(1)
	_bus.actor_hurt.emit(0, 3, Vector2(5, 5), 0, &"hit")
	check_equal(_slots(long_held).size(), 2, "a second time (two fires)")
	_tick(1)
	_bus.actor_hurt.emit(0, 3, Vector2(5, 5), 0, &"hit")
	check_equal(_slots(long_held).size(), 2, "but not a third")


func test_on_hurt_stops_when_the_carrier_is_gone() -> void:
	var held: int = _build(0, [&"on_hurt", &"short", &"rune"])
	_cast(0)
	_tick(20)
	_bus.actor_hurt.emit(0, 3, Vector2(5, 5), 0, &"hit")
	check_equal(_spells.live_shots(held), 0, "an expired carrier fires nothing")


## The caster `donor` casts `donor_cards` away from everything, then wizard 0 casts a bolt with
## `cards` at the body of `donor` (registered as `donor`'s target), with a body of no actor
## behind it. Returns the hit profiles of wizard 0's hits, as a listener connected after Spells
## (Combat) sees them, in order.
func _relay_hits(donor: int, donor_cards: Array[StringName], cards: Array[StringName]) -> Array[HitProfile]:
	var layer: int = ManagerScript.LAYER_PLAYER if donor < 4 else ManagerScript.LAYER_ENEMY
	_target(Vector2(60, 0), layer, donor)
	_target(Vector2(200, 0))
	_build(donor, donor_cards)
	_build(0, cards)
	_spells.cast_staff(donor, 0, Vector2(0, 100), Vector2.DOWN, 10.0)
	_cast(0)
	_tick(60)
	var mine: Array[HitProfile] = []
	for hit: Array in _hits:
		if hit[0] == 0:
			mine.append(hit[4] as HitProfile)
	return mine


func test_relay_on_a_teammate_takes_their_last_infusion() -> void:
	var mine: Array[HitProfile] = _relay_hits(1, [&"frost", &"bolt"], [&"relay", &"bolt"])
	check_equal(mine.size(), 1, "the relay shot hit the teammate")
	if not mine.is_empty():
		check(mine[0] != null and mine[0].element_ids.has(&"frost"), "with the teammate's frost")
		check_equal(mine[0].status_id if mine[0] != null else &"", &"chill", "and its status")
	check_equal(_spells.hit_profile(_spells.current_tag(0, 0, 0)).element_ids.size(), 0, "the build itself stays plain")


func test_relay_on_an_enemy_actor_takes_its_fire() -> void:
	var imp: int = ActorSeats.enemy(_mgr.actors)
	var mine: Array[HitProfile] = _relay_hits(imp, [&"fire", &"bolt"], [&"relay", &"bolt"])
	check(mine.size() == 1 and mine[0] != null and mine[0].element_ids.has(&"fire"), "a hit on an enemy that cast fire takes fire")
	check_equal(mine[0].status_id if mine.size() == 1 and mine[0] != null else &"", &"burn", "and burns")


func test_relay_on_an_actor_that_never_cast_an_infusion_changes_nothing() -> void:
	var mine: Array[HitProfile] = _relay_hits(1, [&"bolt"], [&"relay", &"bolt"])
	check(mine.size() == 1 and mine[0].element_ids.is_empty(), "a teammate whose cast had no infusion gives nothing")


func test_a_relay_shot_keeps_what_it_took_for_its_later_hits() -> void:
	var mine: Array[HitProfile] = _relay_hits(1, [&"frost", &"bolt"], [&"relay", &"pierce", &"bolt"])
	check_equal(mine.size(), 2, "it pierced the teammate and hit the body behind")
	if mine.size() == 2:
		check_equal(mine[1].element_ids.count(&"frost"), 1, "the later hit keeps frost, once")


func test_a_plain_shot_takes_nothing() -> void:
	var mine: Array[HitProfile] = _relay_hits(1, [&"frost", &"bolt"], [&"bolt"])
	check(mine.size() == 1 and mine[0].element_ids.is_empty(), "no relay card, no change")
