extends RefCounted
## The places a mote leaves from within an oval, shared by the motes of the world's sources
## (`source_motes.gd`, `MoteSource`) and of still cards (`still_motes.gd`, `StillMoteSource`). View
## only: each takes the caller's own dice and uses the engine's trig, never the simulation's.

## A point anywhere in the oval of half-axes `half` round its middle, at most `inside` of the way to
## its rim (a pool's surface; `rng` the caller's own dice).
static func in_oval(rng: RandomNumberGenerator, half: Vector2, inside: float = 1.0) -> Vector2:
	var b: float = rng.randf() * TAU
	return Vector2(cos(b), sin(b)) * half * sqrt(rng.randf()) * inside


## A point on the rim of the oval of half-axes `half` round its middle, in whole pixels; with
## `spacing`, only at that many pixels apart round it (a rune's ring).
static func on_oval(rng: RandomNumberGenerator, half: Vector2, spacing: float = 0.0) -> Vector2:
	var a: float = rng.randf() * TAU
	if spacing > 0.0:
		var steps: float = maxf(roundf(TAU * maxf(half.x, half.y) / spacing), 1.0)
		a = roundf(a / TAU * steps) / steps * TAU
	return (Vector2(cos(a), sin(a)) * half).round()


## `along` (a place on a line `w` from the world's origin along it) put on the world's grid of
## `spacing` pixels, so pieces of a row and sources side by side line up (0: as it is).
static func on_grid(along: float, w: float, spacing: float) -> float:
	if spacing <= 0.0:
		return along
	return roundf((w + along) / spacing) * spacing - w
