extends "res://tests/support/suite.gd"
## Homing on every carrier card in the registry, so a new carrier card (or a change to one, or to the Homing
## card) cannot get it wrong unseen. `Carrier.steers` and `Carrier.homing_range` are the one
## rule: a carrier card homing steers must turn onto a target off its line anywhere it can reach (a
## bolt's flight, a beam's length), and on a carrier card it cannot steer the Homing card must be listed
## as wasted and change nothing.
##
## godot --headless --path . --script res://content/spells/modifiers/homing/test_homing_carriers.gd

const StaffKit := preload("res://tests/support/staff_kit.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")

const DT: float = 1.0 / 60.0
## How far off the aim the target stands, in degrees: well off a plain shot's line, and inside a
## homing beam's bend (SpellLimits.INSTANT_HOMING_ANGLE).
const OFF_AIM: float = 20.0
## The share of a carrier card's reach the target stands at: near its end, where a short search misses.
const FAR: float = 0.85

var _registry: Node
var _spells: SpellsScript
var _mgr: ManagerScript
var _bus: EventsScript
## Every target hit, in order.
var _hit: Array = []
## Every move asked of a wizard, as [player, mode, to].
var _moves: Array = []


func before_each() -> void:
	_registry = own(RegistryScript.new()) as Node
	_registry.call("scan")
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _registry
	_spells.bind(_mgr, _bus)
	_hit.clear()
	_moves.clear()
	_bus.projectile_hit.connect(func(_player: int, target: Node, _at: Vector2, _tag: int, _shot: int) -> void: _hit.append(target))
	_bus.caster_move_requested.connect(func(player: int, mode: StringName, to: Vector2, _seconds: float, _tag: int) -> void: _moves.append([player, mode, to]))


func _carrier_cards() -> Array[CarrierCard]:
	var carrier_cards: Array[CarrierCard] = []
	for card: Resource in _registry.call("get_all", &"spells"):
		if card is CarrierCard:
			carrier_cards.append(card as CarrierCard)
	return carrier_cards


## How far a carrier card gets: a beam, a dash or a teleport its length, a shot in flight its
## speed for its life, a rune as far as it creeps in its life, a wall a little past where it
## rises (it creeps as a rune does, rules R4 F6), a pool where it spreads and half as far again
## as it creeps in its life.
static func _reach(carrier_card: CarrierCard) -> float:
	if carrier_card.carrier == &"pool":
		return carrier_card.ray_length + SpellLimits.HOMING_DRIFT * carrier_card.lifetime * 0.5
	if carrier_card.carrier == &"rune":
		return SpellLimits.HOMING_DRIFT * carrier_card.lifetime
	if carrier_card.carrier == &"wall":
		return SpellLimits.WALL_REACH * 3.0
	return carrier_card.ray_length if carrier_card.ray_length > 0.0 else carrier_card.speed * carrier_card.lifetime


## Carrier cards that move their caster instead of hitting: their homing shows in the move asked for.
static func _moves_caster(carrier_card: CarrierCard) -> bool:
	return carrier_card.carrier == &"dash" or carrier_card.carrier == &"teleport"


