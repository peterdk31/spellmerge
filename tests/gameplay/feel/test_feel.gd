extends SceneTree
## Tests for gameplay/feel: hit-stop, screen shake and its setting, the particle
## limit with four players, silent missing sounds, and that feel never changes
## damage. Time moves by fixed binary-fraction deltas.
##
## godot --headless --path . --script res://tests/gameplay/feel/test_feel.gd

const CombatScript := preload("res://gameplay/combat/combat.gd")
const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const RegistryScript :=preload("res://core/registry/registry.gd")
const ActorStandIn := preload("res://tests/gameplay/feel/fixtures/wizard_stand_in.gd")

const STEP: float = 0.0625
const FIXTURE: String = "res://tests/core/fixtures/registry"

var _failures: Array[String] = []
var _bus: Node
var _feel: Node
var _camera: Camera2D
var _registry: Node


func _initialize() -> void:
	# The root joins the scene tree only after _initialize returns: wait one frame.
	await process_frame
	_test_default_preset_loads()
	_test_hit_stop_is_short_and_the_same_for_every_player()
	_test_hit_stop_longest_wins()
	_test_shake_moves_the_camera_and_settles()
	_test_shake_off_does_nothing()
	_test_particle_limit_holds_with_four_players()
	_test_particles_come_back()
	_test_particles_can_be_turned_off()
	_test_missing_sound_is_silent()
	_test_known_sound_plays()
	_test_downed_has_no_particles()
	_test_feel_never_changes_damage()
	_test_bursts_survive_the_world_being_freed()
	_test_hit_stops_are_limited()
	_test_a_kill_uses_one_slot_and_beats_a_full_pool()
	_test_engine_time_scale_comes_back()
	_test_camera_change_is_followed()
	_test_hit_flash_and_squash()
	_test_cast_flash_and_kick()
	_test_death_puff_is_limited()
	_test_muzzle_flash_follows_aim_and_colour()
	_test_muzzle_flash_stays_small()
	_test_cast_squash()
	_test_death_animation()
	_test_death_animation_starts_at_rest_scale()
	_test_cast_squash_skips_a_dash()
	_teardown()
	# The audio server drops stopped playbacks on its next mix; without this wait they
	# are reported as leaked objects (and a resource still in use) at exit.
	await create_timer(0.3).timeout
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("TEST OK: gameplay/feel (hit-stop, shake, particle limit)")
		quit(0)
	else:
		for failure in _failures:
			printerr("TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _setup(sound_id: StringName = &"", projectiles: Node = null) -> void:
	_teardown()
	_bus = EventsScript.new()
	_registry = RegistryScript.new()
	_registry.scan(FIXTURE + "/content", FIXTURE + "/audio", PackedStringArray(["tres"]))
	_feel = FeelScript.new()
	_feel.events = _bus
	_feel.registry = _registry
	_feel.projectiles = projectiles
	_feel.drive_engine = false
	var preset := FeelPresetScript.new()
	preset.hit_sound = sound_id
	preset.death_sound = sound_id
	preset.downed_sound = sound_id
	_feel.preset = preset
	_camera = Camera2D.new()
	root.add_child(_camera)
	root.add_child(_feel)


func _teardown() -> void:
	# A voice that is still playing keeps its stream (a resource) alive at exit.
	if _feel != null and is_instance_valid(_feel):
		for child in _feel.get_children():
			var voice := child as AudioStreamPlayer
			if voice != null:
				voice.stop()
				voice.stream = null
	for node: Node in [_feel, _camera, _registry, _bus]:
		if node != null and is_instance_valid(node):
			node.free()
	_feel = null
	_camera = null
	_registry = null
	_bus = null


func _hit(player: int, at: Vector2 = Vector2.ZERO) -> void:
	_bus.damage_dealt.emit(player, null, 1, at)


func _voices_with_stream() -> int:
	var count: int = 0
	for child in _feel.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).stream != null:
			count += 1
	return count


# --- Tests ------------------------------------------------------------------

func _test_default_preset_loads() -> void:
	var preset := load("res://gameplay/feel/presets/punchy.tres") as FeelPresetScript
	_check(preset != null, "punchy.tres loads as a FeelPreset")
	if preset == null:
		return
	_check(preset.id == &"punchy", "the preset names itself")
	_check(preset.hit_stop_seconds <= 0.1 and preset.death_stop_seconds <= 0.15, "hit-stop is short")
	_check(preset.hit_stop_scale > 0.0, "hit-stop never freezes the physics step")


