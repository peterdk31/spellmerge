extends "res://tests/support/suite.gd"
## The Sniper card (content/spells/modifiers/sniper/, owner 2026-10-27): a modifier whose
## `spread_mult` of 0.25 makes the next carrier keep a quarter of its staff's spread. Two
## multiply; on a staff that aims true it changes nothing; it lands only on the next carrier.
##
## godot --headless --path . --script res://tests/content/spells/test_sniper.gd

const SpellsScript := preload("res://core/spells/spells.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const EventsScript := preload("res://core/events/events.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const AIM := Vector2.RIGHT
const STAFF_SPREAD: float = 40.0

var _registry: Node
var _spells: SpellsScript
var _mgr: ManagerScript


func before_each() -> void:
	_registry = own(RegistryScript.new()) as Node
	_registry.call("scan")
	var bus: EventsScript = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = bus
	# Four wizards seated 0-3 at actor ids 0-3, as the tests name their casters.
	_mgr.actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _registry
	_spells.bind(_mgr, bus)


func _staff(spread: float) -> StaffBase:
	var staff := StaffBase.new()
	staff.id = &"test"
	staff.slots = 16
	staff.cast_delay = 0.0
	staff.recharge = 0.0
	staff.spread = spread
	return staff


func _first(cards: Array[StringName], spread: float = STAFF_SPREAD) -> CompiledSpell:
	return _spells.compile_staff(cards, _staff(spread)).casts[0].group.spells[0]


## Degrees off the aim of every shot `player`'s staff 0 fires in `casts` casts on a staff of
## `spread`, by the node (carrier) that fired it. Each cast waits out the staff's delay first.
func _angles(cards: Array[StringName], spread: float, casts: int, player: int = 0) -> Dictionary:
	var compiled: CompiledStaff = _spells.compile_staff(cards, _staff(spread))
	_spells.install_staff(player, 0, compiled)
	var by_node: Dictionary = {}
	var seen: Dictionary = {}
	for n in casts:
		_spells.step(1.0)
		_spells.cast_staff(player, 0, Vector2.ZERO, AIM, 100.0)
		for slot in _mgr.get_cap():
			if not _mgr.is_alive(slot) or SpellTag.caster_of(_mgr.get_tag_of(slot)) != player:
				continue
			var key := Vector2i(slot, _mgr.get_seq_of(slot))
			if seen.has(key):
				continue
			seen[key] = true
			var node: int = SpellTag.node_of(_mgr.get_tag_of(slot))
			if not by_node.has(node):
				by_node[node] = []
			(by_node[node] as Array).append(absf(rad_to_deg(AIM.angle_to(_mgr.get_velocity_of(slot)))))
	return by_node


func test_the_card_is_a_valid_modifier() -> void:
	var card: ModifierBase = load("res://content/spells/modifiers/sniper/sniper.tres") as ModifierBase
	check(card != null, "sniper.tres loads as a ModifierBase")
	if card == null:
		return
	check_equal(card.id, &"sniper", "its id is its folder")
	check_equal(card.spread_mult, 0.25, "a quarter of the spread")
	check_equal(card.behaviour, ModifierBase.Behaviour.NONE, "numbers only")
	check(card.range_problems().is_empty(), "inside every range: %s" % [card.range_problems()])
	check(_spells.component_stats(&"sniper").has("Spread x0.25"), "the builder shows its factor: %s" % [_spells.component_stats(&"sniper")])


func test_it_quarters_the_spread_and_two_multiply() -> void:
	check_equal(_first([&"bolt"]).spread_mult, 1.0, "a plain bolt keeps the staff's spread")
	check_equal(_first([&"sniper", &"bolt"]).spread_mult, 0.25, "one sniper: a quarter")
	check_equal(_first([&"sniper", &"sniper", &"bolt"]).spread_mult, 0.0625, "two: a sixteenth")


func test_it_changes_nothing_else() -> void:
	var plain: CompiledSpell = _first([&"bolt"])
	var sharp: CompiledSpell = _first([&"sniper", &"bolt"])
	check_equal([sharp.damage, sharp.mana_cost, sharp.cooldown, sharp.speed], [plain.damage, plain.mana_cost, plain.cooldown, plain.speed], "the same numbers")


func test_its_shots_stay_inside_a_quarter_of_the_spread() -> void:
	var angles: Dictionary = _angles([&"sniper", &"bolt"], STAFF_SPREAD, 12)
	var count: int = 0
	for node: int in angles:
		for angle: float in angles[node]:
			count += 1
			check(angle <= STAFF_SPREAD * 0.25 + 0.001, "a sniper bolt leaves at most 10 degrees off (%s)" % angle)
	check_equal(count, 12, "twelve bolts")


func test_it_lands_only_on_the_next_carrier() -> void:
	# double · sniper · bolt · bolt: the first bolt is true-ish, the second keeps the full spread.
	var widest: Array[float] = [0.0, 0.0]
	var compiled: CompiledStaff = _spells.compile_staff([&"double", &"sniper", &"bolt", &"bolt"] as Array[StringName], _staff(STAFF_SPREAD))
	var nodes: Array[int] = [compiled.casts[0].group.spells[0].node, compiled.casts[0].group.spells[1].node]
	var angles: Dictionary = _angles([&"double", &"sniper", &"bolt", &"bolt"], STAFF_SPREAD, 20)
	for k in 2:
		for angle: float in angles.get(nodes[k], []):
			widest[k] = maxf(widest[k], angle)
	check(widest[0] <= STAFF_SPREAD * 0.25 + 0.001, "the sniper bolt keeps to a quarter (%s)" % widest[0])
	check(widest[1] > STAFF_SPREAD * 0.25, "twenty plain bolts go wider than that (%s)" % widest[1])


func test_on_a_staff_that_aims_true_it_does_nothing() -> void:
	var angles: Dictionary = _angles([&"sniper", &"bolt"], 0.0, 3)
	for node: int in angles:
		for angle: float in angles[node]:
			check(angle < 0.001, "along the aim (%s)" % angle)


func test_four_players_snipe_at_once() -> void:
	for player in 4:
		var angles: Dictionary = _angles([&"sniper", &"bolt"], STAFF_SPREAD, 3, player)
		for node: int in angles:
			for angle: float in angles[node]:
				check(angle <= STAFF_SPREAD * 0.25 + 0.001, "player %d's bolt keeps to a quarter (%s)" % [player, angle])
