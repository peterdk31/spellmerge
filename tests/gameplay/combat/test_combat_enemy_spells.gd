extends "res://tests/support/suite.gd"
## Enemy spells in combat (staffs F6, docs/milestones/M2-staffs.md, "Enemy staffs"): an enemy's
## spell hit on a wizard does what a spell does (damage, push, statuses) and wizards take
## reactions from the same table as enemies, for every spell (CONSUME, BURST, EXTEND, SPREAD, the
## reaction wait); `actor_hurt` and `reaction_landed` carry the enemy's tag; an enemy's area hit
## hurts everything in it (wizards, the other enemies and the enemy that cast it; actors G3c).
## The enemy is an unseated actor of the test's actor table (actors G3b: hits name actor ids);
## the wizards are seated 0-3 at the actor ids 0-3.
## Hits arrive as `projectile_hit` and `area_hit_requested` on a test bus, with hand-made hit
## profiles; time moves by `Combat.step` with a fixed delta.
##
## godot --headless --path . --script res://tests/gameplay/combat/test_combat_enemy_spells.gd

const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")
const SpellsScript := preload("res://core/spells/spells.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const STEP: float = 0.0625

var _bus: EventsScript
var _projectiles: ManagerScript
var _combat: CombatScript
var _spells: SpellsScript
var _actors: ActorSeats.ActorsScript
## The enemy actor the tests' spells come from.
var _caster: int = -1
var _next_tag: int = 0
var _hurt: Array = []
var _landed: Array = []
var _reactions: Array = []
var _triggered: Array[StringName] = []


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_projectiles = own(ManagerScript.new()) as ManagerScript
	_projectiles.events = _bus
	_actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	_projectiles.actors = _actors
	_caster = ActorSeats.enemy(_actors)
	_combat = own(CombatScript.new()) as CombatScript
	_combat.events = _bus
	_combat.projectiles = _projectiles
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.bind(_projectiles, _bus)
	_combat.spells = _spells
	_combat.actors = _actors
	_combat._ready()
	_next_tag = 0
	for list: Array in [_hurt, _landed, _reactions, _triggered]:
		list.clear()
	_bus.actor_hurt.connect(func(p: int, a: int, _at: Vector2, tag: int, k: StringName) -> void: _hurt.append([p, a, tag, k]))
	_bus.hit_landed.connect(func(p: int, t: Node, a: int, _at: Vector2, k: StringName) -> void: _landed.append([p, t, a, k]))
	_bus.reaction_landed.connect(func(p: int, id: StringName, t: Node, _at: Vector2, tag: int) -> void: _reactions.append([p, id, t, tag]))
	_bus.reaction_triggered.connect(func(_p: int, id: StringName, _at: Vector2) -> void: _triggered.append(id))


func _wizard(index: int, at: Vector2) -> PlayerScript:
	var wizard := own(PlayerScript.new()) as PlayerScript
	wizard.index = index
	wizard.events = _bus
	# The seat's actor in the test table is the wizard's (opened there, not by the wizard).
	wizard.actors = _actors
	wizard.actor_id = _actors.actor_of_seat(index)
	wizard.projectiles = _projectiles
	wizard.spells = _spells
	wizard.combat = _combat
	wizard.position = at
	# In the tree: area hits, bursts and pulls find bodies by the projectile manager's grid.
	root.add_child(wizard)
	_combat.register_player(index, wizard, 8.0)
	return wizard


func _enemy(at: Vector2, health: int = 100) -> Node2D:
	var enemy := own(Node2D.new()) as Node2D
	enemy.position = at
	root.add_child(enemy)
	_combat.register_actor(enemy, health, 10.0)
	return enemy


## A spell tag of the enemy actor `_caster` whose hit profile is `profile`.
func _enemy_tag(profile: HitProfile) -> int:
	_next_tag += 1
	var tag: int = SpellTag.make(_caster, 0, _next_tag, 1)
	var spell := CompiledSpell.new()
	spell.hit = profile
	_spells._profiles[tag] = spell
	return tag


## A hit of one element that puts its status on.
func _element(damage: int, element: StringName, status: StringName, duration: float = 3.0, strength: float = 40.0) -> HitProfile:
	var profile := HitProfile.new()
	profile.damage = damage
	profile.kind = &"shot"
	profile.element_id = element
	profile.element_ids = [element]
	profile.status_id = status
	profile.status_duration = duration
	profile.status_strength = strength
	return profile


func _hit(wizard: Node2D, profile: HitProfile) -> int:
	var tag: int = _enemy_tag(profile)
	_bus.projectile_hit.emit(_caster, wizard, wizard.position + Vector2(-5.0, 0.0), tag)
	return tag


func _run(seconds: float) -> void:
	for i in int(seconds / STEP):
		_combat.step(STEP)


func test_an_enemys_spell_hurts_a_wizard_like_a_spell() -> void:
	var wizard := _wizard(1, Vector2(100.0, 0.0))
	var profile := _element(5, &"fire", &"burn", 2.0, 2.0)
	profile.knockback = 150.0
	var tag: int = _hit(wizard, profile)
	check_equal(wizard.health, PlayerScript.MAX_HEALTH - 5, "its damage")
	check_equal(_hurt, [[1, 5, tag, &"shot"]], "actor_hurt names the wizard's actor and carries the enemy's tag")
	check_equal(SpellTag.caster_of(_hurt[0][2]), _caster, "whose caster the runtime can find")
	check_equal(_landed[0][0], _caster, "the hit is the enemy actor's")
	check(_combat.status_left(1, &"burn") > 0.0, "its status goes on")
	check(_combat.knockback_of(1).x > 0.0, "and it pushes")


func test_a_wizard_thaws_like_an_enemy() -> void:
	var wizard := _wizard(0, Vector2(100.0, 0.0))
	var near := _wizard(1, Vector2(120.0, 0.0))
	var far := _wizard(2, Vector2(400.0, 0.0))
	_combat.apply_status(EventsScript.NO_PLAYER, 0, &"burn", 3.0, 1.0)
	var tag: int = _hit(wizard, _element(2, &"frost", &"chill"))
	check_equal(_triggered, [&"thaw"] as Array[StringName], "frost on a burning wizard thaws")
	check(_reactions.size() == 1 and _reactions[0][0] == _caster and _reactions[0][2] == wizard and _reactions[0][3] == tag, "reaction_landed names the enemy's tag, for its on reaction")
	check_equal(_combat.status_left(0, &"burn"), 0.0, "the burn is used up")
	check_equal(_combat.status_left(0, &"chill"), 0.0, "the reaction runs instead of the chill")
	check_equal(wizard.health, PlayerScript.MAX_HEALTH - 2 - 3, "the hit and the burst")
	check_equal(near.health, PlayerScript.MAX_HEALTH - 3, "the burst reaches the wizard beside")
	check_equal(far.health, PlayerScript.MAX_HEALTH, "not one far away")
	check_equal(_hurt[-1][2], 0, "the burst's damage carries no spell tag")


func test_a_frozen_wizard_shatters_for_double() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	for i in 3:
		_combat.apply_status(EventsScript.NO_PLAYER, 0, &"chill", 3.0, 30.0)
	check(_combat.status_left(0, &"freeze") > 0.0, "three chills freeze")
	_hit(wizard, _element(1, &"storm", &"shock"))
	check_equal(_triggered, [&"shatter"] as Array[StringName], "storm on a frozen wizard shatters")
	check_equal(wizard.health, PlayerScript.MAX_HEALTH - 1 - 12, "the hit, then twice the shatter")
	check_equal(_combat.status_left(0, &"freeze"), 0.0, "the freeze is gone")


func test_a_chilled_wizard_is_stilled_and_a_burn_kindles_the_wizards_near() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	_wizard(1, Vector2(30.0, 0.0))
	_combat.apply_status(EventsScript.NO_PLAYER, 0, &"chill", 3.0, 30.0)
	_hit(wizard, _element(1, &"void", &"hex"))
	check(_triggered.has(&"stillness") and _combat.status_left(0, &"freeze") > 0.0, "void on a chilled wizard freezes them")
	_triggered.clear()
	_run(1.0)
	_combat.apply_status(EventsScript.NO_PLAYER, 0, &"burn", 3.0, 1.0)
	_hit(wizard, _element(1, &"void", &"hex"))
	check(_triggered.has(&"kindle"), "void on a burning wizard kindles")
	check(_combat.status_left(1, &"burn") > 0.0, "and the wizard beside catches the burn")


func test_a_wizard_waits_before_reacting_again() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	_combat.apply_status(EventsScript.NO_PLAYER, 0, &"burn", 5.0, 1.0)
	_hit(wizard, _element(1, &"storm", &"shock"))
	check_equal(_triggered, [&"flare"] as Array[StringName], "the first hit reacts")
	_combat.apply_status(EventsScript.NO_PLAYER, 0, &"burn", 5.0, 1.0)
	_hit(wizard, _element(1, &"storm", &"shock"))
	check_equal(_triggered.size(), 1, "one right after does not")
	_run(0.75)
	_combat.apply_status(EventsScript.NO_PLAYER, 0, &"burn", 5.0, 1.0)
	_hit(wizard, _element(1, &"storm", &"shock"))
	check_equal(_triggered.size(), 2, "after the wait it reacts again")


func test_an_enemys_area_hit_hurts_everything_in_it() -> void:
	var wizard := _wizard(2, Vector2(10.0, 0.0))
	var other := _enemy(Vector2(-10.0, 0.0))
	var caster := _enemy(Vector2(0.0, 10.0))
	_projectiles.set_target_owner(caster, _caster)
	var blast := HitProfile.new()
	blast.damage = 4
	var tag: int = _enemy_tag(blast)
	_bus.area_hit_requested.emit(_caster, Vector2.ZERO, 40.0, tag)
	check_equal(wizard.health, PlayerScript.MAX_HEALTH - 4, "an enemy's blast hurts the wizard")
	check_equal(_combat.health_of(other), 96, "and the other enemy (G3c: enemies always hurt each other)")
	check_equal(_combat.health_of(caster), 96, "and the enemy that cast it, as a wizard's own blast does the wizard")


func test_an_enemys_mend_heals_its_team_and_hurts_the_wizards() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	wizard.health = 50
	var imp := _enemy(Vector2(10.0, 0.0))
	_combat.hit(_caster, imp, 30)
	var profile := HitProfile.new()
	profile.damage = 2
	profile.heal = 10
	_bus.area_hit_requested.emit(_caster, Vector2.ZERO, 40.0, _enemy_tag(profile))
	check_equal(wizard.health, 48, "an enemy's mend is not the wizards': they take its damage")
	check_equal(_combat.health_of(imp), 80, "it heals its caster's team (actors G5: a mend is for friends)")
