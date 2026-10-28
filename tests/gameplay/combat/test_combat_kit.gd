extends "res://tests/support/suite.gd"
## The combat kit of the staffs (B3, docs/milestones/M2-staffs.md, "Self-harm and hits"): self-harm,
## hit kinds, area hits, several elements per hit, statuses and barriers on wizards, heal hits,
## pulls, the heavy slam, and the events cards listen to (`kill_landed`, `reaction_landed`,
## `wizard_hurt`, `shield_blocked`). Hits arrive as `projectile_hit` and `area_hit_requested` on a
## test bus, with hand-made hit profiles; time moves by `Combat.step` with a fixed delta.
##
## godot --headless --path . --script res://tests/gameplay/combat/test_combat_kit.gd

const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const PlayerScript := preload("res://gameplay/player/player.gd")
const SpellsScript := preload("res://core/spells/spells.gd")

const STEP: float = 0.0625

var _bus: EventsScript
var _projectiles: ManagerScript
var _combat: CombatScript
var _spells: SpellsScript
var _wizards: Array[PlayerScript] = []
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
	_combat = own(CombatScript.new()) as CombatScript
	_combat.events = _bus
	_combat.projectiles = _projectiles
	_spells = own(SpellsScript.new()) as SpellsScript
	_spells.bind(_projectiles, _bus)
	_combat.spells = _spells
	_combat._ready()
	_wizards.clear()
	_next_tag = 0
	for list: Array in [_landed, _hurt, _kills, _reactions, _blocked, _healed, _applied]:
		list.clear()
	_bus.hit_landed.connect(func(p: int, t: Node, a: int, _at: Vector2, k: StringName) -> void: _landed.append([p, t, a, k]))
	_bus.wizard_hurt.connect(func(p: int, a: int, _at: Vector2, tag: int, k: StringName) -> void: _hurt.append([p, a, tag, k]))
	_bus.kill_landed.connect(func(p: int, t: Node, _at: Vector2, tag: int) -> void: _kills.append([p, t, tag]))
	_bus.reaction_landed.connect(func(p: int, id: StringName, t: Node, _at: Vector2, tag: int) -> void: _reactions.append([p, id, t, tag]))
	_bus.shield_blocked.connect(func(p: int, _at: Vector2, tag: int) -> void: _blocked.append([p, tag]))
	_bus.heal_dealt.connect(func(p: int, t: Node, a: int, _at: Vector2) -> void: _healed.append([p, t, a]))
	_bus.status_applied.connect(func(p: int, t: Node, id: StringName) -> void: _applied.append([p, t, id]))


func _wizard(index: int, at: Vector2) -> PlayerScript:
	var wizard := own(PlayerScript.new()) as PlayerScript
	wizard.index = index
	wizard.events = _bus
	wizard._ready()
	wizard.position = at
	_wizards.append(wizard)
	_combat.register_player(index, wizard, 8.0)
	return wizard


func _enemy(at: Vector2, health: int = 100) -> Node2D:
	var enemy := own(Node2D.new()) as Node2D
	enemy.position = at
	root.add_child(enemy)
	_combat.register_enemy(enemy, health, 10.0)
	return enemy


## A spell tag whose hit profile is `profile`.
func _tag(profile: HitProfile) -> int:
	_next_tag += 1
	var tag: int = SpellTag.make(0, 0, _next_tag, 1)
	var spell := CompiledSpell.new()
	spell.hit = profile
	_spells._profiles[tag] = spell
	return tag


## Like `_tag`, for an enemy's spell (its caster row 0).
func _enemy_tag(profile: HitProfile) -> int:
	_next_tag += 1
	var tag: int = SpellTag.make_enemy(0, 0, _next_tag, 1)
	var spell := CompiledSpell.new()
	spell.hit = profile
	_spells._profiles[tag] = spell
	return tag


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
	_bus.projectile_hit.emit(0, wizard, Vector2(90.0, 0.0), tag)
	check_equal(wizard.health, PlayerScript.MAX_HEALTH - 6, "their own shot took health")
	check_equal(_landed, [[0, wizard, 6, &"shot"]], "hit_landed names the caster as both the source and the target")
	check_equal(_hurt, [[0, 6, tag, &"shot"]], "wizard_hurt names the wizard, the damage, the card's tag and the kind")


