extends Node2D
## What a bridge's mouth tells of what lies behind it (connected biomes CB9, "What the players see":
## "A bridge mouth tells what lies behind it (a kind symbol)"): the symbol of the kind of the room the
## mouth leads into (`RoomKind.symbol`, drawn by `kind_symbol.gd`), on the bridge just outside the
## mouth, centred along it. A kind with no symbol tells nothing. A reward room's mouth also tells its
## type (`RewardType`, the owner's ask of 2026-11-19; `reward_glyphs.gd`): its glyphs beside the
## symbol, in a row on its right for a mouth across the bridge's way, else in a column under it, rising
## with it by rows (each glyph's SIDE rows). View only: it reads Feel's mouths
## (`mouth_looks.gd`: each mouth's area and room), the rooms' kinds (Feel's room hearing) and where
## this machine's wizards stand; nothing in the game reads it.
##
## **Smooth** (docs/STYLE.md): a mouth's symbol rises in by rows, a row a frame at FPS, while one of
## this machine's wizards (`Frames.seats_here`, a seat's own body) is within SHOW_REACH of the mouth
## or on its bridge (so the far end of a long bridge tells as the wizard sets out on it), but not from
## inside the room it leads into (that tells nothing new), and sinks out
## the same way once none is; a biome laid (a new one, a restore's) is drawn as it
## stands. Whole pixels; nothing fades.
##
## A child of Feel, top level (world space), over the mouths' looks and under the bodies. Feel steps it
## once a frame (`step`).

const ActorsScript := preload("res://core/actors/actors.gd")
const RoomHearingScript := preload("res://gameplay/feel/room_hearing.gd")
const MouthLooksScript := preload("res://gameplay/feel/mouth_looks.gd")
const KindSymbolScript := preload("res://gameplay/feel/kind_symbol.gd")
const RewardGlyphsScript := preload("res://gameplay/feel/reward_glyphs.gd")

## Over the mouths' looks (1), under the bodies.
const Z: int = 2
## Frames a second it rises and sinks at, a row a frame.
const FPS: float = 12.0
## How near a mouth one of this machine's wizards must stand for it to tell (pixels).
const SHOW_REACH: float = 160.0
## The gap between a mouth's edge and its symbol (pixels).
const GAP: int = 4

## The pieces (Feel's room hearing: each room's kind) and the mouths (Feel's mouth looks).
var pieces: RoomHearingScript = null
var mouths: MouthLooksScript = null

## By mouth: its symbol's pixels (empty: tells nothing), shades, box corner (world pixels), the
## mouth's middle, and the rows shown now.
var _pixels: Array[PackedByteArray] = []
var _shades: Array[PackedColorArray] = []
var _at: PackedVector2Array = PackedVector2Array()
var _middle: PackedVector2Array = PackedVector2Array()
## By mouth: the walkway (place) it lies on.
var _walkway: PackedInt32Array = PackedInt32Array()
var _rows: PackedInt32Array = PackedInt32Array()
## By mouth: its reward type's glyphs (each an Array[PackedByteArray] and an
## Array[PackedColorArray]; empty: none), their first's corner and whether they run in a row.
var _glyph_pixels: Array = []
var _glyph_shades: Array = []
var _glyph_at: PackedVector2Array = PackedVector2Array()
var _glyph_across: PackedByteArray = PackedByteArray()
## What each mouth wants this frame (1: shown).
var _near: PackedByteArray = PackedByteArray()
## The mouths read last: how many and the world they were found in (`RoomHearing.world`).
var _read_mouths: int = -1
var _read_world: int = -1
var _read_places: int = -1
var _clock: float = 0.0


func _ready() -> void:
	top_level = true
	z_index = Z


## How many mouths it knows, mouth `mouth`'s rows shown (0 ... SYMBOL_SIDE; -1: none) and its box's
## corner (for tests).
func count() -> int:
	return _rows.size()


func rows_of(mouth: int) -> int:
	return _rows[mouth] if mouth >= 0 and mouth < _rows.size() else -1


func corner_of(mouth: int) -> Vector2:
	return _at[mouth] if mouth >= 0 and mouth < _at.size() else Vector2.INF


## How many glyphs of its room's reward type mouth `mouth` tells (0: none), and their first's corner.
func glyphs_of(mouth: int) -> int:
	return (_glyph_pixels[mouth] as Array).size() if mouth >= 0 and mouth < _glyph_pixels.size() else 0


func glyph_corner_of(mouth: int) -> Vector2:
	return _glyph_at[mouth] if mouth >= 0 and mouth < _glyph_at.size() else Vector2.INF


## True when mouth `mouth` has a symbol to tell.
func tells(mouth: int) -> bool:
	return mouth >= 0 and mouth < _pixels.size() and not _pixels[mouth].is_empty()


## Once a frame, `delta` real seconds on: the mouths read again for a new biome (from `grid`), each
## mouth told whether one of this machine's wizards (`seats_here` of `table`) is near, and each symbol
## stepped a row toward it at FPS.
func step(delta: float, table: ActorsScript, seats_here: int, grid: RoomGrid) -> void:
	var found: int = mouths.mouths() if mouths != null else 0
	var world_now: int = pieces.world() if pieces != null else 0
	var places: int = grid.places() if grid != null else 0
	if found != _read_mouths or world_now != _read_world or places != _read_places:
		_read_places = places
		_read(grid, found, world_now, table, seats_here)
	if _rows.is_empty():
		return
	_see(table, seats_here, grid)
	if not is_moving():
		_clock = 0.0
		return
	_clock += delta
	var change: float = 1.0 / FPS
	while _clock >= change:
		_clock -= change
		advance()


