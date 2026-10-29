extends "res://tests/support/suite.gd"
## Tests for casting and triggers in core/spells (M2 part 6): `cast` with per-player
## cooldowns, the shapes the forms make, triggers on hit, expire and timer with the per-step
## fire cap, the held spell's origin, direction and exclusion, chain, `hit_profile`, and
## four players with a rebuild mid-flight. It runs a real projectile manager and event bus,
## stepped by hand, with components built in code and a stand-in registry.
##
## godot --headless --path . --script res://tests/core/test_spells_cast.gd

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
## Every projectile_hit as [player, target, position, tag].
var _hits: Array = []
## tag -> how many of its shots have ended
var _ended: Dictionary = {}


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
	_ended.clear()
	_mgr.shot_ended.connect(func(tag: int) -> void: _ended[tag] = _ended.get(tag, 0) + 1)
	_bus.projectile_hit.connect(func(player: int, target: Node, at: Vector2, tag: int) -> void: _hits.append([player, target, at, tag]))
	_form(&"bolt", 5, 300.0, 1.0)
	_form(&"slow", 5, 60.0, 5.0)
	_form(&"short", 5, 300.0, 0.1)
	var heavy: FormBase = _form(&"heavy", 5, 300.0, 1.0)
	heavy.cooldown = 2.0
	var ring: FormBase = _form(&"ring", 5, 300.0, 1.0)
	ring.shots = 24
	ring.spread = 360.0
	var nova: FormBase = _form(&"nova", 5, 300.0, 1.0)
	nova.shots = 8
	nova.spread = 360.0
	var rune: FormBase = _form(&"rune", 5, 0.0, 10.0)
	rune.motion = FormBase.Motion.STILL
	rune.radius = 6.0
	var orb: FormBase = _form(&"orb", 5, 0.0, 5.0)
	orb.motion = FormBase.Motion.ORBIT
	orb.orbit_radius = 40.0
	orb.radius = 6.0
	orb.pierce = 8
	var beam: FormBase = _form(&"beam", 5, 0.0, 0.1)
	beam.motion = FormBase.Motion.RAY
	beam.ray_length = 200.0
	var fire: ElementBase = ElementBase.new()
	fire.status_id = &"burn"
	fire.status_duration = 3.0
	fire.damage_scale = 2.0
	fire.tint = Color(0.88, 0.35, 0.18)
	_put(fire, &"fire")
	var split: ModifierBase = ModifierBase.new()
	split.shot_mult = 3
	_put(split, &"split")
	var chain: ModifierBase = ModifierBase.new()
	chain.behaviour = ModifierBase.Behaviour.CHAIN
	chain.behaviour_strength = 2.0
	_put(chain, &"chain")
	var pierce: ModifierBase = ModifierBase.new()
	pierce.extra_pierce = 3
	_put(pierce, &"pierce")
	var homing: ModifierBase = ModifierBase.new()
	homing.behaviour = ModifierBase.Behaviour.HOMING
	homing.behaviour_strength = 6.0
	homing.behaviour_reach = 160.0
	_put(homing, &"homing")
	_trigger(&"on_hit", TriggerBase.Event.HIT)
	_trigger(&"on_expire", TriggerBase.Event.EXPIRE)
	var timer: TriggerBase = _trigger(&"timer", TriggerBase.Event.TIMER)
	timer.interval = 0.5


func _put(component: SpellComponent, id: StringName) -> void:
	component.id = id
	component.display_name = String(id).capitalize()
	component.complexity = 1
	_fake.items[id] = component


func _form(id: StringName, damage: int, speed: float, lifetime: float) -> FormBase:
	var form := FormBase.new()
	form.base_damage = damage
	form.speed = speed
	form.lifetime = lifetime
	form.mana_cost = 2.0
	_put(form, id)
	return form


func _trigger(id: StringName, event: TriggerBase.Event) -> TriggerBase:
	var trigger := TriggerBase.new()
	trigger.event = event
	_put(trigger, id)
	return trigger


