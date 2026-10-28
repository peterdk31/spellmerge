extends "res://tests/support/suite.gd"
## Enemies that cast staffs (staffs F8a, docs/milestones/M2-staffs.md, "Enemy staffs"): an enemy
## whose data has a staff and cards opens an actor (the enemies' team and ramp, no seat; actors
## G3b) and its caster in Spells, owns its body there, casts its staff after the windup, pays mana
## and gets it back (siphon's `mana_refund_requested` for its actor), winds up only when the next
## cast is ready (so a telegraph always comes true), shows the next cast's reach, compiles its
## staff once per enemy type, and closes its actor when it leaves. A world of its own (bus, an
## actor table, projectiles, spells with cards built in code, combat, one wizard), stepped by hand.
##
## godot --headless --path . --script res://tests/gameplay/ai/test_ai_staff.gd

const AiScript := preload("res://gameplay/ai/ai.gd")
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
var _enemies: Array[AiScript] = []


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
	_spells.bind(_projectiles, _bus)
	_combat = own(CombatScript.new()) as CombatScript
	_combat.events = _bus
	_combat.projectiles = _projectiles
	_combat.spells = _spells
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
	data.max_mana = max_mana
	data.mana_regen = regen
	return data


## An enemy of `data` from the imp's scene (sprite, telegraph), in the tree at `at`.
func _enemy(data: EnemyBase, at: Vector2 = Vector2.ZERO) -> AiScript:
	var enemy: AiScript = ImpData.scene.instantiate()
	enemy.data = data
	enemy.events = _bus
	enemy.combat = _combat
	enemy.projectiles = _projectiles
	enemy.spells = _spells
	enemy.targets.append(_wizard)
	root.add_child(enemy)
	enemy.position = at
	_enemies.append(enemy)
	return enemy


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
func _until_windup(enemy: AiScript, seconds: float) -> bool:
	for i in int(seconds / STEP):
		if enemy.is_telegraphing():
			return true
		_run(STEP)
	return enemy.is_telegraphing()


func test_it_opens_an_actor_and_owns_its_body() -> void:
	var enemy := _enemy(_data([&"bolt"]))
	check(enemy.uses_staff(), "an enemy with a staff and cards casts it")
	check(_actors.is_open(enemy.caster) and enemy.caster != _wizard.id, "it opened an actor of its own: %d" % enemy.caster)
	check_equal(_actors.team_of(enemy.caster), ActorsScript.TEAM_ENEMIES, "on the enemies' team")
	check_equal(_actors.ramp_of(enemy.caster), ActorsScript.RAMP_ENEMY, "drawn in the enemy ramp")
	check_equal(_actors.seat_of(enemy.caster), ActorsScript.NONE, "and driven by no seat")
	check(_actors.node_of(enemy.caster) == enemy, "the actor's node is the enemy")
	check_equal(_projectiles.target_owner_of(enemy), enemy.caster, "its body is its actor's, so its own spells skip it")
	check_equal(enemy.mana, 6.0, "it starts with full mana")
	enemy.mana = 1.0
	_bus.mana_refund_requested.emit(_wizard.id, 2.0)
	check_equal(enemy.mana, 1.0, "another actor's refund is not its own")
	_bus.mana_refund_requested.emit(enemy.caster, 2.0)
	check_equal(enemy.mana, 3.0, "siphon gives its actor mana back by the event")
	_bus.mana_refund_requested.emit(enemy.caster, 100.0)
	check_equal(enemy.mana, 6.0, "never above its most")
	check(_spells.current_tag(enemy.caster, 0) != 0, "its staff is installed")
	check(ImpData.staff != null and ImpData.cards == ([&"fire", &"bolt"] as Array[StringName]), "the ember imp casts a staff of player cards (F9)")
	var none: EnemyBase = ImpData.duplicate() as EnemyBase
	none.staff = null
	none.cards = []
	var plain := _enemy(none)
	check(not plain.uses_staff() and plain.caster == -1, "an enemy without a staff keeps its old attack")


