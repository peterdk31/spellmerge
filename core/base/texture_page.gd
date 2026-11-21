class_name TexturePage
extends RefCounted
## Textures drawn one after another put on one page, so they are one draw call (the performance pass
## of 2026-11-21, round two: "an enemy is 1 draw call instead of 2", "a candle is 1 call instead of
## 2"). Godot draws a run of canvas items in one call only while they read one texture (and one
## material); an enemy's body and its face's sheets, or a candle's wax and its flame's frames, each
## in a file of its own, are a call each. `regions_of(textures)` copies their pixels side by side
## onto one page (a row, GAP clear pixels apart) and hands back an `AtlasTexture` on it for each, the
## same size: drawn as the texture was (nearest filtering, into the same rect), it puts the same
## pixels on screen. An `AtlasTexture` given is copied by its region (a strip's frame).
##
## Made once for each list of textures (a kind's body and face, a decal's art) and kept: every enemy
## of a kind, every candle, shares its page, so neighbours of one kind batch as well. A region given
## again (a look set up a second time) stands for the texture it was made from. When a texture's
## pixels cannot be read (none, compressed past reading) the textures are handed back as they are.
## View only: nothing of the game reads it. Not state, made at load or a spawn, never a frame.

## Clear pixels between two textures on a page, so a scaled draw's edge never reads its neighbour.
const GAP: int = 2

## The regions made, by the list of textures they were made from.
static var _made: Dictionary = {}
## Each region's own texture (a region given again stands for it).
static var _source: Dictionary[Texture2D, Texture2D] = {}
## The pages' images, by page (for tests: a headless run reads these, not the GPU's copy).
static var _images: Dictionary[Texture2D, Image] = {}


## A copy of each of `textures` on one page, in order (null stays null; a texture listed twice is
## one copy); `textures` itself when one cannot be copied.
static func regions_of(textures: Array[Texture2D]) -> Array[Texture2D]:
	var sources: Array[Texture2D] = []
	for texture: Texture2D in textures:
		sources.append(_source.get(texture, texture) as Texture2D if texture != null else null)
	var known: Variant = _made.get(sources, null)
	if known != null:
		return known
	var made: Array[Texture2D] = _page(sources)
	_made[sources] = made
	for i in made.size():
		if made[i] != null and made[i] != sources[i]:
			_source[made[i]] = sources[i]
	return made


## The texture `region` was copied from (itself when it is no page's).
static func source_of(region: Texture2D) -> Texture2D:
	return _source.get(region, region) as Texture2D


## The pixels a region holds, from its page's own image (null for none; for tests).
static func pixels_of(region: Texture2D) -> Image:
	var atlas := region as AtlasTexture
	var page: Image = _images.get(atlas.atlas, null) if atlas != null else null
	return page.get_region(Rect2i(atlas.region)) if page != null else null


static func _page(sources: Array[Texture2D]) -> Array[Texture2D]:
	var images: Array[Image] = []
	var at: Dictionary[Texture2D, int] = {}
	var width: int = 0
	var height: int = 0
	for texture: Texture2D in sources:
		if texture == null or at.has(texture):
			continue
		var image: Image = _image_of(texture)
		if image == null:
			return sources.duplicate()
		at[texture] = width
		images.append(image)
		width += image.get_width() + GAP
		height = maxi(height, image.get_height())
	if images.is_empty():
		return sources.duplicate()
	var page := Image.create_empty(width - GAP, height, false, Image.FORMAT_RGBA8)
	var x: int = 0
	for image: Image in images:
		page.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(x, 0))
		x += image.get_width() + GAP
	var page_texture := ImageTexture.create_from_image(page)
	_images[page_texture] = page
	var made: Array[Texture2D] = []
	var regions: Dictionary[Texture2D, AtlasTexture] = {}
	for texture: Texture2D in sources:
		if texture == null:
			made.append(null)
			continue
		if not regions.has(texture):
			var region := AtlasTexture.new()
			region.atlas = page_texture
			region.region = Rect2(Vector2(at[texture], 0.0), texture.get_size())
			regions[texture] = region
		made.append(regions[texture])
	return made


## `texture`'s pixels as RGBA8 (an atlas region's own), or null when they cannot be read.
static func _image_of(texture: Texture2D) -> Image:
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return null
	image = image.duplicate() as Image
	if image.is_compressed() and image.decompress() != OK:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	if Vector2(image.get_size()) != texture.get_size():
		return null
	return image
