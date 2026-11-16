extends "res://tests/support/suite.gd"
## Actor stats (boss plan OB7, docs/milestones/boss-old-broom.md, "Actor stats"): every actor has a
## `Stats`, its own copy of its `ActorStats` (the defaults leave the game as it is); power is read
## at the hit from the caster's body (its slam and its burn too, never contact or a plain hit), and
## a reused id is never read; mass divides a shove; resist shortens a status (a freeze as a chill)
## and a possession; spell scale is built into the body's spells, a swing's reach too. Test
## numbers only: no content's stats are named here (decision 28).
const Fixture := preload("res://tests/gameplay/actor/actor_fixture.gd")
const CombatScript := preload("res://gameplay/combat/combat.gd")

var _world: Fixture


func before_each() -> void:
	_world = Fixture.new(root)


func after_each() -> void:
	_world.free_all()


func _stats(power: float = 1.0, mass: float = 1.0, spell_scale: float = 1.0) -> ActorStats:
	var stats := ActorStats.new()
	stats.power = power
	stats.mass = mass
	stats.spell_scale = spell_scale
	return stats


## A body that can be hurt at `at`, driven (so it is stepped), with the most health.
func _target(at: Vector2 = Vector2(60.0, 0.0)) -> Actor:
	var body: Actor = _world.actor(at, [&"health", &"hurtbox", &"mover"], Fixture.Scripted.new())
	body.health.max_health = 1000.0
	body.health.reset(1000.0)
	body.downable = true
	return body


## A caster of `cards` on staff 0, of `stats`.
func _caster(cards: Array[StringName], stats: ActorStats = null, at: Vector2 = Vector2.ZERO) -> Actor:
	var body := Actor.new()
	body.name = "Caster%d" % _world.actors.size()
	var own := Stats.new()
	own.base = stats
	body.add_child(own)
	var caster := Caster.new()
	caster.start_cards = [cards]
	body.add_child(caster)
	body.add_child(Fixture.Scripted.new())
	return _world.add(body, at)


## The tag of the first spell of `body`'s staff 0 as built now.
func _tag(body: Actor) -> int:
	return SpellTag.make(body.id, 0, 0, _world.spells._current[body.id * SpellLimits.STAFFS])


## The damage `body` takes from one hit of `by`'s spell `tag`.
func _hit_by(by: int, tag: int, body: Actor) -> float:
	var before: float = body.health.health
	_world.bus.projectile_hit.emit(by, body, body.global_position, tag, -1)
	return before - body.health.health


func test_every_actor_has_stats_that_change_nothing() -> void:
	var body: Actor = _target()
	check(body.stats != null, "an actor with none in its scene is given one")
	check_equal(body.stats.power, 1.0, "power 1")
	check_equal(body.stats.mass, 1.0, "mass 1")
	check_equal(body.stats.spell_scale, 1.0, "spell scale 1")
	check_equal(body.stats.resist.size(), Stats.RESIST_COUNT, "a share for each of Combat's statuses and possess")
	check_equal(body.stats.resist.count(0.0), Stats.RESIST_COUNT, "resisting nothing")
	check(body.stats.at_rest(), "as its data made it")
	check_equal(ActorStats.new().problems(), PackedStringArray(), "the defaults are sound")
	var bad: ActorStats = _stats(-1.0, 0.0, 0.0)
	bad.resist_hex = 1.5
	check_equal(bad.problems().size(), 4, "a power below 0, a mass and a spell scale of 0, a share above 1")


func test_the_data_gives_the_stats() -> void:
	var data := EnemyBase.new()
	data.id = &"test_heavy"
	data.max_health = 10.0
	data.stats = _stats(2.0, 3.0)
	data.stats.resist_chill = 0.5
	var body := Actor.new()
	body.data = data
	body.add_child(Health.new())
	_world.add(body, Vector2.ZERO)
	check_equal(body.stats.power, 2.0, "its enemy data's power")
	check_equal(body.stats.mass, 3.0, "and mass")
	check_equal(body.stats.resist_of(CombatScript.ST_CHILL), 0.5, "a chill resisted by half")
	check_equal(body.stats.resist_of(CombatScript.ST_FREEZE), 0.5, "a freeze as a chill")
	check_equal(data.stats.power, 2.0, "the shared data is left alone")
	body.stats.power = 4.0
	check_equal(data.stats.power, 2.0, "a change is the body's own")
	check(not body.stats.at_rest(), "and it is no longer as its data made it")


func test_power_scales_a_spell_hit_read_at_the_hit() -> void:
	var caster: Actor = _caster([&"bolt"])
	var target: Actor = _target()
	var tag: int = _tag(caster)
	var plain: float = _hit_by(caster.id, tag, target)
	check(plain > 0.0, "a bolt hurts")
	caster.stats.power = 2.0
	check(is_equal_approx(_hit_by(caster.id, tag, target), plain * 2.0), "power 2: twice the hit, read at the hit (the build is shared)")
	var before: float = target.health.health
	_world.combat.hit(caster.id, target, 5.0)
	check(is_equal_approx(before - target.health.health, 5.0), "a plain hit (contact, a reaction) is not scaled")


