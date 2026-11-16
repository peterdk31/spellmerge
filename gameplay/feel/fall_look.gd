class_name FallLook
extends RefCounted
## The look of a fall (hub rework HR-H2, docs/milestones/hub-rework.md, "Holes" 4): a body that falls
## into a hole shrinks toward its feet and darkens into the void, giving off motes, drawn from its
## state (`Actor.fall_share`), never only from `body_fell`, so a machine that joins mid-fall draws it
## and a snapshot restored mid-fall shows it where it is. Feel steps it once a frame (`step`) over the
## actor table's open bodies; a body whose fall is over (or that is gone) gets its own scale and
## colour back.
##
## It writes the body's `scale` (the drawn size of all its parts: nothing in the simulation reads
## it, its size is `Actor.size`) and `modulate` (drawing only), as Feel's hit reaction writes a
## sprite's scale. View only.
##
## Nothing here allocates while bodies fall (its scratch of ids is made once; the dictionary of the
## bodies it drew grows only when a body first falls).

const ActorsScript := preload("res://core/actors/actors.gd")

const VIEW_ONLY: bool = true

## How much of its size a body has lost at the fall's end (it is drawn this much smaller).
const SHRINK: float = 0.85
## How dark it is at the end (its colour toward VOID_TINT), and how faded.
const DARKEN: float = 0.75
const FADE: float = 0.8
## The void's colour a falling body darkens toward, and its motes' colour.
const VOID_TINT: Color = Color(0.05, 0.06, 0.16, 1.0)
const MOTE_COLOUR: Color = Color(0.45, 0.5, 0.95, 1.0)
## Motes a second off a falling body.
const MOTES_PER_SECOND: float = 30.0

## The open ids, scratch.
var _ids: PackedInt32Array = PackedInt32Array()
## The bodies drawn falling (by instance id) and the colour each had before.
var _drawn: Dictionary[int, Color] = {}
## How many motes are owed, carried between frames.
var _owed: float = 0.0


func _init() -> void:
	_ids.resize(ActorsScript.ACTORS)


## The scale a body of `size` is drawn at `share` of the way through its fall.
static func scale_at(size: float, share: float) -> Vector2:
	return Vector2.ONE * size * (1.0 - SHRINK * clampf(share, 0.0, 1.0))


## The colour a body whose own is `own` is drawn at `share` of the way through its fall.
static func tint_at(own: Color, share: float) -> Color:
	var t: float = clampf(share, 0.0, 1.0)
	var tint: Color = own.lerp(VOID_TINT, DARKEN * t)
	tint.a = own.a * (1.0 - FADE * t)
	return tint


## Draw every falling body of `table` as far through its fall as it is, and put back the bodies done.
## `throw` (optional: at, count) gives off `count` motes at `at` for the frame's `real_delta`.
func step(table: ActorsScript, real_delta: float, throw: Callable = Callable()) -> void:
	var falling: int = 0
	if table != null:
		var count: int = table.open_ids(_ids)
		for n in count:
			var body := table.node_of(_ids[n]) as Actor
			if body == null or not body.is_falling():
				continue
			falling += 1
			var key: int = body.get_instance_id()
			if not _drawn.has(key):
				_drawn[key] = body.modulate
			var share: float = body.fall_share()
			body.scale = scale_at(body.size, share)
			body.modulate = tint_at(_drawn[key], share)
			if throw.is_valid() and real_delta > 0.0:
				_owed += MOTES_PER_SECOND * real_delta
				var whole: int = floori(_owed)
				if whole > 0:
					_owed -= float(whole)
					throw.call(body.global_position + body.body_offset * (1.0 - share), whole)
	if _drawn.size() > falling:
		_put_back()


## Every body drawn falling that falls no more (or went) has its own scale and colour back.
func _put_back() -> void:
	for key: int in _drawn.keys():
		var body := instance_from_id(key) as Actor
		if body != null and body.is_falling():
			continue
		if body != null:
			body.scale = Vector2.ONE * body.size
			body.modulate = _drawn[key]
		_drawn.erase(key)


## How many bodies it draws falling now (tests).
func drawn() -> int:
	return _drawn.size()
