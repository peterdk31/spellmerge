extends RefCounted
## The HUD's frames, tiles and lines at the art's detail (ART4, the owner's decision of 2026-11-21:
## all art at 64×64 a cell; docs/STYLE.md, "The picture and the art's detail" and "UI"). The HUD
## is laid out in layout pixels and drawn at the picture's scale, so one layout pixel is two picture
## pixels; what these draw is in **art pixels**, half a layout pixel (`A`), so an outline is one
## picture pixel and a frame has room for a lit edge and a shade beside it, as the redrawn sprites
## do. Every place and size the callers pass is in whole layout pixels, as before: the layouts, the
## hit boxes and the steps of a shade or a fill keep their numbers, and only the drawing inside them
## is finer.
##
## The shape and light rules of each part are here, once (docs/STYLE.md: a 1 px Outline, corners cut
## by one pixel, light from the top-left, at most three shades a material, palette colours only):
##
## - `frame`: a raised frame four art pixels deep (a player's corner panel): the Outline, cut at the
##   corners; a lit top and left edge and a shaded bottom and right one; the ramp's base; and an
##   inner Outline that parts the frame from what it holds.
## - `tile`: a slot's edge two art pixels deep (a cast's frame round its cards, a quick-use cell):
##   the Outline, cut at the corners, then a lit top and left edge and a base bottom and right one.
##   `dashed_tile` is the same with its lit edge broken every other art pixel pair (a recharge).
## - `trough`: a line's sunken track (the health and mana lines): its top art row in the Outline,
##   the rest the track's colour; `line_fill`: the fill in it under that lip (`under_lip`), its
##   bottom art row in its shade.
##
## Static, display only: each call draws a handful of rects on `target` and allocates nothing.
## `target` is the CanvasItem drawn on, or anything with its `draw_rect(rect, color)` (the tests'
## pixel recorder, `tests/hud/test_hud_art.gd`, which reads every art pixel a part sets).

## One art pixel, in layout pixels.
const A: float = 0.5

## The palette's Outline: every frame's outer line and the deepest shadow.
const OUTLINE: Color = Color("#14121f")

## A material's three shades, lightest first (docs/STYLE.md, "Palette"): index LIGHT, BASE, SHADOW.
const LIGHT: int = 0
const BASE: int = 1
const SHADOW: int = 2
const STONE: PackedColorArray = [Color("#7a7694"), Color("#4a4663"), Color("#2b2840")]
const SPARK: PackedColorArray = [Color("#fff3a6"), Color("#f2c230"), Color("#b8801f")]
const FIRE: PackedColorArray = [Color("#ffa23c"), Color("#e0592f"), Color("#8f2d2a")]
const MANA: PackedColorArray = [Color("#6f86f0"), Color("#2c3aa8"), Color("#161c55")]
## The four players' ramps, by seat (the panels' and the markers' colours).
const PLAYER_1: PackedColorArray = [Color("#7fc0f0"), Color("#3b73c9"), Color("#1d3a6b")]
const PLAYER_2: PackedColorArray = [Color("#f59ab8"), Color("#d9477a"), Color("#7a2347")]
const PLAYER_3: PackedColorArray = [Color("#8fd46a"), Color("#3f8f4f"), Color("#1f4a3a")]
const PLAYER_4: PackedColorArray = [Color("#c99af0"), Color("#8a4fc4"), Color("#4a2a6b")]
const PLAYERS: Array[PackedColorArray] = [PLAYER_1, PLAYER_2, PLAYER_3, PLAYER_4]
## How deep `frame` and `tile` are, in layout pixels.
const FRAME_DEPTH: float = 4.0 * A
const TILE_DEPTH: float = 2.0 * A


## Seat `seat`'s ramp (clamped to the four).
static func player_ramp(seat: int) -> PackedColorArray:
	return PLAYERS[clampi(seat, 0, PLAYERS.size() - 1)]


## A raised frame round `rect` (layout pixels), `FRAME_DEPTH` deep, in `ramp`: the Outline cut at
## the corners, the lit top-left and shaded bottom-right edge, the base, and an inner Outline.
static func frame(target: Object, rect: Rect2, ramp: PackedColorArray) -> void:
	if rect.size.x < FRAME_DEPTH * 2.0 + A or rect.size.y < FRAME_DEPTH * 2.0 + A:
		return
	var lit: Rect2 = rect.grow(-A)
	bevel(target, lit, ramp[LIGHT], ramp[SHADOW], ramp[BASE])
	ring(target, lit.grow(-A), ramp[BASE])
	ring(target, lit.grow(-2.0 * A), OUTLINE)
	cut_ring(target, rect, OUTLINE)


## A slot's edge round `rect` (layout pixels), `TILE_DEPTH` deep: the Outline cut at the corners,
## then `lit` on the top and left and `base` on the bottom and right. What it holds is drawn
## inside `rect.grow(-TILE_DEPTH)`; a fill under the whole tile goes in `inside_cut(rect)`, so its
## cut corners stay open.
static func tile(target: Object, rect: Rect2, lit: Color, base: Color) -> void:
	if rect.size.x < TILE_DEPTH * 2.0 or rect.size.y < TILE_DEPTH * 2.0:
		return
	bevel(target, rect.grow(-A), lit, base, base)
	cut_ring(target, rect, OUTLINE)


