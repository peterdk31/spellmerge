class_name ArriveLook
extends Node2D
## The look of an enemy arriving (enemy arrivals EA2, docs/milestones/enemy-arrivals.md, "The look"):
## first a mark grows on the floor where the body will stand, then the body rises out of it. It is
## drawn from the body's state alone (`Actor.arrive_share`), never from a moment it was told of, so a
## machine that joins mid-arrival or a snapshot restored mid-arrival shows it where it is. Feel steps
## it once a frame (`step`: the marks and the cues) over the actor table's open bodies, as it does
## `FallLook`; the bodies are cut just before the frame is drawn (`cut`, on
## `RenderingServer.frame_pre_draw`), after every `_process` and deferred call, so a body added
## after Feel's step (a run started as a load ends) is never drawn whole for a frame.
##
## - **0 to MARK_END, the mark:** a disc on the floor at the body's feet, as wide as its footprint, in
##   the room's floor colours (`RoomBase.floor_colors`: its shadow, darkened, with its light shade
##   as a rim; `use_room`), growing from a dot in MARK_FRAMES frames. The body is not drawn yet.
## - **MARK_END to 1, the rise:** the body comes up out of the mark, drawn shifted down by whole pixels
##   from its full height (`body_height`, and the rows its art has under its feet, `body_bottom`) to 0
##   and cut off at the line of its lowest row, so what is still under the floor is not drawn and
##   nothing of it appears in one jump as it lands. Its own sprite and pose all the way: no fade, no blur, no scale. As the
##   rise starts the cue `enemy_arrive` plays at its feet (dust off the mark, a soft sound): its sound
##   at most every SOUND_EVERY seconds, so a group does not stack it (the cue is played unweighted
##   in between: its dust only). From CLOSE_FROM the mark closes in CLOSE_FRAMES frames as the feet
##   land, down to a dot, so the rise ends where standing begins (docs/STYLE.md, "Smooth").
##
## The cut (checked against the world's y-sort and the light pass on a virtual display before it was
## built, EA2): the body's root is made a clip parent (`CanvasItem.clip_children`) whose own canvas
## item draws one rect, above that line, as the mask, and each of its direct drawn children
## (its sprite, its face, its look; not a top-level one) is drawn shifted down by the rise
## (`RenderingServer.canvas_item_set_transform`, re-set every frame), so a part's own parts go with
## it. That is one cut for any body, layered (`BodyPart`) or not. The root itself is never moved: the
## world's y-sort orders it by its own place, so a rising body stays behind a wizard standing just in
## front of its mark (a shifted root would sort as if its feet were lower and draw over that wizard),
## and the light pass, drawn over the world, lights it as any body. Nothing in the simulation reads
## any of it: its position and its parts' are untouched. A body whose arrival is over (or that is
## gone) gets its children's own transforms back and is no clip parent any more.
##
## View only. Nothing here allocates while bodies arrive: its scratch of ids and marks is made once,
## and the dictionaries of the bodies it cut (with the part of each one's height that follows its
## size, worked out when it is first cut and again only if its size changes) and whose cue it played grow only when a body first arrives (and are walked
## only as one is done).

const ActorsScript := preload("res://core/actors/actors.gd")

const VIEW_ONLY: bool = true

## Where the mark stage ends and the rise begins, as a share of the arrival.
const MARK_END: float = 0.4
## The frames the mark grows in, from a dot to the footprint's width.
const MARK_FRAMES: int = 4
## Where the mark starts to close (share of the arrival), and the frames it closes in.
const CLOSE_FROM: float = 0.92
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
## The table `step` was last given (Feel's actor table), read again by `cut`.
var _table: ActorsScript = null
## The bodies cut (by instance id): how far below their place each was drawn at its last cut, and how
## far below its feet its mask reached (`body_bottom`), in pixels; and the bodies whose rise's cue was
## played.
var _drawn: Dictionary[int, Vector2] = {}
## Each body cut's top from its body and its hurt shape (`size_top`), worked out when it is first cut
## and again only if its size changes mid-arrival (`Actor.set_size` is what moves them), and the size
## it was worked out at (apart: a Vector2 is float32, and the size is compared exactly); forgotten
## with the body in `_drawn`. Its sprite's terms are read every cut: its look's bob moves its art
## while it arrives (`CreatureLook`, the sprite's offset).
var _size_top: Dictionary[int, float] = {}
var _size_top_measured_at: Dictionary[int, float] = {}
var _risen: Dictionary[int, bool] = {}
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