func _test_hit_stop_is_short_and_the_same_for_every_player() -> void:
	_setup()
	var lengths: Array[float] = []
	for player in 4:
		_feel.stop_left = 0.0
		_hit(player)
		lengths.append(_feel.stop_left)
	_check(lengths[0] > 0.0, "a hit starts a hit-stop")
	for length in lengths:
		_check(is_equal_approx(length, lengths[0]), "hit-stop is the same length for every player")
	_check(lengths[0] <= 0.1, "hit-stop is short")
	_feel.step(STEP)
	_check(_feel.stop_left == 0.0, "the hit-stop ends in a few frames")


func _test_hit_stop_longest_wins() -> void:
	_setup()
	_bus.enemy_died.emit(0, null, Vector2.ZERO)
	var death: float = _feel.stop_left
	for player in 4:
		_hit(player)
	_check(is_equal_approx(_feel.stop_left, death), "four hits in the same frame do not stack the stop")
	_check(death >= _feel.preset.hit_stop_seconds, "a death stops at least as long as a hit")


func _test_shake_moves_the_camera_and_settles() -> void:
	_setup()
	_hit(0)
	_check(_feel.trauma() > 0.0, "a hit adds shake")
	_feel.step(0.015625)
	_check(_camera.offset != Vector2.ZERO, "the camera moves while shaking")
	_check(_camera.offset.length() <= _feel.preset.max_shake_pixels * 1.5, "the shake stays within its limit")
	for i in 40:
		_feel.step(STEP)
	_check(_feel.trauma() == 0.0, "the shake dies down")
	_check(_camera.offset == Vector2.ZERO, "the camera is back to rest")
	for i in 10:
		_hit(i % 4)
	_check(_feel.trauma() <= 1.0, "trauma is capped at 1")


func _test_shake_off_does_nothing() -> void:
	_setup()
	_feel.shake_enabled = false
	_hit(0)
	_bus.enemy_died.emit(1, null, Vector2.ZERO)
	_bus.player_downed.emit(2)
	_feel.step(0.015625)
	_check(_feel.trauma() == 0.0, "no trauma with shake off")
	_check(_camera.offset == Vector2.ZERO, "the camera never moves with shake off")
	_check(_feel.stop_left > 0.0, "hit-stop still works with shake off")
	_feel.shake_enabled = true
	_hit(0)
	_check(_feel.trauma() > 0.0, "shake comes back when turned on")
	_hit(0)
	_feel.shake_enabled = false
	_check(_feel.trauma() == 0.0 and _camera.offset == Vector2.ZERO, "turning shake off stops it at once")


## Every hit, kill and puff is an effect (the glow look): a flood from four players fills the
## effect slots and no more, and makes no nodes.
func _test_particle_limit_holds_with_four_players() -> void:
	_setup()
	_feel.set_effect_slots(EffectSlots.MIN)
	var children: int = _feel.get_child_count()
	var most: int = 0
	for frame in 30:
		for player in 4:
			for shot in 5:
				_hit(player, Vector2(10.0 * shot, 10.0 * player))
			_bus.enemy_died.emit(player, null, Vector2(5.0 * player, 0.0))
		_feel.step(0.015625)
		most = maxi(most, _feel.live_effects())
		_check(_feel.live_effects() <= _feel.effect_slots, "live effects stay within the slots (frame %d)" % frame)
	_check(most > 0, "hits make effects")
	_check(most == _feel.effect_slots, "a flood fills the slots and no more")
	_check(_feel.get_child_count() == children, "no node is made for a hit")


func _test_particles_come_back() -> void:
	_setup()
	for i in 20:
		_hit(i % 4)
	_check(_feel.effects_of(FeelScript.KIND_PUFF) == 20, "twenty hits with no way, twenty puffs")
	for i in 30:
		_feel.step(STEP)
	_check(_feel.live_effects() == 0, "finished effects end")
	_hit(0)
	_check(_feel.live_effects() == 1, "and a new hit has one again")


