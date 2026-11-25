extends Node2D
## The markers at a view's edge for the foes of a fight that are out of it (the owner, 2026-11-23:
## "we can have edge markers, that points to enemies out of view in the room"; they came with the
## end of the cameras framing close foes, docs/milestones/connected-biomes.md, "A steady camera").
##
## **The rule:** while a wizard of a seat played on this machine (its own body, or the actor it
## drives) stands in a sealed place of the room grid (a fight under way there, a boss's among them),
## every enemy in that place (an open actor of `TEAM_ENEMIES` whose body is in the tree, one still
## spawning in too) that the view showing that seat does not show gets a small arrow at that view's
## edge (the screen's, or a divider while split: never in another view's cell), on the line from the
## view's anchor to where the view would draw the foe, pointing at it. Nothing outside a sealed
## fight, nothing in a world with no places (the hub, a single room), and nothing with no seat here.
##
## **The look:** a plain triangle in the palette's Fire base with the Outline round it (Fire is the
## enemies' telegraphs' colour; Blight is kept for their spells and the hat colours for the players,
## docs/STYLE.md), smaller than a teammate's marker and with no notch, so the two are told apart by
## shape and size as well as colour. A boss's is larger and in Fire light.
##
## **Smooth** (docs/STYLE.md): a marker grows in and shrinks out over STAGES looks of whole pixels,
## a look a drawn frame at the fastest and STAGE_SECONDS apart; one going keeps its place and way
## while it shrinks, and one wanted again before it is gone grows back from the look it had.
##
## **Always on its own view's edge:** a wanted marker stands where the line from its view's anchor
## to its foe leaves that view's cell, worked out anew every frame, so it moves along the edge with
## its foe and with the cell. It never crosses the picture: where that place leaps (further than
## `reach` allows in the frame: the foe teleported, or the cells were cut anew as the screen split
## or merged), the marker there shrinks out and one grows in at the new place. A marker another
## view now wants right where it stands (the same foe: a split's two views start as one picture,
## and a merge ends on one) is handed to that view as it is. Only a marker shrinking out may be
## left in a cell not its view's, for its last looks.
##
## **Many foes** (decided while building, Claude; for the owner to overrule):
## - at most MOST_A_VIEW markers a view, and BOSSES_A_VIEW more for bosses, so a boss always has
##   one; a marker keeps its slot while its foe stays out of view and a new foe takes a free one
##   (never the nearest N, which would swap markers every frame);
## - a foe gets a marker once it is OUT_BY outside its view's cell and keeps it until it is IN_BY
##   inside, so one walking the edge does not blink;
## - markers of one view never pile up: two within MERGE_GAP of each other become one (a boss's
##   stays, else the older slot's), and a foe gets a marker only where it would sit APART from every
##   other of its view (a boss's only from other bosses').
##
## Feel puts it on the teammate markers' canvas layer, under them, in layout pixels (core/display/picture_grid.gd), so it is the
## same size whatever a view's zoom. View only, on Feel's real clock: nothing in the game reads it,
## and nothing is allocated after it is made.

const ActorsScript := preload("res://core/actors/actors.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")

## How far inside its view's edge a marker sits, in layout pixels (core/display/picture_grid.gd).
const INSET: float = 10.0
## A foe gets a marker once it is this far outside its view's cell, and keeps it until it is this
## far inside (screen pixels).
const OUT_BY: float = 12.0
const IN_BY: float = 4.0
## The most markers a view shows, and the most more for bosses.
const MOST_A_VIEW: int = 6
const BOSSES_A_VIEW: int = 2
## Two markers of one view this close become one, and a new one sits at least this far from the
## others (screen pixels).
const MERGE_GAP: float = 10.0
const APART: float = 16.0
## The looks a marker grows in and shrinks out by, and the least real seconds between two.
const STAGES: int = 3
const STAGE_SECONDS: float = 0.04
## A marker follows its place on the edge while that moves no faster than this (screen pixels a
## real second; at least REACH_LEAST in a drawn frame): further is a leap, which a marker never
## makes (the one there shrinks out, one grows in at the new place).
const REACH_SPEED: float = 1200.0
const REACH_LEAST: float = 16.0
## A marker's size a stage, in layout pixels (core/display/picture_grid.gd): its length (tip to back) and half its width; a boss's.
const LENGTH_STEP: float = 4.0
const HALF_WIDTH_STEP: float = 1.0
const BOSS_LENGTH_STEP: float = 5.0
const BOSS_HALF_WIDTH_STEP: float = 2.0
## The dark edge round it (the palette's Outline) and its colours (Fire base; a boss's Fire light).
const OUTLINE: float = 2.0
const OUTLINE_COLOR: Color = Color("#14121f")
const COLOR: Color = Color("#e0592f")
const BOSS_COLOR: Color = Color("#ffa23c")

