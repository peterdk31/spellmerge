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
## **Big and lit** (the owner, 2026-11-19: "room types must be much easier to see"): the sign is
## drawn SCALE screen pixels a symbol pixel (a 7 px symbol is 21 px, its glyphs 15 px), whole pixels
## with a dark edge as wide, and lit: a light spot of the kind's light stands on it (`LightSpot`, a
## marker a sign that tells; the spell light draws it while "Dynamic lighting" is on), so it reads in
## a dark crypt from the far side of a room. It rises in by rows, a row a frame at FPS, while one of
## this machine's wizards (`Frames.seats_here`, a seat's own body) is within SHOW_REACH of the mouth or
## on its bridge, but not from inside the room it leads into, and sinks out the same way once none is
## (the owner, 2026-11-19); its light dims and brightens with its rows.
##
## **Done** (the owner, 2026-11-20, #883 and #888): once the room a mouth leads into is done (Feel's
## room hearing, `is_done`: a fight's cleared, `rooms_cleared`; a fountain drawn dry; a reward,
## treasure or secret room's rewards taken: `KindSymbol.done_by`; never a shop), its sign steps to
## the calm done look (`kind_symbol.gd`: the symbol dimmed to its shadow, a check drawn across it along its
## stroke), a stage a frame at FPS through `KindSymbol.DONE_STAGES`, and its light dims with it
## (to DONE_LIGHT of its own); on every mouth into that room. A secret room's sign stays down until
## the room is found, its rock broken (`KindSymbol.hidden_until_opened`, the room hearing's
## `is_opened`), and then rises as any sign does.
##
## **Smooth** (docs/STYLE.md): a biome laid (a new one, a restore's) and the rooms done told again
## after a restore are drawn as they stand. Whole pixels; nothing fades.
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
## Screen pixels a symbol pixel (and a glyph pixel).
const SCALE: int = 3
## How near a mouth one of this machine's wizards must stand for its sign to rise in (pixels).
const SHOW_REACH: float = 320.0
## The gap between a mouth's edge and its symbol (pixels).
const GAP: int = 4
## A sign's light: how far it reaches and how bright it is at its middle (`LightSpot`).
const LIGHT_REACH: float = 56.0
const LIGHT_STRENGTH: float = 0.6
## A done room's sign's light, a share of LIGHT_STRENGTH (reached by the done look's stages).
const DONE_LIGHT: float = 0.5

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
## By mouth: whether its room's kind shows the done look once done (1), and the done look's stage drawn.
var _tells_done: PackedByteArray = PackedByteArray()
## By mouth: its room's symbol is hidden until the room is opened (1: a secret room, `KindSymbol.hidden_until_opened`).
var _hidden: PackedByteArray = PackedByteArray()
var _done: PackedInt32Array = PackedInt32Array()
## The room hearing's `done_again` as read last (a change: the rooms done drawn as they stand).
var _read_again: int = 0
## By mouth: its reward type's glyphs (each an Array[PackedByteArray] and an
## Array[PackedColorArray]; empty: none), their first's corner and whether they run in a row.
var _glyph_pixels: Array = []
var _glyph_shades: Array = []
var _glyph_at: PackedVector2Array = PackedVector2Array()
var _glyph_across: PackedByteArray = PackedByteArray()
## By mouth: the light spot on its sign (null: it tells nothing).
var _lights: Array[Marker2D] = []
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


## Mouth `mouth`'s done look's stage (0 none ... `KindSymbol.DONE_STAGES`; for tests).
func done_of(mouth: int) -> int:
	return _done[mouth] if mouth >= 0 and mouth < _done.size() else 0


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
## mouth told whether one of this machine's wizards (`seats_here` of `table`) is near, and each
## symbol stepped a row toward it at FPS.
func step(delta: float, table: ActorsScript, seats_here: int, grid: RoomGrid) -> void:
	var found: int = mouths.mouths() if mouths != null else 0
	var world_now: int = pieces.world() if pieces != null else 0
	var places: int = grid.places() if grid != null else 0
	if found != _read_mouths or world_now != _read_world or places != _read_places:
		_read_places = places
		_read(grid, found, world_now, table, seats_here)
	if _rows.is_empty():
		return
	var again: int = pieces.done_again() if pieces != null else 0
	if again != _read_again:
		_read_again = again
		_settle_done()
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
		if _rows[mouth] != _wanted(mouth) or _done[mouth] != _done_wanted(mouth):
			return true
	return false


