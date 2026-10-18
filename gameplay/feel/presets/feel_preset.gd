class_name FeelPreset
extends Resource
## One set of juice numbers for `gameplay/feel`: how long the hit-stop lasts, how
## hard the screen shakes and how the hit particles look. A preset only tunes
## reactions; it can never change damage or outcomes.

## Unique name of the preset, also its file name.
@export var id: StringName = &""
## Seconds the game slows on a hit. Short, and the same for every player.
@export_range(0.0, 0.2, 0.005) var hit_stop_seconds: float = 0.04
## Seconds after a plain hit's stop in which plain hits cannot stop the game again.
## Keeps a crowded fight from sitting near 5% speed (0.04 s of every 0.19 s is 21%).
@export_range(0.0, 0.5, 0.01) var hit_stop_rest: float = 0.15
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
## How much bigger (speed, life, particle size) a death burst is than a hit burst.
@export_range(1.0, 3.0, 0.1) var death_particle_size: float = 1.6
## Seconds a hit enemy or wizard shows as plain white, and how much its sprite
## squashes then (0.25 is 25% wider and 25% lower), settling back in the same time.
@export_range(0.0, 0.3, 0.01) var flash_seconds: float = 0.08
@export_range(0.0, 0.6, 0.01) var hit_squash: float = 0.25
## The muzzle flash at the staff tip: seconds it shows and its size (1 is the art's size).
@export_range(0.0, 0.3, 0.01) var muzzle_flash_seconds: float = 0.07
@export_range(0.1, 3.0, 0.1) var muzzle_flash_size: float = 1.0
## The white puff where an enemy dies: seconds and biggest size.
@export_range(0.0, 0.5, 0.01) var death_puff_seconds: float = 0.18
@export_range(0.1, 6.0, 0.1) var death_puff_size: float = 2.5
## Camera kick of a cast: pixels pushed against the aim, and pixels given back per second.
@export_range(0.0, 8.0, 0.1) var cast_kick_pixels: float = 1.5
@export_range(1.0, 200.0, 1.0) var cast_kick_decay: float = 40.0
## Sound ids asked from `core/registry`. A missing sound is silent.
@export var hit_sound: StringName = &"hit"
@export var death_sound: StringName = &"enemy_death"
@export var downed_sound: StringName = &"player_downed"
