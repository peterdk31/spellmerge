extends Node2D
## The dark over a biome's rooms nobody has been in yet (connected biomes CB12, decision 30; the
## owner, 2026-11-19: "unseen rooms are completely covered in darkness"). View only: nothing in the
## game reads it.
##
## A room (not a walkway) is visited once the party's map says it was entered (`rooms_seen`, Flow's
## state, connected biomes CB9: a room shown on the map but never entered stays dark), so a machine
## that joins mid-run (a restore, told `again`) draws the rooms entered before it came lit, as they
## stand, never played in. An unvisited room's place is covered whole in the void's black
## (`VoidBackdrop.COLOUR`): nothing in it shows, so it is one with the void round it. Once visited it
## opens by **shrinking blocks** (docs/STYLE.md, "Smooth"): the place is cut into BLOCK px squares,
## each a black square at its middle that shrinks a stage a frame at FPS (BLOCK_SIDES: 8, 6, 4, 2,
## then none), so the room shows through a widening grid; whole pixels, never a fade or a blur. Fine
## and quick (the owner, 2026-11-20, #883: 16 px blocks at 12 fps read as a hard grid of black lines
## mid-way): 8 px blocks over `reveal_seconds()`, still 3 frames between covered and lit, and never
## more than a stage a drawn frame however slow the frame (a frame under 24 fps opens it slower). A
## stage is a tiled texture made once (the solid stage a plain rectangle); it lines up with the
## world's pixels, as every place stands on the 32 px grid.
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


## The rectangle place `place`'s dark covers whole (the place's while it is unvisited; none else).
func covered_of(place: int) -> Rect2:
	var stage: int = stage_of(place)
	return _rects[place] if stage >= 0 and BLOCK_SIDES[stage] >= BLOCK else Rect2()


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
	if _as_stands:
		_as_stands = false
		for place in _rects.size():
			_stage[place] = _wanted(place)
		queue_redraw()
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


## True while a room's dark still changes.
func is_moving() -> bool:
	for place in _rects.size():
		if _stage[place] != _wanted(place):
			return true
	return false


## One stage of every change (a frame at FPS).
func advance() -> void:
	for place in _rects.size():
		_stage[place] += signi(_wanted(place) - _stage[place])
	queue_redraw()


func _wanted(place: int) -> int:
	var entered: bool = place < _seen.size() and _seen[place] >= ENTERED
	return 0 if _room[place] == 0 or entered else BLOCK_SIDES.size() - 1


## A new biome's places, every room dark but those entered already (drawn as it stands: a new world
## is never played in).
func _lay(grid: RoomGrid, places: int) -> void:
	_laid_places = places
	_laid_world = _world_now()
	_rects.clear()
	_room.resize(places)
	_stage.resize(places)
	for place in places:
		_rects.append(grid.place_rect(place))
		_room[place] = 0 if pieces != null and pieces.is_walkway(place) else 1
		_stage[place] = _wanted(place)
	queue_redraw()


func _draw() -> void:
	for place in _rects.size():
		var stage: int = _stage[place]
		if stage <= 0:
			continue
		if BLOCK_SIDES[stage] >= BLOCK:
			draw_rect(_rects[place], DARK)
			continue
		var texture: ImageTexture = _textures[stage] if stage < _textures.size() else null
		if texture != null:
			draw_texture_rect(texture, _rects[place], true)


## The world laid last (Feel's room hearing's count; 0 without it).
func _world_now() -> int:
	return pieces.world() if pieces != null else 0
