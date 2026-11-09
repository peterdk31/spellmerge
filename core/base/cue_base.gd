class_name CueBase
extends Resource
## A cue: a moment's look and weight, as data (gameplay/feel plays it: `Feel.play_cue`, or the
## `cue_shown` event). One `.tres` per cue under `content/cues/`, found by its `id` (the registry's
## folder `cues`), so a new moment (an exploding barrel, a boss's death) is a new file and no list
## is edited. A cue is played at a point with what set it off: who (its ramp), which way, how big
## (its `size` in pixels, the radius of an explosion or the reach of a ground strike; seconds for
## a telegraph), its element's colour and its cards. Feel's moments with a life of their own
## (beams, swing trails, statuses, ghosts) are not cues; a dash's start, path and landing are (S5;
## its path a `stream` part of its start).
##
## The cue's `parts` are each a Dictionary of a part type (its `part`; PART_TYPES, each with the
## keys it may have). Feel plays each part by the player of its type (`Feel.add_cue_part`;
## docs/milestones/spell-spectacle-2.md, S1), so a new kind of part is a row in PART_TYPES (and
## its checks in `_type_problems`, if it has any) and a player in Feel or its spectacle.
##
## A `lane` part (docs/milestones/cast-timing.md, T6b) is a telegraph: a lane from its caster's
## staff tip along its live aim, as long as the carrier of the cue's `tag` reaches (times `reach`,
## 1 by default) and as wide as it hits, in the cue's tint, brightening, its dashes marching and its
## arrowhead growing until the cast leaves (`Spells.is_winding`; `size` is the wind-up's seconds).
## A carrier that is not aimed (a nova, an orbit) shows none. `gameplay/feel/lanes.gd` draws it.
##
## A part with no `part` (or `"part": "flash"`) is a flash Feel draws:
##   `flash`      a flash kind's id (required; content/flashes, `FlashKind`)
##   `zoom`       its size step, fixed (1 when neither this nor `reach` is given; a fraction is
##                rounded after the cue's `power`)
##   `reach`      its size from the cue's: `size` x reach pixels (Feel turns pixels into its zoom)
##   `seconds`    how long it shows (the flash's own when not given)
##   `lasts_size` true: it lasts the cue's `size` in seconds instead (a telegraph: the wait until
##                what it warns of comes), and is left out when that is 0
##   `color`      this exact colour, instead of the caster's ramp and the cue's tint
##   `plain`      true: white in no one's ramp, without the cards (stone chips)
##   `bare`       true: in the caster's ramp, without the cards (a dash's landing ring, a cast's flash)
##   `no_cards`   true: in the cue's ramp and tint, without the cards (a wall's impact ring)
##   `body`       true: in the own colour of the body the cue is of (a dying enemy's
##                `EnemyBase.hit_color`: its death puff, S6), in no one's ramp and without the
##                cards; plain white when the cue has no body colour
##   `way`        `aim` (the cue's direction, the default), `back` (against it), `right` or `up`
##   `particles`  true: left out while particles are off (the stress benchmark)
##   `floor`      true: drawn on the floor, under the bodies, instead of over everything (a ground
##                strike's flash: a slam's; an arc, an explosion's part or a status stays where it is)
##   `if_cards`   true: played only when the cue has cards (a look layer; an element's flare)
##   `if_layer`   a look layer (1 to MoteKind.LOOK_LAYERS; the LOOK_* kinds of core/projectiles):
##                played only when the cue's cards have it (lightning's arc: 5)
##   `if_size_over`, `if_size_upto`  played only when the cue's size is over this, or this or less
##                (a zap's spark into the air, 22 px at the most, burns out sooner than a zap)
## A flash kind drawn along a length (`FlashKind.along`: the `arc`) runs the cue's `size` x its
## `reach` (1 when not given) pixels from the cue's point along its way (left out when that is 0),
## and takes no `zoom`.
## A cue's line (S6, item 9): its way for its `size` pixels from its point (a staff swap is played
## at the staff's grip, along it, its size the staff's length). A flash, a motes part or a light
## may say where on it it plays: `along`, 0 (the cue's point, the default) to 1 (the line's end; 0.5
## its middle). A motes part with `line` true is thrown from all along the line instead of from one
## point (each mote from a point of it at random): a staff unravelling into motes.
## A motes part's `life` is times its kinds' own lives (0.5: a moment over twice as fast).
## A cue played on a body (`Feel.play_cue`'s `follow`: a staff's poof, a possession's ring) follows
## it: its flashes move with the body while they last, where they were played from it, and end
## when it is gone. Its motes, marks and lights stay where it played (they fly, lie and glow in
## the room).
## A part with `"part": "motes"` throws motes instead (docs/milestones/spell-spectacle.md, P1; Feel's
## `mote.gd`, left out with the "Particles" setting or particles off), each count times the
## "Particle amount" setting:
##   `kind`       `spell` (the default): the kinds of the cue's cards (its look's layers), in its
##                ramp and colour; `surface`: the surface kinds, in the colours of what broke (the
##                room's walls, or the art of a body that died); or a kind's id (content/motes),
##                coloured as its own kind is
##   `colours`    `spell` or `surface`: the colours they cool through, in place of their kind's
##                (ash, a kind no card names, in the colours of what burned)
##   `count`      how many in all, split between the kinds (each kind's own count when not given)
##   `reach`      they fly out to the cue's `size` x reach pixels at the most (the kinds' own speed
##                when not given, or when the cue has no size)
##   `spread`     degrees round the way (the kind's own when not given; 360 all round)
##   `up`         times the kind's own speed up (1 when not given)
##   `radius`     they fly out this many pixels at the most when the cue has no size (or the part
##                no `reach`)
##   `ring`       true: all go out as fast, a ring
##   `way`        as a flash's
##   `below`      thrown from this many pixels below the cue's point (a body's feet: 8)
##   `often`      true: a moment of many a frame (a hit's spray), which stops once only the frame's
##                rows the rarer moments keep are left (`Motes.MOMENT_ROWS`), as a shot's shed does
##   `color`      this exact colour, instead of the caster's ramp and the cue's tint (not for
##                what cools through a surface's colours)
##   `body`       true: in the own colour of the body the cue is of, as a flash's `body` (a death
##                puff's sparks)
##   `bare`       true: in the caster's ramp, without the cards, as a flash's `bare` (a cast's
##                sparks, in the seat's colours)
##   `share`      each kind thrown its own count times this, the share split between the kinds,
##                as one of many a frame (a shot's end, S6: `expire`; `often` too): it leaves the moments' rows
##                to the moments and is skipped once only those are left (`Motes.shed_closed`).
##                Takes no `count`, `reach`, `radius` or `ring`: the kinds fly as they shed
## A part with `"part": "mark"` is not a flash but a floor mark (docs/milestones/spell-spectacle.md,
## P2a): stamped once into the room's mark layer, it stays until the room ends. Its keys (MARK_KEYS):
##   `mark`       the mark kind's id (`MarkKind`, content/marks; required, unless `cards`)
##   `reach`      its radius from the cue's: `size` x reach pixels
##   `radius`     its radius in pixels, when the cue has no size (or with no `reach`; 8 when neither)
##   `rot`        `random` (the default) or `aim`: turned the cue's way
##   `cards`      true: the marks of the cue's cards instead when they have any (a frost blast
##                leaves frost where a plain one leaves its scorch); with no `mark`, only theirs
##                (a frost dash's landing leaves frost, a plain one nothing)
## A part with `"part": "light"` lights the room round the cue's point while the "Spell light" setting
## is on (S6, item 4; gameplay/feel/spell_light.gd), fading to nothing over its seconds. Its keys
## (LIGHT_KEYS):
##   `strength`   how bright at first (1 when not given; 2 at the most)
##   `reach`      how far it reaches from the cue's: `size` x reach pixels
##   `radius`     how far in pixels, when the cue has no size (or with no `reach`; 40 when neither)
##   `seconds`    how long it lasts (0.3 when not given)
##   `color`, `plain`, `bare`  its colour, as a flash's
## A part with `"part": "stream"` gives off motes from its cue's caster while it moves (a dash's
## speed streaks and its cards' particles; gameplay/feel/streams.gd): from the moment the cue plays
## until the carrier it shows ends (`carrier_ended` of its caster and spell), its caster has no
## anchor (core/projectiles' `get_anchor`), or its `seconds` run out, following that anchor and
## thrown back against the way it goes (the cue's way until it has moved). Left out with the
## "Particles" setting or particles off. Its keys (STREAM_KEYS):
##   `kind`       `dash_path` (the default: the dash path kinds, `MoteKind.dash_path`, in the
##                caster's ramp without its cards) or `spell` (the cue's cards: each try picks one of
##                its look's layers that give off particles and keeps it at a shot's rate for that
##                layer, `ProjectileManager.SPARK_RATES`, as a shot's trail does; none for no cards)
##   `rate`       tries a second (60 when not given)
##   `side`       pixels across the way it goes they leave from (spread evenly; 0 when not given)
##   `ahead`      pixels along it, either side, they leave from (0 when not given)
##   `feet_layers` the look layers that leave from its feet instead (fire's embers and frost's
##                flecks: [1, 2]), `below` pixels under it
##   `below`      how far under it its feet are (8 when not given)
##   `seconds`    the most it lasts (2 when not given), should its carrier's end never come
## A cue with a light part lights by its light parts alone: its flashes do not light the room by
## their kinds as they otherwise do (`FlashKind.room_light`), so content says how a rune or a
## heal lights.
## Its weight: `shake` (screen trauma, 0 to 1, on top of anything else's), `kick` pixels of camera
## punch `kick_way` (`down` the screen, `away` from the caster's body towards the cue, `back`
## against the cue's direction, `aim` along it: these two only when it has one, a cast's kick back),
## `hold` seconds of local stop on the caster and
## `hold_target` on the target (each held alone; nobody else waits), `hold_shot` to hold the shot
## being sent too, `stop_game` seconds of the game-wide stop (only a downed player and a boss's
## death: melee I7), and the `sound` id asked from the registry (silent until an `.ogg` exists).
## The holds and the game-wide stop are the game's: `gameplay/combat/hit_stop.gd` plays them where
## the simulation's moments happen (online-ready N4), Feel only the rest.
##
## Its own colour and strength (S6): `color`, when it has one, is the exact colour of every flash and
## motes part that names no colour (nor `plain`, nor `bare`) of its own, and of what Feel draws of the
## moment in code (a reaction's name). `power` scales how strong it plays, by one rule (`Feel.play_cue`):
## times every flash's size (its zoom, or its size from `reach`), every motes part's count and how
## far they fly, every mark's radius and every light's reach, its holds, shake and punch; never a part's seconds, nor an
## arc's length (where it runs). A reaction's cues differ in their colour and power only.
##
## How often (S6, item 13): `every` seconds is the least time between two plays of the cue for the
## same actor (the one it is of; none counts as one more), so a moment that comes by the hundred (a
## body caught by a pull, every step) shows a few times a second; a play sooner is left out whole, parts and
## weight. 0 (the default) plays every time.

