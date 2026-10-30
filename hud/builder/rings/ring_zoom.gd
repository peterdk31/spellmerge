extends "res://hud/builder/rings/ring_picker.gd"
## The zoom ring (owner, 2026-10-30): every card on one ring, as the plain ring, but the stick
## held still at full tilt locks a magnified fan around where it points. Then turning the stick
## moves through the fan at `GAIN` of the speed, so each card is 1 / GAIN times wider to aim at,
## and the fan is drawn spread so the card under the stick is the one picked. Past the fan's
## edge the fan slides on under the stick; a fast sweep or easing off the stick unlocks it (the
## plain ring again), and letting go drops the pick. P1's mouse picks on the plain ring: it is
## precise already. The numbers are first guesses, to tune by playing.

const RadialScript := preload("res://hud/builder/radial_builder.gd")

## Locks when the stick is pushed this far (0 to 1) and turns slower than STILL_SPEED (radians a
## second) for LOCK_TIME seconds.
const LOCK_TILT: float = 0.85
const STILL_SPEED: float = 1.5
const LOCK_TIME: float = 0.12
## Unlocks when the stick turns faster than UNLOCK_SPEED, or eases under UNLOCK_TILT.
const UNLOCK_SPEED: float = 8.0
const UNLOCK_TILT: float = 0.5
## Ring angle per stick angle while locked.
const GAIN: float = 0.25
## Half the fan as drawn (radians); the stick past it slides the fan SLIDE_SPEED cards a second.
const FAN_HALF: float = PI * 0.45
const SLIDE_SPEED: float = 8.0
## The size of a card outside the fan.
const MARK_SIZE: float = 3.0

var _locked: bool = false
## The stick's angle when it locked, and the ring angle drawn there.
var _anchor: float = 0.0
var _base: float = 0.0
var _still: float = 0.0
## The stick's angle at the last step (NAN after a reset or a let go).
var _last: float = NAN


func reset() -> void:
	_locked = false
	_still = 0.0
	_last = NAN


## Whether the fan is locked (for tests).
func is_locked() -> bool:
	return _locked


## The ring angle the locked fan has under the stick's direction `angle` (for tests).
func ring_angle_at(angle: float) -> float:
	return _base + clampf(angle_difference(_anchor, angle), -FAN_HALF, FAN_HALF) * GAIN


func pick(radial: Control, delta: float) -> int:
	var r: RadialScript = radial as RadialScript
	var tilt: Vector2 = r.stick_tilt()
	if tilt == Vector2.ZERO:
		reset()
		var mouse: Vector2 = r.mouse_reach()
		return r.pick_on_ring(mouse if mouse.length() * RadialScript.RING_RADIUS > RadialScript.MOUSE_INNER else Vector2.ZERO)
	var angle: float = RadialScript.angle_of(tilt)
	var speed: float = 0.0 if is_nan(_last) or delta <= 0.0 else absf(angle_difference(_last, angle)) / delta
	_last = angle
	if _locked and (speed > UNLOCK_SPEED or tilt.length() < UNLOCK_TILT):
		_locked = false
		_still = 0.0
	if not _locked:
		_still = _still + delta if tilt.length() >= LOCK_TILT and speed < STILL_SPEED else 0.0
		if _still < LOCK_TIME:
			return r.pick_on_ring(tilt)
		_locked = true
		_anchor = angle
		_base = angle
	var off: float = angle_difference(_anchor, angle)
	if absf(off) > FAN_HALF:
		_base += signf(off) * SLIDE_SPEED * _card_width(r) * delta
	return r.pick_among(r._ring_entry, r._ring_angle, r._ring_width, ring_angle_at(angle))


func is_animating() -> bool:
	return _locked


## The ring angle one card takes on the plain ring.
func _card_width(r: RadialScript) -> float:
	return r._card_room() / RadialScript.RING_RADIUS


## Where ring angle `angle` is drawn: spread 1 / GAIN times inside the fan, squeezed outside it.
func _drawn(angle: float) -> float:
	var d: float = angle_difference(_base, angle)
	var half: float = FAN_HALF * GAIN
	if absf(d) <= half:
		return _anchor + d / GAIN
	return _anchor + signf(d) * (FAN_HALF + (absf(d) - half) * (PI - FAN_HALF) / (PI - half))


func draw(radial: Control) -> bool:
	if not _locked:
		return false
	var r: RadialScript = radial as RadialScript
	var radius: float = RadialScript.RING_RADIUS
	r.draw_arc(r._center, radius, 0.0, TAU, 64, RadialScript.LINE, 1.0)
	# The fan, outside the ring.
	r.draw_arc(r._center, radius + RadialScript.ARC_OUT, _anchor - FAN_HALF - PI * 0.5, _anchor + FAN_HALF - PI * 0.5, 32, Color(RadialScript.GOLD, 0.6), 2.0)
	var aim: Vector2 = r._drawn_aim
	if aim != Vector2.ZERO:
		r.draw_line(r._center + aim * (RadialScript.HUB_RADIUS + 2.0), r._center + aim * (radius - 11.0), Color(RadialScript.GOLD, 0.55), 1.0)
	var half: float = FAN_HALF * GAIN
	var picked_at: float = NAN
	for at in r._ring_entry.size():
		var entry: int = r._ring_entry[at]
		if entry == NONE:
			continue
		var angle: float = _drawn(r._ring_angle[at])
		if entry == r._pointed:
			picked_at = angle
		elif absf(angle_difference(_base, r._ring_angle[at])) <= half:
			var size: float = clampf(floorf(r._ring_width[at] / GAIN * radius) - 2.0, MARK_SIZE, RadialScript.TILE_MAX)
			r._draw_ring_card(entry, r._tile_center(angle, radius), size, false)
		else:
			var middle: Vector2 = r._tile_center(angle, radius)
			r.draw_rect(Rect2((middle - Vector2(MARK_SIZE, MARK_SIZE) * 0.5).round(), Vector2(MARK_SIZE, MARK_SIZE)), RadialScript.KIND_COLORS[r._entries[entry]["kind"]])
	if not is_nan(picked_at):
		r._draw_ring_card(r._pointed, r._tile_center(picked_at, radius + 4.0), RadialScript.TILE_PICKED, true)
	return true
