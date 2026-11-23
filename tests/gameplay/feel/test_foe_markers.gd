extends "res://tests/support/suite.gd"
## The markers at a view's edge for a fight's foes out of it (gameplay/feel/foe_markers.gd; the
## owner, 2026-11-23): none outside a sealed fight, none for a foe the seat's view shows, one at the
## edge towards a foe out of view, pointing at it, in the seat's own cell while split; a marker
## grows in and shrinks out by whole pixels over at least three frames (docs/STYLE.md, "Smooth");
## a view shows only so many, and never two on one spot; a frame allocates nothing. Places are
## screen pixels.
const MarkersScript := preload("res://gameplay/feel/foe_markers.gd")
const TeammateMarkersScript := preload("res://gameplay/feel/teammate_markers.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const VoronoiCellsScript := preload("res://gameplay/feel/voronoi_cells.gd")

## This machine's picture: one screen from the world's corner, at zoom 1 (world pixels are screen
## pixels, so the numbers below read as both).
const PICTURE: Rect2 = Rect2(0.0, 0.0, 640.0, 360.0)
const MIDDLE: Vector2 = Vector2(320.0, 180.0)
## The fight's room (a place of the grid, sealed by `before_each`) and one beside it, not sealed.
const ROOM: Rect2 = Rect2(-2048.0, -2048.0, 4096.0, 4096.0)
const NEXT_ROOM: Rect2 = Rect2(3000.0, -2048.0, 4096.0, 4096.0)

var _table: ActorsScript
var _markers: MarkersScript
var _grid: RoomGrid
var _room: int = -1
var _next_room: int = -1


func before_each() -> void:
	_table = own(ActorsScript.new()) as ActorsScript
	root.add_child(_table)
	_markers = own(MarkersScript.new()) as MarkersScript
	root.add_child(_markers)
	_grid = RoomGrid.new()
	_grid.size_to(Rect2(-4096.0, -4096.0, 12288.0, 8192.0))
	_room = _grid.add_place(ROOM)
	_next_room = _grid.add_place(NEXT_ROOM)
	_grid.set_sealed(_room, true)


## One picture showing `picture` (world pixels) at `zoom`, seat 0's.
static func _one(picture: Rect2 = PICTURE, zoom: float = 1.0) -> ScreenViewsScript:
	var views := ScreenViewsScript.new()
	views.set_single(picture.size * zoom, Transform2D(0.0, Vector2(zoom, zoom), 0.0, -picture.position * zoom), 0b0001)
	return views


## Two views side by side (a split), each a half of the screen at zoom 1: the left one (seat 0's)
## shows the world round `left` and the right one (seat 1's) the world round `right`.
static func _two(left: Vector2, right: Vector2) -> ScreenViewsScript:
	var views := ScreenViewsScript.new()
	views.screen = PICTURE.size
	views.count = 2
	var anchors: Array[Vector2] = [Vector2(160.0, 180.0), Vector2(480.0, 180.0)]
	var worlds: Array[Vector2] = [left, right]
	for view in 2:
		views.set_view(view, 1 << view, Transform2D(0.0, Vector2.ONE, 0.0, anchors[view] - worlds[view]), anchors[view])
	VoronoiCellsScript.new().fill(views)
	return views


## Seat `seat`'s own wizard at `at`.
func _wizard(at: Vector2, seat: int) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.position = at
	var id: int = _table.open(ActorsScript.TEAM_WIZARDS, seat, seat)
	_table.set_node(id, node)
	_table.set_home(id, seat)
	return node


## An enemy at `at` (`boss`: a boss, by its data).
func _foe(at: Vector2, boss: bool = false) -> Node2D:
	var node: Node2D = Actor.new() if boss else Node2D.new()
	own(node)
	if boss:
		var data := EnemyBase.new()
		data.boss = true
		(node as Actor).data = data
	root.add_child(node)
	node.position = at
	_table.set_node(_table.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY), node)
	return node


## `frames` drawn frames, each a look's time on (so a marker changes its look every frame).
func _step(views: ScreenViewsScript, frames: int = 1, seats_here: int = 0b0001) -> void:
	for i in frames:
		_markers.step(MarkersScript.STAGE_SECONDS, _table, _grid, seats_here, views)