## The cues of moments both the game's hit-stop (gameplay/combat/hit_stop.gd) and Feel play: one
## name each, here, so the two always pick the same cue.
const REACTION_CUE: StringName = &"reaction"
const PARRY_CUE: StringName = &"parry"
const DOWNED_CUE: StringName = &"player_downed"
const ENEMY_DEATH_CUE: StringName = &"enemy_death"
const BOSS_DEATH_CUE: StringName = &"boss_death"
## A reaction's cue weighs in (its holds; Feel's sound and shake) at most once in this many
## seconds, per reaction.
const REACTION_REPEAT: float = 0.3

const WAYS: Array[StringName] = [&"aim", &"back", &"right", &"up"]
const KICK_WAYS: Array[StringName] = [&"down", &"away", &"back", &"aim"]
## The keys of each kind of part: a flash (`flash`), motes and a floor mark.
const PART_KEYS: Array[String] = ["part", "flash", "zoom", "reach", "seconds", "lasts_size", "color", "plain", "bare", "no_cards", "body", "way", "particles", "if_cards", "if_layer", "if_size_over", "if_size_upto", "along", "floor"]
const MOTE_KEYS: Array[String] = ["part", "kind", "colours", "count", "reach", "radius", "spread", "up", "ring", "way", "below", "color", "bare", "often", "share", "body", "along", "line", "life"]
const MARK_KEYS: Array[String] = ["part", "mark", "reach", "radius", "rot", "cards"]
const LIGHT_KEYS: Array[String] = ["part", "strength", "reach", "radius", "seconds", "color", "plain", "bare", "along"]
const STREAM_KEYS: Array[String] = ["part", "kind", "rate", "side", "ahead", "feet_layers", "below", "seconds"]
const LANE_KEYS: Array[String] = ["part", "reach"]
## The part types a cue may have (a part's `part`; none is `flash`), each with the keys it may have.
const PART_TYPES: Dictionary = {&"flash": PART_KEYS, &"motes": MOTE_KEYS, &"mark": MARK_KEYS, &"light": LIGHT_KEYS, &"stream": STREAM_KEYS, &"lane": LANE_KEYS}
## What a `stream` part gives off (its `kind`).
const STREAM_KINDS: Array[StringName] = [&"dash_path", &"spell"]
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
## Its own colour (none while its alpha is 0), and how strong it plays (see above).
@export var color: Color = Color(0.0, 0.0, 0.0, 0.0)
@export_range(0.1, 4.0, 0.05) var power: float = 1.0
## The least seconds between two plays for the same actor (see above); 0 every time.
@export_range(0.0, 5.0, 0.01) var every: float = 0.0


