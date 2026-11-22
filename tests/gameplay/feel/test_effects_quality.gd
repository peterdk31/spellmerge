extends "res://tests/support/suite.gd"
## How much the effects cost (gameplay/feel/effects_quality.gd; the owner's one pass, 2026-11-22): a row
## of numbers a level, the high row the look as it was, and the spectacle handing each to its effect,
## again to a light or a mist made anew.

const EventsScript := preload("res://core/events/events.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const SpectacleScript := preload("res://gameplay/feel/spectacle.gd")
const MistScript := preload("res://gameplay/feel/mist.gd")
const LightGridScript := preload("res://gameplay/feel/light_grid.gd")
const EffectsQualityScript := preload("res://gameplay/feel/effects_quality.gd")
const AudioScript := preload("res://core/audio/audio.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const FRAME: float = 1.0 / 60.0
const MIST_ROOM: StringName = &"arena_04"

var registry: RegistryScript = null


func before_each() -> void:
	registry = own(RegistryScript.new()) as RegistryScript
	registry.scan()


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
	bus.room_built.emit(room.id, 0, own(room.build(null)) as Node)
	bus.room_entered.emit(room.id, 0)


func _frames(feel: FeelScript, count: int) -> void:
	for frame in count:
		feel._process(FRAME)


func test_every_level_has_a_row_the_effects_can_take() -> void:
	for level: int in EffectsQualityScript.Level.values():
		var quality := EffectsQualityScript.new(level as EffectsQualityScript.Level)
		check_equal(int(quality.level), level, "level %d has its row" % level)
		check(LightGridScript.CELLS.has(quality.light_cell), "a cell the grid offers (%s)" % quality.light_cell)
		check(quality.mist_billows >= 1 and quality.mist_billows <= 3, "1 to 3 layers of billows")
		check(quality.air_share > 0.0 and quality.air_share <= 1.0, "a share of the air")
	var high := EffectsQualityScript.new()
	check_equal(int(high.level), int(EffectsQualityScript.Level.HIGH), "high unless told")
	check(high.light_cell == LightGridScript.CELL and high.light_smooth and high.mist_billows == 3 and high.air_share == 1.0, "the high row is the look as it was")
	var low := EffectsQualityScript.new(EffectsQualityScript.Level.LOW)
	check(low.light_cell > high.light_cell and low.mist_billows < high.mist_billows and low.air_share < high.air_share, "the low row is cheaper in each")


func _billows(mist: MistScript) -> int:
	var value: Variant = (mist.material as ShaderMaterial).get_shader_parameter(&"billows")
	return int(value) if value != null else -1


func test_the_spectacle_hands_each_number_to_its_effect() -> void:
	var made: Array = _feel()
	var bus: EventsScript = made[0]
	var feel: FeelScript = made[1]
	var spectacle: SpectacleScript = feel.spectacle()
	bus.spell_light_changed.emit(true)
	bus.fog_changed.emit(true)
	_enter(bus, MIST_ROOM)
	_frames(feel, 2)
	if spectacle.light == null or spectacle.mist == null:
		check(false, "the light and the mist are drawn")
		return
	check_equal(spectacle.light.grid.cell, LightGridScript.CELL, "high: the light in 8 px cells")
	check_equal(_billows(spectacle.mist), 3, "high: three layers of billows")
	check_equal(int(spectacle.set_effects_quality(EffectsQualityScript.Level.LOW)), int(EffectsQualityScript.Level.LOW), "low taken")
	check_equal(spectacle.light.grid.cell, 16.0, "low: the light in coarser cells")
	check(spectacle.light.grid_smooth == spectacle.quality.light_smooth, "and smoothed as its row says")
	check_equal(_billows(spectacle.mist), 1, "low: one layer of billows")
	# A later room's mist (a biome's) takes the level too.
	var later := own(MistScript.new(SpectacleScript.MARK_Z)) as MistScript
	spectacle.room_mists.append(later)
	spectacle.set_effects_quality(EffectsQualityScript.Level.HIGH)
	check_equal(_billows(later), 3, "a later room's mist: three layers")
	spectacle.set_effects_quality(EffectsQualityScript.Level.LOW)
	check_equal(_billows(later), 1, "and one")
	spectacle.room_mists.erase(later)
	bus.spell_light_changed.emit(false)
	bus.spell_light_changed.emit(true)
	_frames(feel, 1)
	check(spectacle.light != null and spectacle.light.grid.cell == 16.0, "a light made anew takes the level")
	check(spectacle.mist != null and _billows(spectacle.mist) == 1, "and so does a mist made anew")
	spectacle.set_effects_quality(EffectsQualityScript.Level.HIGH)
	check_equal(spectacle.light.grid.cell, LightGridScript.CELL, "high again: 8 px cells")
	check_equal(_billows(spectacle.mist), 3, "and three layers")


## The mist's shader works out as many layers as it is told, three the sum as it was (in its order),
## and the script keeps the number to 1 to 3.
func test_the_mists_billows_are_its_shaders_and_kept_in_range() -> void:
	var density: String = (load("res://gameplay/feel/mist_density.gdshaderinc") as ShaderInclude).code
	check(density.contains("uniform int billows = 3;"), "the shader takes the number of layers, three unless told")
	var first: int = density.find("float n = mist_noise((q - moved) / scale);")
	var second: int = density.find("n = 0.55 * n + 0.3 * mist_noise(")
	var third: int = density.find("n += billows > 2 ? 0.15 * mist_noise(")
	check(first >= 0 and second > first and third > second, "three layers add up in the order they did: (0.55 a + 0.3 b) + 0.15 c")
	var mist := own(MistScript.new(SpectacleScript.MARK_Z)) as MistScript
	for asked: int in [0, 1, 2, 3, 9]:
		mist.set_billows(asked)
		check_equal(_billows(mist), clampi(asked, 1, 3), "%d asked: %d" % [asked, clampi(asked, 1, 3)])
