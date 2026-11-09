extends "res://tests/support/suite.gd"
## A body's move against the wall grid (online-ready N6, core/projectiles/wall_slide.gd and the
## native module's BodyKernel): a circle stops at a wall, slides along it, settles in a corner,
## rounds an outer corner, fits a gap only as wide as it is, never crosses a wall however fast, and
## leaves a wall it stands in by the open side. The native kernel gives the GDScript's bits on every
## case and on a seeded spread of rooms. The actor moves by it (`Actor.move`), and its velocity is
## then what it moved by.
##
## Without the native module the GDScript is still checked (SPELLMERGE_NATIVE=required fails the
## comparison instead).
##
## godot --headless --path . --script res://tests/core/test_wall_slide.gd

const NativeScript := preload("res://core/native/native.gd")
const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

const CELL: float = 8.0
const W: int = 40
const H: int = 30

var _cells: PackedByteArray = PackedByteArray()


func before_each() -> void:
	super.before_each()
	_cells.resize(W * H)
	_cells.fill(0)


## Make the cells from (`x0`, `y0`) to (`x1`, `y1`), both included, walls.
func _wall(x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_cells[y * W + x] = 128


func _slide(from: Vector2, motion: Vector2, radius: float = 6.0) -> Vector2:
	return WallSlide.slide(_cells, W, H, CELL, Vector2.ZERO, from, motion, radius)


## The module's kernel, configured, or null (and a failure when the module is required).
func _kernel() -> Object:
	var kernel: Object = NativeScript.body_kernel()
	if kernel == null:
		if OS.get_environment("SPELLMERGE_NATIVE") == "required":
			check(false, "SPELLMERGE_NATIVE=required, but the native module is not loaded (ci/build/native.sh)")
		return null
	check(kernel.call(&"configure", {"ITERATIONS": WallSlide.ITERATIONS, "MIN_STRIDE": WallSlide.MIN_STRIDE}), "the kernel takes WallSlide's numbers")
	return kernel


func test_open_floor_moves_the_whole_way() -> void:
	check_equal(_slide(Vector2(50.0, 50.0), Vector2(30.0, -12.5)), Vector2(80.0, 37.5), "nothing near: from + motion")
	_wall(20, 0, 20, H - 1)
	check_equal(_slide(Vector2(50.0, 50.0), Vector2(30.0, -12.5)), Vector2(80.0, 37.5), "a wall far off changes nothing")


func test_a_wall_stops_the_body_its_radius_short() -> void:
	_wall(10, 0, 12, H - 1)  # x 80 to 104
	check_equal(_slide(Vector2(50.0, 100.0), Vector2(60.0, 0.0)), Vector2(74.0, 100.0), "it stops with its rim on the wall's face")
	check_equal(_slide(Vector2(130.0, 100.0), Vector2(-60.0, 0.0)), Vector2(110.0, 100.0), "from the other side too")
	check_equal(_slide(Vector2(74.0, 100.0), Vector2(5.0, 0.0)), Vector2(74.0, 100.0), "pressed against it, it stays")


func test_it_slides_along_a_wall() -> void:
	_wall(0, 20, W - 1, 22)  # y 160 to 184
	var to: Vector2 = _slide(Vector2(50.0, 140.0), Vector2(40.0, 40.0))
	check(is_equal_approx(to.x, 90.0), "the way along the wall is kept: %s" % to)
	check(is_equal_approx(to.y, 154.0), "the way into it is not: %s" % to)
	# Along the wall's face, touching it, across many cells' seams: no snag.
	check_equal(_slide(Vector2(20.0, 154.0), Vector2(200.0, 0.0)), Vector2(220.0, 154.0), "along a flat wall it never snags on a seam")


func test_it_settles_in_a_corner() -> void:
	_wall(0, 20, W - 1, 22)  # floor at y 160
	_wall(20, 0, 22, 22)  # wall at x 160
	var to: Vector2 = _slide(Vector2(120.0, 120.0), Vector2(80.0, 80.0))
	check(is_equal_approx(to.x, 154.0) and is_equal_approx(to.y, 154.0), "into an inner corner it rests its radius from both faces: %s" % to)


func test_it_rounds_an_outer_corner() -> void:
	_wall(10, 10, 14, 14)  # a block from (80, 80) to (120, 120)
	# Walking down past the block's left face, then on: it goes on past the corner.
	var to: Vector2 = _slide(Vector2(74.0, 60.0), Vector2(0.0, 100.0))
	check_equal(to, Vector2(74.0, 160.0), "beside the block, along its face, it walks on")
	# Walking down 4 px inside the face's line: the corner turns it aside and it walks on, slowed a
	# little by the turn.
	to = _slide(Vector2(76.0, 50.0), Vector2(0.0, 60.0))
	check(is_equal_approx(to.x, 74.0) and to.y > 100.0 and to.y <= 110.0, "it slips round the corner and on down the face: %s" % to)


func test_it_fits_a_gap_only_as_wide_as_it_is() -> void:
	_wall(10, 0, 12, 9)  # x 80 to 104, y 0 to 80
	_wall(10, 12, 12, H - 1)  # from y 96: a gap of 16 px from y 80 to 96
	check_equal(_slide(Vector2(50.0, 88.0), Vector2(90.0, 0.0)), Vector2(140.0, 88.0), "a body 12 across walks through a gap of 16")
	_cells.fill(0)
	_wall(10, 0, 12, 10)
	_wall(10, 12, 12, H - 1)  # a gap of 8 px from y 88 to 96
	var to: Vector2 = _slide(Vector2(50.0, 92.0), Vector2(90.0, 0.0))
	check(to.x <= 80.0, "a body 12 across does not fit a gap of 8: %s" % to)


func test_it_never_crosses_a_wall_however_fast() -> void:
	_wall(20, 0, 20, H - 1)  # one cell thick, x 160 to 168
	for speed: float in [10.0, 50.0, 100.0, 250.0, 600.0, 2000.0]:
		for radius: float in [0.5, 2.0, 5.0, 6.0, 12.0]:
			var to: Vector2 = _slide(Vector2(100.0, 100.0), Vector2(speed, speed * 0.02), radius)
			check(to.x <= 160.0, "at %s px a step a body of radius %s stays on its side: %s" % [speed, radius, to])


func test_a_body_in_a_wall_leaves_by_the_open_side() -> void:
	_wall(10, 0, 14, H - 1)  # x 80 to 120
	var to: Vector2 = _slide(Vector2(83.0, 100.0), Vector2.ZERO)
	check(is_equal_approx(to.x, 74.0), "near the left face it leaves on the left: %s" % to)
	to = _slide(Vector2(117.0, 100.0), Vector2.ZERO)
	check(is_equal_approx(to.x, 126.0), "near the right face, on the right: %s" % to)
	# Deep in the wall, in a cell with walls all round, nothing pushes it into another wall.
	to = _slide(Vector2(100.0, 100.0), Vector2.ZERO)
	check(to == Vector2(100.0, 100.0) or to.x <= 74.0 or to.x >= 126.0, "deep inside it is not pushed into another wall: %s" % to)


func test_outside_the_grid_is_open() -> void:
	_wall(0, 0, 0, H - 1)
	check_equal(_slide(Vector2(-50.0, 40.0), Vector2(-30.0, 0.0)), Vector2(-80.0, 40.0), "beyond the grid it walks free")


func test_the_native_kernel_gives_the_same_bits() -> void:
	var kernel: Object = _kernel()
	if kernel == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261109
	var cases: int = 0
	var pushed: int = 0
	for room in 60:
		_cells.fill(0)
		if room % 2 == 0:
			# Blocks: faces, inner and outer corners, gaps.
			for block in rng.randi_range(0, 12):
				var x0: int = rng.randi_range(0, W - 1)
				var y0: int = rng.randi_range(0, H - 1)
				_wall(x0, y0, mini(x0 + rng.randi_range(0, 6), W - 1), mini(y0 + rng.randi_range(0, 6), H - 1))
		else:
			# Scattered cells: corners everywhere (a Wall card's stones are laid as such).
			for i in W * H:
				if rng.randf() < 0.18:
					_cells[i] = 1
		var origin: Vector2 = Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-40.0, 40.0))
		for n in 300:
			var from: Vector2 = origin + Vector2(rng.randf_range(-20.0, W * CELL + 20.0), rng.randf_range(-20.0, H * CELL + 20.0))
			var motion: Vector2 = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 40.0) if n % 5 != 0 else Vector2.ZERO
			if n % 7 == 0:
				motion *= 20.0
			var radius: float = [0.0, 0.7, 3.0, 5.0, 6.0, 7.0, 12.0, 20.0][n % 8]
			var gd: Vector2 = WallSlide.slide(_cells, W, H, CELL, origin, from, motion, radius)
			var native: Vector2 = kernel.call(&"slide", _cells, W, H, CELL, origin, from, motion, radius)
			cases += 1
			if gd != from + motion:
				pushed += 1
			if var_to_bytes(gd) != var_to_bytes(native):
				check(false, "room %d case %d: GDScript %s, native %s (from %s by %s, radius %s)" % [room, n, gd, native, from, motion, radius])
				return
	check(cases == 18000, "every case compared: %d" % cases)
	check(pushed > cases / 3, "most cases met a wall, so the pushes are compared: %d of %d" % [pushed, cases])