func test_an_enemys_spell_hurts_a_wizard_with_its_tag_in_wizard_hurt() -> void:
	var wizard := _wizard(1, Vector2.ZERO)
	var tag: int = _enemy_tag(_profile(4))
	_bus.projectile_hit.emit(EventsScript.NO_PLAYER, wizard, Vector2(-5.0, 0.0), tag)
	check_equal(wizard.health, PlayerScript.MAX_HEALTH - 4, "the enemy's spell hurt")
	check_equal(_hurt, [[1, 4, tag, &"shot"]], "wizard_hurt names its tag (its caster row is the enemy's)")
	_bus.projectile_hit.emit(EventsScript.NO_PLAYER, wizard, Vector2(-5.0, 0.0), 9)
	check_equal(wizard.health, PlayerScript.MAX_HEALTH - 4, "a shot with no spell does nothing (staffs F9b: no table)")


func test_a_spell_hit_pushes_the_wizard_it_hurts() -> void:
	var wizard := _wizard(0, Vector2(100.0, 0.0))
	var profile := _profile(2)
	profile.knockback = 200.0
	_bus.projectile_hit.emit(0, wizard, Vector2(90.0, 0.0), _tag(profile))
	check_equal(_combat.consume_wizard_knockback(0, 0.0), Vector2(200.0, 0.0), "pushed away from the hit")
	_combat.consume_wizard_knockback(0, 1.0)
	check_equal(_combat.consume_wizard_knockback(0, 0.0), Vector2.ZERO, "the push fades like an enemy's")


func test_an_enemy_hit_has_the_kind_of_its_profile() -> void:
	var enemy := _enemy(Vector2.ZERO)
	_bus.projectile_hit.emit(0, enemy, Vector2(-5.0, 0.0), _tag(_profile(3, &"ray")))
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
	_bus.projectile_hit.emit(0, enemy, Vector2(195.0, 0.0), _tag(profile))
	var kinds: Array[StringName] = []
	for row: Array in _landed:
		kinds.append(row[3] as StringName)
	check_equal(kinds[0], &"shot", "the shot first")
	check(&"reaction" in kinds, "the thaw's burst is kind reaction")


# --- Area hits ---


func test_an_area_hit_reaches_enemies_the_caster_and_a_teammate() -> void:
	var caster := _wizard(0, Vector2.ZERO)
	var mate := _wizard(1, Vector2(10.0, 0.0))
	var near := _enemy(Vector2(15.0, 0.0))
	var far := _enemy(Vector2(100.0, 0.0))
	_projectiles.step(STEP)
	_bus.area_hit_requested.emit(0, Vector2.ZERO, 30.0, _tag(_profile(5)))
	check_equal(caster.health, PlayerScript.MAX_HEALTH - 5, "the caster is inside their own blast")
	check_equal(mate.health, PlayerScript.MAX_HEALTH - 5, "and so is the teammate: friendly fire is always on (G3c)")
	check_equal(_combat.get_health(near), 95, "the enemy in the circle was hit")
	check_equal(_combat.get_health(far), 100, "the enemy outside was not")
	for row: Array in _landed:
		check_equal(row[3], &"burst", "an area hit is kind burst")


func test_an_area_hit_centred_on_the_caster_hits_at_once_and_pushes_nobody() -> void:
	var caster := _wizard(0, Vector2(50.0, 50.0))
	var profile := _profile(3)
	profile.knockback = 100.0
	_bus.area_hit_requested.emit(0, Vector2(50.0, 50.0), 12.0, _tag(profile))
	check_equal(caster.health, PlayerScript.MAX_HEALTH - 3, "hit at once")
	check_equal(_combat.consume_wizard_knockback(0, 0.0), Vector2.ZERO, "centred: no direction to push")


