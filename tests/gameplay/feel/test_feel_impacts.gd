extends "res://tests/support/suite.gd"
## Hit and wall impacts in gameplay/feel: a shot that hits a character sprays along the way
## it flew, in the colour of what was hit and a little bigger for more damage; a shot that
## ends on a wall throws stone chips back and a spark in the shot's colour. Both stay inside
## the particle limit and the pools, with four players.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const WizardStandIn := preload("res://tests/gameplay/feel/fixtures/wizard_stand_in.gd")

const STEP: float = 0.0625

var bus: EventsScript
var feel: FeelScript
var preset: FeelPresetScript


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	feel = own(FeelScript.new()) as FeelScript
	preset = FeelPresetScript.new()
	preset.hit_sound = &""
	preset.death_sound = &""
	preset.downed_sound = &""
	feel.events = bus
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)


## The live bursts, which are the visible CPUParticles2D children of Feel.
func _live_bursts() -> Array[CPUParticles2D]:
	var found: Array[CPUParticles2D] = []
	for child in feel.get_children():
		var burst: CPUParticles2D = child as CPUParticles2D
		if burst != null and burst.visible:
			found.append(burst)
	return found


func _enemy() -> Node2D:
	var enemy: Node2D = own(Node2D.new()) as Node2D
	root.add_child(enemy)
	return enemy


func _wizard(index: int) -> Node2D:
	var wizard: Node2D = own(WizardStandIn.new()) as Node2D
	wizard.set("index", index)
	root.add_child(wizard)
	return wizard


## What the manager sends for one hit: the impact, then the damage (combat's answer).
func _strike(player: int, target: Node, at: Vector2, direction: Vector2, damage: int) -> void:
	bus.projectile_impact.emit(player, target, at, direction)
	bus.damage_dealt.emit(player, target, damage, target.global_position if target is Node2D else at)


func test_a_hit_sprays_along_the_shot_from_where_it_struck() -> void:
	var enemy: Node2D = _enemy()
	enemy.global_position = Vector2(100.0, 50.0)
	_strike(0, enemy, Vector2(92.0, 50.0), Vector2.RIGHT, 5)
	var bursts: Array[CPUParticles2D] = _live_bursts()
	check_equal(bursts.size(), 1, "one burst")
	if bursts.is_empty():
		return
	check(bursts[0].direction.is_equal_approx(Vector2.RIGHT), "along the shot")
	check_equal(bursts[0].spread, preset.hit_spray_spread, "a narrow cone, not a ring")
	check(bursts[0].global_position.is_equal_approx(Vector2(92.0, 50.0)), "from the point it struck")


func test_a_spray_is_aimed_the_way_the_shot_flew_for_every_player() -> void:
	for player in 4:
		var enemy: Node2D = _enemy()
		var aim: Vector2 = Vector2.from_angle(float(player) * 1.3)
		_strike(player, enemy, Vector2.ZERO, aim, 5)
		var bursts: Array[CPUParticles2D] = _live_bursts()
		check(not bursts.is_empty() and bursts.back().direction.is_equal_approx(aim), "player %d's spray follows the shot" % player)
		for step in 8:
			feel.step(STEP)


func test_an_enemy_is_hit_in_ember() -> void:
	_strike(1, _enemy(), Vector2.ZERO, Vector2.RIGHT, 5)
	var bursts: Array[CPUParticles2D] = _live_bursts()
	check(not bursts.is_empty() and bursts[0].color == preset.enemy_hit_color, "ember")


func test_a_wizard_is_hit_in_its_own_colour() -> void:
	for index in 4:
		for step in 8:
			feel.step(STEP)
		_strike(EventsScript.NO_PLAYER, _wizard(index), Vector2.ZERO, Vector2.LEFT, 5)
		var bursts: Array[CPUParticles2D] = _live_bursts()
		check(not bursts.is_empty() and bursts[0].color == FeelScript.PLAYER_COLORS[index], "wizard %d is hit in its own colour" % index)


func test_more_damage_is_a_bigger_spray() -> void:
	_strike(0, _enemy(), Vector2.ZERO, Vector2.RIGHT, 2)
	_strike(0, _enemy(), Vector2.ZERO, Vector2.RIGHT, 12)
	var bursts: Array[CPUParticles2D] = _live_bursts()
	check_equal(bursts.size(), 2, "two bursts")
	if bursts.size() == 2:
		# The pool hands bursts out in no fixed order, so compare the two ends.
		var slow: CPUParticles2D = bursts[0] if bursts[0].lifetime < bursts[1].lifetime else bursts[1]
		var big: CPUParticles2D = bursts[1] if slow == bursts[0] else bursts[0]
		check(big.lifetime > slow.lifetime, "longer lived")
		check(big.initial_velocity_max > slow.initial_velocity_max, "faster")
		check(is_equal_approx(big.lifetime, preset.particle_lifetime * (1.0 + 7.0 * preset.hit_spray_per_damage)), "12 damage is 7 points over the bolt's 5")


