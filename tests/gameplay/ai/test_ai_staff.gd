extends "res://tests/support/suite.gd"
## Enemies that cast staffs (staffs F8a, docs/milestones/M2-staffs.md, "Enemy staffs"): an enemy
## whose data has a staff and cards opens a caster row, owns its body there, casts its staff
## after the windup, pays mana and gets it back, winds up only when the next cast is ready (so a
## telegraph always comes true), shows the next cast's reach, compiles its staff once per enemy
## type, and gives its row back when it leaves. A world of its own (bus, projectiles, spells with
## cards built in code, combat, one wizard), stepped by hand.
##
## godot --headless --path . --script res://tests/gameplay/ai/test_ai_staff.gd

const AiScript := preload("res://gameplay/ai/ai.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")
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
var _fake: FakeRegistry
var _wizard: PlayerScript
var _enemies: Array[AiScript] = []


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


func test_it_opens_a_row_and_owns_its_body() -> void:
	var enemy := _enemy(_data([&"bolt"]))
	check(enemy.uses_staff(), "an enemy with a staff and cards casts it")
	check(enemy.caster >= SpellLimits.FIRST_ENEMY_CASTER and _spells.is_enemy_caster_open(enemy.caster), "it opened a caster row")
	check_equal(_projectiles.target_owner_of(enemy), enemy.caster, "its body is its row's, so its own spells skip it")
	check_equal(enemy.mana, 6.0, "it starts with full mana")
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
	check_equal(_projectiles.get_count_for(EventsScript.NO_PLAYER), 1, "then its bolt flies")
	check_equal(enemy.mana, 4.0, "and it paid the cast's mana")
	_run(0.5)
	check(_wizard.health < PlayerScript.MAX_HEALTH, "the bolt hurt the wizard through combat")
	check_equal(_combat.get_health(enemy), ImpData.max_health, "and not the enemy that cast it")


func test_no_windup_without_the_mana_and_regen_brings_it() -> void:
	var broke := _enemy(_data([&"bolt"], 1.0, 0.0))
	check(not _until_windup(broke, 3.0), "with too little mana it never telegraphs")
	check_equal(_projectiles.get_count_for(EventsScript.NO_PLAYER), 0, "and never casts")
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
	check_equal(_projectiles.get_count_for(EventsScript.NO_PLAYER), 1, "the first cast")
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
	check(_projectiles.get_count_for(EventsScript.NO_PLAYER) >= 1 and enemy.mana <= 96.0, "and the promised cast comes")


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


func test_one_compile_per_enemy_type_and_its_row_goes_back() -> void:
	var data := _data([&"bolt"])
	var first := _enemy(data)
	var second := _enemy(data, Vector2(0.0, 30.0))
	check(first.caster != second.caster, "each enemy has its own row")
	check(_spells.profile(_spells.current_tag(first.caster, 0)) == _spells.profile(_spells.current_tag(second.caster, 0)), "sharing one compiled staff")
	check_equal(_spells.enemy_casters_open(), 2, "two rows open")
	var row: int = first.caster
	first.free()
	check(not _spells.is_enemy_caster_open(row), "leaving the tree gives the row back")
	check_equal(_spells.enemy_casters_open(), 1, "one left")
