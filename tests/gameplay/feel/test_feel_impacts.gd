extends "res://tests/support/suite.gd"
## Hit and wall impacts in gameplay/feel (the glow look: all effects): a shot that hits a
## character sprays along the way it flew, in the colours of what was hit and a little bigger
## for more damage; a shot that ends on a wall knocks stone chips back and lands in a burst in
## its colours. Everything stays inside the effect slots, with four players.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const WizardStandIn := preload("res://tests/gameplay/feel/fixtures/wizard_stand_in.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

const STEP: float = 0.0625

var bus: EventsScript
var feel: FeelScript
var preset: FeelPresetScript
## Wizards seated 0-3 at the actor ids 0-3, so caster 0-3 shows in hat ramp 0-3.
var actors: ActorSeats.ActorsScript


func before_each() -> void:
	bus = own(EventsScript.new()) as EventsScript
	feel = own(FeelScript.new()) as FeelScript
	preset = FeelPresetScript.new()
	preset.hit_sound = &""
	preset.death_sound = &""
	preset.downed_sound = &""
	feel.events = bus
	actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	feel.actors = actors
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)


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
	check_equal(feel.effects_of(FeelScript.KIND_SPRAY), 1, "one spray")
	var spray: Dictionary = feel.effect_info(FeelScript.KIND_SPRAY)
	check((spray["dir"] as Vector2).is_equal_approx(Vector2.RIGHT), "along the shot")
	check((spray["at"] as Vector2).is_equal_approx(Vector2(92.0, 50.0)), "from the point it struck")
	check_equal(feel.effects_of(FeelScript.KIND_PUFF), 0, "a spray, not a puff all round")


func test_a_spray_is_aimed_the_way_the_shot_flew_for_every_player() -> void:
	for player in 4:
		var aim: Vector2 = Vector2.from_angle(float(player) * 1.3)
		_strike(player, _enemy(), Vector2.ZERO, aim, 5)
		check((feel.effect_info(FeelScript.KIND_SPRAY)["dir"] as Vector2).is_equal_approx(aim), "player %d's spray follows the shot" % player)


func test_an_enemy_is_hit_in_ember() -> void:
	_strike(1, _enemy(), Vector2.ZERO, Vector2.RIGHT, 5)
	check_equal(feel.effect_info(FeelScript.KIND_SPRAY)["core"], preset.enemy_hit_color, "ember")


func test_a_wizard_is_hit_in_its_own_colours() -> void:
	for index in 4:
		_strike(EventsScript.NO_PLAYER, _wizard(index), Vector2.ZERO, Vector2.LEFT, 5)
		var spray: Dictionary = feel.effect_info(FeelScript.KIND_SPRAY)
		check(spray["core"] == Color.WHITE and spray["ramp"] == index, "wizard %d is hit in its own ramp" % index)


func test_more_damage_is_a_bigger_spray() -> void:
	_strike(0, _enemy(), Vector2.ZERO, Vector2.RIGHT, 2)
	check_equal(feel.effect_info(FeelScript.KIND_SPRAY)["zoom"], 1, "a small hit is the small spray")
	_strike(0, _enemy(), Vector2.ZERO, Vector2.RIGHT, 30)
	check_equal(feel.effect_info(FeelScript.KIND_SPRAY)["zoom"], 2, "a big hit a bigger one")


func test_the_spray_size_is_bounded() -> void:
	_strike(0, _enemy(), Vector2.ZERO, Vector2.RIGHT, 100000)
	check((feel.effect_info(FeelScript.KIND_SPRAY)["zoom"] as int) <= roundi(FeelScript.SPRAY_MAX_SIZE), "a huge hit is not a huge spray")


func test_damage_without_an_impact_is_a_puff() -> void:
	bus.damage_dealt.emit(0, null, 5, Vector2(5.0, 5.0))
	check_equal(feel.effects_of(FeelScript.KIND_PUFF), 1, "no shot, no way: a puff all round")
	check((feel.effect_info(FeelScript.KIND_PUFF)["at"] as Vector2).is_equal_approx(Vector2(5.0, 5.0)), "where it was hit")


func test_an_impact_is_used_once_and_only_for_its_target() -> void:
	var first: Node2D = _enemy()
	var second: Node2D = _enemy()
	bus.projectile_impact.emit(0, first, Vector2.ZERO, Vector2.RIGHT)
	bus.damage_dealt.emit(0, second, 5, Vector2.ZERO)
	check_equal(feel.effects_of(FeelScript.KIND_SPRAY), 0, "another target's damage does not take the shot's way")
	check_equal(feel.effects_of(FeelScript.KIND_PUFF), 1, "it is a puff")


func test_a_killing_blow_keeps_one_effect_and_the_colour() -> void:
	var enemy: Node2D = _enemy()
	_strike(0, enemy, Vector2.ZERO, Vector2.RIGHT, 5)
	bus.enemy_died.emit(0, enemy, enemy.global_position)
	check_equal(feel.effects_of(FeelScript.KIND_SPRAY), 0, "the kill turns the hit's spray")
	check_equal(feel.effects_of(FeelScript.KIND_PUFF), 1, "into one bigger puff, not a second effect")
	check_equal(feel.effect_info(FeelScript.KIND_PUFF)["core"], preset.enemy_hit_color, "still ember")


