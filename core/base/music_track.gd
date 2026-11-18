class_name MusicTrack
extends Resource
## A piece of music as data (boss plan OB15, docs/milestones/boss-old-broom.md, "Sound"): a list of
## layers, each a sound id (`audio/music/<id>.ogg`, found by the registry as any sound; silent until
## the file exists), and how its intensity picks among them. A room names its own
## (`RoomBase.music`), and an enemy that lives overrides it (`EnemyBase.music`: a boss's music comes
## with the boss, decision 17); its phases raise the intensity (`EnemyPhase.intensity`).
##
## **Stacked** (the default), intensity n plays the first n layers together, in step (a calm bed,
## then drums over it); **not stacked**, it plays the nth alone (a second, more intense entry;
## decision 25: whoever makes the music chooses). One plain track is one layer. Every layer starts
## together and keeps playing silent until its intensity comes, so they never drift apart; a change
## fades over `fade` seconds. Feel picks it and Audio plays it (`core/audio/music.gd`), drawn only: nothing in the
## game reads it.

## The most layers a track has.
const LAYERS_MOST: int = 4

## Its layers' sound ids, from the calmest.
@export var layers: Array[StringName] = []
## Whether an intensity plays every layer up to it (true) or that one alone (false).
@export var stacked: bool = true
## Seconds a layer, or the whole track, takes to fade in or out.
@export_range(0.0, 8.0, 0.05) var fade: float = 1.5


## Which layers to hear at `intensity` (1: the first; past the last is the last), 1 or 0 a layer,
## into `out` (grown to its layers when shorter; the rest 0).
func audible(intensity: int, out: PackedByteArray) -> void:
	var n: int = layers.size()
	if out.size() < n:
		out.resize(n)
	out.fill(0)
	var at: int = clampi(intensity, 1, maxi(n, 1)) - 1
	for i in n:
		out[i] = 1 if (i <= at if stacked else i == at) else 0


## What is wrong with the track, one line each (empty when it is fine): no layer, an empty one, or
## more than LAYERS_MOST.
func problems(owner: String) -> PackedStringArray:
	var found := PackedStringArray()
	if layers.is_empty():
		found.append("%s: its music has no layer" % owner)
	if layers.size() > LAYERS_MOST:
		found.append("%s: its music has %d layers, more than %d" % [owner, layers.size(), LAYERS_MOST])
	for i in layers.size():
		if layers[i] == &"":
			found.append("%s: its music's layer %d names no sound" % [owner, i])
	return found