## The first carrier of the staff for `recipe` (the old recipe shape, see staff_kit.gd).
func _compile(recipe: Dictionary) -> CompiledSpell:
	var spell: CompiledSpell = StaffKit.first(_spells, StaffKit.cards(recipe))
	check(spell != null, "the staff for %s casts" % [recipe])
	return spell


## Builds `recipe` into a staff and returns the tag of its first spell. A payload's spells have
## the next nodes, so `current_tag(player, staff, 1)` is the first one.
func _build(player: int, staff: int, recipe: Dictionary) -> int:
	return StaffKit.build(_spells, player, staff, StaffKit.cards(recipe))


func _held(form: StringName, trigger: StringName, held: StringName) -> Dictionary:
	return {"form": form, "trigger": trigger, "held": {"form": held}}


func _target(position: Vector2, radius: float = 10.0) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = position
	own(node)
	_mgr.add_target(node, radius, ManagerScript.LAYER_ENEMY)
	return node


func _tick(steps: int) -> void:
	for i in steps:
		_mgr.step(DT)
		_spells.step(DT)


## Shots ever made with `tag` since the test began (alive plus ended).
func _born(tag: int) -> int:
	return _spells.live_shots(tag) + int(_ended.get(tag, 0))


## The slots of the live shots, those with `tag` only if it is not 0.
func _slots(tag: int = 0) -> Array[int]:
	var found: Array[int] = []
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot) and (tag == 0 or _mgr.get_tag_of(slot) == tag):
			found.append(slot)
	return found


func _cast(player: int, slot: int = 0, mana: float = 10.0, origin: Vector2 = Vector2.ZERO, direction: Vector2 = Vector2.RIGHT) -> float:
	return _spells.cast_staff(player, slot, origin, direction, mana)


func test_a_cast_spends_mana_then_cools_down() -> void:
	_build(0, 0, {"form": &"bolt"})
	check_equal(_cast(0), 2.0, "the cast returns the mana it cost")
	check_equal(_mgr.get_count(), 1, "one shot")
	check_equal(_cast(0), SpellsScript.REFUSED, "cooling down")
	check_equal(_mgr.get_count(), 1, "a refused cast fires nothing")
	_tick(29)
	check_equal(_cast(0), SpellsScript.REFUSED, "still cooling after 29 of 30 steps")
	_tick(2)
	check_equal(_cast(0), 2.0, "ready again after the cooldown")


func test_a_refused_cast_changes_nothing() -> void:
	_build(0, 0, {"form": &"bolt"})
	check_equal(_cast(0, 0, 1.0), SpellsScript.REFUSED, "too little mana")
	check_equal(_cast(0, 0, 10.0, Vector2.ZERO, Vector2.ZERO), SpellsScript.REFUSED, "no direction")
	check_equal(_cast(0, 1), SpellsScript.REFUSED, "nothing built in slot B")
	check_equal(_cast(7), SpellsScript.REFUSED, "no player 7")
	check_equal(_spells.cooldown_left(0, 0), 0.0, "no cooldown was started")
	check_equal(_cast(0), 2.0, "so the next cast works at once")


func test_players_and_slots_cool_down_on_their_own() -> void:
	for player in 4:
		_build(player, 0, {"form": &"heavy" if player == 2 else &"bolt"})
	_build(0, 1, {"form": &"bolt"})
	for player in 4:
		check_equal(_cast(player), 2.0, "player %d casts" % player)
		check_equal(_mgr.get_count_for(player), 1, "player %d owns one shot" % player)
	check_equal(_cast(0), SpellsScript.REFUSED, "player 0 cools down")
	check_equal(_cast(0, 1), 2.0, "but slot B of player 0 does not")
	_tick(40)
	check_equal(_cast(0), 2.0, "player 0 is ready after 0.5 s")
	check_equal(_cast(2), SpellsScript.REFUSED, "player 2's heavier spell is not")
	check(_spells.cooldown_left(2, 0) > 1.0, "its cooldown is the longer one")


