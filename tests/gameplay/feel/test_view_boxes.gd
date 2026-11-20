extends "res://tests/support/suite.gd"
## Each view's own part of the world (`ViewBoxes`, gameplay/feel/view_boxes.gd; the performance pass,
## the owner's decision of 2026-11-20): split, the air, the mote sources and the shadows work by each
## view's box, not one box round them all; a point picked over the boxes is as likely anywhere they
## cover, overlap or not, so the air over two views is as thick as over one picture. (The motes are
## drawn by room since the performance pass's follow-up: `test_mote_regions.gd`.)

const ViewBoxesScript := preload("res://gameplay/feel/view_boxes.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const AirMotesScript := preload("res://gameplay/feel/air_motes.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")

const FRAME: float = 1.0 / 60.0


func test_each_view_has_its_own_box() -> void:
	var views := ScreenViewsScript.new()
	views.screen = Vector2(640.0, 360.0)
	views.count = 2
	views.set_view(0, 1, Transform2D(0.0, Vector2.ONE, 0.0, Vector2(0.0, 0.0)), Vector2(160.0, 180.0))
	views.set_view(1, 2, Transform2D(0.0, Vector2.ONE, 0.0, Vector2(-3000.0, 0.0)), Vector2(480.0, 180.0))
	_cell(views, 0, [Vector2(0.0, 0.0), Vector2(320.0, 0.0), Vector2(320.0, 360.0), Vector2(0.0, 360.0)])
	_cell(views, 1, [Vector2(320.0, 0.0), Vector2(640.0, 0.0), Vector2(640.0, 360.0), Vector2(320.0, 360.0)])
	var boxes := ViewBoxesScript.new()
	boxes.set_views(views)
	check_equal(boxes.count, 2, "a box a view")
	check(boxes.boxes[0].is_equal_approx(Rect2(0.0, 0.0, 320.0, 360.0)), "the first view's own part (%s)" % boxes.boxes[0])
	check(boxes.boxes[1].is_equal_approx(Rect2(3320.0, 0.0, 320.0, 360.0)), "the second's, far off (%s)" % boxes.boxes[1])
	check(views.world_box().is_equal_approx(Rect2(0.0, 0.0, 3640.0, 360.0)), "the box round them both holds the rooms between")
	check(boxes.has_point(Vector2(100.0, 100.0)) and boxes.has_point(Vector2(3400.0, 100.0)), "each view's part is seen")
	check(not boxes.has_point(Vector2(1800.0, 100.0)), "the world between them is not")
	check(boxes.has_point(Vector2(330.0, 100.0), 16.0) and not boxes.has_point(Vector2(400.0, 100.0), 16.0), "a margin past a box")


func _cell(views: ScreenViewsScript, view: int, corners: Array) -> void:
	views.set_corners(view, corners.size())
	for at in corners.size():
		views.set_corner(view, at, corners[at])


func test_a_point_picked_over_overlapping_boxes_is_as_likely_anywhere() -> void:
	var boxes := ViewBoxesScript.new()
	boxes.count = 0
	boxes.add(Rect2(0.0, 0.0, 100.0, 100.0))
	boxes.add(Rect2(50.0, 0.0, 100.0, 100.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var left: int = 0
	var both: int = 0
	var right: int = 0
	var refused: int = 0
	for n in 30000:
		var at: Vector2 = boxes.pick(rng, 0.0, Rect2())
		if not at.is_finite():
			refused += 1
		elif at.x < 50.0:
			left += 1
		elif at.x < 100.0:
			both += 1
		else:
			right += 1
	# Each third of the cover (50 x 100 px) is as likely: the overlap is not counted twice.
	for got: int in [left, both, right]:
		check(absf(float(got) / 7500.0 - 1.0) < 0.06, "a third of the cover gets its share (%d, %d, %d of 30000, %d refused)" % [left, both, right, refused])
	check(absf(float(refused) / 7500.0 - 1.0) < 0.06, "the overlap's second count is refused")
	check_equal(boxes.total_area(0.0, Rect2()), 20000.0, "the area counted twice where they meet")
	var bounded: Rect2 = Rect2(0.0, 0.0, 60.0, 100.0)
	for n in 200:
		var at: Vector2 = boxes.pick(rng, 0.0, bounded)
		check(not at.is_finite() or bounded.has_point(at), "inside the bounds")


func test_the_air_over_two_views_is_as_thick_as_over_one_and_only_there() -> void:
	var kind := MoteKind.new()
	kind.id = &"dust_here"
	kind.lit_only = true
	kind.gravity = 0.0
	kind.drag = 0.3
	kind.speed = Vector2(1.0, 4.0)
	kind.up = Vector2(0.0, 1.0)
	kind.life = Vector2(3.0, 3.0)
	var motes: MotesScript = own(MotesScript.new(65536, 0, [kind] as Array[MoteKind])) as MotesScript
	root.add_child(motes)
	var source := MoteSource.new()
	source.kind = &"dust_here"
	source.rate = 40.0
	source.spread = 360.0
	source.colours = [&"bone"] as Array[StringName]
	var bounds := Rect2(0.0, 0.0, 4000.0, 400.0)
	var given: Array[int] = []
	var boxes_of: Array = [[Rect2(100.0, 100.0, 200.0, 100.0)], [Rect2(100.0, 100.0, 200.0, 100.0), Rect2(3000.0, 100.0, 200.0, 100.0)]]
	for set_of: Array in boxes_of:
		var air := AirMotesScript.new(RampTableScript.new())
		air.use(source)
		var seen := ViewBoxesScript.new()
		seen.count = 0
		for box: Rect2 in set_of:
			seen.add(box)
		var clock: float = 0.0
		for frame in 240:
			air.give_off_in(clock, motes, seen, bounds)
			motes.step(clock)
			clock += FRAME
		given.append(air.given)
		check(air.given_box.position.x >= 100.0 - AirMotesScript.VIEW_MARGIN, "never left of the first view")
		if set_of.size() == 1:
			check(air.given_box.end.x <= 300.0 + AirMotesScript.VIEW_MARGIN, "with one view, only near it")
	var ratio: float = float(given[1]) / float(maxi(given[0], 1))
	check(ratio > 1.8 and ratio < 2.2, "two views of the same size give off twice one's: each as thick (%d, %d)" % [given[0], given[1]])

