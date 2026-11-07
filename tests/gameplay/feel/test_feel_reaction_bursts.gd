extends "res://tests/support/suite.gd"
## Reactions and statuses in gameplay/feel (#244, part 3): a reaction is a burst bigger than a
## plain hit (a ring, a bigger spray, a longer hit-stop, more shake and its sound together), and
## an enemy with burning, chill, freeze, shock or hex shows it on its sprite, without text: a glow
## in its element card's colour and the card's motes round it (spell spectacle 2, S6 item 11).

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const FIRE := preload("res://content/spells/elements/fire/fire.tres")
const FROST := preload("res://content/spells/elements/frost/frost.tres")

const ActorSeats := preload("res://tests/support/actor_seats.gd")

const STEP: float = 0.0625


## Stands in for combat: the statuses an enemy has, as seconds left by status id.
class FakeCombat:
	extends Node
	var left: Dictionary = {}

	func status_left(enemy: Node, status_id: StringName) -> float:
		var own_left: Dictionary = left.get(enemy.get_instance_id(), {}) as Dictionary
		return own_left.get(status_id, 0.0) as float


class Enemy:
	extends Node2D
	var sprite: Sprite2D

	func _init() -> void:
		sprite = Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = preload("res://art/vfx/hit_spark.svg")
		add_child(sprite)


var _bus: EventsScript
var _feel: FeelScript
var _combat: FakeCombat
var _actors: ActorSeats.ActorsScript


func before_each() -> void:
	_bus = own(EventsScript.new()) as EventsScript
	_actors = own(ActorSeats.table()) as ActorSeats.ActorsScript
	_combat = own(FakeCombat.new()) as FakeCombat
	_feel = own(FeelScript.new()) as FeelScript
	_feel.events = _bus
	_feel.combat = _combat
	_feel.actors = _actors
	_feel.drive_engine = false
	_feel.preset = FeelPresetScript.new()
	# A status is shown as its element card: the cards come from the registry.
	var registry: RegistryScript = own(RegistryScript.new()) as RegistryScript
	registry.scan()
	_feel.registry = registry
	root.add_child(_feel)


func _enemy() -> Enemy:
	var enemy: Enemy = own(Enemy.new()) as Enemy
	root.add_child(enemy)
	return enemy


func _status_on(enemy: Enemy, id: StringName, player: int = 0) -> void:
	_combat.left[enemy.get_instance_id()] = {id: 3.0}
	_bus.status_applied.emit(player, enemy, id)


func test_a_reaction_stops_longer_and_shakes_more_than_a_plain_hit() -> void:
	var death: CueBase = _feel.cue_of(&"enemy_death")
	var flare: CueBase = _feel.cue_of(&"reaction_flare")
	check(death != null and flare != null, "the cues are there")
	if death == null or flare == null:
		return
	check(flare.hold * flare.power >= death.hold, "at least as long as a death's stop")
	check(flare.shake * flare.power > death.shake * 0.5, "a strong shake")
	_bus.reaction_triggered.emit(0, &"flare", Vector2.ZERO, -1)
	check(_feel.trauma() >= flare.shake * flare.power - 0.0001, "and shake, times its power")


func test_a_stronger_reaction_plays_its_cue_bigger() -> void:
	# The power rule (`play_cue`, S6): a reaction's cues differ in colour and power, and power is
	# times every flash's size. Shatter (1.3) against stillness (0.9), the same parts.
	var strong: CueBase = _feel.cue_of(&"reaction_shatter")
	var weak: CueBase = _feel.cue_of(&"reaction_stillness")
	check(strong.power > weak.power, "shatter is the stronger")
	_bus.reaction_triggered.emit(0, &"shatter", Vector2.ZERO, -1)
	var big: int = _feel.flash_info(&"ring_out")["zoom"] as int
	_bus.reaction_triggered.emit(1, &"stillness", Vector2(80.0, 0.0), -1)
	var small: int = _feel.flash_info(&"ring_out")["zoom"] as int
	check(big > small, "its ring is the bigger (%d, %d)" % [big, small])
	check_equal(big, 4, "shatter's ring as before the cues (2.9 x 1.3, rounded)")
	check_equal(small, 3, "stillness's ring as before the cues (2.9 x 0.9, rounded)")


func test_a_repeated_reaction_shows_again_without_its_weight() -> void:
	_bus.reaction_triggered.emit(0, &"thaw", Vector2.ZERO, -1)
	var shake: float = _feel.trauma()
	var rings: int = _feel.flashes_of(&"ring_out")
	_bus.reaction_triggered.emit(0, &"thaw", Vector2(60.0, 0.0), -1)
	check_equal(_feel.flashes_of(&"ring_out"), rings + 1, "its looks every time")
	check(is_equal_approx(_feel.trauma(), shake), "its shake at most every REACTION_REPEAT seconds")


