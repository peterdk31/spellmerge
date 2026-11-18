class_name AmbienceAccent
extends Resource
## A sound a room's air makes now and then (docs/milestones/atmosphere.md, D; `Ambience.accents`): a
## far drip, a rumble through the stone, a gust. Each time one of its `sounds` at random, after a
## gap of `gap_min` to `gap_max` seconds (the first as long after the room comes), from up to `wide`
## pixels left or right of the middle of the picture, a little louder or softer and higher or lower
## each time. Drawn only: Feel plays it, by its own clock and dice.

## The sound ids it picks among (silent until a file exists).
@export var sounds: Array[StringName] = []
## Decibels on top of the sound's own (and the ambience's `volume`), and how far either way a
## play may stray from it.
@export_range(-40.0, 12.0, 0.5) var volume: float = 0.0
@export_range(0.0, 12.0, 0.5) var volume_spread: float = 0.0
## How far a play's pitch may stray from the sound's own, as a share (0.1: 0.9x to 1.1x).
@export_range(0.0, 0.4, 0.01) var pitch_spread: float = 0.0
## The least and most seconds between two plays.
@export_range(0.5, 600.0, 0.5) var gap_min: float = 6.0
@export_range(0.5, 600.0, 0.5) var gap_max: float = 12.0
## How far left or right of the middle of the picture it may come from (pixels; 0: the middle).
@export_range(0.0, 640.0, 1.0) var wide: float = 0.0