func test_split_fans_the_shots_over_the_spread() -> void:
	_build(0, 0, {"form": &"bolt", "modifiers": [&"split"]})
	_cast(0)
	var angles: Array[float] = []
	for slot in _slots():
		angles.append(snappedf(rad_to_deg(_mgr.get_velocity_of(slot).angle()), 0.01))
	angles.sort()
	check_equal(angles, [-15.0, 0.0, 15.0] as Array[float], "three shots, 30 degrees, centred on the aim")


func test_a_nova_is_an_even_ring() -> void:
	_build(0, 0, {"form": &"nova"})
	_cast(0)
	var sum: Vector2 = Vector2.ZERO
	for slot in _slots():
		sum += _mgr.get_velocity_of(slot)
	check_equal(_mgr.get_count(), 8, "eight shots")
	check(sum.length() < 0.01, "the ring is balanced: " + str(sum))


func test_still_and_orbit_shots_and_a_missing_anchor() -> void:
	_build(0, 0, {"form": &"rune"})
	_cast(0, 0, 10.0, Vector2(30, 30))
	_tick(10)
	check_equal(_mgr.get_position_of(_slots()[0]), Vector2(30, 30), "a rune stays where it was cast")
	_build(1, 0, {"form": &"orb"})
	check_equal(_cast(1), SpellsScript.REFUSED, "an orbit needs the caster's anchor")
	_mgr.set_anchor(1, Vector2(100, 100))
	check_equal(_cast(1), 2.0, "with it the orbit is cast")
	_tick(10)
	var orbit_slot: int = _slots(_spells.current_tag(1, 0))[0]
	check(is_equal_approx(_mgr.get_position_of(orbit_slot).distance_to(Vector2(100, 100)), 40.0), "it circles the anchor at the form's radius")


func test_every_shot_takes_the_colour_of_its_element_in_its_core() -> void:
	_build(0, 0, {"form": &"nova", "element": &"fire"})
	_cast(0)
	var shots: Array[int] = _slots()
	check_equal(shots.size(), 8, "the nova made its ring")
	for slot in shots:
		check_equal(_mgr.get_core_of(slot), Color(0.88, 0.35, 0.18), "a shot of the ring has the element's core")
	_build(1, 0, {"form": &"bolt"})
	_cast(1)
	var plain: int = _slots(_spells.current_tag(1, 0))[0]
	check_equal(_mgr.get_core_of(plain), Color.WHITE, "a spell with no element has a plain core")
	_build(2, 0, {"form": &"rune", "element": &"fire"})
	_cast(2, 0, 10.0, Vector2(30, 30))
	check_equal(_mgr.get_core_of(_slots(_spells.current_tag(2, 0))[0]), Color(0.88, 0.35, 0.18), "a rune has it too")
	_mgr.set_anchor(3, Vector2(100, 100))
	_build(3, 0, {"form": &"orb", "element": &"fire"})
	_cast(3)
	check_equal(_mgr.get_core_of(_slots(_spells.current_tag(3, 0))[0]), Color(0.88, 0.35, 0.18), "and an orbit shot")


