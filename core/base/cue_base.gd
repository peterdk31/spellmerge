class_name CueBase
extends Resource
## A cue: a moment's look and weight, as data (gameplay/feel plays it: `Feel.play_cue`, or the
## `cue_shown` event). One `.tres` per cue under `content/cues/`, found by its `id` (the registry's
## folder `cues`), so a new moment (an exploding barrel, a boss's death) is a new file and no list
## is edited. A cue is played at a point with what set it off: who (its ramp), which way, how big
## (its `size` in pixels, the radius of an explosion or the reach of a ground strike; seconds for
## a telegraph), its element's colour and its cards. Feel's moments with a life of their own
## (beams, dashes, swing trails, statuses, ghosts) are not cues.
##
## The cue's `parts` are each a Dictionary of a part type (its `part`; PART_TYPES, each with the
## keys it may have). Feel plays each part by the player of its type (`Feel.add_cue_part`;
## docs/milestones/spell-spectacle-2.md, S1), so a new kind of part is a row in PART_TYPES (and
## its checks in `_type_problems`, if it has any) and a player in Feel or its spectacle.
##
## A part with no `part` (or `"part": "effect"`) is a flash Feel draws:
##   `effect`     one of EFFECTS (required)
##   `zoom`       its size step, fixed (1 when neither this nor `reach` is given)
##   `reach`      its size from the cue's: `size` x reach pixels (Feel turns pixels into its zoom)
##   `seconds`    how long it shows (the effect's own when not given)
##   `lasts_size` true: it lasts the cue's `size` in seconds instead (a telegraph: the wait until
##                what it warns of comes), and is left out when that is 0
##   `color`      this exact colour, instead of the caster's ramp and the cue's tint
##   `plain`      true: white in no one's ramp, without the cards (stone chips)
##   `way`        `aim` (the cue's direction, the default), `back` (against it), `right` or `up`
##   `particles`  true: left out while particles are off (the stress benchmark)
## A part with `"part": "motes"` throws motes instead (docs/milestones/spell-spectacle.md, P1; Feel's
## `mote.gd`, left out with the "Particles" setting or particles off), each count times the
## "Particle amount" setting:
##   `kind`       `spell` (the default): the kinds of the cue's cards (its look's layers), in its
##                ramp and colour; `surface`: the surface kinds, in the colours of what broke (the
##                room's walls, or the art of a body that died); or a kind's id (content/motes),
##                coloured as its own kind is
##   `count`      how many in all, split between the kinds (each kind's own count when not given)
##   `reach`      they fly out to the cue's `size` x reach pixels at the most (the kinds' own speed
##                when not given, or when the cue has no size)
##   `spread`     degrees round the way (the kind's own when not given; 360 all round)
##   `up`         times the kind's own speed up (1 when not given)
##   `ring`       true: all go out as fast, a ring
##   `way`        as an effect's
## A part with `"part": "mark"` is not a flash but a floor mark (docs/milestones/spell-spectacle.md,
## P2a): stamped once into the room's mark layer, it stays until the room ends. Its keys (MARK_KEYS):
##   `mark`       the mark kind's id (`MarkKind`, content/marks; required)
##   `reach`      its radius from the cue's: `size` x reach pixels
##   `radius`     its radius in pixels, when the cue has no size (or with no `reach`; 8 when neither)
##   `rot`        `random` (the default) or `aim`: turned the cue's way
##   `cards`      true: the marks of the cue's cards instead when they have any (a frost blast
##                leaves frost where a plain one leaves its scorch)
## Its weight: `shake` (screen trauma, 0 to 1, on top of anything else's), `kick` pixels of camera
## punch `kick_way` (`down` the screen, `away` from the caster's body towards the cue, `back`
## against the cue's direction, `aim` along it), `hold` seconds of local stop on the caster and
## `hold_target` on the target (each held alone; nobody else waits), `hold_shot` to hold the shot
## being sent too, `stop_game` seconds of the game-wide stop (only a downed player and a boss's
## death: melee I7), and the `sound` id asked from the registry (silent until an `.ogg` exists).

## The flashes a part can name (Feel maps each to its effect kind, and says how many pixels a
## step of its zoom is).
const EFFECTS: Array[StringName] = [
	&"burst", &"ring_out", &"ring_in", &"rune_burst", &"cast", &"spray", &"puff", &"chips",
	&"quake", &"shell", &"fireball", &"debris", &"scorch", &"rise", &"fall",
]
const WAYS: Array[StringName] = [&"aim", &"back", &"right", &"up"]
const KICK_WAYS: Array[StringName] = [&"down", &"away", &"back", &"aim"]
## The keys of each kind of part: a flash (`effect`), motes and a floor mark.
const PART_KEYS: Array[String] = ["part", "effect", "zoom", "reach", "seconds", "lasts_size", "color", "plain", "way", "particles"]
const MOTE_KEYS: Array[String] = ["part", "kind", "count", "reach", "spread", "up", "ring", "way"]
const MARK_KEYS: Array[String] = ["part", "mark", "reach", "radius", "rot", "cards"]
## The part types a cue may have (a part's `part`; none is `effect`), each with the keys it may have.
const PART_TYPES: Dictionary = {&"effect": PART_KEYS, &"motes": MOTE_KEYS, &"mark": MARK_KEYS}
## The kinds a `motes` part names besides a kind's id, and a mark part's turns.
const MOTE_GROUPS: Array[StringName] = [&"spell", &"surface"]
const MARK_ROTS: Array[StringName] = [&"random", &"aim"]

