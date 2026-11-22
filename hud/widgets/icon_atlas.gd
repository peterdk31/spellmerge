extends RefCounted
## One texture for the small icons the HUD draws many of side by side (the staff rows' card icons;
## the performance pass of 2026-11-21: "reduce draw calls"). Godot draws a run of rects one after
## another in one draw call only while they read one texture, so a row of icons each in its own
## file is a draw call an icon; the same icons read from one page are one call for the row.
##
## `region_of(texture)` gives an `AtlasTexture` on a shared page holding a copy of the texture's
## pixels, the same size (copied once, the first time an icon is asked for; the page uploaded
## again then, never a frame). Drawn as the texture was (`draw_texture_rect` into the same rect,
## nearest filtering), it puts the same pixels on screen. A texture with no pixels to copy (none,
## or larger than a page) is handed back as it is.

## A page's side in pixels (a power of two, so every texel's coordinate is exact).
const PAGE: int = 256

## The copies by the texture they were made from.
static var _regions: Dictionary[Texture2D, Texture2D] = {}
## The pages, their images, and where the next icon goes on the last (a shelf: left to right,
## then down by the shelf's tallest).
static var _pages: Array[ImageTexture] = []
## Each page's one upload point (core/base/texture_upload.gd: a page written again as icons are added
## is safe with a separate render thread).
static var _uploads: Array[TextureUpload] = []
static var _images: Array[Image] = []
static var _cursor: Vector2i = Vector2i.ZERO
static var _shelf: int = 0


## `texture`'s copy on a page (itself when it cannot be copied).
static func region_of(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var known: Texture2D = _regions.get(texture, null)
	if known != null:
		return known
	var copy: Texture2D = _copy(texture)
	_regions[texture] = copy
	return copy


## The pages made so far (for tests).
static func pages() -> int:
	return _pages.size()


## The pixels a copy on a page holds, from the page's own image (null for none; for tests: a
## headless run keeps no texture's pixels).
static func pixels_of(region: AtlasTexture) -> Image:
	var page: int = _pages.find(region.atlas as ImageTexture) if region != null else -1
	return _images[page].get_region(Rect2i(region.region)) if page >= 0 else null


static func _copy(texture: Texture2D) -> Texture2D:
	if texture is AtlasTexture:
		return texture
	var image: Image = texture.get_image()
	if image == null or image.is_empty() or image.get_width() > PAGE or image.get_height() > PAGE:
		return texture
	if image.is_compressed():
		image = image.duplicate() as Image
		if image.decompress() != OK:
			return texture
	if image.get_format() != Image.FORMAT_RGBA8:
		image = image.duplicate() as Image
		image.convert(Image.FORMAT_RGBA8)
	var size := Vector2i(image.get_width(), image.get_height())
	if _pages.is_empty() or _cursor.x + size.x > PAGE:
		_cursor = Vector2i(0, _cursor.y + _shelf)
		_shelf = 0
	if _pages.is_empty() or _cursor.y + size.y > PAGE:
		_images.append(Image.create_empty(PAGE, PAGE, false, Image.FORMAT_RGBA8))
		_uploads.append(TextureUpload.new())
		_pages.append(_uploads[-1].hand(_images[-1]))
		_cursor = Vector2i.ZERO
		_shelf = 0
	var page: Image = _images[-1]
	page.blit_rect(image, Rect2i(Vector2i.ZERO, size), _cursor)
	_uploads[-1].hand(page)
	var region := AtlasTexture.new()
	region.atlas = _pages[-1]
	region.region = Rect2(_cursor, size)
	_cursor.x += size.x
	_shelf = maxi(_shelf, size.y)
	return region
