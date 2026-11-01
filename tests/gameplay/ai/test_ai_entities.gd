extends "res://tests/support/suite.gd"
## Decoys and familiars for enemies (staffs F8d, docs/milestones/M2-staffs.md, "Enemy staffs"):
## an enemy's decoy copies the enemy, is a target every shot but its enemy's hits and wears down,
## and enemies never chase it; an enemy's familiar circles the enemy and casts what its triggers
## give it (rules R4 F3), in the enemy's own spell; each enemy keeps PER_ENEMY of a kind, enemies share rows of their own
## so a crowd never takes a wizard's, and an enemy's entities end with it. Every entity is its
## owner's actor id (actors G3b): the enemy's `caster`, the wizard's `id`, and whether a seat
## drives the owner sorts it into the seats' rows or the others'. The same world as
## test_ai_moves.gd (with its actor table), plus Entities.
##
## godot --headless --path . --script res://tests/gameplay/ai/test_ai_entities.gd

const CombatScript := preload("res://gameplay/combat/combat.gd")
const EntitiesScript := preload("res://gameplay/ai/entities.gd")
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
var _entities: EntitiesScript
var _fake: FakeRegistry
var _actors: ActorsScript
var _wizard: Actor
var _enemies: Array[Actor] = []
## Every entity_ended as [caster, kind, tag].
var _ended: Array = []


func before_each() -> void:
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_bus = own(EventsScript.new()) as EventsScript
	_projectiles = own(ManagerScript.new()) as ManagerScript
	_projectiles.events = _bus
	# The services (and the enemies and Entities, through the manager) use this table.
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
	_entities = own(EntitiesScript.new()) as EntitiesScript
	_entities.events = _bus
	_entities.projectiles = _projectiles
	_entities.spells = _spells
	root.add_child(_entities)
	_enemies.clear()
	var bolt := FormBase.new()
	bolt.base_damage = 5
	bolt.speed = 200.0
	bolt.lifetime = 1.0
	bolt.radius = 4.0
	bolt.mana_cost = 2.0
	_put(bolt, &"bolt")
	var familiar := FormBase.new()
	familiar.carrier = &"familiar"
	familiar.lifetime = 6.0
	familiar.mana_cost = 2.0
	_put(familiar, &"familiar")
	var timer := TriggerBase.new()
	timer.event = TriggerBase.Event.TIMER
	timer.interval = 0.25
	_put(timer, &"timer")
	var decoy := FormBase.new()
	decoy.carrier = &"decoy"
	decoy.lifetime = 4.0
	decoy.mana_cost = 2.0
	_put(decoy, &"decoy")
	_ended.clear()
	_bus.entity_ended.connect(func(player: int, kind: StringName, _at: Vector2, tag: int) -> void: _ended.append([player, kind, tag]))
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


## Enemy data: the imp's numbers with a staff of `cards` and plenty of mana.
func _data(cards: Array[StringName]) -> EnemyBase:
	var data: EnemyBase = ImpData.duplicate() as EnemyBase
	data.id = &"test_caster"
	var staff: StaffBase = StaffKit.plain_staff(cards.size())
	staff.cast_delay = 0.0
	staff.max_mana = 20.0
	staff.mana_regen = 0.0
	data.staffs = [StaffCards.make(staff, cards)] as Array[StaffCards]
	return data


## An enemy of `data` from the imp's scene (its Sprite), in the tree at `at`.
func _enemy(data: EnemyBase, at: Vector2 = Vector2.ZERO) -> Actor:
	var enemy: Actor = ImpData.scene.instantiate()
	enemy.data = data
	enemy.events = _bus
	enemy.combat = _combat
	enemy.projectiles = _projectiles
	enemy.spells = _spells
	enemy.actors = _actors
	_ai(enemy).entities = _entities
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
		_projectiles.step(STEP)
		_spells.step(STEP)
		_combat.step(STEP)
		_entities.step(STEP)


