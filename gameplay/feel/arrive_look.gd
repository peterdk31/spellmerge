class_name ArriveLook
extends Node2D
## The look of an enemy arriving (enemy arrivals EA2, docs/milestones/enemy-arrivals.md, "The look"):
## first a mark grows on the floor where the body will stand, then the body rises out of it. It is
## drawn from the body's state alone (`Actor.arrive_share`), never from a moment it was told of, so a
## machine that joins mid-arrival or a snapshot restored mid-arrival shows it where it is. Feel steps
## it once a frame (`step`) over the actor table's open bodies, as it does `FallLook`.
##
## - **0 to MARK_END, the mark:** a disc on the floor at the body's feet, as wide as its footprint, in
##   the room's floor colours (`RoomBase.floor_colors`: its shadow, darkened, with its light shade
##   as a rim; `use_room`), growing from a dot in MARK_FRAMES frames. The body is not drawn yet.
## - **MARK_END to 1, the rise:** the body comes up out of the mark, drawn shifted down by whole pixels
##   from its full height (`body_height`) to 0 and cut off at its feet's line, so what is still under
##   the floor is not drawn. Its own sprite and pose all the way: no fade, no blur, no scale. As the
##   rise starts the cue `enemy_arrive` plays at its feet (dust off the mark, a soft sound): its sound
##   at most every SOUND_EVERY seconds, so a group does not stack it (the cue is played unweighted
##   in between: its dust only). From CLOSE_FROM the mark closes in CLOSE_FRAMES frames as the feet
##   land, down to a dot, so the rise ends where standing begins (docs/STYLE.md, "Smooth").
##
## The cut (checked against the world's y-sort and the light pass before it was built, EA2): the
## body's root is made a clip parent (`CanvasItem.clip_children`) whose own canvas item draws one
## rect, above the feet's line, as the mask, and its canvas item is drawn shifted down by the rise
## (`RenderingServer.canvas_item_set_transform`, re-set every frame). That is one cut for any body,
## layered (`BodyPart`) or not, with no work per part; the body keeps its place in the y-sort, and
## the light pass, drawn over the world, lights it as any body. Nothing in the simulation reads
## either: its position and its parts are untouched. A body whose arrival is over (or that is gone)
## gets its own transform back and is no clip parent any more.
##
## View only. Nothing here allocates while bodies arrive: its scratch of ids and marks is made once,
## and the dictionary of the bodies it drew grows only when a body first arrives.

const ActorsScript := preload("res://core/actors/actors.gd")

const VIEW_ONLY: bool = true

## Where the mark stage ends and the rise begins, as a share of the arrival.
const MARK_END: float = 0.4
## The frames the mark grows in, from a dot to the footprint's width.
const MARK_FRAMES: int = 4
## Where the mark starts to close (share of the arrival), and the frames it closes in.
const CLOSE_FROM: float = 0.85
const CLOSE_FRAMES: int = 3
## The least height a body rises by, in pixels (so a rise is never fewer than this many frames).
const MIN_HEIGHT: float = 8.0
## Pixels added over a body's measured height, so nothing of it shows above the floor before it rises.
const HEIGHT_MARGIN: float = 2.0
## How much darker than the floor's shadow the mark's inside is: a hole, read at a glance.
const MARK_DARKEN: float = 0.35
## The mask's reach each way from the feet and up (a body's own pixels, at its size 1).
const MASK_HALF_WIDTH: float = 96.0
const MASK_TALL: float = 192.0
## The cue played as a body starts to rise, and the least seconds between two of its sounds.
const CUE: StringName = &"enemy_arrive"
const SOUND_EVERY: float = 0.1
## The mark's colours with no room known (light, base, shadow).
const NO_FLOOR: PackedColorArray = [Color(0.55, 0.55, 0.6), Color(0.35, 0.35, 0.4), Color(0.2, 0.2, 0.24)]

## Plays the cue: (at: Vector2, weighted: bool). Set by Feel; none plays nothing.
var play_cue: Callable = Callable()

