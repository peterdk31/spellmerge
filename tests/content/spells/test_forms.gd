extends "res://tests/support/suite.gd"
## The five forms in content/spells/forms/ (M2 part 10): each is a FormBase resource that
## passes the validator, compiles, and behaves as its shape says when cast through the real
## spell runtime and projectile manager: the bolt flies straight, the beam hits along a line
## up to its reach, the nova throws a ring, the rune stays and waits, the orbit circles its
## caster. Every form also works for all four players at once.
##
## godot --headless --path . --script res://tests/content/spells/test_forms.gd

const StaffKit := preload("res://tests/support/staff_kit.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const DT: float = 1.0 / 60.0
const FORMS: Array[StringName] = [&"bolt", &"beam", &"nova", &"rune", &"orbit"]
## Complexity from the M2 design table.
const COMPLEXITY: Dictionary = {&"bolt": 1, &"beam": 2, &"nova": 2, &"rune": 2, &"orbit": 2}

var _registry: Node
var _spells: SpellsScript
var _mgr: ManagerScript
var _bus: EventsScript
## Every projectile_hit as [player, target, position, tag].
var _hits: Array = []


func before_each() -> void:
	_registry = own(RegistryScript.new()) as Node
	_registry.call("scan")
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _registry
	_spells.bind(_mgr, _bus)
	_hits.clear()
	_bus.projectile_hit.connect(func(player: int, target: Node, at: Vector2, tag: int) -> void: _hits.append([player, target, at, tag]))


func _form(id: StringName) -> FormBase:
	return load("res://content/spells/forms/%s/%s.tres" % [id, id]) as FormBase


func _target(position: Vector2, radius: float = 10.0) -> Node2D:
	var node := Node2D.new()
	root.add_child(node)
	node.global_position = position
	own(node)
	_mgr.add_target(node, radius, ManagerScript.LAYER_ENEMY)
	return node


func _tick(steps: int, anchors: Dictionary = {}) -> void:
	for i in steps:
		for player: int in anchors:
			_mgr.set_anchor(player, anchors[player])
		_mgr.step(DT)
		_spells.step(DT)


## Builds a bare `form` into staff A of `player` and casts it from `origin` toward `direction`.
func _cast(form: StringName, player: int, origin: Vector2, direction: Vector2 = Vector2.RIGHT) -> int:
	var tag: int = StaffKit.build(_spells, player, 0, [form] as Array[StringName])
	check(tag != 0, "%s builds" % form)
	# An orbit needs its caster's anchor; the player pushes it every step.
	_mgr.set_anchor(player, origin)
	check(_spells.cast_staff(player, 0, origin, direction, 100.0) != SpellsScript.REFUSED, "%s is cast" % form)
	return tag


func _slots(tag: int) -> Array[int]:
	var found: Array[int] = []
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot) and _mgr.get_tag_of(slot) == tag:
			found.append(slot)
	return found


func _hit_targets() -> Array:
	var targets: Array = []
	for hit: Array in _hits:
		targets.append(hit[1])
	return targets


# --- All five ---------------------------------------------------------------

func test_every_form_loads_and_matches_its_folder() -> void:
	for id in FORMS:
		var form: FormBase = _form(id)
		check(form != null, "%s loads as a FormBase" % id)
		if form == null:
			continue
		check_equal(form.id, id, "%s: the id is the folder name" % id)
		check(form.display_name != "", "%s has a name" % id)
		check(form.icon != null, "%s has an icon" % id)
		check(form.demo, "%s is in the web demo" % id)
		check_equal(form.complexity, COMPLEXITY[id], "%s: complexity from the design table" % id)
		check_equal(form.range_problems().size(), 0, "%s: %s" % [id, ", ".join(form.range_problems())])


func test_the_registry_finds_the_five_forms_and_the_validator_passes_them() -> void:
	var manifest: Dictionary = SpellValidator.load_manifest()
	for id in FORMS:
		var form: FormBase = _registry.call("get_resource", &"spells", id) as FormBase
		check(form != null, "the registry finds %s as a form" % id)
		if form == null:
			continue
		for problem in SpellValidator.check_component(form, manifest):
			check(false, SpellValidator.format(problem))


func test_each_form_has_the_motion_its_shape_needs() -> void:
	check_equal(_form(&"bolt").motion, FormBase.Motion.STRAIGHT, "bolt flies")
	check_equal(_form(&"nova").motion, FormBase.Motion.STRAIGHT, "nova flies")
	check_equal(_form(&"beam").motion, FormBase.Motion.RAY, "beam is a ray")
	check_equal(_form(&"rune").motion, FormBase.Motion.STILL, "rune waits")
	check_equal(_form(&"orbit").motion, FormBase.Motion.ORBIT, "orbit circles")
	check(_form(&"beam").ray_length > 0.0, "a beam has a reach")
	check(_form(&"orbit").orbit_radius > 0.0, "an orbit has a radius")


