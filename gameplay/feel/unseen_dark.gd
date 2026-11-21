extends Node2D
## The dark over a biome's rooms nobody has been in yet (connected biomes CB12, decision 30; the
## owner, 2026-11-19: "unseen rooms are completely covered in darkness"). View only: nothing in the
## game reads it.
##
## A room (not a walkway) is visited once the party's map says it was entered (`rooms_seen`, Flow's
## state, connected biomes CB9: a room shown on the map but never entered stays dark), so a machine
## that joins mid-run (a restore, told `again`) draws the rooms entered before it came lit, as they
## stand, never played in. An unvisited room's place is covered whole in the void's black
## (`VoidBackdrop.COLOUR`): nothing in it shows, so it is one with the void round it, and the void's
## motes drift over it as over the void (the owner, 2026-11-21: an unseen room looks like the
## background, its motes drifting about): what it covers whole is told to the spectacle
## (`void_covers`), which gives the void's motes off there too and draws them over it. Once visited it
## opens by **shrinking blocks** (docs/STYLE.md, "Smooth"): the place is cut into BLOCK px squares,
## each a black square at its middle that shrinks a stage a frame at FPS (BLOCK_SIDES: 8, 6, 4, 2,
## then none), so the room shows through a widening grid; whole pixels, never a fade or a blur. Fine
## and quick (the owner, 2026-11-20, #883: 16 px blocks at 12 fps read as a hard grid of black lines
## mid-way): 8 px blocks over `reveal_seconds()`, still 3 frames between covered and lit, and never
## more than a stage a drawn frame however slow the frame (a frame under 24 fps opens it slower). A
## stage is a tiled texture made once (the solid stage a plain rectangle); it lines up with the
## world's pixels, as every place stands on the 32 px grid.
##
## **A secret room's bridge** (the owner, 2026-11-20: "the bridge to a secret room is hidden until the
## secret is found"): a bridge with a secret room at an end (its kind's door `secret`,
## `KindSymbol.hidden_until_opened`) that is not opened yet (Feel's room hearing, `is_opened`: Flow's
## `rooms_opened`) is covered whole in the same black, so it is pure void and the doorway it leaves
## from is the room's lip (its rock stands there, `LockDoors`). Found, it **builds** out from the room
## it hangs off (`build_of`): its BLOCK px cells in bands BAND px deep by their distance from that
## room, each band shrinking through BLOCK_SIDES a frame after the band before it, so the causeway
## lays itself toward the secret room a band a frame (3 frames and more between covered and shown for
## every pixel, whole pixels); then the room opens as any room, once entered. A restore or a new
## world draws it as it stands.
##
## A child of Feel, top level (world space), over the bodies (what stands in a dark room is dark too)
## and under the screen's layers. Feel steps it once a frame (`step`).

const EventsScript := preload("res://core/events/events.gd")
const RoomHearingScript := preload("res://gameplay/feel/room_hearing.gd")
const VoidBackdropScript := preload("res://gameplay/feel/void_backdrop.gd")

## Over the bodies and the world's looks, under the labels (22) and the screen's layers.
const Z: int = 20
## Frames a second it lightens at.
const FPS: float = 24.0
## The side of the blocks a room's dark opens by (pixels; a whole number of them on the 32 px grid).
const BLOCK: int = 8
## Each stage's black square at a block's middle, from lit (0) to unvisited (the last: BLOCK, solid).
const BLOCK_SIDES: PackedInt32Array = [0, 2, 4, 6, 8]
## How deep a band of a secret room's bridge builds in at a time (pixels from the room it leaves).
const BAND: float = 32.0
## A bridge's build when hidden (none of it shown).
const HIDDEN: int = -1
## How far out of the room it leaves a hidden bridge's dark begins (pixels past the socket: the
## room's lip there is held within it, `PieceShape.LANDING`).
const LANDING: float = PieceShape.LANDING

## A room's level in `rooms_seen` once it was entered (0 unseen, 1 only shown on the map).
const ENTERED: int = 2
## The dark: the void's black.
const DARK: Color = VoidBackdropScript.COLOUR

## The pieces (Feel's room hearing: which places are walkways).
var pieces: RoomHearingScript = null

