extends "res://tests/support/suite.gd"
## Feel's per-frame pieces on the worker threads (gameplay/feel/feel_jobs.gd; the owner's decision of
## 2026-11-22): every piece runs once, on one thread or many; and what the threaded effects draw is the
## same either way, to the byte: the light grid lit a view a thread (the kernel's view range against
## every view in one call, and the GDScript's), and the rooms' mists parted a room a thread.

const FeelJobsScript := preload("res://gameplay/feel/feel_jobs.gd")
const LightGridScript := preload("res://gameplay/feel/light_grid.gd")
const MistPartingScript := preload("res://gameplay/feel/mist_parting.gd")
const NativeScript := preload("res://core/native/native.gd")
const LightGridTest := preload("res://tests/gameplay/feel/test_light_grid.gd")

const ROWS: int = 160
const PIECES: int = 37


## One piece's own record (each piece writes only its own).
class Seen:
	extends RefCounted
	var runs: int = 0
	var sum: int = 0


var _seen: Array[Seen] = []


func _mark(piece: int) -> void:
	var own: Seen = _seen[piece]
	own.runs += 1
	for k in 2000:
		own.sum += (piece * 31 + k) % 7


func test_every_piece_runs_once_on_one_thread_or_many() -> void:
	for threaded: bool in [false, true]:
		var jobs := FeelJobsScript.new()
		jobs.threaded = threaded
		_seen.clear()
		for piece in PIECES:
			_seen.append(Seen.new())
		jobs.run(_mark, PIECES)
		var once: bool = true
		var sums_same: bool = true
		for piece in PIECES:
			once = once and _seen[piece].runs == 1
			var want: int = 0
			for k in 2000:
				want += (piece * 31 + k) % 7
			sums_same = sums_same and _seen[piece].sum == want
		check(once, "every piece ran exactly once (threaded %s)" % threaded)
		check(sums_same, "and did all of its work before `run` returned (threaded %s)" % threaded)
		check(jobs.groups == (1 if threaded else 0), "a group on the threads only when threaded (%d)" % jobs.groups)
		jobs.run(_mark, 0)
		check(jobs.pieces == PIECES, "no pieces, nothing run")


func test_the_web_runs_every_piece_on_its_one_thread() -> void:
	# The switch's default is the build's: never threads where the engine has none, or on the web.
	if OS.has_feature("web") or not OS.has_feature("threads"):
		check(not FeelJobsScript.default_threaded(), "no threads by default")
	else:
		check(FeelJobsScript.default_threaded() == (OS.get_processor_count() > 1), "threads by default on a desktop of more than one core")


## A grid over three views (the third over the first's middle) with tints and boxes, as the light
## grid's own test lays it.
static func _grid(native: bool) -> LightGridScript:
	var grid := LightGridScript.new()
	grid.set_cell(LightGridScript.CELL)
	var boxes := PackedVector4Array([Vector4(-40.0, -30.0, 600.0, 330.0), Vector4(1985.0, 993.0, 2310.0, 1170.0), Vector4(150.0, 90.0, 470.0, 270.0)])
	grid.fit(boxes, 3)
	var tints := PackedColorArray()
	tints.resize(32)
	tints[2] = Color(0.31, 0.84, 0.86, LightGridScript.INFUSION_MARK)
	tints[9] = Color(0.63, 0.19, 0.60, LightGridScript.INFUSION_MARK)
	grid.use_tints(tints)
	var walls := PackedVector4Array([Vector4(100.0, 100.0, 132.0, 116.0), Vector4(300.0, 60.0, 340.0, 200.0)])
	var bodies := PackedVector4Array([Vector4(100.0, 60.0, 132.0, 1.0), Vector4(300.0, 60.0, 340.0, 0.6)])
	grid.set_blockers(walls, bodies, 2)
	grid.use_native(native)
	return grid


## The lights of a frame on the views `first` to `first` + `views` - 1 of `grid`.
static func _light_views(grid: LightGridScript, first: int, views: int) -> void:
	grid.add_rows(LightGridTest._rows(LightGridScript.ROWS_SHOT, 11), ROWS, LightGridScript.ROWS_SHOT, 1.0, 0.0, 3.25, false, first, views)
	grid.add_rows(LightGridTest._rows(LightGridScript.ROWS_FLASH, 13), ROWS, LightGridScript.ROWS_FLASH, 1.6, 10.0, 3.25, true, first, views)
	grid.add_rows(LightGridTest._rows(LightGridScript.ROWS_SPOT, 15), ROWS, LightGridScript.ROWS_SPOT, 1.0, 0.0, 3.25, true, first, views)
	var path := PackedVector3Array([Vector3(20.0, 300.0, 0.0), Vector3(200.0, 120.0, 0.0), Vector3(580.0, 40.0, 0.0)])
	grid.add_beam(path, path.size(), 24.0, Color(0.9, 0.5, 0.2), first, views)
	var far := PackedVector3Array([Vector3(2000.0, 1100.0, 0.0), Vector3(2300.0, 1000.0, 0.0)])
	grid.add_beam(far, far.size(), 18.0, Color(0.2, 0.6, 1.0), first, views)


