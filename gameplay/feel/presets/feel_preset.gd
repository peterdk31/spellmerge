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
## How much bigger (rounded to a whole zoom) a death's puff is than a hit's.
@export_range(1.0, 3.0, 0.1) var death_particle_size: float = 1.6
## The spray of a hit on a character (an effect along the way the shot flew), bigger or smaller
## by `hit_spray_per_damage` (0.06 is 6%) for each damage point above or below 5, rounded to a
## whole zoom. An enemy is hit in the ramp of `enemy_hit_color` (ember); a wizard in its own.
@export_range(0.0, 0.2, 0.01) var hit_spray_per_damage: float = 0.06
@export var enemy_hit_color: Color = Color("e0592f")
## A shot that ends on a wall or pillar knocks Stone chips back off the surface, `wall_chip_size`
## times as far (rounded to a whole zoom); `wall_spark_size` is the size of a shot's flare when
## its carrier card names none.
@export_range(0.3, 2.0, 0.1) var wall_chip_size: float = 0.9
@export_range(0.1, 3.0, 0.1) var wall_spark_size: float = 0.45
## Seconds a hit enemy or wizard shows as plain white, and how much its sprite
## squashes then (0.25 is 25% wider and 25% lower), settling back in the same time.
@export_range(0.0, 0.3, 0.01) var flash_seconds: float = 0.08
@export_range(0.0, 0.6, 0.01) var hit_squash: float = 0.25
## The caster's squash on a cast: seconds, and how much thinner and taller (0.15 is 15%).
@export_range(0.0, 0.3, 0.01) var cast_squash_seconds: float = 0.12
@export_range(0.0, 0.6, 0.01) var cast_squash: float = 0.2
## Seconds a dead enemy's copy takes to turn white-hot and fall apart.
@export_range(0.0, 0.6, 0.01) var death_anim_seconds: float = 0.25
## The white-hot ring where an enemy dies: seconds and biggest size.
@export_range(0.0, 0.5, 0.01) var death_puff_seconds: float = 0.14
@export_range(0.1, 6.0, 0.1) var death_puff_size: float = 1.6
## Camera kick of a cast: pixels pushed against the aim, and pixels given back per second.
@export_range(0.0, 8.0, 0.1) var cast_kick_pixels: float = 1.5
@export_range(1.0, 200.0, 1.0) var cast_kick_decay: float = 40.0
## An element reaction (`reaction_triggered`): the seconds of its puff, ring and name, the
## shake it adds, and the colour of each reaction by its id (a reaction not listed is white).
## The sound is `reaction_sound_prefix` + the reaction id, for example `reaction_shatter`.
@export_range(0.0, 0.5, 0.01) var reaction_seconds: float = 0.25
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
## The jagged arc of lightning a discharge draws from the enemy struck to each enemy zapped
## (`discharge_arc`), in the colour of the reaction `discharge`: seconds it shows.
@export_range(0.0, 0.5, 0.01) var arc_seconds: float = 0.25
## What a character with a status looks like, by status id (`burn`, `chill`, `freeze`, `shock`,
## `hex`, `static`; the glow look, 2026-10-27): an effect that follows it, giving off the
## particles of a look kind (`look`: a `LOOK_*` of core/projectiles, the element's own: burn
## fire's embers, chill and freeze frost's flecks, shock storm's gusts, hex void's pull, static
## lightning's sparks) round it, with a glow in `color` that pulses.
## When a character has several, the first in `status_order` is the one shown.
@export var status_order: Array[StringName] = [&"freeze", &"static", &"shock", &"burn", &"hex", &"chill"]
@export var status_looks: Dictionary = {
	&"burn": {"color": Color("ff6a1a"), "look": 1},
	&"chill": {"color": Color("8fd8ff"), "look": 2},
	&"freeze": {"color": Color("e8fbff"), "look": 2},
	&"shock": {"color": Color("fff04a"), "look": 3},
	&"hex": {"color": Color("a63cff"), "look": 4},
	&"static": {"color": Color("b4e82a"), "look": 5},
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
## A spell shot's art (an enemy's spells are drawn like a wizard's, in the enemy ramp). The bolt is neutral bone with a Spark core: the owner tints the bone, the element
## colours the core (see `core/projectiles`). Since staffs B6a the shader builds a player's shot
## (a rune and an orbit orb included), so only Feel's lone sprites use this art.
@export var bolt_texture: Texture2D = preload("res://art/vfx/bolt.svg")
## The beam (a 32 px segment that repeats along its length) and the nova ring, drawn from
## `form_shown`, tinted like the bolt.
@export var beam_texture: Texture2D = preload("res://art/vfx/beam.svg")
@export var nova_texture: Texture2D = preload("res://art/vfx/nova_ring.svg")
## How long a beam stays on screen, and how long a nova ring takes to grow to
## `nova_ring_size` pixels across.
@export_range(0.0, 0.5, 0.01) var beam_seconds: float = 0.25
@export_range(0.0, 1.0, 0.01) var nova_seconds: float = 0.25
@export_range(8.0, 400.0, 1.0) var nova_ring_size: float = 120.0
## How much wider a beam's rim and glow are in its first moments (1.0 is twice as wide).
@export_range(0.0, 3.0, 0.1) var beam_flare: float = 1.0
## The share of a beam's life the extra width lasts (0.2 is the first fifth).
@export_range(0.01, 1.0, 0.01) var beam_flare_share: float = 0.2
## The beam thins by this much on every other flicker step (0 is steady; keep it small, a big
## swing at a fast rate reads as a strobe), and the steps come this many times a second.
@export_range(0.0, 0.3, 0.01) var beam_flicker_depth: float = 0.1
@export_range(1.0, 30.0, 1.0) var beam_flicker_rate: float = 16.0
## How strongly a beam glows (1.0 full; the glow look, 2026-10-27). Its one-pixel core leaves
## room round it, so beams that cross (a split, a multicast) all still show.
@export_range(0.2, 1.0, 0.05) var beam_alpha: float = 0.7
## The cast flash on the wizard and the flare where a shot ends are data on the carrier cards
## (`FormBase.cast_look` and `impact_look`, staffs B6b), not in this preset. A card without a
## look gets the plain cast flash and a burst `wall_spark_size` big.