## Long enough for every marker to have grown in or shrunk out.
func _settle(views: ScreenViewsScript, seats_here: int = 0b0001) -> void:
	_step(views, MarkersScript.STAGES + 1, seats_here)


func test_a_foe_of_the_fight_out_of_view_gets_a_marker_on_the_edge_towards_it() -> void:
	_wizard(MIDDLE, 0)
	var foe: Node2D = _foe(Vector2(1500.0, 180.0))
	_settle(_one())
	check_equal(_markers.count, 1, "one foe is out of the picture")
	if _markers.count != 1:
		return
	check_equal(_markers.position_of(0), Vector2(640.0 - MarkersScript.INSET, 180.0), "at the right edge, level with it")
	check_equal(_markers.way_of(0), Vector2.RIGHT, "pointing at it")
	check_equal(_markers.view_id_of(0), 0, "in seat 0's view")
	check_equal(_markers.stage_of(0), MarkersScript.STAGES, "whole")
	check(not _markers.is_boss(0), "no boss")
	check_equal(_table.node_of(_markers.foe_of(0)), foe, "that foe's")


## A marker follows its foe along the edge; where its place leaps (the foe teleported) it never
## crosses the picture: the one there shrinks out where it is and one grows in at the new place.
func test_a_marker_moves_along_the_edge_and_never_across_the_picture() -> void:
	_wizard(MIDDLE, 0)
	var foe: Node2D = _foe(Vector2(1500.0, 180.0))
	var views: ScreenViewsScript = _one()
	_settle(views)
	# Walking round the wizard, a quarter turn: one marker, always INSET inside the edge.
	for i in 60:
		foe.position = MIDDLE + Vector2.from_angle(-PI * 0.5 * float(i + 1) / 60.0) * 1180.0
		_step(views)
		check(_markers.count == 1 and _on_inset_edge(_markers.position_of(0)), "walking round (frame %d): one marker, on the edge (%s)" % [i, _markers.position_of(0) if _markers.count > 0 else Vector2.INF])
		if _markers.count != 1 or not _on_inset_edge(_markers.position_of(0)):
			return
	check(_markers.position_of(0).is_equal_approx(Vector2(320.0, MarkersScript.INSET)) and _markers.way_of(0).is_equal_approx(Vector2.UP), "now at the top edge, pointing up")
	# A leap to the far side.
	foe.position = Vector2(320.0, 1500.0)
	var crossed: bool = false
	for i in MarkersScript.STAGES + 2:
		_step(views)
		for at in _markers.count:
			crossed = crossed or not _on_inset_edge(_markers.position_of(at))
		if i == 0:
			check_equal(_markers.count, 2, "the foe leapt below: the old marker shrinking at the top, a new one growing at the bottom")
	check(not crossed, "no marker stood anywhere but on the edge")
	check(_markers.count == 1 and _markers.position_of(0).is_equal_approx(Vector2(320.0, 360.0 - MarkersScript.INSET)), "one marker, at the bottom edge")


## True for a point INSET inside the picture's edge (on the line a marker of the one picture stands on).
static func _on_inset_edge(at: Vector2) -> bool:
	var inner: Rect2 = PICTURE.grow(-MarkersScript.INSET)
	return inner.grow(0.01).has_point(at) and not inner.grow(-0.01).has_point(at)


func test_a_zoomed_out_picture_keeps_the_marker_as_far_from_its_edge_on_screen() -> void:
	_wizard(Vector2(500.0, 281.25), 0)
	_foe(Vector2(1900.0, 225.0))
	# The game's default zoom, 0.8: 800 x 450 of the world on the 640 x 360 screen.
	_settle(_one(Rect2(0.0, 0.0, 800.0, 450.0), 0.8))
	check_equal(_markers.count, 1, "a marker")
	if _markers.count == 1:
		check(_markers.position_of(0).is_equal_approx(Vector2(640.0 - MarkersScript.INSET, 180.0)), "as far from the screen's edge at zoom 0.8 (%s)" % _markers.position_of(0))


func test_no_marker_for_a_foe_in_view() -> void:
	_wizard(MIDDLE, 0)
	_foe(Vector2(500.0, 100.0))
	_foe(Vector2(40.0, 300.0))
	_settle(_one())
	check_equal(_markers.count, 0, "both foes are in the picture")