## By place: its rectangle, whether it is a room, the stage drawn (0 lit ... the last).
var _rects: Array[Rect2] = []
var _room: PackedByteArray = PackedByteArray()
var _stage: PackedInt32Array = PackedInt32Array()
## The party's map as told last (`rooms_seen`: by room number, which is its place's), and whether it
## was told again after a restore (drawn as it stands at the next step).
var _seen: PackedByteArray = PackedByteArray()
var _as_stands: bool = false
var _textures: Array[ImageTexture] = []
## By place (bridges only; -1 elsewhere): the room its secret room is (-1: none), what its dark
## covers (`_covers`: the bridge's rectangle short of the room it leaves), its build (HIDDEN, or
## frames since it was found, up to `_built_at`) and its cells' bands.
var _secret_of: PackedInt32Array = PackedInt32Array()
var _covers: Array[Rect2] = []
var _build: PackedInt32Array = PackedInt32Array()
var _built_at: PackedInt32Array = PackedInt32Array()
var _bands: Array[PackedInt32Array] = []
## The room hearing's `done_again` read last (a restore: drawn as it stands).
var _read_again: int = 0
## What it covers whole now, one rectangle a place (`void_covers`): the void shows there, so the
## void's motes are given off and drawn over them too (the owner, 2026-11-21). The one array, kept and
## written again only when a stage changes.
var _void_rects: Array[Rect2] = []
var _laid_places: int = -1
var _laid_world: int = -1
var _clock: float = 0.0


func _ready() -> void:
	top_level = true
	z_index = Z
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for stage in BLOCK_SIDES.size():
		_textures.append(block_texture(BLOCK_SIDES[stage]))


## How long a room's dark takes to open, from covered to lit (seconds): a stage a frame at FPS.
static func reveal_seconds() -> float:
	return float(BLOCK_SIDES.size() - 1) / FPS


func bind(events: EventsScript) -> void:
	if events != null:
		events.rooms_seen.connect(_on_rooms_seen)


## A BLOCK × BLOCK texture to tile, a black square of side `side` at its middle (null for none, and
## for a solid block: that stage is drawn as a plain rectangle).
static func block_texture(side: int) -> ImageTexture:
	if side <= 0 or side >= BLOCK:
		return null
	var image := Image.create(BLOCK, BLOCK, false, Image.FORMAT_RGBA8)
	var low: int = (BLOCK - side) / 2
	for y in BLOCK:
		for x in BLOCK:
			var inside: bool = x >= low and x < low + side and y >= low and y < low + side
			image.set_pixel(x, y, DARK if inside else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)


## How many places it knows, and place `place`'s stage (0 lit ... BLOCK_SIDES.size() - 1; -1: none).
func places() -> int:
	return _rects.size()


func stage_of(place: int) -> int:
	return _stage[place] if place >= 0 and place < _stage.size() else -1


## The dark pixels of a block's BLOCK × BLOCK drawn over place `place` now (BLOCK × BLOCK: covered).
func dark_of(place: int) -> int:
	var stage: int = stage_of(place)
	return BLOCK_SIDES[stage] * BLOCK_SIDES[stage] if stage >= 0 else 0


## The rectangle place `place`'s dark covers whole (the place's while it is unvisited, or a secret
## room's bridge while hidden; none else).
func covered_of(place: int) -> Rect2:
	var stage: int = stage_of(place)
	if stage >= 0 and BLOCK_SIDES[stage] >= BLOCK:
		return _rects[place]
	return _covers[place] if build_of(place) == HIDDEN else Rect2()


## Bridge `place`'s build (a secret room's bridge: HIDDEN, or frames since found, `built_at` once
## whole); 0 for any other place.
func build_of(place: int) -> int:
	return _build[place] if place >= 0 and place < _build.size() else 0


## The build at which secret room bridge `place` is whole (0 for any other place).
func built_at(place: int) -> int:
	return _built_at[place] if place >= 0 and place < _built_at.size() else 0


