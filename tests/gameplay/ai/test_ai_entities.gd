extends "res://tests/support/suite.gd"
## Decoys and familiars for enemies (staffs F8d, docs/milestones/M2-staffs.md, "Enemy staffs"):
## an enemy's decoy copies the enemy, is a target wizards' shots hit (and only theirs wear it down)
## and enemies never chase; an enemy's familiar circles the enemy and casts at the nearest wizard,
## in the enemy's own spell; each enemy keeps PER_ENEMY of a kind, enemies share rows of their own
## so a crowd never takes a wizard's, and an enemy's entities end with it. The same world as
## test_ai_moves.gd, plus Entities.
##
## godot --headless --path . --script res://tests/gameplay/ai/test_ai_entities.gd

const AiScript := preload("res://gameplay/ai/ai.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
const EntitiesScript := preload("res://gameplay/ai/entities.gd")
const EventsScript := preload("res://core/events/events.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const StaffKit := preload("res://tests/support/staff_kit.gd")
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
var _wizard: PlayerScript
var _enemies: Array[AiScript] = []
## Every familiar_cast_requested as [player, tag], and entity_ended as [player, kind, tag].
var _casts: Array = []
var _ended: Array = []


func before_each() -> void:
	_fake = own(FakeRegistry.new()) as FakeRegistry
	_bus = own(EventsScript.new()) as EventsScript
	_projectiles = own(ManagerScript.new()) as ManagerScript
	_projectiles.events = _bus
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.registry = _fake
	_spells.bind(_projectiles, _bus)
	_combat = own(CombatScript.new()) as CombatScript
	_combat.events = _bus
	_combat.projectiles = _projectiles
	_combat.spells = _spells
	_combat._ready()
	_entities = own(EntitiesScript.new()) as EntitiesScript
	_entities.events = _bus
	_entities.projectiles = _projectiles
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
	familiar.motion = FormBase.Motion.FAMILIAR
	familiar.lifetime = 6.0
	familiar.mana_cost = 2.0
	_put(familiar, &"familiar")
	var decoy := FormBase.new()
	decoy.motion = FormBase.Motion.DECOY
	decoy.lifetime = 4.0
	decoy.mana_cost = 2.0
	_put(decoy, &"decoy")
	_casts.clear()
	_ended.clear()
	_bus.familiar_cast_requested.connect(func(player: int, _at: Vector2, _direction: Vector2, tag: int) -> void: _casts.append([player, tag]))
	_bus.entity_ended.connect(func(player: int, kind: StringName, _at: Vector2, tag: int) -> void: _ended.append([player, kind, tag]))
	_wizard = own(PlayerScript.new()) as PlayerScript
	_wizard.index = 0
	_wizard.events = _bus
	root.add_child(_wizard)
	_wizard.position = Vector2(80.0, 0.0)
	_combat.register_player(0, _wizard, 8.0, Vector2(0.0, -12.0))


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
	data.staff = StaffKit.plain_staff(cards.size())
	data.staff.cast_delay = 0.0
	data.cards = cards
	data.max_mana = 20.0
	data.mana_regen = 0.0
	return data


## An enemy of `data` from the imp's scene (its Sprite), in the tree at `at`.
func _enemy(data: EnemyBase, at: Vector2 = Vector2.ZERO) -> AiScript:
	var enemy: AiScript = ImpData.scene.instantiate()
	enemy.data = data
	enemy.events = _bus
	enemy.combat = _combat
	enemy.projectiles = _projectiles
	enemy.spells = _spells
	enemy.entities = _entities
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
		_projectiles.step(STEP)
		_spells.step(STEP)
		_combat.step(STEP)
		_entities.step(STEP)


func test_an_enemys_decoy_copies_it_and_only_wizards_wear_it_down() -> void:
	var enemy := _enemy(_data([&"decoy"]))
	var tag: int = _spells.current_tag(enemy.caster, 0)
	_run(enemy.windup_time + 2.0 * STEP)
	check_equal(_entities.count_owned(EntitiesScript.DECOY, enemy.caster), 1, "its decoy card makes one decoy, the enemy's")
	check_equal(_entities.count(EntitiesScript.DECOY, 0), 0, "not the wizard's")
	var at: Vector2 = _entities.positions_of(EventsScript.NO_PLAYER, tag)[0]
	var decoy: Node2D = _projectiles.nearest_target(at, 16.0, ManagerScript.LAYER_ENEMY, enemy)
	check(decoy is EntitiesScript.Decoy, "a target on the enemies' layer, where wizards' shots and homing look")
	check(_projectiles.nearest_target(at, 16.0, ManagerScript.LAYER_PLAYER, _wizard) == null, "and not on the wizards' layer")
	var copied: Sprite2D = (decoy as EntitiesScript.Decoy).sprite
	var fresh: Node = ImpData.scene.instantiate()
	var looks: Array = [(fresh.get_node("Sprite") as Sprite2D).texture, enemy.windup_texture, enemy.hurt_texture]
	fresh.free()
	check(copied.texture != null and looks.has(copied.texture), "it copies the enemy's sprite")
	check(_entities.lure(at) == null, "enemies never chase an enemy's decoy")
	_bus.projectile_hit.emit(EventsScript.NO_PLAYER, decoy, at, tag)
	_bus.projectile_hit.emit(EventsScript.NO_PLAYER, decoy, at, tag)
	_bus.projectile_hit.emit(EventsScript.NO_PLAYER, decoy, at, tag)
	check_equal(_entities.count_owned(EntitiesScript.DECOY, enemy.caster), 1, "an enemy's shots do not wear it")
	for i in EntitiesScript.DECOY_HITS:
		_bus.projectile_hit.emit(0, decoy, at, SpellTag.make(0, 0, 0, 0))
	check_equal(_entities.count_owned(EntitiesScript.DECOY, enemy.caster), 0, "a wizard's shots break it")
	check(_ended.size() == 1 and _ended[0][0] == EventsScript.NO_PLAYER and _ended[0][1] == EntitiesScript.DECOY and _ended[0][2] == tag, "and its end is said as NO_PLAYER with its tag")


func test_an_enemys_familiar_circles_it_and_casts_at_the_wizard() -> void:
	var enemy := _enemy(_data([&"familiar", &"bolt"]))
	var tag: int = _spells.current_tag(enemy.caster, 0)
	_run(enemy.windup_time + 2.0 * STEP)
	check_equal(_entities.count_owned(EntitiesScript.FAMILIAR, enemy.caster), 1, "its familiar card makes one familiar")
	_run(0.25)
	var at: Vector2 = _entities.positions_of(EventsScript.NO_PLAYER, tag)[0]
	var centre: Vector2 = enemy.global_position + EntitiesScript.FAMILIAR_CENTRE
	check(is_equal_approx(at.distance_to(centre), EntitiesScript.FAMILIAR_ORBIT), "it circles the enemy (%.2f from it)" % at.distance_to(centre))
	var hits: Array = []
	_bus.projectile_hit.connect(func(player: int, target: Node, _hit_at: Vector2, _hit_tag: int) -> void: hits.append([player, target]))
	var peak: int = 0
	for i in 12:
		_run(STEP)
		peak = maxi(peak, _projectiles.get_count())
	check(_casts.size() >= 1 and _casts[0][0] == EventsScript.NO_PLAYER and _casts[0][1] == tag, "it casts at the wizard, as NO_PLAYER with its tag")
	check(peak >= 1, "the enemy's spell (its bolt) leaves it")
	check(hits.size() >= 1 and hits[0][0] == EventsScript.NO_PLAYER and hits[0][1] == _wizard, "and hits the wizard as the enemy's")
	check_equal(_entities.drawn_familiars(), 1, "drawn with the others")


func test_an_enemys_familiar_waits_without_a_wizard_in_range() -> void:
	var enemy := _enemy(_data([&"familiar", &"bolt"]))
	_run(enemy.windup_time + 2.0 * STEP)
	_wizard.position = Vector2(2000.0, 0.0)
	_run(EntitiesScript.FAMILIAR_FIRST + 1.0)
	check(_casts.is_empty(), "no wizard within its range: it does not cast (enemies are never its targets)")


func test_an_enemys_entities_end_with_it() -> void:
	var enemy := _enemy(_data([&"familiar", &"bolt"]))
	var tag: int = _spells.current_tag(enemy.caster, 0)
	var caster: int = enemy.caster
	_run(enemy.windup_time + 2.0 * STEP)
	check_equal(_entities.count_owned(EntitiesScript.FAMILIAR, caster), 1, "a familiar is live")
	enemy.close_staff()
	check_equal(_entities.count_owned(EntitiesScript.FAMILIAR, caster), 0, "the enemy gone, its familiar ends")
	check(_ended.size() == 1 and _ended[0][0] == EventsScript.NO_PLAYER and _ended[0][2] == tag, "with entity_ended, so its end still counts")


func test_enemies_keep_their_share_and_never_take_a_wizards_rows() -> void:
	var tag: int = SpellTag.make_enemy(0, 0, 0, 1)
	for i in EntitiesScript.PER_ENEMY + 1:
		_bus.entity_spawn_requested.emit(EventsScript.NO_PLAYER, EntitiesScript.DECOY, Vector2(i * 10.0, 0.0), 5.0, tag, EntitiesScript.CASTER_POINT)
	check_equal(_entities.count_owned(EntitiesScript.DECOY, EntitiesScript.FIRST_ENEMY_CASTER), EntitiesScript.PER_ENEMY, "one enemy keeps PER_ENEMY of a kind; one more ends its oldest")
	check_equal(_ended.size(), 1, "and that end is said")
	for row in EntitiesScript.ENEMY_ROWS + 4:
		var other: int = SpellTag.make_enemy(row + 1, 0, 0, 1)
		_bus.entity_spawn_requested.emit(EventsScript.NO_PLAYER, EntitiesScript.FAMILIAR, Vector2.ZERO, 5.0, other, EntitiesScript.CASTER_POINT)
	check_equal(_entities.count(), EntitiesScript.ENEMY_ROWS, "the enemies fill only their own rows; the oldest give way")
	for player in EntitiesScript.PLAYER_SLOTS:
		for i in EntitiesScript.PER_PLAYER:
			_bus.entity_spawn_requested.emit(player, EntitiesScript.DECOY, Vector2.ZERO, 5.0, SpellTag.make(player, 0, 0, 1), EntitiesScript.CASTER_POINT)
			_bus.entity_spawn_requested.emit(player, EntitiesScript.FAMILIAR, Vector2.ZERO, 5.0, SpellTag.make(player, 0, 1, 1), EntitiesScript.CASTER_POINT)
	check_equal(_entities.count(&"", 0) + _entities.count(&"", 1) + _entities.count(&"", 2) + _entities.count(&"", 3), EntitiesScript.PLAYER_ROWS, "every wizard still gets every entity")
	check_equal(_entities.count(), EntitiesScript.POOL_SIZE, "beside the enemies' (%d)" % _entities.count())
	_bus.entity_spawn_requested.emit(EventsScript.NO_PLAYER, EntitiesScript.DECOY, Vector2.ZERO, 5.0, SpellTag.make(0, 0, 0, 1), EntitiesScript.CASTER_POINT)
	_bus.entity_spawn_requested.emit(0, EntitiesScript.DECOY, Vector2.ZERO, 5.0, SpellTag.make_enemy(0, 0, 0, 1), EntitiesScript.CASTER_POINT)
	check_equal(_entities.count(), EntitiesScript.POOL_SIZE, "NO_PLAYER with a player's tag makes nothing; a player with an enemy's tag ends their own oldest")