func _enter_tree() -> void:
	if not RenderingServer.frame_pre_draw.is_connected(cut):
		RenderingServer.frame_pre_draw.connect(cut)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(cut):
		RenderingServer.frame_pre_draw.disconnect(cut)


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
## centre (both kept in pixels at its size, `Actor.set_size`), and a margin. (A layered body's art is
## in its `BodyPart`s, not its `Sprite`: only bosses are layered today, and they never arrive.)
static func body_height(body: Actor) -> float:
	return _height_from(body, size_top(body))


## The top of `body` from its body's centre and its hurt shape alone, in pixels from its feet: the
## part of `body_height` that, once it is in play, only its size moves (`Actor.set_size`; a prop's
## or a decoy's are set before it is added). A cut keeps it while the body arrives, so anything
## that moved these mid-arrival without its size would have to be counted here (gameplay/feel/README.md).
static func size_top(body: Actor) -> float:
	var top: float = -2.0 * body.body_offset.y
	if body.hurtbox != null:
		top = maxf(top, -body.hurtbox.offset.y + body.hurtbox.outer_radius())
	return top


## `body_height` from its `size_top` and its body sprite as it is now.
static func _height_from(body: Actor, top_of_size: float) -> float:
	var top: float = top_of_size
	var sprite := body.get_node_or_null(^"Sprite") as Sprite2D
	if sprite != null:
		top = maxf(top, -(sprite.position.y + sprite.get_rect().position.y * absf(sprite.scale.y)) * absf(body.size))
	return maxf(ceilf(top + HEIGHT_MARGIN), MIN_HEIGHT)


## How far below its feet `body`'s body sprite reaches, in whole pixels (0 for none above them): the
## rows a frame has under the feet's line (a spitter's), which the cut keeps and the rise lifts.
static func body_bottom(body: Actor) -> float:
	var sprite := body.get_node_or_null(^"Sprite") as Sprite2D
	if sprite == null:
		return 0.0
	return maxf(ceilf((sprite.position.y + sprite.get_rect().end.y * absf(sprite.scale.y)) * absf(body.size)), 0.0)


## Lay out every arriving body of `table`'s mark, and play each one's rise cue once, as far through
## its arrival as it is; the cut itself is `cut`, just before the frame is drawn. `real_delta` is the
## frame's real seconds (the cue's sound is spaced by them).
func step(table: ActorsScript, real_delta: float) -> void:
	_table = table
	_clock += real_delta
	_marks = 0
	var rising: int = 0
	if table != null:
		var count: int = table.open_ids(_ids)
		for n in count:
			var body := table.node_of(_ids[n]) as Actor
			if body == null or not body.is_arriving() or not body.is_inside_tree():
				continue
			var share: float = body.arrive_share()
			if share >= MARK_END:
				rising += 1
				var key: int = body.get_instance_id()
				if not _risen.has(key):
					_risen[key] = true
					_play_rise_cue(body.global_position)
			var radius: int = mark_radius(body.wall_radius(), share)
			if radius > 0 and _marks < _mark_at.size():
				_mark_at[_marks] = body.global_position.round()
				_mark_radius[_marks] = radius
				_marks += 1
	if _risen.size() > rising:
		_forget_risen()
	if _marks > 0 or _drawn_marks > 0:
		queue_redraw()


## Cut every arriving body of the table `step` was last given, and put back the bodies done. Called
## just before every frame is drawn (`RenderingServer.frame_pre_draw`), after every `_process` and
## deferred call, so a body added after Feel's step (a run started as a load ends) is never drawn
## whole for a frame; tests call it by hand.
func cut() -> void:
	var arriving: int = 0
	if _table != null and is_instance_valid(_table):
		var count: int = _table.open_ids(_ids)
		for n in count:
			var body := _table.node_of(_ids[n]) as Actor
			if body == null or not body.is_arriving() or not body.is_inside_tree():
				continue
			arriving += 1
			_cut_body(body)
	if _drawn.size() > arriving:
		_put_back()


