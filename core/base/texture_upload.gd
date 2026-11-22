class_name TextureUpload
extends RefCounted
## A texture whose pixels the game writes on the CPU and hands to the GPU, safe with Godot's
## separate render thread (the owner's decision of 2026-11-22: the desktop builds draw on one;
## core/README.md, "The render thread"). The one way the game updates a picture it keeps writing:
## the light grid's atlas, the mists' partings, the stirs' field, the cover's times, the ramp table,
## the HUD's icon pages (`tests/core/test_texture_upload.gd` fails any other `update` or `set_image`).
##
## **Why:** a call to the RenderingServer from the main thread is queued, and the render thread runs
## it later, while the main thread goes on. `ImageTexture.update(image)` queues the image itself,
## not a copy, so an image written again in the meantime (a pixel set, its data swapped) is read
## half written: Godot logs "p_image->is_empty()" or a size mismatch, or draws a torn picture.
## So the caller's image is never handed over: `hand(image)` copies its pixels into an image of
## this upload's own, one not handed in the last FRAMES_HELD frames (the main loop waits for the
## render thread to run every call queued before it draws the next frame: main/main.cpp, `sync`),
## and hands that. The caller keeps writing its own image whenever it likes, on a worker thread too.
##
## **Once a frame:** the first `hand` of a frame uploads at once (a test reads it straight after);
## a later one that frame waits for the frame's draw (`RenderingServer.frame_pre_draw`, after every
## step and join of Feel's workers) and uploads the image as it is then, once: a frame that adds a
## dozen icons to a page or a few rows to the ramp table hands the GPU two pictures, not a dozen. So
## two images take turns, and at most IMAGES_MOST are held; none is made a frame once they are
## (`blit_rect` writes in place). On the main thread only, as every RenderingServer call; on one
## render thread (the web's) it is the same pictures, a copy dearer.

## The frames an image handed waits before it is written again (one is enough: the frame's `sync`
## has run every call queued before it; two for a margin).
const FRAMES_HELD: int = 2
## The most images an upload holds: two uploads a frame (the first, and the frame's draw) over
## FRAMES_HELD frames.
const IMAGES_MOST: int = 4

## The texture the shaders read; null until the first `hand`. A picture of another size or format
## makes it anew (the old one stays the renderer's until it lets go).
var texture: ImageTexture = null
## How many images this upload made, and how many pictures it handed the GPU, all told (for tests).
var made: int = 0
var uploads: int = 0
## The images handed, and the process frame each was handed on.
var _images: Array[Image] = []
var _handed: PackedInt64Array = PackedInt64Array()
## The process frame of the last upload, and the caller's image waiting for the frame's draw (null:
## none).
var _uploaded_frame: int = -1
var _waiting: Image = null
## The image of this upload's own last handed.
var _last: Image = null


## `image`'s pixels handed to the texture (made the first time, or anew for another size or format),
## now or, when this frame already uploaded, at the frame's draw; the texture back (a new size's is
## the new texture at once). `image` stays the caller's: kept only until the frame's draw, read only.
func hand(image: Image) -> ImageTexture:
	if image == null or image.is_empty():
		return texture
	var now: int = Engine.get_process_frames()
	var resized: bool = texture == null or texture.get_width() != image.get_width() or texture.get_height() != image.get_height() or texture.get_format() != image.get_format()
	if _uploaded_frame == now and not resized:
		if not RenderingServer.frame_pre_draw.is_connected(_upload_waiting):
			RenderingServer.frame_pre_draw.connect(_upload_waiting, CONNECT_ONE_SHOT)
		_waiting = image
		return texture
	_waiting = null
	_upload(image, now)
	return texture


## The image waiting uploaded, at the frame's draw.
func _upload_waiting() -> void:
	if _waiting != null:
		var image: Image = _waiting
		_waiting = null
		_upload(image, Engine.get_process_frames())


func _upload(image: Image, now: int) -> void:
	var at: int = _free_image(image, now)
	var own: Image = _images[at]
	own.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	_handed[at] = now
	_last = own
	_uploaded_frame = now
	uploads += 1
	if texture != null and texture.get_width() == own.get_width() and texture.get_height() == own.get_height() and texture.get_format() == own.get_format():
		texture.update(own)
	else:
		texture = ImageTexture.create_from_image(own)


## The image of this upload's own last handed to the GPU (for tests: a headless renderer keeps no
## texture's pixels).
func last_handed() -> Image:
	return _last


## How many images this upload holds (for tests).
func image_count() -> int:
	return _images.size()


## The index of an image of `image`'s size and format not handed since `now - FRAMES_HELD` (made
## when there is none, up to IMAGES_MOST, else the oldest: only when a frame passes with no draw, as
## a test steps; one of another size or format is let go).
func _free_image(image: Image, now: int) -> int:
	for i in range(_images.size() - 1, -1, -1):
		if _images[i].get_size() != image.get_size() or _images[i].get_format() != image.get_format():
			_images.remove_at(i)
			_handed.remove_at(i)
	var oldest: int = -1
	for i in _images.size():
		if _handed[i] <= now - FRAMES_HELD:
			return i
		if oldest < 0 or _handed[i] < _handed[oldest]:
			oldest = i
	if _images.size() >= IMAGES_MOST:
		return oldest
	_images.append(Image.create_empty(image.get_width(), image.get_height(), false, image.get_format()))
	_handed.append(-FRAMES_HELD)
	made += 1
	return _images.size() - 1
