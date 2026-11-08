class_name FeelPreset
extends Resource
## One set of juice numbers for `gameplay/feel`: how long the hit-stop lasts, how
## hard the screen shakes and how the hit particles look. A preset only tunes
## reactions; it can never change damage or outcomes. The point moments (a parry, a
## deflect, a death, a downed wizard, a self-hit, a heal, an element reaction) are cues in
## `content/cues/`.

## Unique name of the preset, also its file name.
@export var id: StringName = &""
## Hit-stop (how long a hit holds its bodies, their rest, the kinds' stops, the game-wide stop) is
## not a look: it is the game's rule, `gameplay/combat/hit_stop.gd` (online-ready N4).
## Shake added by a plain hit (0 to 1, "trauma").
@export_range(0.0, 1.0, 0.01) var hit_shake: float = 0.15
## Biggest camera offset in pixels at full trauma.
@export_range(0.0, 32.0, 0.5) var max_shake_pixels: float = 6.0
## Trauma lost per second.
@export_range(0.1, 10.0, 0.1) var shake_decay: float = 2.5
## The spray of a hit on a character (an effect along the way the shot flew), bigger or smaller
## by `hit_spray_per_damage` (0.06 is 6%) for each damage point above or below 5, rounded to a
## whole zoom. An enemy is hit in the ramp nearest its own colour (`EnemyBase.hit_color`); a wizard
## in its own ramp.
@export_range(0.0, 0.2, 0.01) var hit_spray_per_damage: float = 0.06
## The spray itself and its sparks are the cue `hit` (a hit with no way, `hit_puff`; content/cues,
## S6 2), `size` zoom steps big.
## A dead body breaks into motes (S3; `Spectacle.break_body`): `death_mote_share` of its art's
## pixels (times its scale's area, at most `death_mote_most`), each a mote of the surface kind
## `death_mote_kind` in its art's colours, flung out from its middle at `death_mote_speed` px/s
## (slowest, fastest) and `death_mote_up` up, falling to its feet.
@export var death_mote_kind: StringName = &"chip"
@export_range(0.0, 1.0, 0.01) var death_mote_share: float = 0.3
@export_range(0, 512) var death_mote_most: int = 160
@export var death_mote_speed: Vector2 = Vector2(8.0, 46.0)
@export var death_mote_up: Vector2 = Vector2(0.0, 40.0)
## A shot that ends on a wall or pillar knocks the wall's motes back off the surface (the
## spectacle's surface kinds); its flare is its carrier card's `impact_cue` (`impact` for none).
## Motes (docs/milestones/spell-spectacle.md, P1; Feel's `mote.gd`) a shot's end throws, as a
## share of its cards' kinds' own count: a hit on a body (back along the way it came, on top of
## its spray). A shot's end (the cue `expire`, its `share`) and a cue's motes (a reaction's ring of
## them among them) are their own data.
@export_range(0.0, 4.0, 0.05) var hit_mote_share: float = 0.5
## Seconds a hit enemy or wizard shows as plain white, and how much its sprite
## squashes then (0.25 is 25% wider and 25% lower), settling back in the same time.
@export_range(0.0, 0.3, 0.01) var hit_flash_seconds: float = 0.08
@export_range(0.0, 0.6, 0.01) var hit_squash: float = 0.25
## Camera kick (a cue's `kick`, a cast's among them): pixels given back per second.
@export_range(1.0, 200.0, 1.0) var cast_kick_decay: float = 40.0
## What a character with a status looks like (spell spectacle 2, S6 item 11): its element card's
## (the element whose `status_id` it is, `ElementBase`): a glow in the card's `tint` that follows
## it and pulses, and the card's motes (the kinds that name it, else those of its `look_layer`)
## given off round it, `status_mote_rate` a second. A status no element puts on is shown as the
## status it deepens from (`deep_statuses`: freeze, which three chills make, as frost's chill) at
## full depth: its glow `status_deep_white` of the way to white and `status_deep_motes` times the
## motes, so a frozen character reads apart from a chilled one.
## When a character has several, the first in `status_order` is the one shown.
@export var status_order: Array[StringName] = [&"freeze", &"static", &"gust", &"burn", &"hex", &"chill"]
@export var deep_statuses: Dictionary = {&"freeze": &"chill"}
@export_range(0.0, 60.0, 0.5) var status_mote_rate: float = 8.0
@export_range(1.0, 8.0, 0.5) var status_deep_motes: float = 2.0
@export_range(0.0, 1.0, 0.05) var status_deep_white: float = 0.75
## The default feel of each hit kind (`hit_landed`: `shot`, `ray`, `swing`, `burst`, `reaction`,
## `status`), so a new card feels like something before it has its own sound: `shake` scales
## `hit_shake` (0 turns it off), `sound` is the id asked from the registry (silent until an `.ogg`
## exists). A kind not listed uses the shot's look. A swing's hit shakes the screen about 2 px (the
## melee playground's, owner 2026-10-29: trauma 0.57 of `max_shake_pixels` 6 is 0.57² x 6); its
## stop (0.05 s) is `HitStop.KIND_STOP`.
@export var kind_looks: Dictionary = {
	&"shot": {"shake": 1.0, "sound": &"hit"},
	&"ray": {"shake": 0.5, "sound": &"hit_ray"},
	&"swing": {"shake": 3.8, "sound": &"hit_swing"},
	&"burst": {"shake": 2.0, "sound": &"hit_burst"},
	&"reaction": {"shake": 1.0, "sound": &"hit_reaction"},
	&"status": {"shake": 0.0, "sound": &""},
}
## How long the "downed by your own ..." note rises over a downed wizard, in seconds.
@export_range(0.5, 6.0, 0.1) var downed_note_seconds: float = 2.5
## Sound ids asked from `core/registry`. A missing sound is silent.
@export var hit_sound: StringName = &"hit"
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
## How long a beam stays on screen (a nova's ring is the cue `nova`, `content/cues`).
@export_range(0.0, 0.5, 0.01) var beam_seconds: float = 0.25
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
## The cast flash on the wizard and the flare where a shot ends are cues the carrier cards name
## (`FormBase.cast_cue` and `impact_cue`, S6 2; `cast` and `impact` by default), not in this preset.
