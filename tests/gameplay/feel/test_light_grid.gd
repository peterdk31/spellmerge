extends "res://tests/support/suite.gd"
## Grid lighting (gameplay/feel/light_grid.gd; the owner's decision of 2026-11-21): the light at each
## cell's middle with the GPU light's falloff (light.gdshader's, before), colours and blocking; the views laid in one atlas on
## the world's grid; the native kernel (`MoteKernel.light_grid_*`) the same as the GDScript to the
## byte, over seeded rows of every kind, beams and boxes.

const LightGridScript := preload("res://gameplay/feel/light_grid.gd")
const NativeScript := preload("res://core/native/native.gd")

const ROWS: int = 160


## A grid of `cell` px over views (one zoomed in, one far off; a third over the first's middle with
## `overlap`), its tints set, boxes that block light.
func _grid(cell: float = LightGridScript.CELL, overlap: bool = false) -> LightGridScript:
	var grid := LightGridScript.new()
	grid.set_cell(cell)
	var boxes := PackedVector4Array([Vector4(-40.0, -30.0, 600.0, 330.0), Vector4(1985.0, 993.0, 2310.0, 1170.0), Vector4(150.0, 90.0, 470.0, 270.0)])
	grid.fit(boxes, 3 if overlap else 2)
	var tints := PackedColorArray()
	tints.resize(32)
	for layer in 32:
		tints[layer] = Color(0, 0, 0, 0)
	# A few layers carry an infusion's tint (alpha the mark); the rest none.
	tints[2] = Color(0.31, 0.84, 0.86, LightGridScript.INFUSION_MARK)
	tints[5] = Color(0.95, 0.76, 0.19, LightGridScript.INFUSION_MARK)
	tints[9] = Color(0.63, 0.19, 0.60, LightGridScript.INFUSION_MARK)
	tints[14] = Color(0.12, 0.61, 0.55, LightGridScript.INFUSION_MARK)
	grid.use_tints(tints)
	var walls := PackedVector4Array([Vector4(100.0, 100.0, 132.0, 116.0), Vector4(300.0, 60.0, 340.0, 200.0), Vector4(2050.0, 1050.0, 2070.0, 1060.0)])
	var bodies := PackedVector4Array([Vector4(100.0, 60.0, 132.0, 1.0), Vector4(300.0, 60.0, 340.0, 0.6), Vector4(2050.0, 1010.0, 2070.0, 0.0)])
	grid.set_blockers(walls, bodies, 3)
	return grid


