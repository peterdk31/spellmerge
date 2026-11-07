extends RefCounted
## How many hit looks each body has shown this frame, per staff that hit it (shot scale H3; owner,
## 2026-11-07): a body shows the look of at most PER_BODY hits of one staff in a frame (its spray,
## impact, sparks, squash and sound), and the hits after that show nothing, so the frame's flashes
## and motes are spread over the bodies being hit instead of spent on the one in front of the
## casters. Each staff counts apart, so a lone cast hitting a body inside another staff's storm still
## shows (the owner, 2026-11-05). Feel asks `take` once a hit and calls `new_frame` at its step.
##
## A table of (body, staff group) keys reused every frame: a slot with an older frame's stamp is
## empty, so nothing is cleared, and it grows only when one frame fills half of it.

const PER_BODY: int = 3
const START_SIZE: int = 1024

var _bodies: PackedInt64Array = PackedInt64Array()
var _groups: PackedInt32Array = PackedInt32Array()
var _stamps: PackedInt32Array = PackedInt32Array()
var _counts: PackedInt32Array = PackedInt32Array()
var _frame: int = 1
var _used: int = 0


func _init() -> void:
	_resize(START_SIZE)


## A new frame: every body may show its looks again.
func new_frame() -> void:
	_frame += 1
	_used = 0


## Whether a hit of the staff `group` (`Spectacle.hit_group`) on the body with the instance id
## `body` shows its look; counts it when it does.
func take(body: int, group: int) -> bool:
	var at: int = _slot_of(body, group)
	if _stamps[at] != _frame:
		if (_used + 1) * 2 > _stamps.size():
			_grow()
			at = _slot_of(body, group)
		_stamps[at] = _frame
		_bodies[at] = body
		_groups[at] = group
		_counts[at] = 0
		_used += 1
	if _counts[at] >= PER_BODY:
		return false
	_counts[at] += 1
	return true


## The slot of (body, group) this frame: its own, or the empty one where it would go.
func _slot_of(body: int, group: int) -> int:
	var mask: int = _stamps.size() - 1
	var at: int = hash(body * 8191 + group) & mask
	while _stamps[at] == _frame and (_bodies[at] != body or _groups[at] != group):
		at = (at + 1) & mask
	return at


## Twice the room, this frame's entries kept.
func _grow() -> void:
	var bodies: PackedInt64Array = _bodies
	var groups: PackedInt32Array = _groups
	var stamps: PackedInt32Array = _stamps
	var counts: PackedInt32Array = _counts
	_resize(stamps.size() * 2)
	for i in stamps.size():
		if stamps[i] == _frame:
			var at: int = _slot_of(bodies[i], groups[i])
			_stamps[at] = _frame
			_bodies[at] = bodies[i]
			_groups[at] = groups[i]
			_counts[at] = counts[i]


func _resize(size: int) -> void:
	_bodies = PackedInt64Array()
	_groups = PackedInt32Array()
	_stamps = PackedInt32Array()
	_counts = PackedInt32Array()
	_bodies.resize(size)
	_groups.resize(size)
	_stamps.resize(size)
	_counts.resize(size)
