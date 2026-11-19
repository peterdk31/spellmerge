extends "res://tests/support/suite.gd"
## The camera spike's split screen (connected biomes CB1): the Voronoi cells (voronoi_cells.gd)
## cover the screen without overlap, each holds its own wizard's site and leans its view toward the
## others; the views node (voronoi_views.gd) draws the root's world once a view and stops the root
## drawing it, keeping the HUD, and puts the root back as it leaves; the runner's scenarios
## (split_views_runner.gd) are the ones its report and the web build expect. How a split looks and
## what it costs are the runner's (split_views.gd, in a window): headless runs draw nothing.

const CellsScript := preload("res://tests/benchmark/voronoi_cells.gd")
const ViewsScript := preload("res://tests/benchmark/voronoi_views.gd")
const RunnerScript := preload("res://tests/benchmark/split_views_runner.gd")

const SCREEN := Vector2(640.0, 360.0)
const SEED: int = 31


func _screen_rect() -> Rect2:
	return Rect2(Vector2.ZERO, SCREEN)


## Every cell inside the screen, each holding its own site, their areas the screen's.
func _check_cover(points: PackedVector2Array, what: String) -> void:
	var cells: Array[PackedVector2Array] = CellsScript.cells(points, _screen_rect())
	check_equal(cells.size(), points.size(), "%s: a cell a site" % what)
	var total: float = 0.0
	for i in cells.size():
		var cell: PackedVector2Array = cells[i]
		check(cell.size() >= 3, "%s: cell %d is a polygon" % [what, i])
		total += CellsScript.area(cell)
		for corner in cell:
			check(_screen_rect().grow(0.01).has_point(corner), "%s: cell %d stays on the screen (%s)" % [what, i, corner])
		check(Geometry2D.is_point_in_polygon(points[i], cell), "%s: site %d is in its own cell" % [what, i])
		check(Geometry2D.is_point_in_polygon(CellsScript.centroid(cell), cell), "%s: cell %d's middle is inside it" % [what, i])
	check(absf(total - SCREEN.x * SCREEN.y) < 1.0, "%s: the cells cover the screen once (%.1f of %.1f)" % [what, total, SCREEN.x * SCREEN.y])
	for i in cells.size():
		for j in range(i + 1, cells.size()):
			var shared: Array[PackedVector2Array] = Geometry2D.intersect_polygons(cells[i], cells[j])
			var overlap: float = 0.0
			for piece in shared:
				overlap += CellsScript.area(piece)
			check(overlap < 1.0, "%s: cells %d and %d do not overlap (%.2f)" % [what, i, j, overlap])


func test_one_site_is_the_whole_screen() -> void:
	var cells: Array[PackedVector2Array] = CellsScript.cells(PackedVector2Array([Vector2(100.0, 50.0)]), _screen_rect())
	check(absf(CellsScript.area(cells[0]) - SCREEN.x * SCREEN.y) < 0.01, "one wizard sees the whole screen")
	var site: PackedVector2Array = CellsScript.sites(PackedVector2Array([Vector2(900.0, -40.0)]), SCREEN, 96.0)
	check_equal(site[0], SCREEN * 0.5, "one wizard's site is the screen's middle")


func test_cells_cover_the_screen_for_two_to_four() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for round_index in 40:
		var count: int = 2 + round_index % 3
		var world := PackedVector2Array()
		for i in count:
			world.append(Vector2(rng.randf_range(-2000.0, 2000.0), rng.randf_range(-1500.0, 1500.0)))
		_check_cover(CellsScript.sites(world, SCREEN, 96.0), "round %d, %d wizards" % [round_index, count])


func test_two_side_by_side_split_down_the_middle() -> void:
	var points: PackedVector2Array = CellsScript.sites(PackedVector2Array([Vector2(0.0, 0.0), Vector2(1000.0, 0.0)]), SCREEN, 96.0)
	check_equal(points[0], Vector2(96.0, 180.0), "the left wizard is the margin from the left edge")
	check_equal(points[1], Vector2(544.0, 180.0), "the right wizard the margin from the right")
	var cells: Array[PackedVector2Array] = CellsScript.cells(points, _screen_rect())
	for corner in cells[0]:
		check(corner.x <= 320.01, "the left cell ends at the middle (%s)" % corner)
	for corner in cells[1]:
		check(corner.x >= 319.99, "the right cell starts at the middle (%s)" % corner)
	# The bisector is square to the line between the wizards: a diagonal pair splits on the other diagonal's slope.
	var diagonal: PackedVector2Array = CellsScript.sites(PackedVector2Array([Vector2(0.0, 0.0), Vector2(100.0, 100.0)]), SCREEN, 96.0)
	var line: Vector2 = diagonal[1] - diagonal[0]
	check(absf(line.normalized().dot(Vector2(1.0, 1.0).normalized()) - 1.0) < 0.0001, "the sites keep the wizards' direction (one scale both ways)")


