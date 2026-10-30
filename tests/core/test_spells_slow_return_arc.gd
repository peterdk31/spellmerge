extends "res://tests/support/suite.gd"
## The kit behind the Slow, Return and Arc cards (owner, 2026-10-27): `lifetime_mult` on a
## modifier, `return` as a modifier behaviour (it was a boomerang carrier), and `arc`, a shot that
## zaps the nearest enemy in its reach on a clock, at `SpellLimits.ARC_DAMAGE` of its damage with
## its infusions, as a hit that sets off `on hit` payloads and chains. It runs a real projectile
## manager and event bus, stepped by hand, with cards built in code.
##
## godot --headless --path . --script res://tests/core/test_spells_slow_return_arc.gd

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
## Every projectile_hit as [player, target, position, tag, the hit profile].
var _hits: Array = []
## Every shot that ended, as [player, position, tag].
var _ended: Array = []


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
	_ended.clear()
	_bus.projectile_hit.connect(func(player: int, target: Node, at: Vector2, tag: int, shot: int) -> void:
		_hits.append([player, target, at, tag, _spells.hit_profile(tag, shot)]))
	_bus.projectile_expired.connect(func(player: int, at: Vector2, tag: int, _shot: int) -> void: _ended.append([player, at, tag]))
	var bolt: FormBase = _form(&"bolt", 300.0, 1.0)
	bolt.base_damage = 10
	var orb: FormBase = _form(&"orb", 30.0, 3.0)
	orb.base_damage = 10
	var rune: FormBase = _form(&"rune", 0.0, 4.0)
	rune.carrier = &"rune"
	rune.base_damage = 10
	var beam: FormBase = _form(&"beam", 0.0, 0.3)
	beam.carrier = &"beam"
	beam.ray_length = 200.0
	var nova: FormBase = _form(&"nova", 300.0, 0.2)
	nova.shots = 8
	nova.spread = 360.0
	var slow: ModifierBase = _modifier(&"slow", ModifierBase.Behaviour.NONE, 0.0)
	slow.speed_mult = 0.3
	slow.lifetime_mult = 3.0
	_modifier(&"return", ModifierBase.Behaviour.RETURN, 1.0)
	var arc: ModifierBase = _modifier(&"arc", ModifierBase.Behaviour.ARC, 2.0)
	arc.behaviour_reach = 60.0
	var on_hit := TriggerBase.new()
	on_hit.event = TriggerBase.Event.HIT
	_put(on_hit, &"on_hit")
	var on_wall := TriggerBase.new()
	on_wall.event = TriggerBase.Event.WALL
	_put(on_wall, &"on_wall")
	var lightning := ElementBase.new()
	lightning.status_id = &"static"
	lightning.status_duration = 2.0
	lightning.status_strength = 10.0
	_put(lightning, &"lightning")


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
	form.radius = 4.0
	_put(form, id)
	return form


func _modifier(id: StringName, behaviour: ModifierBase.Behaviour, strength: float) -> ModifierBase:
	var modifier := ModifierBase.new()
	modifier.behaviour = behaviour
	modifier.behaviour_strength = strength
	_put(modifier, id)
	return modifier


func _compile(cards: Array[StringName]) -> CompiledStaff:
	return StaffKit.compile(_spells, cards)


func _build(player: int, cards: Array[StringName]) -> void:
	StaffKit.build(_spells, player, 0, cards)


func _target(position: Vector2) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = position
	own(node)
	_mgr.add_target(node, 8.0, ManagerScript.LAYER_ENEMY, EventsScript.NO_PLAYER)
	return node


func _tick(steps: int) -> void:
	for i in steps:
		_mgr.step(DT)
		_spells.step(DT)


func _cast(player: int = 0, from: Vector2 = Vector2.ZERO) -> void:
	_mgr.set_anchor(player, from)
	_spells.cast_staff(player, 0, from, Vector2.RIGHT, 100.0)


## Hits on `target`, in order.
func _hits_on(target: Node) -> Array:
	var out: Array = []
	for hit: Array in _hits:
		if hit[1] == target:
			out.append(hit)
	return out


