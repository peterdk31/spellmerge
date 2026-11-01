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

const Fixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
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
	var staff: StaffBase = StaffKit.plain_staff(cards.size())
	staff.cast_delay = delay
	staff.max_mana = max_mana
	staff.mana_regen = regen
	data.staffs = [StaffCards.make(staff, cards)] as Array[StaffCards]
	return data


## An enemy of `data` from the imp's scene (sprite, telegraph), in the tree at `at`.
func _enemy(data: EnemyBase, at: Vector2 = Vector2.ZERO) -> Actor:
	var enemy: Actor = ImpData.scene.instantiate()
	enemy.data = data
	(enemy.get_node("AIController") as AIController).profile = Fixture.exact()
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


func test_it_opens_an_actor_and_owns_its_body() -> void:
	var enemy := _enemy(_data([&"bolt"]))
	check(enemy.caster != null and enemy.caster.has_staff(0), "an enemy with a staff and cards casts it")
	check(_actors.is_open(enemy.id) and enemy.id != _wizard.id, "it opened an actor of its own: %d" % enemy.id)
	check_equal(_actors.team_of(enemy.id), ActorsScript.TEAM_ENEMIES, "on the enemies' team")
	check_equal(_actors.ramp_of(enemy.id), ActorsScript.RAMP_ENEMY, "drawn in the enemy ramp")
	check_equal(_actors.seat_of(enemy.id), ActorsScript.NONE, "and driven by no seat")
	check(_actors.node_of(enemy.id) == enemy, "the actor's node is the enemy")
	check_equal(_projectiles.target_owner_of(enemy), enemy.id, "its body is its actor's, so its own spells skip it")
	check_equal(enemy.caster.mana_of(0), 6.0, "it starts with full mana")
	enemy.caster.set_mana(0, 1.0)
	_bus.mana_refund_requested.emit(_wizard.id, 0, 2.0)
	check_equal(enemy.caster.mana_of(0), 1.0, "another actor's refund is not its own")
	_bus.mana_refund_requested.emit(enemy.id, 0, 2.0)
	check_equal(enemy.caster.mana_of(0), 3.0, "siphon gives its actor mana back by the event")
	_bus.mana_refund_requested.emit(enemy.id, 0, 100.0)
	check_equal(enemy.caster.mana_of(0), 6.0, "never above its most")
	check(_spells.current_tag(enemy.id, 0) != 0, "its staff is installed")
	check(ImpData.has_staffs() and ImpData.staffs[0].cards == ([&"fire", &"bolt"] as Array[StringName]), "the ember imp casts a staff of player cards (F9)")
	var none: EnemyBase = ImpData.duplicate() as EnemyBase
	none.staffs = [] as Array[StaffCards]
	var plain := _enemy(none)
	check(plain.caster == null and plain.caster_number() == -1, "an enemy without a staff has no caster")
	check(_actors.is_open(plain.id), "but an actor id of its own all the same")


func test_it_casts_its_staff_after_the_windup_and_hits_the_wizard() -> void:
	var enemy := _enemy(_data([&"bolt"]))
	check(_until_windup(enemy, 1.0), "in reach and ready, it winds up")
	_run(_ai(enemy).windup_time + STEP)
	check_equal(_projectiles.get_count_for(enemy.id), 1, "then its bolt flies")
	check_equal(enemy.caster.mana_of(0), 4.0, "and it paid the cast's mana")
	_run(0.5)
	check(_wizard.health.health < _wizard.health.max_health, "the bolt hurt the wizard through combat")
	check_equal(_combat.health_of(enemy), ImpData.max_health, "and not the enemy that cast it")


func test_no_windup_without_the_mana_and_regen_brings_it() -> void:
	var broke := _enemy(_data([&"bolt"], 1.0, 0.0))
	check(not _until_windup(broke, 3.0), "with too little mana it never telegraphs")
	check_equal(_projectiles.get_count_for(broke.id), 0, "and never casts")
	broke.free()
	var slow := _enemy(_data([&"bolt"], 2.0, 1.0))
	_run(enemy_windup_and_cast(slow))
	check(slow.caster.mana_of(0) < 1.0, "the first cast spends it")
	check(not _until_windup(slow, 1.5), "for about two seconds it cannot afford the next")
	check(_until_windup(slow, 1.5), "then regen brings it")


## Seconds for one windup and cast of `enemy`.
func enemy_windup_and_cast(enemy: Actor) -> float:
	return _ai(enemy).windup_time + 2.0 * STEP


func test_the_windup_waits_for_the_staffs_delay() -> void:
	var enemy := _enemy(_data([&"bolt"], 100.0, 0.0, 3.0))
	_run(enemy_windup_and_cast(enemy))
	check_equal(_projectiles.get_count_for(enemy.id), 1, "the first cast")
	var seen_early: bool = false
	for i in int(4.0 / STEP):
		_run(STEP)
		if _ai(enemy).is_telegraphing() and _spells.cooldown_left(enemy.id, 0) > _ai(enemy).windup_time:
			seen_early = true
		if _ai(enemy).is_telegraphing():
			break
	check(not seen_early, "no telegraph while the delay is longer than the windup")
	check(_ai(enemy).is_telegraphing(), "it winds up once the delay will be over in time")
	_run(_ai(enemy).windup_time + STEP)
	check(_projectiles.get_count_for(enemy.id) >= 1 and enemy.caster.mana_of(0) <= 96.0, "and the promised cast comes")


