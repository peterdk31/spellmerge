extends "res://tests/support/suite.gd"
## Textures drawn one after another on one page (core/base/texture_page.gd; the performance pass of
## 2026-11-21, round two): each copy is its texture's size and its own pixels (an atlas region's
## region), on one page with the others; a list is paged once and shared; a region given again stands
## for its own texture; a texture whose pixels cannot be read leaves the list as it is.


func _art(size: Vector2i, colour: Color) -> Texture2D:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	image.set_pixel(0, 0, Color.WHITE)
	image.set_pixel(size.x - 1, size.y - 1, Color.BLACK)
	return ImageTexture.create_from_image(image)


func _pixels(texture: Texture2D) -> PackedByteArray:
	var image: Image = texture.get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image.get_data()


func test_each_copy_is_its_texture_s_size_and_pixels_on_one_page() -> void:
	var strip: Texture2D = _art(Vector2i(64, 16), Color.RED)
	var frame := AtlasTexture.new()
	frame.atlas = strip
	frame.region = Rect2(16, 0, 16, 16)
	var textures: Array[Texture2D] = [_art(Vector2i(32, 32), Color.BLUE), null, frame, _art(Vector2i(8, 24), Color.GREEN)]
	var regions: Array[Texture2D] = TexturePage.regions_of(textures)
	check_equal(regions.size(), textures.size(), "a copy for each, in order")
	check(regions[1] == null, "null stays null")
	var page: Texture2D = null
	for i in [0, 2, 3]:
		var region := regions[i] as AtlasTexture
		check(region != null, "texture %d: a region of a page" % i)
		if region == null:
			continue
		page = region.atlas if page == null else page
		check(region.atlas == page, "texture %d: on the one page" % i)
		check_equal(region.get_size(), textures[i].get_size(), "texture %d: its own size" % i)
		check(TexturePage.pixels_of(region).get_data() == _pixels(textures[i]), "texture %d: its own pixels" % i)
	var boxes: Array[Rect2] = []
	for i in [0, 2, 3]:
		var box: Rect2 = (regions[i] as AtlasTexture).region.grow(float(TexturePage.GAP) / 2.0 - 0.01)
		check(boxes.all(func(other: Rect2) -> bool: return not other.intersects(box)), "texture %d: GAP clear pixels from the others" % i)
		boxes.append(box)


func test_a_list_is_paged_once_and_a_region_stands_for_its_texture() -> void:
	var body: Texture2D = _art(Vector2i(32, 32), Color.ORANGE)
	var eyes: Texture2D = _art(Vector2i(16, 8), Color.WHITE)
	var first: Array[Texture2D] = TexturePage.regions_of([body, eyes] as Array[Texture2D])
	var again: Array[Texture2D] = TexturePage.regions_of([body, eyes] as Array[Texture2D])
	check(first[0] == again[0] and first[1] == again[1], "the same list: the same regions, made once")
	var from_regions: Array[Texture2D] = TexturePage.regions_of(first)
	check(from_regions[0] == first[0] and from_regions[1] == first[1], "its regions given again: the same regions (a look set up twice)")
	check(TexturePage.source_of(first[0]) == body and TexturePage.source_of(body) == body, "a region's own texture")


func test_a_texture_with_no_pixels_leaves_the_list_as_it_is() -> void:
	var body: Texture2D = _art(Vector2i(32, 32), Color.ORANGE)
	var empty := PlaceholderTexture2D.new()
	empty.size = Vector2(16, 16)
	var regions: Array[Texture2D] = TexturePage.regions_of([body, empty] as Array[Texture2D])
	check(regions[0] == body and regions[1] == empty, "nothing paged")
