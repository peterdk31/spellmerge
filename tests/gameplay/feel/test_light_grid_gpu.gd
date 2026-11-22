extends "res://tests/support/suite.gd"
## The light grid worked out by the GPU (gameplay/feel/light_grid_gpu.gd; the owner's decision of
## 2026-11-22) against the CPU's (the GDScript's, LightKernel's to the bit) over the same seeded rows
## of every kind, beams and boxes (test_light_grid.gd's): every cell within a byte a channel, most
## the same. It needs a renderer with compute (the Mobile renderer, `GpuCompute.available`): headless,
## as the unit tests run, it checks only that the grid stays on the CPU there. Under the Mobile renderer:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-method mobile --script res://tests/support/run.gd -- res://tests/gameplay/feel/test_light_grid_gpu.gd

const LightGridScript := preload("res://gameplay/feel/light_grid.gd")
const LightGridTest := preload("res://tests/gameplay/feel/test_light_grid.gd")

## How far a channel of a cell may lie from the CPU's (bytes): the shader works in floats where the
## CPU works in doubles, so a cell's sum may round to the next byte.
const BYTES_APART_MOST: int = 1


func after_each() -> void:
	GpuCompute.allowed = true


func test_with_no_compute_the_grid_stays_on_the_cpu() -> void:
	GpuCompute.allowed = false
	var grid: LightGridScript = LightGridTest._grid()
	check(not grid.use_gpu(true), "not on the GPU when GPU effects are not allowed")
	check(grid.texture is ImageTexture, "its texture the CPU's")
	check(not grid.can_split() or grid.kernel != null, "the views split only in the kernel")


func test_the_gpu_lights_the_grid_as_the_cpu_within_a_byte() -> void:
	if not GpuCompute.available():
		check(not LightGridTest._grid().use_gpu(true), "no compute here (headless or Compatibility): the CPU's grid")
		return
	for cell: float in [8.0, 16.0]:
		_compare(cell, false)
	_compare(12.0, true)


func test_a_frame_with_no_light_is_dark_on_the_gpu() -> void:
	if not GpuCompute.available():
		return
	var grid: LightGridScript = LightGridTest._grid()
	check(grid.use_gpu(true), "on the GPU")
	LightGridTest._light(grid)
	grid.clear()
	grid.bake()
	var bytes: PackedByteArray = grid.gpu.read_back(grid.atlas_width, grid.atlas_height)
	var lit: int = 0
	for c in grid.atlas_width * grid.atlas_height:
		if bytes[c * 4] + bytes[c * 4 + 1] + bytes[c * 4 + 2] > 0:
			lit += 1
	check_equal(lit, 0, "last frame's light gone")
	grid.use_gpu(false)


func test_switching_back_hands_the_cpus_texture() -> void:
	if not GpuCompute.available():
		return
	var grid: LightGridScript = LightGridTest._grid()
	check(grid.use_gpu(true), "on the GPU")
	check(grid.texture is Texture2DRD, "the GPU's atlas")
	check(not grid.can_split(), "every view in one dispatch")
	check(not grid.use_gpu(false), "back on the CPU")
	check(grid.texture is ImageTexture, "the CPU's texture again")
	LightGridTest._light(grid)
	check(grid.light_at(0, Vector2(200.0, 120.0)).r > 0.0, "and the CPU lights its cells again")


func _compare(cell: float, overlap: bool) -> void:
	var cpu: LightGridScript = LightGridTest._grid(cell, overlap)
	cpu.use_native(true)
	LightGridTest._light(cpu)
	var on_gpu: LightGridScript = LightGridTest._grid(cell, overlap)
	check(on_gpu.use_gpu(true), "the grid on the GPU at %d px" % int(cell))
	# Twice: the second frame reads the other set of what is handed.
	LightGridTest._light(on_gpu)
	LightGridTest._light(on_gpu)
	var want: PackedByteArray = cpu.baked()
	var got: PackedByteArray = on_gpu.gpu.read_back(on_gpu.atlas_width, on_gpu.atlas_height)
	var same: int = 0
	var off_by_one: int = 0
	var further: int = 0
	var lit: int = 0
	var first_far: String = ""
	for c in cpu.atlas_width * cpu.atlas_height:
		var apart: int = 0
		for ch in 3:
			apart = maxi(apart, absi(int(want[c * 4 + ch]) - int(got[c * 4 + ch])))
		if want[c * 4] + want[c * 4 + 1] + want[c * 4 + 2] > 0:
			lit += 1
		if apart == 0:
			same += 1
		elif apart <= BYTES_APART_MOST:
			off_by_one += 1
		else:
			further += 1
			if first_far == "":
				first_far = "cell %d: cpu %s gpu %s" % [c, str(want.slice(c * 4, c * 4 + 3)), str(got.slice(c * 4, c * 4 + 3))]
	print("LIGHT GRID GPU: %d px cells%s: %d cells, %d lit, %d the same, %d a byte apart, %d further" % [int(cell), " overlapping" if overlap else "", cpu.atlas_width * cpu.atlas_height, lit, same, off_by_one, further])
	check(lit > 1000, "most of the views lit (%d cells)" % lit)
	check_equal(further, 0, "no cell more than %d byte from the CPU's (%s)" % [BYTES_APART_MOST, first_far])
	check(same * 100 >= (cpu.atlas_width * cpu.atlas_height) * 99, "nearly every cell the same (%d of %d)" % [same, cpu.atlas_width * cpu.atlas_height])
	on_gpu.use_gpu(false)