func test_a_reaction_with_no_cue_of_its_own_plays_the_plain_one() -> void:
	_bus.reaction_triggered.emit(0, &"steam", Vector2.ZERO, -1)
	var plain: CueBase = _feel.cue_of(CueBase.REACTION_CUE)
	check(plain != null, "there is a plain reaction cue")
	check_equal(_feel.flash_info(&"ring_out")["core"], plain.color, "its ring in the plain cue's colour")


func test_the_puff_is_bigger_than_a_hit_and_the_ring_ends() -> void:
	_bus.damage_dealt.emit(0, null, 5, Vector2(50.0, 0.0))
	var hit: int = _feel.flash_info(&"puff")["zoom"] as int
	_bus.reaction_triggered.emit(0, &"shatter", Vector2.ZERO, -1)
	check((_feel.flash_info(&"puff")["zoom"] as int) > hit, "a reaction's puff is bigger than a hit's")
	check_equal(_feel.flashes_of(&"ring_out"), 1, "with a ring")
	for i in 40:
		_feel.step(STEP)
	check_equal(_feel.live_flashes(), 0, "ring and puff end")


func test_four_players_reacting_at_once_stay_inside_the_effect_slots() -> void:
	for player in 4:
		_bus.reaction_triggered.emit(player, &"shatter", Vector2(float(player) * 20.0, 0.0), -1)
	check_equal(_feel.flashes_of(&"puff"), 4, "four puffs")
	check(_feel.live_flashes() <= _feel.effect_slots, "inside the effect slots")


func test_each_status_shows_a_different_colour() -> void:
	var seen: Array[Color] = []
	for id: StringName in [&"burn", &"chill", &"freeze", &"shock", &"hex"]:
		var enemy: Enemy = _enemy()
		_status_on(enemy, id)
		check_equal(_feel.status_shown(enemy), id, "%s shows" % id)
		var color: Color = _feel.status_color(id)
		for other in seen:
			var apart: float = Vector3(color.r - other.r, color.g - other.g, color.b - other.b).length()
			check(apart >= 0.3, "%s differs from the others (%.2f)" % [id, apart])
		seen.append(color)


func test_the_status_follows_the_enemy_and_ends_with_the_status() -> void:
	var enemy: Enemy = _enemy()
	enemy.global_position = Vector2(40.0, 30.0)
	_status_on(enemy, &"burn")
	_feel.step(STEP)
	check_equal(_feel.live_statuses(), 1, "one status effect")
	var shown: Dictionary = _feel.status_info()
	check((shown["core"] as Color).is_equal_approx(Color(FIRE.tint.r, FIRE.tint.g, FIRE.tint.b, 1.0)), "in its element card's colour (fire's): %s" % shown["core"])
	check(ProjectileManagerScript.look_has(shown["look"] as int, FIRE.look_layer), "with the card's look (fire's embers)")
	enemy.global_position = Vector2(80.0, 30.0)
	_feel.step(STEP)
	check_equal((_feel.status_info()["at"] as Vector2).x, 80.0, "it moved with the enemy")
	_combat.left.clear()
	for i in 4:
		_feel.step(STEP)
	check_equal(_feel.live_statuses(), 0, "it ends when the status does")


func test_a_frozen_enemy_wins_over_its_other_statuses() -> void:
	var enemy: Enemy = _enemy()
	_combat.left[enemy.get_instance_id()] = {&"burn": 2.0, &"freeze": 1.0}
	_bus.status_applied.emit(0, enemy, &"freeze")
	check_equal(_feel.status_shown(enemy), &"freeze", "freeze first")


func test_a_status_shows_through_a_hit() -> void:
	var enemy: Enemy = _enemy()
	_status_on(enemy, &"hex")
	check_equal(_feel.live_statuses(), 1, "shown")
	_bus.damage_dealt.emit(0, enemy, 3, Vector2.ZERO)
	_feel.step(STEP * 0.1)
	check_equal(_feel.live_statuses(), 1, "its particles go on while the sprite flashes")


func test_a_status_comes_back_when_a_crowd_of_flashes_took_its_slot() -> void:
	_feel.set_effect_slots(EffectSlots.MIN)
	var enemy: Enemy = _enemy()
	_status_on(enemy, &"static")
	for i in _feel.effect_slots:
		_bus.damage_dealt.emit(0, null, 5, Vector2(float(i), 0.0))
	check_equal(_feel.live_statuses(), 0, "the crowd took the oldest slot, the status's")
	_feel.step(STEP)
	check_equal(_feel.live_statuses(), 1, "the next step shows it again")


func test_a_sprite_with_its_own_material_still_shows_a_status() -> void:
	var enemy: Enemy = _enemy()
	(enemy.get_node("Sprite") as Sprite2D).material = ShaderMaterial.new()
	_status_on(enemy, &"burn")
	check_equal(_feel.live_statuses(), 1, "an own material is not the hit flash")


