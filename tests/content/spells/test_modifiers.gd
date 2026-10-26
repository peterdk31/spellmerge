extends "res://tests/support/suite.gd"
## The six modifiers in content/spells/modifiers/ (M2 part 12): each is a ModifierBase
## resource that passes the validator, compiles into the numbers it promises, and changes a
## cast through the real spell runtime and projectile manager as its name says: split throws
## a fan, pierce passes through targets, homing curves toward one, chain jumps on to the next,
## bigger hits wider and faster arrives sooner. Every modifier also works for all four players
## at once.
##
## godot --headless --path . --script res://tests/content/spells/test_modifiers.gd

const StaffKit := preload("res://tests/support/staff_kit.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const DT: float = 1.0 / 60.0
const MODIFIERS: Array[StringName] = [&"split", &"pierce", &"homing", &"chain", &"bigger", &"faster"]
## Complexity from the M2 design table.
const COMPLEXITY: Dictionary = {&"split": 2, &"pierce": 1, &"homing": 2, &"chain": 2, &"bigger": 1, &"faster": 1}

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


func _modifier(id: StringName) -> ModifierBase:
	return load("res://content/spells/modifiers/%s/%s.tres" % [id, id]) as ModifierBase


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


## The modifiers before the form: one carrier with all of them (staffs A6c).
func _row(form: StringName, modifiers: Array[StringName]) -> Array[StringName]:
	var row: Array[StringName] = modifiers.duplicate()
	row.append(form)
	return row


func _compile(form: StringName, modifiers: Array[StringName]) -> CompiledSpell:
	var spell: CompiledSpell = StaffKit.first(_spells, _row(form, modifiers))
	check(spell != null, "%s + %s compiles" % [form, modifiers])
	return spell


## Builds `form` with `modifiers` into staff A of `player` and casts it from `origin`.
func _cast(form: StringName, modifiers: Array[StringName], player: int, origin: Vector2, direction: Vector2 = Vector2.RIGHT) -> int:
	var tag: int = StaffKit.build(_spells, player, 0, _row(form, modifiers))
	check(_spells.cast_staff(player, 0, origin, direction, 100.0) != SpellsScript.REFUSED, "%s + %s is cast" % [form, modifiers])
	return tag


func _hit_targets() -> Array:
	var targets: Array = []
	for hit: Array in _hits:
		targets.append(hit[1])
	return targets


## Ticks until the first hit and returns the number of steps it took (-1 if none in `limit`).
func _steps_to_first_hit(limit: int) -> int:
	for step in limit:
		_tick(1)
		if not _hits.is_empty():
			return step + 1
	return -1


# --- All six ----------------------------------------------------------------

func test_every_modifier_loads_and_matches_its_folder() -> void:
	for id in MODIFIERS:
		var modifier: ModifierBase = _modifier(id)
		check(modifier != null, "%s loads as a ModifierBase" % id)
		if modifier == null:
			continue
		check_equal(modifier.id, id, "%s: the id is the folder name" % id)
		check(modifier.display_name != "", "%s has a name" % id)
		check(modifier.icon != null, "%s has an icon" % id)
		check(modifier.demo, "%s is in the web demo" % id)
		check_equal(modifier.complexity, COMPLEXITY[id], "%s: complexity from the design table" % id)
		check_equal(modifier.range_problems().size(), 0, "%s: %s" % [id, ", ".join(modifier.range_problems())])


func test_the_registry_finds_the_six_modifiers_and_the_validator_passes_them() -> void:
	var manifest: Dictionary = SpellValidator.load_manifest()
	for id in MODIFIERS:
		var modifier: ModifierBase = _registry.call("get_resource", &"spells", id) as ModifierBase
		check(modifier != null, "the registry finds %s as a modifier" % id)
		if modifier == null:
			continue
		for problem in SpellValidator.check_component(modifier, manifest):
			check(false, SpellValidator.format(problem))


func test_every_modifier_has_its_own_icon() -> void:
	var seen: Dictionary = {}
	for id in MODIFIERS:
		var path: String = _modifier(id).icon.resource_path
		check(not seen.has(path), "%s: the icon %s is not shared" % [id, path])
		seen[path] = true


func test_the_behaviours_are_on_the_right_modifiers() -> void:
	check_equal(_modifier(&"homing").behaviour, ModifierBase.Behaviour.HOMING, "homing homes")
	check_equal(_modifier(&"chain").behaviour, ModifierBase.Behaviour.CHAIN, "chain chains")
	for id: StringName in [&"split", &"pierce", &"bigger", &"faster"]:
		check_equal(_modifier(id).behaviour, ModifierBase.Behaviour.NONE, "%s is numbers only" % id)


func test_every_modifier_works_for_all_four_players_at_once() -> void:
	for index in MODIFIERS.size():
		var id: StringName = MODIFIERS[index]
		_spells.clear()
		_mgr.clear()
		_hits.clear()
		# Each player has a target of their own straight ahead; the rows are 400 px apart so
		# that no homing or chain reach can leak from one player's shot to another's target. Each
		# modifier gets its own column, inside the projectile bounds.
		var targets: Array[Node2D] = []
		for player in 4:
			var origin := Vector2(-900.0 + 300.0 * index, -900.0 + 400.0 * player)
			targets.append(_target(origin + Vector2(100.0, 0.0)))
			_cast(&"bolt", [id], player, origin)
		for player in 4:
			check(_mgr.get_count_for(player) > 0, "%s: player %d has shots" % [id, player])
		_tick(60)
		for player in 4:
			var credited: bool = false
			var stolen: bool = false
			for hit: Array in _hits:
				if hit[1] == targets[player]:
					credited = credited or hit[0] == player
					stolen = stolen or hit[0] != player
			check(credited, "%s: player %d hit their own target" % [id, player])
			check(not stolen, "%s: nobody else hit player %d's target" % [id, player])
		_spells.clear()


func test_a_modifier_may_appear_twice_and_stacks() -> void:
	var twice: CompiledSpell = _compile(&"bolt", [&"pierce", &"pierce"])
	check_equal(twice.pierce, 4, "two pierce modifiers pierce four")
	var faster: CompiledSpell = _compile(&"bolt", [&"faster", &"faster"])
	check_equal(faster.speed, 220.0 * 1.5 * 1.5, "two faster modifiers multiply the speed")


func test_many_modifiers_all_attach_to_one_carrier() -> void:
	var spell: CompiledSpell = _compile(&"bolt", [&"split", &"homing", &"chain", &"pierce", &"bigger"])
	check_equal(spell.modifier_ids.size(), 5, "no cap on modifiers: all five are on the bolt")


# --- Split ------------------------------------------------------------------

func test_split_compiles_to_three_weaker_shots() -> void:
	var bare: CompiledSpell = _compile(&"bolt", [])
	var split: CompiledSpell = _compile(&"bolt", [&"split"])
	check_equal(split.shots, 3, "three shots")
	check(split.damage < bare.damage, "each shot is weaker")
	check(split.damage * split.shots > bare.damage, "but the three together are worth more than one")
	check(split.mana_cost > bare.mana_cost, "and it costs more mana")
	check(split.spread > 0.0, "the shots fan out")


func test_split_throws_a_fan_and_hits_three_targets_side_by_side() -> void:
	# The fan is 30 degrees wide, so the outer shots leave 15 degrees to each side.
	var left := _target(Vector2.from_angle(deg_to_rad(-15.0)) * 120.0)
	var middle := _target(Vector2(120.0, 0.0))
	var right := _target(Vector2.from_angle(deg_to_rad(15.0)) * 120.0)
	_cast(&"bolt", [&"split"], 0, Vector2.ZERO)
	check_equal(_mgr.get_count(), 3, "three shots in the air")
	_tick(40)
	var hit: Array = _hit_targets()
	check(hit.has(left) and hit.has(middle) and hit.has(right), "each target was hit")
	check_equal(hit.size(), 3, "once each")


func test_split_on_a_nova_has_no_shot_limit() -> void:
	var spell: CompiledSpell = _compile(&"nova", [&"split", &"split"])
	check_equal(spell.shots, _compile(&"nova", []).shots * 9, "every split multiplies: no build limit")


# --- Pierce -----------------------------------------------------------------

func test_a_bare_bolt_stops_at_the_first_target() -> void:
	var first := _target(Vector2(60.0, 0.0))
	_target(Vector2(120.0, 0.0))
	_cast(&"bolt", [], 0, Vector2.ZERO)
	_tick(40)
	check_equal(_hit_targets(), [first] as Array, "only the first target is hit")


func test_pierce_passes_through_the_targets_in_line() -> void:
	var first := _target(Vector2(60.0, 0.0))
	var second := _target(Vector2(110.0, 0.0))
	var third := _target(Vector2(160.0, 0.0))
	var fourth := _target(Vector2(210.0, 0.0))
	_cast(&"bolt", [&"pierce"], 0, Vector2.ZERO)
	_tick(60)
	var hit: Array = _hit_targets()
	check_equal(hit.size(), 3, "pierce 2 hits three targets")
	check(hit.has(first) and hit.has(second) and hit.has(third), "the first three in line")
	check(not hit.has(fourth), "not the fourth")


func test_pierce_makes_a_beam_reach_further_down_the_line() -> void:
	for n in 5:
		_target(Vector2(50.0 + 40.0 * n, 0.0))
	_cast(&"beam", [], 0, Vector2.ZERO)
	var bare: int = _hits.size()
	_hits.clear()
	_cast(&"beam", [&"pierce"], 1, Vector2.ZERO)
	check_equal(_hits.size(), bare + 2, "two more targets are hit")


# --- Homing -----------------------------------------------------------------

func test_homing_curves_toward_a_target_beside_the_aim() -> void:
	_target(Vector2(120.0, 40.0))
	_cast(&"bolt", [], 0, Vector2.ZERO)
	_tick(60)
	check_equal(_hits.size(), 0, "a bare bolt flies past a target that is not in its way")
	_spells.clear()
	_mgr.clear()
	var imp := _target(Vector2(120.0, 40.0))
	_cast(&"bolt", [&"homing"], 0, Vector2.ZERO)
	_tick(60)
	check_equal(_hit_targets(), [imp] as Array, "a homing bolt turns and hits it")


func test_homing_does_nothing_without_a_target() -> void:
	_cast(&"bolt", [&"homing"], 0, Vector2.ZERO)
	_tick(10)
	var slots: int = 0
	for slot in _mgr.get_cap():
		if _mgr.is_alive(slot):
			slots += 1
			check(_mgr.get_velocity_of(slot).normalized().is_equal_approx(Vector2.RIGHT), "the shot flies straight on")
	check_equal(slots, 1, "one shot")


func test_a_homing_beam_aims_at_a_target_near_its_line() -> void:
	var imp := _target(Vector2(150.0, 30.0))
	_cast(&"beam", [], 0, Vector2.ZERO)
	check_equal(_hits.size(), 0, "a bare beam misses it")
	_cast(&"beam", [&"homing"], 1, Vector2.ZERO)
	check_equal(_hit_targets(), [imp] as Array, "a homing beam turns toward it")


# --- Chain ------------------------------------------------------------------

func test_chain_jumps_on_to_the_nearest_other_targets() -> void:
	var first := _target(Vector2(80.0, 0.0))
	var second := _target(Vector2(80.0, 60.0))
	var third := _target(Vector2(80.0, 120.0))
	var far := _target(Vector2(80.0, 400.0))
	_cast(&"bolt", [&"chain"], 0, Vector2.ZERO)
	_tick(90)
	var hit: Array = _hit_targets()
	check_equal(hit.size(), 3, "the hit and two jumps")
	check(hit.has(first) and hit.has(second) and hit.has(third), "the three in a row")
	check(not hit.has(far), "a target out of range is left alone")


func test_a_bare_bolt_does_not_chain() -> void:
	_target(Vector2(80.0, 0.0))
	_target(Vector2(80.0, 60.0))
	_cast(&"bolt", [], 0, Vector2.ZERO)
	_tick(90)
	check_equal(_hits.size(), 1, "one hit")


func test_chain_compiles_to_two_jumps_and_stacks() -> void:
	check_equal(_compile(&"bolt", [&"chain"]).chain_jumps, 2, "two jumps")
	check_equal(_compile(&"bolt", [&"chain", &"chain", &"chain", &"chain"]).chain_jumps, 8, "four chains jump eight times: no cap")


# --- Bigger -----------------------------------------------------------------

func test_bigger_compiles_to_a_wider_slower_harder_hit() -> void:
	var bare: CompiledSpell = _compile(&"bolt", [])
	var bigger: CompiledSpell = _compile(&"bolt", [&"bigger"])
	check(bigger.radius > bare.radius, "wider")
	check(bigger.damage > bare.damage, "harder")
	check(bigger.speed < bare.speed, "slower")
	check(bigger.cooldown > bare.cooldown, "and the next cast comes later")


func test_bigger_hits_a_target_that_a_bare_bolt_misses() -> void:
	# 17 px beside the path: past a bare bolt (5 + 10), inside a bigger one (8 + 10).
	var imp := _target(Vector2(100.0, 17.0))
	_cast(&"bolt", [], 0, Vector2.ZERO)
	_tick(60)
	check_equal(_hits.size(), 0, "the bare bolt misses")
	_spells.clear()
	_mgr.clear()
	_cast(&"bolt", [&"bigger"], 0, Vector2.ZERO)
	_tick(60)
	check_equal(_hit_targets(), [imp] as Array, "the bigger bolt hits")


# --- Faster -----------------------------------------------------------------

func test_faster_compiles_to_a_quicker_shot_and_cooldown() -> void:
	var bare: CompiledSpell = _compile(&"bolt", [])
	var faster: CompiledSpell = _compile(&"bolt", [&"faster"])
	check(faster.speed > bare.speed, "quicker shot")
	check(faster.cooldown < bare.cooldown, "shorter cooldown")
	check(faster.damage < bare.damage, "but each shot is a little weaker")
	check(faster.damage / faster.cooldown > bare.damage / bare.cooldown, "and it is still worth more per second")


func test_faster_arrives_sooner() -> void:
	_target(Vector2(200.0, 0.0))
	_cast(&"bolt", [], 0, Vector2.ZERO)
	var bare: int = _steps_to_first_hit(120)
	_spells.clear()
	_mgr.clear()
	_hits.clear()
	_cast(&"bolt", [&"faster"], 0, Vector2.ZERO)
	var quick: int = _steps_to_first_hit(120)
	check(bare > 0 and quick > 0, "both arrive (%d, %d steps)" % [bare, quick])
	check(quick < bare, "the faster bolt arrives in fewer steps (%d against %d)" % [quick, bare])
