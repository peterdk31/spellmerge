extends RefCounted
## A room kind's symbol as the view draws it (connected biomes CB9: `RoomKind.symbol`), on a bridge's
## mouth (`mouth_symbols.gd`) and on the held map (`party_map_view.gd`). Whole pixels, a dark edge
## round every pixel drawn; `rows` of its SYMBOL_SIDE shown, rising out of its foot (the bottom row of its
## box): at `rows` 1 only its top row shows, at its foot, so a symbol comes in and goes by rows, never
## at once (docs/STYLE.md, "Smooth"). Nothing is allocated.
##
## **The done look** (the owner, 2026-11-20, #883; "cleared" until #888): a fight's, a challenge's or
## a boss's room once cleared, and (the owner's answers on #888) a reward room, a treasure room and
## a secret room once every reward in it is taken and a fountain once drawn dry (`done_by`), tells
## it calmly: its symbol dimmed to its shadow and a check
## (CHECK, in CHECK_COLOUR, with a dark edge) across it. It comes in by DONE_STAGES, a stage a
## frame (`draw`'s `done`): the lit pixels step down to the base (DIM_LIT), the base to the shadow
## (DIM_BASE), the lit pixels on to the shadow (DIM_ALL), and the check is drawn a pixel a stage along
## its stroke (1 ... DONE_STAGES), so nothing changes in one jump and the symbol keeps its own
## shape throughout; whole pixels, never a fade.

## The light when a kind names none (the mouths' own).
const DEFAULT_LIGHT: StringName = &"spark"
## A lit pixel's four sides, where its dark edge may go.
const EDGES: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
## The done look's stages (0 none ... all) and its check, in symbol pixels (x, row of the 7 × 7
## box), in the order its stroke is drawn: the short arm down, then the long arm up.
const DONE_STAGES: int = 7
const CHECK: Array[Vector2i] = [Vector2i(0, 3), Vector2i(1, 4), Vector2i(2, 5), Vector2i(3, 4), Vector2i(4, 3), Vector2i(5, 2), Vector2i(6, 1)]
## The check's colour: the leaf's light, a calm green (docs/STYLE.md's palette).
const CHECK_COLOUR: Color = Color("a0ad55")
## The done look's stages from which the lit pixels are drawn in the base, the base in the
## shadow, and the lit pixels in the shadow too.
const DIM_LIT: int = 1
const DIM_BASE: int = 2
const DIM_ALL: int = 3


## What makes a room of a kind done (`done_by`): nothing (it never shows the done look), its clear
## (a fight's), its fountain drawn dry (nothing left to give), its rewards taken (entered, and every
## reward item that lay in it opened).
const DONE_NEVER: int = 0
const DONE_CLEARED: int = 1
const DONE_DRY: int = 2
const DONE_TAKEN: int = 3


## What makes a room of `kind` done, for its done look (the owner's answers on #888): a room with a
## fight (enemies, elites, a boss) once cleared; a fountain once drawn dry; a room of no fill that
## rewards its entering (a reward room, a treasure room, a secret room) once everything in it is
## taken. The rest (the start, a shop: the owner's "not shops") never.
static func done_by(kind: RoomKind) -> int:
	if kind == null:
		return DONE_NEVER
	if kind.fills_with_enemies() or kind.fill == RoomKind.FILL_BOSS:
		return DONE_CLEARED
	if kind.fill == RoomKind.FILL_FOUNTAIN:
		return DONE_DRY
	if kind.fill == RoomKind.FILL_NONE and kind.rewards != &"":
		return DONE_TAKEN
	return DONE_NEVER


## True when a room of `kind` keeps its symbol hidden until its door is found open (a secret room,
## the owner's answer on #888: unmarked until discovered, its rock broken).
static func hidden_until_opened(kind: RoomKind) -> bool:
	return kind != null and kind.door == RoomKind.DOOR_SECRET


## True when a room of `kind` shows the done look once done (`done_by`).
static func shows_done(kind: RoomKind) -> bool:
	return done_by(kind) != DONE_NEVER


## The shades a kind's symbol is drawn in (shadow, base, light): its light's, else the spark's.
static func shades_of(kind: RoomKind) -> PackedColorArray:
	var material: StringName = kind.light if kind != null and kind.light != &"" else DEFAULT_LIGHT
	var shades: PackedColorArray = Palette.shades_of(material)
	return shades if shades.size() == 3 else Palette.shades_of(DEFAULT_LIGHT)


## Draw `pixels` (`RoomKind.symbol_pixels`) on `canvas` with its box's corner at `at` (whole pixels),
## `size` screen pixels a symbol pixel, `rows` of its rows shown (0 none ... SYMBOL_SIDE all), in
## `shades` (shadow, base, light), with an edge of Palette.OUTLINE round the pixels drawn. `side`: the
## picture's (a reward glyph's is smaller, `reward_glyphs.gd`). `done`: the done look's stage
## (0 none ... DONE_STAGES; only for a SYMBOL_SIDE picture).
static func draw(canvas: CanvasItem, pixels: PackedByteArray, shades: PackedColorArray, at: Vector2, rows: int, size: int = 1, side: int = RoomKind.SYMBOL_SIDE, done: int = 0) -> void:
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
				canvas.draw_rect(Rect2(at + Vector2(x, top + r) * size, unit), colour_of(pixel, shades, done))
	if side == RoomKind.SYMBOL_SIDE and done > 0:
		_draw_check(canvas, at, rows, top, size, check_shown(done))


## The colour a symbol pixel (`RoomKind.SYMBOL_LIT` or `SYMBOL_BASE`) is drawn in, in `shades`
## (shadow, base, light), at the done look's stage `done`: a shade down at a time (DIM_LIT,
## DIM_BASE, DIM_ALL), to the shadow.
static func colour_of(pixel: int, shades: PackedColorArray, done: int) -> Color:
	if pixel == RoomKind.SYMBOL_LIT:
		if done >= DIM_ALL:
			return shades[0]
		return shades[1] if done >= DIM_LIT else shades[2]
	return shades[0] if done >= DIM_BASE else shades[1]


## How many of the check's pixels the done look's stage `done` draws.
static func check_shown(done: int) -> int:
	return clampi(done, 0, CHECK.size())


## The check's first `shown` pixels (of the rows shown: picture row r sits at box row top + r), with
## an edge of Palette.OUTLINE round them.
static func _draw_check(canvas: CanvasItem, at: Vector2, rows: int, top: int, size: int, shown: int) -> void:
	var unit := Vector2(size, size)
	for index in shown:
		var pixel: Vector2i = CHECK[index]
		if pixel.y >= rows:
			continue
		for edge: Vector2i in EDGES:
			var near: Vector2i = pixel + edge
			if near.y < 0 or near.y >= rows or _in_check(near, shown):
				continue
			canvas.draw_rect(Rect2(at + Vector2(near.x, top + near.y) * size, unit), Palette.OUTLINE)
	for index in shown:
		var pixel: Vector2i = CHECK[index]
		if pixel.y < rows:
			canvas.draw_rect(Rect2(at + Vector2(pixel.x, top + pixel.y) * size, unit), CHECK_COLOUR)


static func _in_check(pixel: Vector2i, shown: int) -> bool:
	for index in shown:
		if CHECK[index] == pixel:
			return true
	return false