func test_an_area_hit_without_a_profile_does_nothing() -> void:
	var caster := _wizard(0, Vector2.ZERO)
	_bus.area_hit_requested.emit(0, Vector2.ZERO, 30.0, SpellTag.make(0, 0, 99, 1))
	check_equal(caster.health, PlayerScript.MAX_HEALTH, "unknown tag, no hit")


func test_area_hits_started_by_a_kill_are_cut_at_the_depth_limit() -> void:
	var caster := _wizard(0, Vector2.ZERO)
	var tag: int = _tag(_profile(1))
	var count: Array = [0]
	_bus.hit_landed.connect(func(_p: int, _t: Node, _a: int, _at: Vector2, _k: StringName) -> void:
		count[0] += 1
		if count[0] < 100:
			_bus.area_hit_requested.emit(0, Vector2.ZERO, 30.0, tag))
	_bus.area_hit_requested.emit(0, Vector2.ZERO, 30.0, tag)
	check(count[0] <= CombatScript.AREA_DEPTH + 1, "a chain of area hits stops at AREA_DEPTH")
	check(caster.health > 0, "and the game goes on")


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
	_bus.reaction_triggered.connect(func(_p: int, id: StringName, _at: Vector2) -> void: ids.append(id))
	_bus.projectile_hit.emit(0, enemy, Vector2(-5.0, 0.0), _tag(profile))
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
	_bus.projectile_hit.emit(0, enemy, Vector2(-5.0, 0.0), _tag(profile))
	check_equal(_reactions, [], "fire on fire reacts with nothing")
	check_equal(_combat.status_left(enemy, &"burn"), 3.0, "burning")
	_run(1.0)
	check(_combat.get_health(enemy) <= 100 - 4 - 8, "the second fire's stronger burn won (9 per second)")


func test_the_elements_of_one_hit_chain_their_reactions() -> void:
	var enemy := _enemy(Vector2.ZERO)
	_combat.apply_status(0, enemy, &"burn", 5.0, 0.0001)
	_combat.apply_status(0, enemy, &"hex", 5.0, 10.0)
	var profile := _profile(4)
	profile.element_id = &"frost"
	profile.element_ids = [&"frost", &"fire"]
	var ids: Array[StringName] = []
	_bus.reaction_triggered.connect(func(_p: int, id: StringName, _at: Vector2) -> void: ids.append(id))
	_bus.projectile_hit.emit(0, enemy, Vector2(-5.0, 0.0), _tag(profile))
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
	_bus.projectile_hit.emit(0, _wizards[0], Vector2(-5.0, 0.0), _tag(profile))
	check(_combat.wizard_status_left(0, &"static") > 0.0, "charged")
	check(_combat.wizard_status_left(0, &"shock") > 0.0, "and shocked by the second element")


func test_a_burn_tick_spends_no_shock_and_no_static_and_adds_no_hex() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	var near := _enemy(Vector2(30.0, 0.0))
	_projectiles.step(STEP)
	_combat.apply_wizard_status(0, 0, &"shock", 5.0, 100.0)
	_combat.apply_wizard_status(0, 0, &"static", 5.0, 50.0)
	_combat.apply_wizard_status(0, 0, &"burn", 1.0, 4.0)
	_run(1.0)
	check(_combat.wizard_status_left(0, &"shock") > 0.0, "the shock is still on after the ticks")
	check(_combat.wizard_status_left(0, &"static") > 0.0, "so is the static")
	check_equal(_combat.get_health(near), 100, "no discharge from the wizard's own burn")
	check_equal(wizard.health, PlayerScript.MAX_HEALTH - 4, "the ticks took plain damage, no shock bonus")


func test_a_burn_tick_sends_a_status_hit_kind_that_feel_gives_no_stop() -> void:
	_wizard(0, Vector2.ZERO)
	_combat.apply_wizard_status(0, 0, &"burn", 1.0, 4.0)
	_run(1.0)
	check(not _landed.is_empty(), "ticks are told")
	for row: Array in _landed:
		check_equal(row[3], &"status", "every tick is kind status")