func test_sprays_stay_inside_the_effect_slots_with_four_players() -> void:
	feel.set_effect_slots(EffectSlots.MIN)
	for frame in 20:
		for player in 4:
			for shot in 4:
				_strike(player, _enemy(), Vector2(float(shot) * 9.0, float(player) * 9.0), Vector2.RIGHT, 5)
		feel.step(STEP / 4.0)
		check(feel.live_effects() <= feel.effect_slots, "within the effect slots (frame %d)" % frame)


func test_a_wall_hit_knocks_chips_back_off_the_wall() -> void:
	bus.projectile_impact.emit(0, null, Vector2(96.0, 100.0), Vector2.RIGHT)
	check_equal(feel.effects_of(FeelScript.KIND_CHIPS), 1, "one spray of chips")
	var chips: Dictionary = feel.effect_info(FeelScript.KIND_CHIPS)
	check((chips["dir"] as Vector2).is_equal_approx(Vector2.LEFT), "back the way the shot came")
	check((chips["at"] as Vector2).is_equal_approx(Vector2(96.0, 100.0)), "at the wall")


func test_a_wall_hit_shows_an_effect_in_its_casters_ramp() -> void:
	for player in 4:
		bus.projectile_impact.emit(player, null, Vector2(10.0 * float(player), 0.0), Vector2.UP)
	for player in 4:
		check_equal(feel.effects_of(FeelScript.KIND_BURST, player), 1, "player %d's burst, in its hat ramp" % player)
	check_equal(feel.effects_of(FeelScript.KIND_CHIPS), 4, "and four sprays of chips")


func test_an_enemy_shot_on_a_wall_lands_in_the_enemy_ramp() -> void:
	bus.projectile_impact.emit(ActorSeats.enemy(actors), null, Vector2.ZERO, Vector2.UP)
	var shown: Dictionary = feel.effect_info(FeelScript.KIND_BURST)
	check(shown["ramp"] == ActorSeats.ActorsScript.RAMP_ENEMY and shown["core"] == Color.WHITE, "an enemy shot's burst is a spell's, in the enemy ramp (staffs F7)")
	bus.projectile_impact.emit(EventsScript.NO_PLAYER, null, Vector2.ZERO, Vector2.UP)
	check(not ProjectilesScript.is_hat_ramp(feel.effect_info(FeelScript.KIND_BURST)["ramp"] as int), "a shot of no actor too")


func test_wall_effects_are_limited_and_end() -> void:
	feel.set_effect_slots(EffectSlots.MIN)
	for i in 60:
		bus.projectile_impact.emit(i % 4, null, Vector2(float(i), 0.0), Vector2.UP)
		bus.projectile_impact.emit(-1, null, Vector2(float(i), 0.0), Vector2.UP)
	check(feel.live_effects() <= feel.effect_slots, "no more effects than slots")
	for i in 12:
		feel.step(STEP)
	check_equal(feel.live_effects(), 0, "they end")


func test_an_impact_without_damage_is_not_kept_for_a_later_hit() -> void:
	var target: Node2D = _enemy()
	bus.projectile_impact.emit(0, target, Vector2.ZERO, Vector2.RIGHT)
	feel._impact_frame -= 1  # the damage never came; a contact hit on a later frame
	bus.damage_dealt.emit(0, target, 5, Vector2.ZERO)
	check_equal(feel.effects_of(FeelScript.KIND_SPRAY), 0, "a stale impact gives no spray")
	check_equal(feel.effects_of(FeelScript.KIND_PUFF), 1, "but a puff")


func test_a_contact_hit_does_not_take_a_refused_shots_direction() -> void:
	var target: Node2D = _wizard(0)
	bus.projectile_impact.emit(1, target, Vector2.ZERO, Vector2.RIGHT)  # combat refused it: no damage
	bus.damage_dealt.emit(EventsScript.NO_PLAYER, target, 5, Vector2.ZERO)
	check_equal(feel.effects_of(FeelScript.KIND_SPRAY), 0, "a contact hit gets no spray")
	check_equal(feel.effects_of(FeelScript.KIND_PUFF), 1, "but a puff")


func test_a_kill_keeps_the_effect_where_the_shot_struck() -> void:
	var enemy: Node2D = _enemy()
	enemy.global_position = Vector2(100.0, 50.0)
	_strike(0, enemy, Vector2(92.0, 50.0), Vector2.RIGHT, 5)
	bus.enemy_died.emit(0, enemy, enemy.global_position)
	check((feel.effect_info(FeelScript.KIND_PUFF)["at"] as Vector2).is_equal_approx(Vector2(92.0, 50.0)), "the bigger puff stays where the shot struck")


func test_effects_draw_above_the_room_and_the_pillar_tops() -> void:
	check(feel._effect_node.z_index > 5, "above the pillar tops (z 5)")
	var children: int = feel.get_child_count()
	bus.damage_dealt.emit(0, null, 5, Vector2.ZERO)
	bus.projectile_impact.emit(0, null, Vector2.ZERO, Vector2.UP)
	check_equal(feel.get_child_count(), children, "no nodes for hits: one batch draws them all")
	for child in feel.get_children():
		check(not child is CPUParticles2D and not child is Line2D or child in feel._live_beams, "no particle nodes and no lines but the beams: %s" % child)