## Cast `body`'s staff 0 to the right and step once, so its shot is in the air.
func _fire(body: Actor) -> void:
	body.aim = Vector2.RIGHT
	check(body.caster.cast(0), "%s casts" % body.name)
	_world.run(1)


## Step until `body` is hit (60 steps at most); the damage it took.
func _until_hit(body: Actor) -> float:
	var before: float = body.health.health
	for i in 60:
		_world.run(1)
		if body.health.health < before:
			break
	return before - body.health.health


func test_a_gone_caster_and_a_reused_id_hit_at_one() -> void:
	var target: Actor = _target(Vector2(120.0, 0.0))
	var caster: Actor = _caster([&"bolt"], _stats(3.0))
	var id: int = caster.id
	var plain: float = _world.spells.hit_profile(_tag(caster)).damage
	_fire(caster)
	check(is_equal_approx(_until_hit(target), plain * 3.0), "power 3 while its caster stands")
	var gone: Actor = _caster([&"bolt"], _stats(3.0), Vector2(0.0, 200.0))
	var its_target: Actor = _target(Vector2(120.0, 200.0))
	_fire(gone)
	_world.actors.erase(gone)
	gone.free()
	check(is_equal_approx(_until_hit(its_target), plain), "a shot whose caster is gone hits at 1")
	_world.actors.erase(caster)
	caster.free()
	var old: Actor = _caster([&"bolt"], _stats(3.0))
	check_equal(old.id, id, "(the id is free again)")
	_fire(old)
	_world.actors.erase(old)
	old.free()
	var again: Actor = _caster([&"bolt"], _stats(5.0), Vector2(0.0, 100.0))
	check_equal(again.id, id, "a new body takes the id while the old shot flies")
	check(is_equal_approx(_until_hit(target), plain), "the old shot is never read as the new body's")
	check(is_equal_approx(_hit_by(id, _tag(again), target), plain * 5.0), "its own hits at its power")


func test_power_scales_the_burn_its_hit_puts_on() -> void:
	var caster: Actor = _caster([&"fire", &"bolt"])
	var target: Actor = _target()
	var tag: int = _tag(caster)
	var burns: Array[float] = []
	for power: float in [1.0, 2.0]:
		caster.stats.power = power
		_hit_by(caster.id, tag, target)
		var before: float = target.health.health
		for i in 16:
			_world.combat.step(0.0625)
		burns.append(before - target.health.health)
		_world.combat._remove_status(_world.combat._row_of(target), CombatScript.BURN)
	check(burns[0] > 0.0, "a fire bolt burns")
	check(is_equal_approx(burns[1], burns[0] * 2.0), "power 2 burns twice as hard: %s" % [burns])


func test_power_scales_a_heavy_slam() -> void:
	var profile := HitProfile.new()
	profile.slam = 5
	check_equal(CombatScript._slam_of(profile, 10.0, 0.0), 5, "a heavy hit's own slam at power 1")
	check_equal(CombatScript._slam_of(profile, 20.0, 0.0, 2.0), 10, "twice it at power 2")


func test_mass_divides_a_shove() -> void:
	var light: Actor = _target(Vector2(60.0, 0.0))
	var heavy: Actor = _target(Vector2(-60.0, 0.0))
	heavy.stats.mass = 4.0
	_world.combat.hit(-1, light, 1.0, Vector2.RIGHT, 200.0)
	_world.combat.hit(-1, heavy, 1.0, Vector2.RIGHT, 200.0)
	check(is_equal_approx(_world.combat.knockback_of(light).x, 200.0), "mass 1: the whole shove")
	check(is_equal_approx(_world.combat.knockback_of(heavy).x, 50.0), "mass 4: a quarter of it")
	_world.combat.pull(-1, Vector2.ZERO, 200.0, 120.0)
	check(is_equal_approx(_world.combat.knockback_of(heavy).length(), 30.0), "a pull too")