func test_a_beam_and_a_nova_announce_themselves_for_looks() -> void:
	var seen: Array = []
	_bus.form_shown.connect(func(player: int, form: StringName, origin: Vector2, direction: Vector2, length: float, tint: Color, _look: int) -> void: seen.append([player, form, origin, direction, length, tint]))
	_build(2, 0, {"form": &"beam", "element": &"fire"})
	_cast(2, 0, 10.0, Vector2(5, 6), Vector2.DOWN)
	# A beam lives on for its lifetime, so it is shown from the live beams, not announced.
	check_equal(seen.size(), 0, "a beam is no announcement")
	check_equal(_spells.beam_count(), 1, "one live beam")
	var at: int = -1
	for i in _spells.beam_slots():
		if _spells.beam_on(i):
			at = i
	check_equal(_spells.beam_caster(at), 2, "from the caster")
	check_equal(_spells.beam_origin(at), Vector2(5, 6), "from the staff")
	check(_spells.beam_origin(at).direction_to(_spells.beam_end(at)).is_equal_approx(Vector2.DOWN), "along the aim")
	check(is_equal_approx(_spells.beam_reach(at), 200.0), "as long as it got (%s)" % str(_spells.beam_reach(at)))
	check_equal(_spells.beam_tint(at), Color(0.88, 0.35, 0.18), "in the element's colour")
	_build(1, 0, {"form": &"nova"})
	_cast(1)
	check_equal(seen.size(), 1, "one nova, one announcement, not one per shot")
	check_equal(seen[0][1], &"nova", "as a nova")
	seen.clear()
	_build(0, 0, {"form": &"bolt"})
	_cast(0)
	check_equal(seen.size(), 0, "a bolt has no announcement, it is drawn as a shot")


func test_a_beam_hits_instantly_and_counts_as_a_shot() -> void:
	_target(Vector2(100, 0))
	var tag: int = _build(0, 0, {"form": &"beam"})
	check_equal(_cast(0), 2.0, "the beam fired")
	check_equal(_hits.size(), 1, "it hit at once")
	check_equal(_hits[0][3], tag, "with the spell's tag")
	check_equal(_spells.live_shots(tag), 1, "it counts as a shot while it is on")
	_tick(30)
	check_equal(_spells.live_shots(tag), 0, "and is no longer counted when its life is over")


func test_on_hit_fires_the_held_spell_from_the_hit_point_along_the_shot() -> void:
	_target(Vector2(60, 0))
	_build(0, 0, _held(&"bolt", &"on_hit", &"bolt"))
	_cast(0, 0, 10.0, Vector2.ZERO, Vector2.RIGHT)
	_tick(30)
	check_equal(_hits.size(), 1, "the first shot hit once")
	check_equal(_mgr.get_count(), 1, "and was replaced by the held shot")
	var held: int = _slots()[0]
	check_equal(SpellTag.node_of(_mgr.get_tag_of(held)), 1, "the payload shot carries node 1's tag")
	check(_mgr.get_velocity_of(held).normalized().is_equal_approx(Vector2.RIGHT), "it flies the way the first one did")
	var hit_at: Vector2 = _hits[0][2]
	check(_mgr.get_position_of(held).x >= hit_at.x, "it started at the hit point")


func test_the_held_spell_cannot_hit_the_target_that_fired_it() -> void:
	var near: Node2D = _target(Vector2(60, 0))
	var far: Node2D = _target(Vector2(160, 0))
	_build(0, 0, {"form": &"bolt", "trigger": &"on_hit", "held": {"form": &"nova"}})
	_cast(0)
	_tick(60)
	var on_near: int = 0
	var on_far: int = 0
	for hit in _hits:
		if hit[1] == near:
			on_near += 1
		elif hit[1] == far:
			on_far += 1
	check_equal(on_near, 1, "the near target was hit by the first shot only, not by the nova born on it")
	check(on_far >= 1, "the nova reached something new")


func test_on_expire_fires_where_the_shot_ended() -> void:
	_build(0, 0, _held(&"short", &"on_expire", &"bolt"))
	_cast(0)
	_tick(3)
	check_equal(_mgr.get_count(), 1, "still the first shot")
	_tick(6)
	var shots: Array[int] = _slots()
	check_equal(shots.size(), 1, "the first shot is gone, its held spell flies")
	check_equal(SpellTag.node_of(_mgr.get_tag_of(shots[0])), 1, "at node 1")
	check(_mgr.get_position_of(shots[0]).x > 25.0, "from where the first one ended")


