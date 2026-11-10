class_name NetChecks
extends RefCounted
## The hash checks of an online run (netcode spike S2, docs/milestones/netcode-spike.md): both
## machines hash the game's state the same way at the same ticks, the client sends its hashes and
## the host compares them with its own.
##
## A check covers `every` ticks (a second). Hashing the whole state in one tick costs tens of
## milliseconds in a crowd, so each tick hashes one part of it (`SimHash.slice`: part
## `tick % every`; each area is in exactly one part), after that tick has stepped, and the check
## is whole when its last tick is in. An area's hash is therefore of the tick its part came up,
## the same tick on both machines; a state that parts is seen within one check of the tick it
## parted, by the area it parted in or one it spread to.
##
##     var window: Dictionary[String, int] = checks.add(tick, tick_areas)   # after every tick
##     if not window.is_empty(): ...   # a whole check, of the `every` ticks up to `tick`

## The ticks a check covers.
const EVERY: int = 60
const _NONE: Dictionary[String, int] = {}

var every: int = EVERY
var _window: Dictionary[String, int] = {}


func _init(ticks: int = EVERY) -> void:
	every = maxi(ticks, 1)


## Tick `tick` has stepped: hash its part of `named` (the game's areas by name,
## `Tick.state_areas`). Returns the whole check (each area's hash, by name) when `tick` is a
## check's last, else an empty one. Call it after every tick, in order.
func add(tick: int, named: Dictionary) -> Dictionary[String, int]:
	var part: int = posmod(tick, every)
	if part == 0:
		_window = {}
	_window.merge(SimHash.areas(SimHash.slice(named, part, every)), true)
	return _window if part == every - 1 else _NONE


## The areas that differ between two checks of one tick: another hash, or in one only. In `mine`'s
## order, then those only in `theirs`.
static func parting(mine: Dictionary[String, int], theirs: Dictionary[String, int]) -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in mine:
		if not theirs.has(name) or theirs[name] != mine[name]:
			out.append(name)
	for name: String in theirs:
		if not mine.has(name):
			out.append(name)
	return out
