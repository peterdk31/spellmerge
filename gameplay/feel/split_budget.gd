extends RefCounted
## The split screen's frame-time budget (connected biomes CB6; decision 31, the owner's targets of
## 2026-11-19: a frame in 16.7 ms on the desktop and in 33 ms on the web build, with four views; to be
## tuned from a GPU run). While the screen is split and the frames run over the target, it steps up
## a ladder of CB1's fallbacks, one rung at a time; back under it with room to spare, it steps down.
## View only, on real time: it reads the drawn frames' times, nothing in the simulation.
##
## The rungs, in CB1's order of what saves most for least look (docs/milestones/connected-biomes.md,
## "CB1's numbers"): a cheaper light a view (the light buffers past the first view's twice as small
## again each way), then half the motes, then a quarter. Light off and a view's own room's shots only
## are not rungs yet: they wait for a GPU run to say they are needed.
##
## A rung up after the frames' average has been over the target for UP_SECONDS; a rung down after it
## has been under DOWN_SHARE of the target for DOWN_SECONDS; nothing changes with one view (the one
## picture costs what it did before the split). `switched_off` keeps it on rung 0 (the benchmarks).

const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")

## The targets (seconds a frame).
const DESKTOP_TARGET: float = 1.0 / 60.0
const WEB_TARGET: float = 0.033
## How fast the average follows the frames (per second), and how long over (or well under) before a rung changes.
const AVERAGE_SPEED: float = 4.0
const UP_SECONDS: float = 1.0
const DOWN_SECONDS: float = 3.0
const DOWN_SHARE: float = 0.75
## The rungs: the light buffers' downscale past the first view, and the share of motes thrown.
const RUNG_DOWNSCALE: PackedInt32Array = [SpellLightScript.DOWNSCALE, SpellLightScript.DOWNSCALE * 2, SpellLightScript.DOWNSCALE * 2, SpellLightScript.DOWNSCALE * 2]
const RUNG_MOTES: PackedFloat32Array = [1.0, 1.0, 0.5, 0.25]

## The rung now (0: none), the target (seconds), the frames' average (seconds). Read only.
var rung: int = 0
var target: float = DESKTOP_TARGET
var average: float = 0.0
## True keeps it on rung 0.
var switched_off: bool = false

var _over: float = 0.0
var _under: float = 0.0


func _init(web: bool = OS.has_feature("web")) -> void:
	target = WEB_TARGET if web else DESKTOP_TARGET


## A drawn frame that took `delta` real seconds, with `views` views on the screen.
func step(delta: float, views: int) -> void:
	if delta <= 0.0:
		return
	average = delta if average <= 0.0 else lerpf(average, delta, 1.0 - exp(-AVERAGE_SPEED * delta))
	if switched_off or views < 2:
		_over = 0.0
		_under = 0.0
		if switched_off:
			rung = 0
		return
	if average > target:
		_over += delta
		_under = 0.0
		if _over >= UP_SECONDS and rung < RUNG_MOTES.size() - 1:
			rung += 1
			_over = 0.0
	elif average < target * DOWN_SHARE:
		_under += delta
		_over = 0.0
		if _under >= DOWN_SECONDS and rung > 0:
			rung -= 1
			_under = 0.0
	else:
		_over = 0.0
		_under = 0.0


## The light buffers' downscale past the first view on this rung.
func light_downscale() -> int:
	return RUNG_DOWNSCALE[rung]


## The share of motes thrown on this rung.
func mote_share() -> float:
	return RUNG_MOTES[rung]