func test_on_expire_at_a_wall_fires_in_front_of_it() -> void:
	var walls: Array[Rect2] = [Rect2(100, -50, 50, 100)]
	_mgr.set_walls(walls)
	_build(0, 0, _held(&"bolt", &"on_expire", &"bolt"))
	var held_tag: int = _spells.current_tag(0, 0, 1)
	_cast(0)
	var shots: Array[int] = []
	for step in 40:
		_tick(1)
		shots = _slots(held_tag)
		if not shots.is_empty():
			break
	check_equal(shots.size(), 1, "the held shot exists")
	if not shots.is_empty():
		check(_mgr.get_position_of(shots[0]).x < 100.0, "in front of the wall, not inside it")


func test_a_timer_fires_every_interval_for_as_long_as_its_shot_lives() -> void:
	var tag: int = _build(0, 0, _held(&"slow", &"timer", &"rune"))
	var held_tag: int = _spells.current_tag(0, 0, 1)
	_cast(0)
	_tick(20)
	check_equal(_spells.live_shots(held_tag), 0, "nothing before the first interval")
	_tick(15)
	check_equal(_spells.live_shots(held_tag), 1, "one after 0.5 s")
	_tick(200)
	check_equal(_spells.live_shots(held_tag), 7, "one every 0.5 s: seven by 3.9 s, no count stops it")
	check_equal(_spells.live_shots(tag), 1, "the timer shot flies on")
	_tick(120)
	check_equal(_spells.live_shots(tag), 0, "until its 5 s life is over")
	check(_spells.live_shots(held_tag) >= 9, "and it fired all its life (%d)" % _spells.live_shots(held_tag))


func test_a_trigger_fires_every_time_its_event_happens() -> void:
	for x in [40.0, 70.0, 100.0, 130.0]:
		_target(Vector2(x, 0))
	_build(0, 0, {"form": &"bolt", "modifiers": [&"pierce"], "trigger": &"on_hit", "held": {"form": &"bolt"}})
	_cast(0)
	_tick(30)
	var first_hits: int = 0
	for hit in _hits:
		first_hits += 1 if hit[3] == _spells.current_tag(0, 0) else 0
	check_equal(first_hits, 4, "the shot pierced four targets")
	check_equal(_born(_spells.current_tag(0, 0, 1)), 4, "and its trigger fired at every hit")


func test_fires_past_a_steps_room_wait_for_the_next_step() -> void:
	for n in 24:
		_target(Vector2.from_angle(TAU * n / 24.0) * 120.0)
	var hold: Dictionary = {"form": &"ring", "trigger": &"on_hit", "held": {"form": &"bolt"}}
	_spells.fire_shots_per_step = 32
	_build(0, 0, hold)
	_build(0, 1, hold)
	_build(1, 0, hold)
	_cast(0, 0)
	_cast(0, 1)
	_cast(1, 0)
	var fired_0: int = 0
	for _i in 30:
		# The hits are in the manager's step; the runtime's step opens the next room.
		_mgr.step(DT)
		fired_0 = _born(_spells.current_tag(0, 0, 1)) + _born(_spells.current_tag(0, 1, 1))
		if fired_0 > 0:
			break
		_spells.step(DT)
	check_equal(fired_0, 32, "player 0 fired the step's room, from 48 hits")
	check_equal(_born(_spells.current_tag(1, 0, 1)), 24, "player 1 fired all 24: the room is per player")
	check_equal(_spells.fires_waited, 16, "the rest wait, not dropped")
	_spells.step(DT)
	check_equal(_born(_spells.current_tag(0, 0, 1)) + _born(_spells.current_tag(0, 1, 1)), 48, "and fire as the next step opens")


