extends "res://tests/support/suite.gd"
## Hits of part of a point (an atom's speck): the card's damage is kept as it is when compiled, and
## health is decimal (owner, 2026-10-30), so a 0.25 speck takes 0.25 health and says so in every
## event: `hit_landed`, `damage_dealt`.

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
	_bus.damage_dealt.connect(func(_player: int, target: Node, amount: float, _at: Vector2) -> void: _damage.append([target, amount]))
	_bus.hit_landed.connect(func(_player: int, target: Node, _amount: float, _at: Vector2, _kind: StringName, _shot: int) -> void: _landed.append(target))
	_bus.status_applied.connect(func(_player: int, _target: Node, id: StringName) -> void: _applied.append(id))
	var speck := FormBase.new()
	speck.id = &"speck"
	speck.base_damage = 0.25
	speck.speed = 600.0
	speck.lifetime = 0.5
	_fake.items[&"speck"] = speck
	_fake.items[&"fire"] = load("res://content/spells/elements/fire/fire.tres")


func _enemy(at: Vector2, health: float = 10.0) -> Node2D:
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


func test_a_card_below_a_point_keeps_its_damage() -> void:
	var spell: CompiledSpell = StaffKit.first(_spells, StaffKit.cards({"form": &"speck"}))
	check_equal(spell.damage, 0.25, "not rounded up to a point")
	check_equal(spell.hit.damage, 0.25, "its hit too")


func test_a_speck_takes_its_share_of_health() -> void:
	var enemy: Node2D = _enemy(Vector2(100.0, 0.0))
	var tag: int = _tag({"form": &"speck"})
	_hit(enemy, tag)
	check(is_equal_approx(_combat.health_of(enemy), 9.75), "a quarter of a point gone (%s)" % _combat.health_of(enemy))
	check_equal(_landed.size(), 1, "it landed")
	check_equal(_damage.size(), 1, "and its damage was told")
	check(is_equal_approx(float(_damage[0][1]), 0.25), "as 0.25 (%s)" % str(_damage[0][1]))
	for i in 11:
		_hit(enemy, tag)
	check(is_equal_approx(_combat.health_of(enemy), 7.0), "twelve specks are three points (%s)" % _combat.health_of(enemy))


func test_specks_kill_at_last() -> void:
	var enemy: Node2D = _enemy(Vector2(100.0, 0.0), 1)
	var tag: int = _tag({"form": &"speck"})
	for i in 3:
		_hit(enemy, tag)
	check(_combat.is_registered(enemy), "three quarters: it stands")
	_hit(enemy, tag)
	check(not _combat.is_registered(enemy), "the fourth speck kills it, with no crumb of health left")


func test_a_target_of_a_hundredth_of_a_point_dies_of_any_hit() -> void:
	var enemy: Node2D = _enemy(Vector2(100.0, 0.0))
	_combat.unregister_actor(enemy)
	_combat.register_actor(enemy, 0.01, 10.0)
	_hit(enemy, _tag({"form": &"speck"}))
	check(not _combat.is_registered(enemy), "a speck kills it")


func test_a_speck_puts_its_status_on() -> void:
	var enemy: Node2D = _enemy(Vector2(100.0, 0.0), 100)
	_hit(enemy, _tag({"form": &"speck", "element": &"fire"}))
	check(_applied.has(&"burn"), "it burns")
