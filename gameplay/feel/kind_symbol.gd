extends RefCounted
## A room kind's symbol as the view draws it (connected biomes CB9: `RoomKind.symbol`), on a bridge's
## mouth (`mouth_symbols.gd`) and on the held map (`party_map_view.gd`). Whole pixels, a dark edge
## round every pixel drawn; `rows` of its SYMBOL_SIDE shown, rising out of its foot (the bottom row of its
## box): at `rows` 1 only its top row shows, at its foot, so a symbol comes in and goes by rows, never
## at once (docs/STYLE.md, "Smooth"). Nothing is allocated.

## The light when a kind names none (the mouths' own).
const DEFAULT_LIGHT: StringName = &"spark"
## A lit pixel's four sides, where its dark edge may go.
const EDGES: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]


## The shades a kind's symbol is drawn in (shadow, base, light): its light's, else the spark's.
static func shades_of(kind: RoomKind) -> PackedColorArray:
	var material: StringName = kind.light if kind != null and kind.light != &"" else DEFAULT_LIGHT
	var shades: PackedColorArray = Palette.shades_of(material)
	return shades if shades.size() == 3 else Palette.shades_of(DEFAULT_LIGHT)


## Draw `pixels` (`RoomKind.symbol_pixels`) on `canvas` with its box's corner at `at` (whole pixels),
## `size` screen pixels a symbol pixel, `rows` of its rows shown (0 none ... SYMBOL_SIDE all), in
## `shades` (shadow, base, light), with an edge of Palette.OUTLINE round the pixels drawn.
static func draw(canvas: CanvasItem, pixels: PackedByteArray, shades: PackedColorArray, at: Vector2, rows: int, size: int = 1) -> void:
	var side: int = RoomKind.SYMBOL_SIDE
	if pixels.size() != side * side or rows <= 0 or shades.size() < 3:
		return
	rows = mini(rows, side)
	# Shown row r of the picture sits at row (side - rows + r) of the box.
	var top: int = side - rows
	var unit := Vector2(size, size)
	for r in rows:
		for x in side:
			if pixels[r * side + x] == RoomKind.SYMBOL_NONE:
				continue
			for edge: Vector2i in EDGES:
				var ex: int = x + edge.x
				var er: int = r + edge.y
				var inside: bool = ex >= 0 and ex < side and er >= 0 and er < rows
				if not inside or pixels[er * side + ex] == RoomKind.SYMBOL_NONE:
					canvas.draw_rect(Rect2(at + Vector2(ex, top + er) * size, unit), Palette.OUTLINE)
	for r in rows:
		for x in side:
			var pixel: int = pixels[r * side + x]
			if pixel != RoomKind.SYMBOL_NONE:
				canvas.draw_rect(Rect2(at + Vector2(x, top + r) * size, unit), shades[2] if pixel == RoomKind.SYMBOL_LIT else shades[1])