func test_chain_jumps_to_new_targets_only() -> void:
	var a: Node2D = _target(Vector2(60, 0))
	var b: Node2D = _target(Vector2(110, 0))
	var c: Node2D = _target(Vector2(160, 0))
	_build(0, 0, {"form": &"bolt", "modifiers": [&"chain"]})
	_cast(0)
	_tick(120)
	var order: Array = []
	for hit in _hits:
		order.append(hit[1])
	check_equal(order, [a, b, c], "each target once, in order, after two jumps")


func test_chain_does_not_bounce_between_two_targets() -> void:
	var a: Node2D = _target(Vector2(60, 0))
	var b: Node2D = _target(Vector2(110, 0))
	_build(0, 0, {"form": &"bolt", "modifiers": [&"chain"]})
	_cast(0)
	_tick(200)
	var order: Array = []
	for hit in _hits:
		order.append(hit[1])
	check_equal(order, [a, b], "two hits, though two jumps were left")


func test_a_beam_chains_with_another_beam() -> void:
	var a: Node2D = _target(Vector2(100, 0))
	var b: Node2D = _target(Vector2(110, 60))
	_build(0, 0, {"form": &"beam", "modifiers": [&"chain"]})
	_cast(0)
	var order: Array = []
	for hit in _hits:
		order.append(hit[1])
	# The jump is queued by the first hit's handler and cast after that beam returns.
	check_equal(order.size(), 2, "the beam hit two targets, though a jump could have hit the first again")
	check(order.has(a) and order.has(b), "one directly, the other by the jump")


func test_a_beam_makes_all_six_jumps() -> void:
	var line: Array[Node2D] = []
	for i in 8:
		line.append(_target(Vector2(60 + 40 * i, 0)))
	var recipe: Dictionary = {"form": &"beam", "modifiers": [&"chain", &"chain", &"chain"]}
	var spell: CompiledSpell = _compile(recipe)
	check_equal(spell.chain_jumps, 6, "three chain runes give the most jumps")
	_build(0, 0, recipe)
	_cast(0)
	check_equal(_hits.size(), 6 + 1, "the beam and all six jumps hit, deeper than the ray nesting limit")
	for i in 7:
		check_equal(_hits[i][1], line[i], "target %d was hit in order" % i)
	_tick(30)
	check_equal(_spells.live_shots(_spells.current_tag(0, 0, 0)), 0, "every beam was counted as ended")


func test_split_beams_chain_past_the_ray_depth() -> void:
	for x in range(40, 330, 30):
		for y in range(-60, 61, 30):
			_target(Vector2(x, y))
	var recipe: Dictionary = {"form": &"beam", "modifiers": [&"split", &"chain", &"chain"]}
	_build(0, 0, recipe)
	_cast(0)
	check(_hits.size() > 0, "the beams hit")
	var spell: CompiledSpell = _compile(recipe)
	check(_hits.size() > spell.shots * (spell.pierce + 1), "the jumps added hits beyond the first beams: %d" % _hits.size())
	_tick(30)
	check_equal(_spells.live_shots(_spells.current_tag(0, 0, 0)), 0, "every beam was counted as ended")


func test_a_beams_held_spell_flies_along_the_beam_from_the_hit() -> void:
	_target(Vector2(100, 0))
	_build(0, 0, _held(&"beam", &"on_hit", &"bolt"))
	_cast(0, 0, 10.0, Vector2.ZERO, Vector2.RIGHT)
	var shots: Array[int] = _slots()
	check_equal(shots.size(), 1, "the held shot is out")
	check_equal(_mgr.get_position_of(shots[0]), Vector2(100, 0), "from the hit point")
	check_equal(_mgr.get_velocity_of(shots[0]).normalized(), Vector2.RIGHT, "along the beam")