func test_no_marker_outside_a_sealed_fight() -> void:
	_wizard(MIDDLE, 0)
	_foe(Vector2(1500.0, 180.0))
	_grid.set_sealed(_room, false)
	_settle(_one())
	check_equal(_markers.count, 0, "the room is not sealed: no fight, no marker")
	_markers.step(1.0, _table, null, 0b0001, _one())
	check_equal(_markers.count, 0, "no grid: none")
	_markers.step(1.0, _table, RoomGrid.new(), 0b0001, _one())
	check_equal(_markers.count, 0, "a world with no places (the hub, a single room): none")
	_grid.set_sealed(_room, true)
	_settle(_one(), 0)
	check_equal(_markers.count, 0, "no seat played here: none")
	_settle(_one())
	check_equal(_markers.count, 1, "sealed, a seat here: a marker")


func test_no_marker_for_a_foe_in_another_room() -> void:
	_wizard(MIDDLE, 0)
	_foe(NEXT_ROOM.position + Vector2(200.0, 2228.0))
	_settle(_one())
	check_equal(_markers.count, 0, "a foe of the next room, which is not sealed: none")
	_grid.set_sealed(_next_room, true)
	_settle(_one())
	check_equal(_markers.count, 0, "nor when that room has a fight of its own: no wizard of this machine is in it")


func test_a_wizard_or_a_wizards_puppet_gets_none_and_the_driven_actors_room_counts() -> void:
	_wizard(MIDDLE, 0)
	_wizard(Vector2(1500.0, 180.0), 1)
	_settle(_one())
	check_equal(_markers.count, 0, "a wizard out of view is not a foe (the teammate markers' job)")
	# Seat 0's own body leaves the fight, but the actor it drives stands in it.
	var puppet: Node2D = own(Node2D.new()) as Node2D
	root.add_child(puppet)
	puppet.position = Vector2(300.0, 180.0)
	var id: int = _table.open(ActorsScript.TEAM_WIZARDS, 0)
	_table.set_node(id, puppet)
	_table.set_driver(id, ActorsScript.TEAM_WIZARDS, 0)
	(_table.node_of(_table.home_of_seat(0)) as Node2D).position = NEXT_ROOM.get_center()
	_foe(Vector2(1500.0, 180.0))
	_settle(_one())
	check_equal(_markers.count, 1, "the fight the seat's driven actor stands in is marked")


## It grows in and shrinks out by whole pixels, a look a frame at the fastest, never in one jump.
func test_a_marker_grows_in_and_shrinks_out_over_three_looks() -> void:
	_wizard(MIDDLE, 0)
	var foe: Node2D = _foe(Vector2(1500.0, 180.0))
	var views: ScreenViewsScript = _one()
	check(MarkersScript.STAGES >= 3, "at least three looks between none and whole")
	var last: Vector2 = Vector2.ZERO
	for stage in range(1, MarkersScript.STAGES + 1):
		_step(views)
		check(_markers.count == 1 and _markers.stage_of(0) == stage, "frame %d in: look %d" % [stage, stage])
		var size: Vector2 = MarkersScript.size_at(stage, false)
		check(size == size.round() and size.x > last.x and size.y > last.y, "look %d is bigger by whole pixels (%s)" % [stage, size])
		last = size
	_step(views, 5)
	check_equal(_markers.stage_of(0), MarkersScript.STAGES, "then whole, and it stays")
	var at: Vector2 = _markers.position_of(0)
	foe.position = Vector2(400.0, 180.0)
	for stage in range(MarkersScript.STAGES - 1, 0, -1):
		_step(views)
		check(_markers.count == 1 and _markers.stage_of(0) == stage, "its foe in view: look %d on the way out" % stage)
		check_equal(_markers.position_of(0), at, "where it was while it shrinks")
	_step(views)
	check_equal(_markers.count, 0, "then gone")
	check(MarkersScript.size_at(MarkersScript.STAGES, false).x < TeammateMarkersScript.LENGTH, "smaller than a teammate's marker")


