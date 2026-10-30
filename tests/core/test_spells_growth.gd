extends "res://tests/support/suite.gd"
## Growth is size only (owner, 2026-10-27): a grown shot hits wider, as its radius is its hit
## circle, and for its card's damage, however much it grew; damage boosts are overcharge's. Real
## manager and event bus, cards built in code.
##
## godot --headless --path . --script res://tests/core/test_spells_growth.gd

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
## The damage of every hit's profile, read as combat reads it.
var _damage: Array[int] = []


func before_each() -> void:
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_bus = own(EventsScript.new()) as EventsScript
	_mgr = own(ManagerScript.new()) as ManagerScript
	_mgr.events = _bus
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _fake
	_spells.bind(_mgr, _bus)
	_damage.clear()
	_bus.projectile_hit.connect(func(_player: int, _target: Node, _at: Vector2, tag: int, _shot: int) -> void:
		var profile: HitProfile = _spells.hit_profile(tag)
		_damage.append(profile.damage if profile != null else -1))
	var bolt := FormBase.new()
	bolt.base_damage = 10
	bolt.speed = 100.0
	bolt.lifetime = 3.0
	bolt.radius = 4.0
	_put(bolt, &"bolt")
	var growth := ModifierBase.new()
	growth.behaviour = ModifierBase.Behaviour.GROWTH
	growth.behaviour_strength = 2.0
	_put(growth, &"growth")


func _put(component: SpellComponent, id: StringName) -> void:
	component.id = id
	component.display_name = String(id).capitalize()
	component.complexity = 1
	_fake.items[id] = component


## The damage of the first hit of `cards` on a target `distance` px ahead and `off` px off the
## line, or -1 for none.
func _first_hit(cards: Array[StringName], distance: float, off: float = 0.0) -> int:
	var target := Node2D.new()
	root.add_child(target)
	own(target)
	target.global_position = Vector2(distance, off)
	_mgr.add_target(target, 6.0, ManagerScript.LAYER_ENEMY, EventsScript.NO_PLAYER)
	StaffKit.build(_spells, 0, 0, cards)
	_spells.cast_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, 100.0)
	for i in 240:
		_mgr.step(DT)
		_spells.step(DT)
		if not _damage.is_empty():
			break
	return _damage[0] if not _damage.is_empty() else -1


func test_a_grown_shot_hits_for_its_damage() -> void:
	check_equal(_first_hit([&"bolt"], 100.0), 10, "a plain bolt")
	before_each()
	check_equal(_first_hit([&"growth", &"bolt"], 200.0), 10, "a bolt that has grown for two seconds: the same damage")


func test_a_grown_shot_hits_wider() -> void:
	# 20 px off the line, out of a plain bolt's reach (4 + 6 px), inside a bolt grown x4 (16 + 6).
	check_equal(_first_hit([&"bolt"], 250.0, 20.0), -1, "a plain bolt flies past")
	before_each()
	check_equal(_first_hit([&"growth", &"bolt"], 250.0, 20.0), 10, "a grown one catches it, for its damage")
