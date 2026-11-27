class_name GlyphWarmup
extends RefCounted
## Every glyph the game draws, rasterized before play (the render thread, 2026-11-22, after #923).
## Godot's font cache draws a glyph the first time it is drawn at a size and outline, into an atlas
## image it then updates on the GPU; on a separate render thread (the desktop builds) a glyph drawn
## while the atlas's last update is still queued writes that image as the render thread reads it,
## and Godot logs `p_image->is_empty()` (a whole biome's play: once, entering the boss's room; a
## script that draws labels of new sizes over a busy render thread: a few in 600 frames; core/README.md,
## "The render thread"). An atlas drawn in full before play is never written again. So the HUD and
## Feel warm the default font as they start (`warm_game`), and `drawn_since_warm` names any glyph a
## run drew that was not warmed (the 4-bot smoke test and the playtest's `--fail-on-errors` fail on
## it, headless too), so a new size or character cannot be forgotten.
##
## The game's own font (`PixelFont`, ART4 part 4) is a bitmap font with every glyph of every size it
## has on its pages from the start: nothing is ever rasterized, so warming it only notes its caches,
## and `drawn_since_warm` names a size or outline drawn that it does not have (a cache it did not
## have before) instead.

## The characters warmed: printable ASCII, and the few others the game writes. The game's pixel
## font draws these and no others (a character it lacks draws nothing: it has no system fallback),
## so a new character is drawn in `tools/font_art.py` and listed here (`test_pixel_font.gd`).
const FIRST: int = 32
const LAST: int = 126
const EXTRA: String = "×·•–—…∞°"
## Letters the font draws as one glyph of no character of its own (its ligatures: "fi" is one).
const LIGATURES: String = "fi fl ff ffi ffl ft fj"
## The default font's sizes the game draws (font size, outline size): the labels (8 to 16 px and
## the theme's outline 2; the panels' 3 and 4), the damage numbers (8 px, outline 3), the frame
## rate's readout (10 px, outline 3), the altar's code (16 px, outline 4) and the main menu's title
## (40 px). Measured on a whole biome's play (seed 11, two players) and the menus; a size drawn
## and not listed is named by `drawn_since_warm` (`tests/core/test_glyph_warmup.gd` shows the
## menu and the HUD's widgets). About 10 ms a pair for a font that rasterizes (none for the pixel font, which has them all).
const GAME_SIZES: Array[Vector2i] = [
	Vector2i(8, 0), Vector2i(10, 0), Vector2i(12, 0), Vector2i(14, 0), Vector2i(16, 0),
	Vector2i(8, 2), Vector2i(10, 2), Vector2i(12, 2), Vector2i(14, 2), Vector2i(16, 2),
	Vector2i(8, 3), Vector2i(10, 3), Vector2i(8, 4), Vector2i(16, 4),
	Vector2i(40, 0), Vector2i(40, 2),
]

## The glyphs of each font's caches when warmed, by font and "size/outline".
static var _warmed: Dictionary = {}
## How long the game's warm-up took (ms; `warm_game`).
static var game_ms: float = 0.0


## The default font (the theme's and the damage numbers') warmed at each of GAME_SIZES, once, where
## the renderer may have a thread of its own: never on the web, which has none (its boot is slower,
## and nothing there races): the HUD and Feel each call it as they start. Returns the milliseconds
## it took (0 when warmed already).
static func warm_game() -> float:
	var font := ThemeDB.fallback_font as FontFile
	if font == null or _warmed.has(font) or OS.has_feature("web"):
		return 0.0
	var began: int = Time.get_ticks_usec()
	warm(font, GAME_SIZES)
	game_ms = float(Time.get_ticks_usec() - began) / 1000.0
	return game_ms


## `font`'s glyphs at each of `sizes` (font size, outline size) rasterized now: every character
## warmed and each ligature, at each quarter-pixel offset (the font caches a small glyph once for
## each; `render_range` and `render_glyph` draw all four). Nothing is drawn or handed to the GPU
## here (a label's first draw hands each atlas over once), so nothing races; call it before
## anything draws text (an autoload's `_ready`). A FontFile only (another kind of font draws no
## atlas of its own).
static func warm(font: Font, sizes: Array[Vector2i]) -> void:
	var file := font as FontFile
	if file == null:
		return
	if file.data.is_empty():
		# A bitmap font: every glyph is drawn on its pages already.
		_warmed[file] = glyphs(file)
		return
	var server: TextServer = TextServerManager.get_primary_interface()
	for size: Vector2i in sizes:
		file.render_range(0, size, FIRST, LAST)
		for i in EXTRA.length():
			file.render_glyph(0, size, file.get_glyph_index(size.x, EXTRA.unicode_at(i), 0))
		# A ligature is a glyph of no character: shaped to find it.
		var shaped: RID = server.create_shaped_text()
		server.shaped_text_add_string(shaped, LIGATURES, file.get_rids(), size.x)
		for glyph: Dictionary in server.shaped_text_get_glyphs(shaped):
			file.render_glyph(0, size, int(glyph["index"]))
		server.free_rid(shaped)
	_warmed[file] = glyphs(file)


## The glyphs each of `font`'s caches holds, by "size/outline".
static func glyphs(font: FontFile) -> Dictionary:
	var out: Dictionary = {}
	for size: Vector2i in font.get_size_cache_list(0):
		out["%d/%d" % [size.x, size.y]] = font.get_glyph_list(0, size)
	return out


## The caches of the fonts warmed that drew glyphs since: each "size/outline: before -> now glyphs
## (the characters, when they are characters of their own)".
static func drawn_since_warm() -> PackedStringArray:
	var out := PackedStringArray()
	for font: FontFile in _warmed:
		var before: Dictionary = _warmed[font]
		var bitmap: bool = font.data.is_empty()
		var font_name: String = font.resource_path if not font.resource_path.is_empty() else "the default font"
		var now: Dictionary = glyphs(font)
		for key: String in now:
			var had: PackedInt32Array = before.get(key, PackedInt32Array())
			var has: PackedInt32Array = now[key]
			if bitmap and not before.has(key):
				out.append("%s %s: a size or outline the font does not have" % [font_name, key])
				continue
			if has.size() == had.size():
				continue
			var size: int = int(key.get_slice("/", 0))
			var new_chars: String = ""
			for glyph: int in has:
				if not had.has(glyph):
					new_chars += characters_of(font, size, glyph)
			out.append("%s %s: %d -> %d glyphs (%s)" % [font_name, key, had.size(), has.size(), new_chars.c_escape()])
	return out


## The characters (up to U+2FFF) whose glyph in `font` at `size` is `glyph` (its subpixel offset
## bits left out), for a report.
static func characters_of(font: FontFile, size: int, glyph: int) -> String:
	var out: String = ""
	var bare: int = glyph & 0xFFFFFF
	for code in range(1, 0x3000):
		if font.get_glyph_index(size, code, 0) == bare:
			out += String.chr(code)
	return out
