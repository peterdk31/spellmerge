extends SubViewport
## The damage numbers' glyphs at one font size, on one sheet (the performance pass, 2026-11-23): the
## drawer (`damage_number_drawer.gd`) drew each number's outlines and glyphs from the font's own two
## textures, so numbers over each other broke into a draw call a texture change, and with the screen
## split every view drew them all again (144 of a four-view frame's 465 draw calls). Here each
## character a number may have is drawn once by the font into this viewport, its glyph in the sheet's
## first line and its outline in the second, and a white square after them (a spared hit's line), so
## everything a number draws is a region of the one texture and numbers of one size share a draw
## call however they overlap.
##
## Drawn once: its page asks for the one render as it draws (`UPDATE_ONCE`, so a sheet made after a
## frame's drawing, or out of the tree, renders once its page has drawn), and `ready_now` says when
## its texture holds the glyphs (a frame drawn after that), from when it renders no more
## (`UPDATE_DISABLED`). The sheet's pixels are the font's own, in white, premultiplied
## by their coverage (drawn over nothing), so the drawer draws them with a premultiplied blend
## and its colour times its alpha. View only; nothing is allocated after it is made.
##
## **At art-pixel detail** (ART4 part 4, 2026-11-27): the game's font draws two art pixels a pixel
## of its size (`PixelFont`), so the sheet is drawn DETAIL times its size (its page scaled), and each
## region is that many sheet pixels a world unit: at zoom 1 an art pixel of a number is a pixel of
## the picture, as the HUD's text is.

const VIEW_ONLY: bool = true

## The white square's side (pixels).
const WHITE: int = 4
## Sheet pixels a pixel of the font's size (the font's art detail).
const DETAIL: int = ArtDetail.DETAIL

## The font size this sheet is of, and the room left round a glyph in its cell (its outline's).
var font_size: int = 8
var pad: int = 1
## A cell's height, and the baseline's height in it.
var cell_height: int = 0
var baseline: int = 0

var _font: Font = null
var _outline: int = 0
var _glyphs: PackedStringArray = PackedStringArray()
## By character code: its cell's left edge in the sheet and its width (its advance and the room
## round it), and its advance.
var _left: Dictionary[int, int] = {}
var _wide: Dictionary[int, int] = {}
var _advance: Dictionary[int, float] = {}
var _white_at: Vector2 = Vector2.ZERO
## The drawn frame its page drew in (-1: not yet).
var _page_frame: int = -1


func _init(font: Font, size_of_font: int, outline: int, glyphs: PackedStringArray) -> void:
	_font = font
	font_size = size_of_font
	_outline = outline
	_glyphs = glyphs
	pad = outline + 1
	baseline = pad + ceili(font.get_ascent(size_of_font))
	cell_height = baseline + ceili(font.get_descent(size_of_font)) + pad
	var x: int = 0
	for glyph in glyphs:
		var code: int = glyph.unicode_at(0)
		var advance: float = font.get_char_size(code, size_of_font).x
		_left[code] = x
		_wide[code] = ceili(advance) + pad * 2
		_advance[code] = advance
		x += _wide[code]
	_white_at = Vector2(float(x), 0.0)
	size = Vector2i(x + WHITE, cell_height * 2) * DETAIL
	transparent_bg = true
	disable_3d = true
	gui_disable_input = true
	canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	var page := Node2D.new()
	page.name = "Page"
	page.scale = Vector2(DETAIL, DETAIL)
	page.draw.connect(_draw_page.bind(page))
	add_child(page)


## Whether the sheet's texture holds the glyphs (a frame has been drawn since its page drew).
func ready_now() -> bool:
	if _page_frame < 0 or Engine.get_frames_drawn() <= _page_frame:
		return false
	if render_target_update_mode != SubViewport.UPDATE_DISABLED:
		render_target_update_mode = SubViewport.UPDATE_DISABLED
	return true


## The advance of the character `code` (0 for one not on the sheet).
func advance_of(code: int) -> float:
	return _advance.get(code, 0.0)


## Whether the character `code` is on the sheet.
func has(code: int) -> bool:
	return _left.has(code)


## The sheet's region of `code`'s glyph (`outline`: its outline's), in sheet pixels: DETAIL a pixel
## of `place_of`'s.
func region_of(code: int, outline: bool) -> Rect2:
	var top: float = float(cell_height) if outline else 0.0
	return Rect2(float(_left[code] * DETAIL), top * DETAIL, float(_wide[code] * DETAIL), float(cell_height * DETAIL))


## Where `code`'s cell is drawn for a glyph whose baseline starts at `at`, in the drawer's pixels (a
## DETAIL-th of its region's size): the same pixels as the
## font drawing the character there.
func place_of(code: int, at: Vector2) -> Rect2:
	return Rect2(at.x - float(pad), at.y - float(baseline), float(_wide[code]), float(cell_height))


## The sheet's white square (a pixel in from its edges).
func white_region() -> Rect2:
	return Rect2((_white_at + Vector2.ONE) * float(DETAIL), Vector2.ONE * float((WHITE - 2) * DETAIL))


func _draw_page(page: Node2D) -> void:
	# The one render, asked for as the page draws (again if it is ever drawn again).
	_page_frame = Engine.get_frames_drawn()
	render_target_update_mode = SubViewport.UPDATE_ONCE
	for glyph in _glyphs:
		var code: int = glyph.unicode_at(0)
		var at := Vector2(float(_left[code] + pad), float(baseline))
		page.draw_char(_font, at, glyph, font_size, Color.WHITE)
		page.draw_char_outline(_font, at + Vector2(0.0, float(cell_height)), glyph, font_size, _outline, Color.WHITE)
	page.draw_rect(Rect2(_white_at, Vector2.ONE * float(WHITE)), Color.WHITE)