func test_an_enemys_decoy_copies_it_and_every_hit_wears_it_down() -> void:
	var enemy := _enemy(_data([&"decoy"]))
	var tag: int = _spells.current_tag(enemy.id, 0)
	_run(_ai(enemy).windup_time + 2.0 * STEP)
	check_equal(_entities.count_owned(EntitiesScript.DECOY, enemy.id), 1, "its decoy card makes one decoy, the enemy's")
	check_equal(_entities.count(EntitiesScript.DECOY, _wizard.id), 0, "not the wizard's")
	var at: Vector2 = _entities.positions_of(enemy.id, tag)[0]
	var decoy: Node2D = _projectiles.nearest_target(at, 16.0, ManagerScript.LAYER_ENEMY, enemy)
	check(decoy is EntitiesScript.Decoy, "a target on the enemies' layer, where wizards' shots and homing look")
	check(_projectiles.nearest_target(at, 16.0, ManagerScript.LAYER_PLAYER, _wizard) == null, "and not on the wizards' layer")
	var copied: Sprite2D = (decoy as EntitiesScript.Decoy).sprite
	var fresh: Node = ImpData.scene.instantiate()
	var looks: Array = [(fresh.get_node("Sprite") as Sprite2D).texture, _look(enemy).windup_texture, _look(enemy).hurt_texture]
	fresh.free()
	check(copied.texture != null and looks.has(copied.texture), "it copies the enemy's sprite")
	check(_entities.lure(at) == null, "enemies never chase an enemy's decoy")
	# Another enemy's shot wears it too (its own enemy's never reach it: core/projectiles).
	var other_enemy: int = _actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	_bus.projectile_hit.emit(other_enemy, decoy, at, SpellTag.make(other_enemy, 0, 0, 0), -1)
	var wizard_tag: int = SpellTag.make(_wizard.id, 0, 0, 0)
	for i in EntitiesScript.DECOY_HITS - 2:
		_bus.projectile_hit.emit(_wizard.id, decoy, at, wizard_tag, -1)
	check_equal(_entities.count_owned(EntitiesScript.DECOY, enemy.id), 1, "it holds until its last hit")
	_bus.projectile_hit.emit(_wizard.id, decoy, at, wizard_tag, -1)
	check_equal(_entities.count_owned(EntitiesScript.DECOY, enemy.id), 0, "DECOY_HITS hits break it, an enemy's among them")
	check(_ended.size() == 1 and _ended[0][0] == enemy.id and _ended[0][1] == EntitiesScript.DECOY and _ended[0][2] == tag, "and its end is said under the enemy's actor id with its tag")


func test_an_enemys_familiar_circles_it_and_its_timer_casts_the_enemys_spell() -> void:
	var enemy := _enemy(_data([&"timer", &"familiar", &"bolt"]))
	var tag: int = _spells.current_tag(enemy.id, 0)
	_run(_ai(enemy).windup_time + 2.0 * STEP)
	check_equal(_entities.count_owned(EntitiesScript.FAMILIAR, enemy.id), 1, "its familiar card makes one familiar")
	_run(0.25)
	var at: Vector2 = _entities.positions_of(enemy.id, tag)[0]
	var centre: Vector2 = enemy.global_position + EntitiesScript.FAMILIAR_CENTRE
	check(is_equal_approx(at.distance_to(centre), EntitiesScript.FAMILIAR_ORBIT), "it circles the enemy (%.2f from it)" % at.distance_to(centre))
	var casters: Array[int] = []
	for i in 12:
		_run(STEP)
		for slot in _projectiles.get_cap():
			if _projectiles.is_alive(slot):
				casters.append(SpellTag.caster_of(_projectiles.get_tag_of(slot)))
	check(not casters.is_empty(), "its timer casts the enemy's spell (its bolt)")
	check(casters.all(func(caster: int) -> bool: return caster == enemy.id), "as the enemy's")
	check_equal(_entities.drawn_familiars(), 1, "drawn with the others")


func test_a_familiar_casts_from_its_orb_outward_like_a_sprinkler() -> void:
	# Rules R4 F8: what a familiar's timer casts comes from its orb, outward from what it circles,
	# so as it circles its bolts go round.
	var enemy := _enemy(_data([&"timer", &"familiar", &"bolt"]))
	var tag: int = _spells.current_tag(enemy.id, 0)
	_run(_ai(enemy).windup_time + 2.0 * STEP)
	var centre: Vector2 = enemy.global_position + EntitiesScript.FAMILIAR_CENTRE
	var ways: Array[Vector2] = []
	for i in 24:
		var orb: Vector2 = _entities.positions_of(enemy.id, tag)[0]
		_run(STEP)
		for slot in _projectiles.get_cap():
			if _projectiles.is_alive(slot) and _projectiles.get_position_of(slot).distance_to(orb) < 0.5:
				ways.append(_projectiles.get_velocity_of(slot).normalized())
				check(ways[-1].dot((orb - centre).normalized()) > 0.95, "the bolt flies outward from the enemy through the orb")
	check(ways.size() >= 2, "its bolts start at the orb (%d of them)" % ways.size())
	check(ways.size() >= 2 and ways[0].angle_to(ways[1]) > 0.1, "and each goes another way as the orb circles")


func test_an_enemys_familiar_without_a_trigger_casts_nothing() -> void:
	var enemy := _enemy(_data([&"familiar"]))
	_run(_ai(enemy).windup_time + 2.0 * STEP)
	check_equal(_entities.count_owned(EntitiesScript.FAMILIAR, enemy.id), 1, "its familiar card makes one familiar")
	var peak: int = 0
	for i in 24:
		_run(STEP)
		peak = maxi(peak, _projectiles.get_count())
	check_equal(peak, 0, "with no trigger it casts nothing (no payload of its own, rules R4 F3)")


