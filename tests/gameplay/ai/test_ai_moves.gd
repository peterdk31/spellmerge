extends "res://tests/support/suite.gd"
## Caster-side cards on enemies (staffs F8c, docs/milestones/M2-staffs.md, "Enemy staffs"): the
## moves an enemy's own cards ask for move it as they move a wizard: a dash from its staff tip
## over the card's time, a teleport at once and short of a wall, a pull and a swap to a point, a
## recoil back from its shot; every move says where it ended, so the card's blast
## goes off there. Moves are asked and answered under its actor id (`caster`, actors G3b); moves
## for another actor (an enemy or a wizard) are not its own. The same world as test_ai_staff.gd:
## bus, an actor table, projectiles, spells with cards built in code, combat, one wizard.
##
## godot --headless --path . --script res://tests/gameplay/ai/test_ai_moves.gd

const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const WizardScene := preload("res://content/wizard/base/wizard.tscn")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const StaffKit := preload("res://tests/support/staff_kit.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ImpData := preload("res://content/enemies/ember_imp/ember_imp.tres")

const STEP: float = 0.0625


class FakeRegistry:
	extends Node
	var items: Dictionary = {}

	func get_resource(_folder: StringName, id: StringName) -> Resource:
		return items.get(id)


var _bus: EventsScript
var _projectiles: ManagerScript
var _spells: SpellsScript
var _combat: CombatScript
var _fake: FakeRegistry
var _actors: ActorsScript
var _wizard: Actor
var _enemies: Array[Actor] = []
## Every caster_move_finished as [caster, mode, position, tag], and every blast cue as
## [caster, position, radius].
var _finished: Array = []
var _areas: Array = []


func before_each() -> void:
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_bus = own(EventsScript.new()) as EventsScript
	_projectiles = own(ManagerScript.new()) as ManagerScript
	_projectiles.events = _bus
	# The services (and the enemies, through the manager) use this table, not the autoload.
	_actors = own(ActorsScript.new()) as ActorsScript
	_projectiles.actors = _actors
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _fake
	_spells.actors = _actors
	_spells.bind(_projectiles, _bus)
	_combat = own(CombatScript.new()) as CombatScript
	_combat.events = _bus
	_combat.projectiles = _projectiles
	_combat.spells = _spells
	_combat.actors = _actors
	_combat._ready()
	_enemies.clear()
	var bolt := FormBase.new()
	bolt.base_damage = 5
	bolt.speed = 200.0
	bolt.lifetime = 1.0
	bolt.radius = 4.0
	bolt.mana_cost = 2.0
	_put(bolt, &"bolt")
	var nova := FormBase.new()
	nova.base_damage = 3
	nova.speed = 150.0
	nova.lifetime = 0.5
	nova.shots = 8
	nova.spread = 360.0
	nova.mana_cost = 2.0
	_put(nova, &"nova")
	var dash := FormBase.new()
	dash.carrier = &"dash"
	dash.ray_length = 60.0
	dash.speed = 300.0
	dash.lifetime = 0.2
	dash.mana_cost = 2.0
	_put(dash, &"dash")
	var teleport := FormBase.new()
	teleport.carrier = &"teleport"
	teleport.ray_length = 70.0
	teleport.mana_cost = 2.0
	_put(teleport, &"teleport")
	var recoil := ModifierBase.new()
	recoil.behaviour = ModifierBase.Behaviour.RECOIL
	recoil.behaviour_strength = 30.0
	_put(recoil, &"recoil")
	var blast := ModifierBase.new()
	blast.behaviour = ModifierBase.Behaviour.BLAST
	blast.behaviour_strength = 20.0
	_put(blast, &"blast")
	_finished.clear()
	_areas.clear()
	_bus.caster_move_finished.connect(func(player: int, mode: StringName, at: Vector2, tag: int) -> void: _finished.append([player, mode, at, tag]))
	_bus.cue_shown.connect(func(player: int, _cue: StringName, at: Vector2, _direction: Vector2, radius: float, _tint: Color, _look: int) -> void: _areas.append([player, at, radius]))
	# The wizard of seat 0 (actors G7: the real scene); its hurtbox registers it in Combat.
	_wizard = own(WizardScene.instantiate()) as Actor
	PlayerController.seat_wizard(_wizard, 0, null, [[], [], [], []])
	_wizard.events = _bus
	_wizard.combat = _combat
	_wizard.projectiles = _projectiles
	_wizard.spells = _spells
	_wizard.actors = _actors
	_wizard.position = Vector2(80.0, 0.0)
	root.add_child(_wizard)
	_wizard.set_physics_process(false)


func after_each() -> void:
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.free()
	_enemies.clear()
	super.after_each()


func _put(component: SpellComponent, id: StringName) -> void:
	component.id = id
	component.display_name = String(id).capitalize()
	component.complexity = 1
	_fake.items[id] = component


## Enemy data: the imp's numbers with a staff of `cards` (cast delay `delay`), `max_mana` and
## `regen` a second.
func _data(cards: Array[StringName], max_mana: float = 6.0, regen: float = 0.0, delay: float = 0.0) -> EnemyBase:
	var data: EnemyBase = ImpData.duplicate() as EnemyBase
	data.id = &"test_caster"
	data.staff = StaffKit.plain_staff(cards.size())
	data.staff.cast_delay = delay
	data.cards = cards
	data.staff.max_mana = max_mana
	data.staff.mana_regen = regen
	return data


## An enemy of `data` from the imp's scene (sprite, telegraph), in the tree at `at`.
func _enemy(data: EnemyBase, at: Vector2 = Vector2.ZERO) -> Actor:
	var enemy: Actor = ImpData.scene.instantiate()
	enemy.data = data
	enemy.events = _bus
	enemy.combat = _combat
	enemy.projectiles = _projectiles
	enemy.spells = _spells
	enemy.actors = _actors
	root.add_child(enemy)
	enemy.position = at
	_enemies.append(enemy)
	return enemy


## The enemy's AI and look (its home controller and its CreatureLook).
func _ai(enemy: Actor) -> AIController:
	return enemy.get_node("AIController") as AIController


func _look(enemy: Actor) -> CreatureLook:
	return enemy.get_node("CreatureLook") as CreatureLook


func _run(seconds: float) -> void:
	for i in int(seconds / STEP):
		for enemy in _enemies:
			if is_instance_valid(enemy):
				enemy.step(STEP)
				enemy.position += enemy.velocity * STEP
		_projectiles.step(STEP)
		_spells.step(STEP)
		_combat.step(STEP)


## Steps until the enemy is telegraphing (at most `seconds`); true if it did.
func _until_windup(enemy: Actor, seconds: float) -> bool:
	for i in int(seconds / STEP):
		if _ai(enemy).is_telegraphing():
			return true
		_run(STEP)
	return _ai(enemy).is_telegraphing()


func test_a_dash_card_dashes_the_enemy_and_its_blast_goes_off_where_it_ends() -> void:
	var enemy := _enemy(_data([&"blast", &"dash"]))
	var tag: int = _spells.current_tag(enemy.id, 0)
	check(_until_windup(enemy, 1.0), "a dash staff winds up")
	check_equal(_look(enemy).telegraph_reach(), 0.0, "with no line: a dash is not a shot")
	_run(_ai(enemy).windup_time + STEP)
	check(enemy.mover.is_moving(), "then the enemy dashes")
	_run(0.5)
	check(not enemy.mover.is_moving(), "for the card's time")
	check(is_equal_approx(enemy.position.x, 60.0), "the card's distance toward its aim (%.2f)" % enemy.position.x)
	check(_finished.size() == 1 and _finished[0][0] == enemy.id and _finished[0][1] == &"dash" and _finished[0][3] == tag, "and says where it ended, under its actor id with its tag")
	check(_areas.size() == 1 and (_areas[0][1] as Vector2).is_equal_approx(enemy.position), "the card's blast goes off there")


func test_a_teleport_jumps_at_once_and_stops_short_of_a_wall() -> void:
	var enemy := _enemy(_data([&"teleport"]))
	_run(_ai(enemy).windup_time + 2.0 * STEP)
	check(is_equal_approx(enemy.position.x, 70.0), "a teleport lands its distance along the aim (%.2f)" % enemy.position.x)
	check(_finished.size() == 1 and _finished[0][0] == enemy.id and _finished[0][1] == &"teleport", "and says where at once, under its actor id")
	_finished.clear()
	var walled := _enemy(_data([&"teleport"]), Vector2(0.0, 100.0))
	_wizard.position = Vector2(80.0, 100.0)
	_projectiles.set_walls([Rect2(40.0, 80.0, 16.0, 60.0)] as Array[Rect2])
	_run(_ai(walled).windup_time + 4.0 * STEP)
	check(walled.position.x < 40.0 - walled.mover.body_radius + 0.01, "it stops short of the wall, its body clear (%.2f)" % walled.position.x)


func test_a_recoil_pushes_the_enemy_back_from_its_shot() -> void:
	var enemy := _enemy(_data([&"recoil", &"bolt"]))
	_run(_ai(enemy).windup_time + STEP)
	_run(0.5)
	check(is_equal_approx(enemy.position.x, -30.0), "pushed the recoil's distance back from the aim (%.2f)" % enemy.position.x)


func test_pulls_and_swaps_move_the_enemy_and_others_moves_are_not_its_own() -> void:
	var enemy := _enemy(_data([&"bolt"]))
	var tag: int = _spells.current_tag(enemy.id, 0)
	_bus.caster_move_requested.emit(enemy.id, &"pull", Vector2(40.0, 20.0), 0.25, tag)
	_run(0.5)
	check(enemy.position.is_equal_approx(Vector2(40.0, 20.0)), "a pull moves it to the hit (%s)" % enemy.position)
	check(_finished.size() == 1 and _finished[0][1] == &"pull", "and says it arrived")
	_bus.caster_move_requested.emit(enemy.id, &"swap", Vector2(-40.0, -20.0), 0.1, tag)
	_run(0.25)
	check(enemy.position.is_equal_approx(Vector2.ZERO), "a swap takes it to the target's place")
	check(_finished.size() == 2 and _finished[1][1] == &"swap", "and says so too: %s" % [_finished])
	var other := _enemy(_data([&"bolt"]), Vector2(0.0, 200.0))
	var other_tag: int = _spells.current_tag(other.id, 0)
	_bus.caster_move_requested.emit(other.id, &"pull", Vector2(100.0, 0.0), 0.25, other_tag)
	_bus.caster_move_requested.emit(enemy.id, &"pull", Vector2(100.0, 0.0), 0.25, SpellTag.make(_wizard.id, 0, 0, 0))
	_run(0.5)
	check(enemy.position.is_equal_approx(Vector2.ZERO), "another enemy's move, or one with a wizard's tag, do not move it (the tag says whose move it is: the actor kit's rule)")