func test_a_shock_jump_kill_is_no_kill_for_a_card() -> void:
	var struck := _enemy(Vector2.ZERO)
	var weak := _enemy(Vector2(30.0, 0.0), 1)
	_projectiles.step(STEP)
	_combat.apply_status(0, struck, &"shock", 5.0, 100.0)
	_bus.projectile_hit.emit(0, struck, Vector2(-5.0, 0.0), _tag(_profile(5)))
	check_equal(_combat.get_health(weak), -1, "the jump killed it")
	check(_kills.is_empty(), "a jump is not the spell's own hit")


func test_burn_on_a_wizard_hurts_over_time_as_kind_status() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	check(_combat.apply_wizard_status(0, 0, &"burn", 1.0, 4.0), "the burn took")
	_run(1.0)
	check(wizard.health <= PlayerScript.MAX_HEALTH - 3, "burn took health")
	check(_hurt.is_empty(), "a burn tick is not a hit: no wizard_hurt for cards")
	check(_landed.size() > 0 and _landed[0][3] == &"status", "ticks are kind status")
	check_equal(_applied[0], [0, wizard, &"burn"], "status_applied names the wizard")
	_run(1.0)
	check_equal(_combat.wizard_status_left(0, &"burn"), 0.0, "and it ends")


func test_three_chills_freeze_a_wizard_and_chill_slows() -> void:
	_wizard(2, Vector2.ZERO)
	_combat.apply_wizard_status(2, 2, &"chill", 3.0, 40.0)
	check_equal(snappedf(_combat.wizard_speed_factor(2), 0.01), 0.6, "a chill takes 40 % of the pace")
	_combat.apply_wizard_status(2, 2, &"chill", 3.0, 40.0)
	_combat.apply_wizard_status(2, 2, &"chill", 3.0, 40.0)
	check_equal(_combat.wizard_speed_factor(2), 0.0, "frozen")
	check(&"freeze" in _applied.map(func(row: Array) -> StringName: return row[2] as StringName), "freeze is announced")
	check_equal(_combat.wizard_speed_factor(0), 1.0, "other wizards move freely")
	_run(1.25)
	check_equal(_combat.wizard_speed_factor(2), 1.0, "the freeze ends")


func test_a_hex_makes_a_wizard_take_more_and_a_shock_is_spent_by_one_hit() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	_combat.apply_wizard_status(0, 0, &"hex", 5.0, 50.0)
	_combat.apply_wizard_status(0, 0, &"shock", 5.0, 100.0)
	check(_combat.hit(EventsScript.NO_PLAYER, wizard, 4), "hit")
	check_equal(wizard.health, PlayerScript.MAX_HEALTH - 12, "4 plus 50 % (hex) plus 100 % of that (shock)")
	check(_combat.hit(EventsScript.NO_PLAYER, wizard, 4), "hit again")
	check_equal(wizard.health, PlayerScript.MAX_HEALTH - 18, "the shock was spent, the hex stays")


func test_a_charged_wizard_discharges_into_enemies_near_on_the_next_hit() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	var near := _enemy(Vector2(30.0, 0.0))
	var far := _enemy(Vector2(300.0, 0.0))
	_projectiles.step(STEP)
	_combat.apply_wizard_status(0, 0, &"static", 5.0, 50.0)
	_combat.hit(EventsScript.NO_PLAYER, wizard, 10)
	check_equal(_combat.get_health(near), 95, "half the hit leaves as lightning")
	check_equal(_combat.get_health(far), 100, "far enemies are left alone")
	_combat.hit(EventsScript.NO_PLAYER, wizard, 10)
	check_equal(_combat.get_health(near), 95, "the charge was spent")


