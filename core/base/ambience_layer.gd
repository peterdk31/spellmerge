class_name AmbienceLayer
extends Resource
## One loop of a room's sound bed (docs/milestones/atmosphere.md, D; `Ambience.layers`): a sound id
## (`audio/ambience/<id>.ogg`, found by the registry as any sound; silent until the file exists),
## imported to loop, and how loud it is against the others. Drawn only: Feel plays it.

## The loop's sound id.
@export var sound: StringName = &""
## Decibels on top of the sound's own (and the ambience's `volume`).
@export_range(-40.0, 12.0, 0.5) var volume: float = 0.0