## Seeded rows of `kind` round the two views (some off them), each field over its range.
static func _rows(kind: int, seed_of: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_of
	var rows := PackedFloat32Array()
	rows.resize(ROWS * LightGridScript.STRIDE)
	for i in ROWS:
		var at: int = i * LightGridScript.STRIDE
		var place := Vector2(rng.randf_range(-80.0, 640.0), rng.randf_range(-60.0, 380.0))
		if i % 3 == 0:
			place = Vector2(rng.randf_range(1950.0, 2350.0), rng.randf_range(960.0, 1200.0))
		var turn: float = rng.randf_range(-PI, PI)
		var size: float = rng.randf_range(4.0, 90.0)
		rows[at] = cos(turn) * size
		rows[at + 4] = sin(turn) * size
		rows[at + 1] = -sin(turn) * size * rng.randf_range(0.2, 1.0)
		rows[at + 5] = cos(turn) * size * rng.randf_range(0.2, 1.0)
		rows[at + 3] = place.x
		rows[at + 7] = place.y
		rows[at + 2] = rng.randf_range(0.5, 1.6)
		rows[at + 6] = rng.randf_range(0.0, 1.4)
		# The colour: player and zoom in red, the look bits in green, blue and alpha.
		var red: int = rng.randi_range(0, 3) + 4 * rng.randi_range(0, 5)
		rows[at + 8] = float(red) / 255.0
		var bits: int = 0
		for layer in [2, 5, 9, 14, 3, 18]:
			if rng.randf() < 0.3:
				bits |= 1 << (layer - 1)
		if rng.randf() < 0.15:
			bits |= 1 << (LightGridScript.ENEMY_RAMP - 1)
		if rng.randf() < 0.1:
			bits |= 1 << (LightGridScript.EXACT - 1)
		rows[at + 9] = float(bits & 255) / 255.0
		rows[at + 10] = float((bits >> 8) & 255) / 255.0
		rows[at + 11] = float((bits >> 16) & 255) / 255.0
		# The core: plain (white), a palette shade, or anything.
		var core := Color(1.0, 1.0, 1.0)
		var pick: float = rng.randf()
		if pick < 0.4:
			var m: int = rng.randi_range(0, 20)
			core = Color(LightGridScript.SHADES[m * 3], LightGridScript.SHADES[m * 3 + 1], LightGridScript.SHADES[m * 3 + 2])
		elif pick < 0.8:
			core = Color(rng.randf(), rng.randf(), rng.randf())
		rows[at + 12] = core.r
		rows[at + 13] = core.g
		rows[at + 14] = core.b
		rows[at + 15] = rng.randf()
		if kind == LightGridScript.ROWS_SHOT:
			# Live or not (the flags), a speck now and then.
			rows[at + 5] = 1.0 if rng.randf() < 0.85 else 2.0
		elif kind == LightGridScript.ROWS_SPOT:
			# A spot's colour and strength, flicker, seed and where it stands.
			rows[at + 8] = rng.randf()
			rows[at + 9] = rng.randf()
			rows[at + 10] = rng.randf()
			rows[at + 11] = rng.randf_range(0.2, 1.0)
			rows[at + 12] = rng.randf_range(0.0, 0.5)
			rows[at + 13] = rng.randf()
			rows[at + 14] = rng.randf_range(-6.0, 6.0)
			rows[at + 15] = rng.randf_range(0.0, 30.0)
	return rows


## Every kind of row and two beams into `grid` (blocked as the light blocks them), then baked.
static func _light(grid: LightGridScript) -> void:
	grid.clear()
	grid.add_rows(_rows(LightGridScript.ROWS_SHOT, 11), ROWS, LightGridScript.ROWS_SHOT, 1.0, 0.0, 3.25, false)
	grid.add_rows(_rows(LightGridScript.ROWS_RUNE, 12), ROWS, LightGridScript.ROWS_RUNE, 1.0, 0.0, 3.25, false)
	grid.add_rows(_rows(LightGridScript.ROWS_FLASH, 13), ROWS, LightGridScript.ROWS_FLASH, 1.6, 10.0, 3.25, true)
	grid.add_rows(_rows(LightGridScript.ROWS_CUE, 14), ROWS, LightGridScript.ROWS_CUE, 1.0, 0.0, 3.25, true)
	grid.add_rows(_rows(LightGridScript.ROWS_SPOT, 15), ROWS, LightGridScript.ROWS_SPOT, 1.0, 0.0, 3.25, true)
	grid.add_rows(_rows(LightGridScript.ROWS_SPOT, 16), ROWS, LightGridScript.ROWS_SPOT, 1.0, 0.0, 7.5, false)
	var path := PackedVector3Array([Vector3(20.0, 300.0, 0.0), Vector3(200.0, 120.0, 0.0), Vector3(205.0, 121.0, 0.0), Vector3(580.0, 40.0, 0.0)])
	grid.add_beam(path, path.size(), 24.0, Color(0.9, 0.5, 0.2))
	var far := PackedVector3Array([Vector3(2000.0, 1100.0, 0.0), Vector3(2300.0, 1000.0, 0.0)])
	grid.add_beam(far, far.size(), 18.0, Color(0.2, 0.6, 1.0))
	# A piece of no length (a beam's two points the same), and a beam lit by fewer points than its path.
	var still := PackedVector3Array([Vector3(400.0, 200.0, 0.0), Vector3(400.0, 200.0, 0.0), Vector3(450.0, 260.0, 0.0), Vector3(9999.0, 9999.0, 0.0)])
	grid.add_beam(still, 3, 20.0, Color(0.5, 1.0, 0.4))
	# A beam narrower than a cell (its reach raised to a cell, on each side alike).
	var thin := PackedVector3Array([Vector3(60.0, 330.0, 0.0), Vector3(500.0, 290.0, 0.0)])
	grid.add_beam(thin, thin.size(), 1.5, Color(1.0, 0.8, 0.6))
	grid.bake()


func test_the_views_lie_on_the_worlds_grid_side_by_side() -> void:
	var grid := LightGridScript.new()
	grid.fit(PackedVector4Array([Vector4(-13.0, 5.0, 627.0, 365.0), Vector4(1000.0, 1000.0, 1160.0, 1090.0)]), 2)
	check_equal(grid.view_count, 2, "two views")
	check_equal(Vector2(grid.view_origin[0], grid.view_origin[1]), Vector2(-16.0, 0.0), "the first cell's corner on the world's grid")
	check_equal(Vector2i(grid.view_size[0], grid.view_size[1]), Vector2i(81, 46), "its cells cover its box")
	check_equal(Vector2i(grid.view_at[2], grid.view_at[3]), Vector2i(81, 0), "the second view's cells beside the first's")
	check(grid.atlas_width >= 81 + 20 and grid.atlas_height >= 46, "the atlas holds both")
	var texture: ImageTexture = grid.texture
	grid.fit(PackedVector4Array([Vector4(0.0, 0.0, 320.0, 180.0)]), 1)
	check(grid.texture == texture, "a smaller view keeps the atlas (nothing made)")
	grid.set_cell(16.0)
	grid.fit(PackedVector4Array([Vector4(0.0, 0.0, 320.0, 180.0)]), 1)
	check_equal(Vector2i(grid.view_size[0], grid.view_size[1]), Vector2i(20, 12), "a coarser cell, fewer cells")


func test_a_light_falls_off_as_the_shader_draws_it() -> void:
	var grid := LightGridScript.new()
	grid.fit(PackedVector4Array([Vector4(0.0, 0.0, 320.0, 180.0)]), 1)
	var rows := PackedFloat32Array()
	rows.resize(LightGridScript.STRIDE)
	# A spot at a cell's middle, reach 40, white, full strength, no flicker.
	rows[0] = 40.0
	rows[3] = 100.0
	rows[7] = 100.0
	rows[8] = 1.0
	rows[9] = 1.0
	rows[10] = 1.0
	rows[11] = 1.0
	grid.clear()
	grid.add_rows(rows, 1, LightGridScript.ROWS_SPOT, 1.0, 0.0, 0.0, false)
	var middle: Color = grid.light_at(0, Vector2(100.0, 100.0))
	check(is_equal_approx(middle.r, 1.0) and is_equal_approx(middle.b, 1.0), "full at its middle (%s)" % middle)
	var near: Color = grid.light_at(0, Vector2(120.0, 100.0))
	var at := Vector2(124.0, 100.0)
	var want: float = pow(1.0 - (at - Vector2(100.0, 100.0)).length() / 40.0, 2.0)
	check(is_equal_approx(near.r, want), "(1 - distance / reach)² at a cell's middle (%s against %s)" % [near.r, want])
	check_equal(grid.light_at(0, Vector2(150.0, 100.0)), Color.BLACK, "nothing past its reach")


func test_the_native_kernel_lights_the_grid_as_the_gdscript_to_the_byte() -> void:
	if not NativeScript.loaded():
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "the native module is loaded")
		return
	_check_native(LightGridScript.CELL, false)


