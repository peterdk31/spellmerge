extends "res://tests/support/suite.gd"
## A biome's bridge mouths as the view draws them (gameplay/feel/mouth_looks.gd), at the art's detail
## (ART3): drawn in art pixels, DETAIL a world pixel each way, at the same sizes as before. The
## mouths found on a grid, the shimmer, the flares and the seals are played in
## test_biome_sound_and_look.gd; these check the drawing's measures.

const LooksScript := preload("res://gameplay/feel/mouth_looks.gd")


func test_it_draws_at_the_arts_detail() -> void:
	check_equal(LooksScript.DETAIL, ArtDetail.DETAIL, "the art's detail")


func test_the_seals_rune_is_its_old_size_in_art_pixels() -> void:
	var side: int = LooksScript.RUNE_SIDE * LooksScript.DETAIL
	check_equal(LooksScript.RUNE_2X.size(), side, "RUNE_SIDE world pixels high")
	var lit: int = 0
	for y in side:
		var line: String = LooksScript.RUNE_2X[y]
		check_equal(line.length(), side, "row %d RUNE_SIDE world pixels wide" % y)
		for x in side:
			check(".#+".contains(line[x]), "row %d: only shade, lit or none" % y)
			# Left to right it mirrors, in which pixels are drawn (its lit ones may sit on either side).
			check_equal(line[x] == ".", line[side - 1 - x] == ".", "row %d mirrors at %d" % [y, x])
			if line[x] == "+":
				lit += 1
				check(y < side / 2, "a lit pixel on its upper half: %d, %d" % [x, y])
	check(lit > 0, "it has lit pixels")


func test_an_art_point_is_in_the_world_pixel_of_its_old_point() -> void:
	var area := Rect2i(64, 96, 32, 9)
	# Along a wide mouth's middle line: art rows 0 and 1 are the world row the old drawing used.
	for along in [0, 5, 63]:
		for across in [0, 1]:
			var art: Vector2 = LooksScript.art_point(area, true, along, across)
			var world: Vector2 = (art / float(LooksScript.DETAIL)).floor()
			check_equal(world, Vector2(area.position.x + along / 2, area.position.y + area.size.y / 2), "wide, %d along, %d across" % [along, across])
	var tall := Rect2i(64, 96, 9, 32)
	var art_tall: Vector2 = LooksScript.art_point(tall, false, 7, 1)
	check_equal((art_tall / float(LooksScript.DETAIL)).floor(), Vector2(tall.position.x + tall.size.x / 2, tall.position.y + 3), "tall: across is x")