var _split_grid: LightGridScript = null


func _light_one_view(view: int) -> void:
	_light_views(_split_grid, view, 1)


func test_the_grid_lit_a_view_a_thread_is_the_grid_lit_at_once() -> void:
	var whole: LightGridScript = _grid(false)
	whole.clear()
	_light_views(whole, 0, LightGridScript.VIEWS_MOST)
	whole.bake()
	var by_view: LightGridScript = _grid(false)
	by_view.clear()
	for view in by_view.view_count:
		_light_views(by_view, view, 1)
	by_view.bake()
	check(by_view.rgb.to_byte_array() == whole.rgb.to_byte_array(), "the GDScript: each view lit alone, every cell the same to the bit")
	var lit: int = 0
	for c in whole.rgb.size():
		lit += 1 if whole.rgb[c] > 0.0 else 0
	check(lit > 500, "and the frame lights cells in every view (%d channels)" % lit)
	if not NativeScript.loaded():
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "the native module is loaded")
		return
	_split_grid = _grid(true)
	check(_split_grid.can_split(), "the kernel's grid lights its views apart")
	check(not whole.can_split(), "the GDScript's keeps to one thread")
	var jobs := FeelJobsScript.new()
	jobs.threaded = true
	for round in 3:
		_split_grid.clear()
		jobs.run(_light_one_view, _split_grid.view_count)
		_split_grid.bake()
		check(_split_grid.rgb.to_byte_array() == whole.rgb.to_byte_array(), "the kernel, a view a thread: every cell as the GDScript's at once (round %d)" % round)
		check(_split_grid.baked() == whole.baked(), "and every byte handed to the texture (round %d)" % round)
	check(jobs.groups == 3, "the views ran on the threads")


var _mists: Array[MistPartingScript] = []
var _feet := PackedVector2Array()


func _part_one(room: int) -> void:
	_mists[room].work(1.0 / 60.0, _feet, _feet.size())


static func _rooms() -> Array[MistPartingScript]:
	var out: Array[MistPartingScript] = []
	for room in 5:
		var grid := MistPartingScript.new()
		grid.lay(Vector2(320.0 + 64.0 * room, 240.0), Vector2(400.0 * room, 0.0))
		out.append(grid)
	return out


func test_the_rooms_mists_parted_a_room_a_thread_are_the_same() -> void:
	var alone: Array[MistPartingScript] = _rooms()
	_mists = _rooms()
	var jobs := FeelJobsScript.new()
	jobs.threaded = true
	var same: bool = true
	for frame in 90:
		# Feet walking through every room, some of them in two.
		_feet.resize(0)
		for room in 5:
			_feet.append(Vector2(400.0 * room + 40.0 + 3.0 * frame, 60.0 + 1.5 * frame))
			_feet.append(Vector2(400.0 * room + 300.0 - 2.0 * frame, 200.0))
		for room in 5:
			alone[room].step(1.0 / 60.0, _feet, _feet.size())
		jobs.run(_part_one, _mists.size())
		for room in 5:
			_mists[room].upload()
			for x in [3, 11, 20, 33]:
				for y in [2, 9, 17, 25]:
					var at := Vector2(400.0 * room + 8.0 * x + 4.0, 8.0 * y + 4.0)
					same = same and _mists[room].parted_at(at) == alone[room].parted_at(at)
			same = same and _mists[room].live_cells() == alone[room].live_cells()
	check(same, "every room's cells parted as on one thread, every frame")
	var picture_same: bool = true
	for room in 5:
		var threaded_picture: Image = _mists[room].texture.get_image()
		var one_picture: Image = alone[room].texture.get_image()
		if threaded_picture != null and one_picture != null:
			picture_same = picture_same and threaded_picture.get_data() == one_picture.get_data()
	check(picture_same, "and every room's picture the same")
	check(jobs.groups == 90, "the rooms ran on the threads")