## However fast the frames are drawn, a look lasts STAGE_SECONDS; and one wanted again before it
## is gone grows back from the look it had.
func test_looks_are_paced_by_real_time_and_turn_back() -> void:
	_wizard(MIDDLE, 0)
	var foe: Node2D = _foe(Vector2(1500.0, 180.0))
	var views: ScreenViewsScript = _one()
	var quick: float = MarkersScript.STAGE_SECONDS / 4.0
	_markers.step(MarkersScript.STAGE_SECONDS, _table, _grid, 0b0001, views)
	check(_markers.count == 1 and _markers.stage_of(0) == 1, "the first look")
	for i in 3:
		_markers.step(quick, _table, _grid, 0b0001, views)
		check_equal(_markers.stage_of(0), 1, "three quick frames later: the same look")
	_markers.step(quick, _table, _grid, 0b0001, views)
	check_equal(_markers.stage_of(0), 2, "a look's time on: the next")
	foe.position = Vector2(400.0, 180.0)
	_step(views)
	check(_markers.count == 1 and _markers.stage_of(0) == 1, "its foe in view: one look smaller")
	foe.position = Vector2(1500.0, 180.0)
	_step(views)
	check(_markers.count == 1 and _markers.stage_of(0) == 2, "out of view again: it grows back from there")


## A foe walking along the edge does not blink its marker on and off.
func test_a_marker_comes_once_well_out_and_goes_once_well_in() -> void:
	_wizard(MIDDLE, 0)
	var foe: Node2D = _foe(Vector2(640.0 + MarkersScript.OUT_BY - 2.0, 180.0))
	var views: ScreenViewsScript = _one()
	_settle(views)
	check_equal(_markers.count, 0, "just past the edge: not yet")
	foe.position.x = 640.0 + MarkersScript.OUT_BY + 2.0
	_settle(views)
	check_equal(_markers.count, 1, "well past it: a marker")
	foe.position.x = 640.0 - MarkersScript.IN_BY + 2.0
	_settle(views)
	check(_markers.count == 1 and _markers.stage_of(0) == MarkersScript.STAGES, "back at the edge: kept, whole")
	foe.position.x = 640.0 - MarkersScript.IN_BY - 2.0
	_settle(views)
	check_equal(_markers.count, 0, "well inside: gone")


## Split: a marker sits in its seat's own cell, at the divider when its foe is that way; the other
## seat, in no fight, has none.
func test_split_a_marker_sits_in_its_seats_own_cell() -> void:
	_wizard(Vector2(0.0, 0.0), 0)
	_wizard(NEXT_ROOM.get_center(), 1)
	_foe(Vector2(800.0, 0.0))
	var views: ScreenViewsScript = _two(Vector2(0.0, 0.0), NEXT_ROOM.get_center())
	_settle(views, 0b0011)
	check_equal(_markers.count, 1, "one marker: seat 1's room has no fight")
	if _markers.count != 1:
		return
	check_equal(_markers.view_id_of(0), 0, "seat 0's")
	check(views.cell_holds(0, _markers.position_of(0), 0.0), "in the left view's cell (%s)" % _markers.position_of(0))
	check(is_equal_approx(_markers.position_of(0).x, 320.0 - MarkersScript.INSET), "at the divider, INSET inside (%s)" % _markers.position_of(0))
	check_equal(_markers.way_of(0), Vector2.RIGHT, "pointing at its foe")
	# A fight in seat 1's room too: its foe's marker in seat 1's cell, seat 0's as it was.
	_grid.set_sealed(_next_room, true)
	_foe(NEXT_ROOM.get_center() + Vector2(0.0, 900.0))
	_settle(views, 0b0011)
	check_equal(_markers.count, 2, "a marker a fight")
	for at in _markers.count:
		var view: int = views.view_of_seat(_markers.view_id_of(at))
		check(views.cell_holds(view, _markers.position_of(at), 0.0), "seat %d's marker is in its own cell (%s)" % [_markers.view_id_of(at), _markers.position_of(at)])
		if _markers.view_id_of(at) == 1:
			check(_markers.position_of(at).is_equal_approx(Vector2(480.0, 360.0 - MarkersScript.INSET)), "seat 1's at the bottom edge under its wizard (%s)" % _markers.position_of(at))
	# Only seat 0 is played here: seat 1's view is not this machine's to mark.
	_settle(views, 0b0001)
	check(_markers.count == 1 and _markers.view_id_of(0) == 0, "seat 0 alone here: its marker alone")


