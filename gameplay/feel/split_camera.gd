extends RefCounted
## The Voronoi split's views, worked out each drawn frame (connected biomes CB6,
## docs/milestones/connected-biomes.md, decision 27; the drawing is `split_screen.gd`'s). Pure: it
## reads the actor table and the world camera's state, and writes `views` (core's ScreenViews). View
## only, on real time: nothing in the simulation reads it.
##
## - **One view while everyone fits.** While the box round this machine's wizards fits in the
##   picture at the party camera's widest zoom (PartyCamera.MIN_ZOOM, its margin kept), there is no
##   view here: the world's camera draws the one picture (`party_camera.gd`). Past that the screen
##   splits; it merges again once the box fits with MERGE_ROOM to spare (so it does not flicker).
## - **Groups, a view each** (up to four). Wizards in one place share a view: two seats are in one
##   group while they stand within JOIN_REACH of each other (LEAVE_REACH once together), through any
##   chain of them. With one group and no fit, each seat is its own.
## - **Each view leans toward the others.** The groups' middles are laid on the screen as they stand
##   (the party's middle at the screen's middle, one scale both ways, the farthest SITE_MARGIN from
##   an edge); a view looks where its group is drawn at its own place, at SPLIT_ZOOM, kept to the
##   camera's limits. The screen is cut along the bisectors between where the groups are drawn
##   (`VoronoiCells.fill`): cells that cover it without overlap, each holding its own group.
## - **Close foes in view** (the owner, 2026-11-19). A view zooms out from SPLIT_ZOOM, no further
##   than the party camera's MIN_ZOOM, until the enemies close to its group (`close_foes.gd`) are
##   drawn inside its cell with FOE_MARGIN to spare (`zoom_for_foes`: the cell as the half-planes
##   between its group's place and the others' and the screen's edges). It zooms about its group's
##   place, so its wizards only come nearer it and the cell still holds them; whether to split or
##   merge is still the wizards' alone. Eased like everything else here.
## - **No jump** (docs/STYLE.md, "Smooth"). Every view eases to its place and zoom (the party
##   camera's FOLLOW_SPEED). A new view starts as the picture it splits from (the world camera's, or
##   the view that held its seats), so at first both sides of the line show the same picture; and a
##   view merging into another (or back into the one picture) eases onto it and goes only once the
##   two are the same to SETTLED of a pixel. The only thing that changes at once is the divider,
##   which grows in a whole pixel a drawn frame (DIVIDER_WIDTH of them) and shrinks out the same
##   way once the pictures meet.
##
## - **Equal panes** (the owner, 2026-11-19 and 2026-11-20; `equal`, the "Split screen: Equal"
##   setting, `SplitScreenSetting`): the same one picture while everyone fits, the same groups
##   (wizards close together share a view, with the same JOIN_REACH and LEAVE_REACH, so it does not
##   flicker at the join distance) and the same easing, but each group's view is laid on its pane
##   (`equal_panes.gd`: one group the whole screen, two the left and right halves, three or four the
##   quarters): its wizards' middle drawn at its pane's middle and its anchor easing there with its
##   picture (at most PANE_ANCHOR_STEP a frame, from where its wizards were drawn), so the bisectors
##   between the anchors settle on the panes' edges. With three groups the fourth quarter is a blank
##   (`blank_count`, `blank_anchor`): a site no view owns, which moves in from past its corner of the
##   screen over BLANK_TIME as the screen splits and back out before the last views merge, so it
##   grows and shrinks from its corner; `split_screen.gd` shows the void there. Each seat's HUD spot
##   follows its pane (`corners`, `corners_version`). Close foes are framed inside the pane. View
##   only, like the rest: the mode is this machine's, never the simulation's.
##
## A view keeps its slot (0 to VIEWS_MOST - 1) while it lives, so its drawing is the same node
## frame to frame (`slot_of`). Nothing is allocated after it is made.

