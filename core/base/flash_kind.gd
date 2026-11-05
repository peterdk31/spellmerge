class_name FlashKind
extends Resource
## A kind of flash (docs/milestones/flash-kinds.md): one shaped glow a cue's `flash` part shows,
## drawn whole by a shot shader and gone in a moment (a shot's end, a cast at the staff tip, a ring
## flashing out, a column of light). One file per kind in `content/flashes/<id>.tres`; the registry
## finds it by its `id`, and a cue part names it (`{"flash": &"burst"}`), so a new look is a new
## file and no list is edited.
##
## How it is drawn (`draw`):
##   `shape`     (the default) the parts below, from its curves: Feel's flash shader reads them
##               from a table (`gameplay/feel/flash_table.gd`), so a new look needs no shader edit
##   `clouds`    a staff's poof: bone clouds swelling along the staff (code), its glow from its curves
##   `cracks`    the ground struck: cracks cooling from white-hot on the floor (code), its glow from
##               its curves; drawn under the bodies
##   `shell`, `fireball`  an explosion's parts, drawn by `shot_blast.gdshader` (code)
##   `arc`       lightning along a length (the cue's size), drawn by `shot_arc.gdshader` (code)
## Its colours are never here: a flash is in the ramp of the shot or caster it comes from (or the
## cue's own colour); its curves pick which shade of that ramp (`first`, `second`).
##
## **The parts of a shape,** each a curve over the flash's life (0 to 1); a part with no curve is
## not drawn:
##   `arm`            a cross: its arms' length (rounded to whole pixels), its middle in `first`, its
##                    arms in `second`
##   `disc`           a dotted disc: its reach, in `first`
##   `ring`           a ring fraying with its age: its radius, in `second`; round, a diamond or flat
##                    on the floor (`metric`), frayed by a hash salted with `salt`
##   `column_width`   a column of light: its half width (rounded), white-hot `first` down its middle,
##                    then `second`, its rim the ramp's base; it narrows and frays into its top third
##   `column_top`, `column_foot`  where it starts and ends (pixels down from the flash's middle:
##                    the top of its square is 1 - 12 x its zoom)
##   `column_length`  the most it is long, from its foot (a falling streak); none: top to foot
##   `column_dotted`  1: every other row (0 or none: whole)
##   `star`           a star of `star_points` points (4: a cross turned sharp): its reach; white-hot
##                    `first` in its middle, `second` out to its points (flash kinds F4)
##   `rays`, `rays_inner`  `ray_count` thin rays all round, from `rays_inner` (0 when none) out to
##                    `rays`, one pixel wide, in `second` (white-hot `first` within 2 px of their
##                    inner end): rays thrown out, or drawn in
##   `dots`           a ring of `dot_count` dots: its radius, in `second` (dots of a pixel, a plus
##                    from zoom 2)
##   `spiral`         a spiral of `spiral_arms` arms, coils `spiral_gap` pixels a zoom step apart (each
##                    arm's: 2 arms 6 px apart at zoom 1 are 12 px at zoom 2), out to its
##                    reach, in `second` (`first` in its middle third); `spiral_turn` how far it has
##                    turned (in turns: 1 is all the way round; it grows to spin it)
## **Its glow** (added light round it, over its whole square; drawn first):
##   `glow`                             how bright it is
##   `glow_ring`, `glow_ring_reach`     a soft light round the ring's line (or the column's)
##   `glow_middle`, `glow_middle_reach` a soft light round its middle
## **Its two colours,** `first` and `second`: a shade of its ramp over its life (`hot`, `hi`,
## `mid`, `lo`).
##
## **A curve** is up to MAX_SEGMENTS segments, each a Dictionary, the first at 0, each starting
## where the one before ends:
##   `at`        the age it starts (0 to below 1; 0 when not given)
##   `from`, `to`              its value at its start and end, in pixels (or as a number: a glow)
##   `from_z`, `to_z`          and in steps of the flash's zoom, added (a flash at zoom 2 is twice
##                             as big); `to` is `from` and `to_z` is `from_z` when not given
##   `way`       how it goes from `from` to `to`: `linear` (the default), `out` (fast, then slowing:
##               1 - (1 - t)^2), `in` (slow, then fast: t^2) or `hold` (`from` all the way)
##   `over`      the age it reaches `to` (the next segment's `at`, or 1, when not given): a curve may
##               be cut before it gets there by the next segment
##   `off`       true: the part is not drawn from `at` (until a later segment)
## A shade curve's segments are `at` and `shade` only.