## Whether 0 for not yet known, then 1 or 2: the cue has a `light` part (`lights`).
var _lights: int = 0


func kind() -> StringName:
	return &"cue"


## Whether it has a `light` part, so it lights by its light parts alone (its flashes unlit). Read
## from its parts once.
func lights() -> bool:
	if _lights == 0:
		_lights = 1
		for part: Dictionary in parts:
			if StringName(part.get("part", "flash")) == &"light":
				_lights = 2
	return _lights == 2


## What is wrong with this cue, one line each (empty when nothing is): an unknown part type, way or
## key, or a number out of its range. Whether its flash kinds exist is `kind_problems`.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if id == &"":
		found.append("a cue needs an id")
	if power <= 0.0:
		found.append("%s: power %s is 0 or less" % [id, power])
	if every < 0.0:
		found.append("%s: every %s is below 0" % [id, every])
	if not KICK_WAYS.has(kick_way):
		found.append("%s: kick_way '%s' is not one of %s" % [id, kick_way, KICK_WAYS])
	for i in parts.size():
		var part: Dictionary = parts[i]
		var type: StringName = StringName(part.get("part", "flash"))
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
	if part.has("along") and (float(part["along"]) < 0.0 or float(part["along"]) > 1.0):
		return PackedStringArray(["%s: part %d's along is not from 0 to 1" % [id, i]])
	match type:
		&"flash":
			return _flash_problems(i, part)
		&"motes":
			return _mote_problems(i, part)
		&"mark":
			return _mark_problems(i, part)
		&"light":
			return _light_problems(i, part)
		&"stream":
			return _stream_problems(i, part)
	return PackedStringArray()


