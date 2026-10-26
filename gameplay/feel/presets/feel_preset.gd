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
## The spray of a hit on a character: along the way the shot flew, `hit_spray_spread`
## degrees to each side, `spray_speed` times as fast as a round puff, bigger or smaller
## by `hit_spray_per_damage` (0.06 is 6%) for each damage point above or below 5.
## An enemy is hit in `enemy_hit_color` (ember); a wizard in its own colour.
@export_range(0.0, 90.0, 1.0) var hit_spray_spread: float = 35.0
@export_range(0.5, 3.0, 0.1) var spray_speed: float = 1.4
@export_range(0.0, 0.2, 0.01) var hit_spray_per_damage: float = 0.06
@export var enemy_hit_color: Color = Color("e0592f")
## A shot that ends on a wall or pillar: stone chips and dust fly back off the surface
## (`wall_chip_size`, `wall_chip_spread` degrees to each side, `wall_chip_color`) and a
## short spark in the shot's colour shows for `wall_spark_seconds`.
@export_range(0.3, 2.0, 0.1) var wall_chip_size: float = 0.9
@export_range(0.0, 90.0, 1.0) var wall_chip_spread: float = 60.0
@export var wall_chip_color: Color = Color("a39fb8")
@export_range(0.0, 0.3, 0.01) var wall_spark_seconds: float = 0.1
@export_range(0.1, 3.0, 0.1) var wall_spark_size: float = 0.45
## Seconds a hit enemy or wizard shows as plain white, and how much its sprite
## squashes then (0.25 is 25% wider and 25% lower), settling back in the same time.
@export_range(0.0, 0.3, 0.01) var flash_seconds: float = 0.08
@export_range(0.0, 0.6, 0.01) var hit_squash: float = 0.25
## The caster's squash on a cast: seconds, and how much thinner and taller (0.15 is 15%).
@export_range(0.0, 0.3, 0.01) var cast_squash_seconds: float = 0.12
@export_range(0.0, 0.6, 0.01) var cast_squash: float = 0.2
## Seconds a dead enemy's white copy takes to collapse and fade.
@export_range(0.0, 0.6, 0.01) var death_anim_seconds: float = 0.25
## The muzzle flash at the staff tip: seconds it shows and its size (1 is the art's size).
@export_range(0.0, 0.3, 0.01) var muzzle_flash_seconds: float = 0.1
## How long the mark of a combo cast (`combo_cast`) stays on the wizard; 0 turns it off.
@export_range(0.0, 1.0, 0.01) var combo_mark_seconds: float = 0.36
@export_range(0.1, 3.0, 0.1) var muzzle_flash_size: float = 0.5
## The white puff where an enemy dies: seconds and biggest size.
@export_range(0.0, 0.5, 0.01) var death_puff_seconds: float = 0.14
@export_range(0.1, 6.0, 0.1) var death_puff_size: float = 1.6
## Camera kick of a cast: pixels pushed against the aim, and pixels given back per second.
@export_range(0.0, 8.0, 0.1) var cast_kick_pixels: float = 1.5
@export_range(1.0, 200.0, 1.0) var cast_kick_decay: float = 40.0
## An element reaction (`reaction_triggered`): the flash and the name's size and seconds, the
## shake it adds, and the colour of each reaction by its id (a reaction not listed is white).
## The sound is `reaction_sound_prefix` + the reaction id, for example `reaction_shatter`.
@export_range(0.0, 0.5, 0.01) var reaction_seconds: float = 0.25
@export_range(0.1, 6.0, 0.1) var reaction_flash_size: float = 1.4
@export_range(0.0, 1.0, 0.01) var reaction_shake: float = 0.2
@export var reaction_colors: Dictionary = {
	&"shatter": Color("e8fbff"),
	&"thaw": Color("7be05a"),
	&"flare": Color("ffd23a"),
	&"kindle": Color("ff3b30"),
	&"stillness": Color("4a78ff"),
	&"rift": Color("c05cff"),
	&"discharge": Color("00f0ff"),
	&"overload": Color("ff6ba0"),
	&"superconduct": Color("14a38b"),
}
@export var reaction_sound_prefix: String = "reaction_"
## The burst a reaction adds to its flash, bigger than any plain hit: its hit-stop in seconds
## (longer than a death's), the size of its particle burst, and the size of the ring that
## opens (1.0 is the nova ring art's size; it grows as it fades). `reaction_power` scales
## these and the flash and shake by reaction id (a reaction not listed is 1.0).
@export_range(0.0, 0.3, 0.005) var reaction_stop_seconds: float = 0.09
@export_range(1.0, 4.0, 0.1) var reaction_burst_size: float = 2.2
@export_range(0.1, 4.0, 0.1) var reaction_ring_size: float = 0.9
@export var reaction_power: Dictionary = {
	&"shatter": 1.3,
	&"rift": 1.2,
	&"flare": 1.1,
	&"kindle": 1.0,
	&"thaw": 1.0,
	&"stillness": 0.9,
	&"discharge": 0.7,
	&"overload": 1.1,
	&"superconduct": 1.0,
}
## The jagged arc a discharge draws from the enemy struck to each enemy zapped (`discharge_arc`),
## in the colour of the reaction `discharge`: seconds it shows, its width in pixels and how far
## its corners stray from the straight line, in pixels.
@export_range(0.0, 0.5, 0.01) var arc_seconds: float = 0.25
@export_range(0.5, 6.0, 0.5) var arc_width: float = 2.0
@export_range(0.0, 16.0, 0.5) var arc_jag: float = 5.0
## What an enemy with a status looks like, by status id (`burn`, `chill`, `freeze`, `shock`,
## `hex`, `static`): a colour laid over its sprite, the most it shows (alpha), how fast it pulses per
## second (0: steady), how far it jitters in pixels, and whether it blinks off between pulses.
## When an enemy has several, the first in `status_order` is the one shown.
@export var status_order: Array[StringName] = [&"freeze", &"static", &"shock", &"burn", &"hex", &"chill"]
@export var status_looks: Dictionary = {
	&"burn": {"color": Color("ff6a1a"), "alpha": 0.55, "rate": 7.0, "jitter": 0.0, "blink": false},
	&"chill": {"color": Color("8fd8ff"), "alpha": 0.5, "rate": 0.0, "jitter": 0.0, "blink": false},
	&"freeze": {"color": Color("e8fbff"), "alpha": 0.8, "rate": 0.0, "jitter": 0.0, "blink": false},
	&"shock": {"color": Color("fff04a"), "alpha": 0.75, "rate": 14.0, "jitter": 1.0, "blink": true},
	&"hex": {"color": Color("a63cff"), "alpha": 0.5, "rate": 1.8, "jitter": 0.0, "blink": false},
	&"static": {"color": Color("b4e82a"), "alpha": 0.7, "rate": 5.0, "jitter": 0.5, "blink": true},
}
## The default feel of each hit kind (`hit_landed`: `shot`, `ray`, `burst`, `reaction`, `status`),
## so a new card feels like something before it has its own sound: `stop` and `shake` scale
## `hit_stop_seconds` and `hit_shake` (0 turns it off), `sound` is the id asked from the registry
## (silent until an `.ogg` exists). A kind not listed uses the shot's look.
@export var kind_looks: Dictionary = {
	&"shot": {"stop": 1.0, "shake": 1.0, "sound": &"hit"},
	&"ray": {"stop": 0.5, "shake": 0.5, "sound": &"hit_ray"},
	&"burst": {"stop": 1.5, "shake": 2.0, "sound": &"hit_burst"},
	&"reaction": {"stop": 1.0, "shake": 1.0, "sound": &"hit_reaction"},
	&"status": {"stop": 0.0, "shake": 0.0, "sound": &""},
}
## A wizard hit by their own spell: a ring in this colour on the frame of the hit, so a self-hit
## is never mistaken for an enemy's (seconds, size as `reaction_ring_size`, and the sound id).
@export var self_hit_color: Color = Color("ff5fa8")
@export_range(0.05, 1.0, 0.01) var self_hit_seconds: float = 0.35
@export_range(0.2, 4.0, 0.1) var self_hit_size: float = 1.3
@export var self_hit_sound: StringName = &"self_hit"
## A heal hit: a soft ring in this colour, no stop, no shake (seconds, size, sound id).
@export var heal_color: Color = Color("6be36b")
@export_range(0.05, 1.0, 0.01) var heal_seconds: float = 0.4
@export_range(0.2, 4.0, 0.1) var heal_size: float = 1.0
@export var heal_sound: StringName = &"heal"
## How long the "downed by your own ..." note rises over a downed wizard, in seconds.
@export_range(0.5, 6.0, 0.1) var downed_note_seconds: float = 2.5
## Sound ids asked from `core/registry`. A missing sound is silent.
@export var hit_sound: StringName = &"hit"
@export var death_sound: StringName = &"enemy_death"
@export var downed_sound: StringName = &"player_downed"
## The art feel draws, so a re-skin is a new preset (or new files at these paths) and
## never an edit to `feel.gd`. Each defaults to the shipped placeholder art.
## The hit spark, also used for the white flashes and puffs.
@export var spark_texture: Texture2D = preload("res://art/vfx/hit_spark.svg")
## A player's spell shot, and an enemy's shot (drawn apart, so it never reads as a spell).
## The bolt is neutral bone with a Spark core: the owner tints the bone, the element
## colours the core (see `core/projectiles`). Since staffs B6a the shader builds a player's shot
## (a rune and an orbit orb included), so only Feel's lone sprites use this art.
@export var bolt_texture: Texture2D = preload("res://art/vfx/bolt.svg")
@export var hostile_texture: Texture2D = preload("res://art/vfx/imp_fireball.svg")
## The beam (a 32 px segment that repeats along its length) and the nova ring, drawn from
## `form_shown`, tinted like the bolt.
@export var beam_texture: Texture2D = preload("res://art/vfx/beam.svg")
@export var nova_texture: Texture2D = preload("res://art/vfx/nova_ring.svg")
## How long a beam stays on screen, and how long a nova ring takes to grow to
## `nova_ring_size` pixels across.
@export_range(0.0, 0.5, 0.01) var beam_seconds: float = 0.25
@export_range(0.0, 1.0, 0.01) var nova_seconds: float = 0.25
@export_range(8.0, 400.0, 1.0) var nova_ring_size: float = 120.0
## How much wider a beam is in its first moments (1.0 is twice as wide).
@export_range(0.0, 3.0, 0.1) var beam_flare: float = 1.0
## The share of a beam's life the extra width lasts (0.2 is the first fifth).
@export_range(0.01, 1.0, 0.01) var beam_flare_share: float = 0.2
## The beam thins by this much on every other flicker step (0 is steady; keep it small, a big
## swing at a fast rate reads as a strobe), and the steps come this many times a second.
@export_range(0.0, 0.3, 0.01) var beam_flicker_depth: float = 0.1
@export_range(1.0, 30.0, 1.0) var beam_flicker_rate: float = 16.0
## The cast flash on the wizard and the flare where a shot ends are data on the carrier cards
## (`FormBase.cast_look` and `impact_look`, staffs B6b), not in this preset. A card without a
## look gets the muzzle flash above and the wall spark.
## An enemy's shot ending or hitting always shows this mark turned on its corner, in
## `enemy_hit_color`, whatever any player cast.
@export_range(0.0, 0.3, 0.01) var enemy_impact_seconds: float = 0.12
@export_range(0.1, 3.0, 0.1) var enemy_impact_size: float = 0.7