func test_wizards_together_still_get_a_cell_each() -> void:
	var world := PackedVector2Array([Vector2(5.0, 5.0), Vector2(5.0, 5.0), Vector2(5.0, 5.0), Vector2(5.0, 5.0)])
	var points: PackedVector2Array = CellsScript.sites(world, SCREEN, 96.0)
	for i in points.size():
		for j in range(i + 1, points.size()):
			check(points[i].distance_to(points[j]) >= CellsScript.MIN_GAP - 0.0001, "sites %d and %d are pushed apart" % [i, j])
	_check_cover(points, "four wizards on one spot")


func test_the_view_leans_toward_the_others() -> void:
	var points: PackedVector2Array = CellsScript.sites(PackedVector2Array([Vector2(0.0, 0.0), Vector2(1000.0, 0.0)]), SCREEN, 96.0)
	var cells: Array[PackedVector2Array] = CellsScript.cells(points, _screen_rect())
	var middle: Vector2 = CellsScript.centroid(cells[0])
	var centre: Vector2 = CellsScript.camera_centre(Vector2(0.0, 0.0), middle, SCREEN, 1.0)
	check_equal((Vector2(0.0, 0.0) - centre) + SCREEN * 0.5, middle, "the wizard is drawn at its cell's middle")
	check(centre.x > 0.0, "the left wizard's view looks right of it, toward the other")
	var zoomed: Vector2 = CellsScript.camera_centre(Vector2(10.0, 20.0), middle, SCREEN, 2.0)
	check(((Vector2(10.0, 20.0) - zoomed) * 2.0 + SCREEN * 0.5).distance_to(middle) < 0.0001, "at zoom 2 too")


func test_views_draw_the_world_once_a_view_and_the_root_keeps_the_hud() -> void:
	var mask_before: int = root.canvas_cull_mask
	var views: ViewsScript = own(ViewsScript.new(3)) as ViewsScript
	root.add_child(views)
	check_equal(views.views.size(), 3, "three views")
	for view in views.views:
		check(view.world_2d == root.world_2d, "%s draws the root's world" % view.name)
	check_equal(root.canvas_cull_mask & ViewsScript.WORLD_LAYER, 0, "the root no longer draws the world")
	check(root.canvas_cull_mask & ViewsScript.SCREEN_LAYER != 0, "but draws what is on the screen")
	for cell in views.shown:
		check(cell.visibility_layer & ViewsScript.SCREEN_LAYER != 0, "%s is drawn by the root" % cell.name)
	# A HUD made later (on a canvas layer of the root) stays on screen; the world's items do not.
	var hud := CanvasLayer.new()
	var label := Label.new()
	hud.add_child(label)
	root.add_child(own(hud) as Node)
	check(label.visibility_layer & ViewsScript.SCREEN_LAYER != 0, "a HUD item added later is kept on the screen")
	var world_item := Node2D.new()
	root.add_child(own(world_item) as Node)
	check_equal(world_item.visibility_layer & ViewsScript.SCREEN_LAYER, 0, "a world item is left to the views")
	views.place(PackedVector2Array([Vector2(0.0, 0.0), Vector2(800.0, 0.0), Vector2(400.0, 600.0), Vector2(9.0, 9.0)]))
	var total: float = 0.0
	var places := PackedVector2Array([Vector2(0.0, 0.0), Vector2(800.0, 0.0), Vector2(400.0, 600.0)])
	for i in 3:
		var want: Vector2 = CellsScript.camera_centre(places[i], CellsScript.centroid(views.cells[i]), Vector2(views.views[i].size), ViewsScript.ZOOM)
		check(views.cameras[i].position.distance_to(want) < 0.001, "view %d's camera draws its wizard at its cell's middle" % i)
		check(views.cameras[i].is_current(), "view %d's camera is its view's" % i)
	for i in 3:
		check(views.shown[i].polygon.size() >= 3, "cell %d is placed" % i)
		check_equal(views.shown[i].uv, views.shown[i].polygon, "cell %d shows its own pixels of its view" % i)
		total += CellsScript.area(views.shown[i].polygon)
	check(absf(total - Vector2(views.views[0].size).x * Vector2(views.views[0].size).y) < 1.0, "the cells cover the screen")
	# A light buffer a view past the first, sharing the game's light's world.
	var game_light := SubViewport.new()
	game_light.size = Vector2i(160, 90)
	root.add_child(own(game_light) as Node)
	views.use_light(game_light)
	check_equal(views.light_buffers.size(), 2, "a light buffer for each view past the first")
	for buffer in views.light_buffers:
		check(buffer.world_2d == game_light.world_2d, "%s draws the game light's world" % buffer.name)
	views.use_light(null)
	check(views.light_buffers.is_empty(), "the light off: no extra buffers")
	var made: Array[SubViewport] = views.views.duplicate()
	root.remove_child(views)
	check_equal(root.canvas_cull_mask, mask_before, "the root draws the world again as the views leave")
	views.free()
	for view in made:
		check(not is_instance_valid(view), "the views go with the node")