func test_a_downed_wizard_takes_no_status() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	wizard.take_damage(1000)
	check(not _combat.apply_wizard_status(0, 0, &"burn", 1.0, 4.0), "refused")
	check_equal(_combat.wizard_status_left(0, &"burn"), 0.0, "nothing on")


func test_a_spell_hit_puts_its_status_on_the_wizard_it_hurt() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	var profile := _profile(2)
	profile.status_id = &"hex"
	profile.status_duration = 2.0
	profile.status_strength = 40.0
	_bus.projectile_hit.emit(0, wizard, Vector2(-5.0, 0.0), _tag(profile))
	check(_combat.wizard_status_left(0, &"hex") > 0.0, "hexed by their own spell")


# --- Barriers on wizards ---


func test_a_barrier_blocks_hits_one_charge_each() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	_bus.wizard_shield_requested.emit(0, 2, 2.0, 77)
	check_equal(_combat.wizard_shield(0), 2, "two charges")
	check(not _combat.hit(EventsScript.NO_PLAYER, wizard, 5), "the first hit is blocked")
	check(not _combat.hit(EventsScript.NO_PLAYER, wizard, 5), "so is the second")
	check_equal(wizard.health, PlayerScript.MAX_HEALTH, "no damage")
	check_equal(_blocked, [[0, 77], [0, 77]], "shield_blocked names the wizard and the card, once per charge")
	check(_combat.hit(EventsScript.NO_PLAYER, wizard, 5), "the third lands")
	check_equal(wizard.health, PlayerScript.MAX_HEALTH - 5, "damage")


func test_a_barrier_ends_with_its_time_and_stacks() -> void:
	var wizard := _wizard(1, Vector2.ZERO)
	_combat.give_wizard_shield(1, 1, 0.25, 5)
	_combat.give_wizard_shield(1, 2, 0.25, 5)
	check_equal(_combat.wizard_shield(1), 3, "charges add up")
	_run(1.0)
	check_equal(_combat.wizard_shield(1), 0, "the barrier ended")
	check(_combat.hit(EventsScript.NO_PLAYER, wizard, 2), "and no longer blocks")


func test_a_barrier_blocks_a_spell_hit_with_its_status_and_push() -> void:
	var wizard := _wizard(0, Vector2(100.0, 0.0))
	var profile := _profile(2)
	profile.status_id = &"burn"
	profile.status_duration = 2.0
	profile.status_strength = 3.0
	profile.knockback = 100.0
	_combat.give_wizard_shield(0, 1, 2.0, 3)
	_bus.projectile_hit.emit(0, wizard, Vector2(90.0, 0.0), _tag(profile))
	check_equal(wizard.health, PlayerScript.MAX_HEALTH, "no damage")
	check_equal(_combat.wizard_status_left(0, &"burn"), 0.0, "no status")
	check_equal(_combat.consume_wizard_knockback(0, 0.0), Vector2.ZERO, "no push")


func test_burning_goes_through_a_barrier_without_using_it_up() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	_combat.apply_wizard_status(0, 0, &"burn", 1.0, 4.0)
	_combat.give_wizard_shield(0, 1, 5.0, 3)
	_run(1.0)
	check(wizard.health < PlayerScript.MAX_HEALTH, "the burn still hurts")
	check_equal(_combat.wizard_shield(0), 1, "and the barrier is still there")


# --- Heals ---


func test_a_heal_hit_gives_a_wizard_health_whoever_cast_it() -> void:
	var mate := _wizard(1, Vector2.ZERO)
	_wizard(0, Vector2(500.0, 0.0))
	mate.take_damage(30)
	var profile := _profile(1)
	profile.heal = 12
	_bus.projectile_hit.emit(0, mate, Vector2(-5.0, 0.0), _tag(profile))
	check_equal(mate.health, PlayerScript.MAX_HEALTH - 18, "healed 12")
	check_equal(_healed, [[0, mate, 12]], "heal_dealt")
	check_equal(_landed[0][3], &"heal", "kind heal")
	check(_hurt.is_empty(), "a heal hurts nobody")