func test_it_casts_its_staff_after_the_windup_and_hits_the_wizard() -> void:
	var enemy := _enemy(_data([&"bolt"]))
	check(_until_windup(enemy, 1.0), "in reach and ready, it winds up")
	_run(enemy.windup_time + STEP)
	check_equal(_projectiles.get_count_for(enemy.caster), 1, "then its bolt flies")
	check_equal(enemy.mana, 4.0, "and it paid the cast's mana")
	_run(0.5)
	check(_wizard.health.health < _wizard.health.max_health, "the bolt hurt the wizard through combat")
	check_equal(_combat.get_health(enemy), ImpData.max_health, "and not the enemy that cast it")


func test_no_windup_without_the_mana_and_regen_brings_it() -> void:
	var broke := _enemy(_data([&"bolt"], 1.0, 0.0))
	check(not _until_windup(broke, 3.0), "with too little mana it never telegraphs")
	check_equal(_projectiles.get_count_for(broke.caster), 0, "and never casts")
	broke.free()
	var slow := _enemy(_data([&"bolt"], 2.0, 1.0))
	_run(enemy_windup_and_cast(slow))
	check(slow.mana < 1.0, "the first cast spends it")
	check(not _until_windup(slow, 1.5), "for about two seconds it cannot afford the next")
	check(_until_windup(slow, 1.5), "then regen brings it")


## Seconds for one windup and cast of `enemy`.
func enemy_windup_and_cast(enemy: AiScript) -> float:
	return enemy.windup_time + 2.0 * STEP


func test_the_windup_waits_for_the_staffs_delay() -> void:
	var enemy := _enemy(_data([&"bolt"], 100.0, 0.0, 3.0))
	_run(enemy_windup_and_cast(enemy))
	check_equal(_projectiles.get_count_for(enemy.caster), 1, "the first cast")
	var seen_early: bool = false
	for i in int(4.0 / STEP):
		_run(STEP)
		if enemy.is_telegraphing() and _spells.cooldown_left(enemy.caster, 0) > enemy.windup_time:
			seen_early = true
		if enemy.is_telegraphing():
			break
	check(not seen_early, "no telegraph while the delay is longer than the windup")
	check(enemy.is_telegraphing(), "it winds up once the delay will be over in time")
	_run(enemy.windup_time + STEP)
	check(_projectiles.get_count_for(enemy.caster) >= 1 and enemy.mana <= 96.0, "and the promised cast comes")


func test_the_telegraph_shows_the_next_casts_reach() -> void:
	var enemy := _enemy(_data([&"bolt"]))
	_until_windup(enemy, 1.0)
	var line: Sprite2D = enemy.get_node("Telegraph") as Sprite2D
	check(line.visible, "a bolt shows its line")
	check(is_equal_approx(enemy.telegraph_reach(), 200.0), "as far as the bolt flies (%.1f)" % enemy.telegraph_reach())
	check(is_equal_approx(float((line.material as ShaderMaterial).get_shader_parameter(&"telegraph_lane")), 4.0 + AiScript.TELEGRAPH_LANE_MARGIN * 0.5), "as wide as the bolt, with a margin")
	var ring := _enemy(_data([&"nova"]), Vector2(0.0, 40.0))
	_until_windup(ring, 1.0)
	check(ring.is_telegraphing(), "a nova winds up too")
	check(not (ring.get_node("Telegraph") as Node2D).visible, "but shows no line: the pose and flash say it")


func test_one_compile_per_enemy_type_and_its_actor_closes() -> void:
	var data := _data([&"bolt"])
	var first := _enemy(data)
	var second := _enemy(data, Vector2(0.0, 30.0))
	check(first.caster != second.caster, "each enemy has its own actor")
	check(_spells.profile(_spells.current_tag(first.caster, 0)) == _spells.profile(_spells.current_tag(second.caster, 0)), "sharing one compiled staff")
	check(_actors.is_open(first.caster) and _actors.is_open(second.caster), "two enemy actors open")
	var id: int = first.caster
	first.free()
	check(not _actors.is_open(id), "leaving the tree closes its actor")
	check_equal(_spells.current_tag(id, 0), 0, "and its caster in Spells")
	check(_actors.is_open(second.caster) and _spells.current_tag(second.caster, 0) != 0, "the other casts on")