## The most segments a curve has (the shader's table holds this many).
const MAX_SEGMENTS: int = 4
const DRAWS: Array[StringName] = [&"shape", &"clouds", &"cracks", &"shell", &"fireball", &"arc"]
## The most points, rays, dots and arms (the table holds them as whole numbers).
const MAX_POINTS: int = 12
const MAX_RAYS: int = 31
const MAX_DOTS: int = 64
const MAX_ARMS: int = 4
## The draws Feel's flash shader draws (from the table), and the one drawn along a length.
const TABLE_DRAWS: Array[StringName] = [&"shape", &"clouds", &"cracks"]
const LENGTH_DRAWS: Array[StringName] = [&"arc"]
const METRICS: Array[StringName] = [&"round", &"diamond", &"flat"]
const WAYS: Array[StringName] = [&"linear", &"out", &"in", &"hold"]
const SHADES: Array[StringName] = [&"hot", &"hi", &"mid", &"lo"]
## The number curves, in the table's order (FlashTable.CHANNELS mirrors it), and the shade curves.
const NUMBER_CURVES: Array[StringName] = [
	&"arm", &"disc", &"ring", &"column_width", &"column_top", &"column_foot", &"column_length",
	&"column_dotted", &"glow", &"glow_ring", &"glow_ring_reach", &"glow_middle", &"glow_middle_reach",
	&"star", &"rays", &"rays_inner", &"dots", &"spiral", &"spiral_turn",
]
## The parts a shape may draw (at least one).
const PARTS: Array[StringName] = [&"arm", &"disc", &"ring", &"column_width", &"star", &"rays", &"dots", &"spiral"]
const SHADE_CURVES: Array[StringName] = [&"first", &"second"]
const SEGMENT_KEYS: Array[String] = ["at", "from", "to", "from_z", "to_z", "way", "over", "off"]
const SHADE_KEYS: Array[String] = ["at", "shade"]

## Unique name, also its file name; what a cue's `flash` part names.
@export var id: StringName = &""
## How it is drawn (DRAWS).
@export var draw: StringName = &"shape"
## How long it shows (s), when its cue part gives no `seconds`.
@export_range(0.01, 5.0, 0.01) var seconds: float = 0.3
## Pixels a step of its zoom is: a cue part's `reach` (the cue's size times it, in pixels) is that
## many steps (a ring's radius, a flare's half width, the cracks' reach, an explosion's radius).
@export_range(0.5, 64.0, 0.5) var step: float = 12.0
## How much it lights the room at its start, while "Spell light" is on (0: not at all), fading
## over its life; a cue with a `light` part lights by that instead.
@export_range(0.0, 2.0, 0.05) var room_light: float = 0.0
## Drawn under the bodies, on the floor (the cracks), instead of over everything.
@export var on_floor: bool = false

@export_group("Shape")
## How its distances are measured (METRICS): a ring and its glow round, as a diamond (a rune's) or
## flat on the floor (seen from the side: 0.6 as high as wide).
@export var metric: StringName = &"round"
## The hash salt of its ring's fraying (two kinds with the same salt fray alike).
@export var salt: int = 32
@export var arm: Array[Dictionary] = []
@export var disc: Array[Dictionary] = []
@export var ring: Array[Dictionary] = []
@export var column_width: Array[Dictionary] = []
@export var column_top: Array[Dictionary] = []
@export var column_foot: Array[Dictionary] = []
@export var column_length: Array[Dictionary] = []
@export var column_dotted: Array[Dictionary] = []
@export var star: Array[Dictionary] = []
@export_range(2, 12) var star_points: int = 4
@export var rays: Array[Dictionary] = []
@export var rays_inner: Array[Dictionary] = []
@export_range(1, 31) var ray_count: int = 8
@export var dots: Array[Dictionary] = []
@export_range(1, 64) var dot_count: int = 12
@export var spiral: Array[Dictionary] = []
@export var spiral_turn: Array[Dictionary] = []
@export_range(1, 4) var spiral_arms: int = 1
## Pixels a zoom step between one arm's coils (the shader's gap is this times the zoom).
@export_range(2.0, 32.0, 0.5) var spiral_gap: float = 6.0