func _test_particles_can_be_turned_off() -> void:
	_setup()
	_feel.particles_enabled = false
	for i in 20:
		_hit(i % 4)
	_bus.enemy_died.emit(0, null, Vector2(5.0, 0.0))
	_feel.step(STEP)
	_check(_feel.effects_of(FeelScript.KIND_PUFF) == 0 and _feel.effects_of(FeelScript.KIND_SPRAY) == 0, "no hit effects start with particles off")
	_feel.particles_enabled = true
	_hit(0)
	_check(_feel.effects_of(FeelScript.KIND_PUFF) == 1, "they start again when turned back on")


func _test_missing_sound_is_silent() -> void:
	_setup(&"no_such_sound")
	_hit(0)
	_bus.enemy_died.emit(0, null, Vector2.ZERO)
	_bus.player_downed.emit(1)
	_check(_voices_with_stream() == 0, "an unknown sound id plays nothing")
	_feel.registry = null
	_hit(0)
	_check(_voices_with_stream() == 0, "no registry plays nothing")


func _test_known_sound_plays() -> void:
	_setup(&"zap")
	_hit(0)
	_check(_voices_with_stream() == 1, "a known sound id plays on a hit")
	for i in 20:
		_hit(i % 4)
	_check(_voices_with_stream() <= FeelScript.SOUND_VOICES, "sounds never use more voices than SOUND_VOICES")


func _test_downed_has_no_particles() -> void:
	_setup()
	_bus.player_downed.emit(3)
	_check(_feel.live_effects() == 0, "a downed event names no position, so no effect")
	_check(_feel.stop_left > 0.0 and _feel.trauma() > 0.0, "a downed wizard still gets stop and shake")


func _test_feel_never_changes_damage() -> void:
	var results: Array = []
	for with_feel in [false, true]:
		_setup()
		var combat: Node = CombatScript.new()
		combat.events = _bus
		combat._ready()
		if not with_feel:
			_feel.free()
			_feel = null
		var damage: Array = []
		var deaths: Array = []
		_bus.damage_dealt.connect(func(p: int, _t: Node, amount: int, _at: Vector2) -> void:
			damage.append([p, amount]))
		_bus.enemy_died.connect(func(p: int, _e: Node, _at: Vector2) -> void:
			deaths.append(p))
		var enemy := Node2D.new()
		combat.register_actor(enemy, 10, 10.0, 0)
		for player in 4:
			combat.hit(player, enemy, 2)
		var health: int = combat.health_of(enemy)
		results.append([damage, deaths, health])
		if _feel != null:
			_feel.step(STEP)
		combat.free()
		enemy.free()
	_check(results[0] == results[1], "damage, deaths and health are the same with and without feel")
	_check(results[1][2] == 2 and results[1][1].is_empty(), "four hits of 2 leave 2 health, as combat says")


func _test_bursts_survive_the_world_being_freed() -> void:
	_setup()
	for round in 3:
		var world := Node2D.new()
		root.add_child(world)
		current_scene = world
		_hit(0, Vector2(4.0, 4.0))
		_check(_feel.live_effects() == 1, "an effect starts with a world scene (round %d)" % round)
		world.free()
		current_scene = null
		for i in 30:
			_feel.step(STEP)
	for shot in 12:
		_hit(shot % 4, Vector2(shot, 0.0))
	_check(_feel.live_effects() == 12, "after the world was freed three times, effects still show")


func _test_hit_stops_are_limited() -> void:
	_setup()
	var stopped: float = 0.0
	var total: float = 0.0
	for frame in 256:
		for player in 4:
			_hit(player)
		if _feel.stop_left > 0.0:
			stopped += 0.015625
		total += 0.015625
		_feel.step(0.015625)
	_check(stopped / total < 0.3, "a stream of hits keeps the stopped time under 30%% (was %.2f)" % (stopped / total))
	_check(stopped > 0.0, "a stream of hits still stops the game now and then")
	_setup()
	_hit(0)
	_feel.step(STEP)
	_check(_feel.rest_left > 0.0, "a rest follows a hit-stop")
	_hit(0)
	_check(_feel.stop_left == 0.0, "a plain hit in the rest does not stop the game")
	_bus.enemy_died.emit(0, null, Vector2.ZERO)
	_check(_feel.stop_left > 0.0, "a death stops the game even in the rest")