## At a 12 px cell (not exact in binary sums) and with a view over another's middle (rows lit in two
## views at once), the kernel and the GDScript still agree to the byte.
func test_the_native_kernel_agrees_at_a_coarser_cell_and_overlapping_views() -> void:
	if not NativeScript.loaded():
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "the native module is loaded")
		return
	_check_native(12.0, true)


## At the split's cheaper 16 px cell (SpellLight.SPLIT_CHEAP_CELL), the same.
func test_the_native_kernel_agrees_at_the_splits_coarser_cell() -> void:
	if not NativeScript.loaded():
		check(OS.get_environment("SPELLMERGE_NATIVE") != "required", "the native module is loaded")
		return
	_check_native(16.0, false)


func _check_native(cell: float, overlap: bool) -> void:
	var script_grid: LightGridScript = _grid(cell, overlap)
	check(not script_grid.use_native(false), "the GDScript")
	_light(script_grid)
	var native_grid: LightGridScript = _grid(cell, overlap)
	check(native_grid.use_native(true), "the kernel matches the grid's numbers and members")
	_light(native_grid)
	var differ: int = 0
	var first_differ: int = -1
	var same_size: bool = native_grid.rgb.size() == script_grid.rgb.size()
	for i in script_grid.rgb.size() if same_size else 0:
		if native_grid.rgb[i] != script_grid.rgb[i]:
			differ += 1
			if first_differ < 0:
				first_differ = i
	check(native_grid.rgb.to_byte_array() == script_grid.rgb.to_byte_array(), "every cell's light the same to the bit (%d channels differ, the first %d)" % [differ, first_differ])
	check(native_grid.baked() == script_grid.baked(), "and every byte handed to the texture")
	var lit: int = 0
	var blocked: int = 0
	for c in script_grid.atlas_width * script_grid.atlas_height:
		if script_grid.rgb[c * 3] + script_grid.rgb[c * 3 + 1] + script_grid.rgb[c * 3 + 2] > 0.0:
			lit += 1
	# The same lights with no boxes light more: the boxes were reached.
	var open: LightGridScript = _grid(cell, overlap)
	open.set_blockers(PackedVector4Array(), PackedVector4Array(), 0)
	_light(open)
	if open.rgb != script_grid.rgb:
		blocked = 1
	check(lit > 1000, "most of the views lit (%d cells)" % lit)
	check_equal(blocked, 1, "the boxes stopped some light")


