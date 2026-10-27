extends "res://tests/support/suite.gd"
## Growth hits harder (owner design, M2-staffs.md: "Grows and gets stronger the further it
## flies"): `Spells.hit_profile` scales a grown shot's damage by how much it grew
## (`Projectiles.get_growth_of`), with no allocation per hit. Real manager and event bus, cards
## built in code.
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
	_bus.projectile_hit.connect(func(_player: int, _target: Node, _at: Vector2, tag: int) -> void:
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


## The damage of the first hit of `cards` on a target `distance` px ahead.
func _first_hit(cards: Array[StringName], distance: float) -> int:
	var target := Node2D.new()
	root.add_child(target)
	own(target)
	target.global_position = Vector2(distance, 0.0)
	_mgr.add_target(target, 6.0, ManagerScript.LAYER_ENEMY, EventsScript.NO_PLAYER)
	StaffKit.build(_spells, 0, 0, cards)
	_spells.cast_staff(0, 0, Vector2.ZERO, Vector2.RIGHT, 100.0)
	for i in 240:
		_mgr.step(DT)
		_spells.step(DT)
		if not _damage.is_empty():
			break
	return _damage[0] if not _damage.is_empty() else -1


func test_a_plain_shot_hits_for_its_damage() -> void:
	check_equal(_first_hit([&"bolt"], 100.0), 10, "no growth, no change")


func test_a_grown_shot_hits_harder_the_further_it_flew() -> void:
	# x2 a second: after about a second of flight it is about twice as big and hits for about 20.
	var near: int = _first_hit([&"growth", &"bolt"], 30.0)
	before_each()
	var far: int = _first_hit([&"growth", &"bolt"], 110.0)
	check(near > 10 and near < 15, "close, it has grown a little (%d)" % near)
	check(far >= 18 and far <= 24, "after about a second, about twice (%d)" % far)


func test_growth_is_capped() -> void:
	# GROWTH_MAX (4) times at most, however far it flies.
	var far: int = _first_hit([&"growth", &"bolt"], 290.0)
	check(far <= roundi(10 * ManagerScript.GROWTH_MAX), "at most %s times (%d)" % [ManagerScript.GROWTH_MAX, far])
	check(far >= 30, "and it got there (%d)" % far)
