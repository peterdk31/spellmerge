extends "res://tests/support/suite.gd"
## The combat kit of the staffs (B3, docs/milestones/M2-staffs.md, "Self-harm and hits"): self-harm,
## hit kinds, several elements per hit, statuses and barriers on wizards, heal hits,
## pulls, the heavy slam, and the events cards listen to (`kill_landed`, `reaction_landed`,
## `actor_hurt`, `shield_blocked`). Hits arrive as `projectile_hit` on a
## test bus, with hand-made hit profiles; time moves by `Combat.step` with a fixed delta. Hits name
## actor ids (actors G3b): the test's actor table seats the wizards 0-3 at the ids 0-3 and opens
## one unseated enemy actor for the enemies' spells.
##
## godot --headless --path . --script res://tests/gameplay/combat/test_combat_kit.gd

const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const WizardScene := preload("res://content/wizard/base/wizard.tscn")
const SpellsScript := preload("res://core/spells/spells.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const STEP: float = 0.0625

var _bus: EventsScript
var _projectiles: ManagerScript
var _combat: CombatScript
var _spells: SpellsScript
var _actors: ActorSeats.ActorsScript
## The enemy actor the enemies' spells come from.
var _enemy_caster: int = -1
var _wizards: Array[Actor] = []
var _next_tag: int = 0
## Each event as an array of its arguments.
var _landed: Array = []
var _hurt: Array = []
var _kills: Array = []
var _reactions: Array = []
var _blocked: Array = []
var _healed: Array = []
var _applied: Array = []


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_projectiles = own(ManagerScript.new()) as ManagerScript
	_projectiles.events = _bus
	_actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	_projectiles.actors = _actors
	_enemy_caster = ActorSeats.enemy(_actors)
	_combat = own(CombatScript.new()) as CombatScript
	_combat.events = _bus
	_combat.projectiles = _projectiles
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.bind(_projectiles, _bus)
	_combat.spells = _spells
	_combat.actors = _actors
	_combat._ready()
	_wizards.clear()
	_next_tag = 0
	for list: Array in [_landed, _hurt, _kills, _reactions, _blocked, _healed, _applied]:
		list.clear()
	_bus.hit_landed.connect(func(p: int, t: Node, a: int, _at: Vector2, k: StringName, _shot: int) -> void: _landed.append([p, t, a, k]))
	_bus.actor_hurt.connect(func(p: int, a: int, _at: Vector2, tag: int, k: StringName) -> void: _hurt.append([p, a, tag, k]))
	_bus.kill_landed.connect(func(p: int, t: Node, _at: Vector2, tag: int, _shot: int) -> void: _kills.append([p, t, tag]))
	_bus.reaction_landed.connect(func(p: int, id: StringName, t: Node, _at: Vector2, tag: int, _shot: int) -> void: _reactions.append([p, id, t, tag]))
	_bus.shield_blocked.connect(func(p: int, _at: Vector2, tag: int) -> void: _blocked.append([p, tag]))
	_bus.heal_dealt.connect(func(p: int, t: Node, a: int, _at: Vector2) -> void: _healed.append([p, t, a]))
	_bus.status_applied.connect(func(p: int, t: Node, id: StringName) -> void: _applied.append([p, t, id]))


## A wizard actor of seat `index` from the real scene (actors G7), in the tree at `at`.
func _wizard(index: int, at: Vector2) -> Actor:
	# The wizard opens its own actor as it enters the tree: give it the seat's id in the test
	# table (the lowest free one once the seat's is closed).
	_actors.close(_actors.actor_of_seat(index))
	var wizard := own(WizardScene.instantiate()) as Actor
	PlayerController.seat_wizard(wizard, index, null, [[], [], [], []])
	wizard.events = _bus
	wizard.combat = _combat
	wizard.projectiles = _projectiles
	wizard.spells = _spells
	wizard.actors = _actors
	wizard.position = at
	root.add_child(wizard)
	wizard.set_physics_process(false)
	# Its hurtbox registered it in Combat's seat slot.
	_wizards.append(wizard)
	return wizard


func _enemy(at: Vector2, health: int = 100) -> Node2D:
	var enemy := own(Node2D.new()) as Node2D
	enemy.position = at
	root.add_child(enemy)
	_combat.register_actor(enemy, health, 10.0)
	return enemy


## A spell tag of `caster` (actor 0, the wizard of seat 0, unless named) whose hit profile is `profile`.
func _tag(profile: HitProfile, caster: int = 0) -> int:
	_next_tag += 1
	var tag: int = SpellTag.make(caster, 0, _next_tag, 1)
	var spell := CompiledSpell.new()
	spell.hit = profile
	_spells._profiles[tag] = spell
	return tag


## Like `_tag`, for an enemy's spell (the unseated enemy actor `_enemy_caster`).
func _enemy_tag(profile: HitProfile) -> int:
	return _tag(profile, _enemy_caster)


func _profile(damage: int, kind: StringName = &"shot") -> HitProfile:
	var profile := HitProfile.new()
	profile.damage = damage
	profile.kind = kind
	return profile


func _run(seconds: float) -> void:
	for i in int(seconds / STEP):
		_combat.step(STEP)


# --- Self-harm and hit kinds ---


func test_a_wizard_is_hurt_by_their_own_spell() -> void:
	var wizard := _wizard(0, Vector2(100.0, 0.0))
	var tag: int = _tag(_profile(6))
	_bus.projectile_hit.emit(0, wizard, Vector2(90.0, 0.0), tag, -1)
	check_equal(wizard.health.health, wizard.health.max_health - 6, "their own shot took health")
	check_equal(_landed, [[0, wizard, 6, &"shot"]], "hit_landed names the caster as both the source and the target")
	check_equal(_hurt, [[0, 6, tag, &"shot"]], "actor_hurt names the wizard's actor, the damage, the card's tag and the kind")


func test_an_enemys_spell_hurts_a_wizard_with_its_tag_in_actor_hurt() -> void:
	var wizard := _wizard(1, Vector2.ZERO)
	var tag: int = _enemy_tag(_profile(4))
	_bus.projectile_hit.emit(_enemy_caster, wizard, Vector2(-5.0, 0.0), tag, -1)
	check_equal(wizard.health.health, wizard.health.max_health - 4, "the enemy's spell hurt")
	check_equal(_hurt, [[1, 4, tag, &"shot"]], "actor_hurt names the wizard's actor and the tag (its caster is the enemy actor)")
	_bus.projectile_hit.emit(_enemy_caster, wizard, Vector2(-5.0, 0.0), 9, -1)
	check_equal(wizard.health.health, wizard.health.max_health - 4, "a shot with no spell does nothing (staffs F9b: no table)")


func test_a_spell_hit_pushes_the_wizard_it_hurts() -> void:
	var wizard := _wizard(0, Vector2(100.0, 0.0))
	var profile := _profile(2)
	profile.knockback = 200.0
	_bus.projectile_hit.emit(0, wizard, Vector2(90.0, 0.0), _tag(profile), -1)
	check_equal(_combat.consume_knockback(_wizards[0], 0.0), Vector2(200.0, 0.0), "pushed away from the hit")
	_combat.consume_knockback(_wizards[0], 1.0)
	check_equal(_combat.consume_knockback(_wizards[0], 0.0), Vector2.ZERO, "the push fades like an enemy's")


func test_an_enemy_hit_has_the_kind_of_its_profile() -> void:
	var enemy := _enemy(Vector2.ZERO)
	_bus.projectile_hit.emit(0, enemy, Vector2(-5.0, 0.0), _tag(_profile(3, &"ray")), -1)
	check_equal(_landed, [[0, enemy, 3, &"ray"]], "a beam's hit is a ray")


func test_a_burn_that_kills_is_kind_status_and_reaction_damage_is_kind_reaction() -> void:
	var dying := _enemy(Vector2.ZERO, 2)
	_combat.apply_status(0, dying, &"burn", 2.0, 4.0)
	_run(1.0)
	check_equal(_landed[0][3], &"status", "the killing tick is kind status")
	_landed.clear()
	var enemy := _enemy(Vector2(200.0, 0.0))
	_combat.apply_status(0, enemy, &"burn", 3.0, 0.0001)
	var profile := _profile(4)
	profile.element_id = &"frost"
	profile.element_ids = [&"frost"]
	_bus.projectile_hit.emit(0, enemy, Vector2(195.0, 0.0), _tag(profile), -1)
	var kinds: Array[StringName] = []
	for row: Array in _landed:
		kinds.append(row[3] as StringName)
	check_equal(kinds[0], &"shot", "the shot first")
	check(&"reaction" in kinds, "the thaw's burst is kind reaction")


# --- Several elements ---


func test_a_later_element_reacts_with_the_status_the_first_left() -> void:
	var enemy := _enemy(Vector2.ZERO)
	var profile := _profile(4)
	profile.element_id = &"fire"
	profile.element_ids = [&"fire", &"frost"]
	profile.status_id = &"burn"
	profile.status_duration = 3.0
	profile.status_strength = 2.0
	profile.later_status_ids = [&"chill"]
	profile.later_status_durations = PackedFloat32Array([3.0])
	profile.later_status_strengths = PackedFloat32Array([40.0])
	var ids: Array[StringName] = []
	_bus.reaction_triggered.connect(func(_p: int, id: StringName, _at: Vector2, _shot: int) -> void: ids.append(id))
	_bus.projectile_hit.emit(0, enemy, Vector2(-5.0, 0.0), _tag(profile), -1)
	check_equal(ids, [&"thaw"], "fire then frost thaws on a single hit")
	check(not _combat.has_status(enemy, &"chill"), "the reaction ran instead of the chill")


func test_a_later_element_without_a_reaction_puts_its_own_status_on() -> void:
	var enemy := _enemy(Vector2.ZERO)
	var profile := _profile(4)
	profile.element_id = &"fire"
	profile.element_ids = [&"fire", &"fire"]
	profile.status_id = &"burn"
	profile.status_duration = 3.0
	profile.status_strength = 2.0
	profile.later_status_ids = [&"burn"]
	profile.later_status_durations = PackedFloat32Array([3.0])
	profile.later_status_strengths = PackedFloat32Array([9.0])
	_bus.projectile_hit.emit(0, enemy, Vector2(-5.0, 0.0), _tag(profile), -1)
	check_equal(_reactions, [], "fire on fire reacts with nothing")
	check_equal(_combat.status_left(enemy, &"burn"), 3.0, "burning")
	_run(1.0)
	check(_combat.health_of(enemy) <= 100 - 4 - 8, "the second fire's stronger burn won (9 per second)")


func test_the_elements_of_one_hit_chain_their_reactions() -> void:
	var enemy := _enemy(Vector2.ZERO)
	_combat.apply_status(0, enemy, &"burn", 5.0, 0.0001)
	_combat.apply_status(0, enemy, &"hex", 5.0, 10.0)
	var profile := _profile(4)
	profile.element_id = &"frost"
	profile.element_ids = [&"frost", &"fire"]
	var ids: Array[StringName] = []
	_bus.reaction_triggered.connect(func(_p: int, id: StringName, _at: Vector2, _shot: int) -> void: ids.append(id))
	_bus.projectile_hit.emit(0, enemy, Vector2(-5.0, 0.0), _tag(profile), -1)
	check_equal(ids, [&"thaw", &"kindle"], "the second element reacts with what the first reaction left")


# --- Statuses on wizards ---


func test_every_element_of_a_hit_puts_its_status_on_the_wizard_it_hurt() -> void:
	# Lightning then storm: static and shock have no reaction, so both go on. (Fire then frost
	# thaws on a wizard as on an enemy since staffs F6: see test_combat_enemy_spells.gd.)
	_wizard(0, Vector2.ZERO)
	var profile := _profile(2)
	profile.element_id = &"lightning"
	profile.element_ids = [&"lightning", &"storm"]
	profile.status_id = &"static"
	profile.status_duration = 2.0
	profile.status_strength = 30.0
	profile.later_status_ids = [&"shock"]
	profile.later_status_durations = PackedFloat32Array([3.0])
	profile.later_status_strengths = PackedFloat32Array([40.0])
	_bus.projectile_hit.emit(0, _wizards[0], Vector2(-5.0, 0.0), _tag(profile), -1)
	check(_combat.status_left(0, &"static") > 0.0, "charged")
	check(_combat.status_left(0, &"shock") > 0.0, "and shocked by the second element")


func test_a_burn_tick_spends_no_shock_and_no_static_and_adds_no_hex() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	var near := _enemy(Vector2(30.0, 0.0))
	_projectiles.step(STEP)
	_combat.apply_status(0, 0, &"shock", 5.0, 100.0)
	_combat.apply_status(0, 0, &"static", 5.0, 50.0)
	_combat.apply_status(0, 0, &"burn", 1.0, 4.0)
	_run(1.0)
	check(_combat.status_left(0, &"shock") > 0.0, "the shock is still on after the ticks")
	check(_combat.status_left(0, &"static") > 0.0, "so is the static")
	check_equal(_combat.health_of(near), 100, "no discharge from the wizard's own burn")
	check_equal(wizard.health.health, wizard.health.max_health - 4, "the ticks took plain damage, no shock bonus")


func test_a_burn_tick_on_a_wizard_is_quiet_but_reaches_its_health_and_its_hud() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	var stats: Array = []
	_bus.player_stats_changed.connect(func(p: int, health: int, _most: int, _mana: float, _max_mana: float) -> void: stats.append([p, health]))
	_combat.apply_status(0, 0, &"burn", 1.0, 4.0)
	_run(1.0)
	# The seat tells the HUD on its next look.
	(wizard.home_controller as PlayerController).think(wizard, STEP)
	check_equal(wizard.health.health, wizard.health.max_health - 4, "the ticks took health")
	check(_landed.is_empty(), "nobody was told: burn ticks are quiet for everyone (actors G5)")
	check(not stats.is_empty() and stats[stats.size() - 1] == [0, wizard.health.max_health - 4], "the seat's HUD heard the new health")


func test_a_burn_tick_that_downs_a_wizard_is_told_as_kind_status() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	wizard.health.health = 2
	_combat.apply_status(0, 0, &"burn", 1.0, 4.0)
	_run(1.0)
	check(wizard.is_down(), "the burn downed the wizard")
	check_equal(_landed.size(), 1, "only the tick that downed it was told")
	check_equal(_landed[0][3], &"status", "as kind status")


func test_a_shock_jump_kill_is_no_kill_for_a_card() -> void:
	var struck := _enemy(Vector2.ZERO)
	var weak := _enemy(Vector2(30.0, 0.0), 1)
	_projectiles.step(STEP)
	_combat.apply_status(0, struck, &"shock", 5.0, 100.0)
	_bus.projectile_hit.emit(0, struck, Vector2(-5.0, 0.0), _tag(_profile(5)), -1)
	check_equal(_combat.health_of(weak), -1, "the jump killed it")
	check(_kills.is_empty(), "a jump is not the spell's own hit")


func test_burn_on_a_wizard_hurts_over_time_as_kind_status() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	check(_combat.apply_status(0, 0, &"burn", 1.0, 4.0), "the burn took")
	_run(1.0)
	check(wizard.health.health <= wizard.health.max_health - 3, "burn took health")
	check(_hurt.is_empty(), "a burn tick is not a hit: no actor_hurt for cards")
	check(_landed.is_empty(), "and quiet while the wizard stands")
	check_equal(_applied[0], [0, wizard, &"burn"], "status_applied names the wizard")
	_run(1.0)
	check_equal(_combat.status_left(0, &"burn"), 0.0, "and it ends")


func test_three_chills_freeze_a_wizard_and_chill_slows() -> void:
	_wizard(2, Vector2.ZERO)
	_combat.apply_status(2, 2, &"chill", 3.0, 40.0)
	check_equal(snappedf(_combat.pace_of(2), 0.01), 0.6, "a chill takes 40 % of the pace")
	_combat.apply_status(2, 2, &"chill", 3.0, 40.0)
	_combat.apply_status(2, 2, &"chill", 3.0, 40.0)
	check_equal(_combat.pace_of(2), 0.0, "frozen")
	check(&"freeze" in _applied.map(func(row: Array) -> StringName: return row[2] as StringName), "freeze is announced")
	check_equal(_combat.pace_of(0), 1.0, "other wizards move freely")
	_run(1.25)
	check_equal(_combat.pace_of(2), 1.0, "the freeze ends")


func test_a_hex_makes_a_wizard_take_more() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	_combat.apply_status(0, 0, &"hex", 5.0, 50.0)
	check(_combat.hit(EventsScript.NO_PLAYER, wizard, 4), "hit")
	check_equal(wizard.health.health, wizard.health.max_health - 6, "4 plus 50 % (hex)")


func test_a_hexed_wizard_is_pulled_toward_a_spell_hit() -> void:
	var wizard := _wizard(0, Vector2(100.0, 0.0))
	_combat.apply_status(0, 0, &"hex", 5.0, 50.0)
	var profile := _profile(2)
	profile.knockback = 200.0
	_bus.projectile_hit.emit(_enemy_caster, wizard, Vector2(90.0, 0.0), _enemy_tag(profile), -1)
	check_equal(_combat.knockback_of(0), Vector2(-100.0, 0.0), "pulled toward the hit at half the push (actors G5: the enemy's rule)")


func test_a_shocked_wizards_next_spell_hit_jumps_to_its_nearest_teammate() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	var mate := _wizard(1, Vector2(40.0, 0.0))
	var enemy := _enemy(Vector2(-20.0, 0.0))
	_projectiles.step(STEP)
	_combat.apply_status(0, 0, &"shock", 5.0, 100.0)
	check(_combat.hit(EventsScript.NO_PLAYER, wizard, 4), "a plain hit")
	check_equal(wizard.health.health, wizard.health.max_health - 4, "adds nothing (actors G5: no shock bonus)")
	check(_combat.has_status(wizard, &"shock"), "and leaves the shock for a spell")
	_bus.projectile_hit.emit(_enemy_caster, wizard, Vector2(-5.0, -12.0), _enemy_tag(_profile(4)), -1)
	check_equal(mate.health.health, mate.health.max_health - 4, "the spell hit jumped to the nearest actor of the wizard's team")
	check_equal(_combat.health_of(enemy), 100, "not to the enemy, though it stands nearer")
	check(not _combat.has_status(wizard, &"shock"), "the shock is spent")


func test_a_charged_wizard_discharges_into_enemies_near_on_the_next_hit() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	var near := _enemy(Vector2(30.0, 0.0))
	var far := _enemy(Vector2(300.0, 0.0))
	_projectiles.step(STEP)
	_combat.apply_status(0, 0, &"static", 5.0, 50.0)
	_combat.hit(EventsScript.NO_PLAYER, wizard, 10)
	check_equal(_combat.health_of(near), 95, "half the hit leaves as lightning")
	check_equal(_combat.health_of(far), 100, "far enemies are left alone")
	_combat.hit(EventsScript.NO_PLAYER, wizard, 10)
	check_equal(_combat.health_of(near), 95, "the charge was spent")


func test_a_charged_enemy_discharges_into_the_wizards_near_and_is_spent() -> void:
	var first := _wizard(0, Vector2(30.0, 12.0))
	var second := _wizard(1, Vector2(-30.0, 12.0))
	var kin := _enemy(Vector2(0.0, 30.0))
	var enemy := _enemy(Vector2.ZERO)
	_projectiles.step(STEP)
	_combat.apply_status(0, enemy, &"static", 5.0, 50.0)
	_combat.hit(0, enemy, 10)
	check_equal(first.health.health, first.health.max_health - 5, "half the hit arcs to a wizard near")
	check_equal(second.health.health, second.health.max_health - 5, "and to the other")
	check_equal(_combat.health_of(kin), 100, "its own team is left alone")
	check(not _combat.has_status(enemy, &"static"), "the charge is spent")


func test_an_enemy_takes_a_barrier_like_a_wizard() -> void:
	var enemy := _enemy(Vector2.ZERO)
	_bus.wizard_shield_requested.emit(_combat.actor_of(enemy), 1, 2.0, 6)
	check_equal(_combat.shield(enemy), 1, "the caster's own actor gets the barrier, whoever it is")
	check(not _combat.hit(0, enemy, 5), "it blocks a hit")
	check_equal(_combat.health_of(enemy), 100, "whole")
	check_equal(_blocked, [[_combat.actor_of(enemy), 6]], "shield_blocked names the enemy's actor and the card")


func test_a_downed_wizard_takes_no_status() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	wizard.health.take(1000)
	check(not _combat.apply_status(0, 0, &"burn", 1.0, 4.0), "refused")
	check_equal(_combat.status_left(0, &"burn"), 0.0, "nothing on")


func test_a_spell_hit_puts_its_status_on_the_wizard_it_hurt() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	var profile := _profile(2)
	profile.status_id = &"hex"
	profile.status_duration = 2.0
	profile.status_strength = 40.0
	_bus.projectile_hit.emit(0, wizard, Vector2(-5.0, 0.0), _tag(profile), -1)
	check(_combat.status_left(0, &"hex") > 0.0, "hexed by their own spell")


# --- Barriers on wizards ---


func test_a_barrier_blocks_hits_one_charge_each() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	_bus.wizard_shield_requested.emit(0, 2, 2.0, 77)
	check_equal(_combat.shield(0), 2, "two charges")
	check(not _combat.hit(EventsScript.NO_PLAYER, wizard, 5), "the first hit is blocked")
	check(not _combat.hit(EventsScript.NO_PLAYER, wizard, 5), "so is the second")
	check_equal(wizard.health.health, wizard.health.max_health, "no damage")
	check_equal(_blocked, [[0, 77], [0, 77]], "shield_blocked names the wizard's actor and the card, once per charge")
	check(_combat.hit(EventsScript.NO_PLAYER, wizard, 5), "the third lands")
	check_equal(wizard.health.health, wizard.health.max_health - 5, "damage")


func test_a_barrier_ends_with_its_time_and_stacks() -> void:
	var wizard := _wizard(1, Vector2.ZERO)
	_combat.give_shield(1, 1, 0.25, 5)
	_combat.give_shield(1, 2, 0.25, 5)
	check_equal(_combat.shield(1), 3, "charges add up")
	_run(1.0)
	check_equal(_combat.shield(1), 0, "the barrier ended")
	check(_combat.hit(EventsScript.NO_PLAYER, wizard, 2), "and no longer blocks")


func test_a_barrier_blocks_a_spell_hit_with_its_status_and_push() -> void:
	var wizard := _wizard(0, Vector2(100.0, 0.0))
	var profile := _profile(2)
	profile.status_id = &"burn"
	profile.status_duration = 2.0
	profile.status_strength = 3.0
	profile.knockback = 100.0
	_combat.give_shield(0, 1, 2.0, 3)
	_bus.projectile_hit.emit(0, wizard, Vector2(90.0, 0.0), _tag(profile), -1)
	check_equal(wizard.health.health, wizard.health.max_health, "no damage")
	check_equal(_combat.status_left(0, &"burn"), 0.0, "no status")
	check_equal(_combat.consume_knockback(_wizards[0], 0.0), Vector2.ZERO, "no push")


func test_burning_goes_through_a_barrier_without_using_it_up() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	_combat.apply_status(0, 0, &"burn", 1.0, 4.0)
	_combat.give_shield(0, 1, 5.0, 3)
	_run(1.0)
	check(wizard.health.health < wizard.health.max_health, "the burn still hurts")
	check_equal(_combat.shield(0), 1, "and the barrier is still there")


# --- Heals ---


func test_a_heal_hit_gives_a_wizard_health_whoever_cast_it() -> void:
	var mate := _wizard(1, Vector2.ZERO)
	_wizard(0, Vector2(500.0, 0.0))
	mate.health.take(30)
	var profile := _profile(1)
	profile.heal = 12
	_bus.projectile_hit.emit(0, mate, Vector2(-5.0, 0.0), _tag(profile), -1)
	check_equal(mate.health.health, mate.health.max_health - 18, "healed 12")
	check_equal(_healed, [[0, mate, 12]], "heal_dealt")
	check_equal(_landed[0][3], &"heal", "kind heal")
	check(_hurt.is_empty(), "a heal hurts nobody")


func test_a_heal_stops_at_full_health_and_skips_the_downed() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	var profile := _profile(1)
	profile.heal = 500
	_bus.projectile_hit.emit(0, wizard, Vector2(-5.0, 0.0), _tag(profile), -1)
	check_equal(wizard.health.health, wizard.health.max_health, "never above the maximum")
	wizard.health.take(1000)
	_healed.clear()
	_bus.projectile_hit.emit(0, wizard, Vector2(-5.0, 0.0), _tag(profile), -1)
	check(_healed.is_empty(), "a downed wizard is not healed")


func test_a_heal_hit_heals_a_teammate() -> void:
	_wizard(0, Vector2.ZERO)
	var mate := _wizard(1, Vector2(10.0, 0.0))
	mate.health.take(20)
	var profile := _profile(1)
	profile.heal = 8
	_bus.projectile_hit.emit(0, mate, Vector2.ZERO, _tag(profile), -1)
	check_equal(mate.health.health, mate.health.max_health - 12, "the teammate was healed")


# --- Pulls and the slam ---


func test_a_pull_draws_enemies_toward_the_point() -> void:
	var enemy := _enemy(Vector2(50.0, 0.0))
	_projectiles.step(STEP)
	_bus.pull_requested.emit(0, Vector2.ZERO, 80.0, 150.0, 1, Vector2.ZERO)
	check_equal(_combat.knockback_of(enemy), Vector2(-150.0, 0.0), "pulled toward the point at the strength")
	_bus.pull_requested.emit(0, Vector2.ZERO, 80.0, 150.0, 1, Vector2.ZERO)
	check_equal(_combat.knockback_of(enemy), Vector2(-150.0, 0.0), "pulling each step does not pile speed up")


func test_a_pull_leaves_actors_out_of_reach_and_moves_wizards_too() -> void:
	var far := _enemy(Vector2(500.0, 0.0))
	_wizard(0, Vector2(20.0, 0.0))
	_projectiles.step(STEP)
	_combat.pull(0, Vector2.ZERO, 80.0, 150.0)
	check_equal(_combat.knockback_of(far), Vector2.ZERO, "out of reach")
	check_equal(_combat.consume_knockback(_wizards[0], 0.0).length(), 150.0, "a wizard is pulled like any actor (actors G5)")


func test_a_pull_event_pulls_enemies_but_not_the_caster_or_a_teammate() -> void:
	var enemy := _enemy(Vector2(50.0, 0.0))
	var caster := _wizard(0, Vector2(20.0, 0.0))
	var mate := _wizard(1, Vector2(0.0, 30.0))
	_projectiles.step(STEP)
	_bus.pull_requested.emit(0, Vector2.ZERO, 80.0, 150.0, 1, Vector2.ZERO)
	check_equal(_combat.knockback_of(enemy), Vector2(-150.0, 0.0), "the enemy is pulled")
	check_equal(_combat.knockback_of(caster), Vector2.ZERO, "the caster is not")
	check_equal(_combat.knockback_of(mate), Vector2.ZERO, "nor is a teammate")


func test_a_pull_event_keeps_a_teammates_push_but_replaces_an_enemys() -> void:
	var enemy := _enemy(Vector2(50.0, 0.0))
	_wizard(0, Vector2(20.0, 0.0))
	var mate := _wizard(1, Vector2(0.0, 30.0))
	_projectiles.step(STEP)
	_combat.pull(1, Vector2(0.0, 500.0), 600.0, 90.0)
	var before: Vector2 = _combat.knockback_of(mate)
	check(before.length() > 0.0, "the teammate has a push to keep")
	_bus.pull_requested.emit(0, Vector2.ZERO, 80.0, 150.0, 1, Vector2.ZERO)
	check_equal(_combat.knockback_of(mate), before, "a teammate's push survives the pull")
	check_equal(_combat.knockback_of(enemy), Vector2(-150.0, 0.0), "an enemy's is replaced")


func test_a_heavy_hit_that_knocks_an_enemy_into_a_wall_hurts_once() -> void:
	_projectiles.set_bounds(Rect2(-200.0, -200.0, 400.0, 400.0))
	_projectiles.set_walls([Rect2(20.0, -20.0, 20.0, 40.0)] as Array[Rect2])
	var enemy := _enemy(Vector2(10.0, 0.0))
	var profile := _profile(3)
	profile.knockback = 300.0
	profile.slam = 7
	_bus.projectile_hit.emit(0, enemy, Vector2(0.0, 0.0), _tag(profile), -1)
	check_equal(_combat.health_of(enemy), 97, "the hit itself")
	_run(STEP)
	check_equal(_combat.health_of(enemy), 90, "the slam into the wall")
	check_equal(_landed[_landed.size() - 1][3], &"reaction", "a slam is told as kind reaction, not a shot")
	_run(STEP * 2.0)
	check_equal(_combat.health_of(enemy), 90, "only once")


func test_an_enemy_killed_by_the_slam_is_not_the_spells_kill() -> void:
	_projectiles.set_bounds(Rect2(-200.0, -200.0, 400.0, 400.0))
	_projectiles.set_walls([Rect2(20.0, -20.0, 20.0, 40.0)] as Array[Rect2])
	var enemy := _enemy(Vector2(10.0, 0.0), 8)
	var deaths: Array = []
	_bus.enemy_died.connect(func(p: int, e: Node, _at: Vector2, _shot: int) -> void: deaths.append([p, e]))
	var profile := _profile(3)
	profile.knockback = 300.0
	profile.slam = 7
	_bus.projectile_hit.emit(0, enemy, Vector2(0.0, 0.0), _tag(profile), -1)
	check(deaths.is_empty(), "the hit itself leaves it alive")
	_run(STEP)
	check_equal(deaths.size(), 1, "the slam killed it")
	check(_kills.is_empty(), "a slam is not the spell's own hit, so no kill_landed")


func test_a_later_plain_hit_disarms_the_slam() -> void:
	_projectiles.set_bounds(Rect2(-200.0, -200.0, 400.0, 400.0))
	_projectiles.set_walls([Rect2(20.0, -20.0, 20.0, 40.0)] as Array[Rect2])
	var enemy := _enemy(Vector2(10.0, 0.0))
	var heavy := _profile(3)
	heavy.knockback = 300.0
	heavy.slam = 7
	var plain := _profile(3)
	plain.knockback = 300.0
	_bus.projectile_hit.emit(0, enemy, Vector2(0.0, 0.0), _tag(heavy), -1)
	_bus.projectile_hit.emit(1, enemy, Vector2(0.0, 0.0), _tag(plain), -1)
	_run(0.5)
	check_equal(_combat.health_of(enemy), 94, "two hits of 3 and no slam damage")


func test_a_heavy_hit_in_the_open_slams_nothing() -> void:
	_projectiles.set_bounds(Rect2(-200.0, -200.0, 400.0, 400.0))
	var enemy := _enemy(Vector2(10.0, 0.0))
	var profile := _profile(3)
	profile.knockback = 300.0
	profile.slam = 7
	_bus.projectile_hit.emit(0, enemy, Vector2.ZERO, _tag(profile), -1)
	_run(0.5)
	check_equal(_combat.health_of(enemy), 97, "no wall, no slam")


# --- Events cards listen to ---


func test_a_kill_names_the_spell_that_landed_it() -> void:
	var enemy := _enemy(Vector2.ZERO, 3)
	var tag: int = _tag(_profile(5))
	_bus.projectile_hit.emit(2, enemy, Vector2(-5.0, 0.0), tag, -1)
	check_equal(_kills, [[2, enemy, tag]], "kill_landed carries the player and the tag")


func test_a_burn_death_is_no_kill_for_a_card() -> void:
	var enemy := _enemy(Vector2.ZERO, 2)
	_combat.apply_status(0, enemy, &"burn", 2.0, 4.0)
	_run(1.0)
	check_equal(_combat.health_of(enemy), -1, "it died")
	check(_kills.is_empty(), "damage over time carries no tag, so it fires no on kill")


func test_a_reaction_names_the_hit_that_set_it_off() -> void:
	var enemy := _enemy(Vector2.ZERO)
	_combat.apply_status(0, enemy, &"burn", 3.0, 2.0)
	var profile := _profile(4)
	profile.element_id = &"frost"
	profile.element_ids = [&"frost"]
	profile.status_id = &"chill"
	profile.status_duration = 3.0
	profile.status_strength = 40.0
	var tag: int = _tag(profile)
	_bus.projectile_hit.emit(1, enemy, Vector2(-5.0, 0.0), tag, -1)
	check_equal(_reactions, [[1, &"thaw", enemy, tag]], "reaction_landed has the player, the reaction, the target and the tag")


# --- The note when a wizard goes down ---


func test_the_note_tells_who_downed_the_wizard() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	_wizard(1, Vector2(500.0, 0.0))
	var profile := _profile(1000, &"burst")
	profile.source_name = "Twice-Thawing Blast"
	var tag: int = _tag(profile)
	_bus.projectile_hit.emit(0, wizard, Vector2(-5.0, 0.0), tag, -1)
	check_equal(_combat.downed_note_of(0), "downed by your own Twice-Thawing Blast", "their own spell, by name")
	var plain := _wizard(2, Vector2(900.0, 0.0))
	_bus.projectile_hit.emit(2, plain, Vector2(895.0, 0.0), _tag(_profile(1000, &"burst")), -1)
	check(plain.is_down(), "downed")
	check_equal(_combat.downed_note_of(2), "downed by your own Blast", "no name: the kind's word")


func test_the_note_names_a_teammate_and_is_empty_for_an_enemy() -> void:
	var wizard := _wizard(1, Vector2.ZERO)
	var profile := _profile(1000)
	profile.source_name = "Frost Nova"
	_bus.projectile_hit.emit(0, wizard, Vector2(-5.0, 0.0), _tag(profile), -1)
	check_equal(_combat.downed_note_of(1), "downed by player 1's Frost Nova", "a teammate's spell")
	var other := _wizard(3, Vector2(900.0, 0.0))
	_bus.projectile_hit.emit(_enemy_caster, other, Vector2(890.0, 0.0), _enemy_tag(_profile(1000)), -1)
	check_equal(_combat.downed_note_of(3), "", "an enemy gets no note")
	check_equal(_combat.downed_note_of(99), "", "an actor Combat does not know gets none")


func test_a_wizard_whose_actor_id_is_not_its_seat_is_named_by_its_actor_id() -> void:
	# Five enemies take the ids 0-4, so the wizards of seats 0-2 are the actors 5-7.
	_actors = own(ActorSeats.table(3, 5)) as ActorSeats.ActorsScript
	_projectiles.actors = _actors
	_combat.actors = _actors
	var wizard := _wizard(0, Vector2.ZERO)
	var mate := _wizard(1, Vector2(500.0, 0.0))
	check_equal([wizard.id, mate.id], [5, 6], "the seats' actors")
	var damage: Array = []
	_bus.damage_dealt.connect(func(p: int, t: Node, a: int, _at: Vector2) -> void: damage.append([p, t, a]))
	var profile := _profile(1000)
	profile.source_name = "Blast"
	var tag: int = _tag(profile, 5)
	_bus.projectile_hit.emit(5, wizard, Vector2(-5.0, 0.0), tag, -1)
	check_equal(_hurt, [[5, 1000, tag, &"shot"]], "actor_hurt names the wizard's actor id, not its seat")
	check_equal(damage, [[5, wizard, 1000]], "damage_dealt names the caster's actor id")
	check_equal(_combat.downed_note_of(wizard), "downed by your own Blast", "its own spell: its actor id is its own")
	var nova := _profile(1000)
	nova.source_name = "Frost Nova"
	_bus.projectile_hit.emit(5, mate, Vector2(495.0, 0.0), _tag(nova, 5), -1)
	check_equal(_combat.downed_note_of(mate), "downed by player 1's Frost Nova", "a teammate's: the seat that drives actor 5")
	_wizard(2, Vector2(900.0, 0.0))
	_bus.wizard_shield_requested.emit(7, 1, 2.0, 3)
	check_equal(_combat.shield(7), 1, "a barrier cast by actor 7 goes to actor 7, the wizard of seat 2")


func test_downing_clears_a_wizards_statuses_and_barrier() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	_combat.apply_status(0, 0, &"hex", 5.0, 50.0)
	_combat.give_shield(0, 2, 5.0, 1)
	_bus.player_downed.emit(0)
	wizard.health.take(0)
	check_equal(_combat.status_left(0, &"hex"), 0.0, "no hex on a downed wizard")
	check_equal(_combat.shield(0), 0, "no barrier either")