func test_a_rows_glow_is_its_looks() -> void:
	var grid: LightGridScript = _grid()
	# A plain shot of player 2: its ramp's base toward its light.
	var plain: Vector3 = grid.look_glow(1.0, 1.0, 1.0, 1, 0, 0, 0, false)
	check(plain.is_equal_approx(Vector3(0.851 + (0.961 - 0.851) * 0.35, 0.278 + (0.604 - 0.278) * 0.35, 0.478 + (0.722 - 0.478) * 0.35)), "a plain look glows in its player's colours")
	# An enemy's: the fifth ramp.
	var enemy: Vector3 = grid.look_glow(1.0, 1.0, 1.0, 1, 0, 0, 1 << (LightGridScript.ENEMY_RAMP - 17), false)
	check(enemy.is_equal_approx(Vector3(0.651 + (0.890 - 0.651) * 0.35, 0.541 + (0.812 - 0.541) * 0.35, 0.165 + (0.420 - 0.165) * 0.35)), "an enemy's in Blight")
	# A fire core with an ice infusion: it glows in the ice's material.
	var fire_ice: Vector3 = grid.look_glow(0.878, 0.349, 0.184, 0, 1 << 1, 0, 0, false)
	check(fire_ice.is_equal_approx(Vector3(0.310 + (0.769 - 0.310) * 0.35, 0.839 + (0.965 - 0.839) * 0.35, 0.863 + (0.949 - 0.863) * 0.35)), "a second infusion's material glows")
	check(grid.look_glow(0.878, 0.349, 0.184, 0, 1 << 1, 0, 0, true).is_equal_approx(Vector3(0.878 + (1.0 - 0.878) * 0.35, 0.349 + (0.635 - 0.349) * 0.35, 0.184 + (0.235 - 0.184) * 0.35)), "a beam's own infusions: the first material alone")


## Every light reaches at least a cell each way (the owner, 2026-11-21): a light smaller than a cell,
## standing on a corner between four cells' middles, still lights them, and the kernel agrees.
func test_a_light_smaller_than_a_cell_still_lights_the_cells_round_it() -> void:
	for native: bool in [false, true]:
		if native and not NativeScript.loaded():
			continue
		var grid := LightGridScript.new()
		grid.use_native(native)
		grid.fit(PackedVector4Array([Vector4(0.0, 0.0, 320.0, 180.0)]), 1)
		var rows := PackedFloat32Array()
		rows.resize(LightGridScript.STRIDE)
		# A spot of reach 2 px on the corner of four cells (their middles 4 px off each way, 5.7 px away).
		rows[0] = 2.0
		rows[3] = 96.0
		rows[7] = 96.0
		rows[8] = 1.0
		rows[9] = 1.0
		rows[10] = 1.0
		rows[11] = 1.0
		grid.clear()
		grid.add_rows(rows, 1, LightGridScript.ROWS_SPOT, 1.0, 0.0, 0.0, false)
		for at: Vector2 in [Vector2(92.0, 92.0), Vector2(100.0, 92.0), Vector2(92.0, 100.0), Vector2(100.0, 100.0)]:
			check(grid.light_at(0, at).r > 0.0, "the cell at %s is lit (native %s)" % [at, native])
		# The next cells' middles are 12.6 px away: past one cell's reach.
		for at: Vector2 in [Vector2(108.0, 92.0), Vector2(84.0, 92.0), Vector2(92.0, 108.0)]:
			check_equal(grid.light_at(0, at), Color.BLACK, "but the cell at %s, past a cell's reach, is not (native %s)" % [at, native])
		# A beam narrower than a cell too.
		grid.clear()
		# On a cells' edge, between two rows' middles (4 px off each side).
		grid.add_beam(PackedVector3Array([Vector3(40.0, 48.0, 0.0), Vector3(200.0, 48.0, 0.0)]), 2, 1.0, Color.WHITE)
		check(grid.light_at(0, Vector2(120.0, 52.0)).r > 0.0 and grid.light_at(0, Vector2(120.0, 44.0)).r > 0.0, "a beam of reach 1 px lights the cells either side of it (native %s)" % native)
		check_equal(grid.light_at(0, Vector2(120.0, 60.0)), Color.BLACK, "but not the rows past those (native %s)" % native)
		check_equal(grid.light_at(0, Vector2(120.0, 36.0)), Color.BLACK, "nor above (native %s)" % native)