func _test_a_kill_uses_one_slot_and_beats_a_full_pool() -> void:
	_setup()
	_hit(0, Vector2(7.0, 7.0))
	_bus.enemy_died.emit(0, null, Vector2(7.0, 7.0))
	_check(_feel.effects_of(FeelScript.KIND_PUFF) == 1, "a killing blow's puff becomes the death puff: one slot, not two")
	_check(_feel.effects_of(FeelScript.KIND_RING_OUT) == 1, "and a white-hot ring")
	_feel.step(STEP)
	_feel.set_effect_slots(EffectSlots.MIN)
	for i in _feel.effect_slots:
		_hit(i % 4, Vector2(100.0 + i, 0.0))
	_check(_feel.live_effects() == _feel.effect_slots, "the slots are full of hit effects")
	_bus.enemy_died.emit(1, null, Vector2(-50.0, 9.0))
	_check(_feel.effects_of(FeelScript.KIND_PUFF) >= 1, "a kill gets its puff even when the slots are full (the oldest is taken)")
	_check(_feel.live_effects() == _feel.effect_slots, "taking one over keeps the limit")


func _test_engine_time_scale_comes_back() -> void:
	_setup()
	_feel.drive_engine = true
	_hit(0)
	_check(Engine.time_scale < 1.0, "a hit slows the engine")
	_feel.step(STEP)
	_check(Engine.time_scale == 1.0, "the engine is back to full speed when the stop ends")
	_bus.enemy_died.emit(0, null, Vector2.ZERO)
	_check(Engine.time_scale < 1.0, "a death slows the engine")
	_teardown()
	_check(Engine.time_scale == 1.0, "removing feel mid-stop restores the engine speed")


func _test_camera_change_is_followed() -> void:
	_setup()
	_camera.make_current()
	_hit(0)
	_feel.step(0.015625)
	_check(_camera.offset != Vector2.ZERO, "the first camera shakes")
	var second := Camera2D.new()
	root.add_child(second)
	second.make_current()
	_hit(0)
	_check(_camera.offset == Vector2.ZERO, "the old camera is put back at rest")
	_feel.step(0.015625)
	_check(second.offset != Vector2.ZERO, "the new camera shakes")
	second.free()


func _test_hit_flash_and_squash() -> void:
	_setup()
	var enemy := Node2D.new()
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	enemy.add_child(sprite)
	root.add_child(enemy)
	_bus.damage_dealt.emit(0, enemy, 1, Vector2.ZERO)
	_check(sprite.material != null, "a hit flashes the sprite")
	_check(_feel.reacting_sprites() == 1, "one sprite reacts")
	_feel.step(0.015625)
	_check(sprite.scale.x > 1.0 and sprite.scale.y < 1.0, "the sprite squashes")
	_bus.damage_dealt.emit(1, enemy, 1, Vector2.ZERO)
	_check(_feel.reacting_sprites() == 1, "a second hit on the same sprite does not add a reaction")
	for i in 4:
		_feel.step(STEP)
	_check(sprite.material == null, "the flash ends")
	_check(sprite.scale == Vector2.ONE, "the sprite is back to its size")
	_check(_feel.reacting_sprites() == 0, "no reaction is left")
	# A scale set by the sprite's owner mid-squash (a dash look) is kept, not overwritten.
	var dasher := Node2D.new()
	var dash_sprite := Sprite2D.new()
	dash_sprite.name = "Sprite"
	dasher.add_child(dash_sprite)
	root.add_child(dasher)
	_bus.damage_dealt.emit(0, dasher, 1, Vector2.ZERO)
	_feel.step(0.015625)
	dash_sprite.scale = Vector2(1.4, 0.7)
	_feel.step(0.015625)
	_check(dash_sprite.scale.x > 1.0 and dash_sprite.scale.y < 1.0, "a dash look set during a squash stays stretched")
	for i in 4:
		_feel.step(STEP)
	_check(dash_sprite.scale.is_equal_approx(Vector2(1.4, 0.7)), "the squash ends on the dash scale, not the old one")
	dasher.free()
	# A target without a Sprite, and one freed mid-flash, are fine.
	var bare := Node2D.new()
	_bus.damage_dealt.emit(0, bare, 1, Vector2.ZERO)
	bare.free()
	_bus.damage_dealt.emit(0, enemy, 1, Vector2.ZERO)
	enemy.free()
	_feel.step(STEP)
	_check(_feel.reacting_sprites() == 0, "a freed sprite is dropped")
	var crowd: Array[Node2D] = []
	for i in 40:
		var many := Node2D.new()
		var s := Sprite2D.new()
		s.name = "Sprite"
		many.add_child(s)
		root.add_child(many)
		crowd.append(many)
		_bus.damage_dealt.emit(i % 4, many, 1, Vector2.ZERO)
	_check(_feel.reacting_sprites() <= FeelScript.REACT_SLOTS, "reactions stay within their limit")
	for many in crowd:
		many.free()