## Two seats in one fight, a view each: a foe out of both gets a marker in each view; one that a
## seat's own view shows gets none there, whatever the other view shows.
func test_split_each_view_marks_what_it_does_not_show() -> void:
	_wizard(Vector2(-1000.0, 0.0), 0)
	_wizard(Vector2(1000.0, 0.0), 1)
	var foe: Node2D = _foe(Vector2(0.0, 1200.0))
	var views: ScreenViewsScript = _two(Vector2(-1000.0, 0.0), Vector2(1000.0, 0.0))
	_settle(views, 0b0011)
	check_equal(_markers.count, 2, "out of both views: a marker in each")
	foe.position = Vector2(1040.0, 20.0)
	_settle(views, 0b0011)
	check(_markers.count == 1 and _markers.view_id_of(0) == 0, "beside seat 1: only seat 0's view marks it")


## Many foes (decided while building): at most MOST_A_VIEW markers a view and BOSSES_A_VIEW more
## for bosses; a marker keeps its slot, and a freed one goes to a foe that had none.
func test_a_view_shows_only_so_many_and_a_boss_always() -> void:
	_wizard(MIDDLE, 0)
	var foes: Array[Node2D] = []
	for i in 10:
		foes.append(_foe(MIDDLE + Vector2.from_angle(TAU * float(i) / 10.0 + 0.2) * 1500.0))
	var views: ScreenViewsScript = _one()
	_settle(views)
	check_equal(_markers.count, MarkersScript.MOST_A_VIEW, "ten foes out of view: the most a view shows")
	var first: Array[int] = []
	for at in _markers.count:
		first.append(_markers.foe_of(at))
	_step(views, 30)
	var kept: bool = _markers.count == first.size()
	for at in mini(_markers.count, first.size()):
		kept = kept and _markers.foe_of(at) == first[at]
	check(kept, "the same foes' half a second on: no swapping")
	_foe(MIDDLE + Vector2(0.0, -1500.0), true)
	_settle(views)
	check_equal(_markers.count, MarkersScript.MOST_A_VIEW + 1, "a boss has a marker all the same")
	var bosses: int = 0
	for at in _markers.count:
		if _markers.is_boss(at):
			bosses += 1
			check(MarkersScript.size_at(_markers.stage_of(at), true).x > MarkersScript.size_at(MarkersScript.STAGES, false).x, "and a larger one")
	check_equal(bosses, 1, "one boss's")
	# A marked foe walks into view: its slot goes to a foe that had none.
	var gone: int = first[0]
	(_table.node_of(gone) as Node2D).position = MIDDLE + Vector2(40.0, 0.0)
	_settle(views)
	_settle(views)
	check_equal(_markers.count, MarkersScript.MOST_A_VIEW + 1, "as many again")
	for at in _markers.count:
		check(_markers.foe_of(at) != gone, "none for the foe in view")


## Markers of one view never pile up: foes the same way share one, and part again when they do.
func test_foes_the_same_way_share_a_marker() -> void:
	_wizard(MIDDLE, 0)
	_foe(Vector2(1500.0, 180.0))
	var other: Node2D = _foe(Vector2(1500.0, 200.0))
	var views: ScreenViewsScript = _one()
	_settle(views)
	check_equal(_markers.count, 1, "two foes the same way: one marker")
	other.position = Vector2(1500.0, 1200.0)
	_settle(views)
	check_equal(_markers.count, 2, "apart: one each")
	if _markers.count == 2:
		check(_markers.position_of(0).distance_to(_markers.position_of(1)) >= MarkersScript.APART, "well apart (%s, %s)" % [_markers.position_of(0), _markers.position_of(1)])
	# Walking back beside the first: its marker comes along the edge and shrinks out into the first's.
	var nearest: float = INF
	for i in 120:
		other.position.y = maxf(other.position.y - 12.0, 190.0)
		_step(views)
		if _markers.count == 2 and not _markers.is_going(0) and not _markers.is_going(1):
			nearest = minf(nearest, _markers.position_of(0).distance_to(_markers.position_of(1)))
	check_equal(_markers.count, 1, "the same way again: one marker")
	check(nearest >= MarkersScript.MERGE_GAP, "two wanted markers never sat on one spot (%.1f px apart at the nearest)" % nearest)