## Twice the most wanted at once: room for those shrinking out beside those growing in.
const SLOTS: int = ScreenViewsScript.VIEWS_MOST * (MOST_A_VIEW + BOSSES_A_VIEW) * 2
## The most sealed places a view's wizards stand in (each seat's own body and the actor it drives).
const PLACES_A_VIEW: int = ActorsScript.SEATS * 2

## How many markers are drawn now (growing in, whole or shrinking out).
var count: int = 0

## By slot: its look (0: free, up to STAGES), the foe's actor id, its view's id (`ScreenViews.ids`:
## the view's own while it lives), whether the foe is a boss, its place (screen pixels) and its way (to its foe).
var _stage: PackedInt32Array = PackedInt32Array()
var _foe: PackedInt32Array = PackedInt32Array()
var _key: PackedInt32Array = PackedInt32Array()
var _boss: PackedByteArray = PackedByteArray()
var _at: PackedVector2Array = PackedVector2Array()
var _way: PackedVector2Array = PackedVector2Array()
## By slot: wanted this frame (its foe out of view; else it shrinks), and the frame before.
var _wanted: PackedByteArray = PackedByteArray()
var _was: PackedByteArray = PackedByteArray()
## The drawn markers' slots, in slot order (`count` of them).
var _shown: PackedInt32Array = PackedInt32Array()
## By view: the sealed places its wizards stand in (`_place_counts` of them from view x PLACES_A_VIEW).
var _places: PackedInt32Array = PackedInt32Array()
var _place_counts: PackedInt32Array = PackedInt32Array()
var _ids: PackedInt32Array = PackedInt32Array()
## Real seconds since the markers last changed their looks.
var _since: float = 0.0
## The triangle and its edge (closed), filled for each marker drawn.
var _points: PackedVector2Array = PackedVector2Array()
var _outline: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	_stage.resize(SLOTS)
	_foe.resize(SLOTS)
	_foe.fill(ActorsScript.NONE)
	_key.resize(SLOTS)
	_boss.resize(SLOTS)
	_at.resize(SLOTS)
	_way.resize(SLOTS)
	_wanted.resize(SLOTS)
	_was.resize(SLOTS)
	_shown.resize(SLOTS)
	_places.resize(ScreenViewsScript.VIEWS_MOST * PLACES_A_VIEW)
	_place_counts.resize(ScreenViewsScript.VIEWS_MOST)
	_ids.resize(ActorsScript.ACTORS)
	_points.resize(3)
	_outline.resize(4)


## A drawn frame, `delta` real seconds on: find the foes of the sealed places the wizards of
## `seats_here` (a bit per seat played on this machine; 0: no markers) stand in, by the places of
## `grid` (null or none: no markers), that `views` (this machine's: the one picture, or the split
## screen's; `ScreenViews`) do not show, and move every marker on.
func step(delta: float, table: ActorsScript, grid: RoomGrid, seats_here: int, views: ScreenViewsScript) -> void:
	var before: int = count
	for slot in SLOTS:
		_was[slot] = _wanted[slot]
		_wanted[slot] = 0
	if table != null and grid != null and grid.places() > 0 and seats_here != 0 and views != null and views.count > 0:
		if _find_places(table, grid, seats_here, views):
			var open: int = table.open_ids(_ids)
			var reach: float = maxf(REACH_SPEED * maxf(delta, 0.0), REACH_LEAST)
			# Bosses first, so a boss's marker is the one that stays where two would pile up.
			_want(table, grid, views, open, true, reach)
			_want(table, grid, views, open, false, reach)
			_merge()
	_since += maxf(delta, 0.0)
	var change: bool = _since >= STAGE_SECONDS
	if change:
		_since = 0.0
	count = 0
	for slot in SLOTS:
		if _foe[slot] == ActorsScript.NONE:
			continue
		if _wanted[slot] != 0:
			if change:
				_stage[slot] = mini(_stage[slot] + 1, STAGES)
		elif change or _stage[slot] == 0:
			# Shrinking out; one gone (or never drawn) gives its slot up.
			_stage[slot] = maxi(_stage[slot] - 1, 0)
			if _stage[slot] == 0:
				_foe[slot] = ActorsScript.NONE
				continue
		if _stage[slot] > 0:
			_shown[count] = slot
			count += 1
	if count > 0 or before > 0:
		queue_redraw()


