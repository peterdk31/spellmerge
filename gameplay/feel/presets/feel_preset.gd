class_name FeelPreset
extends Resource
## One set of juice numbers for `gameplay/feel`: how long the hit-stop lasts, how
## hard the screen shakes and how the hit particles look. A preset only tunes
## reactions; it can never change damage or outcomes.

## Unique name of the preset, also its file name.
@export var id: StringName = &""
## Seconds the game slows on a hit. Short, and the same for every player.
@export_range(0.0, 0.2, 0.005) var hit_stop_seconds: float = 0.04
## Seconds for an enemy death or a downed wizard (a little longer than a plain hit).
@export_range(0.0, 0.3, 0.005) var death_stop_seconds: float = 0.07
## Engine.time_scale while the hit-stop lasts (0 would freeze the physics step).
@export_range(0.01, 1.0, 0.01) var hit_stop_scale: float = 0.05
## Shake added by a hit, a death and a downed wizard (0 to 1, "trauma").
@export_range(0.0, 1.0, 0.01) var hit_shake: float = 0.15
@export_range(0.0, 1.0, 0.01) var death_shake: float = 0.3
@export_range(0.0, 1.0, 0.01) var downed_shake: float = 0.5
## Biggest camera offset in pixels at full trauma.
@export_range(0.0, 32.0, 0.5) var max_shake_pixels: float = 6.0
## Trauma lost per second.
@export_range(0.1, 10.0, 0.1) var shake_decay: float = 2.5
## How far hit particles fly (pixels per second) and how long they live.
@export_range(0.0, 400.0, 1.0) var particle_speed: float = 90.0
@export_range(0.05, 2.0, 0.05) var particle_lifetime: float = 0.3
## Sound ids asked from `core/registry`. A missing sound is silent.
@export var hit_sound: StringName = &"hit"
@export var death_sound: StringName = &"enemy_death"
@export var downed_sound: StringName = &"player_downed"
