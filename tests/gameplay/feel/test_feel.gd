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
const RegistryScript := preload("res://core/registry/registry.gd")

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
	_test_missing_sound_is_silent()
	_test_known_sound_plays()
	_test_downed_has_no_particles()
	_test_feel_never_changes_damage()
	_test_projectile_texture_is_set()
	_test_bursts_survive_the_world_being_freed()
	_test_hit_stops_are_limited()
	_test_a_kill_uses_one_slot_and_beats_a_full_pool()
	_test_engine_time_scale_comes_back()
	_test_camera_change_is_followed()
	_teardown()
	Node.print_orphan_nodes()
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


func _test_particle_limit_holds_with_four_players() -> void:
	_setup()
	var most: int = 0
	for frame in 30:
		for player in 4:
			for shot in 5:
				_hit(player, Vector2(10.0 * shot, 10.0 * player))
			_bus.enemy_died.emit(player, null, Vector2(5.0 * player, 0.0))
		_feel.step(0.015625)
		most = maxi(most, _feel.live_particles())
		_check(_feel.live_particles() <= FeelScript.PARTICLE_LIMIT, "live particles stay within PARTICLE_LIMIT (frame %d)" % frame)
	_check(most > 0, "hits make particles")
	_check(most == FeelScript.PARTICLE_LIMIT, "a flood fills the limit and no more")
	_check(FeelScript.BURST_PARTICLES * (FeelScript.PARTICLE_LIMIT / FeelScript.BURST_PARTICLES) == FeelScript.PARTICLE_LIMIT, "the limit is a whole number of bursts")
	var emitters: int = 0
	for child in _feel.get_children():
		if child is CPUParticles2D:
			emitters += 1
	_check(emitters <= FeelScript.PARTICLE_LIMIT / FeelScript.BURST_PARTICLES, "no more emitters exist than the limit allows")


func _test_particles_come_back() -> void:
	_setup()
	for i in 20:
		_hit(i % 4)
	_check(_feel.live_particles() == FeelScript.PARTICLE_LIMIT, "the pool is used up")
	for i in 8:
		_feel.step(STEP)
	_check(_feel.live_particles() == 0, "finished bursts return to the pool")
	_hit(0)
	_check(_feel.live_particles() == FeelScript.BURST_PARTICLES, "a returned burst can be used again")


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
	_check(_feel.live_particles() == 0, "a downed event names no position, so no burst")
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
		combat.register_enemy(enemy, 10, 10.0, 0)
		for player in 4:
			combat.hit(player, enemy, 2)
		var health: int = combat.get_health(enemy)
		results.append([damage, deaths, health])
		if _feel != null:
			_feel.step(STEP)
		combat.free()
		enemy.free()
	_check(results[0] == results[1], "damage, deaths and health are the same with and without feel")
	_check(results[1][2] == 2 and results[1][1].is_empty(), "four hits of 2 leave 2 health, as combat says")


func _test_projectile_texture_is_set() -> void:
	var texture := load("res://art/vfx/fire_bolt.svg") as Texture2D
	_check(texture != null, "the fire bolt art loads")
	var projectiles: Node = load("res://core/projectiles/projectile_manager.gd").new()
	_check(projectiles.texture == null, "the projectile texture starts empty")
	_setup(&"", projectiles)
	_check(projectiles.texture == texture, "feel sets Projectiles.texture to the fire bolt")
	projectiles.free()


func _test_bursts_survive_the_world_being_freed() -> void:
	_setup()
	for round in 3:
		var world := Node2D.new()
		root.add_child(world)
		current_scene = world
		_hit(0, Vector2(4.0, 4.0))
		_check(_feel.live_particles() == FeelScript.BURST_PARTICLES, "a burst starts with a world scene (round %d)" % round)
		world.free()
		current_scene = null
		for i in 9:
			_feel.step(STEP)
	for shot in 12:
		_hit(shot % 4, Vector2(shot, 0.0))
	_check(_feel.live_particles() == FeelScript.PARTICLE_LIMIT, "after the world was freed three times, bursts still fill the limit")


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
	_check(_feel.live_particles() == FeelScript.BURST_PARTICLES, "a killing blow uses one burst, not two")
	_feel.step(STEP)
	for i in FeelScript.BURST_SLOTS:
		_hit(i % 4, Vector2(100.0 + i, 0.0))
	_check(_feel.live_particles() == FeelScript.PARTICLE_LIMIT, "the pool is full of hit bursts")
	_bus.enemy_died.emit(1, null, Vector2(-50.0, 9.0))
	var found: bool = false
	for child in _feel.get_children():
		if child is CPUParticles2D and (child as CPUParticles2D).global_position == Vector2(-50.0, 9.0):
			found = true
	_check(found, "a kill gets a burst even when the pool is full of hit bursts")
	_check(_feel.live_particles() == FeelScript.PARTICLE_LIMIT, "taking a burst over keeps the limit")


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