func test_a_held_spell_from_an_orbit_shot_goes_outward_from_the_caster() -> void:
	_mgr.set_anchor(0, Vector2(200, 200))
	_target(Vector2(200, 160))
	_build(0, 0, _held(&"orb", &"on_hit", &"bolt"))
	_cast(0, 0, 10.0, Vector2(200, 200), Vector2.UP)
	_tick(10)
	var held: Array[int] = _slots(_spells.current_tag(0, 0, 1))
	check_equal(held.size(), 1, "the orbit shot hit and fired")
	var outward: Vector2 = (_mgr.get_position_of(held[0]) - Vector2(200, 200)).normalized()
	check(_mgr.get_velocity_of(held[0]).normalized().is_equal_approx(outward), "away from the caster through the shot")


func test_hit_profile_gives_combat_the_numbers() -> void:
	var tag: int = _build(0, 0, {"form": &"bolt", "element": &"fire"})
	var profile: HitProfile = _spells.hit_profile(tag)
	check(profile != null, "the tag has a profile")
	check_equal(profile.damage, 10, "damage with the element's scale")
	check_equal(profile.status_id, &"burn", "the status")
	check_equal(profile.element_id, &"fire", "the element")
	check(profile.knockback > 0.0, "a hit pushes")
	check(_spells.hit_profile(tag) == _spells.hit_profile(tag), "the same object each time: no allocation")
	check(_spells.hit_profile(0) == null, "tag 0 is nobody's")
	check(_spells.hit_profile(12345) == null, "an unknown tag too")


func test_a_rebuild_mid_flight_leaves_the_old_shot_its_old_numbers() -> void:
	_target(Vector2(120, 0))
	var old: int = _build(0, 0, {"form": &"bolt"})
	_cast(0)
	_tick(5)
	var new: int = _build(0, 0, {"form": &"bolt", "element": &"fire"})
	check(old != new, "a new generation has a new tag")
	_tick(40)
	check_equal(_hits.size(), 1, "the old shot hit")
	check_equal(_hits[0][3], old, "with its old tag")
	check_equal(_spells.hit_profile(old), null, "its spell is forgotten once it ended")
	check_equal(_spells.hit_profile(new).damage, 10, "the new build has its own numbers")
	check_equal(_spells.generations_held(0, 0), 1, "only the current build is kept")


func test_an_old_shot_fires_its_old_held_spell_and_keeps_it_alive() -> void:
	_target(Vector2(60, 0))
	var old: int = _build(0, 0, _held(&"bolt", &"on_hit", &"bolt"))
	var old_held: int = _spells.current_tag(0, 0, 1)
	_cast(0)
	_tick(5)
	_build(0, 0, {"form": &"bolt"})
	_tick(10)
	check_equal(_spells.live_shots(old_held), 1, "the old shot fired the held spell of the old build")
	check(_spells.hit_profile(old_held) != null, "which is kept while that rune lives")
	check_equal(_spells.generations_held(0, 0), 2, "so two builds are held")
	_mgr.clear()
	check_equal(_spells.generations_held(0, 0), 1, "the old build is freed with its last shot")
	check_equal(_spells.live_shots(old), 0, "and nothing is counted")


func test_a_full_ring_of_rebuilds_removes_the_revoked_shots() -> void:
	var first: int = _build(0, 0, {"form": &"slow"})
	_cast(0)
	_build(1, 0, {"form": &"slow"})
	_cast(1)
	for n in SpellLimits.GENERATIONS - 1:
		_build(0, 0, {"form": &"bolt"})
	check_equal(_mgr.get_count_for(0), 1, "seven rebuilds keep the old shot")
	var wrapped: int = _build(0, 0, {"form": &"bolt", "element": &"fire"})
	check_equal(wrapped, first, "the ring came round to the first tag")
	check_equal(_mgr.get_count_for(0), 0, "the old shot was removed, not mis-profiled")
	check_equal(_mgr.get_count_for(1), 1, "another player's shot is not touched")
	check_equal(_spells.live_shots(wrapped), 0, "the new build starts with no shots")
	_tick(40)
	_cast(0)
	check_equal(_spells.live_shots(wrapped), 1, "and counts its own")
	_tick(130)
	check_equal(_spells.live_shots(wrapped), 0, "which ends normally")