## `tile`'s edge with its coloured line broken: two art pixels drawn, two left out, along each
## side from inside the cut corners (the recharge's dashed frame; the same pitch as the layout pixel's dashes
## it replaces). The Outline stays whole, so the slot keeps its shape.
static func dashed_tile(target: Object, rect: Rect2, lit: Color, base: Color) -> void:
	if rect.size.x < TILE_DEPTH * 2.0 or rect.size.y < TILE_DEPTH * 2.0:
		return
	var edge: Rect2 = rect.grow(-A)
	var x: float = edge.position.x + A
	while x < edge.end.x - A:
		var wide: float = minf(2.0 * A, edge.end.x - A - x)
		target.draw_rect(Rect2(x, edge.position.y, wide, A), lit)
		target.draw_rect(Rect2(x, edge.end.y - A, wide, A), base)
		x += 4.0 * A
	var y: float = edge.position.y + A
	while y < edge.end.y - A:
		var tall: float = minf(2.0 * A, edge.end.y - A - y)
		target.draw_rect(Rect2(edge.position.x, y, A, tall), lit)
		target.draw_rect(Rect2(edge.end.x - A, y, A, tall), base)
		y += 4.0 * A
	cut_ring(target, rect, OUTLINE)


## The part of `rect` a fill under a `tile` or `frame` covers: all but its outer art pixel, so the
## cut corners show what is under the tile, as a sprite's do.
static func inside_cut(rect: Rect2) -> Rect2:
	return rect.grow(-A)


## A line's sunken track over `rect` (layout pixels): its top art row in the Outline (the trough's
## shade, under the light from the top-left), the rest in `track`.
static func trough(target: Object, rect: Rect2, track: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	target.draw_rect(rect, track)
	target.draw_rect(Rect2(rect.position, Vector2(rect.size.x, A)), OUTLINE)


## The part of a trough's `rect` under its Outline lip, where its fill goes (all of a trough one art
## pixel tall, which has no lip to spare).
static func under_lip(rect: Rect2) -> Rect2:
	if rect.size.y <= A:
		return rect
	return Rect2(rect.position.x, rect.position.y + A, rect.size.x, rect.size.y - A)


## A line's fill over `rect` (layout pixels) in its trough: `color`, its bottom art row in `shade`
## (a fill one art pixel tall is all `color`).
static func line_fill(target: Object, rect: Rect2, color: Color, shade: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	target.draw_rect(rect, color)
	if rect.size.y > A:
		target.draw_rect(Rect2(rect.position.x, rect.end.y - A, rect.size.x, A), shade)


## A ring one art pixel wide just inside `rect`, in `color`.
static func ring(target: Object, rect: Rect2, color: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	target.draw_rect(Rect2(rect.position, Vector2(rect.size.x, A)), color)
	target.draw_rect(Rect2(rect.position.x, rect.end.y - A, rect.size.x, A), color)
	target.draw_rect(Rect2(rect.position.x, rect.position.y + A, A, rect.size.y - 2.0 * A), color)
	target.draw_rect(Rect2(rect.end.x - A, rect.position.y + A, A, rect.size.y - 2.0 * A), color)


## A ring one art pixel wide just inside `rect` with its corners cut by one pixel: each side stops
## an art pixel short of the corner, and the art pixel diagonally inside the corner closes it, so
## the line steps round the corner one pixel at a time (docs/STYLE.md, "Outline").
static func cut_ring(target: Object, rect: Rect2, color: Color) -> void:
	var left: float = rect.position.x
	var top: float = rect.position.y
	var right: float = rect.end.x - A
	var bottom: float = rect.end.y - A
	target.draw_rect(Rect2(left + A, top, rect.size.x - 2.0 * A, A), color)
	target.draw_rect(Rect2(left + A, bottom, rect.size.x - 2.0 * A, A), color)
	target.draw_rect(Rect2(left, top + A, A, rect.size.y - 2.0 * A), color)
	target.draw_rect(Rect2(right, top + A, A, rect.size.y - 2.0 * A), color)
	for corner: Vector2 in [Vector2(left + A, top + A), Vector2(right - A, top + A), Vector2(left + A, bottom - A), Vector2(right - A, bottom - A)]:
		target.draw_rect(Rect2(corner, Vector2(A, A)), color)


## A ring one art pixel wide just inside `rect`: `lit` on the top and left, `shade` on the bottom
## and right, and `corner` at the top-right and bottom-left art pixels, where the two meet.
static func bevel(target: Object, rect: Rect2, lit: Color, shade: Color, corner: Color) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var right: float = rect.end.x - A
	var bottom: float = rect.end.y - A
	target.draw_rect(Rect2(rect.position, Vector2(rect.size.x - A, A)), lit)
	target.draw_rect(Rect2(rect.position.x, rect.position.y + A, A, rect.size.y - 2.0 * A), lit)
	target.draw_rect(Rect2(rect.position.x + A, bottom, rect.size.x - A, A), shade)
	target.draw_rect(Rect2(right, rect.position.y + A, A, rect.size.y - 2.0 * A), shade)
	target.draw_rect(Rect2(right, rect.position.y, A, A), corner)
	target.draw_rect(Rect2(rect.position.x, bottom, A, A), corner)