func _test_cast_flash_and_kick() -> void:
	_setup()
	_bus.spell_cast.emit(2, &"fire_bolt", Vector2(10, 5), Vector2.RIGHT)
	_check(_feel.effects_of(FeelScript.KIND_CAST, 2) == 1, "a cast shows a cast flash")
	_check(_feel.kick().x < 0.0 and _feel.kick().y == 0.0, "the camera kicks against the aim")
	_feel.step(0.015625)
	_check(_camera.offset.x < 0.0, "the camera moves with the kick")
	for i in 100:
		_bus.spell_cast.emit(i % 4, &"fire_bolt", Vector2.ZERO, Vector2.RIGHT)
	_check(_feel.kick().length() <= FeelScript.MAX_KICK_PIXELS + 0.001, "the kick is capped")
	for i in 10:
		_feel.step(STEP)
	_check(_feel.effects_of(FeelScript.KIND_CAST) == 0, "the cast flashes end")
	_check(_camera.offset == Vector2.ZERO and _feel.kick() == Vector2.ZERO, "the camera settles after a cast")
	_feel.shake_enabled = false
	_bus.spell_cast.emit(0, &"fire_bolt", Vector2.ZERO, Vector2.RIGHT)
	_check(_feel.kick() == Vector2.ZERO, "no kick with shake off")


## The cast flash is a small effect at the staff tip: a cross of a few pixels and sparks that
## reach no further than a shot's own quad (zoom 1).
func _test_muzzle_flash_stays_small() -> void:
	_setup()
	_bus.spell_cast.emit(0, &"fire_bolt", Vector2.ZERO, Vector2.RIGHT)
	_feel.step(0.01)
	var multimesh: MultiMesh = _feel._effect_node.multimesh
	_check(multimesh.visible_instance_count == 1, "the cast flash is drawn")
	_check(is_equal_approx(multimesh.buffer[0], FeelScript.EFFECT_GRID), "in a quad of 24 px at most")


func _test_muzzle_flash_follows_aim_and_colour() -> void:
	_setup()
	_bus.spell_cast.emit(1, &"fire_bolt", Vector2(10, 5), Vector2.DOWN)
	_feel.step(0.01)
	_check(_feel.effects_of(FeelScript.KIND_CAST, 1) == 1, "player 2's cast flash shows")
	var buffer: PackedFloat32Array = _feel._effect_node.multimesh.buffer
	_check(Vector2(buffer[0], buffer[4]).normalized().is_equal_approx(Vector2.DOWN), "the cast flash turns along the aim")
	_check(roundi(buffer[8] * 255.0) % 4 == 1, "it is drawn in the colours of player 2")
	_check(is_equal_approx(buffer[3], 10.0) and is_equal_approx(buffer[7], 5.0), "at the staff tip")


func _test_cast_squash() -> void:
	_setup()
	var wizard := Node2D.new()
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	wizard.add_child(sprite)
	root.add_child(wizard)
	_bus.actor_cast.emit(0, wizard)
	_check(_feel.reacting_sprites() == 1, "a cast starts a reaction on the caster")
	_check(sprite.material == null, "a cast squash has no white flash")
	_feel.step(0.015625)
	_check(sprite.scale.x < 1.0 and sprite.scale.y > 1.0, "the caster gets thin and tall")
	# A hit during the cast squash takes it over; a cast during a hit does not.
	_bus.damage_dealt.emit(0, wizard, 1, Vector2.ZERO)
	_check(sprite.material != null and _feel.reacting_sprites() == 1, "a hit replaces the cast squash")
	_bus.actor_cast.emit(0, wizard)
	_check(sprite.material != null, "a cast does not replace a hit's flash")
	for i in 4:
		_feel.step(STEP)
	_check(sprite.scale == Vector2.ONE and sprite.material == null and _feel.reacting_sprites() == 0, "the sprite is back at rest")
	wizard.free()
	# Nothing to squash: no node, or a node without a Sprite.
	var bare := Node.new()
	_bus.actor_cast.emit(0, null)
	_bus.actor_cast.emit(0, bare)
	_check(_feel.reacting_sprites() == 0, "nothing reacts without a Sprite")
	bare.free()