@export_group("Glow")
@export var glow: Array[Dictionary] = []
@export var glow_ring: Array[Dictionary] = []
@export var glow_ring_reach: Array[Dictionary] = []
@export var glow_middle: Array[Dictionary] = []
@export var glow_middle_reach: Array[Dictionary] = []

@export_group("Colours")
@export var first: Array[Dictionary] = []
@export var second: Array[Dictionary] = []


## Whether Feel's flash shader draws it (from the table), not a shader of its own.
func in_table() -> bool:
	return TABLE_DRAWS.has(draw)


## Whether it is drawn along a length (the cue's size times its part's `reach`), not at a zoom.
func along() -> bool:
	return LENGTH_DRAWS.has(draw)


## The curve called `curve` (NUMBER_CURVES or SHADE_CURVES).
func curve_of(curve: StringName) -> Array[Dictionary]:
	return get(curve) as Array[Dictionary]


## What is wrong with this kind, one line each (empty when nothing is).
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if id == &"":
		found.append("a flash kind needs an id")
	if not DRAWS.has(draw):
		found.append("%s: draw '%s' is not one of %s" % [id, draw, DRAWS])
	if not METRICS.has(metric):
		found.append("%s: metric '%s' is not one of %s" % [id, metric, METRICS])
	if seconds <= 0.0 or step <= 0.0 or room_light < 0.0:
		found.append("%s: seconds and step are above 0, room_light 0 or more" % id)
	if on_floor and draw != &"cracks":
		found.append("%s: only the cracks are drawn on the floor" % id)
	var drawn: bool = false
	for name: StringName in NUMBER_CURVES + SHADE_CURVES:
		var curve: Array[Dictionary] = curve_of(name)
		if not curve.is_empty() and not in_table():
			found.append("%s: a %s flash is drawn by its own shader, so it has no curves (%s)" % [id, draw, name])
		found.append_array(_curve_problems(name, curve))
		if not curve.is_empty() and PARTS.has(name):
			drawn = true
	if draw == &"shape" and not drawn:
		found.append("%s: a shape draws at least one of %s" % [id, PARTS])
	if star_points < 2 or star_points > MAX_POINTS or ray_count < 1 or ray_count > MAX_RAYS or dot_count < 1 or dot_count > MAX_DOTS or spiral_arms < 1 or spiral_arms > MAX_ARMS:
		found.append("%s: star_points 2-%d, ray_count 1-%d, dot_count 1-%d, spiral_arms 1-%d" % [id, MAX_POINTS, MAX_RAYS, MAX_DOTS, MAX_ARMS])
	if spiral_gap < 2.0:
		found.append("%s: spiral_gap is 2 px or more" % id)
	return found


func _curve_problems(name: StringName, curve: Array[Dictionary]) -> PackedStringArray:
	var found := PackedStringArray()
	if curve.size() > MAX_SEGMENTS:
		found.append("%s: %s has %d segments, at most %d" % [id, name, curve.size(), MAX_SEGMENTS])
	var shade: bool = SHADE_CURVES.has(name)
	var last: float = -1.0
	for i in curve.size():
		var segment: Dictionary = curve[i]
		for key: Variant in segment:
			if not (SHADE_KEYS if shade else SEGMENT_KEYS).has(str(key)):
				found.append("%s: %s segment %d has the key '%s', not one of %s" % [id, name, i, key, SHADE_KEYS if shade else SEGMENT_KEYS])
		var at: float = float(segment.get("at", 0.0))
		if i == 0 and at != 0.0:
			found.append("%s: %s starts at 0" % [id, name])
		if at < 0.0 or at >= 1.0 or at <= last:
			found.append("%s: %s segment %d starts at %s: from 0 to below 1, after the one before" % [id, name, i, at])
		last = at
		if shade:
			if not SHADES.has(StringName(segment.get("shade", ""))):
				found.append("%s: %s segment %d's shade is not one of %s" % [id, name, i, SHADES])
			continue
		if not WAYS.has(StringName(segment.get("way", "linear"))):
			found.append("%s: %s segment %d's way is not one of %s" % [id, name, i, WAYS])
		if segment.has("over") and float(segment["over"]) <= at:
			found.append("%s: %s segment %d reaches its end (over) after it starts" % [id, name, i])
		if bool(segment.get("off", false)) and (segment.has("from") or segment.has("from_z") or segment.has("to") or segment.has("to_z")):
			found.append("%s: %s segment %d is off, so it has no values" % [id, name, i])
	return found
