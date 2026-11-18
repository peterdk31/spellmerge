extends "res://tests/support/suite.gd"
## The atmosphere's settings in Feel (docs/milestones/atmosphere.md, "Settings"): each switch heard
## on its core event and making or freeing its part with nothing left over, flipped mid-room as often
## as wished. "Shadows" (C: the light's blockers and the bodies' shadows, the staff's drawn shadow
## back with them off), "Fog" (F: the mist) and "Ambient particles" (B: the air's dust) need
## "Dynamic lighting" (the spell light); "Environment interaction" (E) off reads no shot and starts no
## blast, the wake easing out to a still field; "Ambience volume" (D) reaches Audio from the saved
## choice (its bus and its easing are tests/core/audio/test_audio_buses.gd's).

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const SpectacleScript := preload("res://gameplay/feel/spectacle.gd")
const MistScript := preload("res://gameplay/feel/mist.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const StirsScript := preload("res://gameplay/feel/stirs.gd")
const SpotStirsScript := preload("res://gameplay/feel/spot_stirs.gd")
const AirMotesScript := preload("res://gameplay/feel/air_motes.gd")
const AudioScript := preload("res://core/audio/audio.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const FRAME: float = 1.0 / 60.0
const VIEW := Rect2(0.0, 0.0, 640.0, 360.0)
const STRIDE: int = ProjectilesScript.SPARK_BIRTH_STRIDE
## arena_03 (the ossuary court): four bone walls that block its light. arena_04: a mist.
const WALLED_ROOM: StringName = &"arena_03"
const WALLS: int = 4
const MIST_ROOM: StringName = &"arena_04"

var registry: RegistryScript = null


func before_each() -> void:
	registry = own(RegistryScript.new()) as RegistryScript
	registry.scan()


## Feel on a bus, a table and a projectile manager of its own: [bus, feel].
func _feel() -> Array:
	var bus: EventsScript = own(EventsScript.new()) as EventsScript
	var table: Node = own(ActorSeats.table()) as Node
	var manager: ProjectilesScript = own(ProjectilesScript.new()) as ProjectilesScript
	manager.events = bus
	manager.actors = table
	root.add_child(manager)
	var audio: AudioScript = own(AudioScript.new()) as AudioScript
	audio.events = bus
	audio.registry = registry
	root.add_child(audio)
	var feel: FeelScript = own(FeelScript.new()) as FeelScript
	feel.audio = audio
	var preset := FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = bus
	feel.registry = registry
	feel.actors = table
	feel.projectiles = manager
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)
	return [bus, feel, audio]


## The room `id` built and entered.
func _enter(bus: EventsScript, id: StringName) -> void:
	var room := registry.get_resource(&"rooms", id) as RoomBase
	bus.room_built.emit(room.id, own(room.build(null)) as Node)
	bus.room_entered.emit(room.id)


func _frames(feel: FeelScript, count: int) -> void:
	for frame in count:
		feel._process(FRAME)


# --- The defaults ---------------------------------------------------------------------------------

func test_feel_starts_at_the_settings_defaults() -> void:
	var made: Array = _feel()
	var feel: FeelScript = made[1]
	var audio: AudioScript = made[2]
	var spectacle: SpectacleScript = feel.spectacle()
	check_equal(spectacle.shadows_on, ShadowsSetting.default_on(), "Shadows")
	check_equal(spectacle.fog, FogSetting.default_on(), "Fog")
	check_equal(spectacle.ambient_particles, AmbientParticles.default_on(), "Ambient particles")
	check_equal(spectacle.environment_interaction, EnvironmentInteraction.default_on(), "Environment interaction")
	check(is_equal_approx(audio.buses.volume(AudioScript.BUS_AMBIENCE), AmbienceVolume.share_of(AmbienceVolume.DEFAULT)), "Ambience volume")


# --- Shadows --------------------------------------------------------------------------------------

func test_shadows_off_eases_out_then_frees_the_shadows_mid_room() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var spectacle: SpectacleScript = feel.spectacle()
	bus.spell_light_changed.emit(true)
	_enter(bus, WALLED_ROOM)
	_frames(feel, 2)
	check(spectacle.shadows != null and spectacle.light.blocker_count() == WALLS, "on: the shadows drawn and the walls block")
	var children: int = spectacle.get_child_count()
	for flip in 3:
		bus.shadows_changed.emit(false)
		check(spectacle.shadows != null, "off: kept while it eases out")
		var frames: int = _fade_out(feel, func() -> bool: return spectacle.shadows == null, func() -> float: return spectacle.blockers.share)
		check(frames >= 3, "eased out over %d frames (at least 3)" % frames)
		check_equal(spectacle.light.blocker_count(), 0, "off: nothing blocks the light")
		check_equal(spectacle.get_child_count(), children - 1, "off: only the shadows' node is gone")
		bus.shadows_changed.emit(true)
		check(spectacle.shadows != null and spectacle.shadows.share == 0.0, "on again: made, from none")
		_frames(feel, 1)
		check_equal(spectacle.light.blocker_count(), WALLS, "the walls handed over at the next step")
		check(spectacle.blockers.bodies[0].w < 1.0, "easing in (the boxes' strength, %s)" % spectacle.blockers.bodies[0].w)
		_frames(feel, 30)
		check(spectacle.shadows.share == 1.0 and is_equal_approx(spectacle.blockers.bodies[0].w, 1.0), "eased all the way in")
		check_equal(spectacle.get_child_count(), children, "on again: as many children as before")


## Frames of Feel until `gone` says the layer is gone (at most 60), each frame's step of `share`
## (0 to 1) at most a frame's share of LAYER_FADE_SECONDS; the frames taken.
func _fade_out(feel: FeelScript, gone: Callable, share: Callable) -> int:
	var last: float = share.call()
	var most: float = FRAME / SpectacleScript.LAYER_FADE_SECONDS + 0.0001
	var frames: int = 0
	while not gone.call() and frames < 60:
		feel._process(FRAME)
		frames += 1
		if gone.call():
			break
		var now: float = share.call()
		check(last - now <= most, "a frame eases at most its share (%s to %s)" % [last, now])
		last = now
	check(gone.call(), "gone once faded out")
	return frames


func test_with_shadows_off_the_staffs_own_shadow_shows_again() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var drawn := Node2D.new()
	drawn.add_to_group(LightSpot.DRAWN_SHADOW)
	root.add_child(own(drawn))
	bus.spell_light_changed.emit(true)
	check(not drawn.visible, "the cast shadows take the drawn one's place")
	bus.shadows_changed.emit(false)
	check(not drawn.visible, "shadows off: hidden while the cast shadows ease out")
	_frames(feel, 30)
	check(drawn.visible, "faded out: the drawn shadow shows again")
	bus.shadows_changed.emit(true)
	check(not drawn.visible, "on again: hidden again")
	bus.spell_light_changed.emit(false)
	check(drawn.visible, "and with the light off, as before")
	check(feel.spectacle().light == null, "no light")


func test_shadows_need_dynamic_lighting() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var spectacle: SpectacleScript = feel.spectacle()
	bus.spell_light_changed.emit(false)
	bus.shadows_changed.emit(true)
	check(spectacle.shadows == null and spectacle.shadows_on, "the light off: the choice kept, nothing drawn")
	bus.spell_light_changed.emit(true)
	check(spectacle.shadows != null, "the light on: the shadows come with it")
	bus.shadows_changed.emit(false)
	bus.spell_light_changed.emit(false)
	bus.spell_light_changed.emit(true)
	check(spectacle.shadows == null and spectacle.light != null, "shadows off: the light made anew comes without them")
	_enter(bus, WALLED_ROOM)
	_frames(feel, 2)
	check_equal(spectacle.light.blocker_count(), 0, "and blocks nothing")
	bus.shadows_changed.emit(true)
	_frames(feel, 30)
	check_equal(spectacle.light.blocker_count(), WALLS, "shadows on again under that light: the walls block it")


# --- Fog ------------------------------------------------------------------------------------------

func test_fog_off_eases_out_then_frees_the_mist_and_on_eases_it_in_with_the_room() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var spectacle: SpectacleScript = feel.spectacle()
	bus.spell_light_changed.emit(true)
	_enter(bus, MIST_ROOM)
	var room := registry.get_resource(&"rooms", MIST_ROOM) as RoomBase
	check(spectacle.mist != null and spectacle.mist.share == 1.0, "on: the mist is made, at full")
	var children: int = spectacle.get_child_count()
	for flip in 3:
		bus.fog_changed.emit(false)
		check(spectacle.mist != null, "off: kept while it eases out")
		var mist: MistScript = spectacle.mist
		var frames: int = _fade_out(feel, func() -> bool: return spectacle.mist == null, func() -> float: return mist.share)
		check(frames >= 3, "thinned out over %d frames" % frames)
		check_equal(spectacle.get_child_count(), children - 1, "off: the mist node is gone")
		bus.fog_changed.emit(true)
		check(spectacle.mist != null and spectacle.mist.mist == room.mist and spectacle.mist.room_size == room.places().size, "on again: with the room's mist and room")
		check(is_zero_approx(float((spectacle.mist.material as ShaderMaterial).get_shader_parameter(&"thickness"))), "from nothing")
		check(spectacle.get_children().back() == spectacle.mist, "and last at its z, over the shadows and the marks")
		check((spectacle.mist.material as ShaderMaterial).get_shader_parameter(&"light_buffer") == spectacle.light.buffer(), "lit by the light's buffer")
		_frames(feel, 30)
		check(is_equal_approx(float((spectacle.mist.material as ShaderMaterial).get_shader_parameter(&"thickness")), room.mist.thickness), "eased in to the room's thickness")


func test_fog_needs_dynamic_lighting_and_stays_over_shadows_made_later() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var spectacle: SpectacleScript = feel.spectacle()
	bus.spell_light_changed.emit(false)
	_enter(bus, MIST_ROOM)
	check(spectacle.mist == null and spectacle.fog, "the light off: no mist, the choice kept")
	bus.spell_light_changed.emit(true)
	check(spectacle.mist != null, "the light on: the mist with it")
	bus.shadows_changed.emit(false)
	bus.shadows_changed.emit(true)
	var children: Array[Node] = spectacle.get_children()
	check(children.find(spectacle.mist) > children.find(spectacle.shadows), "shadows made again lie under the mist")
	bus.fog_changed.emit(false)
	bus.spell_light_changed.emit(false)
	bus.spell_light_changed.emit(true)
	check(spectacle.mist == null, "fog off: the light made anew comes without it")
	bus.fog_changed.emit(true)
	bus.spell_light_changed.emit(false)
	bus.spell_light_changed.emit(true)
	check(spectacle.mist != null and spectacle.mist.share == 1.0, "fog on: a light made anew brings it at full, as it comes at once")
	_frames(feel, 2)


# --- Ambient particles ----------------------------------------------------------------------------

func test_ambient_particles_off_gives_off_no_air_mid_room() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var air: AirMotesScript = feel.spectacle().air
	bus.spell_light_changed.emit(true)
	bus.room_entered.emit(&"arena_01")
	_frames(feel, 60)
	check(air.given > 0, "on: the room's dust is given off")
	bus.ambient_particles_changed.emit(false)
	var given: int = air.given
	_frames(feel, 60)
	check_equal(air.given, given, "off: none")
	bus.ambient_particles_changed.emit(true)
	_frames(feel, 60)
	check(air.given > given, "on again: given off again")
	bus.spell_light_changed.emit(false)
	given = air.given
	_frames(feel, 60)
	check_equal(air.given, given, "it needs the light: none with it off")


# --- Environment interaction ----------------------------------------------------------------------

## `count` tail births along a line through `from`, flying right (the projectile manager's layout).
func _births(from: Vector2, count: int) -> PackedFloat32Array:
	var births := PackedFloat32Array()
	births.resize(count * STRIDE)
	for n in count:
		var i: int = n * STRIDE
		births[i + ProjectilesScript.SPARK_X] = from.x + float(n) * 4.0
		births[i + ProjectilesScript.SPARK_Y] = from.y
		births[i + ProjectilesScript.SPARK_BACK_X] = -4.0
		births[i + ProjectilesScript.SPARK_BACK_Y] = 0.0
	return births


func test_interaction_off_reads_no_shot_and_starts_no_blast() -> void:
	var stirs := StirsScript.new()
	stirs.enabled = false
	stirs.step(0.0, _births(Vector2(200.0, 150.0), 16), 16, VIEW)
	check_equal(stirs.read, 0, "no shot read")
	check_equal(stirs.live_cells(), 0, "no wake")
	stirs.blast(Vector2(200.0, 150.0), 24.0, 0.0)
	check_equal(stirs.blast_count(), 0, "no blast")
	check(stirs.shots_near(Vector2(210.0, 150.0), 30.0) == Vector3.ZERO, "no shot near anything")
	var material := ShaderMaterial.new()
	stirs.hand_to(material)
	var strength: PackedFloat32Array = material.get_shader_parameter(&"stir_strength")
	check(strength.count(0.0) == StirsScript.BLASTS, "the shaders are handed no push")
	var cell: Color = stirs.texture.get_image().get_pixel(12, 9)
	check(cell.r == 0.0 and cell.g == 0.0, "and a still field")


func test_interaction_off_mid_wake_eases_back_to_still_with_no_jump() -> void:
	var stirs := StirsScript.new()
	var at := Vector2(200.0, 150.0)
	var now: float = 0.0
	for frame in 20:
		stirs.step(now, _births(at, 16), 16, VIEW)
		now += FRAME
	var before: Vector2 = stirs.wake_at(at + Vector2(16.0, 0.0))
	check(before.length() > 0.1, "a wake dragged")
	stirs.enabled = false
	var biggest: float = 0.0
	var last: Vector2 = before
	for frame in 120:
		stirs.step(now, _births(at, 16), 16, VIEW)
		now += FRAME
		var shown: Vector2 = stirs.wake_at(at + Vector2(16.0, 0.0))
		biggest = maxf(biggest, last.distance_to(shown))
		last = shown
	check(biggest <= StirsScript.SHOWN_RATE * FRAME + 0.001, "off: it eases out a frame's share at a time, the biggest step %s" % biggest)
	check_equal(stirs.live_cells(), 0, "and is still again")
	stirs.enabled = true
	stirs.step(now, _births(at, 16), 16, VIEW)
	check(stirs.read > 0, "on again: the shots are read")


func test_feel_with_interaction_off_pushes_nothing_and_its_lights_rest() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var spectacle: SpectacleScript = feel.spectacle()
	var spot := Marker2D.new()
	spot.position = Vector2(100.0, 100.0)
	spot.add_to_group(LightSpot.GROUP)
	root.add_child(own(spot))
	bus.spell_light_changed.emit(true)
	spectacle.light.draw_spots()
	bus.environment_interaction_changed.emit(false)
	check(not spectacle.stirs.enabled and not spectacle.environment_interaction, "the stirs are off")
	feel.show_flash(&"fireball", Vector2(90.0, 100.0), Vector2.RIGHT, Color.WHITE, 0, 0, 12, 0.4)
	check_equal(spectacle.stirs.blast_count(), 0, "an explosion pushes nothing")
	_frames(feel, 6)
	var spots: SpotStirsScript = spectacle.spot_stirs
	check(not spots.stirred, "the candle is at rest")
	bus.environment_interaction_changed.emit(true)
	feel.show_flash(&"fireball", Vector2(90.0, 100.0), Vector2.RIGHT, Color.WHITE, 0, 0, 12, 0.4)
	check_equal(spectacle.stirs.blast_count(), 1, "on again: it pushes")
	_frames(feel, 4)
	check(spectacle.spot_stirs.stirred, "and the candle leans")
	bus.environment_interaction_changed.emit(false)
	_frames(feel, 120)
	check(not spectacle.spot_stirs.stirred, "off mid-lean: the candle settles back to rest")
	check_equal(spectacle.stirs.blast_count(), 0, "the blast under way ran out")


# --- Ambience volume ------------------------------------------------------------------------------

## A silent 8 kHz looping stream.
# --- Nothing left over ----------------------------------------------------------------------------

func test_flipping_every_switch_leaves_nothing_over() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var spectacle: SpectacleScript = feel.spectacle()
	bus.spell_light_changed.emit(true)
	_enter(bus, MIST_ROOM)
	# Its ambience's sounds loaded first: an accent first heard in a later round (its gap is the
	# dice's) would load its file then, a cache filled once, not an object left over.
	var room := registry.get_resource(&"rooms", MIST_ROOM) as RoomBase
	if room.ambience != null:
		for accent: AmbienceAccent in room.ambience.accents:
			for id: StringName in accent.sounds:
				registry.get_sound(id)
	_frames(feel, 4)
	var children: int = spectacle.get_child_count()
	var objects: float = 0.0
	for round in 4:
		bus.shadows_changed.emit(false)
		bus.fog_changed.emit(false)
		bus.ambient_particles_changed.emit(false)
		bus.environment_interaction_changed.emit(false)
		_frames(feel, 30)
		bus.spell_light_changed.emit(false)
		_frames(feel, 4)
		bus.shadows_changed.emit(true)
		bus.fog_changed.emit(true)
		bus.ambient_particles_changed.emit(true)
		bus.environment_interaction_changed.emit(true)
		bus.spell_light_changed.emit(true)
		_frames(feel, 4)
		# Off and on again mid-fade, and the light flipped while a layer eases.
		bus.shadows_changed.emit(false)
		bus.fog_changed.emit(false)
		_frames(feel, 5)
		bus.spell_light_changed.emit(false)
		bus.spell_light_changed.emit(true)
		bus.shadows_changed.emit(true)
		bus.fog_changed.emit(true)
		_frames(feel, 30)
		# The freed nodes go at the frame's end.
		await process_frame
		# Counted from the second round (the first fills a cache once).
		if round == 1:
			objects = Performance.get_monitor(Performance.OBJECT_COUNT)
	check_equal(spectacle.get_child_count(), children, "as many children as before")
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "each round of flips leaves no object over")