func test_an_enemys_entities_end_with_it() -> void:
	var enemy := _enemy(_data([&"familiar", &"bolt"]))
	var tag: int = _spells.current_tag(enemy.id, 0)
	var caster: int = enemy.id
	_run(_ai(enemy).windup_time + 2.0 * STEP)
	check_equal(_entities.count_owned(EntitiesScript.FAMILIAR, caster), 1, "a familiar is live")
	# Leaving the tree (dying, a new room) ends them.
	root.remove_child(enemy)
	check_equal(_entities.count_owned(EntitiesScript.FAMILIAR, caster), 0, "the enemy gone, its familiar ends")
	check(_ended.size() == 1 and _ended[0][0] == caster and _ended[0][2] == tag, "with entity_ended, so its end still counts")


func test_enemies_keep_their_share_and_never_take_a_wizards_rows() -> void:
	# Seats 1-3 join the wizard of seat 0; the enemies are unseated actors of the same table.
	var seated: Array[int] = [_wizard.id]
	for seat in range(1, EntitiesScript.PLAYER_SLOTS):
		seated.append(_actors.open(ActorsScript.TEAM_WIZARDS, seat, seat))
	var first: int = _actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	var tag: int = SpellTag.make(first, 0, 0, 1)
	for i in EntitiesScript.PER_ENEMY + 1:
		_bus.entity_spawn_requested.emit(first, EntitiesScript.DECOY, Vector2(i * 10.0, 0.0), 5.0, tag, EntitiesScript.CASTER_POINT)
	check_equal(_entities.count_owned(EntitiesScript.DECOY, first), EntitiesScript.PER_ENEMY, "one enemy keeps PER_ENEMY of a kind; one more ends its oldest")
	check_equal(_ended.size(), 1, "and that end is said")
	for row in EntitiesScript.ENEMY_ROWS + 4:
		var other: int = _actors.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
		_bus.entity_spawn_requested.emit(other, EntitiesScript.FAMILIAR, Vector2.ZERO, 5.0, SpellTag.make(other, 0, 0, 1), EntitiesScript.CASTER_POINT)
	check_equal(_entities.count(), EntitiesScript.ENEMY_ROWS, "the enemies fill only their own rows; the oldest give way")
	var wizards_have: int = 0
	for id in seated:
		for i in EntitiesScript.PER_PLAYER:
			_bus.entity_spawn_requested.emit(id, EntitiesScript.DECOY, Vector2.ZERO, 5.0, SpellTag.make(id, 0, 0, 1), EntitiesScript.CASTER_POINT)
			_bus.entity_spawn_requested.emit(id, EntitiesScript.FAMILIAR, Vector2.ZERO, 5.0, SpellTag.make(id, 0, 1, 1), EntitiesScript.CASTER_POINT)
		wizards_have += _entities.count(&"", id)
	check_equal(wizards_have, EntitiesScript.PLAYER_ROWS, "every wizard still gets every entity")
	check_equal(_entities.count(), EntitiesScript.POOL_SIZE, "beside the enemies' (%d)" % _entities.count())
	var ended: int = _ended.size()
	_bus.entity_spawn_requested.emit(first, EntitiesScript.DECOY, Vector2.ZERO, 5.0, SpellTag.make(seated[0], 0, 0, 1), EntitiesScript.CASTER_POINT)
	_bus.entity_spawn_requested.emit(seated[0], EntitiesScript.DECOY, Vector2.ZERO, 5.0, tag, EntitiesScript.CASTER_POINT)
	check(_entities.count() == EntitiesScript.POOL_SIZE and _ended.size() == ended, "a spell tag of another caster makes nothing and ends nothing")


## Enemies always hurt each other (actors G3c: the Enemy fire setting is gone): an enemy's bolt
## hits another enemy in its way, through the real AI, Spells, projectile manager and Combat.
func test_an_enemys_bolt_hits_another_enemy_in_its_way() -> void:
	var caster := _enemy(_data([&"bolt"]), Vector2.ZERO)
	_wizard.position = Vector2(80.0, 0.0)
	var blocker := _enemy(_data([&"bolt"]), Vector2(40.0, 0.0))
	blocker.caster.set_mana(0, 0.0)
	var health: float = _combat.health_of(blocker)
	_run(_ai(caster).windup_time + 0.5)
	check(_combat.health_of(blocker) < health, "the enemy in the way is hit")
	check(_combat.health_of(caster) == ImpData.max_health, "the caster is never hit by its own bolt")