func test_no_split_changes_nothing() -> void:
	var mask_before: int = root.canvas_cull_mask
	var views: ViewsScript = own(ViewsScript.new(0)) as ViewsScript
	root.add_child(views)
	check(views.views.is_empty(), "no views")
	check_equal(root.canvas_cull_mask, mask_before, "the root still draws the world")
	views.start_measuring()
	views.place(PackedVector2Array([Vector2.ZERO]))
	check_equal(views.frames_counted(), 1, "the baseline's frames are counted")
	root.remove_child(views)


func test_the_runner_scenarios() -> void:
	var runner: Node = own(RunnerScript.new())
	var rows: Array[Dictionary] = runner.get(&"rows")
	var all: Array[int] = runner.get(&"scenarios")
	check_equal(all.size(), rows.size(), "every scenario runs by default")
	var counts: Dictionary = {}
	for row in rows:
		var label: String = row["label"]
		check(not label.contains(","), "%s can be named in --only (no comma)" % label)
		counts[int(row["views"])] = true
		check_equal(bool(row.get("desktop_only", false)), label.begins_with("desktop"), "%s is desktop only exactly when it is the desktop's" % label)
	for count in [0, 2, 3, 4]:
		check(counts.has(count), "a scenario with %d views" % count)
	var web: Array[int] = RunnerScript.scenarios_for(all, true, rows)
	check(not web.is_empty(), "the web build has scenarios")
	for index in web:
		check(String(rows[index]["label"]).begins_with("web"), "the web build runs only the web's")
	var named: Array[int] = RunnerScript.scenarios_named(all, PackedStringArray(["web 4 views"]), rows)
	check_equal(named.size(), 1, "--only picks one scenario by its label")
	check_equal(runner.get(&"result_word"), "SPLIT VIEWS", "the run ends with SPLIT VIEWS OK")


## A stand-in for Feel's spectacle: the two settings a scenario changes.
class StandInSpectacle:
	extends Node
	var spell_light: bool = true
	var mote_cap: int = 32768
	var light: Node = null

	func set_spell_light(on: bool) -> bool:
		spell_light = on
		return on

	func set_mote_cap(cap: int) -> int:
		mote_cap = cap
		return cap


class StandInFeel:
	extends Node
	var shown: Node = null

	func spectacle() -> Node:
		return shown


func test_a_scenario_puts_the_light_and_the_motes_back() -> void:
	var runner: Node = own(RunnerScript.new())
	var feel := own(StandInFeel.new()) as StandInFeel
	var spectacle := own(StandInSpectacle.new()) as StandInSpectacle
	spectacle.mote_cap = 8192
	feel.shown = spectacle
	runner.set(&"_feel", feel)
	var rows: Array[Dictionary] = runner.get(&"rows")
	for row in rows:
		runner.call(&"_scenario_started", row)
		check_equal(spectacle.spell_light, bool(row.get("light", true)), "%s: the light as the scenario asks" % row["label"])
		check_equal(spectacle.mote_cap, int(row.get("motes", 8192)), "%s: the motes as the scenario asks" % row["label"])
		runner.call(&"_scenario_ending")
		check(spectacle.spell_light, "%s: the light is back on" % row["label"])
		check_equal(spectacle.mote_cap, 8192, "%s: the motes are back" % row["label"])
		check(runner.get(&"_views") == null, "%s: the views are gone" % row["label"])