## A boss the same way as a marked foe still gets its marker, and the lesser foe's gives way.
func test_a_boss_takes_its_place_beside_a_marked_foe() -> void:
	_wizard(MIDDLE, 0)
	_foe(Vector2(1500.0, 180.0))
	var views: ScreenViewsScript = _one()
	_settle(views)
	check(_markers.count == 1 and not _markers.is_boss(0), "a foe's marker first")
	_foe(Vector2(1500.0, 185.0), true)
	_settle(views)
	_settle(views)
	check(_markers.count == 1 and _markers.is_boss(0), "a boss the same way: its marker, the foe's gone into it (%d markers)" % _markers.count)
	if _markers.count == 1:
		check_equal(_markers.stage_of(0), MarkersScript.STAGES, "whole")


## A view with no cell yet (fewer than three corners) has no edge to sit at: no marker.
func test_a_view_with_no_cell_gets_no_marker() -> void:
	_wizard(MIDDLE, 0)
	_foe(Vector2(1500.0, 180.0))
	var views: ScreenViewsScript = _one()
	views.set_corners(0, 0)
	_settle(views)
	check_equal(_markers.count, 0, "no cell: no marker")


## An actor id used again while its old marker lives (a boss dead, a stray made with its id) is
## another foe: the old marker shrinks out and the new foe's is its own kind.
func test_a_reused_actor_id_is_a_new_marker() -> void:
	_wizard(MIDDLE, 0)
	var boss: Node2D = _foe(Vector2(1500.0, 180.0), true)
	var views: ScreenViewsScript = _one()
	_settle(views)
	check(_markers.count == 1 and _markers.is_boss(0), "a boss's marker")
	var id: int = _markers.foe_of(0)
	_table.close(id)
	boss.position = Vector2(-5000.0, -5000.0)
	var stray := own(Node2D.new()) as Node2D
	root.add_child(stray)
	stray.position = Vector2(1500.0, 180.0)
	var again: int = _table.open(ActorsScript.TEAM_ENEMIES, ActorsScript.RAMP_ENEMY)
	_table.set_node(again, stray)
	check_equal(again, id, "the table hands the closed id out again")
	if again != id:
		return
	_step(views)
	for at in _markers.count:
		if _markers.is_boss(at):
			check(_markers.is_going(at), "the dead boss's marker is shrinking out")
	_settle(views)
	check(_markers.count == 1 and not _markers.is_boss(0), "then one marker, a plain foe's")


func test_a_dead_foes_marker_shrinks_out() -> void:
	_wizard(MIDDLE, 0)
	_foe(Vector2(1500.0, 180.0))
	var views: ScreenViewsScript = _one()
	_settle(views)
	check_equal(_markers.count, 1, "a marker")
	_table.close(_markers.foe_of(0))
	_step(views)
	check(_markers.count == 1 and _markers.stage_of(0) == MarkersScript.STAGES - 1, "its foe gone from the table: it shrinks, not pops")
	_settle(views)
	check_equal(_markers.count, 0, "then gone")


func test_a_frame_allocates_nothing() -> void:
	_wizard(MIDDLE, 0)
	var foes: Array[Node2D] = []
	for i in 12:
		foes.append(_foe(MIDDLE + Vector2.from_angle(TAU * float(i) / 12.0) * 900.0))
	var views: ScreenViewsScript = _one()
	_settle(views)
	var objects: float = Performance.get_monitor(Performance.OBJECT_COUNT)
	for frame in 100:
		for i in foes.size():
			foes[i].position = MIDDLE + Vector2.from_angle(TAU * float(i) / 12.0 + float(frame) * 0.05) * (300.0 + 6.0 * float(frame))
		_step(views)
	check_equal(Performance.get_monitor(Performance.OBJECT_COUNT), objects, "100 frames of twelve foes walking in and out of view make no object")


func test_feel_draws_them_on_the_teammate_markers_layer() -> void:
	var feel: Node = root.get_node_or_null(^"Feel")
	check(feel != null and feel.has_method(&"foe_markers"), "Feel has the foe markers")
	if feel == null or not feel.has_method(&"foe_markers"):
		return
	var made: MarkersScript = feel.call(&"foe_markers") as MarkersScript
	var theirs: Node = feel.call(&"teammate_markers") as Node
	check(made != null and theirs != null and made.get_parent() == theirs.get_parent(), "beside the teammate markers")
	if made == null or theirs == null:
		return
	check((made.get_parent() as CanvasLayer).layer == TeammateMarkersScript.LAYER, "on their layer, over the HUD")
	check(made.get_index() < theirs.get_index(), "under them: a teammate's marker is drawn over a foe's")
