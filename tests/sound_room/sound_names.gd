extends RefCounted
## The sound room's list (docs/milestones/sound.md, section 7): every sound id the game names, read
## from its data, never from a list kept here: the cues' `sound` and their `held` parts', a carrier
## card's `cast_sound` and an infusion's `cast_hint` (Feel's cast sounds), an enemy's
## `death_sound`, its phases' held `look.sound` and its music, a room's music and its ambience's
## layers and accents, and the ids Feel names itself (`feel_names`: its preset's `hit_sound` and each
## hit kind's `kind_looks` sound, the cast sound and the pickups') and the HUD's menu sounds (`UiSounds.IDS`, played
## on the UI bus; sound plan AU8), which the room hands to `read`. Each id has the
## kind it is played as (the first that names it wins) and every place it is named; every music track
## and ambience is kept too, with its owner.
##
##     var names := SoundNames.new()
##     names.read(registry, SoundNames.feel_names(preset, &"cast"))
##     for id: StringName in names.ids(): ...

const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const PickupSoundsScript := preload("res://gameplay/feel/pickup_sounds.gd")

## How a sound is played: a one-shot (SFX), held while its moment lasts (SFX), a layer of a music
## track (MusicDuck), a room's bed loop or one of its accents (Ambience), or a menu's sound (UI).
enum Kind { ONE_SHOT, HELD, MUSIC, BED, ACCENT, UI }

## Each named id's kind, and where it is named (lines such as "cue hit_spark").
var kinds: Dictionary[StringName, Kind] = {}
var where: Dictionary[StringName, PackedStringArray] = {}
## Every music track the data names (each once), and its first owner's name, by index.
var tracks: Array[MusicTrack] = []
var track_owners: PackedStringArray = PackedStringArray()
## Every ambience the data names (each once), and its first owner's name, by index.
var beds: Array[Ambience] = []
var bed_owners: PackedStringArray = PackedStringArray()


## The ids Feel names itself, as [id, where] pairs for `read`: `preset`'s `hit_sound`, each hit kind's
## sound (`kind_looks`, in kind order), `cast` (Feel's `CAST_SOUND`, a carrier's with none) and each
## kind of pickup's (`PickupSounds.ids`).
static func feel_names(preset: FeelPresetScript, cast: StringName) -> Array:
	var found: Array = [[preset.hit_sound, "Feel's hit sound (its preset)"]]
	var kinds_named: Array = preset.kind_looks.keys()
	kinds_named.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	for kind: Variant in kinds_named:
		var look: Dictionary = preset.kind_looks[kind]
		found.append([StringName(look.get("sound", "")), "Feel's %s hit (its preset's kind_looks)" % kind])
	found.append([cast, "Feel's cast sound (a carrier card with none of its own)"])
	for id: StringName in PickupSoundsScript.ids():
		found.append([id, "Feel's pickup sound (pickup_sounds.gd)"])
	return found


## Reads every folder of `registry` (`get_folders`, `get_all`), `feel`'s own ids: pairs of
## [id, where] (`feel_names`), and the menus' sounds `ui` (`UiSounds.IDS`).
func read(registry: Node, feel: Array, ui: Array[StringName] = []) -> void:
	kinds.clear()
	where.clear()
	tracks.clear()
	track_owners.clear()
	beds.clear()
	bed_owners.clear()
	for pair: Array in feel:
		note(pair[0] as StringName, Kind.ONE_SHOT, pair[1] as String)
	for id: StringName in ui:
		note(id, Kind.UI, "the HUD's menu sound (UiSounds)")
	var folders: Array[StringName] = registry.call(&"get_folders")
	for folder: StringName in folders:
		var all: Array[Resource] = registry.call(&"get_all", folder)
		for resource: Resource in all:
			if resource is CueBase:
				_read_cue(resource as CueBase)
			elif resource is CarrierCard:
				note((resource as CarrierCard).cast_sound, Kind.ONE_SHOT, "carrier %s's cast" % (resource as CarrierCard).id)
			elif resource is ElementBase:
				note((resource as ElementBase).cast_hint, Kind.ONE_SHOT, "infusion %s's cast hint" % (resource as ElementBase).id)
			elif resource is EnemyBase:
				_read_enemy(resource as EnemyBase)
			elif resource is RoomBase:
				var room := resource as RoomBase
				_read_track(room.music, "room %s" % room.id)
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


## The ambience whose layer or accent `id` is (null: none).
func bed_of(id: StringName) -> Ambience:
	for bed: Ambience in beds:
		for layer: AmbienceLayer in bed.layers:
			if layer != null and layer.sound == id:
				return bed
		for accent: AmbienceAccent in bed.accents:
			if accent != null and accent.sounds.has(id):
				return bed
	return null


## The decibels the accent `id` plays at in `bed` (the bed's and the accent's own; 0: none).
static func accent_volume(bed: Ambience, id: StringName) -> float:
	if bed == null:
		return 0.0
	for accent: AmbienceAccent in bed.accents:
		if accent != null and accent.sounds.has(id):
			return bed.volume + accent.volume
	return 0.0


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
	if bed == null:
		return
	if not beds.has(bed):
		beds.append(bed)
		bed_owners.append(owner)
	for layer: AmbienceLayer in bed.layers:
		if layer != null:
			note(layer.sound, Kind.BED, "ambience of %s" % owner)
	for accent: AmbienceAccent in bed.accents:
		if accent != null:
			for id: StringName in accent.sounds:
				note(id, Kind.ACCENT, "ambience of %s" % owner)
