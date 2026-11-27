extends "res://tests/support/suite.gd"
## The small shapes at the art's detail (ART4 part 3; `core/display/pixel_shape.gd`): the Outline
## round a mask with its corners cut, the light from the top-left, whole art pixels when drawn, and
## the markers' heads turning by whole steps.

const TONES: PackedColorArray = [Color("#14121f"), Color("#7a7694"), Color("#4a4663"), Color("#2b2840")]


## Notes every rect drawn, in art pixels, and any not on whole art pixels.
class Recorder extends RefCounted:
	var image: Image = null
	var off_grid: int = 0
	var rects: int = 0

	func _init(art_size: Vector2i) -> void:
		image = Image.create(art_size.x, art_size.y, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.0, 0.0, 0.0, 0.0))

	func draw_rect(rect: Rect2, color: Color) -> void:
		rects += 1
		var art := Rect2(rect.position * 2.0, rect.size * 2.0)
		if not art.position.is_equal_approx(art.position.round()) or not art.size.is_equal_approx(art.size.round()):
			off_grid += 1
		image.fill_rect(Rect2i(Vector2i(art.position.round()), Vector2i(art.size.round())), color)


func test_the_outline_wraps_a_mask_with_its_corners_cut() -> void:
	var shape: PixelShape = PixelShape.from_rows(PackedStringArray(["###", "###"]))
	check_equal([shape.width, shape.height], [5, 4], "an art pixel of Outline each side")
	check_equal(shape.tone_at(0, 0), -1, "the outer corner is cut")
	check_equal(shape.tone_at(1, 0), PixelShape.OUTLINE, "the Outline above the mask")
	check_equal(shape.tone_at(0, 1), PixelShape.OUTLINE, "and beside it")
	check_equal(shape.tone_at(2, 1), PixelShape.BASE, "the mask unshaded in its base")


func test_a_shaded_shape_is_lit_from_the_top_left() -> void:
	var shape: PixelShape = PixelShape.from_rows(PackedStringArray(["####", "####", "####", "####"]), true)
	check_equal(shape.tone_at(1, 1), PixelShape.LIGHT, "its top-left lit")
	check_equal(shape.tone_at(3, 1), PixelShape.LIGHT, "its top edge lit")
	check_equal(shape.tone_at(1, 3), PixelShape.LIGHT, "its left edge lit")
	check_equal(shape.tone_at(4, 4), PixelShape.SHADOW, "its bottom-right in shadow")
	check_equal(shape.tone_at(2, 4), PixelShape.SHADOW, "its bottom edge in shadow")
	check_equal(shape.tone_at(2, 2), PixelShape.BASE, "its inside the base")


func test_it_draws_whole_art_pixels_centred_on_a_snapped_point() -> void:
	var shape: PixelShape = PixelShape.disc(10)
	var recorder := Recorder.new(Vector2i(40, 40))
	shape.draw(recorder, Vector2(10.13, 9.87), TONES)
	check_equal(recorder.off_grid, 0, "every rect on whole art pixels, wherever its middle")
	check(recorder.rects < shape.width * shape.height / 2, "drawn in runs, not a rect a pixel (%d)" % recorder.rects)
	var middle: Color = recorder.image.get_pixel(20, 20)
	check(middle.a > 0.0, "drawn round its middle")


func test_a_disc_is_round_and_a_ring_is_open() -> void:
	var disc: PixelShape = PixelShape.disc(12, false)
	check_equal(disc.tone_at(1, 1), -1, "a disc's corner is empty")
	check_equal(disc.tone_at(7, 7), PixelShape.BASE, "its middle filled")
	var ring: PixelShape = PixelShape.ring(12, 2)
	check_equal(ring.tone_at(7, 7), -1, "a ring's middle is open")
	check_equal(ring.tone_at(7, 1), PixelShape.BASE, "its band filled")


func test_arrows_turn_by_whole_steps_and_point_their_way() -> void:
	var heads: Array[PixelShape] = PixelShape.arrows(20.0, 6.0, 4.0, 16)
	check_equal(heads.size(), 16, "a head a way")
	check_equal(PixelShape.way_index(Vector2.RIGHT, 16), 0, "right is the first")
	check_equal(PixelShape.way_index(Vector2.DOWN, 16), 4, "down a quarter on (clockwise on screen)")
	check_equal(PixelShape.way_index(Vector2.UP, 16), 12, "up three quarters on")
	check_equal(PixelShape.way_index(Vector2(-1.0, -0.01).normalized(), 16), 8, "left either side of its line")
	var right: PixelShape = heads[0]
	check(right.width > right.height, "the head pointing right is long across")
	var down: PixelShape = heads[4]
	check(down.height > down.width, "the one pointing down is long down")
	# Its tip: the filled pixels narrow toward its point.
	var near_tip: int = 0
	var near_back: int = 0
	for y in right.height:
		if right.tone_at(right.width - 3, y) > PixelShape.OUTLINE:
			near_tip += 1
		if right.tone_at(4, y) > PixelShape.OUTLINE:
			near_back += 1
	check(near_tip < near_back, "narrow at its tip (%d), wide at its barbs (%d)" % [near_tip, near_back])


func test_an_arrow_is_symmetric_about_its_way() -> void:
	for head: PixelShape in [PixelShape.arrows(30.0, 9.0, 6.0, 16)[0], PixelShape.arrows(16.0, 8.0, 0.0, 16)[4]]:
		var across: bool = head.width > head.height
		var mirrored: bool = true
		for y in head.height:
			for x in head.width:
				var other: int = head.tone_at(x, head.height - 1 - y) if across else head.tone_at(head.width - 1 - x, y)
				# Light and shadow swap sides in a mirror; only what is drawn must match.
				mirrored = mirrored and ((head.tone_at(x, y) >= 0) == (other >= 0))
		check(mirrored, "a head %dx%d is the same either side of its way" % [head.width, head.height])


func test_a_base_colour_is_shaded_in_its_own_ramp() -> void:
	check_equal(PixelShape.light_of(Color("3b73c9")), Color("7fc0f0"), "player 1's light")
	check_equal(PixelShape.shadow_of(Color("e0592f")), Color("8f2d2a"), "fire's shadow")
	check_equal(PixelShape.light_of(Color("123456")), Color("123456"), "no ramp: itself")
