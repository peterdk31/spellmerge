extends RefCounted
## The sound room's list (docs/milestones/sound.md, section 7): every sound id the game names, read
## from its data, never from a list kept here: the cues' `sound` and their `held` parts', an enemy's
## `death_sound`, its phases' held `look.sound` and its music, a room's music and its ambience's
## layers and accents, and the ids Feel names itself (its preset's `hit_sound`, the cast sound),
## which the room hands to `read`. Each id has the kind it is played as (the first that names it
## wins) and where it is named; every music track is kept too, with its owner.
##
##     var names := SoundNames.new()
##     names.read(registry, [[&"hit", "Feel's hit"]])
##     for id: StringName in names.ids(): ...

## How a sound is played: a one-shot (SFX), held while its moment lasts (SFX), a layer of a music
## track (MusicDuck), a room's bed loop or one of its accents (Ambience).
enum Kind { ONE_SHOT, HELD, MUSIC, BED, ACCENT }

## Each named id's kind, and where it is named (lines such as "cue hit_spark").
var kinds: Dictionary[StringName, Kind] = {}
var where: Dictionary[StringName, PackedStringArray] = {}
## Every music track the data names (each once), and its owner's name, by index.
var tracks: Array[MusicTrack] = []
var track_owners: PackedStringArray = PackedStringArray()


## Reads every folder of `registry` (`get_folders`, `get_all`), and `feel`'s own ids: pairs of
## [id, where].
func read(registry: Node, feel: Array) -> void:
	kinds.clear()
	where.clear()
	tracks.clear()
	track_owners.clear()
	for pair: Array in feel:
		note(pair[0] as StringName, Kind.ONE_SHOT, pair[1] as String)
	var folders: Array[StringName] = registry.call(&"get_folders")
	var seen_beds: Array[Ambience] = []
	for folder: StringName in folders:
		var all: Array[Resource] = registry.call(&"get_all", folder)
		for resource: Resource in all:
			if resource is CueBase:
				_read_cue(resource as CueBase)
			elif resource is EnemyBase:
				_read_enemy(resource as EnemyBase)
			elif resource is RoomBase:
				var room := resource as RoomBase
				_read_track(room.music, "room %s" % room.id)
				if room.ambience != null and not seen_beds.has(room.ambience):
					seen_beds.append(room.ambience)
					_read_bed(room.ambience, "room %s" % room.id)


## Every named id, in id order.
func ids() -> Array[StringName]:
	var found: Array[StringName] = []
	for id: StringName in kinds:
		found.append(id)
	found.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return found


## Names `id` (empty: nothing) as played as `kind`, at `place`.
func note(id: StringName, kind: Kind, place: String) -> void:
	if id == &"":
		return
	if not kinds.has(id):
		kinds[id] = kind
		where[id] = PackedStringArray()
	if not where[id].has(place):
		where[id].append(place)


## The track that plays `id` as a layer, and that layer's place in it ([track, layer]; [] for none).
func track_of(id: StringName) -> Array:
	for track: MusicTrack in tracks:
		var at: int = track.layers.find(id)
		if at >= 0:
			return [track, at]
	return []


func _read_cue(cue: CueBase) -> void:
	note(cue.sound, Kind.ONE_SHOT, "cue %s" % cue.id)
	for part: Dictionary in cue.parts:
		if StringName(part.get("part", "")) == &"held":
			note(StringName(part.get("sound", "")), Kind.HELD, "cue %s held" % cue.id)


func _read_enemy(enemy: EnemyBase) -> void:
	note(enemy.death_sound, Kind.ONE_SHOT, "enemy %s death" % enemy.id)
	_read_track(enemy.music, "enemy %s" % enemy.id)
	for at in enemy.phases.size():
		var phase: EnemyPhase = enemy.phases[at]
		if phase != null and phase.look != null:
			note(phase.look.sound, Kind.HELD, "enemy %s phase %d" % [enemy.id, at])


func _read_track(track: MusicTrack, owner: String) -> void:
	if track == null:
		return
	if not tracks.has(track):
		tracks.append(track)
		track_owners.append(owner)
	for layer: StringName in track.layers:
		note(layer, Kind.MUSIC, "music of %s" % owner)


func _read_bed(bed: Ambience, owner: String) -> void:
	for layer: AmbienceLayer in bed.layers:
		if layer != null:
			note(layer.sound, Kind.BED, "ambience of %s" % owner)
	for accent: AmbienceAccent in bed.accents:
		if accent != null:
			for id: StringName in accent.sounds:
				note(id, Kind.ACCENT, "ambience of %s" % owner)
