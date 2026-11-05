extends RefCounted
## Mote streams: a cue's `stream` parts (`CueBase`, "part": "stream"; docs/milestones/spell-spectacle-2.md,
## S5). A stream gives off motes from its cue's caster while it moves: a dash's speed streaks and
## its cards' particles, back along the way it goes, where it really goes (sliding along a wall,
## homing). It follows the caster's anchor in the projectile manager (`get_anchor`, the body's
## middle, as its orbit shots do) and lasts from the cue until the carrier it shows ends (`end`, for
## `carrier_ended` of its caster and spell), the anchor is gone, or its part's `seconds` run out.
## A new stream of the same part for the same caster takes over (a dash ends the one before).
##
## Its motes are births in the trails' format (`births.gd`), given off with Feel's own drawings',
## so they take their spell's cards' kinds by its tag as a shot's do. Nothing here changes a fight:
## a stream reads the anchor and keeps nothing the simulation reads (the dash's look was the
## projectile manager's `follow_caster` until 2026-11-05). The spectacle owns one (`Spectacle.streams`)
## and steps it once a frame. Allocation-free while it runs.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const BirthsScript := preload("res://gameplay/feel/births.gd")

## The most streams at once; one more takes the place of the one that would end soonest.
const MOST: int = 64
## What a stream gives off (`CueBase.STREAM_KINDS`): the dash path kinds, or its cards'.
const KIND_PATH: int = 0
const KIND_SPELL: int = 1
## The way a stream goes is taken again once its caster has moved this far (px) since the last.
const MOVED: float = 0.25
## Its feet layers' motes leave from this wide a patch (px across, px down).
const FEET_ACROSS: float = 8.0
const FEET_DOWN: float = 2.0
## The longest frame a stream gives off for (s): a frame after a stall gives off no more.
const LONGEST_FRAME: float = 0.1


## A `stream` part read into its typed fields once (`prepare`).
class Part:
	var kind: int = KIND_PATH
	var rate: float = 60.0
	var side: float = 0.0
	var ahead: float = 0.0
	var feet: PackedInt32Array = PackedInt32Array()
	var below: float = 8.0
	var seconds: float = 2.0


## The streams under way: the first `count` of each list.
var count: int = 0
var _part: Array[Part] = []
var _caster: PackedInt32Array = PackedInt32Array()
var _tag: PackedInt64Array = PackedInt64Array()
var _until: PackedFloat64Array = PackedFloat64Array()
var _ramp: PackedInt32Array = PackedInt32Array()
var _look: PackedInt32Array = PackedInt32Array()
var _core: PackedColorArray = PackedColorArray()
## Where its caster was when the way was last taken, and that way (unit).
var _last: PackedVector2Array = PackedVector2Array()
var _way: PackedVector2Array = PackedVector2Array()
## Feel's clock at the last step.
var _clock: float = -1.0


func _init() -> void:
	_part.resize(MOST)
	_caster.resize(MOST)
	_tag.resize(MOST)
	_until.resize(MOST)
	_ramp.resize(MOST)
	_look.resize(MOST)
	_core.resize(MOST)
	_last.resize(MOST)
	_way.resize(MOST)


## A cue's `stream` part (a Dictionary, `CueBase.STREAM_KEYS`) read into a `Part`.
static func prepare(part: Dictionary) -> Part:
	var made := Part.new()
	made.kind = KIND_SPELL if StringName(part.get("kind", "dash_path")) == &"spell" else KIND_PATH
	made.rate = float(part.get("rate", 60.0))
	made.side = float(part.get("side", 0.0))
	made.ahead = float(part.get("ahead", 0.0))
	for layer: Variant in part.get("feet_layers", []):
		made.feet.append(int(layer))
	made.below = float(part.get("below", 8.0))
	made.seconds = float(part.get("seconds", 2.0))
	return made