## The dark stage of the cell of bridge `place` at world point `at` now (0 shown ... the last).
func cell_stage_at(place: int, at: Vector2) -> int:
	if place < 0 or place >= _rects.size() or _secret_of[place] < 0:
		return 0
	var cover: Rect2 = _covers[place]
	if not cover.has_point(at):
		return 0
	var cell: Vector2i = Vector2i(((at - cover.position) / float(BLOCK)).floor())
	var columns: int = ceili(cover.size.x / float(BLOCK))
	var bands: PackedInt32Array = _bands[place]
	var index: int = cell.y * columns + cell.x
	return _cell_stage(place, bands[index]) if index >= 0 and index < bands.size() else 0


## A cell of band `band` of bridge `place`: its dark stage at the bridge's build now.
func _cell_stage(place: int, band: int) -> int:
	var last: int = BLOCK_SIDES.size() - 1
	if _build[place] == HIDDEN:
		return last
	return clampi(last - (_build[place] - band), 0, last)


func _on_rooms_seen(seen: PackedByteArray, again: bool) -> void:
	_seen = seen
	_as_stands = _as_stands or again


## Once a frame, `delta` real seconds on, from `grid` (null: no places): the places read again for a
## new biome, and each room's dark stepped toward what the party's map wants at FPS (drawn as it
## stands after a restore).
func step(delta: float, grid: RoomGrid) -> void:
	var places: int = grid.places() if grid != null else 0
	if places != _laid_places or _laid_world != _world_now():
		_lay(grid, places)
	var again: int = pieces.done_again() if pieces != null else 0
	if again != _read_again:
		# Told again after a restore (the rooms opened among them): drawn as it stands.
		_read_again = again
		_as_stands = true
	if _as_stands:
		_as_stands = false
		for place in _rects.size():
			_stage[place] = _wanted(place)
			_build[place] = _build_wanted(place)
		_changed()
	if _rects.is_empty():
		return
	if not is_moving():
		_clock = 0.0
		return
	_clock += delta
	var change: float = 1.0 / FPS
	if _clock >= change:
		# At most a stage a drawn frame: a slow frame never skips one (Smooth's 3 frames between).
		_clock = minf(_clock - change, change)
		advance()


## True while a room's dark still changes, or a secret room's bridge still builds.
func is_moving() -> bool:
	for place in _rects.size():
		if _stage[place] != _wanted(place) or _build[place] != _build_wanted(place):
			return true
	return false


## One stage of every change (a frame at FPS): a bridge found builds a band on, one hidden again (a
## new world's) is covered at once.
func advance() -> void:
	for place in _rects.size():
		_stage[place] += signi(_wanted(place) - _stage[place])
		var wanted: int = _build_wanted(place)
		# Frames since found: the first frame after it is frame 1 (its nearest band a stage in).
		_build[place] = HIDDEN if wanted == HIDDEN else mini(maxi(_build[place], 0) + 1, wanted)
	_changed()


## A secret room's bridge's build wanted: HIDDEN while its room is not opened, else whole.
func _build_wanted(place: int) -> int:
	if _secret_of[place] < 0:
		return 0
	return _built_at[place] if pieces != null and pieces.is_opened(_secret_of[place]) else HIDDEN


func _wanted(place: int) -> int:
	var entered: bool = place < _seen.size() and _seen[place] >= ENTERED
	return 0 if _room[place] == 0 or entered else BLOCK_SIDES.size() - 1


## A new biome's places, every room dark but those entered already (drawn as it stands: a new world
## is never played in).
func _lay(grid: RoomGrid, places: int) -> void:
	_laid_places = places
	_laid_world = _world_now()
	_rects.clear()
	_bands.clear()
	_room.resize(places)
	_stage.resize(places)
	_secret_of.resize(places)
	_secret_of.fill(-1)
	_covers.clear()
	_build.resize(places)
	_built_at.resize(places)
	_built_at.fill(0)
	_read_again = pieces.done_again() if pieces != null else 0
	for place in places:
		_rects.append(grid.place_rect(place))
		_room[place] = 0 if pieces != null and pieces.is_walkway(place) else 1
		_stage[place] = _wanted(place)
	for place in places:
		_bands.append(PackedInt32Array())
		_covers.append(Rect2())
		if _room[place] == 0:
			_lay_secret_bridge(place)
		_build[place] = _build_wanted(place)
	_changed()


## The rectangles the dark covers whole now (each unvisited room's, each hidden secret room's
## bridge's: `covered_of`), where an unseen room is the void itself: the spectacle gives the void's
## motes off over them and draws them over the dark (`Spectacle.void_air`, `void_pool`). The same
## array every call, written again when a stage changes; read only.
func void_covers() -> Array[Rect2]:
	return _void_rects