# --- Slow: lifetime_mult --------------------------------------------------------------------

func test_slow_crawls_as_far_for_longer() -> void:
	var plain: CompiledSpell = _compile([&"bolt"]).casts[0].group.spells[0]
	var slow: CompiledSpell = _compile([&"slow", &"bolt"]).casts[0].group.spells[0]
	check(is_equal_approx(slow.speed, plain.speed * 0.3), "a third of the speed (%s)" % slow.speed)
	check(is_equal_approx(slow.lifetime, plain.lifetime * 3.0), "three times the life (%s)" % slow.lifetime)
	check(is_equal_approx(slow.speed * slow.lifetime, plain.speed * plain.lifetime * 0.9), "about as far")


func test_lifetime_factors_multiply_and_have_a_range() -> void:
	var twice: CompiledSpell = _compile([&"slow", &"slow", &"bolt"]).casts[0].group.spells[0]
	check(is_equal_approx(twice.lifetime, 9.0), "two slows: nine times the life (%s)" % twice.lifetime)
	var wild := ModifierBase.new()
	wild.lifetime_mult = 5.0
	check(not wild.range_problems().is_empty(), "5 is out of range")


# --- Return as a modifier -------------------------------------------------------------------

func test_a_returning_bolt_comes_back_to_its_caster() -> void:
	_build(0, [&"return", &"bolt"])
	_cast(0, Vector2(50.0, 50.0))
	_tick(20)
	check(_mgr.get_count() == 1 and _mgr.get_velocity_of(0).x > 0.0, "it flies out first")
	_tick(60)
	check(not _ended.is_empty() and (_ended.back()[1] as Vector2).distance_to(Vector2(50.0, 50.0)) < 4.0, "and ends back at the caster: %s" % [_ended])


func test_return_is_wasted_on_a_carrier_that_does_not_fly_out() -> void:
	for form: StringName in [&"beam", &"rune"]:
		var staff: CompiledStaff = _compile([&"return", form])
		check(staff.wasted.has(0), "return on a %s is wasted" % form)
		check(staff.wasted.has(0), "return on it is wasted: %s" % staff.wasted)


func test_the_boomerang_carrier_is_gone() -> void:
	check(not Carriers.ids().has(&"return"), "return is a modifier, not a carrier")


# --- Arc ------------------------------------------------------------------------------------

func test_an_arc_compiles_its_clock_reach_and_weaker_hit() -> void:
	var spell: CompiledSpell = _compile([&"arc", &"lightning", &"bolt"]).casts[0].group.spells[0]
	check(is_equal_approx(spell.arc_interval, 0.5), "two zaps a second: every 0.5 s (%s)" % spell.arc_interval)
	check_equal(spell.arc_reach, 60.0, "the card's reach")
	check(spell.arc_hit != null, "a zap's hit")
	if spell.arc_hit != null:
		check_equal(spell.arc_hit.damage, roundi(10 * SpellLimits.ARC_DAMAGE), "at ARC_DAMAGE of the shot")
		check_equal(spell.arc_hit.status_id, &"static", "with its infusion")
	var two: CompiledSpell = _compile([&"arc", &"arc", &"bolt"]).casts[0].group.spells[0]
	check(is_equal_approx(two.arc_interval, 0.25), "two arc cards zap twice as often (%s)" % two.arc_interval)


func test_a_slow_orb_zaps_the_enemy_beside_its_path() -> void:
	# A slow orb (30 px/s) passes 40 px from an imp: it never touches it, but zaps it.
	var imp: Node2D = _target(Vector2(30.0, 40.0))
	_build(0, [&"arc", &"lightning", &"orb"])
	_cast()
	_tick(150)
	var zaps: Array = _hits_on(imp)
	check(zaps.size() >= 3, "it zaps the imp again and again (%d)" % zaps.size())
	if not zaps.is_empty():
		var profile: HitProfile = zaps[0][4]
		check(profile != null and profile.damage == roundi(10 * SpellLimits.ARC_DAMAGE), "each zap at ARC_DAMAGE of the orb")
		check(profile != null and profile.status_id == &"static", "carrying the orb's infusion")