# --- From the save to Feel ------------------------------------------------------------------------
# At boot the Hud (its pause menu) binds after Feel (project.godot's autoload order: Feel before Hud)
# and sends each saved choice that is not its default. The same here, with the real Hud scene and
# Feel on one bus of their own and a save of the test's own (the autoloads have booted already).

const HUD_SCENE_PATH: String = "res://hud/panels/panels.tscn"
const InputManagerScript := preload("res://core/input/input_manager.gd")
const UIFocusScript := preload("res://core/ui_focus/ui_focus.gd")
const SAVE_PATH: String = "user://test_atmosphere_settings_save.cfg"


func test_saved_choices_reach_feel_when_the_hud_binds() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	var saved := SaveFile.new(SAVE_PATH)
	saved.set_setting(&"shadows", not ShadowsSetting.default_on())
	saved.set_setting(&"fog", not FogSetting.default_on())
	saved.set_setting(&"ambient_particles", not AmbientParticles.default_on())
	saved.set_setting(&"environment_interaction", not EnvironmentInteraction.default_on())
	saved.set_setting(&"ambience_volume", 40)
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var audio: AudioScript = made[2]
	var input: InputManagerScript = own(InputManagerScript.new()) as InputManagerScript
	input.events = bus
	var focus: UIFocusScript = own(UIFocusScript.new()) as UIFocusScript
	focus.input = input
	focus.events = bus
	focus._ready()
	var hud: Node = own((load(HUD_SCENE_PATH) as PackedScene).instantiate()) as Node
	hud.set(&"events", bus)
	hud.set(&"ui_focus", focus)
	hud.set(&"input", input)
	hud.set(&"save", SaveFile.new(SAVE_PATH))
	root.add_child(hud)
	var spectacle: SpectacleScript = feel.spectacle()
	check_equal(spectacle.shadows_on, not ShadowsSetting.default_on(), "Shadows reached Feel")
	check_equal(spectacle.fog, not FogSetting.default_on(), "Fog reached Feel")
	check_equal(spectacle.ambient_particles, not AmbientParticles.default_on(), "Ambient particles reached Feel")
	check_equal(spectacle.environment_interaction, not EnvironmentInteraction.default_on(), "Environment interaction reached Feel")
	check(is_equal_approx(audio.buses.volume(AudioScript.BUS_AMBIENCE), AmbienceVolume.share_of(40)), "Ambience volume reached Audio")
	audio.buses.reset()
	root.remove_child(hud)
	DirAccess.remove_absolute(SAVE_PATH)
