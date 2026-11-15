class_name ScaleCurve
extends Resource
## A factor that grows (or shrinks) over a span (run generation RG5, docs/milestones/run-generation.md,
## "Scaling"), as a card's speed over life does: `start` at the span's start, `end` at its end, and
## `easing` how it goes from one to the other (1 evenly, above 1 most of the change early, below 1
## late; the same shape as `ModifierBase.speed_ease`). A sub-resource of `RunScaling`: the run's
## scale per depth (from its first row to its deepest) and per extra player (from one player to four).
## Read-only content, shared like a card; `at` is a pure function, through `DMath`, so it is the same
## to the bit on every machine.

## The factor at the span's start (above 0).
@export_range(0.01, 100.0, 0.01) var start: float = 1.0
## The factor at the span's end (above 0).
@export_range(0.01, 100.0, 0.01) var end: float = 1.0
## How it goes from `start` to `end` (above 0): 1 evenly, above 1 most of the change early, below 1 late.
@export_range(0.1, 8.0, 0.01) var easing: float = 1.0


## A curve from `from` to `to` by `how`.
static func make(from: float, to: float, how: float = 1.0) -> ScaleCurve:
	var curve := ScaleCurve.new()
	curve.start = from
	curve.end = to
	curve.easing = how
	return curve


## The factor at `t` of the span (0 its start, 1 its end; clamped to them):
## `start + (end - start) x (1 - (1 - t) ^ easing)`.
func at(t: float) -> float:
	var along: float = clampf(t, 0.0, 1.0)
	return start + (end - start) * (1.0 - DMath.pow(1.0 - along, easing))


## What is wrong with the curve, one line each, named `what` (empty when every number is above 0
## and finite).
func problems(what: String) -> PackedStringArray:
	var found := PackedStringArray()
	for pair: Array in [["start", start], ["end", end], ["easing", easing]]:
		var value: float = pair[1]
		if not (value > 0.0) or not is_finite(value):
			found.append("%s: %s %s; above 0." % [what, pair[0], value])
	return found