func test_a_freed_enemy_loses_its_overlay() -> void:
	var enemy: Enemy = _enemy()
	_status_on(enemy, &"shock")
	enemy.free()
	_feel.step(STEP)
	check_equal(_feel.live_statuses(), 0, "no overlay for a freed enemy")


func test_a_crowd_of_statuses_stays_inside_the_slots() -> void:
	for i in FeelScript.STATUS_SLOTS + 8:
		_status_on(_enemy(), &"burn", i % 4)
	check(_feel.live_statuses() <= FeelScript.STATUS_SLOTS, "no more statuses than slots")


func test_without_combat_there_are_no_overlays() -> void:
	_feel.combat = null
	var enemy: Enemy = _enemy()
	_bus.status_applied.emit(0, enemy, &"burn")
	check_equal(_feel.live_statuses(), 0, "nothing to read, nothing shown")


func test_a_status_is_shown_as_its_element_card() -> void:
	for id: StringName in [&"burn", &"chill", &"shock", &"hex", &"static"]:
		var card: Array = _feel._status_card(id)
		check(not card.is_empty() and card[ElementBase.STATUS_LOOK_STATUS] == id, "%s is the status of a card" % id)
		var tint: Color = card[ElementBase.STATUS_LOOK_TINT] as Color
		check(_feel.status_color(id).is_equal_approx(Color(tint.r, tint.g, tint.b, 1.0)), "%s glows in its card's tint" % id)
	check(_feel._status_card(&"chill")[ElementBase.STATUS_LOOK_CARD] == &"frost", "chill is frost's")
	check(_feel._status_card(&"freeze") == _feel._status_card(&"chill"), "freeze, which no element puts on, is shown as the chill it deepens from (frost)")
	check(_feel._status_card(&"nothing").is_empty() and _feel.status_color(&"nothing") == Color.WHITE, "an unknown status has no card")
	var enemy: Enemy = _enemy()
	_status_on(enemy, &"nothing")
	check_equal(_feel.live_statuses(), 0, "and shows nothing")


func test_freeze_reads_apart_from_chill() -> void:
	var chill: Color = _feel.status_color(&"chill")
	var freeze: Color = _feel.status_color(&"freeze")
	check(chill.is_equal_approx(Color(FROST.tint.r, FROST.tint.g, FROST.tint.b, 1.0)), "chill in frost's tint")
	check(freeze.get_luminance() > chill.get_luminance() + 0.15, "freeze far whiter: %s against %s" % [freeze, chill])
	var chilled: int = _status_motes_over(&"chill", 2.0)
	var frozen: int = _status_motes_over(&"freeze", 2.0)
	check(float(frozen) >= float(chilled) * 1.4, "and a frozen body gives off far more motes: %d against %d" % [frozen, chilled])


func test_a_status_gives_off_its_cards_motes_slowly_while_it_shows() -> void:
	var preset: FeelPresetScript = _feel.preset
	var thrown: int = _status_motes_over(&"burn", 2.0)
	var expected: float = preset.status_mote_rate * 2.0
	check(absf(float(thrown) - expected) <= expected * 0.5 + 2.0, "about status_mote_rate a second: %d in 2 s" % thrown)
	var enemy: Enemy = _enemy()
	_status_on(enemy, &"burn")
	_feel.step(STEP)
	var embers: PackedInt32Array = _feel.motes().kinds_of_layer(FIRE.look_layer)
	check(not embers.is_empty(), "fire's look layer has kinds (embers)")
	(enemy.get_node("Sprite") as Sprite2D).visible = false
	_feel.step(STEP)
	var written: int = _feel.motes().written
	for i in 16:
		_feel.step(STEP)
	check_equal(_feel.motes().written, written, "none while the body is hidden")


## Motes written while one enemy shows status `id` for `seconds` (the frame's other motes aside: no
## shot flies in this test).
func _status_motes_over(id: StringName, seconds: float) -> int:
	var enemy: Enemy = _enemy()
	_status_on(enemy, id)
	_feel.step(STEP)
	var before: int = _feel.motes().written
	for i in roundi(seconds / STEP):
		_combat.left[enemy.get_instance_id()] = {id: 3.0}
		_feel.step(STEP)
	var thrown: int = _feel.motes().written - before
	_combat.left.erase(enemy.get_instance_id())
	for i in 4:
		_feel.step(STEP)
	return thrown


func test_the_status_shader_draws_only_its_glow() -> void:
	var code: String = (FeelScript.STATUS_SHADER as Shader).code
	check(not code.contains("shot_particle") and not code.contains("for ("), "no particle loop: its particles are motes (S6 item 11)")
