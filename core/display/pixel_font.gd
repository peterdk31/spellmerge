class_name PixelFont
extends RefCounted
## The game's text font (ART4 part 4, 2026-11-27): an original pixel face drawn at art-pixel detail,
## two art pixels a layout pixel (docs/STYLE.md, "The picture and the art's detail"), so text on a
## layer drawn at the picture's scale shows every art pixel, as 2x art does, crisp and never blurred.
## `tools/font_art.py` draws the face at each size of its list from glyph parts, onto one glyph sheet
## (`art/ui/fonts/text.png`, imported as an Image) with its metrics (`text.json`); this makes the
## one FontFile every text of the game is drawn with from them, and `install` makes it the theme's
## default font (`ThemeDB.fallback_font` and the engine's default theme: every Label, Button and `get_theme_default_font()`).
##
## **A bitmap font with every size made up front.** The FontFile has no font data, only caches:
## one for each font size in SIZES and outline size up to MAX_OUTLINE, each glyph a region of its
## face's band of the sheet. A size is drawn by the largest face at or under it (a size past the
## last face by a face doubled, tripled: whole art pixels), its line's ascent and descent the size's
## own (`line_of`, the old default font's, so layouts are unchanged). An outline is the sheet's
## one-art-pixel outline (the owner's rule of 2026-11-27: text sits on the game with a one-art-pixel
## dark outline or a hard shadow, whole pixels), and from HEAVY up that outline with a pixel's hard
## shadow down and right. A size or outline outside the lists has no glyphs (`has_size`; the glyph
## warm-up's check names one drawn, `GlyphWarmup.drawn_since_warm`).
##
## Nothing is ever rasterized while the game runs: every glyph is on its page from the start, so the
## font's textures are handed to the GPU once and never written again (core/README.md, "The render
## thread"). View only.

const SHEET: Image = preload("res://art/ui/fonts/text.png")
const METRICS: JSON = preload("res://art/ui/fonts/text.json")

## The font sizes made (layout pixels): every size the game may draw, and the damage numbers' scaled.
const FIRST_SIZE: int = 4
const LAST_SIZE: int = 48
## The outline sizes made (Godot's outline size, any of which draws the one-art-pixel outline).
const MAX_OUTLINE: int = 4
## The outline size from which the outline also has a hard shadow (the panels' and the numbers' 3
## and 4; the theme's labels' 2 is the outline alone).
const HEAVY: int = 3

static var _font: FontFile = null


## The game's font, made the first time it is asked for.
static func font() -> FontFile:
	if _font == null:
		_font = make()
	return _font


## Make the game's font the default of every theme (before any text is drawn: an autoload's): the
## engine's default theme's and the fallback that a theme without a font of its own reads.
static func install() -> void:
	ThemeDB.fallback_font = font()
	ThemeDB.get_default_theme().default_font = font()


## Whether the font draws text of `size` with an outline of `outline`.
static func has_size(size: int, outline: int) -> bool:
	return size >= FIRST_SIZE and size <= LAST_SIZE and outline >= 0 and outline <= MAX_OUTLINE


## A font size's line in layout pixels: its ascent and descent (those of the engine's default font
## the game drew with before, so every layout keeps its lines).
static func line_of(size: int) -> Vector2i:
	return Vector2i(roundi(size * 1.075 + 0.3), roundi(size * 0.3 + 0.4))


## The face a font size is drawn by and its whole-number scale: the largest face times scale at or
## under the size, the smaller scale on a tie (the finer pixel); the smallest face under it.
static func face_of(size: int, faces: Array) -> Vector2i:
	var best := Vector2i(int(faces[0]["size"]), 1)
	var best_at: int = 0
	for scale in range(1, 9):
		for face: Dictionary in faces:
			var at: int = int(face["size"]) * scale
			if at <= size and at > best_at:
				best_at = at
				best = Vector2i(int(face["size"]), scale)
	return best


## A new FontFile of every size and outline from the sheet and its metrics.
static func make() -> FontFile:
	var data: Dictionary = METRICS.data
	var detail: float = float(data["detail"])
	var pad: int = int(data["pad"])
	var chars: String = data["chars"]
	var faces: Array = data["faces"]
	var by_size: Dictionary[int, Dictionary] = {}
	var pages: Dictionary[int, Image] = {}
	for face: Dictionary in faces:
		var size: int = int(face["size"])
		by_size[size] = face
		pages[size] = SHEET.get_region(Rect2i(0, int(face["top"]), SHEET.get_width(), int(face["height"])))
	var file := FontFile.new()
	file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	file.generate_mipmaps = false
	file.multichannel_signed_distance_field = false
	file.allow_system_fallback = false
	file.hinting = TextServer.HINTING_NONE
	file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	file.fixed_size = 0
	for size in range(FIRST_SIZE, LAST_SIZE + 1):
		var pick: Vector2i = face_of(size, faces)
		var face: Dictionary = by_size[pick.x]
		var page: Image = pages[pick.x]
		if pick.y > 1:
			page = page.duplicate()
			page.resize(page.get_width() * pick.y, page.get_height() * pick.y, Image.INTERPOLATE_NEAREST)
		var unit: float = float(pick.y) / detail
		var line: Vector2i = line_of(size)
		var cell_height: int = int(face["cell_height"])
		var gap: int = int(face["gap"])
		var glyphs: Array = face["glyphs"]
		file.set_cache_ascent(0, size, float(line.x))
		file.set_cache_descent(0, size, float(line.y))
		for outline in range(0, MAX_OUTLINE + 1):
			var cache := Vector2i(size, outline)
			var band: int = 0 if outline == 0 else (1 if outline < HEAVY else 2)
			file.set_texture_image(0, cache, 0, page)
			for i in chars.length():
				var code: int = chars.unicode_at(i)
				var glyph: Array = glyphs[i]
				var cell := Rect2(float(glyph[0]), float(int(glyph[1]) + band * cell_height), float(glyph[2]), float(cell_height))
				var art_width: int = int(glyph[3])
				# The pen at the baseline: the cell's top is the face's ascent and the pad above it,
				# its left edge the pad left of half the gap (the glyph's left bearing).
				var left: int = gap / 2 - pad
				var top: int = -(int(face["ascent"]) + pad)
				if outline == 0:
					# A whole layout pixel: the pen stays on the layout's pixels, so every gap is the same.
					file.set_glyph_advance(0, size, code, Vector2(ceilf(float(art_width + gap) * unit), 0.0))
				file.set_glyph_offset(0, cache, code, Vector2(float(left), float(top)) * unit)
				file.set_glyph_size(0, cache, code, cell.size * unit)
				file.set_glyph_uv_rect(0, cache, code, Rect2(cell.position * pick.y, cell.size * pick.y))
				file.set_glyph_texture_idx(0, cache, code, 0)
	return file