## One row of every change (a frame at FPS).
func advance() -> void:
	for mouth in _rows.size():
		var was: int = _rows[mouth]
		var was_done: int = _done[mouth]
		_rows[mouth] += signi(_wanted(mouth) - _rows[mouth])
		_done[mouth] += signi(_done_wanted(mouth) - _done[mouth])
		if _rows[mouth] != was or _done[mouth] != was_done:
			# Its light dims and brightens with its rows (made again only while a sign moves).
			_light(mouth)
	queue_redraw()


func _wanted(mouth: int) -> int:
	if _near[mouth] == 0 or _pixels[mouth].is_empty() or not _shown(mouth):
		return 0
	return RoomKind.SYMBOL_SIDE


## False while mouth `mouth`'s room keeps its symbol hidden (a secret room not yet opened).
func _shown(mouth: int) -> bool:
	return _hidden[mouth] == 0 or (pieces != null and pieces.is_opened(mouths.room_of(mouth)))


func _done_wanted(mouth: int) -> int:
	if _tells_done[mouth] == 0 or pieces == null or not pieces.is_done(mouths.room_of(mouth)):
		return 0
	return KindSymbolScript.DONE_STAGES


## Every mouth's done look as it stands (a restore's rooms done, told again), its light with it.
func _settle_done() -> void:
	for mouth in _done.size():
		var wanted: int = _done_wanted(mouth)
		var rows: int = _rows[mouth] if _hidden[mouth] == 0 else _wanted(mouth)
		if _done[mouth] != wanted or _rows[mouth] != rows:
			# A secret room's sign found or lost by the restore is drawn as it stands too.
			_done[mouth] = wanted
			_rows[mouth] = rows
			_light(mouth)
	queue_redraw()


## Whether one of this machine's wizards stands within SHOW_REACH of each mouth or on its bridge, and
## not inside the room it leads into (that tells nothing new); with none here, anyone's.
func _see(table: ActorsScript, seats_here: int, grid: RoomGrid) -> void:
	_near.fill(0)
	if table == null:
		return
	# With no seat here that has a wizard (a recording, a machine waiting for its seat), everyone's
	# wizards tell, as the party camera then holds everyone.
	var seats: int = seats_here
	for seat in ActorsScript.SEATS:
		if seats_here & (1 << seat) != 0 and table.node_of(table.home_of_seat(seat)) is Node2D:
			break
		if seat == ActorsScript.SEATS - 1:
			seats = (1 << ActorsScript.SEATS) - 1
	for seat in ActorsScript.SEATS:
		if seats & (1 << seat) == 0:
			continue
		var body := table.node_of(table.home_of_seat(seat)) as Node2D
		if body == null or not is_instance_valid(body) or not body.is_inside_tree():
			continue
		var at: Vector2 = body.global_position
		var on: int = grid.place_at(at) if grid != null else RoomGrid.NO_PLACE
		for mouth in _middle.size():
			if on != RoomGrid.NO_PLACE and on == mouths.room_of(mouth):
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
	_tells_done.resize(found)
	_hidden.resize(found)
	_done.resize(found)
	_read_again = pieces.done_again() if pieces != null else 0
	for mouth in found:
		var room: int = mouths.room_of(mouth)
		var kind: RoomKind = pieces.kind_of(room) if pieces != null else null
		_pixels.append(kind.symbol_pixels() if kind != null else PackedByteArray())
		_tells_done[mouth] = 1 if KindSymbolScript.shows_done(kind) else 0
		_hidden[mouth] = 1 if KindSymbolScript.hidden_until_opened(kind) else 0
		_shades.append(KindSymbolScript.shades_of(kind))
		var area: Rect2i = mouths.area_of(mouth)
		var middle: Vector2 = Rect2(area).get_center()
		_middle[mouth] = middle
		_walkway[mouth] = grid.place_at(middle) if grid != null else RoomGrid.NO_PLACE
		_at[mouth] = corner_beside(area, grid.place_rect(room) if grid != null else Rect2())
		var type: RewardType = pieces.type_of(room) if pieces != null and kind != null else null
		var glyphs: Array[PackedByteArray] = []
		var glyph_shades: Array[PackedColorArray] = []
		var element: Resource = pieces.content(RewardGlyphsScript.card_folder(), type.element) if type != null else null
		RewardGlyphsScript.glyphs_of(type, element, glyphs, glyph_shades)
		_glyph_pixels.append(glyphs)
		_glyph_shades.append(glyph_shades)
		var across: bool = area.size.x > area.size.y
		_glyph_across[mouth] = 1 if across else 0
		_glyph_at[mouth] = glyphs_beside(_at[mouth], across)
	_see(table, seats_here, grid)
	for mouth in found:
		_rows[mouth] = _wanted(mouth)
		_done[mouth] = _done_wanted(mouth)
	for light in _lights:
		if light != null:
			light.queue_free()
	_lights.clear()
	_lights.resize(found)
	for mouth in found:
		_light(mouth)
	queue_redraw()


