extends RefCounted
## A stand-in grass for the cover screenshots (ground cover GC3 and GC4, docs/milestones/ground-cover.md):
## the test grass's states (tests/core/fixtures/cover_content) with a sheet of seven frames drawn in
## code (three at rest, two burning, one of ash, one trampled), before the game has art of its own
## (GC8's).

const FIXTURE: String = "res://tests/core/fixtures/cover_content/cover/test_grass/test_grass.tres"
## The grass's colours (docs/STYLE.md's greens: dark, base, light).
const DARK := Color("1e4d2b")
const BASE := Color("3d8a3a")
const LIGHT := Color("8fcf5a")
## The frame its tufts draw trampled.
const TRAMPLED_FRAME: int = 6


## The stand-in grass, filling `biomes` at `density` in clumps of `clump`; its resting tufts draw
## `TRAMPLED_FRAME` trampled.
static func make(biomes: Array[StringName], density: float = 0.06, clump: int = 3) -> CoverKind:
	var kind := (load(FIXTURE) as CoverKind).duplicate(true) as CoverKind
	kind.id = &"preview_grass"
	kind.biomes = biomes
	kind.fill_density = density
	kind.clump_size = clump
	kind.sway = 1.5
	kind.sheet = sheet()
	kind.states[0].trampled_frames = PackedInt32Array([TRAMPLED_FRAME])
	return kind


## Seven 16×16 tufts: blades from the foot up, a dark side and a lit tip each; burning, shorter
## blades in flame colours; ash, a low grey stubble; trampled, blades lying along the floor.
static func sheet() -> Texture2D:
	var image := Image.create_empty(112, 16, false, Image.FORMAT_RGBA8)
	var blades: Array[PackedInt32Array] = [
		PackedInt32Array([5, 9, 7, 6, 10, 9]),
		PackedInt32Array([4, 7, 8, 11, 6, 10]),
		PackedInt32Array([6, 10, 8, 7, 9, 8]),
	]
	for frame in 3:
		var shape: PackedInt32Array = blades[frame]
		for blade in 3:
			var x: int = frame * 16 + shape[blade * 2]
			var height: int = shape[blade * 2 + 1]
			for y in range(16 - height, 16):
				image.set_pixel(x, y, DARK if y > 13 else BASE)
			image.set_pixel(x, 16 - height, LIGHT)
	for frame in [3, 4]:
		for blade in 3:
			var x: int = frame * 16 + 5 + blade * 3
			for y in range(9 + (blade + frame) % 3, 16):
				image.set_pixel(x, y, Color("f2a93b") if y < 12 else Color("b8442f"))
	for blade in 4:
		image.set_pixel(80 + 5 + blade * 2, 15, Color("5b5966"))
		image.set_pixel(80 + 5 + blade * 2, 14, Color("7a7694"))
	for blade in 3:
		var y: int = 15 - blade
		for x in range(96 + 3 + blade * 2, 96 + 10 + blade * 2):
			image.set_pixel(x, y, DARK if x < 96 + 6 + blade * 2 else BASE)
		image.set_pixel(96 + 10 + blade * 2, y, LIGHT)
	return ImageTexture.create_from_image(image)