const ActorsScript := preload("res://core/actors/actors.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const VoronoiCellsScript := preload("res://gameplay/feel/voronoi_cells.gd")
const PartyCameraScript := preload("res://gameplay/feel/party_camera.gd")
const CloseFoesScript := preload("res://gameplay/feel/close_foes.gd")
const EqualPanesScript := preload("res://gameplay/feel/equal_panes.gd")

const VIEWS_MOST: int = ScreenViewsScript.VIEWS_MOST
## A split view's zoom (1: the world at its own size, as one player sees it). The owner's to tune.
const SPLIT_ZOOM: float = 1.0
## The room kept between a close foe and its view's cell's edge, in screen pixels.
const FOE_MARGIN: float = 32.0
## Split views merge again once the box round the wizards fits at the widest zoom this many times
## over (each way), so a party at the edge does not split and merge frame by frame.
const MERGE_ROOM: float = 1.1
## Two wizards share a view within this far of each other (world pixels), and keep sharing it until
## this far apart.
const JOIN_REACH: float = 160.0
const LEAVE_REACH: float = 224.0
## The farthest group is drawn this far from the screen's edge (screen pixels), and two groups at
## least this far apart.
const SITE_MARGIN: float = 96.0
const SITE_GAP: float = 96.0
## The divider's full width (whole screen pixels; it grows or shrinks one a drawn frame).
const DIVIDER_WIDTH: int = 3
## Two pictures are the same when they are this close (screen pixels): a merging view goes.
const SETTLED: float = 0.05
## How far a view's anchor moves a drawn frame at most while it is not on its own place (screen
## pixels): a new view's from the one it split from, a merging view's onto the one it merges into.
const ANCHOR_STEP: float = 4.0
## A merging view's divider shrinks once its picture is this close to the one it merges into.
const SHRINK_FROM: float = 1.0
## A new view eases in over this many real seconds (its pull rising from none), so it sets off from
## the picture it split from gently rather than at the party camera's full pull.
const EASE_IN: float = 0.4
## How long the equal split's blank quarter takes to move in from past its corner, or back out (real
## seconds).
const BLANK_TIME: float = 0.4
## The most of that way it moves in one drawn frame (Smooth: at least three frames).
const BLANK_STEP_MOST: float = 1.0 / 3.0
## The most an equal pane's anchor moves a drawn frame on its way to its pane's middle (screen
## pixels; it eases with its picture, at least ANCHOR_STEP).
const PANE_ANCHOR_STEP: float = 12.0

## A slot: free, a live view (its group's), or a view merging into another.
const FREE: int = 0
const LIVE: int = 1
const MERGING: int = 2

## The views as last laid out (count, cells, transforms, anchors, seats). Read only.
var views: ScreenViewsScript = ScreenViewsScript.new()
## True while the screen is split (it merges once everyone fits again with room to spare).
var split: bool = false
## True: equal panes, a view a seat (`SplitScreenSetting.EQUAL`); false: the Voronoi split. Set by
## `set_equal`.
var equal: bool = false
## By seat: the quarter and side of the screen its HUD sits in (`EqualPanes.corner`'s spots): its
## pane's while the equal split is laid, its own corner's otherwise. Read only.
var corners: PackedInt32Array = PackedInt32Array()
## Counts the changes of `corners` (a reader compares it with the count it last saw).
var corners_version: int = 0

## By slot: FREE, LIVE or MERGING; the seats it holds; where it looks (the camera's centre, its
## shake left out) and its zoom; its divider's width (whole pixels).
var _state: PackedInt32Array = PackedInt32Array()
var _members: PackedInt32Array = PackedInt32Array()
var _centre: PackedVector2Array = PackedVector2Array()
var _zoom: PackedFloat32Array = PackedFloat32Array()
var _stage: PackedInt32Array = PackedInt32Array()
## By slot: the slot it split from (while its divider grows in) or merges into (-1: the world
## camera's picture, or none). Only the line between a view and its kin grows or shrinks; its other
## lines were its kin's, drawn already.
var _kin: PackedInt32Array = PackedInt32Array()
## By slot: real seconds since it was made (its ease-in, EASE_IN), and how much of the way to its
## aim its picture eased this frame.
var _age: PackedFloat32Array = PackedFloat32Array()
var _pull: PackedFloat32Array = PackedFloat32Array()
## By view (as laid out in `views`): its slot.
var _slot_of: PackedInt32Array = PackedInt32Array()
## By slot: the seats it held before this frame's groups were matched (where a new view starts).
var _held_before: PackedInt32Array = PackedInt32Array()
## By slot: where its anchor is drawn (screen pixels), which moves to its own place (a live view's
## group, as drawn) or, once their pictures are one, onto the anchor of the view it merges into, by
## at most ANCHOR_STEP a frame,
## so a cell is never cut at once from a picture not its own; true once it is on its own place,
## from then on following it. A new view's starts on the anchor of the view it split from.
var _shown: PackedVector2Array = PackedVector2Array()
var _anchored: PackedByteArray = PackedByteArray()
## By slot: made this frame (drawn first as the picture it split from).
var _born: PackedByteArray = PackedByteArray()
## By slot: how far a merging view's picture is from its target's (screen pixels).
var _merge_gap: PackedFloat32Array = PackedFloat32Array()
## By seat: its box's middle and its box (each seat's own body and the actor it drives).
var _point: PackedVector2Array = PackedVector2Array()
var _box: Array[Rect2] = []
## The seats with a body this frame (a bit a seat).
var _present: int = 0
## Groups this frame: by seat, its group's lowest seat (-1: none); by group (lowest seat), its
## seats, its middle and its place on the screen.
var _group_of: PackedInt32Array = PackedInt32Array()
var _group_seats: PackedInt32Array = PackedInt32Array()
var _group_middle: PackedVector2Array = PackedVector2Array()
var _group_site: PackedVector2Array = PackedVector2Array()
## By group (lowest seat): the slot that shows it.
var _group_slot: PackedInt32Array = PackedInt32Array()
var _cells: VoronoiCellsScript = VoronoiCellsScript.new()
## The foes close to this machine's wizards this frame (null: none).
var _foes: CloseFoesScript = null
## The equal split's blank quarter: which quarter it is (-1: none), how far it has moved in
## from its rest (0 out to 1 on its quarter's middle), and where its site is drawn now.
var _blank_quarter: int = -1
## The group (lowest seat) whose twin the blank is (it shows that group's picture; -1: the void).
var _blank_owner: int = -1
var _blank_in: float = 0.0
var _blank_at: Vector2 = Vector2.INF
## The equal split's panes for this frame's groups.
var _panes: EqualPanesScript = EqualPanesScript.new()
## The seats with a body that are not this machine's (a bit a seat): shown on the HUD, in no pane.
var _elsewhere: int = 0


func _init() -> void:
	_state.resize(VIEWS_MOST)
	_members.resize(VIEWS_MOST)
	_centre.resize(VIEWS_MOST)
	_zoom.resize(VIEWS_MOST)
	_stage.resize(VIEWS_MOST)
	_kin.resize(VIEWS_MOST)
	_kin.fill(-1)
	_age.resize(VIEWS_MOST)
	_pull.resize(VIEWS_MOST)
	_slot_of.resize(VIEWS_MOST)
	_held_before.resize(VIEWS_MOST)
	_shown.resize(VIEWS_MOST)
	_anchored.resize(VIEWS_MOST)
	_born.resize(VIEWS_MOST)
	_merge_gap.resize(VIEWS_MOST)
	_point.resize(ActorsScript.SEATS)
	_box.resize(ActorsScript.SEATS)
	_group_of.resize(ActorsScript.SEATS)
	_group_seats.resize(ActorsScript.SEATS)
	_group_middle.resize(ActorsScript.SEATS)
	_group_site.resize(ActorsScript.SEATS)
	_group_slot.resize(ActorsScript.SEATS)
	corners.resize(ActorsScript.SEATS)
	for seat in ActorsScript.SEATS:
		corners[seat] = EqualPanesScript.home_spot(seat)


## Every view gone at once (a new room: the world's camera jumps to it, and splits again from there).
func reset() -> void:
	for slot in VIEWS_MOST:
		_state[slot] = FREE
		_members[slot] = 0
		_stage[slot] = 0
		_kin[slot] = -1
		_shown[slot] = Vector2.INF
		_anchored[slot] = 0
		_born[slot] = 0
	split = false
	views.count = 0
	_blank_quarter = -1
	_blank_owner = -1
	_blank_in = 0.0
	_blank_at = Vector2.INF
	_set_corners(false)


## Equal panes (true) or the Voronoi split (false), from the next drawn frame. A change while split
## eases over: every anchor walks to its new place and the groups regroup as a split does.
func set_equal(on: bool) -> void:
	if on == equal:
		return
	equal = on
	for slot in VIEWS_MOST:
		_anchored[slot] = 0


## The number of blank sites now (0 or 1: the equal split's empty quarter with three seats).
func blank_count() -> int:
	return 1 if _blank_quarter >= 0 and _blank_in > 0.0 else 0


## Where blank site `blank` is drawn now (screen pixels; a site no view owns, so no view draws
## nearer it than any view's anchor).
func blank_anchor(_blank: int) -> Vector2:
	return _blank_at


## The width the cell shader is told for the divider between view `view` and the blank (whole
## pixels): twice the view's own, since the shader draws half a line a side and no view draws the
## blank's side, so the view draws the whole line; it grows in with the split, shrinks with the merge.
func blank_divider(view: int) -> int:
	if view == blank_owner_view():
		# Its own twin: one pane, no line between.
		return 0
	return _stage[_slot_of[view]] * 2


## The view whose picture the blank shows (its twin, three groups of four players; the owner,
## 2026-11-20), or -1: the blank is the void.
func blank_owner_view() -> int:
	if _blank_owner < 0 or blank_count() == 0:
		return -1
	var slot: int = _group_slot[_blank_owner] if _group_seats[_blank_owner] != 0 else -1
	if slot < 0 or _state[slot] != LIVE:
		return -1
	for view in views.count:
		if _slot_of[view] == slot:
			return view
	return -1


## The slot of view `view` (0 to `views.count` - 1).
func slot_of(view: int) -> int:
	return _slot_of[view]


## The divider's width round view `view` now (whole pixels).
func stage_of(view: int) -> int:
	return _stage[_slot_of[view]]


## The divider's width between views `a` and `b` (whole pixels): the narrower of theirs where one
## is the other's kin (split from it, or merging into it) or neither has kin (both split from or
## merging into the one picture), so a line grows in with the newer view and shrinks out with the
## one merging; any other line was there already, at its full width.
func divider_between(a: int, b: int) -> int:
	var slot_a: int = _slot_of[a]
	var slot_b: int = _slot_of[b]
	if _kin[slot_a] == slot_b or _kin[slot_b] == slot_a or (_kin[slot_a] < 0 and _kin[slot_b] < 0):
		return mini(_stage[slot_a], _stage[slot_b])
	return DIVIDER_WIDTH


## A drawn frame, `delta` real seconds on: find this machine's wizards in `table` (`seats`, a bit a
## seat; none of them in the world: everyone, as the party camera does), and lay the views out on a
## screen of `screen` pixels from the world camera `camera` (its place, zoom, limits and shake).
## With no camera nothing is split. `foes` (null: none): the enemies close to each seat's wizards,
## which each view zooms out to frame.
func step(delta: float, table: ActorsScript, seats: int, camera: Camera2D, screen: Vector2, foes: CloseFoesScript = null) -> void:
	views.screen = screen
	_foes = foes
	if camera == null or not is_instance_valid(camera) or table == null or screen.x <= 0.0 or screen.y <= 0.0:
		reset()
		return
	# Only this machine's seats split it (decision 27); with none of them in the world (a machine
	# waiting for its seat) there is one picture, which then holds everyone (the party camera).
	_find(table, seats)
	var limits := Rect2(Vector2(camera.limit_left, camera.limit_top), Vector2(camera.limit_right - camera.limit_left, camera.limit_bottom - camera.limit_top))
	var root_zoom: float = camera.zoom.x
	var root_centre: Vector2 = _clamp(camera.position, root_zoom, limits, screen)
	if camera.is_inside_tree():
		# The picture the world's camera draws now (Godot's own clamp to its limits), its shake
		# taken off: what a new view starts as and what views merging back ease onto.
		var drawn: Transform2D = camera.get_viewport().get_canvas_transform()
		root_zoom = drawn.x.x
		if root_zoom > 0.0:
			root_centre = (screen * 0.5 - drawn.origin) / root_zoom - camera.offset
	split = _wants_split(screen)
	if split:
		_group()
		_lay_sites(screen)
		_match(root_centre, root_zoom)
	else:
		for slot in VIEWS_MOST:
			if _state[slot] != FREE:
				_state[slot] = MERGING
	_step_blank(delta, screen)
	_step_corners()
	_ease(delta, root_centre, root_zoom, limits, screen)
	_publish(camera.offset, screen)


## Each seat's box (its own body and the actor it drives) and its middle, for `seats` (0: all).
func _find(table: ActorsScript, seats: int) -> void:
	_present = 0
	_elsewhere = 0
	for seat in ActorsScript.SEATS:
		var box: Rect2 = PartyCameraScript.party_box(table, 1 << seat)
		if box.size.x < 0.0:
			continue
		if seats != 0 and seats & (1 << seat) == 0:
			_elsewhere |= 1 << seat
			continue
		_box[seat] = box
		_point[seat] = box.get_center()
		_present |= 1 << seat
	for slot in VIEWS_MOST:
		_members[slot] &= _present


## Whether the box round every present seat no longer fits at the widest zoom (or, while split,
## does not fit with MERGE_ROOM to spare).
func _wants_split(screen: Vector2) -> bool:
	if _present & (_present - 1) == 0:
		return false
	var party := Rect2()
	var first: bool = true
	for seat in ActorsScript.SEATS:
		if _present & (1 << seat) == 0:
			continue
		party = _box[seat] if first else party.merge(_box[seat])
		first = false
	var need: Vector2 = party.size + Vector2.ONE * (PartyCameraScript.CAMERA_MARGIN * 2.0)
	var fit: float = minf(screen.x / need.x, screen.y / need.y)
	return fit < PartyCameraScript.MIN_ZOOM * (MERGE_ROOM if split else 1.0)


## Group the present seats: joined while within JOIN_REACH (LEAVE_REACH for two a live view holds
## together), through any chain; one group alone splits into a group a seat.
func _group() -> void:
	for seat in ActorsScript.SEATS:
		_group_of[seat] = seat if _present & (1 << seat) != 0 else -1
	for a in ActorsScript.SEATS:
		if _group_of[a] < 0:
			continue
		for b in range(a + 1, ActorsScript.SEATS):
			if _group_of[b] < 0:
				continue
			var reach: float = LEAVE_REACH if _together(a, b) else JOIN_REACH
			if _point[a].distance_to(_point[b]) < reach:
				_join(_group_of[a], _group_of[b])
	var groups: int = 0
	for seat in ActorsScript.SEATS:
		if _group_of[seat] == seat:
			groups += 1
	if groups == 1:
		for seat in ActorsScript.SEATS:
			if _group_of[seat] >= 0:
				_group_of[seat] = seat
	for seat in ActorsScript.SEATS:
		_group_seats[seat] = 0
	for seat in ActorsScript.SEATS:
		if _group_of[seat] >= 0:
			_group_seats[_group_of[seat]] |= 1 << seat
	for seat in ActorsScript.SEATS:
		if _group_seats[seat] != 0:
			_group_middle[seat] = _middle_of(_group_seats[seat])


## Seats `a` and `b` are held by one live view.
func _together(a: int, b: int) -> bool:
	var both: int = (1 << a) | (1 << b)
	for slot in VIEWS_MOST:
		if _state[slot] == LIVE and _members[slot] & both == both:
			return true
	return false


## Groups `x` and `y` (lowest seats) are one, under the lower.
func _join(x: int, y: int) -> void:
	var keep: int = mini(x, y)
	var drop: int = maxi(x, y)
	if keep == drop:
		return
	for seat in ActorsScript.SEATS:
		if _group_of[seat] == drop:
			_group_of[seat] = keep


## The middle of the box round the seats `held` (world pixels).
func _middle_of(held: int) -> Vector2:
	var box := Rect2()
	var first: bool = true
	for seat in ActorsScript.SEATS:
		if held & (1 << seat) == 0 or _present & (1 << seat) == 0:
			continue
		box = _box[seat] if first else box.merge(_box[seat])
		first = false
	return box.get_center()


## Each group's place on the screen: the groups' middles about the screen's middle, scaled by one
## factor (at most SPLIT_ZOOM) until the farthest is SITE_MARGIN from an edge.
func _lay_sites(screen: Vector2) -> void:
	if equal:
		# Equal panes: each group's at its pane's middle.
		_panes.lay(_group_seats, _elsewhere)
		for seat in ActorsScript.SEATS:
			if _group_seats[seat] != 0:
				_group_site[seat] = _panes.site(seat, screen)
		return
	var low := Vector2.INF
	var high := -Vector2.INF
	for seat in ActorsScript.SEATS:
		if _group_seats[seat] != 0:
			low = low.min(_group_middle[seat])
			high = high.max(_group_middle[seat])
	var mid: Vector2 = (low + high) * 0.5
	var reach: Vector2 = (high - low) * 0.5
	var room: Vector2 = (screen * 0.5 - Vector2.ONE * SITE_MARGIN).max(Vector2.ONE)
	var scale: float = SPLIT_ZOOM
	if reach.x > VoronoiCellsScript.EPSILON:
		scale = minf(scale, room.x / reach.x)
	if reach.y > VoronoiCellsScript.EPSILON:
		scale = minf(scale, room.y / reach.y)
	for seat in ActorsScript.SEATS:
		if _group_seats[seat] != 0:
			_group_site[seat] = screen * 0.5 + (_group_middle[seat] - mid) * scale
	# Two groups' places at least SITE_GAP apart, pushed along the line between them in the world
	# (so the divider between them keeps its way): a far third wizard squeezes the party onto the
	# screen, and two places almost on one point would swing their line round at the least step.
	var inner := Rect2(Vector2.ONE * (SITE_MARGIN * 0.5), screen - Vector2.ONE * SITE_MARGIN)
	for pass_count in 4:
		for a in ActorsScript.SEATS:
			if _group_seats[a] == 0:
				continue
			for b in range(a + 1, ActorsScript.SEATS):
				if _group_seats[b] == 0:
					continue
				var apart: float = _group_site[a].distance_to(_group_site[b])
				if apart >= SITE_GAP:
					continue
				var way: Vector2 = (_group_middle[b] - _group_middle[a]).normalized()
				if way == Vector2.ZERO:
					way = Vector2.RIGHT
				var push: Vector2 = way * ((SITE_GAP - apart) * 0.5)
				_group_site[a] = (_group_site[a] - push).clamp(inner.position, inner.end)
				_group_site[b] = (_group_site[b] + push).clamp(inner.position, inner.end)


## Give each group a slot: the one holding most of its seats (a live one before a merging one),
## else a new one, starting as the picture its seats were in (the world camera's with none). A
## live slot no group took merges into the one that holds its first seat now.
func _match(root_centre: Vector2, root_zoom: float) -> void:
	for slot in VIEWS_MOST:
		_held_before[slot] = _members[slot] if _state[slot] != FREE else 0
	var taken: int = 0
	for seat in ActorsScript.SEATS:
		_group_slot[seat] = -1
		var held: int = _group_seats[seat]
		if held == 0:
			continue
		var best: int = -1
		var best_score: int = 0
		for slot in VIEWS_MOST:
			if _state[slot] == FREE or taken & (1 << slot) != 0:
				continue
			var score: int = _bits(_members[slot] & held) * 2 + (1 if _state[slot] == LIVE else 0)
			if _members[slot] & held != 0 and score > best_score:
				best = slot
				best_score = score
		if best < 0:
			best = _open_slot(held, root_centre, root_zoom)
		if best < 0:
			continue
		taken |= 1 << best
		_group_slot[seat] = best
		if _members[best] != held or _state[best] != LIVE:
			# Its group changed (a seat joined or left, or it came back from merging): its anchor
			# walks to the group's new middle rather than jumping there.
			_anchored[best] = 0
		_state[best] = LIVE
		_members[best] = held
	for slot in VIEWS_MOST:
		if _state[slot] == LIVE and taken & (1 << slot) == 0:
			_state[slot] = MERGING


## A free slot for a new view of the seats `held`, started as the picture they were in: the slot
## that held most of them, else the world camera's. With none free, the merging view nearest done
## gives its slot up. -1 when there is none.
func _open_slot(held: int, root_centre: Vector2, root_zoom: float) -> int:
	var free: int = -1
	for slot in VIEWS_MOST:
		if _state[slot] == FREE:
			free = slot
			break
	if free < 0:
		var nearest: float = INF
		for slot in VIEWS_MOST:
			if _state[slot] == MERGING and _gap(slot) < nearest:
				nearest = _gap(slot)
				free = slot
	if free < 0:
		return -1
	var from: int = -1
	var most: int = 0
	for slot in VIEWS_MOST:
		if slot != free and _bits(_held_before[slot] & held) > most:
			most = _bits(_held_before[slot] & held)
			from = slot
	_centre[free] = _centre[from] if from >= 0 else root_centre
	_zoom[free] = _zoom[from] if from >= 0 else root_zoom
	_stage[free] = 0
	_kin[free] = from
	_age[free] = 0.0
	_born[free] = 1
	_anchored[free] = 0
	_shown[free] = _shown[from] if from >= 0 else Vector2.INF
	_members[free] = held
	_state[free] = LIVE
	return free


## Ease every view on: a live one to where its group is drawn at its place (SPLIT_ZOOM), a merging
## one onto the view now holding its first seat (or the world camera's picture); dividers grow or
## shrink a pixel; a merging view whose picture is the same as its target's, its divider gone, goes.
func _ease(delta: float, root_centre: Vector2, root_zoom: float, limits: Rect2, screen: Vector2) -> void:
	var weight: float = 1.0 - exp(-PartyCameraScript.FOLLOW_SPEED * maxf(delta, 0.0))
	for slot in VIEWS_MOST:
		if _state[slot] != LIVE:
			continue
		if _born[slot] != 0:
			# Born this frame: drawn first as the picture it splits from, eased from the next.
			_born[slot] = 0
			_pull[slot] = 0.0
			_stage[slot] = 1
			continue
		_age[slot] += maxf(delta, 0.0)
		var rise: float = clampf(_age[slot] / EASE_IN, 0.0, 1.0)
		var pull: float = weight * rise * rise * (3.0 - 2.0 * rise)
		_pull[slot] = pull
		var group: int = _group_holding(slot)
		var aim_zoom: float = lerpf(_zoom[slot], zoom_for_foes(group, screen, limits) if group >= 0 else SPLIT_ZOOM, pull)
		var aim: Vector2 = _centre[slot]
		if group >= 0:
			aim = _group_middle[group] - (_group_site[group] - screen * 0.5) / aim_zoom
		_zoom[slot] = aim_zoom
		_centre[slot] = _clamp(_centre[slot].lerp(aim, pull), aim_zoom, limits, screen)
		_stage[slot] = mini(_stage[slot] + 1, DIVIDER_WIDTH)
		if _stage[slot] == DIVIDER_WIDTH:
			_kin[slot] = -1
	for slot in VIEWS_MOST:
		if _state[slot] != MERGING:
			continue
		var into: int = _merge_target(slot)
		_kin[slot] = into
		var to_centre: Vector2 = _centre[into] if into >= 0 else root_centre
		var to_zoom: float = _zoom[into] if into >= 0 else root_zoom
		_zoom[slot] = lerpf(_zoom[slot], to_zoom, weight)
		_centre[slot] = _clamp(_centre[slot].lerp(to_centre, weight), _zoom[slot], limits, screen)
		var gap: float = _picture_gap(_centre[slot], _zoom[slot], to_centre, to_zoom, screen)
		_merge_gap[slot] = gap
		if gap < SHRINK_FROM:
			_stage[slot] = maxi(_stage[slot] - 1, 0)
		var on_target: bool = into < 0 or _shown[slot].distance_to(_shown[into]) <= VoronoiCellsScript.MIN_GAP * 2.0
		# Back into the one picture only once the blank quarter has moved out (it is drawn while
		# any view is).
		var blank_out: bool = into >= 0 or _blank_in <= 0.0
		if _stage[slot] == 0 and gap < SETTLED and on_target and blank_out:
			if into >= 0:
				# Its seats are its target's alone now: that view's anchor walks to them.
				_anchored[into] = 0
			_state[slot] = FREE
			_members[slot] = 0
			_kin[slot] = -1


## The zoom group `group`'s view frames its close foes at: SPLIT_ZOOM while they are drawn inside its
## cell with FOE_MARGIN to spare, else lower, down to the party camera's MIN_ZOOM. The cell is where
## the screen is nearer the group's place than any other group's, within the screen; the view zooms
## about the group's middle drawn at its place. Never wider than `limits` (the world camera's; none:
## no bound) allow: a picture past them would be pushed off its group's place.
func zoom_for_foes(group: int, screen: Vector2, limits: Rect2 = Rect2()) -> float:
	var zoom: float = SPLIT_ZOOM
	if _foes == null or _foes.count == 0:
		return zoom
	var site: Vector2 = _group_site[group]
	var seats: int = _group_seats[group]
	for i in _foes.count:
		if _foes.seats_of[i] & seats == 0:
			continue
		var way: Vector2 = _foes.at[i] - _group_middle[group]
		if way.length_squared() < 1.0:
			continue
		# The screen's four edges, then the line half way to each other group's place.
		zoom = _fit_along(zoom, way, Vector2.LEFT, site.x)
		zoom = _fit_along(zoom, way, Vector2.RIGHT, screen.x - site.x)
		zoom = _fit_along(zoom, way, Vector2.UP, site.y)
		zoom = _fit_along(zoom, way, Vector2.DOWN, screen.y - site.y)
		for other in ActorsScript.SEATS:
			if other == group or _group_seats[other] == 0:
				continue
			var apart: Vector2 = _group_site[other] - site
			if apart.length_squared() < 1.0:
				continue
			zoom = _fit_along(zoom, way, apart.normalized(), apart.length() * 0.5)
		if equal and split:
			# The empty quarter's edge, where it settles.
			var blank: Vector2 = _panes.blank_site(screen) - site
			if blank.is_finite() and blank.length_squared() >= 1.0:
				zoom = _fit_along(zoom, way, blank.normalized(), blank.length() * 0.5)
	var widest: float = PartyCameraScript.MIN_ZOOM
	if limits.has_area() and limits.size.x < PartyCameraScript.LIMIT_UNSET and limits.size.y < PartyCameraScript.LIMIT_UNSET:
		widest = maxf(widest, maxf(screen.x / limits.size.x, screen.y / limits.size.y))
	return clampf(zoom, minf(widest, SPLIT_ZOOM), SPLIT_ZOOM)


## `zoom`, lowered so a point `way` from the place (drawn `way` × zoom from it) stays FOE_MARGIN
## inside `room` of it along `normal`.
static func _fit_along(zoom: float, way: Vector2, normal: Vector2, room: float) -> float:
	var reach: float = way.dot(normal)
	if reach <= 0.0:
		return zoom
	return minf(zoom, maxf(room - FOE_MARGIN, 0.0) / reach)


## The equal split's blank quarter moved on: in from its rest while split with three seats, out while
## not (or before it moves to another quarter), at most BLANK_STEP_MOST of the way a drawn frame.
func _step_blank(delta: float, screen: Vector2) -> void:
	var want: int = -1
	var want_owner: int = -1
	if equal and split:
		want = _panes.blank_quarter
		if _panes.twin_group >= 0:
			want = _panes.twin_quarter
			want_owner = _panes.twin_group
	var step: float = minf(maxf(delta, 0.0) / BLANK_TIME, BLANK_STEP_MOST)
	if want != _blank_quarter or want_owner != _blank_owner:
		# Another quarter, or the void turning a pair's twin (or back): out first, then in.
		_blank_in = maxf(_blank_in - step, 0.0)
		if _blank_in <= 0.0:
			_blank_quarter = want
			_blank_owner = want_owner
	elif want >= 0:
		_blank_in = minf(_blank_in + step, 1.0)
	if _blank_quarter < 0:
		_blank_at = Vector2.INF
		return
	# Between its rest and its own quarter's middle, going in, out or turning back, so it never jumps.
	var rest: Vector2 = EqualPanesScript.blank_rest(_blank_quarter, screen)
	var site: Vector2 = EqualPanesScript.quarter_site(_blank_quarter, screen)
	var t: float = _blank_in * _blank_in * (3.0 - 2.0 * _blank_in)
	_blank_at = rest.lerp(site, t)


## Each seat's HUD spot this frame: its pane's while split on equal panes, else its own corner's.
func _step_corners() -> void:
	_set_corners(equal and split)


## `corners` the panes' spots (`laid`) or every seat's own corner's, counted when they change.
func _set_corners(laid: bool) -> void:
	var changed: bool = false
	for seat in ActorsScript.SEATS:
		var spot: int = _panes.corner[seat] if laid else EqualPanesScript.home_spot(seat)
		if spot != corners[seat]:
			corners[seat] = spot
			changed = true
	if changed:
		corners_version += 1


## The quarter of the equal split's blank now (-1: none).
func blank_quarter() -> int:
	return _blank_quarter if blank_count() > 0 else -1


## The zoom the live views draw at now (the first's; SPLIT_ZOOM with none), for the void view.
func view_zoom() -> float:
	return views.to_screen[0].x.x if views.count > 0 else SPLIT_ZOOM


## The equal panes as last laid (for tests).
func panes() -> EqualPanesScript:
	return _panes


## The group (lowest seat) live slot `slot` shows, or -1.
func _group_holding(slot: int) -> int:
	for seat in ActorsScript.SEATS:
		if _group_seats[seat] != 0 and _group_slot[seat] == slot:
			return seat
	return -1


## The live slot merging slot `slot` eases onto (the one holding its first seat), or -1: the world
## camera's picture.
func _merge_target(slot: int) -> int:
	if not split:
		return -1
	var held: int = _members[slot]
	for seat in ActorsScript.SEATS:
		if held & (1 << seat) == 0:
			continue
		for other in VIEWS_MOST:
			if other != slot and _state[other] == LIVE and _members[other] & (1 << seat) != 0:
				return other
	# Its seats are gone: the live view nearest its picture.
	var nearest: int = -1
	var gap: float = INF
	for other in VIEWS_MOST:
		if other != slot and _state[other] == LIVE and _centre[other].distance_to(_centre[slot]) < gap:
			gap = _centre[other].distance_to(_centre[slot])
			nearest = other
	return nearest


## How far merging slot `slot`'s picture is from its target's (screen pixels; 0 for a slot not merging).
func _gap(slot: int) -> float:
	var into: int = _merge_target(slot)
	if into < 0:
		return 0.0
	return _picture_gap(_centre[slot], _zoom[slot], _centre[into], _zoom[into], views.screen)


## How far apart two pictures are on screen (pixels): their centres apart, and their zooms' gap at
## the screen's corner.
static func _picture_gap(a: Vector2, a_zoom: float, b: Vector2, b_zoom: float, screen: Vector2) -> float:
	return a.distance_to(b) * maxf(a_zoom, b_zoom) + absf(a_zoom - b_zoom) / maxf(minf(a_zoom, b_zoom), 0.0001) * screen.length() * 0.5


## Write `views`: a view a used slot (in slot order), its transform (the shake `offset` added), its
## anchor (where its seats' middle is drawn, the shake left out; pushed MIN_GAP apart) and its cell.
func _publish(offset: Vector2, screen: Vector2) -> void:
	var count: int = 0
	for slot in VIEWS_MOST:
		if _state[slot] == FREE:
			continue
		var zoom: float = _zoom[slot]
		var transform := Transform2D(0.0, Vector2(zoom, zoom), 0.0, screen * 0.5 - (_centre[slot] + offset) * zoom)
		var held: int = _members[slot]
		var own: Vector2 = screen * 0.5
		var on_pane: bool = equal and _state[slot] == LIVE and _group_holding(slot) >= 0
		# A live view's anchor leaves out the seats a view merging into it still holds: it moves to
		# its whole group's middle once that view is gone, never across it.
		var placed: int = held & ~_merging_into(slot) if _state[slot] == LIVE else held
		if placed == 0:
			placed = held
		if placed != 0:
			own = screen * 0.5 + (_middle_of(placed) - _centre[slot]) * zoom
		var anchor: Vector2 = _pane_anchor(slot, own, screen) if on_pane else _anchor_of(slot, own)
		views.set_view(count, held, transform, anchor)
		_slot_of[count] = slot
		count += 1
	views.count = count
	_apart(count)
	_cells.fill(views, _blank_at if blank_count() > 0 else Vector2.INF, blank_owner_view())


## The seats held by the views merging into live slot `slot`.
func _merging_into(slot: int) -> int:
	var held: int = 0
	for other in VIEWS_MOST:
		if other != slot and _state[other] == MERGING and _merge_target(other) == slot:
			held |= _members[other]
	return held


## Where slot `slot`'s anchor is drawn this frame, its own place being `own`: on it once it got
## there; else moved toward it (a live view) or onto its target's anchor (a merging one) by at most
## ANCHOR_STEP.
func _anchor_of(slot: int, own: Vector2) -> Vector2:
	var aim: Vector2 = own
	if _state[slot] == MERGING:
		var into: int = _merge_target(slot)
		_anchored[slot] = 0
		# Onto its target's anchor only once the two pictures are one: the line between them may
		# then swing anyhow (the same picture either side), and its lines to the others move on.
		if into >= 0 and _shown[into].is_finite() and _merge_gap[slot] < SHRINK_FROM:
			aim = _shown[into]
	elif _anchored[slot] != 0 or not _shown[slot].is_finite():
		_shown[slot] = own
		_anchored[slot] = 1
		return own
	_shown[slot] = _shown[slot].move_toward(aim, ANCHOR_STEP)
	if _state[slot] == LIVE and _shown[slot].distance_to(own) < 0.5:
		_anchored[slot] = 1
	return _shown[slot]


## Where live slot `slot`'s anchor is drawn this frame on equal panes: from where its wizard was
## drawn (`drawn`, kept to the screen) when it was made, onto its pane's middle, eased as its
## picture is (its pull this frame, so the cut follows the picture it cuts) and moving at least
## ANCHOR_STEP and at most PANE_ANCHOR_STEP a frame.
func _pane_anchor(slot: int, drawn: Vector2, screen: Vector2) -> Vector2:
	var group: int = _group_holding(slot)
	var site: Vector2 = _group_site[group]
	if group == _blank_owner and _blank_quarter >= 2:
		# A pair with a twin: cut as its half's top quarter, eased there as the twin comes in, so the
		# twin's site and its own cut the half from the others as two quarters do.
		var t: float = _blank_in * _blank_in * (3.0 - 2.0 * _blank_in)
		site = site.lerp(EqualPanesScript.quarter_site(_blank_quarter - 2, screen), t)
	if not _shown[slot].is_finite():
		_shown[slot] = drawn.clamp(Vector2.ZERO, screen)
	var step: float = clampf(_shown[slot].distance_to(site) * _pull[slot], ANCHOR_STEP, PANE_ANCHOR_STEP)
	_shown[slot] = _shown[slot].move_toward(site, step)
	_anchored[slot] = 1 if _shown[slot] == site else 0
	return _shown[slot]


## Anchors closer than MIN_GAP to an earlier one moved off it, each toward its own side.
func _apart(count: int) -> void:
	for i in count:
		var away := Vector2.from_angle(TAU * float(i) / float(maxi(count, 1))) * VoronoiCellsScript.MIN_GAP
		var tries: int = 0
		var moved: bool = true
		while moved and tries < count * 4:
			moved = false
			tries += 1
			for j in i:
				if views.anchor[i].distance_to(views.anchor[j]) < VoronoiCellsScript.MIN_GAP:
					views.set_view(i, views.seats[i], views.to_screen[i], views.anchor[i] + away)
					moved = true


## `centre` moved so a picture at `zoom` stays inside `limits` (as the party camera keeps it).
static func _clamp(centre: Vector2, zoom: float, limits: Rect2, screen: Vector2) -> Vector2:
	var half: Vector2 = screen * (0.5 / maxf(zoom, 0.0001))
	var low: Vector2 = limits.position + half
	var high: Vector2 = limits.end - half
	var x: float = clampf(centre.x, low.x, high.x) if low.x <= high.x else limits.get_center().x
	var y: float = clampf(centre.y, low.y, high.y) if low.y <= high.y else limits.get_center().y
	return Vector2(x, y)


static func _bits(mask: int) -> int:
	var n: int = 0
	while mask != 0:
		mask &= mask - 1
		n += 1
	return n