## True while a symbol still rises or sinks.
func is_moving() -> bool:
	for mouth in _rows.size():
		if _rows[mouth] != _wanted(mouth):
			return true
	return false


## One row of every change (a frame at FPS).
func advance() -> void:
	for mouth in _rows.size():
		_rows[mouth] += signi(_wanted(mouth) - _rows[mouth])
	queue_redraw()


func _wanted(mouth: int) -> int:
	return RoomKind.SYMBOL_SIDE if _near[mouth] != 0 and not _pixels[mouth].is_empty() else 0


## Whether one of this machine's wizards stands within SHOW_REACH of each mouth.
func _see(table: ActorsScript, seats_here: int, grid: RoomGrid) -> void:
	_near.fill(0)
	if table == null:
		return
	for seat in ActorsScript.SEATS:
		if seats_here & (1 << seat) == 0:
			continue
		var body := table.node_of(table.home_of_seat(seat)) as Node2D
		if body == null or not is_instance_valid(body) or not body.is_inside_tree():
			continue
		var at: Vector2 = body.global_position
		var on: int = grid.place_at(at) if grid != null else RoomGrid.NO_PLACE
		for mouth in _middle.size():
			if on != RoomGrid.NO_PLACE and on == mouths.room_of(mouth):
				# Inside the room the mouth leads into: it tells nothing new.
				continue
			if at.distance_to(_middle[mouth]) <= SHOW_REACH or (on != RoomGrid.NO_PLACE and on == _walkway[mouth]):
				_near[mouth] = 1


## Every mouth's symbol from the mouths found (`mouths`), each on its bridge's side of its mouth; drawn
## as it stands (a world laid is never played in).
func _read(grid: RoomGrid, found: int, world_now: int, table: ActorsScript, seats_here: int) -> void:
	_read_mouths = found
	_read_world = world_now
	_pixels.clear()
	_shades.clear()
	_glyph_pixels.clear()
	_glyph_shades.clear()
	_glyph_at.resize(found)
	_glyph_across.resize(found)
	_at.resize(found)
	_middle.resize(found)
	_walkway.resize(found)
	_rows.resize(found)
	_near.resize(found)
	for mouth in found:
		var room: int = mouths.room_of(mouth)
		var kind: RoomKind = pieces.kind_of(room) if pieces != null else null
		_pixels.append(kind.symbol_pixels() if kind != null else PackedByteArray())
		_shades.append(KindSymbolScript.shades_of(kind))
		var area: Rect2i = mouths.area_of(mouth)
		var middle: Vector2 = Rect2(area).get_center()
		_middle[mouth] = middle
		_walkway[mouth] = grid.place_at(middle) if grid != null else RoomGrid.NO_PLACE
		_at[mouth] = corner_beside(area, grid.place_rect(room) if grid != null else Rect2())
		var type: RewardType = pieces.type_of(room) if pieces != null and kind != null else null
		var glyphs: Array[PackedByteArray] = []
		var glyph_shades: Array[PackedColorArray] = []
		var element: Resource = pieces.content(RewardGlyphsScript.CARD_FOLDER, type.element) if type != null else null
		RewardGlyphsScript.glyphs_of(type, element, glyphs, glyph_shades)
		_glyph_pixels.append(glyphs)
		_glyph_shades.append(glyph_shades)
		var across: bool = area.size.x > area.size.y
		_glyph_across[mouth] = 1 if across else 0
		_glyph_at[mouth] = glyphs_beside(_at[mouth], across)
	_see(table, seats_here, grid)
	for mouth in found:
		_rows[mouth] = _wanted(mouth)
	queue_redraw()


## The corner of a symbol's box beside a mouth of area `area` into a room of rect `room`: on the far
## side of the mouth from the room's middle (the bridge's), GAP from its edge, centred along it, in
## whole pixels.
static func corner_beside(area: Rect2i, room: Rect2) -> Vector2:
	var side: int = RoomKind.SYMBOL_SIDE
	var middle: Vector2i = area.position + area.size / 2
	var towards: Vector2 = room.get_center() - Vector2(middle) if room.has_area() else Vector2.DOWN
	if area.size.x > area.size.y:
		var x: int = middle.x - side / 2
		return Vector2(x, area.position.y - GAP - side) if towards.y > 0.0 else Vector2(x, area.end.y + GAP)
	var y: int = middle.y - side / 2
	return Vector2(area.position.x - GAP - side, y) if towards.x > 0.0 else Vector2(area.end.x + GAP, y)


## The corner of a reward type's first glyph beside a symbol whose box's corner is `symbol`: on its
## right, feet level with its foot, for a mouth across the bridge's way (`across`); else under it,
## centred.
static func glyphs_beside(symbol: Vector2, across: bool) -> Vector2:
	var side: int = RoomKind.SYMBOL_SIDE
	var glyph: int = RewardGlyphsScript.SIDE
	if across:
		return symbol + Vector2(side + RewardGlyphsScript.GAP, side - glyph)
	return symbol + Vector2((side - glyph) / 2, side + RewardGlyphsScript.GAP)


func _draw() -> void:
	for mouth in _rows.size():
		if _rows[mouth] > 0:
			KindSymbolScript.draw(self, _pixels[mouth], _shades[mouth], _at[mouth], _rows[mouth])
			# Each a typed array as made in `_read` (nothing allocated here).
			RewardGlyphsScript.draw(self, _glyph_pixels[mouth], _glyph_shades[mouth], _glyph_at[mouth], _glyph_across[mouth] != 0, _rows[mouth])