func test_every_form_works_for_all_four_players_at_once() -> void:
	for id in FORMS:
		_spells.clear()
		_mgr.clear()
		for player in 4:
			var anchor := Vector2(0.0, 300.0 * player)
			_mgr.set_anchor(player, anchor)
			_cast(id, player, anchor)
		for player in 4:
			if id != &"beam":
				check(_mgr.get_count_for(player) > 0, "%s: player %d has shots" % [id, player])
			else:
				check_equal(_mgr.get_count_for(player), 0, "beam: a ray holds no shot")
		_spells.clear()


# --- Bolt -------------------------------------------------------------------

func test_the_bolt_is_one_shot_that_flies_straight_and_hits() -> void:
	var imp := _target(Vector2(100.0, 0.0))
	_target(Vector2(100.0, 60.0))
	var tag: int = _cast(&"bolt", 0, Vector2.ZERO)
	check_equal(_mgr.get_count(), 1, "one shot")
	_tick(30)
	check_equal(_hit_targets(), [imp] as Array, "it hit the imp in its way and not the one beside it")
	check_equal(_spells.hit_profile(tag).damage, _form(&"bolt").base_damage, "a bare bolt hits for its base damage")


func test_the_bolt_ends_after_its_lifetime() -> void:
	_cast(&"bolt", 0, Vector2.ZERO)
	_tick(ceili(_form(&"bolt").lifetime / DT) + 4)
	check_equal(_mgr.get_count(), 0, "the shot expired")


# --- Beam -------------------------------------------------------------------

func test_the_beam_hits_along_a_line_up_to_its_reach_at_once() -> void:
	var near := _target(Vector2(60.0, 0.0))
	var second := _target(Vector2(120.0, 0.0))
	var third := _target(Vector2(180.0, 0.0))
	var beside := _target(Vector2(120.0, 50.0))
	_cast(&"beam", 0, Vector2.ZERO)
	check_equal(_form(&"beam").pierce, 0, "a beam pierces only with pierce cards")
	check_equal(_hit_targets(), [near] as Array, "a bare beam hits the nearest on the line and stops there")
	check(not _hit_targets().has(second) and not _hit_targets().has(third) and not _hit_targets().has(beside), "not the ones behind it nor the one beside it")
	check_equal(_mgr.get_count(), 0, "a beam holds no shot")


func test_one_beam_hits_at_once_and_every_tick_of_its_life() -> void:
	_target(Vector2(60.0, 0.0))
	var spell: CompiledSpell = StaffKit.first(_spells, [&"beam"] as Array[StringName])
	_cast(&"beam", 0, Vector2.ZERO)
	check_equal(_hits.size(), 1, "a hit at once")
	check_equal(_spells.beam_count(), 1, "and the beam stays on")
	_tick(60)
	var hits: int = SpellsScript.beam_hits(FormBase.Motion.RAY, spell.lifetime)
	check_equal(_hits.size(), hits, "then one hit every %s s of its %s s life" % [SpellLimits.BEAM_TICK, spell.lifetime])
	check_equal(_spells.beam_count(), 0, "then it is gone")
	check_equal(spell.damage, 2, "a hit does 2 damage")


func test_a_held_beam_stays_on_and_drains_mana_steadily() -> void:
	_target(Vector2(60.0, 0.0))
	# A starter staff (the curl): the beam's life covers a whole cast cycle, so held fire leaves no gap.
	var staff: StaffBase = load("res://content/wizard/staffs/curl/curl.tres") as StaffBase
	_spells.install_staff(0, 0, _spells.compile_staff([&"beam"] as Array[StringName], staff))
	var spell: CompiledSpell = StaffKit.first(_spells, [&"beam"] as Array[StringName])
	var mana: float = 100.0
	var casts: int = 0
	var dark: int = 0
	# Fire is held for 2 seconds: the player casts whenever the staff allows.
	for i in 120:
		var taken: float = _spells.cast_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, mana)
		if taken != SpellsScript.REFUSED:
			mana -= taken
			casts += 1
		if _spells.beam_count() == 0:
			dark += 1
		_tick(1)
	check_equal(dark, 0, "a beam is on in every step")
	check_equal(spell.mana_cost, 4.0, "a cast costs 4 mana")
	check(absf(100.0 - mana - 4.0 * casts) < 0.01, "each cast takes 4 mana (%f)" % mana)
	check(absi(_hits.size() - roundi(2.0 / SpellLimits.BEAM_TICK)) <= 3, "the enemy is hit about every %s s: %d hits" % [SpellLimits.BEAM_TICK, _hits.size()])


func test_the_beam_does_not_reach_past_its_length() -> void:
	_target(Vector2(_form(&"beam").ray_length + 40.0, 0.0))
	_cast(&"beam", 0, Vector2.ZERO)
	check_equal(_hits.size(), 0, "a target beyond the reach is safe")