func test_counts_return_to_zero_after_a_busy_fight() -> void:
	for n in 6:
		_target(Vector2(60 + 40 * n, 20 * (n % 3)))
	var recipes: Array[Dictionary] = [
		{"form": &"nova", "modifiers": [&"chain"], "trigger": &"on_hit", "held": {"form": &"bolt", "trigger": &"on_expire", "held": {"form": &"short"}}},
		{"form": &"bolt", "modifiers": [&"split", &"homing"], "trigger": &"timer", "held": {"form": &"short"}},
		{"form": &"beam", "modifiers": [&"chain"], "trigger": &"on_expire", "held": {"form": &"bolt"}},
		{"form": &"bolt", "modifiers": [&"pierce"], "trigger": &"on_hit_twice", "held": {"form": &"nova"}},
	]
	for player in 4:
		_build(player, 0, recipes[player])
	for player in 4:
		_cast(player)
	_tick(600)
	_build(0, 0, {"form": &"bolt"})
	for player in 4:
		for depth in 3:
			check_equal(_spells.live_shots(_spells.current_tag(player, 0, depth)), 0, "player %d depth %d has no shots left" % [player, depth])
	check_equal(_mgr.get_count(), 0, "the field is empty")
	for player in 4:
		check_equal(_spells.generations_held(player, 0), 1, "player %d holds only the current build" % player)


## How many live entries of the live-carrier list (whose clocks run) name `slot`.
func _timer_entries(slot: int) -> int:
	var found: int = 0
	for i in _spells._lc_count:
		if _spells._lc_kind[i] == SpellsScript.LC_SLOT and _spells._lc_ref[i] == slot and _spells._lc_where(i).is_finite():
			found += 1
	return found


func test_a_shot_replaced_in_its_slot_is_timed_once() -> void:
	_target(Vector2(60, 0))
	_target(Vector2(110, 0))
	_build(0, 0, {"form": &"bolt", "modifiers": [&"chain"], "trigger": &"timer", "held": {"form": &"short"}})
	_cast(0)
	var parent: int = _slots()[0]
	var reused: bool = false
	var most: int = 0
	for _i in 60:
		_tick(1)
		most = maxi(most, _timer_entries(parent))
		if _hits.size() == 1 and _mgr.is_alive(parent):
			reused = true
	check(reused, "the jump's shot took the slot of the shot that hit")
	check_equal(most, 1, "the slot is listed once, so its clock runs once")
	check(_born(_spells.current_tag(0, 0, 1)) <= 2, "the held spell fired at the timer's rate (1 s of life, every 0.5 s)")


func test_every_chain_jump_happens_however_many_in_one_step() -> void:
	# A dense crowd, so every jump finds a new target in reach.
	for x in range(20, 190, 8):
		for y in range(-60, 61, 8):
			_target(Vector2(x, y))
	var recipe: Dictionary = {"form": &"beam", "modifiers": [&"split", &"split", &"split", &"chain", &"chain", &"chain"]}
	var spell: CompiledSpell = _compile(recipe)
	check(spell.shots * spell.chain_jumps > SpellsScript.JUMP_QUEUE, "more jumps in one step than the jump ring starts with (%d)" % (spell.shots * spell.chain_jumps))
	_build(0, 0, recipe)
	_cast(0)
	# Up to shots x (jumps + 1); a beam at the fan's edge that misses the crowd makes none.
	check(_hits.size() > spell.shots + SpellsScript.JUMP_QUEUE, "more jumps landed in this one step than the ring starts with (%d hits)" % _hits.size())
	check(_hits.size() <= spell.shots * (spell.chain_jumps + 1), "and no more than the cards give")

func test_the_spell_runtime_steps_after_the_projectile_manager() -> void:
	check(ProjectSettings.get_order("autoload/Projectiles") < ProjectSettings.get_order("autoload/Spells"), "Projectiles is listed before Spells in project.godot")