## Each view's sealed places: where the wizards of its seats here stand in a fight. False with none.
func _find_places(table: ActorsScript, grid: RoomGrid, seats_here: int, views: ScreenViewsScript) -> bool:
	var any: bool = false
	for view in views.count:
		_place_counts[view] = 0
		if views.corners(view) < 3:
			# No cell to sit at the edge of (a view just made or going).
			continue
		var held: int = views.seats[view] & seats_here
		for seat in ActorsScript.SEATS:
			if held & (1 << seat) == 0:
				continue
			for driven in 2:
				var id: int = table.actor_of_seat(seat) if driven == 1 else table.home_of_seat(seat)
				var body := table.node_of(id) as Node2D
				if body == null or not body.is_inside_tree() or table.team_of(id) == ActorsScript.TEAM_ENEMIES:
					continue
				var place: int = grid.place_at(body.global_position)
				if not grid.is_sealed(place) or _has_place(view, place):
					continue
				_places[view * PLACES_A_VIEW + _place_counts[view]] = place
				_place_counts[view] += 1
				any = true
	return any


func _has_place(view: int, place: int) -> bool:
	for i in _place_counts[view]:
		if _places[view * PLACES_A_VIEW + i] == place:
			return true
	return false


## Mark the markers of the foes (`bosses`: the bosses, else the rest) out of their views as wanted,
## each on its view's edge; a foe newly out of view is given a slot where there is one. `reach`: how
## far a marker may follow its place this frame.
func _want(table: ActorsScript, grid: RoomGrid, views: ScreenViewsScript, open: int, bosses: bool, reach: float) -> void:
	for i in open:
		var id: int = _ids[i]
		if table.team_of(id) != ActorsScript.TEAM_ENEMIES:
			continue
		var body := table.node_of(id) as Node2D
		if body == null or not body.is_inside_tree() or _is_boss(body) != bosses:
			continue
		var where: Vector2 = body.global_position
		var place: int = grid.place_at(where)
		if not grid.is_sealed(place):
			continue
		for view in views.count:
			if not _has_place(view, place):
				continue
			var drawn: Vector2 = views.to_screen[view] * where
			# Well inside its view: no marker (one it had shrinks out).
			if views.cell_holds(view, drawn, -IN_BY):
				continue
			# From the view's anchor, kept on the screen (a view's wizards may be drawn just off it
			# while its picture eases to them).
			var from: Vector2 = views.anchor[view].clamp(Vector2.ONE * INSET, views.screen - Vector2.ONE * INSET)
			var to: Vector2 = drawn - from
			if to.length_squared() < 1.0:
				continue
			var at: Vector2 = _on_edge(views, view, from, to)
			if not views.cell_holds(view, at, 0.0):
				# No place for it in this view's cell (a sliver of one, its anchor outside it).
				continue
			var key: int = views.ids[view]
			var slot: int = _marker_near(id, bosses, at, key, reach)
			# One it had the frame before is kept until its foe is well inside; a new one (or one
			# shrinking out, turned back) only once its foe is well outside and there is room.
			if slot < 0 or _was[slot] == 0:
				if views.cell_holds(view, drawn, OUT_BY) or _crowded(at, key, slot, bosses):
					continue
				if slot < 0:
					slot = _free_slot(key, bosses)
					if slot < 0:
						continue
					_foe[slot] = id
					_boss[slot] = 1 if bosses else 0
					_stage[slot] = 0
			_key[slot] = key
			_at[slot] = at
			_way[slot] = to.normalized()
			_wanted[slot] = 1


## Where the line from `from` along `to` leaves view `view`'s cell, INSET inside it (screen pixels).
static func _on_edge(views: ScreenViewsScript, view: int, from: Vector2, to: Vector2) -> Vector2:
	# Past the foe's drawn place where that is inside the cell: a marker stands at the edge.
	var far: Vector2 = to.normalized() * maxf(to.length(), views.screen.length())
	return from + far * views.reach_inside(view, from, far, INSET)