## Its name; the registry finds it by this under `cues`, and the file is `<id>.tres`.
@export var id: StringName = &""
@export var parts: Array[Dictionary] = []
@export_range(0.0, 1.0, 0.01) var shake: float = 0.0
@export_range(0.0, 8.0, 0.1) var kick: float = 0.0
@export var kick_way: StringName = &"down"
@export_range(0.0, 0.5, 0.01) var hold: float = 0.0
@export_range(0.0, 0.5, 0.01) var hold_target: float = 0.0
@export var hold_shot: bool = false
@export_range(0.0, 0.5, 0.01) var stop_game: float = 0.0
@export var sound: StringName = &""


func kind() -> StringName:
	return &"cue"


## What is wrong with this cue, one line each (empty when nothing is): an unknown effect, way or
## key, or a number out of its range.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if id == &"":
		found.append("a cue needs an id")
	if not KICK_WAYS.has(kick_way):
		found.append("%s: kick_way '%s' is not one of %s" % [id, kick_way, KICK_WAYS])
	for i in parts.size():
		var part: Dictionary = parts[i]
		var type: StringName = StringName(part.get("part", "effect"))
		if not PART_TYPES.has(type):
			found.append("%s: part %d's type '%s' is not one of %s" % [id, i, type, PART_TYPES.keys()])
			continue
		var keys: Array = PART_TYPES[type]
		for key: Variant in part.keys():
			if not keys.has(String(key)):
				found.append("%s: %s part %d has an unknown key '%s'" % [id, type, i, key])
		if part.has("way") and not WAYS.has(StringName(part["way"])):
			found.append("%s: %s part %d's way '%s' is not one of %s" % [id, type, i, part["way"], WAYS])
		found.append_array(_type_problems(type, i, part))
	return found


## What else is wrong with the part `i` (`part`) of the type `type`: what its type checks beyond
## its keys and its way. A type with nothing more to check needs no line here.
func _type_problems(type: StringName, i: int, part: Dictionary) -> PackedStringArray:
	match type:
		&"effect":
			return _effect_problems(i, part)
		&"motes":
			return _mote_problems(i, part)
		&"mark":
			return _mark_problems(i, part)
	return PackedStringArray()


## What is wrong with the flash part `i` (`part`): an unknown effect, or sizes that clash or are 0
## or less.
func _effect_problems(i: int, part: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	var effect: StringName = StringName(part.get("effect", ""))
	if not EFFECTS.has(effect):
		found.append("%s: part %d's effect '%s' is not one of %s" % [id, i, effect, EFFECTS])
	if part.has("zoom") and part.has("reach"):
		found.append("%s: part %d has both zoom and reach" % [id, i])
	if part.has("lasts_size") and (part.has("seconds") or part.has("reach")):
		found.append("%s: part %d lasts the cue's size, so it takes no seconds or reach" % [id, i])
	if float(part.get("seconds", 1.0)) <= 0.0 or float(part.get("reach", 1.0)) <= 0.0 or int(part.get("zoom", 1)) < 1:
		found.append("%s: part %d has a seconds, reach or zoom of 0 or less" % [id, i])
	return found


## What is wrong with the `motes` part `i` (`part`): a kind of no name, or a number out of its
## range. Whether its kind exists is the registry's (tests/gameplay/feel/test_motes.gd).
func _mote_problems(i: int, part: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	if StringName(part.get("kind", "spell")) == &"":
		found.append("%s: motes part %d names no kind" % [id, i])
	if int(part.get("count", 1)) < 1 or float(part.get("reach", 1.0)) <= 0.0 or float(part.get("up", 1.0)) < 0.0:
		found.append("%s: motes part %d has a count or reach of 0 or less, or an up below 0" % [id, i])
	if float(part.get("spread", 0.0)) < 0.0 or float(part.get("spread", 0.0)) > 360.0:
		found.append("%s: motes part %d's spread is not 0 to 360 degrees" % [id, i])
	return found


## What is wrong with the mark part `part` (number `i`). Whether its mark exists is the
## registry's to say (`tests/content/test_cues.gd`).
func _mark_problems(i: int, part: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	if StringName(part.get("mark", "")) == &"":
		found.append("%s: mark part %d names no mark" % [id, i])
	if part.has("rot") and not MARK_ROTS.has(StringName(part["rot"])):
		found.append("%s: mark part %d's rot '%s' is not one of %s" % [id, i, part["rot"], MARK_ROTS])
	if float(part.get("reach", 1.0)) <= 0.0 or float(part.get("radius", 1.0)) <= 0.0:
		found.append("%s: mark part %d has a reach or radius of 0 or less" % [id, i])
	return found
