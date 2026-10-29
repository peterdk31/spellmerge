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
## The cue's `parts` are flashes Feel draws, each a Dictionary:
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
	&"quake", &"shell", &"fireball", &"debris", &"scorch",
]
const WAYS: Array[StringName] = [&"aim", &"back", &"right", &"up"]
const KICK_WAYS: Array[StringName] = [&"down", &"away", &"back", &"aim"]
## The keys a part may have.
const PART_KEYS: Array[String] = ["effect", "zoom", "reach", "seconds", "lasts_size", "color", "plain", "way", "particles"]

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
		var effect: StringName = StringName(part.get("effect", ""))
		if not EFFECTS.has(effect):
			found.append("%s: part %d's effect '%s' is not one of %s" % [id, i, effect, EFFECTS])
		for key: Variant in part.keys():
			if not PART_KEYS.has(String(key)):
				found.append("%s: part %d has an unknown key '%s'" % [id, i, key])
		if part.has("way") and not WAYS.has(StringName(part["way"])):
			found.append("%s: part %d's way '%s' is not one of %s" % [id, i, part["way"], WAYS])
		if part.has("zoom") and part.has("reach"):
			found.append("%s: part %d has both zoom and reach" % [id, i])
		if part.has("lasts_size") and (part.has("seconds") or part.has("reach")):
			found.append("%s: part %d lasts the cue's size, so it takes no seconds or reach" % [id, i])
		if float(part.get("seconds", 1.0)) <= 0.0 or float(part.get("reach", 1.0)) <= 0.0 or int(part.get("zoom", 1)) < 1:
			found.append("%s: part %d has a seconds, reach or zoom of 0 or less" % [id, i])
	return found