# --- Nova -------------------------------------------------------------------

func test_the_nova_throws_a_ring_in_every_direction() -> void:
	var form: FormBase = _form(&"nova")
	check_equal(form.shots, 8, "eight shots")
	var around: Array[Node2D] = []
	for n in 8:
		around.append(_target(Vector2.from_angle(TAU * n / 8.0) * 45.0))
	_cast(&"nova", 0, Vector2.ZERO)
	check_equal(_mgr.get_count(), 8, "eight shots in the air")
	_tick(30)
	var hit: Array = _hit_targets()
	for n in 8:
		check(hit.has(around[n]), "the target at %d degrees was hit" % (45 * n))
	check_equal(hit.size(), 8, "each exactly once")


func test_the_nova_does_not_hit_past_its_reach() -> void:
	var form: FormBase = _form(&"nova")
	_target(Vector2(form.speed * form.lifetime + 60.0, 0.0))
	_cast(&"nova", 0, Vector2.ZERO)
	_tick(60)
	check_equal(_hits.size(), 0, "a target beyond the reach is not hit")


# --- Rune -------------------------------------------------------------------

func test_the_rune_stays_where_it_was_cast_and_hits_what_walks_in() -> void:
	var tag: int = _cast(&"rune", 0, Vector2(50.0, 50.0))
	check_equal(_slots(tag).size(), 1, "one rune")
	_tick(90)
	check_equal(_mgr.get_position_of(_slots(tag)[0]), Vector2(50.0, 50.0), "it did not move")
	check_equal(_hits.size(), 0, "nobody was near")
	var imp := _target(Vector2(300.0, 300.0))
	imp.global_position = Vector2(55.0, 50.0)
	_tick(4)
	check_equal(_hit_targets(), [imp] as Array, "an imp that walks in is hit")


func test_the_rune_stays_when_the_caster_and_a_target_move_away() -> void:
	var tag: int = _cast(&"rune", 0, Vector2.ZERO)
	var imp := _target(Vector2(300.0, 0.0))
	_tick(30, {0: Vector2(200.0, 0.0)})
	imp.global_position = Vector2(400.0, 0.0)
	_tick(30, {0: Vector2(200.0, 0.0)})
	check_equal(_mgr.get_position_of(_slots(tag)[0]), Vector2.ZERO, "the rune stays at the cast point")
	check_equal(_hits.size(), 0, "nobody was near it")


# --- Orbit ------------------------------------------------------------------

func test_the_orbit_circles_its_caster_at_the_forms_radius() -> void:
	var form: FormBase = _form(&"orbit")
	var centre := Vector2(100.0, 100.0)
	var tag: int = _cast(&"orbit", 0, centre)
	_tick(1, {0: centre})
	check_equal(_slots(tag).size(), form.shots, "one orb per shot")
	var before: Array[Vector2] = []
	for slot in _slots(tag):
		before.append(_mgr.get_position_of(slot))
	_tick(40, {0: centre})
	var moved: bool = false
	var index: int = 0
	for slot in _slots(tag):
		check(is_equal_approx(_mgr.get_position_of(slot).distance_to(centre), form.orbit_radius), "orb %d stays at the radius" % index)
		moved = moved or not _mgr.get_position_of(slot).is_equal_approx(before[index])
		index += 1
	check(moved, "the orbs turn")


func test_the_orbit_follows_a_moving_caster() -> void:
	var form: FormBase = _form(&"orbit")
	var tag: int = _cast(&"orbit", 0, Vector2.ZERO)
	_tick(30, {0: Vector2(300.0, 0.0)})
	for slot in _slots(tag):
		check(is_equal_approx(_mgr.get_position_of(slot).distance_to(Vector2(300.0, 0.0)), form.orbit_radius), "the orb moved with the caster")


func test_the_orbit_hits_an_enemy_that_crosses_it() -> void:
	var form: FormBase = _form(&"orbit")
	var centre := Vector2.ZERO
	var imp := _target(Vector2(form.orbit_radius, 0.0))
	_cast(&"orbit", 0, centre)
	_tick(120, {0: centre})
	check(_hit_targets().has(imp), "an imp standing on the orbit is hit")
	check(_hits.size() < 12, "a pass hits once, not every step (%d hits in two seconds)" % _hits.size())


func test_the_orbit_ends_with_its_lifetime() -> void:
	var form: FormBase = _form(&"orbit")
	var tag: int = _cast(&"orbit", 0, Vector2.ZERO)
	_tick(ceili(form.lifetime / DT) + 4, {0: Vector2.ZERO})
	check_equal(_slots(tag).size(), 0, "the orbs are gone")
	check_equal(_spells.live_shots(tag), 0, "and counted as ended")