## The light spot on mouth `mouth`'s sign made again in its kind's light, as bright as the share of
## its rows shown (none when it tells nothing or shows no row), so a sign rising or sinking
## brightens or dims its light by its rows (Smooth), and dimmed toward DONE_LIGHT by its done
## look's stage. Made only as a world is read or a sign moves, never in a still frame.
func _light(mouth: int) -> void:
	if _lights[mouth] != null:
		_lights[mouth].queue_free()
		_lights[mouth] = null
	if _pixels[mouth].is_empty() or _rows[mouth] <= 0:
		return
	var light := Marker2D.new()
	light.name = "SignLight%d" % mouth
	light.position = _at[mouth] + Vector2.ONE * (RoomKind.SYMBOL_SIDE * SCALE * 0.5)
	LightSpot.mark(light, LIGHT_REACH, light_strength(_rows[mouth], _done[mouth]), 0.0, _shades[mouth][1])
	_lights[mouth] = light
	add_child(light)


## A sign's light's strength with `rows` of its rows shown and its done look at stage `done`.
static func light_strength(rows: int, done: int) -> float:
	var dim: float = lerpf(1.0, DONE_LIGHT, float(done) / float(KindSymbolScript.DONE_STAGES))
	return LIGHT_STRENGTH * dim * float(rows) / float(RoomKind.SYMBOL_SIDE)


## The light spot on mouth `mouth`'s sign (null: none; for tests).
func light_of(mouth: int) -> Marker2D:
	return _lights[mouth] if mouth >= 0 and mouth < _lights.size() else null


## The corner of a symbol's box beside a mouth of area `area` into a room of rect `room`: on the far
## side of the mouth from the room's middle (the bridge's), GAP from its edge and from the room's,
## centred along it, in whole pixels.
static func corner_beside(area: Rect2i, room: Rect2) -> Vector2:
	var side: int = RoomKind.SYMBOL_SIDE * SCALE
	var middle: Vector2i = area.position + area.size / 2
	var towards: Vector2 = room.get_center() - Vector2(middle) if room.has_area() else Vector2.DOWN
	# Clear of the room's own rectangle too (its dark covers it whole until it is entered).
	var near: Rect2i = area.merge(Rect2i(room)) if room.has_area() else area
	if area.size.x > area.size.y:
		var x: int = middle.x - side / 2
		return Vector2(x, near.position.y - GAP - side) if towards.y > 0.0 else Vector2(x, near.end.y + GAP)
	var y: int = middle.y - side / 2
	return Vector2(near.position.x - GAP - side, y) if towards.x > 0.0 else Vector2(near.end.x + GAP, y)


## The corner of a reward type's first glyph beside a symbol whose box's corner is `symbol`: on its
## right, feet level with its foot, for a mouth across the bridge's way (`across`); else under it,
## centred.
static func glyphs_beside(symbol: Vector2, across: bool) -> Vector2:
	var side: int = RoomKind.SYMBOL_SIDE * SCALE
	var glyph: int = RewardGlyphsScript.SIDE * SCALE
	var gap: int = RewardGlyphsScript.GAP * SCALE
	if across:
		return symbol + Vector2(side + gap, side - glyph)
	return symbol + Vector2((side - glyph) / 2, side + gap)


func _draw() -> void:
	for mouth in _rows.size():
		if _rows[mouth] > 0:
			KindSymbolScript.draw(self, _pixels[mouth], _shades[mouth], _at[mouth], _rows[mouth], SCALE, RoomKind.SYMBOL_SIDE, _done[mouth])
			# Each a typed array as made in `_read` (nothing allocated here).
			RewardGlyphsScript.draw(self, _glyph_pixels[mouth], _glyph_shades[mouth], _glyph_at[mouth], _glyph_across[mouth] != 0, _rows[mouth], SCALE)
