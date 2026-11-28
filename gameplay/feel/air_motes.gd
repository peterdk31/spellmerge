extends RefCounted
## The room's air (docs/milestones/atmosphere.md, B: lit dust in the air): what drifts over the
## whole room, the `MoteSource` its data names (`RoomBase.air`), given off all the time over the
## part of the room in view and a little past it (VIEW_MARGIN), its rate for every
## `RoomBase.AIR_AREA` of that floor, so a big room and a small one look as thick and nothing is
## given off where nobody looks. Each mote leaves from a point anywhere in that part at random,
## shown its source's `height` over the floor, thrown its `way` within its `spread`, in one of its
## colours at random, never more than RING_SHARE of the motes' ring at once, as motes of many a
## frame (`often`: in a crowded frame they give way to the moments and the hits first). Its colours
## are rows of the ramp table, asked for again whenever the table writes a row (`RampTable.writes`),
## so a long fight's new colours taking the oldest rows never recolour the air. Its kind is usually lit only (`MoteKind.lit_only`), so the dust is
## seen only where a light falls; that is the motes' drawing, not this.
##
## It knows the room only by what the spectacle hands it (`use`: the air, `give_off`: the room's
## bounds and the view), and the motes only by their pool. View only: its dice are its own and it
## runs on Feel's clock.

const MotesScript := preload("res://gameplay/feel/mote.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")
const ViewBoxesScript := preload("res://gameplay/feel/view_boxes.gd")
const VoidEdgesScript := preload("res://gameplay/feel/void_edges.gd")

## The longest frame it gives off for (s): a frame after a stall gives off no more.
const LONGEST_FRAME: float = 0.1
## How far past the view it gives off (px): what drifts in from just outside it.
const VIEW_MARGIN: float = 32.0
## The most of the motes' ring the air may hold at once (its rate is cut to keep within it, by its
## kind's average life): the dust never crowds out a fight's motes, whatever the "Particles"
## setting (Minimal's 2,048 rows: 256 of dust at most).
const RING_SHARE: float = 0.125
## How many points a mote that must leave from outside every place tries (`give_off`'s `outside`).
const OUTSIDE_TRIES: int = 4
## No rectangles: nothing inside a place counts as the void (`give_off`'s `shown_void`).
const NO_RECTS: Array[Rect2] = []

## The air given off (null: none), its colours as the ramp table's sources, and motes owed (a part
## of one). Read only.
var look: MoteSource = null
var sources: PackedInt32Array = PackedInt32Array()
var _owed: float = 0.0
## Its ramps (read once), and the table's writes when its sources were last asked for.
var _ramps: Array[PackedColorArray] = []
var _written: int = -1
var _table: RampTableScript = null
## Its dice's seed: the same every run, so what it draws is the same picture every time a run is
## played (a new generator starts at a random seed; screenshots compare runs byte for byte); each
## one made takes it with its count (`FeelDice.made`).
const DICE_SEED: int = 0xA1E5
var _rng := FeelDice.made(DICE_SEED)
var _last: float = -1.0
## Whether the kind the pool lacks was warned of (once a room).
var _warned: bool = false
## Motes given off, all told, and the box round where they left from (for tests).
var given: int = 0
var given_box: Rect2 = Rect2()
## `give_off`'s one box, as views (kept: nothing is made a frame).
var _one: ViewBoxesScript = ViewBoxesScript.new()


## Air whose colours are rows of `table` (the spectacle's, shared with the motes).
func _init(table: RampTableScript) -> void:
	_table = table


## The room's air from now (`RoomBase.air`; null: none). Air with a problem gives off nothing and
## says why, once.
func use(air: MoteSource) -> void:
	look = null
	sources = PackedInt32Array()
	_ramps = []
	_owed = 0.0
	_warned = false
	if air == null:
		return
	var problems: PackedStringArray = RoomBase.problems_of_air(air)
	if not problems.is_empty():
		push_warning("The room's air gives off nothing: %s." % "; ".join(problems))
		return
	_ramps = air.ramps()
	sources.resize(_ramps.size())
	_resolve()
	if sources.is_empty():
		push_warning("The room's air gives off nothing: it has no colours.")
		return
	look = air


## The part of the room it gives off over: `bounds` (the room's; empty: anywhere) within
## VIEW_MARGIN of `view` (the world's part on screen; empty: all of `bounds`).
static func area_of(view: Rect2, bounds: Rect2) -> Rect2:
	if not view.has_area():
		return bounds
	var near: Rect2 = view.grow(VIEW_MARGIN)
	return near.intersection(bounds) if bounds.has_area() else near