## The marker of foe `id` (`boss`: a boss's) not taken this frame that stands within `reach` of
## `at`: the nearest, one of the view of id `key` before another view's (which is then handed
## over), or -1. One further off is left to shrink out where it is.
func _marker_near(id: int, boss: bool, at: Vector2, key: int, reach: float) -> int:
	var best: int = -1
	var nearest: float = reach * reach
	var own: bool = false
	for slot in SLOTS:
		if _foe[slot] != id or _wanted[slot] != 0 or (_boss[slot] != 0) != boss:
			continue
		var gap: float = _at[slot].distance_squared_to(at)
		if gap > reach * reach:
			continue
		var same: bool = _key[slot] == key
		if best < 0 or (same and not own) or (same == own and gap < nearest):
			best = slot
			nearest = gap
			own = same
	return best


## True when a new marker at `at` would sit within APART of one of the view of id `key` that is
## wanted (this frame so far, or the last; other than `but`). A boss's (`boss`) is crowded only by
## another boss's: it takes its place beside a lesser foe's marker, which then gives way (`_merge`).
func _crowded(at: Vector2, key: int, but: int, boss: bool) -> bool:
	for slot in SLOTS:
		if boss and _boss[slot] == 0:
			continue
		if slot != but and (_wanted[slot] != 0 or _was[slot] != 0) and _foe[slot] != ActorsScript.NONE and _key[slot] == key and _at[slot].distance_squared_to(at) < APART * APART:
			return true
	return false


## A free slot for a marker of the view of id `key`, or -1: that view already has its most (of
## bosses' for `boss`, of the others' otherwise; those shrinking out for more than a frame not
## counted).
func _free_slot(key: int, boss: bool) -> int:
	var free: int = -1
	var used: int = 0
	for slot in SLOTS:
		if _foe[slot] == ActorsScript.NONE:
			if free < 0:
				free = slot
		elif _key[slot] == key and (_boss[slot] != 0) == boss and (_wanted[slot] != 0 or _was[slot] != 0):
			used += 1
	return free if used < (BOSSES_A_VIEW if boss else MOST_A_VIEW) else -1


## Two wanted markers of one view within MERGE_GAP become one: a boss's stays over another's, else
## the lower slot's; the other shrinks out.
func _merge() -> void:
	for a in SLOTS:
		if _wanted[a] == 0:
			continue
		for b in range(a + 1, SLOTS):
			if _wanted[b] == 0 or _key[b] != _key[a] or _at[a].distance_squared_to(_at[b]) >= MERGE_GAP * MERGE_GAP:
				continue
			if _boss[b] != 0 and _boss[a] == 0:
				_wanted[a] = 0
				break
			_wanted[b] = 0


static func _is_boss(body: Node) -> bool:
	return body is Actor and (body as Actor).data != null and (body as Actor).data.boss


## Marker `at` (0 to `count` - 1): its foe's actor id, the id of its view (`ScreenViews.ids`), where
## it is (screen pixels), the way it points, its look (1 to STAGES), whether its foe is a boss and
## whether it is shrinking out (not wanted this frame).
func foe_of(at: int) -> int:
	return _foe[_shown[at]]


func view_id_of(at: int) -> int:
	return _key[_shown[at]]


func position_of(at: int) -> Vector2:
	return _at[_shown[at]]


func way_of(at: int) -> Vector2:
	return _way[_shown[at]]


func stage_of(at: int) -> int:
	return _stage[_shown[at]]


func is_boss(at: int) -> bool:
	return _boss[_shown[at]] != 0


func is_going(at: int) -> bool:
	return _wanted[_shown[at]] == 0


## The length (tip to back) and half the width a marker is drawn at look `stage`, in whole screen
## pixels (`boss`: a boss's).
static func size_at(stage: int, boss: bool) -> Vector2:
	return Vector2(BOSS_LENGTH_STEP if boss else LENGTH_STEP, BOSS_HALF_WIDTH_STEP if boss else HALF_WIDTH_STEP) * float(stage)


func _draw() -> void:
	for at in count:
		var slot: int = _shown[at]
		var boss: bool = _boss[slot] != 0
		var size: Vector2 = size_at(_stage[slot], boss)
		var middle: Vector2 = _at[slot].round()
		var way: Vector2 = _way[slot]
		var side: Vector2 = Vector2(-way.y, way.x) * size.y
		var back: Vector2 = middle - way * (size.x * 0.5)
		_points[0] = middle + way * (size.x * 0.5)
		_points[1] = back + side
		_points[2] = back - side
		_outline[0] = _points[0]
		_outline[1] = _points[1]
		_outline[2] = _points[2]
		_outline[3] = _points[0]
		draw_polyline(_outline, OUTLINE_COLOR, OUTLINE)
		draw_colored_polygon(_points, BOSS_COLOR if boss else COLOR)
