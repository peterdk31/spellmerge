extends RefCounted
## Mote jets: a cue's `motes` parts with `for` (`CueBase`; the owner, 2026-11-16: "I really like the
## jet animation"). A jet throws its part's `count` spread evenly over its `for` seconds instead of
## at once, from where its cue played along its way, each throw with the part's other keys: a
## stream poured out of a staff. The spectacle owns one (`Spectacle.jets`), starts one where it
## plays such a part and steps it once a frame; each frame's share is thrown by the spectacle's own
## motes player (`throw`, handed in), so a jet's motes are a motes part's in every way.
##
## Nothing here changes a fight: it keeps nothing the simulation reads, and runs on Feel's clock.
## Allocation-free while it runs: each of its MOST slots keeps a part and a cue of its own, made
## once and refilled (the cue a part is played with is refilled for the next cue at once).

const CueContextScript := preload("res://gameplay/feel/cue_context.gd")
const MotesPartScript := preload("res://gameplay/feel/motes_part.gd")

## The most jets at once; one more takes the place of the one that would end soonest.
const MOST: int = 32
## The longest frame a jet throws for (s): after a stall it throws no more than this much of it.
const LONGEST_FRAME: float = 0.1

## The jets under way: the first `count` of each list.
var count: int = 0
## How each slot throws: its part's copy (its count set to each frame's share) and its cue.
var _parts: Array[MotesPartScript] = []
var _cues: Array[CueContextScript] = []
## Each jet's start, its seconds, its whole count and how many it has thrown.
var _from: PackedFloat64Array = PackedFloat64Array()
var _lasts: PackedFloat32Array = PackedFloat32Array()
var _whole: PackedInt32Array = PackedInt32Array()
var _thrown: PackedInt32Array = PackedInt32Array()
## What throws a part with a cue (the spectacle's motes player).
var _throw: Callable
## Feel's clock at the last step.
var _clock: float = -1.0


## `throw(part, cue)` throws a motes part's `count` now (the spectacle's motes player).
func _init(throw: Callable) -> void:
	_throw = throw
	for n in MOST:
		_parts.append(MotesPartScript.new())
		_cues.append(CueContextScript.new())
	_from.resize(MOST)
	_lasts.resize(MOST)
	_whole.resize(MOST)
	_thrown.resize(MOST)


## Start a jet of `part` (a prepared motes part with `lasts` over 0 and a count) played with `cue`
## at Feel's clock `now`: its count thrown over its `lasts` seconds. Its first share is thrown at the
## next step.
func start(part: MotesPartScript, cue: CueContextScript, now: float) -> void:
	var whole: int = maxi(roundi(float(part.count) * cue.count_times()), 1)
	var lasts: float = part.lasts
	if lasts <= 0.0:
		return
	var slot: int = count
	if count < MOST:
		count += 1
	else:
		slot = 0
		for n in count:
			if _from[n] + _lasts[n] < _from[slot] + _lasts[slot]:
				slot = n
	var own: MotesPartScript = _parts[slot]
	own.copy_from(part)
	own.turn = 0
	# Its power is in its whole count and in how far it throws (a cue's power scales both), so
	# each frame's share is thrown at power 1.
	own.radius *= cue.power
	if own.reach >= 0.0:
		own.reach *= cue.power
	_cues[slot].copy_from(cue)
	_cues[slot].power = 1.0
	_cues[slot].grow = 1.0
	_from[slot] = now
	_lasts[slot] = lasts
	_whole[slot] = whole
	_thrown[slot] = 0


## Whether a jet is under way (for tests).
func is_pouring() -> bool:
	return count > 0


## Every jet ends (a room change).
func clear() -> void:
	count = 0


## Once a frame, at Feel's clock `now`: each jet throws its share of its count for the time since
## it started (no more than LONGEST_FRAME of it since the last step); one whose time is up ends.
func step(now: float) -> void:
	var stalled: float = now - _clock - LONGEST_FRAME if _clock >= 0.0 else 0.0
	_clock = now
	var n: int = 0
	while n < count:
		if stalled > 0.0:
			# A stall: the jet takes up from here, as if no time had passed.
			_from[n] += stalled
		var done: float = clampf((now - _from[n]) / _lasts[n], 0.0, 1.0)
		var due: int = roundi(float(_whole[n]) * done) - _thrown[n]
		if due > 0:
			_thrown[n] += due
			var part: MotesPartScript = _parts[n]
			part.count = due
			_throw.call(part, _cues[n])
		if done >= 1.0:
			_remove(n)
			continue
		n += 1


func _remove(n: int) -> void:
	count -= 1
	if n == count:
		return
	# The slots' own part and cue swap with the last's, so each slot keeps one of its own.
	var part: MotesPartScript = _parts[n]
	_parts[n] = _parts[count]
	_parts[count] = part
	var cue: CueContextScript = _cues[n]
	_cues[n] = _cues[count]
	_cues[count] = cue
	_from[n] = _from[count]
	_lasts[n] = _lasts[count]
	_whole[n] = _whole[count]
	_thrown[n] = _thrown[count]
