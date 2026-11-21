extends "res://tests/support/suite.gd"
## The split's merge ends in a short, bounded time (the owner's report of 2026-11-21: "Sometimes when
## local players go back near each other, the voronoi line split does not disappear for some time";
## gameplay/feel/split_camera.gd, MERGE_TIME). A merging view used to go only once its picture was
## within SETTLED of the one it merged into, easing onto it at the party camera's pull: while that
## picture kept moving (the wizards walking on together, close foes in a fight moving the party
## camera) it never got there, and the divider stayed. Here wizards walk back together at a wizard's
## pace (2 to 4 seats, with and without close foes, standing still or walking on together, Dynamic
## and Equal) and the divider must be gone within MERGE_BOUND of their standing within JOIN_REACH,
## with no jump; at the edges (the fit, JOIN_REACH) it does not flicker. With the hand-made
## twelve-room row (tests/support/biome_maps.gd), as test_split_camera.gd does.
const SplitCameraScript := preload("res://gameplay/feel/split_camera.gd")
const PartyCameraScript := preload("res://gameplay/feel/party_camera.gd")
const CloseFoesScript := preload("res://gameplay/feel/close_foes.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const BiomeMaps := preload("res://tests/support/biome_maps.gd")

const SCREEN := Vector2(640.0, 360.0)
const FRAME: float = 1.0 / 60.0
## A wizard's walking pace (pixels a second; gameplay/actor/mover.gd's `speed`).
const PACE: float = 90.0
## The divider is gone within this long of the wizards standing within JOIN_REACH (real seconds;
## the owner's aim, under about half a second).
const MERGE_BOUND: float = 0.5
## A view's picture may always move this far a frame (screen pixels, at the screen's corners);
## more only up to three times its move the frame before (an ease from rest grows 1, 3, 5 ...; a
## jump is far more).
const SPIKE_FREE: float = 12.0
## Where the walkers stop, about seat 0's wizard (world pixels): all within JOIN_REACH of each other.
const SPOTS: Array[Vector2] = [Vector2.ZERO, Vector2(48.0, 0.0), Vector2(0.0, 40.0), Vector2(48.0, 40.0)]
## Where each seat starts (rooms of the row).
const STARTS: Array[int] = [2, 4, 5, 3]

var _table: ActorsScript
var _holder: SubViewport
var _camera: Camera2D
var _party: PartyCameraScript
var _split: SplitCameraScript
var _foes: CloseFoesScript
var _rooms: PackedVector2Array = PackedVector2Array()


func before_each() -> void:
	_table = own(ActorsScript.new()) as ActorsScript
	root.add_child(_table)
	_holder = own(SubViewport.new()) as SubViewport
	_holder.size = Vector2i(SCREEN)
	_holder.disable_3d = true
	root.add_child(_holder)
	_camera = Camera2D.new()
	_holder.add_child(_camera)
	_camera.make_current()
	_party = PartyCameraScript.new()
	_party.follow(_camera)
	_split = SplitCameraScript.new()
	_foes = CloseFoesScript.new()
	_rooms = _room_middles()


func _room_middles() -> PackedVector2Array:
	var out := PackedVector2Array()
	var registry: Object = root.get_node_or_null(^"Registry")
	if registry == null:
		return out
	var map: BiomeMap = BiomeMaps.twelve_rooms(registry)
	var bounds := Rect2()
	for room in map.rooms():
		var shape: PieceShape = BiomeMaps.shape(registry, map.room_templates[room]).mirrored(map.room_mirrors[room])
		var rect := Rect2(map.room_places[room], shape.size)
		bounds = rect if room == 0 else bounds.merge(rect)
		out.append(rect.get_center())
	_camera.limit_left = int(bounds.position.x)
	_camera.limit_top = int(bounds.position.y) - 400
	_camera.limit_right = int(bounds.end.x)
	_camera.limit_bottom = int(bounds.end.y) + 400
	return out


func _body(team: int, seat: int, at: Vector2) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.global_position = at
	if team == ActorsScript.TEAM_WIZARDS:
		var id: int = _table.open(team, seat, seat)
		_table.set_node(id, node)
		_table.set_home(id, seat)
	else:
		_table.set_node(_table.open(team, ActorsScript.RAMP_ENEMY), node)
	return node


## A drawn frame as Feel steps it: the close foes, the party camera, then the split.
func _frame() -> void:
	_foes.find(_table, null)
	_party.look(_table, 0, _foes)
	_party.step(FRAME)
	_split.step(FRAME, _table, 0, _camera, SCREEN, _foes)


## The wizards of `wizards` all stand within JOIN_REACH of each other.
static func _together(wizards: Array[Node2D]) -> bool:
	for a in wizards.size():
		for b in range(a + 1, wizards.size()):
			if wizards[a].global_position.distance_to(wizards[b].global_position) >= SplitCameraScript.JOIN_REACH:
				return false
	return true


## How far two pictures are apart on screen (pixels), at the screen's corners.
static func _gap(a: Transform2D, b: Transform2D) -> float:
	var most: float = 0.0
	for corner: Vector2 in [Vector2.ZERO, Vector2(SCREEN.x, 0.0), SCREEN, Vector2(0.0, SCREEN.y)]:
		most = maxf(most, (a.affine_inverse() * corner).distance_to(b.affine_inverse() * corner) * a.x.x)
	return most


## `seats` wizards far apart walk back to seat 0's at a wizard's pace and stay (`fight`: two foes
## circle them, so the party camera never rests; `walk_on`: once there they walk on together;
## `equal`: equal panes; `far`: one more seat stands far off, so the screen stays split and the
## walkers' views merge into one another). Checks the walkers share one picture (the one picture, or
## one view beside the far seat's) within MERGE_BOUND of their standing within JOIN_REACH and keep
## it, a divider changes a pixel a frame at most and has shrunk before its view goes, and the last
## views' pictures were the one drawn. Returns the merge's time (seconds from together to merged).
func _merge_case(seats: int, fight: bool, walk_on: bool, equal: bool, far: bool = false) -> float:
	var what: String = "%d seats%s%s%s%s" % [seats, ", a fight" if fight else "", ", walking on" if walk_on else "", ", equal" if equal else "", ", one far" if far else ""]
	_split.set_equal(equal)
	var wizards: Array[Node2D] = []
	for seat in seats:
		wizards.append(_body(ActorsScript.TEAM_WIZARDS, seat, _rooms[STARTS[seat]] + Vector2(0.0, 30.0 * seat)))
	if far:
		_body(ActorsScript.TEAM_WIZARDS, seats, _rooms[10])
	var walkers: int = 0
	for seat in seats:
		walkers |= 1 << seat
	var merged_views: int = 2 if far else 0
	var foes: Array[Node2D] = []
	if fight:
		for i in 2:
			foes.append(_body(ActorsScript.TEAM_ENEMIES, 0, _rooms[STARTS[0]]))
	var angle: float = 0.0
	for i in 120:
		_frame()
	check(_split.split and _split.views.count >= 2, "%s: apart, split" % what)
	var together_at: int = -1
	var merged_at: int = -1
	var line_gone_at: int = -1
	var unsplit_at: int = -1
	var stages := {}
	var last_seen := {}
	var last_root := Transform2D()
	var arrived_for: int = 0
	var most_moved: float = 0.0
	var last_moved := {}
	var frame: int = 0
	while frame < 60 * 90 and arrived_for <= 120:
		frame += 1
		var home: Vector2 = wizards[0].global_position
		var all_there: bool = true
		for seat in range(1, seats):
			var to: Vector2 = home + SPOTS[seat] - wizards[seat].global_position
			wizards[seat].global_position += to.limit_length(PACE * FRAME)
			all_there = all_there and to.length() <= PACE * FRAME
		if all_there:
			arrived_for += 1
			if walk_on:
				# On together, away from the far seat (west).
				for wizard in wizards:
					wizard.global_position += Vector2(-PACE * FRAME if far else PACE * FRAME, 0.0)
		if fight:
			angle += 1.5 * FRAME
			for i in foes.size():
				foes[i].global_position = wizards[0].global_position + Vector2.from_angle(angle + PI * i) * 150.0
		_frame()
		if together_at < 0 and _together(wizards):
			together_at = frame
		if _split.split:
			unsplit_at = -1
		elif unsplit_at < 0:
			unsplit_at = frame
		var views: ScreenViewsScript = _split.views
		var shared: int = views.view_of_seat(0)
		var one: bool = views.count == merged_views and (views.count == 0 or (shared >= 0 and views.seats[shared] & walkers == walkers))
		if not one:
			merged_at = -1
		elif merged_at < 0:
			merged_at = frame
		# No divider drawn between two views of the walkers (the line the owner saw stay).
		var line: bool = false
		for a in views.count:
			for b in range(a + 1, views.count):
				if views.seats[a] & walkers != 0 and views.seats[b] & walkers != 0 and _split.divider_between(a, b) > 0:
					line = true
		if line:
			line_gone_at = -1
		elif line_gone_at < 0:
			line_gone_at = frame
		for view in views.count:
			var slot: int = _split.slot_of(view)
			var stage: int = _split.stage_of(view)
			if stages.has(slot):
				check(absi(stage - int(stages[slot])) <= 1, "%s: a divider changes a pixel a frame at most" % what)
				# Smooth: a merging view's picture eases, its move a frame changing gradually: a jump
				# (the landing on its target included) would be a frame moving far more than the one
				# before.
				var moved: float = _gap(views.to_screen[view], last_seen[slot])
				var before: float = float(last_moved.get(slot, 0.0))
				if _split.is_merging(view):
					check(moved <= maxf(before * 3.0, SPIKE_FREE), "%s: merging view slot %d's picture moved %.2f px a frame after %.2f (no jump)" % [what, slot, moved, before])
				last_moved[slot] = moved
				most_moved = maxf(most_moved, moved)
			stages[slot] = stage
			last_seen[slot] = views.to_screen[view]
		for slot in stages.keys():
			var live: bool = false
			for view in views.count:
				live = live or _split.slot_of(view) == slot
			if live:
				continue
			# Gone: its divider had shrunk to a pixel at most (the next width, none, is its going);
			# gone into the one picture, its picture was the one drawn that frame.
			check(int(stages[slot]) <= 1, "%s: a view goes once its divider has shrunk (it was %d)" % [what, int(stages[slot])])
			if views.count == 0:
				var off: float = _gap(last_seen[slot], last_root)
				check(off < SplitCameraScript.SETTLED * 4.0, "%s: the last view's picture was the one drawn (%.4f px off)" % [what, off])
				var merging: float = float(frame - unsplit_at) * FRAME
				check(unsplit_at >= 0 and merging <= MERGE_BOUND, "%s: the views were gone %.2f s after the screen stopped wanting a split (at most %.2f s)" % [what, merging, MERGE_BOUND])
				print("MERGE: %s: the views gone %.2f s after the split's end" % [what, merging])
			stages.erase(slot)
			last_seen.erase(slot)
			last_moved.erase(slot)
		last_root = _holder.get_canvas_transform()
	check(together_at >= 0, "%s: the wizards stood together" % what)
	check(merged_at >= 0, "%s: the walkers share one picture and keep it (%d views)" % [what, _split.views.count])
	check(far == _split.split, "%s: split only with a seat far off" % what)
	var took: float = float(merged_at - together_at) * FRAME if merged_at >= 0 and together_at >= 0 else INF
	check(took <= MERGE_BOUND, "%s: the walkers shared one picture %.2f s after they stood within JOIN_REACH (at most %.2f s)" % [what, took, MERGE_BOUND])
	var line_took: float = float(line_gone_at - together_at) * FRAME if line_gone_at >= 0 and together_at >= 0 else INF
	check(line_took <= MERGE_BOUND, "%s: no divider between the walkers %.2f s after they stood within JOIN_REACH (at most %.2f s)" % [what, line_took, MERGE_BOUND])
	print("MERGE: %s: no divider between them %.2f s, one picture %.2f s after together; a picture moved at most %.2f px a frame" % [what, line_took, took, most_moved])
	return took


func test_two_seats_walking_back_merge_in_time() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	_merge_case(2, false, false, false)


func test_two_seats_walking_back_and_on_together_merge_in_time() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	_merge_case(2, false, true, false)


func test_two_seats_in_a_fight_merge_in_time() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	_merge_case(2, true, false, false)


func test_three_seats_merge_in_time() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	_merge_case(3, false, false, false)


func test_three_seats_in_a_fight_walking_on_merge_in_time() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	_merge_case(3, true, true, false)


func test_four_seats_merge_in_time() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	_merge_case(4, false, false, false)


func test_four_seats_in_a_fight_merge_in_time() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	_merge_case(4, true, false, false)


func test_equal_panes_two_seats_walking_on_merge_in_time() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	_merge_case(2, false, true, true)


func test_equal_panes_four_seats_in_a_fight_merge_in_time() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	_merge_case(4, true, false, true)


func test_two_seats_beside_a_far_one_merge_in_time() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	_merge_case(2, false, false, false, true)


func test_two_seats_beside_a_far_one_walking_on_in_a_fight_merge_in_time() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	_merge_case(2, true, true, false, true)


func test_three_seats_beside_a_far_one_merge_in_time() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	_merge_case(3, false, false, false, true)


func test_three_seats_beside_a_far_one_in_a_fight_merge_in_time() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	_merge_case(3, true, false, false, true)


func test_equal_panes_two_seats_beside_a_far_one_merge_in_time() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	_merge_case(2, false, true, true, true)


# --- No flicker at the edges -----------------------------------------------------------------------

## Two seats: B walks east until the screen splits, then stands there swaying a few pixels for five
## seconds: the split holds (it merges only with MERGE_ROOM to spare), then B walks back and it
## merges once, within MERGE_BOUND of the screen no longer wanting the split.
func test_no_flicker_at_the_fit() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	_body(ActorsScript.TEAM_WIZARDS, 0, _rooms[2])
	var b: Node2D = _body(ActorsScript.TEAM_WIZARDS, 1, _rooms[2] + Vector2(48.0, 0.0))
	for i in 60:
		_frame()
	check(not _split.split, "together: one picture")
	var frames: int = 0
	while not _split.split and frames < 2000:
		b.global_position += Vector2(PACE * FRAME, 0.0)
		_frame()
		frames += 1
	check(_split.split, "walked apart: split")
	var edge: Vector2 = b.global_position
	var changes: int = 0
	var was: bool = _split.split
	for i in 300:
		b.global_position = edge + Vector2(6.0 * sin(float(i) * 0.4), 0.0)
		_frame()
		if _split.split != was:
			changes += 1
			was = _split.split
	check_equal(changes, 0, "swaying at the edge: no flicker")
	check(_split.split and _split.views.count == 2, "still split")
	var unsplit_at: int = -1
	frames = 0
	while (_split.split or _split.views.count > 0) and frames < 2000:
		b.global_position += Vector2(-PACE * FRAME, 0.0)
		_frame()
		frames += 1
		if not _split.split and unsplit_at < 0:
			unsplit_at = frames
		if _split.split and unsplit_at >= 0:
			check(false, "a merge that started holds: no split again")
			break
	check_equal(_split.views.count, 0, "walked back: one picture")
	var took: float = float(frames - unsplit_at) * FRAME
	check(unsplit_at >= 0 and took <= MERGE_BOUND, "merged %.2f s after the screen stopped wanting the split (at most %.2f s)" % [took, MERGE_BOUND])


## A pair beside a far seat: B walks to A until they share a view, then sways about JOIN_REACH for
## five seconds: they keep sharing it (they part only past LEAVE_REACH), with no view made or lost.
func test_no_flicker_at_join_reach() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	var a: Node2D = _body(ActorsScript.TEAM_WIZARDS, 0, _rooms[2])
	var b: Node2D = _body(ActorsScript.TEAM_WIZARDS, 1, _rooms[2] + Vector2(SplitCameraScript.LEAVE_REACH + 60.0, 0.0))
	_body(ActorsScript.TEAM_WIZARDS, 2, _rooms[10])
	for i in 120:
		_frame()
	check(_split.views.view_of_seat(0) != _split.views.view_of_seat(1), "apart: a view each")
	var frames: int = 0
	while _split.views.count != 2 and frames < 2000:
		b.global_position += Vector2(-PACE * FRAME, 0.0)
		_frame()
		frames += 1
	check_equal(_split.views.count, 2, "joined: the pair's view and the far one's")
	check_equal(_split.views.view_of_seat(0), _split.views.view_of_seat(1), "the pair shares one")
	var edge: float = a.global_position.x + SplitCameraScript.JOIN_REACH
	var changes: int = 0
	var count: int = _split.views.count
	for i in 300:
		b.global_position.x = edge + 6.0 * sin(float(i) * 0.4)
		_frame()
		if _split.views.count != count:
			changes += 1
			count = _split.views.count
	check_equal(changes, 0, "swaying about JOIN_REACH: no view made or lost")
	check_equal(_split.views.view_of_seat(0), _split.views.view_of_seat(1), "the pair still shares one")


# --- The merge clock (the review of 2026-11-21) ----------------------------------------------------

## A merge lands at its time whatever that time is (0.35 s never did with the clock in 32 bits: it
## stopped a hair short, the pull fell to none and the view froze), and the pull is 1 once there.
func test_the_merge_clock_lands_at_any_time() -> void:
	for time: float in [0.25, 0.3, 0.35, 0.4, 0.45, 0.5, 0.7]:
		var clock := PackedFloat64Array([0.0])
		var frames: int = 0
		var landed: bool = false
		while frames < 200 and not landed:
			var was: float = clock[0]
			clock[0] = SplitCameraScript.merge_clock(was, FRAME, time)
			landed = clock[0] >= time
			if landed:
				check_equal(SplitCameraScript.merge_pull(was, clock[0], time), 1.0, "%.2f s: on its target once landed" % time)
			frames += 1
		check(landed and frames <= int(ceil(time / FRAME)) + 1, "a %.2f s merge lands in %d frames" % [time, frames])


## A pair's merging view, landed on its partner's picture and waiting for its anchor, gets a new
## target when the far seat comes back and the split ends: it eases onto the one picture from rest
## (no jump, its divider back while the pictures differ) and goes only once on it, never at once
## with its partner's picture handed to the cells round it.
func test_a_landed_view_given_a_new_target_eases_onto_it() -> void:
	if _rooms.size() < 12:
		check(false, "the biome's rooms were read")
		return
	var a: Node2D = _body(ActorsScript.TEAM_WIZARDS, 0, _rooms[2])
	var b: Node2D = _body(ActorsScript.TEAM_WIZARDS, 1, _rooms[2] + Vector2(SplitCameraScript.LEAVE_REACH + 60.0, 0.0))
	var far: Node2D = _body(ActorsScript.TEAM_WIZARDS, 2, _rooms[10])
	for i in 120:
		_frame()
	check_equal(_split.views.count, 3, "a view each")
	# B walks to A until the view it leaves has landed (merging, its divider gone, still drawn).
	var landed: int = -1
	var frames: int = 0
	while landed < 0 and frames < 2000:
		b.global_position += (a.global_position + Vector2(48.0, 0.0) - b.global_position).limit_length(PACE * FRAME)
		_frame()
		frames += 1
		for view in _split.views.count:
			if _split.is_merging(view) and _split.stage_of(view) == 0:
				landed = _split.slot_of(view)
	check(landed >= 0, "the pair's merging view landed and waits for its anchor")
	if landed < 0:
		return
	# The far seat comes back within the fit: the split ends, every view merges into the one picture.
	far.global_position = a.global_position + Vector2(400.0, 0.0)
	var last := Transform2D()
	var last_root := Transform2D()
	var gap0: float = -1.0
	var seen: bool = false
	for i in 120:
		_frame()
		var view: int = -1
		for v in _split.views.count:
			if _split.slot_of(v) == landed:
				view = v
		if view < 0:
			if seen:
				var off: float = _gap(last, last_root)
				check(off < SplitCameraScript.SETTLED * 4.0, "it went only once on the one picture (%.3f px off)" % off)
			break
		if gap0 < 0.0:
			# How far its picture is from the one picture as the split ends (screen pixels).
			gap0 = _gap(last, _holder.get_canvas_transform())
		if seen:
			# An ease from rest over MERGE_TIME moves at most about 8% of the way a frame; snapping
			# to the new target (the bug) would move all of it.
			var moved: float = _gap(_split.views.to_screen[view], last)
			check(moved <= maxf(SPIKE_FREE, gap0 * 0.12), "its picture eased onto the new one (%.2f px a frame, %.2f px to go at the start)" % [moved, gap0])
		seen = true
		last = _split.views.to_screen[view]
		last_root = _holder.get_canvas_transform()
	check(seen, "it was still drawn after the split ended")
	check_equal(_split.views.count, 0, "then the one picture")
