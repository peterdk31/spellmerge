extends "res://tests/support/suite.gd"
## The music the game names (sound plan AU7, docs/milestones/sound.md, section 4): every
## `MusicTrack` of a room or an enemy (a boss's included), found through the registry. Each layer
## that has a file is a loop (imported with `loop` on), the layers of one track are of one length
## (they start together and must stay together), and a boss's phases bring in every layer of its
## music. The audio itself (one length, the seam, the level) is the sequencer's tests'
## (tools/test_sound_score.py); here is what Godot imports and the data names.

const RegistryScript := preload("res://core/registry/registry.gd")

## How far apart two layers' lengths may be (s): a sample is 0.023 ms.
const LENGTH_SLACK: float = 0.001

var registry: RegistryScript


func before_each() -> void:
	registry = own(RegistryScript.new()) as RegistryScript
	registry.scan()


func test_every_layer_with_a_file_loops_and_a_tracks_layers_are_of_one_length() -> void:
	var tracks: Dictionary = _tracks()
	check(not tracks.is_empty(), "the rooms and enemies name music")
	var files: int = 0
	for owner: String in tracks:
		var track: MusicTrack = tracks[owner]
		var length: float = -1.0
		for id: StringName in track.layers:
			var stream: AudioStream = registry.get_sound(id)
			if stream == null:
				continue  # named before it is made: silent (audio/README.md, "Sound ids")
			files += 1
			var ogg := stream as AudioStreamOggVorbis
			check(ogg != null, "%s: its layer %s is an Ogg Vorbis file" % [owner, id])
			if ogg == null:
				continue
			check(ogg.loop, "%s: its layer %s is imported to loop (loop=true in its .import)" % [owner, id])
			if length < 0.0:
				length = ogg.get_length()
			check(absf(ogg.get_length() - length) <= LENGTH_SLACK,
					"%s: its layer %s is %.3f s, the first %.3f s; a track's layers are of one length" % [owner, id, ogg.get_length(), length])
	check(files >= 3, "the boss's two layers and the crypt's track have files (%d)" % files)


func test_a_bosss_phases_bring_in_every_layer_of_its_music() -> void:
	var bosses: int = 0
	for res: Resource in registry.get_all(&"bosses"):
		var boss := res as EnemyBase
		if boss == null or boss.music == null:
			continue
		bosses += 1
		var heard := PackedByteArray()
		var ever := PackedByteArray()
		ever.resize(boss.music.layers.size())
		for intensity: int in _intensities(boss):
			boss.music.audible(intensity, heard)
			for i in ever.size():
				ever[i] = ever[i] | heard[i]
		for i in ever.size():
			check(ever[i] == 1, "%s: its music's layer %s is heard in some phase" % [boss.id, boss.music.layers[i]])
	check(bosses >= 1, "a boss has music")


func test_the_crypts_fight_rooms_name_their_music() -> void:
	for res: Resource in registry.get_all(&"rooms"):
		var room := res as RoomBase
		if room == null or room.biome != &"crypt" or not room.hosts(&"fight"):
			continue
		check(room.music != null and not room.music.layers.is_empty(), "%s has music" % room.id)


## Every room's and enemy's music, by who names it.
func _tracks() -> Dictionary:
	var found: Dictionary = {}
	for res: Resource in registry.get_all(&"rooms"):
		var room := res as RoomBase
		if room != null and room.music != null:
			found["room %s" % room.id] = room.music
	for folder: StringName in [&"enemies", &"bosses"]:
		for res: Resource in registry.get_all(folder):
			var enemy := res as EnemyBase
			if enemy != null and enemy.music != null:
				found["%s %s" % [folder, enemy.id]] = enemy.music
	return found


## The music's intensity before its first phase and in each phase: 1, then each phase's own
## `intensity`, or one more than the phase before (`intensity_of` in gameplay/feel/body_sounds.gd).
func _intensities(boss: EnemyBase) -> Array[int]:
	var out: Array[int] = [1]
	for phase: EnemyPhase in boss.phases:
		out.append(phase.intensity if phase != null and phase.intensity > 0 else out[-1] + 1)
	return out
