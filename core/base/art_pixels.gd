class_name ArtPixels
extends RefCounted
## What a picture is made of, read from its pixels: the colours it is mostly drawn in and the pixels
## that show. One reader for everything that takes its look from art rather than numbers: a room's
## walls and floor (`RoomBase.surface_colors`, `floor_colors`), a light spot's colour (`LightSpot`),
## a body breaking into motes of its own art and a mote source's mask (gameplay/feel). A pixel shows
## when its alpha is at least a half. Static only; it reads textures and keeps nothing.

## The colours of art that count, at most; a colour on fewer pixels than MIN_SHARE of the most common
## one's is left out (a speck of trim).
const SHADES: int = 3
const MIN_SHARE: float = 0.1


## The colours of the art `texture` (only its `region` when one is given: a frame of a sheet): its
## most common ones, lightest first (light, base, shadow; always three, a colour repeated when it
## has fewer). Empty when there is no art to read.
static func colours_of(texture: Texture2D, region: Rect2i = Rect2i()) -> PackedColorArray:
	return three(top_colours(count_colours(texture, {}, region)))


## The pixels of `texture` (within `region` when it has one) that show, as positions in the region,
## every `step`-th of them in reading order. Empty for no texture.
static func pixels_of(texture: Texture2D, region: Rect2i = Rect2i(), step: int = 1) -> PackedVector2Array:
	var found := PackedVector2Array()
	var image: Image = _image_of(texture)
	if image == null:
		return found
	var area: Rect2i = _area_of(image, region)
	var n: int = 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if image.get_pixel(x, y).a >= 0.5:
				if n % maxi(step, 1) == 0:
					found.append(Vector2(x - area.position.x, y - area.position.y))
				n += 1
	return found


## The part of its texture `sprite` shows: its region, or its frame of a sheet (empty with no
## texture).
static func frame_of(sprite: Sprite2D) -> Rect2i:
	if sprite == null or sprite.texture == null:
		return Rect2i()
	if sprite.region_enabled:
		return Rect2i(sprite.region_rect)
	var size: Vector2i = Vector2i(sprite.texture.get_size()) / Vector2i(maxi(sprite.hframes, 1), maxi(sprite.vframes, 1))
	return Rect2i(Vector2i(sprite.frame % maxi(sprite.hframes, 1), sprite.frame / maxi(sprite.hframes, 1)) * size, size)


## Adds the pixels of `texture` that show (of its `region` only, when one is given) to `counts`
## (RGBA32 -> pixels) and returns it.
static func count_colours(texture: Texture2D, counts: Dictionary, region: Rect2i = Rect2i()) -> Dictionary:
	var image: Image = _image_of(texture)
	if image == null:
		return counts
	var area: Rect2i = _area_of(image, region)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a >= 0.5:
				var rgba: int = Color(pixel.r, pixel.g, pixel.b, 1.0).to_rgba32()
				counts[rgba] = int(counts.get(rgba, 0)) + 1
	return counts


## The most common colours of `counts` (RGBA32 -> pixels), most common first: at most SHADES, none on
## fewer than MIN_SHARE of the most common one's pixels. Empties `counts`' top colours.
static func top_colours(counts: Dictionary) -> PackedColorArray:
	var found := PackedColorArray()
	var most: int = 0
	for rgba: int in counts:
		most = maxi(most, int(counts[rgba]))
	while found.size() < SHADES and not counts.is_empty():
		var top: int = most_common(counts)
		if float(counts[top]) < float(most) * MIN_SHARE:
			break
		found.append(Color.hex(top))
		counts.erase(top)
	return found


## `colours` as three shades, lightest first: light, base, shadow (a colour repeated when there are
## fewer; empty for none).
static func three(colours: PackedColorArray) -> PackedColorArray:
	var sorted: Array[Color] = []
	for colour in colours:
		sorted.append(colour)
	sorted.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() > b.get_luminance())
	match sorted.size():
		0:
			return PackedColorArray()
		1:
			return PackedColorArray([sorted[0], sorted[0], sorted[0]])
		2:
			return PackedColorArray([sorted[0], sorted[0], sorted[1]])
	return PackedColorArray([sorted[0], sorted[1], sorted[2]])


## The colour of `counts` (RGBA32 -> pixels) on the most pixels, -1 for none.
static func most_common(counts: Dictionary) -> int:
	var best: int = -1
	var most: int = 0
	for rgba: int in counts:
		if int(counts[rgba]) > most:
			most = int(counts[rgba])
			best = rgba
	return best


## `texture`'s image to read (decompressed), or null when there is none.
static func _image_of(texture: Texture2D) -> Image:
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return null
	if image.is_compressed():
		image.decompress()
	return image


static func _area_of(image: Image, region: Rect2i) -> Rect2i:
	var area := Rect2i(Vector2i.ZERO, image.get_size())
	return area.intersection(region) if region.has_area() else area
