extends "res://tests/support/suite.gd"
## gameplay/feel's core juice: screen shake and its setting (and only for what is in this
## machine's picture), the camera kick of a cast, the flash pool's limit with four players, flashes
## that end and come back, the particles setting, the hit sound (missing ones silent, a frame's
## voices capped), the hit flash and squash of a sprite, the cast flash, and that feel never
## changes damage. Each test gets a fresh Feel on its own bus, a registry of the test fixture's
## content and sounds (with the game's own cues and flash kinds), the four seats' actor table and a
## camera (`before_each`); `after_each` silences its voices and frees it all. Time moves by fixed
## binary-fraction steps. Each cue's own flashes and weight (a death's, a downed wizard's, a cast's
## kick) are test_feel_cues.gd's and test_feel_carrier_looks.gd's; the hits' share of the slots is
## test_feel_impacts.gd's.

const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const SoundsScript := preload("res://gameplay/feel/sounds.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const STEP: float = 0.0625
## A short step: one frame at 64 fps.
const FRAME: float = 0.015625
const FIXTURE: String = "res://tests/core/fixtures/registry"


## The fixture's content and sounds, with the game's own cues and the flash kinds they name
## (`content/cues`, `content/flashes`, from the Registry autoload): a death and a downed wizard are
## cues.
class FixtureRegistry:
	extends RegistryScript
	var cues: RegistryScript = null

	func get_resource(folder: StringName, id: StringName) -> Resource:
		if (folder == &"cues" or folder == &"flashes") and cues != null:
			return cues.get_resource(folder, id)
		return super(folder, id)

	func get_all(folder: StringName) -> Array[Resource]:
		if folder == &"flashes" and cues != null:
			return cues.get_all(folder)
		return super(folder)


var bus: EventsScript
var feel: FeelScript
var camera: Camera2D
var registry: FixtureRegistry
## Wizards at actor ids 0-3 (seats 0-3): the `player` of `_hit` is the attacker's actor id.
var actors: Node


func before_each() -> void:
	bus = EventsScript.new()
	registry = FixtureRegistry.new()
	registry.cues = root.get_node_or_null("Registry") as RegistryScript
	registry.scan(FIXTURE + "/content", FIXTURE + "/audio", PackedStringArray(["tres"]))
	feel = FeelScript.new()
	feel.events = bus
	feel.registry = registry
	actors = ActorSeats.table()
	feel.actors = actors
	feel.drive_engine = false
	feel.preset = FeelPresetScript.new()
	camera = Camera2D.new()
	root.add_child(camera)
	root.add_child(feel)


func after_each() -> void:
	# A voice that is still playing keeps its stream (a resource) alive at exit.
	if feel != null and is_instance_valid(feel) and feel.sounds() != null:
		feel.sounds().clear()
	for node: Node in [feel, camera, registry, bus, actors]:
		if node != null and is_instance_valid(node):
			node.free()
	feel = null
	camera = null
	registry = null
	bus = null
	actors = null


## The preset's hit sound (an id of the fixture's audio, or none).
func _sound(id: StringName) -> void:
	feel.preset.hit_sound = id


func _hit(player: int, at: Vector2 = Vector2.ZERO) -> void:
	bus.damage_dealt.emit(player, null, 1, at)


func _voices_with_stream() -> int:
	return feel.sounds().voices_with_stream()


## A plain body with a Sprite child, in the tree, freed after the test.
func _sprited(body: Node2D = null) -> Sprite2D:
	var holder: Node2D = body if body != null else Node2D.new()
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	holder.add_child(sprite)
	root.add_child(own(holder) as Node2D)
	return sprite


func test_the_punchy_preset_loads_and_names_itself() -> void:
	var preset := load("res://gameplay/feel/presets/punchy.tres") as FeelPresetScript
	check(preset != null, "punchy.tres loads as a FeelPreset")
	check(preset != null and preset.id == &"punchy", "the preset names itself")


# --- Shake -----------------------------------------------------------------------------------

func test_a_hit_shakes_the_camera() -> void:
	_hit(0)
	check(feel.trauma() > 0.0, "a hit adds shake")
	feel.step(FRAME)
	check(camera.offset != Vector2.ZERO, "the camera moves while shaking")


func test_the_shake_stays_within_the_presets_limit() -> void:
	_hit(0)
	feel.step(FRAME)
	check(camera.offset.length() <= feel.preset.max_shake_pixels * 1.5, "the shake stays within its limit")


func test_the_shake_dies_down_to_a_camera_at_rest() -> void:
	_hit(0)
	for i in 40:
		feel.step(STEP)
	check_equal(feel.trauma(), 0.0, "the shake dies down")
	check_equal(camera.offset, Vector2.ZERO, "the camera is back to rest")


func test_trauma_is_capped_at_one() -> void:
	for i in 10:
		_hit(i % 4)
	check(feel.trauma() <= 1.0, "trauma is capped at 1")


func test_with_shake_off_nothing_moves_the_camera() -> void:
	feel.shake_enabled = false
	_hit(0)
	bus.enemy_died.emit(1, null, Vector2.ZERO, -1)
	bus.player_downed.emit(2)
	feel.step(FRAME)
	check_equal(feel.trauma(), 0.0, "no trauma with shake off")
	check_equal(camera.offset, Vector2.ZERO, "the camera never moves with shake off")


func test_shake_comes_back_when_turned_on() -> void:
	feel.shake_enabled = false
	_hit(0)
	feel.shake_enabled = true
	_hit(0)
	check(feel.trauma() > 0.0, "shake comes back when turned on")


func test_turning_shake_off_stops_it_at_once() -> void:
	_hit(0)
	_hit(0)
	feel.shake_enabled = false
	check(feel.trauma() == 0.0 and camera.offset == Vector2.ZERO, "turning shake off stops it at once")


## Each machine's camera holds its own wizards (owner, 2026-11-13), so a hit or a cast far off this
## machine's picture (a teammate's fight on another machine) does not shake or kick it; one in the
## picture or just past its edge does. The picture.
func _picture() -> Rect2:
	camera.make_current()
	feel.step(FRAME)
	var picture: Rect2 = feel.party_camera.visible_rect()
	check(picture.has_area(), "the party camera has a picture")
	return picture


func test_a_hit_far_out_of_the_picture_does_not_shake_it() -> void:
	var picture: Rect2 = _picture()
	_hit(0, picture.end + Vector2(2000.0, 2000.0))
	check_equal(feel.trauma(), 0.0, "a hit far out of the picture does not shake it")


func test_a_cast_far_out_of_the_picture_neither_shakes_nor_kicks() -> void:
	var picture: Rect2 = _picture()
	feel.play_cue(&"cast", 0, picture.end + Vector2(2000.0, 2000.0), Vector2.RIGHT)
	check(feel.trauma() == 0.0 and feel.kick() == Vector2.ZERO, "a cast far out of the picture neither shakes nor kicks")


func test_a_hit_just_past_the_pictures_edge_is_still_felt() -> void:
	var picture: Rect2 = _picture()
	_hit(0, picture.end + Vector2(FeelScript.SHAKE_REACH * 0.5, 0.0))
	check(feel.trauma() > 0.0, "a hit just past the edge is still felt")


func test_a_hit_in_the_picture_shakes() -> void:
	var picture: Rect2 = _picture()
	_hit(0, picture.get_center())
	check(feel.trauma() > 0.0, "a hit in the picture shakes")


func test_a_new_current_camera_shakes() -> void:
	camera.make_current()
	var second := own(Camera2D.new()) as Camera2D
	root.add_child(second)
	second.make_current()
	_hit(0)
	feel.step(FRAME)
	check(second.offset != Vector2.ZERO, "the new camera shakes")


func test_the_old_camera_is_put_back_at_rest_when_the_camera_changes() -> void:
	camera.make_current()
	_hit(0)
	feel.step(FRAME)
	check(camera.offset != Vector2.ZERO, "the first camera shakes")
	var second := own(Camera2D.new()) as Camera2D
	root.add_child(second)
	second.make_current()
	_hit(0)
	check_equal(camera.offset, Vector2.ZERO, "the old camera is put back at rest")


# --- The cast's kick -------------------------------------------------------------------------

func test_the_camera_moves_with_a_casts_kick() -> void:
	bus.spell_cast.emit(2, &"fire_bolt", Vector2(10, 5), Vector2.RIGHT)
	feel.step(FRAME)
	check(camera.offset.x < 0.0, "the camera moves with the kick, against the aim")


func test_the_kick_is_capped() -> void:
	for i in 100:
		bus.spell_cast.emit(i % 4, &"fire_bolt", Vector2.ZERO, Vector2.RIGHT)
	check(feel.kick().length() <= FeelScript.MAX_KICK_PIXELS + 0.001, "the kick is capped")


func test_the_camera_settles_after_a_cast() -> void:
	bus.spell_cast.emit(2, &"fire_bolt", Vector2(10, 5), Vector2.RIGHT)
	for i in 10:
		feel.step(STEP)
	check_equal(feel.flashes_of(&"cast"), 0, "the cast flashes end")
	check(camera.offset == Vector2.ZERO and feel.kick() == Vector2.ZERO, "the camera settles after a cast")


func test_a_cast_kicks_nothing_with_shake_off() -> void:
	feel.shake_enabled = false
	bus.spell_cast.emit(0, &"fire_bolt", Vector2.ZERO, Vector2.RIGHT)
	check_equal(feel.kick(), Vector2.ZERO, "no kick with shake off")


# --- The cast flash --------------------------------------------------------------------------

## Player 2's cast at (10, 5) aiming down, drawn; the flash batch's buffer.
func _cast_flash() -> PackedFloat32Array:
	bus.spell_cast.emit(1, &"fire_bolt", Vector2(10, 5), Vector2.DOWN)
	feel.step(0.01)
	check_equal(feel.flashes_of(&"cast", 1), 1, "player 2's cast flash shows")
	check_equal(feel._flash_node.multimesh.visible_instance_count, 1, "the cast flash is drawn")
	return feel._flash_node.multimesh.buffer


func test_the_cast_flash_is_drawn_at_the_staff_tip_turned_along_the_aim() -> void:
	var buffer: PackedFloat32Array = _cast_flash()
	check(Vector2(buffer[0], buffer[4]).normalized().is_equal_approx(Vector2.DOWN), "the cast flash turns along the aim")
	check(is_equal_approx(buffer[3], 10.0) and is_equal_approx(buffer[7], 5.0), "at the staff tip")


func test_the_cast_flash_is_drawn_in_its_players_colours() -> void:
	var buffer: PackedFloat32Array = _cast_flash()
	check_equal(roundi(buffer[8] * 255.0) % 4, 1, "it is drawn in the colours of player 2")


# --- The flash pool --------------------------------------------------------------------------

## Every hit, kill and puff is a flash (the glow look): a flood from four players fills the
## effect slots and no more.
func test_a_flood_from_four_players_fills_the_effect_slots_and_no_more() -> void:
	feel.set_effect_slots(EffectSlots.MIN)
	var most: int = 0
	var over: int = 0
	for frame in 30:
		for player in 4:
			for shot in 5:
				_hit(player, Vector2(10.0 * shot, 10.0 * player))
			bus.enemy_died.emit(player, null, Vector2(5.0 * player, 0.0), -1)
		feel.step(FRAME)
		most = maxi(most, feel.live_flashes())
		if feel.live_flashes() > feel.effect_slots:
			over += 1
	check_equal(over, 0, "live flashes stay within the slots on every frame")
	check(most > 0, "hits make flashes")
	check_equal(most, feel.effect_slots, "a flood fills the slots and no more")


func test_a_hit_makes_no_node() -> void:
	var children: int = feel.get_child_count()
	for i in 20:
		_hit(i % 4, Vector2(float(i), 0.0))
	feel.step(FRAME)
	check_equal(feel.get_child_count(), children, "no node is made for a hit")


func test_each_hit_with_no_way_is_a_puff() -> void:
	for i in 20:
		_hit(i % 4)
	check_equal(feel.flashes_of(&"puff"), 20, "twenty hits with no way, twenty puffs")


func test_flashes_come_back_after_they_end() -> void:
	for i in 20:
		_hit(i % 4)
	for i in 30:
		feel.step(STEP)
	check_equal(feel.live_flashes(), 0, "finished flashes end")
	_hit(0)
	check_equal(feel.live_flashes(), 1, "a new hit has one again")


func test_a_kill_gets_its_puff_even_when_the_slots_are_full() -> void:
	feel.set_effect_slots(EffectSlots.MIN)
	for i in feel.effect_slots:
		_hit(i % 4, Vector2(100.0 + i, 0.0))
	for i in feel.effect_slots:
		feel.show_flash(&"burst", Vector2(100.0 + i, 20.0), Vector2.UP, Color.WHITE, 0, 0, 1, 0.5)
	check_equal(feel.live_flashes(), feel.effect_slots, "the slots are full")
	bus.enemy_died.emit(1, null, Vector2(-50.0, 9.0), -1)
	check(feel.flashes_of(&"puff") >= 1, "a kill gets its puff even when the slots are full (the oldest is taken)")
	check_equal(feel.live_flashes(), feel.effect_slots, "taking one over keeps the limit")


func test_death_puffs_stay_within_the_effect_slots() -> void:
	feel.set_effect_slots(EffectSlots.MIN)
	for i in 100:
		bus.enemy_died.emit(i % 4, null, Vector2(i, 0), -1)
	check(feel.live_flashes() <= feel.effect_slots, "death puffs stay within the effect slots")


func test_death_puffs_end() -> void:
	for i in 100:
		bus.enemy_died.emit(i % 4, null, Vector2(i, 0), -1)
	for i in 30:
		feel.step(STEP)
	check_equal(feel.live_flashes(), 0, "the puffs end")


func test_no_hit_flash_starts_with_particles_off() -> void:
	feel.particles_enabled = false
	for i in 20:
		_hit(i % 4)
	bus.enemy_died.emit(0, null, Vector2(5.0, 0.0), -1)
	feel.step(STEP)
	check(feel.flashes_of(&"puff") == 0 and feel.flashes_of(&"spray") == 0, "no hit flashes start with particles off")


func test_hit_flashes_start_again_when_particles_are_back_on() -> void:
	feel.particles_enabled = false
	_hit(0)
	feel.particles_enabled = true
	_hit(0)
	check_equal(feel.flashes_of(&"puff"), 1, "they start again when turned back on")


func test_flashes_survive_the_world_scene_being_freed() -> void:
	for round in 3:
		var world := own(Node2D.new()) as Node2D
		root.add_child(world)
		current_scene = world
		_hit(0, Vector2(4.0, 4.0))
		check_equal(feel.live_flashes(), 1, "a flash starts with a world scene (round %d)" % round)
		world.free()
		current_scene = null
		for i in 30:
			feel.step(STEP)
	for shot in 12:
		_hit(shot % 4, Vector2(shot, 0.0))
	check_equal(feel.live_flashes(), 12, "after the world was freed three times, flashes still show")


# --- Sounds ----------------------------------------------------------------------------------

func test_an_unknown_hit_sound_plays_nothing() -> void:
	_sound(&"no_such_sound")
	_hit(0)
	bus.enemy_died.emit(0, null, Vector2.ZERO, -1)
	bus.player_downed.emit(1)
	check_equal(_voices_with_stream(), 0, "an unknown sound id plays nothing")


func test_no_registry_plays_nothing() -> void:
	_sound(&"zap")
	feel.registry = null
	_hit(0)
	check_equal(_voices_with_stream(), 0, "no registry plays nothing")


func test_a_known_hit_sound_plays_on_a_hit() -> void:
	_sound(&"zap")
	_hit(0)
	check_equal(_voices_with_stream(), 1, "a known sound id plays on a hit")


func test_sounds_never_use_more_than_sound_voices() -> void:
	_sound(&"zap")
	for i in 20:
		_hit(i % 4)
		feel.step(FRAME)
	check(_voices_with_stream() <= FeelScript.SOUND_VOICES, "sounds never use more voices than SOUND_VOICES")


## A frame's hit sounds start at most HIT_SOUNDS_PER_FRAME voices (shot scale H3: past them each
## would only cut short one of the same frame).
func test_a_frames_hits_start_at_most_hit_sounds_per_frame() -> void:
	_sound(&"zap")
	for i in 20:
		_hit(i % 4, Vector2(float(i), 0.0))
	check_equal(feel.sounds().started, FeelScript.HIT_SOUNDS_PER_FRAME, "a frame's hits start HIT_SOUNDS_PER_FRAME sounds")


func test_a_frames_hit_sounds_of_one_sound_take_at_most_per_sound_voices() -> void:
	_sound(&"zap")
	for i in 20:
		_hit(i % 4, Vector2(float(i), 0.0))
	check_equal(_voices_with_stream(), SoundsScript.PER_SOUND, "on at most PER_SOUND voices of the one sound")


func test_the_next_frames_hit_sounds_start_again() -> void:
	_sound(&"zap")
	for i in 20:
		_hit(i % 4, Vector2(float(i), 0.0))
	feel.step(FRAME)
	_hit(0, Vector2(-30.0, 0.0))
	check_equal(feel.sounds().started, FeelScript.HIT_SOUNDS_PER_FRAME + 1, "the next frame's hit sounds")


# --- Damage is combat's ----------------------------------------------------------------------

## Four hits of 2 by the four players on a body of 10 health in a Combat of its own bus, with a
## Feel on that bus or none: [damage events, deaths, health left].
func _combat_outcome(with_feel: bool) -> Array:
	var own_bus := own(EventsScript.new()) as EventsScript
	var combat := own(CombatScript.new()) as CombatScript
	combat.events = own_bus
	combat._ready()
	var listener: FeelScript = null
	if with_feel:
		listener = own(FeelScript.new()) as FeelScript
		listener.events = own_bus
		listener.registry = registry
		listener.actors = actors
		listener.drive_engine = false
		listener.preset = FeelPresetScript.new()
		root.add_child(listener)
	var damage: Array = []
	var deaths: Array = []
	own_bus.damage_dealt.connect(func(p: int, _t: Node, amount: int, _at: Vector2) -> void:
		damage.append([p, amount]))
	own_bus.enemy_died.connect(func(p: int, _e: Node, _at: Vector2, _shot: int) -> void:
		deaths.append(p))
	var enemy := own(Node2D.new()) as Node2D
	combat.register_actor(enemy, 10, 10.0, 0)
	for player in 4:
		combat.hit(player, enemy, 2)
	var health: float = combat.health_of(enemy)
	if listener != null:
		listener.step(STEP)
		listener.sounds().clear()
	return [damage, deaths, health]


func test_feel_never_changes_damage() -> void:
	var without: Array = _combat_outcome(false)
	var felt: Array = _combat_outcome(true)
	check(without == felt, "damage, deaths and health are the same with and without feel")
	check(felt[2] == 2 and (felt[1] as Array).is_empty(), "four hits of 2 leave 2 health, as combat says")


# --- A hit's flash and squash on the body ----------------------------------------------------

func test_a_hit_flashes_the_targets_sprite() -> void:
	var sprite: Sprite2D = _sprited()
	bus.damage_dealt.emit(0, sprite.get_parent(), 1, Vector2.ZERO)
	check(sprite.material != null, "a hit flashes the sprite")
	check_equal(feel.reacting_sprites(), 1, "one sprite reacts")


func test_a_hit_squashes_the_targets_sprite() -> void:
	var sprite: Sprite2D = _sprited()
	bus.damage_dealt.emit(0, sprite.get_parent(), 1, Vector2.ZERO)
	feel.step(FRAME)
	check(sprite.scale.x > 1.0 and sprite.scale.y < 1.0, "the sprite squashes")


func test_a_second_hit_on_a_reacting_sprite_adds_no_reaction() -> void:
	var sprite: Sprite2D = _sprited()
	bus.damage_dealt.emit(0, sprite.get_parent(), 1, Vector2.ZERO)
	bus.damage_dealt.emit(1, sprite.get_parent(), 1, Vector2.ZERO)
	check_equal(feel.reacting_sprites(), 1, "a second hit on the same sprite does not add a reaction")


func test_the_flash_and_squash_end_on_the_sprites_own_look() -> void:
	var sprite: Sprite2D = _sprited()
	bus.damage_dealt.emit(0, sprite.get_parent(), 1, Vector2.ZERO)
	feel.step(FRAME)
	for i in 4:
		feel.step(STEP)
	check(sprite.material == null, "the flash ends")
	check_equal(sprite.scale, Vector2.ONE, "the sprite is back to its size")
	check_equal(feel.reacting_sprites(), 0, "no reaction is left")


## A scale set by the sprite's owner mid-squash (a dash look) is kept, not overwritten.
func test_a_dash_scale_set_mid_squash_is_kept() -> void:
	var sprite: Sprite2D = _sprited()
	bus.damage_dealt.emit(0, sprite.get_parent(), 1, Vector2.ZERO)
	feel.step(FRAME)
	sprite.scale = Vector2(1.4, 0.7)
	feel.step(FRAME)
	check(sprite.scale.x > 1.0 and sprite.scale.y < 1.0, "a dash look set during a squash stays stretched")
	for i in 4:
		feel.step(STEP)
	check(sprite.scale.is_equal_approx(Vector2(1.4, 0.7)), "the squash ends on the dash scale, not the old one")


func test_a_target_with_no_sprite_or_freed_mid_flash_is_dropped() -> void:
	var bare := Node2D.new()
	bus.damage_dealt.emit(0, bare, 1, Vector2.ZERO)
	bare.free()
	var sprite: Sprite2D = _sprited()
	var body: Node = sprite.get_parent()
	bus.damage_dealt.emit(0, body, 1, Vector2.ZERO)
	body.free()
	feel.step(STEP)
	check_equal(feel.reacting_sprites(), 0, "a freed sprite is dropped")


## No limit (owner, 2026-10-31): 120 bodies hit in one frame, actors and plain nodes. Their sprites.
func _crowd_hit() -> Array[Sprite2D]:
	var sprites: Array[Sprite2D] = []
	for i in 120:
		var sprite: Sprite2D = _sprited(Actor.new() if i % 2 == 0 else Node2D.new())
		sprites.append(sprite)
		bus.damage_dealt.emit(i % 4, sprite.get_parent(), 1, Vector2.ZERO)
	return sprites


func test_every_one_of_120_bodies_hit_at_once_flashes() -> void:
	var sprites: Array[Sprite2D] = _crowd_hit()
	check_equal(feel.reacting_sprites(), 120, "every one of 120 sprites hit at once reacts")
	var flashing: int = 0
	for sprite in sprites:
		if sprite.material != null:
			flashing += 1
	check_equal(flashing, 120, "every one flashes")


func test_a_second_hit_on_a_flashing_actor_or_node_adds_none() -> void:
	var sprites: Array[Sprite2D] = _crowd_hit()
	bus.damage_dealt.emit(0, sprites[7].get_parent(), 1, Vector2.ZERO)
	bus.damage_dealt.emit(0, sprites[8].get_parent(), 1, Vector2.ZERO)
	check_equal(feel.reacting_sprites(), 120, "a second hit on a flashing actor or node adds none")


func test_the_next_crowd_reuses_the_room_of_the_last() -> void:
	var sprites: Array[Sprite2D] = _crowd_hit()
	var room: int = feel._react_sprites.size()
	for i in 4:
		feel.step(STEP)
	check_equal(feel.reacting_sprites(), 0, "every flash ends")
	for sprite in sprites:
		bus.damage_dealt.emit(0, sprite.get_parent(), 1, Vector2.ZERO)
	check(feel.reacting_sprites() == 120 and feel._react_sprites.size() == room, "the next crowd reuses the room: nothing grows")
