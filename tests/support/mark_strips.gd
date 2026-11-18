extends RefCounted
## Mark strips made in the test (spawn styles AS4, docs/milestones/spawn-styles.md): a style's
## `mark_strip` is a row of square frames side by side, and these make one, and a style that names it,
## with no art committed. Frame `n` is a square `n + 1` pixels wide each way from its centre in the
## shade `n` of `SHADES` (wrapping), on clear pixels, so a frame drawn is told from the others by its
## colour.
##
##     const MarkStrips := preload("res://tests/support/mark_strips.gd")
##     var strip: ImageTexture = MarkStrips.strip(16, 4)        # 64x16, four frames
##     var style: SpawnStyle = MarkStrips.style(&"rooted", strip) # rise's numbers, with the strip
##     MarkStrips.write_folder("user://strip_fixture/rooted", strip, true) # the png and its assets.json

## The frames' colours, in order.
const SHADES: PackedColorArray = [Color8(0x3a, 0x2a, 0x1e), Color8(0x6b, 0x4a, 0x2e), Color8(0x9a, 0x6e, 0x3f), Color8(0xc8, 0x9b, 0x5a)]


## A strip of `frames` frames `side` pixels square (its image `side * frames` wide; `wide` and `high`
## override its size, for a strip that is not square frames).
static func strip(side: int, frames: int, wide: int = -1, high: int = -1) -> ImageTexture:
	var width: int = wide if wide > 0 else side * frames
	var height: int = high if high > 0 else side
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for n in frames:
		var centre: int = n * side + side / 2
		var reach: int = mini(n + 1, side / 2)
		for x in range(centre - reach, centre + reach):
			for y in range(height / 2 - reach, height / 2 + reach):
				if x >= 0 and x < width and y >= 0 and y < height:
					image.set_pixel(x, y, SHADES[n % SHADES.size()])
	return ImageTexture.create_from_image(image)


## A style of `rise`'s numbers named `id`, its mark `strip`.
static func style(id: StringName, mark: Texture2D) -> SpawnStyle:
	var made := SpawnStyle.from_default()
	made.id = id
	made.mark_strip = mark
	return made


## The png of `mark` written into `folder` (a user:// folder), and the texture's path set to it; and
## an assets.json there listing it if `listed`. Returns the png's path.
static func write_folder(folder: String, mark: ImageTexture, listed: bool) -> String:
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join("mark.png")
	mark.get_image().save_png(path)
	mark.resource_path = path
	var assets: Array = []
	if listed:
		assets.append({"path": path, "origin": "human", "author": "the tests", "license": "CC0-1.0"})
	var file := FileAccess.open(folder.path_join(SpawnStyle.ASSETS_FILE), FileAccess.WRITE)
	file.store_string(JSON.stringify({"assets": assets}))
	file.close()
	return path


## Remove a folder `write_folder` wrote.
static func remove_folder(folder: String) -> void:
	for name: String in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(name))
	DirAccess.remove_absolute(folder)
