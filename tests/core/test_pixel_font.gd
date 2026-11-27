extends "res://tests/support/suite.gd"
## The game's pixel font (core/display/pixel_font.gd, ART4 part 4): every theme's default from the
## start, every size and outline the game draws made, every character the game writes on it, lines
## as the old default font's (layouts unchanged), whole-pixel advances, and its sheet all whole
## pixels (white, clear or solid).


func test_it_is_every_themes_default_font() -> void:
	check(ThemeDB.fallback_font == PixelFont.font(), "the fallback font is the pixel font")
	check(ThemeDB.get_default_theme().default_font == PixelFont.font(), "the engine's default theme's font is the pixel font")
	var label: Label = own(Label.new()) as Label
	root.add_child(label)
	check(label.get_theme_font(&"font") == PixelFont.font(), "a label draws with it")


func test_every_size_the_game_draws_is_made() -> void:
	var font: FontFile = PixelFont.font()
	var cached: Array[Vector2i] = font.get_size_cache_list(0)
	for size: Vector2i in GlyphWarmup.GAME_SIZES:
		check(PixelFont.has_size(size.x, size.y), "%d px, outline %d, is one of the font's" % [size.x, size.y])
		check(cached.has(size), "%d px, outline %d, has its cache" % [size.x, size.y])


func test_every_character_the_game_writes_has_a_glyph() -> void:
	var font: FontFile = PixelFont.font()
	var text: String = GlyphWarmup.EXTRA
	for code in range(GlyphWarmup.FIRST, GlyphWarmup.LAST + 1):
		text += String.chr(code)
	for size in [8, 12, 40]:
		var cache := Vector2i(size, 0)
		for i in text.length():
			var code: int = text.unicode_at(i)
			check(font.get_glyph_advance(0, size, code).x > 0.0, "%s at %d px has an advance" % [String.chr(code), size])
			check(font.get_glyph_size(0, cache, code).x > 0.0, "%s at %d px has a glyph" % [String.chr(code), size])


func test_lines_are_the_old_fonts_and_advances_whole_pixels() -> void:
	var font: FontFile = PixelFont.font()
	# The engine's default font's ascent and descent at the sizes the game used it at.
	var old: Dictionary[int, Vector2i] = {8: Vector2i(9, 3), 10: Vector2i(11, 3), 12: Vector2i(13, 4), 14: Vector2i(15, 5), 16: Vector2i(18, 5), 40: Vector2i(43, 12)}
	for size: int in old:
		check_equal(Vector2i(roundi(font.get_ascent(size)), roundi(font.get_descent(size))), old[size], "%d px: the old line" % size)
		for code in ["0", "1", "W", "i", " ", "m"]:
			var advance: float = font.get_char_size(code.unicode_at(0), size).x
			check(advance == roundf(advance), "%d px: %s advances a whole pixel (%s)" % [size, code, advance])


func test_a_size_is_drawn_by_the_largest_face_under_it() -> void:
	var faces: Array = [{"size": 8}, {"size": 10}, {"size": 16}]
	check_equal(PixelFont.face_of(8, faces), Vector2i(8, 1), "its own face")
	check_equal(PixelFont.face_of(9, faces), Vector2i(8, 1), "the face under it")
	check_equal(PixelFont.face_of(20, faces), Vector2i(10, 2), "a face doubled past the last, the finer on a tie")
	check_equal(PixelFont.face_of(6, faces), Vector2i(8, 1), "the smallest under the smallest face")


func test_the_sheet_is_whole_pixels() -> void:
	var sheet: Image = PixelFont.SHEET
	check(sheet.get_width() > 0 and sheet.get_height() > 0, "the sheet loads")
	# A row of every face's band, through glyphs and outlines: every pixel clear or solid white.
	var bad: int = 0
	for y in range(0, sheet.get_height(), 7):
		for x in sheet.get_width():
			var c: Color = sheet.get_pixel(x, y)
			if c.a != 0.0 and (c.a != 1.0 or c.r != 1.0 or c.g != 1.0 or c.b != 1.0):
				bad += 1
	check_equal(bad, 0, "no pixel half clear or not white")