## Start `part` for `caster` (an actor) at Feel's clock `now`, from where its anchor is `at`, going
## `way` until it has moved: of the spell tagged `tag`, in `ramp`, with the cards of `look` in the
## colour `core`. Nothing for no actor or no anchor.
func start(part: Part, caster: int, tag: int, ramp: int, look: int, core: Color, at: Vector2, way: Vector2, now: float) -> void:
	if caster < 0 or not at.is_finite():
		return
	var slot: int = -1
	for n in count:
		if _caster[n] == caster and _part[n] == part:
			slot = n
			break
	if slot < 0 and count < MOST:
		slot = count
		count += 1
	if slot < 0:
		slot = 0
		for n in count:
			if _until[n] < _until[slot]:
				slot = n
	_part[slot] = part
	_caster[slot] = caster
	_tag[slot] = tag
	_until[slot] = now + part.seconds
	_ramp[slot] = ramp
	_look[slot] = look
	_core[slot] = Color(core.r, core.g, core.b, 1.0)
	_last[slot] = at
	_way[slot] = way.normalized() if way.length_squared() > 0.0001 else Vector2.RIGHT


## The carrier of the spell tagged `tag` that `caster` showed has ended: its streams end.
func end(caster: int, tag: int) -> void:
	var n: int = 0
	while n < count:
		if _caster[n] == caster and _tag[n] == tag:
			_remove(n)
			continue
		n += 1


## Whether a stream of `caster` is under way (for tests).
func is_streaming(caster: int) -> bool:
	for n in count:
		if _caster[n] == caster:
			return true
	return false


## Every stream ends (a room change, a new run).
func clear() -> void:
	for n in count:
		_part[n] = null
	count = 0


## Once a frame, at Feel's clock `now`: each stream follows its caster's anchor (`projectiles`)
## and gives off its motes for the time since the last frame into `births`, while `on` (motes are
## thrown); one whose time is up or whose caster has no anchor ends.
func step(now: float, projectiles: ProjectilesScript, births: BirthsScript, on: bool) -> void:
	var seconds: float = clampf(now - _clock, 0.0, LONGEST_FRAME) if _clock >= 0.0 else 0.0
	_clock = now
	var n: int = 0
	while n < count:
		var at: Vector2 = projectiles.get_anchor(_caster[n]) if projectiles != null else Vector2.INF
		if now >= _until[n] or not at.is_finite():
			_remove(n)
			continue
		var moved: Vector2 = at - _last[n]
		if moved.length_squared() > MOVED * MOVED:
			_way[n] = moved.normalized()
			_last[n] = at
		if on and seconds > 0.0:
			_give_off(n, at, seconds, births)
		n += 1


## Stream `n`'s motes for `seconds`, from its caster at `at`.
func _give_off(n: int, at: Vector2, seconds: float, births: BirthsScript) -> void:
	var part: Part = _part[n]
	var back: Vector2 = -_way[n]
	var side: Vector2 = Vector2(-back.y, back.x)
	var look: int = _look[n]
	for i in births.roll(part.rate * seconds):
		if part.kind == KIND_PATH:
			var from: Vector2 = at + side * (births.dice() - 0.5) * part.side - back * (births.dice() * 2.0 - 1.0) * part.ahead
			if not births.add(from, back, ProjectilesScript.SPARK_STREAK, _ramp[n], 0, Color.WHITE, _tag[n]):
				return
			continue
		var layer: int = births.emitting_layer(look)
		if layer == 0 or births.dice() >= ProjectilesScript.SPARK_RATES[layer]:
			continue
		var from: Vector2 = at + side * (births.dice() - 0.5) * part.side - back * (births.dice() * 2.0 - 1.0) * part.ahead
		if part.feet.has(layer):
			from = at + Vector2((births.dice() - 0.5) * FEET_ACROSS, part.below + (births.dice() - 0.5) * FEET_DOWN)
		if not births.add(from, back, layer, _ramp[n], look, _core[n], _tag[n]):
			return


func _remove(n: int) -> void:
	count -= 1
	_part[n] = _part[count]
	_caster[n] = _caster[count]
	_tag[n] = _tag[count]
	_until[n] = _until[count]
	_ramp[n] = _ramp[count]
	_look[n] = _look[count]
	_core[n] = _core[count]
	_last[n] = _last[count]
	_way[n] = _way[count]
	_part[count] = null