func test_a_heal_stops_at_full_health_and_skips_the_downed() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	var profile := _profile(1)
	profile.heal = 500
	_bus.projectile_hit.emit(0, wizard, Vector2(-5.0, 0.0), _tag(profile))
	check_equal(wizard.health, PlayerScript.MAX_HEALTH, "never above the maximum")
	wizard.take_damage(1000)
	_healed.clear()
	_bus.projectile_hit.emit(0, wizard, Vector2(-5.0, 0.0), _tag(profile))
	check(_healed.is_empty(), "a downed wizard is not healed")


func test_a_heal_area_reaches_teammates() -> void:
	_wizard(0, Vector2.ZERO)
	var mate := _wizard(1, Vector2(10.0, 0.0))
	mate.take_damage(20)
	var profile := _profile(1)
	profile.heal = 8
	_bus.area_hit_requested.emit(0, Vector2.ZERO, 30.0, _tag(profile))
	check_equal(mate.health, PlayerScript.MAX_HEALTH - 12, "the teammate was healed")


# --- Pulls and the slam ---


func test_a_pull_draws_enemies_toward_the_point() -> void:
	var enemy := _enemy(Vector2(50.0, 0.0))
	_projectiles.step(STEP)
	_bus.pull_requested.emit(0, Vector2.ZERO, 80.0, 150.0, 1)
	check_equal(_combat.get_knockback(enemy), Vector2(-150.0, 0.0), "pulled toward the point at the strength")
	_bus.pull_requested.emit(0, Vector2.ZERO, 80.0, 150.0, 1)
	check_equal(_combat.get_knockback(enemy), Vector2(-150.0, 0.0), "pulling each step does not pile speed up")


func test_a_pull_leaves_enemies_out_of_reach_and_all_wizards_alone() -> void:
	var far := _enemy(Vector2(500.0, 0.0))
	_wizard(0, Vector2(20.0, 0.0))
	_projectiles.step(STEP)
	_bus.pull_requested.emit(0, Vector2.ZERO, 80.0, 150.0, 1)
	check_equal(_combat.get_knockback(far), Vector2.ZERO, "out of reach")
	check_equal(_combat.consume_wizard_knockback(0, 0.0), Vector2.ZERO, "wizards are not pulled")


func test_a_heavy_hit_that_knocks_an_enemy_into_a_wall_hurts_once() -> void:
	_projectiles.set_bounds(Rect2(-200.0, -200.0, 400.0, 400.0))
	_projectiles.set_walls([Rect2(20.0, -20.0, 20.0, 40.0)] as Array[Rect2])
	var enemy := _enemy(Vector2(10.0, 0.0))
	var profile := _profile(3)
	profile.knockback = 300.0
	profile.slam = 7
	_bus.projectile_hit.emit(0, enemy, Vector2(0.0, 0.0), _tag(profile))
	check_equal(_combat.get_health(enemy), 97, "the hit itself")
	_run(STEP)
	check_equal(_combat.get_health(enemy), 90, "the slam into the wall")
	check_equal(_landed[_landed.size() - 1][3], &"reaction", "a slam is told as kind reaction, not a shot")
	_run(STEP * 2.0)
	check_equal(_combat.get_health(enemy), 90, "only once")


func test_an_enemy_killed_by_the_slam_is_not_the_spells_kill() -> void:
	_projectiles.set_bounds(Rect2(-200.0, -200.0, 400.0, 400.0))
	_projectiles.set_walls([Rect2(20.0, -20.0, 20.0, 40.0)] as Array[Rect2])
	var enemy := _enemy(Vector2(10.0, 0.0), 8)
	var deaths: Array = []
	_bus.enemy_died.connect(func(p: int, e: Node, _at: Vector2) -> void: deaths.append([p, e]))
	var profile := _profile(3)
	profile.knockback = 300.0
	profile.slam = 7
	_bus.projectile_hit.emit(0, enemy, Vector2(0.0, 0.0), _tag(profile))
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
	_bus.projectile_hit.emit(0, enemy, Vector2(0.0, 0.0), _tag(heavy))
	_bus.projectile_hit.emit(1, enemy, Vector2(0.0, 0.0), _tag(plain))
	_run(0.5)
	check_equal(_combat.get_health(enemy), 94, "two hits of 3 and no slam damage")