func test_the_spray_size_is_bounded() -> void:
	_strike(0, _enemy(), Vector2.ZERO, Vector2.RIGHT, 100000)
	var bursts: Array[CPUParticles2D] = _live_bursts()
	check(not bursts.is_empty() and bursts[0].lifetime <= preset.particle_lifetime * FeelScript.SPRAY_MAX_SIZE + 0.001, "a huge hit is not a huge spray")


func test_damage_without_an_impact_is_still_a_round_puff() -> void:
	bus.damage_dealt.emit(0, null, 5, Vector2(5.0, 5.0))
	var bursts: Array[CPUParticles2D] = _live_bursts()
	check(not bursts.is_empty() and bursts[0].spread == 180.0, "no shot, no direction")


func test_an_impact_is_used_once_and_only_for_its_target() -> void:
	var first: Node2D = _enemy()
	var second: Node2D = _enemy()
	bus.projectile_impact.emit(0, first, Vector2.ZERO, Vector2.RIGHT)
	bus.damage_dealt.emit(0, second, 5, Vector2.ZERO)
	var bursts: Array[CPUParticles2D] = _live_bursts()
	check(not bursts.is_empty() and bursts[0].spread == 180.0, "another target's damage does not take the shot's direction")


func test_a_killing_blow_keeps_one_burst_and_the_colour() -> void:
	var enemy: Node2D = _enemy()
	_strike(0, enemy, Vector2.ZERO, Vector2.RIGHT, 5)
	bus.enemy_died.emit(0, enemy, enemy.global_position)
	var bursts: Array[CPUParticles2D] = _live_bursts()
	check_equal(bursts.size(), 1, "the kill makes the hit's burst bigger, not a second one")
	check(not bursts.is_empty() and bursts[0].color == preset.enemy_hit_color, "still ember")


func test_sprays_stay_inside_the_particle_limit_with_four_players() -> void:
	for frame in 20:
		for player in 4:
			for shot in 4:
				_strike(player, _enemy(), Vector2(float(shot) * 9.0, float(player) * 9.0), Vector2.RIGHT, 5)
		feel.step(STEP / 4.0)
		check(feel.live_particles() <= FeelScript.PARTICLE_LIMIT, "within PARTICLE_LIMIT (frame %d)" % frame)


func test_a_wall_hit_throws_chips_back_off_the_wall() -> void:
	bus.projectile_impact.emit(0, null, Vector2(96.0, 100.0), Vector2.RIGHT)
	var bursts: Array[CPUParticles2D] = _live_bursts()
	check_equal(bursts.size(), 1, "one burst of chips")
	if bursts.is_empty():
		return
	check(bursts[0].direction.is_equal_approx(Vector2.LEFT), "back the way the shot came")
	check_equal(bursts[0].color, preset.wall_chip_color, "stone coloured")
	check(bursts[0].global_position.is_equal_approx(Vector2(96.0, 100.0)), "at the wall")


func test_a_wall_hit_shows_a_spark_in_the_shot_colour() -> void:
	for player in 4:
		bus.projectile_impact.emit(player, null, Vector2(10.0 * float(player), 0.0), Vector2.UP)
	check_equal(feel.live_flashes(), 4, "four sparks")
	for player in 4:
		check_equal(feel.wall_spark(player).modulate, FeelScript.PLAYER_COLORS[player], "spark %d has its player's colour" % player)


func test_an_enemy_shot_on_a_wall_is_ember() -> void:
	bus.projectile_impact.emit(EventsScript.NO_PLAYER, null, Vector2.ZERO, Vector2.UP)
	check_equal(feel.wall_spark(0).modulate, preset.enemy_hit_color, "an enemy shot's spark")


func test_wall_sparks_are_limited_and_end() -> void:
	for i in 30:
		bus.projectile_impact.emit(i % 4, null, Vector2(float(i), 0.0), Vector2.UP)
	check(feel.live_flashes() <= FeelScript.SPARK_SLOTS, "no more sparks than slots")
	for i in 4:
		feel.step(STEP)
	check_equal(feel.live_flashes(), 0, "the sparks end")


func test_wall_dust_never_takes_the_bursts_hits_need() -> void:
	for i in 40:
		bus.projectile_impact.emit(i % 4, null, Vector2(float(i), 0.0), Vector2.UP)
	check(feel.live_particles() <= FeelScript.PARTICLE_LIMIT - FeelScript.WALL_RESERVE * FeelScript.BURST_PARTICLES, "walls stop at the reserve")
	_strike(0, _enemy(), Vector2.ZERO, Vector2.RIGHT, 5)
	_strike(1, _enemy(), Vector2.ZERO, Vector2.RIGHT, 5)
	check_equal(feel.live_particles(), FeelScript.PARTICLE_LIMIT, "two hits on characters still get their bursts")


func test_wall_dust_and_chips_come_back_to_the_pool() -> void:
	for i in 10:
		bus.projectile_impact.emit(0, null, Vector2.ZERO, Vector2.UP)
	for i in 10:
		feel.step(STEP)
	check_equal(feel.live_particles(), 0, "finished bursts return")