## The open ids, scratch.
var _ids: PackedInt32Array = PackedInt32Array()
## The bodies drawn arriving (by instance id), and whether the cue of each one's rise was played.
var _drawn: Dictionary[int, bool] = {}
## This frame's marks: where (whole pixels) and how wide; `_marks` of them are in use.
var _mark_at: PackedVector2Array = PackedVector2Array()
var _mark_radius: PackedInt32Array = PackedInt32Array()
var _marks: int = 0
## How many marks the last draw drew (to clear them once when there are none).
var _drawn_marks: int = 0
## The mark's fill and rim.
var _fill: Color = NO_FLOOR[2].darkened(MARK_DARKEN)
var _rim: Color = NO_FLOOR[0]
## Real seconds since it started, and when the cue last sounded.
var _clock: float = 0.0
var _sounded_at: float = -INF


func _init() -> void:
	_ids.resize(ActorsScript.ACTORS)
	_mark_at.resize(ActorsScript.ACTORS)
	_mark_radius.resize(ActorsScript.ACTORS)


func _ready() -> void:
	top_level = true


## The room played in now (null for none): the mark takes its floor's colours.
func use_room(room: RoomBase) -> void:
	var colours: PackedColorArray = room.floor_colors() if room != null else PackedColorArray()
	if colours.is_empty():
		colours = NO_FLOOR
	_rim = colours[0]
	_fill = colours[mini(2, colours.size() - 1)].darkened(MARK_DARKEN)


## How far below its place a body `height` pixels tall is drawn at `share` of its arrival, in whole
## pixels: all of it under the floor through the mark, then up to 0 as it lands.
static func rise_shift(height: float, share: float) -> float:
	if share < MARK_END:
		return height
	var t: float = clampf((share - MARK_END) / (1.0 - MARK_END), 0.0, 1.0)
	return roundf(height * (1.0 - t))


## How wide the mark under a body whose footprint is `radius` pixels is at `share` of its arrival, in
## whole pixels (0: none): growing from a dot in MARK_FRAMES frames, held, then closing in
## CLOSE_FRAMES frames down to a dot.
static func mark_radius(radius: float, share: float) -> int:
	if share >= 1.0 or share < 0.0:
		return 0
	var full: int = maxi(roundi(radius), 2)
	if share < MARK_END:
		var k: int = mini(floori(share / MARK_END * MARK_FRAMES), MARK_FRAMES - 1)
		return roundi(lerpf(1.0, float(full), float(k) / float(MARK_FRAMES - 1)))
	if share < CLOSE_FROM:
		return full
	var j: int = mini(floori((share - CLOSE_FROM) / (1.0 - CLOSE_FROM) * CLOSE_FRAMES), CLOSE_FRAMES - 1)
	return maxi(roundi(lerpf(float(full), 1.0, float(j + 1) / float(CLOSE_FRAMES))), 1)


## How tall `body` is drawn, in pixels from its feet (its size counted): the highest of its body
## sprite's top (`Sprite`, drawn at the body's scale), its hurt shape's top and twice its body's
## centre (both kept in pixels at its size, `Actor.set_size`), and a margin.
static func body_height(body: Actor) -> float:
	var top: float = -2.0 * body.body_offset.y
	if body.hurtbox != null:
		top = maxf(top, -body.hurtbox.offset.y + body.hurtbox.outer_radius())
	var sprite := body.get_node_or_null(^"Sprite") as Sprite2D
	if sprite != null:
		top = maxf(top, -(sprite.position.y + sprite.get_rect().position.y * absf(sprite.scale.y)) * absf(body.size))
	return maxf(ceilf(top + HEIGHT_MARGIN), MIN_HEIGHT)