func test_the_telegraph_shows_the_next_casts_reach() -> void:
	var enemy := _enemy(_data([&"bolt"]))
	_until_windup(enemy, 1.0)
	var line: Sprite2D = enemy.get_node("Telegraph") as Sprite2D
	check(line.visible, "a bolt shows its line")
	check(is_equal_approx(_look(enemy).telegraph_reach(), 200.0), "as far as the bolt flies (%.1f)" % _look(enemy).telegraph_reach())
	check(is_equal_approx(float((line.material as ShaderMaterial).get_shader_parameter(&"telegraph_lane")), 4.0 + CreatureLook.TELEGRAPH_LANE_MARGIN * 0.5), "as wide as the bolt, with a margin")
	var ring := _enemy(_data([&"nova"]), Vector2(0.0, 40.0))
	_until_windup(ring, 1.0)
	check(_ai(ring).is_telegraphing(), "a nova winds up too")
	check(not (ring.get_node("Telegraph") as Node2D).visible, "but shows no line: the pose and flash say it")


func test_one_compile_per_enemy_type_and_its_actor_closes() -> void:
	var data := _data([&"bolt"])
	var first := _enemy(data)
	var second := _enemy(data, Vector2(0.0, 30.0))
	check(first.id != second.id, "each enemy has its own actor")
	check(_spells.profile(_spells.current_tag(first.id, 0)) == _spells.profile(_spells.current_tag(second.id, 0)), "sharing one compiled staff")
	check(_actors.is_open(first.id) and _actors.is_open(second.id), "two enemy actors open")
	var id: int = first.id
	first.free()
	check(not _actors.is_open(id), "leaving the tree closes its actor")
	check_equal(_spells.current_tag(id, 0), 0, "and its caster in Spells")
	check(_actors.is_open(second.id) and _spells.current_tag(second.id, 0) != 0, "the other casts on")


## Walls (owner, 2026-11-01): in reach with an aimed cast but a wall in between, it winds up
## nothing (the shot would hit the wall) and walks round until the line is clear, then casts.
func test_it_walks_round_a_wall_instead_of_shooting_into_it() -> void:
	var enemy := _enemy(_data([&"bolt"], 100.0, 10.0), Vector2(0.0, 0.0))
	_projectiles.set_bounds(Rect2(-400.0, -400.0, 800.0, 800.0))
	_projectiles.set_walls([Rect2(32.0, -40.0, 16.0, 64.0)] as Array[Rect2])
	var eye := func() -> bool:
		return AISight.line_clear(_projectiles, enemy.global_position + enemy.body_offset, _wizard.global_position + _wizard.body_offset)
	check(not eye.call(), "the wall stands between them")
	_run(STEP * 2.0)
	check_equal(_ai(enemy).state, AIController.State.REPOSITION, "in reach but walled off: it repositions")
	var start: Vector2 = enemy.position
	var wound: bool = false
	for i in int(8.0 / STEP):
		_run(STEP)
		if _ai(enemy).is_telegraphing():
			check(eye.call(), "it only winds up with the line clear (at %s)" % enemy.position)
			wound = true
			break
	check(enemy.position.distance_to(start) > 4.0, "it walked")
	check(wound, "round the wall, it winds up (at %s)" % enemy.position)


func test_a_cast_that_is_not_aimed_ignores_walls() -> void:
	var enemy := _enemy(_data([&"nova"], 100.0, 10.0), Vector2(0.0, 0.0))
	_projectiles.set_bounds(Rect2(-400.0, -400.0, 800.0, 800.0))
	_projectiles.set_walls([Rect2(32.0, -40.0, 16.0, 64.0)] as Array[Rect2])
	check(_until_windup(enemy, 1.0), "a nova winds up behind the wall as before")


## A minion (owner, 2026-11-01: an idea for a card, not built yet): an enemy handed to an AI of the
## players' team (`Actor.drive`) fights for them with no other code. Its team is its driver's, so
## it targets the other enemies (never the wizard), casts its own staff at them through the same
## states, walls included; `release` gives it back to its own AI, an enemy again.
func test_an_enemy_driven_by_an_ai_of_the_players_team_is_a_minion() -> void:
	_wizard.position = Vector2(-80.0, 0.0)
	var minion := _enemy(_data([&"bolt"], 100.0, 10.0), Vector2(0.0, 0.0))
	var foe := _enemy(_data([&"bolt"], 0.0, 0.0), Vector2(70.0, 0.0))
	var mind := AIController.new()
	mind.team = ActorsScript.TEAM_WIZARDS
	minion.add_child(mind)
	minion.drive(mind)
	check_equal(minion.team(), ActorsScript.TEAM_WIZARDS, "its team is its new driver's")
	check_equal(_actors.team_of(minion.id), ActorsScript.TEAM_WIZARDS, "and the actor table knows it")
	for i in int(1.0 / STEP):
		if mind.is_telegraphing():
			break
		_run(STEP)
	check(mind.is_telegraphing(), "it winds up")
	check(mind.target == foe, "at the other enemy, not the wizard")
	_run(mind.windup_time + 0.5)
	check(_combat.health_of(foe) < ImpData.max_health, "its own staff hurt the enemy")
	minion.release()
	check_equal(minion.team(), ActorsScript.TEAM_ENEMIES, "released, it is an enemy again")