## A stage changed: drawn again, and what it covers whole read again.
func _changed() -> void:
	_void_rects.clear()
	for place in _rects.size():
		var covered: Rect2 = covered_of(place)
		if covered.has_area():
			_void_rects.append(covered)
	queue_redraw()


## Bridge `place`, when a secret room stands at an end (its real ends, as Flow put them on its layout:
## the room hearing's `secret_end`): that room, what its dark covers (the bridge's rectangle, its
## edge on the room it leaves pulled back to LANDING px out of that room's socket, so the black never
## bites into that room's slab or lip round the doorway, and the doorway is the room's lip), and each
## BLOCK px cell's band (its distance from that socket, along and across, in BAND steps: a corner
## walkway builds round its turn).
func _lay_secret_bridge(place: int) -> void:
	var secret_end: int = pieces.secret_end(place) if pieces != null else -1
	if secret_end < 0:
		return
	_secret_of[place] = pieces.end_room(place, secret_end)
	var from: int = 1 - secret_end
	var at: Vector2 = pieces.end_at(place, from)
	var cover: Rect2 = _rects[place]
	match pieces.end_facing(place, from):
		RoomSocket.Facing.NORTH:
			cover.end = Vector2(cover.end.x, minf(cover.end.y, at.y - LANDING))
		RoomSocket.Facing.SOUTH:
			cover = Rect2(Vector2(cover.position.x, maxf(cover.position.y, at.y + LANDING)), Vector2(cover.size.x, cover.end.y - maxf(cover.position.y, at.y + LANDING)))
		RoomSocket.Facing.EAST:
			cover = Rect2(Vector2(maxf(cover.position.x, at.x + LANDING), cover.position.y), Vector2(cover.end.x - maxf(cover.position.x, at.x + LANDING), cover.size.y))
		RoomSocket.Facing.WEST:
			cover.end = Vector2(minf(cover.end.x, at.x - LANDING), cover.end.y)
	_covers[place] = cover
	var columns: int = ceili(cover.size.x / float(BLOCK))
	var rows: int = ceili(cover.size.y / float(BLOCK))
	var bands := PackedInt32Array()
	bands.resize(columns * rows)
	var most: int = 0
	for y in rows:
		for x in columns:
			var middle: Vector2 = cover.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * float(BLOCK)
			var band: int = floori((absf(middle.x - at.x) + absf(middle.y - at.y)) / BAND)
			bands[y * columns + x] = band
			most = maxi(most, band)
	_bands[place] = bands
	_built_at[place] = most + BLOCK_SIDES.size() - 1


func _draw() -> void:
	for place in _rects.size():
		if _secret_of[place] >= 0 and _build[place] < _built_at[place]:
			_draw_bridge(place)
			continue
		var stage: int = _stage[place]
		if stage <= 0:
			continue
		if BLOCK_SIDES[stage] >= BLOCK:
			draw_rect(_rects[place], DARK)
			continue
		var texture: ImageTexture = _textures[stage] if stage < _textures.size() else null
		if texture != null:
			draw_texture_rect(texture, _rects[place], true)


## A secret room's bridge: whole while hidden, else cell by cell as it builds.
func _draw_bridge(place: int) -> void:
	var rect: Rect2 = _covers[place]
	if _build[place] == HIDDEN:
		draw_rect(rect, DARK)
		return
	var columns: int = ceili(rect.size.x / float(BLOCK))
	var bands: PackedInt32Array = _bands[place]
	for index in bands.size():
		var stage: int = _cell_stage(place, bands[index])
		if stage <= 0:
			continue
		var cell := Rect2(rect.position + Vector2(index % columns, index / columns) * float(BLOCK), Vector2(BLOCK, BLOCK)).intersection(rect)
		if BLOCK_SIDES[stage] >= BLOCK:
			draw_rect(cell, DARK)
		elif _textures[stage] != null:
			draw_texture_rect(_textures[stage], cell, true)


## The world laid last (Feel's room hearing's count; 0 without it).
func _world_now() -> int:
	return pieces.world() if pieces != null else 0