## Draw every arriving body of `table` as far through its arrival as it is, and put back the bodies
## done. `real_delta` is the frame's real seconds (the cue's sound is spaced by them).
func step(table: ActorsScript, real_delta: float) -> void:
	_clock += real_delta
	_marks = 0
	var arriving: int = 0
	if table != null:
		var count: int = table.open_ids(_ids)
		for n in count:
			var body := table.node_of(_ids[n]) as Actor
			if body == null or not body.is_arriving() or not body.is_inside_tree():
				continue
			arriving += 1
			_draw_body(body)
	if _drawn.size() > arriving:
		_put_back()
	if _marks > 0 or _drawn_marks > 0:
		queue_redraw()


## One arriving body: its cut and shift, its mark, and its rise's cue once.
func _draw_body(body: Actor) -> void:
	var key: int = body.get_instance_id()
	if not _drawn.has(key):
		_drawn[key] = false
		body.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	var share: float = body.arrive_share()
	var shift: float = rise_shift(body_height(body), share)
	var item: RID = body.get_canvas_item()
	RenderingServer.canvas_item_set_transform(item, body.get_transform().translated(Vector2(0.0, shift)))
	RenderingServer.canvas_item_clear(item)
	if share >= MARK_END:
		var size: float = maxf(absf(body.size), 0.01)
		var line: float = -shift / size
		RenderingServer.canvas_item_add_rect(item, Rect2(-MASK_HALF_WIDTH, -MASK_TALL, 2.0 * MASK_HALF_WIDTH, MASK_TALL + line), Color.WHITE)
		if not _drawn[key]:
			_drawn[key] = true
			_play_rise_cue(body.global_position)
	var radius: int = mark_radius(body.wall_radius(), share)
	if radius > 0 and _marks < _mark_at.size():
		_mark_at[_marks] = body.global_position.round()
		_mark_radius[_marks] = radius
		_marks += 1


func _play_rise_cue(at: Vector2) -> void:
	if not play_cue.is_valid():
		return
	var weighted: bool = _clock - _sounded_at >= SOUND_EVERY
	if weighted:
		_sounded_at = _clock
	play_cue.call(at, weighted)


## Every body drawn arriving that arrives no more (or went) has its own transform back and is no clip
## parent any more.
func _put_back() -> void:
	for key: int in _drawn.keys():
		var body := instance_from_id(key) as Actor
		if body != null and body.is_arriving() and body.is_inside_tree():
			continue
		if body != null:
			body.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
			var item: RID = body.get_canvas_item()
			RenderingServer.canvas_item_clear(item)
			RenderingServer.canvas_item_set_transform(item, body.get_transform())
		_drawn.erase(key)


func _draw() -> void:
	_drawn_marks = _marks
	for m in _marks:
		_draw_mark(_mark_at[m], _mark_radius[m])


## A mark `radius` pixels wide each way at `at` (radius 1: a dot), half as high (it lies on the floor),
## row by row in whole pixels: its inside in the fill, its edge in the rim.
func _draw_mark(at: Vector2, radius: int) -> void:
	var high: int = maxi(radius / 2, 0)
	for row in range(-high, high + 1):
		var across: float = 1.0 - (float(row) / float(high + 1)) ** 2 if high > 0 else 1.0
		var half: int = maxi(floori((float(radius) - 0.5) * sqrt(across)), 0)
		var y: float = at.y + float(row)
		var width: float = float(2 * half + 1)
		if row == -high or row == high or half <= 1:
			draw_rect(Rect2(at.x - float(half), y, width, 1.0), _rim)
			continue
		draw_rect(Rect2(at.x - float(half), y, 1.0, 1.0), _rim)
		draw_rect(Rect2(at.x - float(half) + 1.0, y, width - 2.0, 1.0), _fill)
		draw_rect(Rect2(at.x + float(half), y, 1.0, 1.0), _rim)


## How many bodies it draws arriving now, and how many marks it drew this frame (tests).
func drawn() -> int:
	return _drawn.size()


func marks() -> int:
	return _marks


## The mark `n` of this frame: where and how wide (tests).
func mark(n: int) -> Vector3:
	return Vector3(_mark_at[n].x, _mark_at[n].y, float(_mark_radius[n]))