## Give off the motes owed since the last call, at Feel's clock `now`, into `pool` (null: none, the
## particles or the light are off), over `area_of(view, bounds)`, holding at most `share` of the
## motes' ring at once (RING_SHARE for the room's air; a kind's air in each of its rooms takes a part
## of its own, gameplay/feel/kind_air.gd). With `outside` (a grid with places) a mote leaves only
## from a point in none of its places (the void between a biome's slabs, `void_air`): a point inside
## one is drawn again up to OUTSIDE_TRIES times, then that mote is not given off. A point in one of
## `shown_void`'s rectangles counts as outside (the places the void covers: an unvisited room is the
## void until it is entered, the owner, 2026-11-21; `UnseenDark.void_covers`), and so does one off
## its piece's slab by `edges` (the void inside a piece's rectangle, the owner, 2026-11-23;
## void_edges.gd; null: none).
func give_off(now: float, pool: MotesScript, view: Rect2, bounds: Rect2, share: float = RING_SHARE, outside: RoomGrid = null, shown_void: Array[Rect2] = NO_RECTS, edges: VoidEdgesScript = null) -> void:
	_one.set_one(view)
	give_off_in(now, pool, _one, bounds, share, outside, shown_void, edges)


## As `give_off`, over each of the views' boxes `seen` (each within VIEW_MARGIN, in `bounds`; none:
## all of `bounds`) at the rate for the floor they cover together, a part two views both show
## counted once (`ViewBoxes.pick`): split, each view's air is as thick as one picture's (the owner,
## 2026-11-20), and nothing is given off over the rooms and the void between the views.
func give_off_in(now: float, pool: MotesScript, seen: ViewBoxesScript, bounds: Rect2, share: float = RING_SHARE, outside: RoomGrid = null, shown_void: Array[Rect2] = NO_RECTS, edges: VoidEdgesScript = null) -> void:
	var dt: float = clampf(now - _last, 0.0, LONGEST_FRAME) if _last >= 0.0 else 0.0
	_last = now
	if look == null or pool == null:
		_owed = 0.0
		return
	var area: float = bounds.get_area() if seen.is_empty() else seen.total_area(VIEW_MARGIN, bounds)
	if area <= 0.0:
		_owed = 0.0
		return
	var k: int = pool.kind_index(look.kind)
	if k < 0:
		if not _warned:
			_warned = true
			push_warning("The room's air gives off nothing: '%s' is no mote kind (content/motes)." % look.kind)
		return
	var life: Vector2 = pool.kinds()[k].life
	var most: float = float(pool.cap()) * share / maxf((life.x + life.y) * 0.5, 0.05)
	_owed += minf(look.rate * area / RoomBase.AIR_AREA, most) * dt
	if _table.writes != _written:
		_resolve()
	var height: float = look.height if look.height > 0.0 else -1.0
	while _owed >= 1.0:
		_owed -= 1.0
		var at: Vector2 = _point(seen, bounds)
		if outside != null:
			var tries: int = 1
			while at.is_finite() and not is_void(at, outside, shown_void, edges) and tries < OUTSIDE_TRIES:
				at = _point(seen, bounds)
				tries += 1
			if at.is_finite() and not is_void(at, outside, shown_void, edges):
				continue
		if not at.is_finite():
			continue
		var ramp: int = sources[_rng.randi() % sources.size()]
		pool.throw_part(k, at, look.way, ramp, Color.WHITE, 1, look.reach, look.spread, 1.0, false, true, Vector2.ZERO, 1.0, 0, height)
		given_box = given_box.expand(at) if given > 0 else Rect2(at, Vector2.ZERO)
		given += 1


## Whether `at` shows the void: in none of `grid`'s places, off its place's slab by `edges` (null:
## never), or in one of `shown_void`'s rectangles.
static func is_void(at: Vector2, grid: RoomGrid, shown_void: Array[Rect2], edges: VoidEdgesScript = null) -> bool:
	var place: int = grid.place_at(at)
	if place == RoomGrid.NO_PLACE or (edges != null and edges.shows(at, place, grid)):
		return true
	for rect in shown_void:
		if rect.has_point(at):
			return true
	return false


## A point to give a mote off from: in the views' boxes `seen` (INF: one in an earlier box's part,
## counted there), or with none anywhere in `bounds`.
func _point(seen: ViewBoxesScript, bounds: Rect2) -> Vector2:
	if seen.is_empty():
		return Vector2(bounds.position.x + _rng.randf() * bounds.size.x, bounds.position.y + _rng.randf() * bounds.size.y)
	return seen.pick(_rng, VIEW_MARGIN, bounds)


## Its ramps' rows in the table, asked for again (each kept, or written again where its row went to
## other colours), into `sources` (no new array).
func _resolve() -> void:
	for i in _ramps.size():
		sources[i] = _table.source(_ramps[i])
	_written = _table.writes
