extends "res://tests/support/suite.gd"
## Hits below a whole point (an atom's speck): the card's damage is kept as it is when compiled,
## and combat keeps what each target is owed, taking a whole point once it adds up. A speck that
## takes none yet still lands: its status goes on and `hit_landed` is sent, but no `damage_dealt`.

const StaffKit := preload("res://tests/support/staff_kit.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const STEP: float = 0.0625


class FakeRegistry:
	extends Node
	var items: Dictionary = {}

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)


var _bus: EventsScript
var _projectiles: ManagerScript
var _combat: CombatScript
var _spells: SpellsScript
var _actors: ActorSeats.ActorsScript
var _fake: FakeRegistry
## Each damage_dealt as [target, amount], each hit_landed's target, each status_applied's id.
var _damage: Array = []
var _landed: Array = []
var _applied: Array[StringName] = []


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_projectiles = own(ManagerScript.new()) as ManagerScript
	_projectiles.events = _bus
	_actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	_projectiles.actors = _actors
	_combat = own(CombatScript.new()) as CombatScript
	_combat.events = _bus
	_combat.projectiles = _projectiles
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _fake
	_spells.bind(_projectiles, _bus)
	_combat.spells = _spells
	_combat._ready()
	_damage.clear()
	_landed.clear()
	_applied.clear()
	_bus.damage_dealt.connect(func(_player: int, target: Node, amount: int, _at: Vector2) -> void: _damage.append([target, amount]))
	_bus.hit_landed.connect(func(_player: int, target: Node, _amount: int, _at: Vector2, _kind: StringName, _shot: int) -> void: _landed.append(target))
	_bus.status_applied.connect(func(_player: int, _target: Node, id: StringName) -> void: _applied.append(id))
	var speck := FormBase.new()
	speck.id = &"speck"
	speck.base_damage = 0.25
	speck.speed = 600.0
	speck.lifetime = 0.5
	_fake.items[&"speck"] = speck
	_fake.items[&"fire"] = load("res://content/spells/elements/fire/fire.tres")


func _enemy(at: Vector2, health: int = 10) -> Node2D:
	var enemy := own(Node2D.new()) as Node2D
	enemy.position = at
	root.add_child(enemy)
	_combat.register_actor(enemy, health, 10.0)
	return enemy


func _tag(cards: Dictionary) -> int:
	return StaffKit.build(_spells, 0, 0, StaffKit.cards(cards))


func _hit(enemy: Node2D, tag: int) -> void:
	_projectiles.step(STEP)
	_bus.projectile_hit.emit(0, enemy, enemy.position + Vector2(-8.0, 0.0), tag, -1)


func _dealt_to(enemy: Node2D) -> int:
	var total: int = 0
	for row: Array in _damage:
		if row[0] == enemy:
			total += row[1] as int
	return total


func test_a_card_below_a_point_keeps_its_damage() -> void:
	var spell: CompiledSpell = StaffKit.first(_spells, StaffKit.cards({"form": &"speck"}))
	check_equal(spell.damage, 0.25, "not rounded up to a point")
	check_equal(spell.hit.damage, 0.25, "its hit too")


func test_four_quarter_specks_take_one_point() -> void:
	var enemy: Node2D = _enemy(Vector2(100.0, 0.0))
	var tag: int = _tag({"form": &"speck"})
	for i in 3:
		_hit(enemy, tag)
	check_equal(_combat.health_of(enemy), 10, "three quarters owed, no point yet")
	check_equal(_landed.size(), 3, "but every speck landed")
	check_equal(_damage.size(), 0, "and no damage was announced")
	_hit(enemy, tag)
	check_equal(_combat.health_of(enemy), 9, "the fourth makes a point")
	check_equal(_dealt_to(enemy), 1, "announced once, as a whole point")
	for i in 8:
		_hit(enemy, tag)
	check_equal(_combat.health_of(enemy), 7, "twelve specks are three points")


func test_what_is_owed_is_each_targets_own() -> void:
	var first: Node2D = _enemy(Vector2(100.0, 0.0))
	var second: Node2D = _enemy(Vector2(100.0, 100.0))
	var tag: int = _tag({"form": &"speck"})
	for i in 2:
		_hit(first, tag)
		_hit(second, tag)
	check_equal(_combat.health_of(first), 10, "half a point owed to the first")
	check_equal(_combat.health_of(second), 10, "and its own half to the second")
	_hit(first, tag)
	_hit(first, tag)
	check_equal(_combat.health_of(first), 9, "the first's specks add up on the first")
	check_equal(_combat.health_of(second), 10, "and never on the second")


func test_a_speck_with_no_point_yet_still_puts_its_status_on() -> void:
	var enemy: Node2D = _enemy(Vector2(100.0, 0.0), 100)
	_hit(enemy, _tag({"form": &"speck", "element": &"fire"}))
	check_equal(_combat.health_of(enemy), 100, "no point yet")
	check(_applied.has(&"burn"), "it burns all the same")
