extends "res://tests/support/suite.gd"
## The kit behind the Slow, Return and Arc cards (owner, 2026-10-27): `lifetime_mult` on a
## modifier, `return` as a modifier behaviour (it was a boomerang carrier), and `arc`, a shot that
## zaps the nearest enemy in its reach on a clock, at `SpellLimits.ZAP_DAMAGE` of its damage with
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
	# A sure zap (100%), so these tests read its rules, not its chance (tests/content/spells/test_zap.gd).
	var arc: ModifierBase = _modifier(&"zap", ModifierBase.Behaviour.ZAP, 1.0)
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

func test_a_zap_compiles_its_chance_reach_and_weaker_hit() -> void:
	var spell: CompiledSpell = _compile([&"zap", &"lightning", &"bolt"]).casts[0].group.spells[0]
	check(is_equal_approx(spell.zap_chance, 1.0), "the card's chance (%s)" % spell.zap_chance)
	check_equal(spell.zap_reach, 60.0, "the card's reach")
	check(spell.zap_hit != null, "a zap's hit")
	if spell.zap_hit != null:
		check(is_equal_approx(spell.zap_hit.damage, 10.0 * SpellLimits.ZAP_DAMAGE), "at ZAP_DAMAGE of the shot")
		check_equal(spell.zap_hit.status_id, &"static", "with its infusion")
	var two: CompiledSpell = _compile([&"zap", &"zap", &"bolt"]).casts[0].group.spells[0]
	check(is_equal_approx(two.zap_chance, 1.0), "two sure cards are still sure, never past 100%% (%s)" % two.zap_chance)


func test_a_slow_orb_zaps_the_enemy_beside_its_path() -> void:
	# A slow orb (30 px/s) passes 40 px from an imp: it never touches it, but zaps it, once.
	var imp: Node2D = _target(Vector2(30.0, 40.0))
	_build(0, [&"zap", &"lightning", &"orb"])
	_cast()
	_tick(150)
	var zaps: Array = _hits_on(imp)
	check_equal(zaps.size(), 1, "it zaps the imp once, as it comes in reach")
	if not zaps.is_empty():
		var profile: HitProfile = zaps[0][4]
		check(profile != null and is_equal_approx(profile.damage, 10.0 * SpellLimits.ZAP_DAMAGE), "the zap at ZAP_DAMAGE of the orb")
		check(profile != null and profile.status_id == &"static", "carrying the orb's infusion")


func test_no_zap_out_of_reach() -> void:
	var far: Node2D = _target(Vector2(30.0, 90.0))
	_build(0, [&"zap", &"orb"])
	_cast()
	_tick(120)
	check(_hits_on(far).is_empty(), "an imp 90 px off the path is out of a 60 px reach")


## Each body rolls once a shot (owner, 2026-10-30): a rune beside an imp for 4 s zaps it once, at a
## random moment of the most a zap waits (SpellLimits.ZAP_WAIT_MOST: a rune stands still).
func test_each_body_is_zapped_once_a_shot() -> void:
	var imp: Node2D = _target(Vector2(0.0, 40.0))
	_build(0, [&"zap", &"rune"])
	_cast()
	_tick(roundi(SpellLimits.ZAP_WAIT_MOST / DT) + 2 * SpellLimits.ZAP_EVERY + 1)
	check_equal(_hits_on(imp).size(), 1, "zapped within the longest wait")
	_tick(240)
	check_equal(_hits_on(imp).size(), 1, "and never again by that rune")


## The moment is random too (owner, 2026-10-30): bolts flying past the same imp zap it from
## different places on their way through its reach, not all as it comes in reach.
func test_bolts_past_an_imp_zap_it_from_different_places() -> void:
	var imp: Node2D = _target(Vector2(120.0, 40.0))
	var from: Array[float] = []
	_bus.form_shown.connect(func(_caster: int, form: StringName, origin: Vector2, _way: Vector2, length: float, _tint: Color, _look: int) -> void:
		if form == &"zap" and length > 22.0:
			from.append(origin.x))
	_build(0, [&"zap", &"bolt"])
	for n in 10:
		_spells._cooldown.fill(0.0)
		_cast()
		_tick(90)
	var low: float = INF
	var high: float = -INF
	for x: float in from:
		low = minf(low, x)
		high = maxf(high, x)
	check_equal(from.size(), 10, "every bolt zapped the imp (a sure card)")
	check(high - low > 30.0, "from places along the way more than 30 px apart (%.0f to %.0f)" % [low, high])


## The body a shot is about to hit is zapped before the shot gets there (its wait ends first).
func test_the_body_ahead_is_zapped_before_the_shot_hits_it() -> void:
	var imp: Node2D = _target(Vector2(100.0, 0.0))
	_build(0, [&"zap", &"bolt"])
	for n in 8:
		_spells._cooldown.fill(0.0)
		_cast()
		_tick(60)
	var kinds: Array[StringName] = []
	for hit: Array in _hits_on(imp):
		var profile: HitProfile = hit[4]
		kinds.append(profile.kind if profile != null else &"")
	var order: PackedStringArray = PackedStringArray()
	for kind: StringName in kinds:
		order.append(String(kind))
	check_equal(kinds.size(), 16, "eight bolts and their eight zaps (%s)" % ", ".join(order))
	for n in mini(kinds.size(), 16) / 2:
		check(kinds[n * 2] == &"ray" and kinds[n * 2 + 1] != &"ray", "bolt %d: the zap, then the bolt (%s)" % [n, ", ".join(order)])


func test_a_zap_sets_off_on_hit() -> void:
	# `on hit` fires its payload at the first zapped imp, from there.
	var imp: Node2D = _target(Vector2(0.0, 40.0))
	_build(0, [&"zap", &"on_hit", &"rune", &"nova"])
	_cast()
	_tick(121)
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
	_build(0, [&"zap", &"on_wall", &"orb", &"nova"])
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


func test_zap_is_wasted_on_a_beam() -> void:
	var staff: CompiledStaff = _compile([&"zap", &"beam"])
	check(staff.wasted.has(0), "zap on a beam is wasted")


func test_zaps_are_capped_per_step() -> void:
	# More arc shots than the cap, all in reach at once: no step zaps more than the cap.
	_target(Vector2(0.0, 0.0))
	_mgr.set_cap(512)
	for player in 4:
		_build(player, [&"zap", &"rune"])
	var per_step: Array[int] = []
	for n in 12:
		for player in 4:
			_spells._cooldown.fill(0.0)
			_cast(player, Vector2(float(n), 0.0))
	var before: int = _hits.size()
	_tick(31)
	check(_hits.size() - before > 0, "they zap")
	check(_spells._zaps_used <= SpellLimits.MAX_ZAPS_PER_STEP, "at most the cap in the last step")


func test_four_players_orbs_zap_their_own_imps() -> void:
	var imps: Array[Node2D] = []
	for player in 4:
		imps.append(_target(Vector2(30.0, 40.0 + 200.0 * player)))
		_build(player, [&"zap", &"orb"])
	for player in 4:
		_cast(player, Vector2(0.0, 200.0 * player))
	_tick(90)
	for player in 4:
		var zaps: Array = _hits_on(imps[player])
		check(not zaps.is_empty(), "player %d's orb zaps its imp" % player)
		for hit: Array in zaps:
			check_equal(hit[0], player, "zapped by its own player")
