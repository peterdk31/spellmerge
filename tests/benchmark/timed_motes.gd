extends "res://gameplay/feel/mote.gd"
## The mote pool, timing its own calls (P1c, docs/milestones/spell-spectacle.md): the sandbox
## storm hands Feel one (`Feel.use_motes`) to measure what motes cost the CPU in a fight. `usec`
## sums the time of every call from outside (a shed, a throw, a burst, the trails' give_off, a step); a call made inside
## another is in its caller's time. Not used by the game.

## Microseconds spent in the pool's calls since it was made, and those calls (each adds the
## timer's own cost, about 0.13 us: mote_write.gd measures it).
var usec: int = 0
var calls: int = 0
var _depth: int = 0


func shed(at: Vector2, dir: Vector2, core: Color, ramp: int, look: int, scale: float = 1.0) -> void:
	var start: int = _enter()
	super(at, dir, core, ramp, look, scale)
	_leave(start)


func throw(k: int, at: Vector2, dir: Vector2, source: int, core: Color, scale: float = 1.0) -> void:
	var start: int = _enter()
	super(k, at, dir, source, core, scale)
	_leave(start)


func throw_part(k: int, at: Vector2, dir: Vector2, source: int, core: Color, count: int, reach: float, spread: float, up: float, ring: bool, often: bool = false, line: Vector2 = Vector2.ZERO, life: float = 1.0, look: int = 0) -> void:
	var start: int = _enter()
	super(k, at, dir, source, core, count, reach, spread, up, ring, often, line, life, look)
	_leave(start)


func burst(k: int, at: Vector2, dir: Vector2, count: int, speed: Vector2, spread: float, up: Vector2, life: Vector2, source: int, core: Color, height: float = 0.0, line: Vector2 = Vector2.ZERO, turns: int = 0) -> void:
	var start: int = _enter()
	super(k, at, dir, count, speed, spread, up, life, source, core, height, line, turns)
	_leave(start)


func give_off(births: PackedFloat32Array, count: int) -> void:
	var start: int = _enter()
	super(births, count)
	_leave(start)


func step(now: float) -> void:
	var start: int = _enter()
	super(now)
	_leave(start)


func _enter() -> int:
	_depth += 1
	return Time.get_ticks_usec() if _depth == 1 else 0


func _leave(start: int) -> void:
	_depth -= 1
	if _depth == 0:
		usec += Time.get_ticks_usec() - start
		calls += 1