func test_resist_shortens_a_status_and_a_freeze() -> void:
	var body: Actor = _target()
	body.stats.resist[CombatScript.ST_BURN] = 0.25
	body.stats.resist[CombatScript.ST_HEX] = 1.0
	body.stats.resist[CombatScript.ST_CHILL] = 0.5
	check(_world.combat.apply_status(-1, body, CombatScript.BURN, 4.0, 1.0), "a burn takes")
	check(is_equal_approx(_world.combat.status_left(body, CombatScript.BURN), 3.0), "for three quarters of its time")
	check(not _world.combat.apply_status(-1, body, CombatScript.HEX, 4.0, 10.0), "a share of 1 never takes it")
	for i in CombatScript.CHILL_STACKS_TO_FREEZE - 1:
		_world.combat.apply_status(-1, body, CombatScript.CHILL, 2.0, 30.0)
	check(is_equal_approx(_world.combat.status_left(body, CombatScript.CHILL), 1.0), "a chill for half its time")
	_world.combat.apply_status(-1, body, CombatScript.CHILL, 2.0, 30.0)
	check(is_equal_approx(_world.combat.status_left(body, CombatScript.FREEZE), CombatScript.FREEZE_TIME * 0.5), "three chills freeze it for half the time")
	check_equal(body.stats.resist_of(CombatScript.ST_FREEZE), 0.5, "a freeze is read as the chill's share")
	var plain: Actor = _target(Vector2(0.0, 80.0))
	_world.combat.apply_status(-1, plain, CombatScript.BURN, 4.0, 1.0)
	check(is_equal_approx(_world.combat.status_left(plain, CombatScript.BURN), 4.0), "a body resisting nothing takes it whole")


func test_resist_shortens_a_possession() -> void:
	var by: Actor = _target(Vector2(-60.0, 0.0))
	var body: Actor = _target()
	body.stats.resist[Stats.POSSESS] = 0.75
	var possession: Possession = Possession.begin(by, body, 4.0)
	check(possession != null, "it is possessed")
	check(is_equal_approx(possession.seconds, 1.0), "for a quarter of the time")
	possession.end()
	body.stats.resist[Stats.POSSESS] = 1.0
	check(Possession.begin(by, body, 4.0) == null, "a share of 1 is never possessed")


func test_spell_scale_grows_the_body_s_spells() -> void:
	var plain: Actor = _caster([&"bolt"])
	var big: Actor = _caster([&"bolt"], _stats(1.0, 1.0, 2.0), Vector2(0.0, 100.0))
	var radius: float = _world.spells.carrier_radius(_tag(plain))
	check(radius > 0.0, "a bolt has a size")
	check(is_equal_approx(_world.spells.carrier_radius(_tag(big)), radius * 2.0), "spell scale 2: twice the radius")
	check(is_equal_approx(_world.spells.hit_profile(_tag(big)).damage, _world.spells.hit_profile(_tag(plain)).damage), "no more damage")
	var swing: Actor = _caster([&"swing"], _stats(1.0, 1.0, 1.5), Vector2(0.0, 200.0))
	var plain_swing: Actor = _caster([&"swing"], null, Vector2(0.0, 300.0))
	check(is_equal_approx(_world.spells.carrier_reach(_tag(swing)), _world.spells.carrier_reach(_tag(plain_swing)) * 1.5), "a swing's reach is its size")
	big.stats.spell_scale = 1.0
	big.caster.rebuild()
	check(is_equal_approx(_world.spells.carrier_radius(_tag(big)), radius), "built again at its new scale")


func test_resist_shortens_what_a_reaction_adds() -> void:
	# A review found an extending reaction (lightning on a chill freezes) skipped the resist.
	var body: Actor = _target()
	body.stats.resist[CombatScript.ST_CHILL] = 0.5
	body.stats.resist[CombatScript.ST_BURN] = 0.75
	var row: int = _world.combat._row_of(body)
	var freeze := ReactionRow.new()
	freeze.status_id = CombatScript.CHILL
	freeze.duration = 2.0
	_world.combat._extend(-1, row, freeze)
	check(is_equal_approx(_world.combat.status_left(body, CombatScript.FREEZE), 1.0), "a reaction's freeze for half its time")
	_world.combat.apply_status(-1, body, CombatScript.BURN, 4.0, 1.0)
	var longer := ReactionRow.new()
	longer.status_id = CombatScript.BURN
	longer.duration = 4.0
	_world.combat._extend(-1, row, longer)
	check(is_equal_approx(_world.combat.status_left(body, CombatScript.BURN), 2.0), "a reaction's longer burn a quarter as long more")


func test_spell_scale_grows_a_pulse_s_ring_and_a_blast() -> void:
	var plain: Actor = _caster([&"pulse"])
	var big: Actor = _caster([&"pulse"], _stats(1.0, 1.0, 2.0), Vector2(0.0, 100.0))
	check(is_equal_approx(_world.spells.carrier_reach(_tag(big)), _world.spells.carrier_reach(_tag(plain)) * 2.0), "a pulse's ring reaches twice as far")
	var blast: int = ModifierBase.Behaviour.BLAST
	var plain_bolt: Actor = _caster([&"blast", &"bolt"], null, Vector2(0.0, 200.0))
	var big_bolt: Actor = _caster([&"blast", &"bolt"], _stats(1.0, 1.0, 2.0), Vector2(0.0, 300.0))
	var plain_blast: float = _world.spells.profile(_tag(plain_bolt)).behaviour(blast)
	check(plain_blast > 0.0, "a blast has a radius")
	check(is_equal_approx(_world.spells.profile(_tag(big_bolt)).behaviour(blast), plain_blast * 2.0), "twice as wide on a body of spell scale 2")