func test_a_heavy_hit_in_the_open_slams_nothing() -> void:
	_projectiles.set_bounds(Rect2(-200.0, -200.0, 400.0, 400.0))
	var enemy := _enemy(Vector2(10.0, 0.0))
	var profile := _profile(3)
	profile.knockback = 300.0
	profile.slam = 7
	_bus.projectile_hit.emit(0, enemy, Vector2.ZERO, _tag(profile))
	_run(0.5)
	check_equal(_combat.get_health(enemy), 97, "no wall, no slam")


# --- Events cards listen to ---


func test_a_kill_names_the_spell_that_landed_it() -> void:
	var enemy := _enemy(Vector2.ZERO, 3)
	var tag: int = _tag(_profile(5))
	_bus.projectile_hit.emit(2, enemy, Vector2(-5.0, 0.0), tag)
	check_equal(_kills, [[2, enemy, tag]], "kill_landed carries the player and the tag")


func test_a_burn_death_is_no_kill_for_a_card() -> void:
	var enemy := _enemy(Vector2.ZERO, 2)
	_combat.apply_status(0, enemy, &"burn", 2.0, 4.0)
	_run(1.0)
	check_equal(_combat.get_health(enemy), -1, "it died")
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
	_bus.projectile_hit.emit(1, enemy, Vector2(-5.0, 0.0), tag)
	check_equal(_reactions, [[1, &"thaw", enemy, tag]], "reaction_landed has the player, the reaction, the target and the tag")


# --- The note when a wizard goes down ---


func test_the_note_tells_who_downed_the_wizard() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	_wizard(1, Vector2(500.0, 0.0))
	var profile := _profile(1000, &"burst")
	profile.source_name = "Twice-Thawing Blast"
	var tag: int = _tag(profile)
	_bus.projectile_hit.emit(0, wizard, Vector2(-5.0, 0.0), tag)
	check_equal(_combat.downed_note(0), "downed by your own Twice-Thawing Blast", "their own spell, by name")
	var plain := _wizard(2, Vector2(900.0, 0.0))
	_bus.area_hit_requested.emit(2, Vector2(900.0, 0.0), 20.0, _tag(_profile(1000, &"burst")))
	check(plain.is_downed(), "downed")
	check_equal(_combat.downed_note(2), "downed by your own Blast", "no name: the kind's word")


func test_the_note_names_a_teammate_and_is_empty_for_an_enemy() -> void:
	var wizard := _wizard(1, Vector2.ZERO)
	var profile := _profile(1000)
	profile.source_name = "Frost Nova"
	_bus.projectile_hit.emit(0, wizard, Vector2(-5.0, 0.0), _tag(profile))
	check_equal(_combat.downed_note(1), "downed by player 1's Frost Nova", "a teammate's spell")
	var other := _wizard(3, Vector2(900.0, 0.0))
	_bus.projectile_hit.emit(EventsScript.NO_PLAYER, other, Vector2(890.0, 0.0), _enemy_tag(_profile(1000)))
	check_equal(_combat.downed_note(3), "", "an enemy gets no note")
	check_equal(_combat.downed_note(7), "", "a bad index gets none")


func test_downing_clears_a_wizards_statuses_and_barrier() -> void:
	var wizard := _wizard(0, Vector2.ZERO)
	_combat.apply_wizard_status(0, 0, &"hex", 5.0, 50.0)
	_combat.give_wizard_shield(0, 2, 5.0, 1)
	_bus.player_downed.emit(0)
	wizard.take_damage(0)
	check_equal(_combat.wizard_status_left(0, &"hex"), 0.0, "no hex on a downed wizard")
	check_equal(_combat.wizard_shield(0), 0, "no barrier either")
