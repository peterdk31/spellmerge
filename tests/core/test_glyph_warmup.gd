extends "res://tests/support/suite.gd"
# unit-test-alone
## Every glyph the game draws, rasterized before play (core/base/glyph_warmup.gd): a glyph drawn in
## play writes the font's atlas image as a separate render thread reads it (the render thread,
## 2026-11-22: `p_image->is_empty()` entering the boss's room). The warm-up draws each size and
## outline the game uses, at every quarter-pixel offset, with the ligatures; text drawn after it at
## those sizes draws no glyph of its own, the main menu and the HUD's widgets draw none either, and
## one at a size not warmed is named. Alone in its process: it checks the default font as the
## autoloads warmed it, which another test file's text would change.


func test_the_game_font_is_warmed_as_the_game_starts() -> void:
	GlyphWarmup.warm_game()
	var font := ThemeDB.fallback_font as FontFile
	check(font != null, "the default font is a font file")
	var cached: Array[Vector2i] = font.get_size_cache_list(0)
	for size: Vector2i in GlyphWarmup.GAME_SIZES:
		check(cached.has(size), "%d px, outline %d, is warmed" % [size.x, size.y])
	check_equal(GlyphWarmup.warm_game(), 0.0, "once: a second call does nothing")


func test_text_drawn_at_warmed_sizes_draws_no_glyph() -> void:
	GlyphWarmup.warm_game()
	var font := ThemeDB.fallback_font as FontFile
	var item: RID = RenderingServer.canvas_item_create()
	for size: Vector2i in GlyphWarmup.GAME_SIZES:
		# A label's text, at an odd place: every letter lands on some quarter pixel.
		var text: String = "Fireball × 3 — fifty-five (98%), offline… Staff 4: +12 ∞ 45°"
		if size.y > 0:
			font.draw_string_outline(item, Vector2(1.81, 11.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size.x, size.y)
		else:
			font.draw_string(item, Vector2(3.37, 11.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size.x)
	RenderingServer.free_rid(item)
	check_equal(GlyphWarmup.drawn_since_warm(), PackedStringArray(), "nothing drawn that was not warmed")


func test_the_main_menu_and_the_frame_rate_draw_no_glyph() -> void:
	GlyphWarmup.warm_game()
	var menu: Node = own(load("res://hud/menus/main_menu/main_menu.tscn").instantiate())
	root.add_child(menu)
	var fps: Label = own(load("res://hud/widgets/fps_counter.gd").new()) as Label
	root.add_child(fps)
	fps.visible = true
	fps.text = "60 FPS"
	await process_frame
	await process_frame
	check_equal(GlyphWarmup.drawn_since_warm(), PackedStringArray(), "nothing drawn that was not warmed")


func test_a_size_not_warmed_is_named() -> void:
	GlyphWarmup.warm_game()
	var font := ThemeDB.fallback_font as FontFile
	var item: RID = RenderingServer.canvas_item_create()
	font.draw_string(item, Vector2.ZERO, "Az", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 77)
	RenderingServer.free_rid(item)
	var named: PackedStringArray = GlyphWarmup.drawn_since_warm()
	check(named.size() == 1 and named[0].contains("77/0"), "the size drawn and not warmed is named: %s" % str(named))
	font.remove_size_cache(0, Vector2i(77, 0))
