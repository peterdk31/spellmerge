extends "res://tests/support/suite.gd"
## A texture's one upload point (core/base/texture_upload.gd): the image handed to the renderer is
## the upload's own copy, never written again for two frames, so a separate render thread never reads
## a picture half written (the render thread, 2026-11-22: "p_image->is_empty()" from the light grid
## swapping its image's data while the render thread read it). And no game script updates a texture
## another way.

## The folders of the game (the benchmarks and tests may read pictures as they like).
const GAME: Array[String] = ["res://core", "res://gameplay", "res://hud", "res://content", "res://net"]
const UPLOAD: String = "res://core/base/texture_upload.gd"


func _image(width: int, height: int, value: float) -> Image:
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color8(int(value * 255.0), 0, 0))
	return image


func test_the_texture_holds_a_copy_and_the_caller_keeps_its_image() -> void:
	var upload := TextureUpload.new()
	var image: Image = _image(4, 3, 128.0 / 255.0)
	var texture: ImageTexture = upload.hand(image)
	check(texture != null, "a texture is made")
	check_equal(texture.get_size(), Vector2(4, 3), "of the image's size")
	check(texture.get_image() != image, "the texture was not handed the caller's image")
	check_equal(texture.get_image().get_pixel(1, 1).r8, 128, "with its pixels")
	image.set_pixel(1, 1, Color(1.0, 0.0, 0.0, 1.0))
	check_equal(upload.last_handed().get_pixel(1, 1).r8, 128, "the caller's writes after handing do not reach the image handed")
	check(upload.hand(image) == texture, "the same size and format updates the same texture")


func test_a_frame_uploads_at_once_then_once_more_at_its_draw() -> void:
	var upload := TextureUpload.new()
	var image: Image = _image(2, 2, 0.0)
	upload.hand(image)
	check_equal(upload.uploads, 1, "the frame's first hand uploads at once")
	for value: int in [10, 20, 30]:
		image.set_pixel(0, 0, Color8(value, 0, 0))
		upload.hand(image)
	check_equal(upload.uploads, 1, "a later hand the same frame waits for the frame's draw")
	RenderingServer.frame_pre_draw.emit()
	check_equal(upload.uploads, 2, "and uploads once there")
	check_equal(upload.last_handed().get_pixel(0, 0).r8, 30, "the image as it was at the draw")
	check_equal(upload.image_count(), 2, "into a second image: the first is still the render thread's")


func test_an_image_handed_is_not_written_for_two_frames() -> void:
	var upload := TextureUpload.new()
	var image: Image = _image(2, 2, 0.1)
	for i in 8:
		upload.hand(image)
		await process_frame
	check_equal(upload.image_count(), TextureUpload.FRAMES_HELD, "handed once a frame, FRAMES_HELD images take turns")
	var made: int = upload.made
	for i in 8:
		upload.hand(image)
		await process_frame
	check_equal(upload.made, made, "and none is made a frame")


func test_another_size_makes_the_texture_anew() -> void:
	var upload := TextureUpload.new()
	var first: ImageTexture = upload.hand(_image(2, 2, 0.0))
	var second: ImageTexture = upload.hand(_image(5, 1, 1.0))
	check(second != first, "a new texture for a new size")
	check_equal(second.get_size(), Vector2(5, 1), "of that size")
	check_equal(upload.hand(Image.new()), second, "an empty image hands nothing")


## Every file under `path` ending in `.gd`.
func _scripts(path: String, found: PackedStringArray) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".gd"):
			found.append(path.path_join(file))
	for sub in dir.get_directories():
		_scripts(path.path_join(sub), found)


func test_no_game_script_updates_a_texture_another_way() -> void:
	var found := PackedStringArray()
	for folder in GAME:
		_scripts(folder, found)
	check(found.size() > 100, "the scripts are found: %d" % found.size())
	# A texture's `update(...)` or `set_image(...)` (split, so this file does not name them).
	var pattern := RegEx.create_from_string("(?i)\\b(\\w*_)?(tex\\w*|pages?\\[[^\\]]*\\])\\s*\\.\\s*(up" + "date|set_im" + "age)\\(")
	for path in found:
		if path == UPLOAD:
			continue
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for n in lines.size():
			var line: String = lines[n].strip_edges()
			if line.begins_with("#"):
				continue
			check(pattern.search(line) == null, "%s:%d updates a texture by hand: hand the image to a TextureUpload (core/base/texture_upload.gd), or a separate render thread reads it half written" % [path, n + 1])