## What is wrong with the flash part `i` (`part`): no kind, or sizes that clash or are 0 or less.
func _flash_problems(i: int, part: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	if StringName(part.get("flash", "")) == &"":
		found.append("%s: part %d names no flash kind" % [id, i])
	if part.has("zoom") and part.has("reach"):
		found.append("%s: part %d has both zoom and reach" % [id, i])
	if part.has("lasts_size") and (part.has("seconds") or part.has("reach")):
		found.append("%s: part %d lasts the cue's size, so it takes no seconds or reach" % [id, i])
	if float(part.get("seconds", 1.0)) <= 0.0 or float(part.get("reach", 1.0)) <= 0.0 or float(part.get("zoom", 1.0)) < 1.0:
		found.append("%s: part %d has a seconds, reach or zoom of 0 or less" % [id, i])
	if int(part.has("color")) + int(bool(part.get("plain", false))) + int(bool(part.get("bare", false))) + int(bool(part.get("no_cards", false))) + int(bool(part.get("body", false))) > 1:
		found.append("%s: part %d takes one of color, plain, bare, no_cards and body" % [id, i])
	if part.has("if_layer") and (int(part["if_layer"]) < 1 or int(part["if_layer"]) > MoteKind.LOOK_LAYERS):
		found.append("%s: part %d's if_layer is not a look layer (1-%d)" % [id, i, MoteKind.LOOK_LAYERS])
	if part.has("if_size_over") and part.has("if_size_upto") and float(part["if_size_upto"]) <= float(part["if_size_over"]):
		found.append("%s: part %d's if_size_over and if_size_upto leave no size it plays at" % [id, i])
	return found


## What is wrong with this cue's flash parts with the flash kinds `kinds` (id -> FlashKind; the
## registry's content/flashes): a kind there is not, or a zoom or lasts_size on a kind drawn along a
## length (`tests/content/test_cues.gd` checks every cue).
func kind_problems(kinds: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	for i in parts.size():
		var part: Dictionary = parts[i]
		if StringName(part.get("part", "flash")) != &"flash":
			continue
		var flash: StringName = StringName(part.get("flash", ""))
		var kind: FlashKind = kinds.get(flash) as FlashKind
		if kind == null:
			found.append("%s: part %d's flash '%s' is no flash kind (content/flashes)" % [id, i, flash])
		elif kind.along() and (part.has("zoom") or part.has("lasts_size")):
			found.append("%s: part %d's %s is drawn along the cue's size: it takes no zoom or lasts_size" % [id, i, flash])
	return found


## What is wrong with the `motes` part `i` (`part`): a kind of no name, or a number out of its
## range. Whether its kind exists is the registry's (tests/gameplay/feel/test_motes.gd).
func _mote_problems(i: int, part: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	if StringName(part.get("kind", "spell")) == &"":
		found.append("%s: motes part %d names no kind" % [id, i])
	if int(part.get("count", 1)) < 1 or float(part.get("reach", 1.0)) <= 0.0 or float(part.get("radius", 1.0)) <= 0.0 or float(part.get("up", 1.0)) < 0.0:
		found.append("%s: motes part %d has a count, reach or radius of 0 or less, or an up below 0" % [id, i])
	if float(part.get("spread", 0.0)) < 0.0 or float(part.get("spread", 0.0)) > 360.0:
		found.append("%s: motes part %d's spread is not 0 to 360 degrees" % [id, i])
	if part.has("colours") and not MOTE_GROUPS.has(StringName(part["colours"])):
		found.append("%s: motes part %d's colours are not one of %s" % [id, i, MOTE_GROUPS])
	var paints: int = int(part.has("color")) + int(bool(part.get("bare", false))) + int(bool(part.get("body", false)))
	if paints > 1:
		found.append("%s: motes part %d has more than one of color, bare and body" % [id, i])
	if bool(part.get("bare", false)) and StringName(part.get("kind", "spell")) == &"spell":
		found.append("%s: motes part %d is bare (without the cards) but throws the cards' kinds" % [id, i])
	if float(part.get("life", 1.0)) <= 0.0 or float(part.get("life", 1.0)) > 4.0:
		found.append("%s: motes part %d's life is not over 0 and at most 4 times its kinds'" % [id, i])
	if float(part.get("below", 0.0)) < 0.0 or float(part.get("below", 0.0)) > 32.0:
		found.append("%s: motes part %d's below is not 0 to 32 pixels" % [id, i])
	if part.has("share"):
		if float(part["share"]) <= 0.0:
			found.append("%s: motes part %d's share is 0 or less" % [id, i])
		for key: String in ["count", "reach", "radius", "ring"]:
			if part.has(key):
				found.append("%s: motes part %d sheds a share of its kinds, so it takes no %s" % [id, i, key])
	return found


## What is wrong with the mark part `part` (number `i`). Whether its mark exists is the
## registry's to say (`tests/content/test_cues.gd`).
func _mark_problems(i: int, part: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	if StringName(part.get("mark", "")) == &"" and not bool(part.get("cards", false)):
		found.append("%s: mark part %d names no mark (and takes no cards' marks)" % [id, i])
	if part.has("rot") and not MARK_ROTS.has(StringName(part["rot"])):
		found.append("%s: mark part %d's rot '%s' is not one of %s" % [id, i, part["rot"], MARK_ROTS])
	if float(part.get("reach", 1.0)) <= 0.0 or float(part.get("radius", 1.0)) <= 0.0:
		found.append("%s: mark part %d has a reach or radius of 0 or less" % [id, i])
	return found


## What is wrong with the light part `part` (number `i`): a number out of its range, or more than
## one of its colours.
func _light_problems(i: int, part: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	var strength: float = float(part.get("strength", 1.0))
	if strength <= 0.0 or strength > 2.0:
		found.append("%s: light part %d's strength is not above 0 and at most 2" % [id, i])
	if float(part.get("reach", 1.0)) <= 0.0 or float(part.get("radius", 1.0)) <= 0.0 or float(part.get("seconds", 1.0)) <= 0.0:
		found.append("%s: light part %d has a reach, radius or seconds of 0 or less" % [id, i])
	if int(part.has("color")) + int(bool(part.get("plain", false))) + int(bool(part.get("bare", false))) > 1:
		found.append("%s: light part %d takes one of color, plain and bare" % [id, i])
	return found


## What is wrong with the stream part `part` (number `i`): a kind it does not know, a number out
## of its range, or a feet layer that is not a look layer.
func _stream_problems(i: int, part: Dictionary) -> PackedStringArray:
	var found := PackedStringArray()
	if not STREAM_KINDS.has(StringName(part.get("kind", "dash_path"))):
		found.append("%s: stream part %d's kind '%s' is not one of %s" % [id, i, part.get("kind"), STREAM_KINDS])
	if float(part.get("rate", 1.0)) <= 0.0 or float(part.get("seconds", 1.0)) <= 0.0:
		found.append("%s: stream part %d has a rate or seconds of 0 or less" % [id, i])
	if float(part.get("side", 0.0)) < 0.0 or float(part.get("ahead", 0.0)) < 0.0 or float(part.get("below", 0.0)) < 0.0 or float(part.get("below", 0.0)) > 32.0:
		found.append("%s: stream part %d has a side or ahead below 0, or a below not 0 to 32 pixels" % [id, i])
	for layer: Variant in part.get("feet_layers", []):
		if int(layer) < 1 or int(layer) > MoteKind.LOOK_LAYERS:
			found.append("%s: stream part %d's feet layer %s is not a look layer (1-%d)" % [id, i, layer, MoteKind.LOOK_LAYERS])
	return found


## The cue of the reaction `reaction_id`: its own (`reaction_<id>`) where `find` (a cue id to its
## CueBase, or null) has one, else REACTION_CUE.
static func reaction_cue(reaction_id: StringName, find: Callable) -> StringName:
	var own: StringName = StringName("reaction_" + String(reaction_id))
	return own if find.call(own) != null else REACTION_CUE
