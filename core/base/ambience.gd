class_name Ambience
extends Resource
## A room's sound under its music (docs/milestones/atmosphere.md, D; `RoomBase.ambience`): a bed of
## looping `layers` (`AmbienceLayer`: a sound id and its volume) that start together and play on
## while the room is in play, and `accents` (`AmbienceAccent`) heard now and then at random over it.
## The whole is `volume` decibels on top of each part's own, quiet under the music. It comes in with
## its room over `fade` seconds and goes out with it as the next room's comes in (the same ambience
## in the next room plays on). Rooms of one biome share one file. Feel plays it (`gameplay/feel/
## room_ambience.gd`), drawn only: nothing in the game reads it.

## The most layers and accents an ambience has.
const LAYERS_MOST: int = 4
const ACCENTS_MOST: int = 4
## The least seconds between two plays of an accent.
const GAP_LEAST: float = 0.5
## The decibels any volume may be within.
const VOLUME_RANGE: float = 40.0
## The most an accent's pitch may stray (a share).
const PITCH_MOST: float = 0.4

## Its loops, played together.
@export var layers: Array[AmbienceLayer] = []
## Its sounds heard now and then.
@export var accents: Array[AmbienceAccent] = []
## Decibels on top of every part's own.
@export_range(-40.0, 12.0, 0.5) var volume: float = -8.0
## Seconds it takes to come in with its room, or go out with it.
@export_range(0.0, 8.0, 0.05) var fade: float = 2.0


## What is wrong with it, one line each (empty when it is fine): nothing in it, too many parts, a
## part naming no sound, a volume, a spread or a gap out of range.
func problems(owner: String) -> PackedStringArray:
	var found := PackedStringArray()
	if layers.is_empty() and accents.is_empty():
		found.append("%s: its ambience has no layer and no accent" % owner)
	if layers.size() > LAYERS_MOST:
		found.append("%s: its ambience has %d layers, more than %d" % [owner, layers.size(), LAYERS_MOST])
	if accents.size() > ACCENTS_MOST:
		found.append("%s: its ambience has %d accents, more than %d" % [owner, accents.size(), ACCENTS_MOST])
	if absf(volume) > VOLUME_RANGE:
		found.append("%s: its ambience's volume is not within %s dB" % [owner, VOLUME_RANGE])
	if fade < 0.0:
		found.append("%s: its ambience's fade is below 0" % owner)
	for i in layers.size():
		var layer: AmbienceLayer = layers[i]
		if layer == null or layer.sound == &"":
			found.append("%s: its ambience's layer %d names no sound" % [owner, i])
		elif absf(layer.volume) > VOLUME_RANGE:
			found.append("%s: its ambience's layer %d's volume is not within %s dB" % [owner, i, VOLUME_RANGE])
	for i in accents.size():
		found.append_array(_accent_problems(owner, i, accents[i]))
	return found


func _accent_problems(owner: String, i: int, accent: AmbienceAccent) -> PackedStringArray:
	var found := PackedStringArray()
	var name: String = "%s: its ambience's accent %d" % [owner, i]
	if accent == null or accent.sounds.is_empty():
		found.append("%s names no sound" % name)
		return found
	if accent.sounds.has(&""):
		found.append("%s has an empty sound" % name)
	if absf(accent.volume) > VOLUME_RANGE or accent.volume_spread < 0.0 or accent.volume_spread > VOLUME_RANGE:
		found.append("%s's volume or its spread is not within %s dB" % [name, VOLUME_RANGE])
	if accent.pitch_spread < 0.0 or accent.pitch_spread > PITCH_MOST:
		found.append("%s's pitch spread is not within 0 to %s" % [name, PITCH_MOST])
	if accent.gap_min < GAP_LEAST or accent.gap_max < accent.gap_min:
		found.append("%s's gaps are not %s s or more, the least first" % [name, GAP_LEAST])
	if accent.wide < 0.0:
		found.append("%s's wide is below 0" % name)
	return found