## Casts `cards` for `player` from the origin to the right, runs it out, and says whether
## `target` was hit.
func _hits(player: int, cards: Array[StringName], target: Node2D, seconds: float) -> bool:
	_hit.clear()
	StaffKit.build(_spells, player, 0, cards)
	check(_spells.cast_staff(player, 0, Vector2.ZERO, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "%s is cast" % [cards])
	for i in ceili(seconds / DT):
		_mgr.step(DT)
		_spells.step(DT)
	return _hit.has(target)


func test_there_are_carrier_cards_of_both_kinds() -> void:
	var steered: int = 0
	var not_steered: int = 0
	for carrier_card in _carrier_cards():
		if Carriers.of(carrier_card.carrier).steers():
			steered += 1
		else:
			not_steered += 1
	check(steered >= 2 and not_steered >= 1, "the registry has carrier cards homing steers (%d) and carrier cards it does not (%d)" % [steered, not_steered])


func test_a_homing_carrier_card_reaches_a_target_off_its_line_near_the_end_of_its_reach() -> void:
	for carrier_card in _carrier_cards():
		if not Carriers.of(carrier_card.carrier).steers():
			continue
		before_each()
		var at: Vector2 = Vector2.from_angle(deg_to_rad(OFF_AIM)) * _reach(carrier_card) * FAR
		var target := Node2D.new()
		root.add_child(target)
		own(target)
		target.global_position = at
		_mgr.add_target(target, 8.0, ManagerScript.LAYER_ENEMY)
		var seconds: float = carrier_card.lifetime + 0.2
		if _moves_caster(carrier_card):
			_check_move(carrier_card, at)
			continue
		if not Carriers.of(carrier_card.carrier).hits():
			# A decoy hits nothing: homing makes it creep toward its target (test_decoy.gd).
			continue
		# A lone shot on its line misses it, so a hit below is the homing's doing.
		if carrier_card.shots == 1 and carrier_card.spread <= 0.0:
			check(not _hits(0, [carrier_card.id] as Array[StringName], target, seconds), "a plain %s misses a target %s px off at %s degrees" % [carrier_card.id, roundi(at.length()), OFF_AIM])
		check(_hits(1, [&"homing", carrier_card.id] as Array[StringName], target, seconds), "a homing %s turns onto a target %s px off at %s degrees" % [carrier_card.id, roundi(at.length()), OFF_AIM])


## A homing teleport is sent at the target; a homing dash hands the wizard the turn rate and
## reach it turns with as it goes (the wizard's turning is tested in test_player_caster.gd).
func _check_move(carrier_card: CarrierCard, at: Vector2) -> void:
	_moves.clear()
	_spells.set_aim(1, Vector2.ZERO, Vector2.RIGHT)
	StaffKit.build(_spells, 1, 0, [&"homing", carrier_card.id] as Array[StringName])
	check(_spells.cast_staff(1, 0, Vector2.ZERO, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "a homing %s is cast" % carrier_card.id)
	check_equal(_moves.size(), 1, "a homing %s asks for one move" % carrier_card.id)
	if _moves.size() != 1:
		return
	if carrier_card.carrier == &"teleport":
		var to: Vector2 = _moves[0][2]
		check(absf(to.angle_to(at)) < 0.01, "a homing %s blinks straight at a target %s px off at %s degrees: %s" % [carrier_card.id, roundi(at.length()), OFF_AIM, to])
	else:
		var homing: Homing = CarrierDash.of(_spells).move_homing(1)
		check(homing.homes() and homing.reach >= at.length(), "a homing %s turns the wizard toward a target %s px off (reach %s)" % [carrier_card.id, roundi(at.length()), homing.reach])


## Homing places a wall on a target near where it stands (rules R4i); its shots then keep still
## (they do not creep as a rune does), so it stays a wall.
func test_a_homing_wall_creeps_toward_its_target_as_one_piece() -> void:
	var target := Node2D.new()
	root.add_child(target)
	own(target)
	target.global_position = Vector2(70.0, 30.0)
	_mgr.add_target(target, 8.0, ManagerScript.LAYER_ENEMY)
	StaffKit.build(_spells, 1, 0, [&"homing", &"wall"] as Array[StringName])
	check(_spells.cast_staff(1, 0, Vector2.ZERO, Vector2.RIGHT, 100.0) != SpellsScript.REFUSED, "a homing wall is cast")
	var slots: Array[int] = []
	for slot in _mgr._cap:
		if _mgr.is_alive(slot):
			slots.append(slot)
	check_equal(slots.size(), 1, "the wall is one body (rules R4 F6)")
	if slots.size() != 1:
		return
	var start: Vector2 = _mgr.get_position_of(slots[0])
	check(start.is_equal_approx(Vector2(SpellLimits.WALL_REACH, 0.0)), "it rises ahead of the caster: %s" % start)
	for i in 30:
		_mgr.step(DT)
	var now: Vector2 = _mgr.get_position_of(slots[0])
	check(now.distance_to(target.global_position) < start.distance_to(target.global_position) - 8.0, "it crept toward the target: %s" % now)
	check(_mgr.clip_to_walls(now - Vector2(30.0, 0.0), now + Vector2(30.0, 0.0)) != now + Vector2(30.0, 0.0), "its wall went with it")


func test_homing_on_a_carrier_card_it_cannot_steer_is_wasted_and_changes_nothing() -> void:
	for carrier_card in _carrier_cards():
		if Carriers.of(carrier_card.carrier).steers():
			continue
		var staff: CompiledStaff = StaffKit.compile(_spells, [&"homing", carrier_card.id] as Array[StringName])
		check(staff.wasted.has(0), "homing on a %s is listed as wasted" % carrier_card.id)
		var plain: CompiledSpell = StaffKit.first(_spells, [carrier_card.id] as Array[StringName])
		var homing: CompiledSpell = StaffKit.first(_spells, [&"homing", carrier_card.id] as Array[StringName])
		check_equal(homing.homing_range, 0.0, "a %s does not home" % carrier_card.id)
		check_equal(homing.damage, plain.damage, "nor does the wasted card cut a %s's damage" % carrier_card.id)
		check_equal(homing.look, plain.look, "nor change a %s's look" % carrier_card.id)


func test_the_compiled_range_is_the_rule_for_each_carrier_card() -> void:
	var reach: float = (_registry.call("get_resource", &"spells", &"homing") as ModifierBase).behaviour_reach
	for carrier_card in _carrier_cards():
		var spell: CompiledSpell = StaffKit.first(_spells, [&"homing", carrier_card.id] as Array[StringName])
		check_equal(spell.homing_range, Carriers.of(carrier_card.carrier).homing_range(carrier_card.ray_length, reach), "a homing %s looks as far as the rule says" % carrier_card.id)