func _test_death_animation() -> void:
	_setup()
	var texture := load("res://art/vfx/hit_spark.svg") as Texture2D
	var enemy := Node2D.new()
	enemy.position = Vector2(40, 30)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	enemy.add_child(sprite)
	root.add_child(enemy)
	_bus.enemy_died.emit(0, enemy, enemy.position)
	enemy.free()
	_check(_feel.live_ghosts() == 1, "a death starts an animation although the enemy is freed")
	var copy: Sprite2D = _feel.ghost(0)
	_check(copy.global_position == Vector2(40, 30) and copy.texture == texture, "the copy sits where the enemy was")
	var dissolve: ShaderMaterial = copy.material as ShaderMaterial
	_check(dissolve != null and dissolve.shader == FeelScript.SPRITE_SHADER, "drawn by the shots' sprite shader")
	var start: float = dissolve.get_shader_parameter(&"dissolve") as float
	_feel.step(0.1875)
	_check((dissolve.get_shader_parameter(&"dissolve") as float) > start, "the copy falls apart pixel by pixel")
	_check(copy.scale == Vector2.ONE and copy.modulate.a == 1.0, "never stretched nor faded: whole pixels go")
	for i in 4:
		_feel.step(STEP)
	_check(_feel.live_ghosts() == 0 and not copy.visible, "the animation ends")
	for i in 40:
		var many := Node2D.new()
		var s := Sprite2D.new()
		s.name = "Sprite"
		s.texture = texture
		many.add_child(s)
		root.add_child(many)
		_bus.enemy_died.emit(0, many, Vector2.ZERO)
		many.free()
	_check(_feel.live_ghosts() == FeelScript.GHOST_SLOTS, "death animations stay within their limit")
	var bare := Node2D.new()
	_bus.enemy_died.emit(0, null, Vector2.ZERO)
	_bus.enemy_died.emit(0, bare, Vector2.ZERO)
	bare.free()


func _test_death_puff_is_limited() -> void:
	_setup()
	_feel.set_effect_slots(EffectSlots.MIN)
	for i in 100:
		_bus.enemy_died.emit(i % 4, null, Vector2(i, 0))
	_check(_feel.live_effects() <= _feel.effect_slots, "death puffs stay within the effect slots")
	for i in 30:
		_feel.step(STEP)
	_check(_feel.live_effects() == 0, "the puffs end")


func _test_death_animation_starts_at_rest_scale() -> void:
	_setup()
	var enemy := Node2D.new()
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = load("res://art/vfx/hit_spark.svg") as Texture2D
	sprite.centered = false
	sprite.scale = Vector2(2.0, 2.0)
	enemy.add_child(sprite)
	root.add_child(enemy)
	_bus.damage_dealt.emit(0, enemy, 1, Vector2.ZERO)
	_feel.step(0.015625)
	_check(sprite.scale != Vector2(2.0, 2.0), "the enemy is squashed when it is killed")
	_bus.enemy_died.emit(0, enemy, Vector2.ZERO)
	enemy.free()
	var copy: Sprite2D = _feel.ghost(0)
	_check(copy.scale.is_equal_approx(Vector2(2.0, 2.0)), "the copy starts at the rest scale, not the squashed one")
	_check(not copy.centered, "the copy keeps the sprite's centring")


## A mover in the middle of a dash.
class DashingMover:
	extends Mover

	func is_moving() -> bool:
		return true


func _test_cast_squash_skips_a_dash() -> void:
	_setup()
	var wizard := ActorStandIn.new() as Actor
	var mover := DashingMover.new()
	wizard.mover = mover
	wizard.add_child(mover)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	wizard.add_child(sprite)
	root.add_child(wizard)
	_bus.actor_cast.emit(0, wizard)
	_check(_feel.reacting_sprites() == 0 and sprite.scale == Vector2.ONE, "a cast during a dash does not touch the sprite scale")
	wizard.free()