## One arriving body cut at its feet's line (the lowest row of its art) and its parts shifted by its rise.
func _cut_body(body: Actor) -> void:
	var key: int = body.get_instance_id()
	if not _drawn.has(key):
		body.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	var size: float = maxf(absf(body.size), 0.01)
	var bottom: float = body_bottom(body)
	var shift: float = rise_shift(_height_from(body, _size_top_of(body, key)) + bottom, body.arrive_share())
	_drawn[key] = Vector2(shift, bottom)
	_shift_parts(body, shift / size)
	var item: RID = body.get_canvas_item()
	RenderingServer.canvas_item_clear(item)
	# The mask: everything above the line (in the body's own pixels). Always drawn, every frame: a
	# clip parent that draws nothing clips nothing. Through the mark the parts are shifted their whole
	# height and more, so all of them are under the line.
	RenderingServer.canvas_item_add_rect(item, mask_rect(bottom, size), Color.WHITE)


## The mask of a body whose art reaches `bottom` pixels below its feet, at its `size`: everything
## above that line, in the body's own pixels.
static func mask_rect(bottom: float, size: float) -> Rect2:
	return Rect2(-MASK_HALF_WIDTH, -MASK_TALL, 2.0 * MASK_HALF_WIDTH, MASK_TALL + bottom / size)


## `body`'s `size_top`, as kept for `key` (its instance id): worked out the first time and whenever
## its size is not the one it was worked out at.
func _size_top_of(body: Actor, key: int) -> float:
	if _size_top_measured_at.get(key, NAN) == body.size:
		return _size_top[key]
	var top: float = size_top(body)
	_size_top[key] = top
	_size_top_measured_at[key] = body.size
	return top


## Each direct drawn child of `body` (a Node2D that is not top level) drawn `by` of the body's own
## pixels below where it is (0: where it is). Its node is untouched; only its canvas item is moved.
static func _shift_parts(body: Actor, by: float) -> void:
	for i in body.get_child_count():
		var part := body.get_child(i) as Node2D
		if part == null or part.top_level:
			continue
		var place: Transform2D = part.get_transform()
		RenderingServer.canvas_item_set_transform(part.get_canvas_item(), place.translated(Vector2(0.0, by)) if by != 0.0 else place)


func _play_rise_cue(at: Vector2) -> void:
	if not play_cue.is_valid():
		return
	var weighted: bool = _clock - _sounded_at >= SOUND_EVERY
	if weighted:
		_sounded_at = _clock
	play_cue.call(at, weighted)


## The bodies whose rise cue played that rise no more (or went) are forgotten.
func _forget_risen() -> void:
	for key: int in _risen.keys():
		var body := instance_from_id(key) as Actor
		if body == null or not body.is_arriving() or not body.is_inside_tree():
			_risen.erase(key)


## Every body cut that arrives no more (or went) has its parts' own transforms back and is no clip
## parent any more.
func _put_back() -> void:
	for key: int in _drawn.keys():
		var body := instance_from_id(key) as Actor
		if body != null and body.is_arriving() and body.is_inside_tree():
			continue
		if body != null:
			body.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
			RenderingServer.canvas_item_clear(body.get_canvas_item())
			_shift_parts(body, 0.0)
		_drawn.erase(key)
		_size_top.erase(key)
		_size_top_measured_at.erase(key)


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


## How many bodies it cuts now, and how many marks it lays this frame (tests).
func drawn() -> int:
	return _drawn.size()


## The `size_top` it keeps for `body` (NAN: none), and for how many bodies it keeps one (tests).
func size_top_kept(body: Actor) -> float:
	return _size_top.get(body.get_instance_id(), NAN)


func size_tops_kept() -> int:
	return _size_top.size()


## How far below its feet `body`'s mask reached at its last cut, in pixels (-1: not cut; tests).
func bottom_of(body: Actor) -> float:
	return _drawn.get(body.get_instance_id(), Vector2(-1.0, -1.0)).y


## How far below its place `body` was drawn at its last cut, in pixels (-1: not cut; tests).
func shift_of(body: Actor) -> float:
	return _drawn.get(body.get_instance_id(), Vector2(-1.0, -1.0)).x


func marks() -> int:
	return _marks


## The mark `n` of this frame: where and how wide (tests).
func mark(n: int) -> Vector3:
	return Vector3(_mark_at[n].x, _mark_at[n].y, float(_mark_radius[n]))