func test_the_manager_answers_by_its_grid_and_either_side() -> void:
	var mgr := own(ManagerScript.new()) as ManagerScript
	mgr.set_bounds(Rect2(0.0, 0.0, 320.0, 240.0))
	check_equal(mgr.slide_body(Vector2(50.0, 100.0), Vector2(60.0, 0.0), 6.0), Vector2(110.0, 100.0), "no walls: the whole way")
	mgr.set_walls([Rect2(80.0, 0.0, 24.0, 240.0)])
	var native_side: Vector2 = mgr.slide_body(Vector2(50.0, 100.0), Vector2(60.0, 0.0), 6.0)
	check_equal(native_side, Vector2(74.0, 100.0), "a room wall stops it")
	mgr.native = false
	check_equal(mgr.slide_body(Vector2(50.0, 100.0), Vector2(60.0, 0.0), 6.0), native_side, "the GDScript says the same")


func test_an_actor_moves_by_it_and_keeps_its_slide() -> void:
	var mgr := own(ManagerScript.new()) as ManagerScript
	mgr.set_bounds(Rect2(0.0, 0.0, 320.0, 240.0))
	mgr.set_walls([Rect2(0.0, 160.0, 320.0, 24.0)])
	var body := own(Actor.new()) as Actor
	body.projectiles = mgr
	var mover := Mover.new()
	mover.body_radius = 6.0
	body.mover = mover
	body.position = Vector2(50.0, 150.0)
	body.velocity = Vector2(600.0, 600.0)
	body.move(1.0 / 60.0)
	check(is_equal_approx(body.position.x, 60.0) and is_equal_approx(body.position.y, 154.0), "it slides along the floor's wall: %s" % body.position)
	check(is_equal_approx(body.velocity.x, 600.0) and is_equal_approx(body.velocity.y, 240.0), "its velocity is what it moved by: %s" % body.velocity)
	mover.free()