func test_no_zap_out_of_reach() -> void:
	var far: Node2D = _target(Vector2(30.0, 90.0))
	_build(0, [&"arc", &"orb"])
	_cast()
	_tick(120)
	check(_hits_on(far).is_empty(), "an imp 90 px off the path is out of a 60 px reach")


func test_zaps_keep_to_the_clock() -> void:
	var imp: Node2D = _target(Vector2(0.0, 40.0))
	_build(0, [&"arc", &"rune"])
	_cast()
	_tick(121)
	var zaps: int = _hits_on(imp).size()
	check(zaps >= 3 and zaps <= 5, "a rune zapping twice a second for 2 s zaps about 4 times (%d)" % zaps)


func test_a_zap_sets_off_on_hit() -> void:
	# `on hit` fires its payload at the first zapped imp, from there.
	var imp: Node2D = _target(Vector2(0.0, 40.0))
	_build(0, [&"arc", &"on_hit", &"rune", &"nova"])
	_cast()
	_tick(60)
	var novas: int = 0
	for row: Array in _ended:
		var spell: CompiledSpell = _spells._profiles.get(row[2])
		if spell != null and spell.form_id == &"nova":
			novas += 1
	check_equal(novas, 8, "the zap fired the nova payload once: eight nova shots")
	check(not _hits_on(imp).is_empty(), "the imp was zapped")


## Rules R4a: a zap that ends on a wall is not its shot meeting a wall: `on wall` stays quiet.
func test_a_zap_ending_on_a_wall_does_not_set_off_on_wall() -> void:
	var imp: Node2D = _target(Vector2(30.0, 40.0))
	_mgr.set_walls([Rect2(-100.0, 16.0, 300.0, 8.0)] as Array[Rect2])
	_build(0, [&"arc", &"on_wall", &"orb", &"nova"])
	_cast()
	var walls: Array[int] = [0]
	_mgr.wall_met.connect(func(_caster: int, _at: Vector2, _heading: Vector2, _tag: int, _shot: int) -> void: walls[0] += 1)
	var most: int = 0
	for _i in 90:
		_tick(1)
		most = maxi(most, _mgr.get_count())
	check(walls[0] > 0, "the zaps ended on the wall between the orb and the imp (%d)" % walls[0])
	check(_hits_on(imp).is_empty(), "the wall kept the imp from the zaps")
	check_equal(most, 1, "only the orb: its on wall payload never fired")


func test_arc_is_wasted_on_a_beam() -> void:
	var staff: CompiledStaff = _compile([&"arc", &"beam"])
	check(staff.wasted.has(0), "arc on a beam is wasted")


func test_zaps_are_capped_per_step() -> void:
	# More arc shots than the cap, all in reach at once: no step zaps more than the cap.
	_target(Vector2(0.0, 0.0))
	_mgr.set_cap(512)
	for player in 4:
		_build(player, [&"arc", &"rune"])
	var per_step: Array[int] = []
	for n in 12:
		for player in 4:
			_spells._cooldown.fill(0.0)
			_cast(player, Vector2(float(n), 0.0))
	var before: int = _hits.size()
	_tick(31)
	check(_hits.size() - before > 0, "they zap")
	check(_spells._arcs_used <= SpellLimits.MAX_ARCS_PER_STEP, "at most the cap in the last step")


func test_four_players_orbs_zap_their_own_imps() -> void:
	var imps: Array[Node2D] = []
	for player in 4:
		imps.append(_target(Vector2(30.0, 40.0 + 200.0 * player)))
		_build(player, [&"arc", &"orb"])
	for player in 4:
		_cast(player, Vector2(0.0, 200.0 * player))
	_tick(90)
	for player in 4:
		var zaps: Array = _hits_on(imps[player])
		check(not zaps.is_empty(), "player %d's orb zaps its imp" % player)
		for hit: Array in zaps:
			check_equal(hit[0], player, "zapped by its own player")
