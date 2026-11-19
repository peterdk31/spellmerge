extends Node2D
## The dark over a biome's rooms nobody has been in yet (connected biomes CB12, decision 30:
## "Unvisited rooms in a view are dark by a whole-pixel dither, lightening in stages"). View only:
## nothing in the game reads it.
##
## A room (not a walkway) is visited once it is entered (`room_entered`, its number) or once any
## wizard stands in its place (a machine that joined after the room was entered, whose restore sent
## no `room_entered`; CB9's seen rooms, when they are state, can say it instead). An unvisited room's
## place is drawn over with the void's dark through a 4×4 ordered dither (`DITHER`), DARK_STAGES of
## its sixteen pixels dark; once visited it lightens a stage a frame at FPS (DARK_STAGES frames),
## by whole pixels, never a fade. The dither is a tiled texture a stage, made once; it lines up with
## the world's pixels, as every place stands on the 32 px grid.
##
## A child of Feel, top level (world space), over the bodies (what stands in a dark room is dark too)
## and under the screen's layers. Feel steps it once a frame (`step`).

const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const RoomHearingScript := preload("res://gameplay/feel/room_hearing.gd")

## Over the bodies and the world's looks, under the labels (22) and the screen's layers.
const Z: int = 20
## Frames a second it lightens at.
const FPS: float = 12.0
## How dark an unvisited room is, as dark pixels of 16 a stage, from lit (0) to unvisited (the last).
const DARK_STAGES: PackedInt32Array = [0, 3, 7, 11, 14]
## The 4×4 ordered dither: a pixel is dark at a stage when its number is below the stage's count.
const DITHER: PackedInt32Array = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
const DITHER_SIDE: int = 4
## The void's dark (the split's divider's).
const DARK := Color(0.05, 0.04, 0.09)

## The pieces (Feel's room hearing: which places are walkways).
var pieces: RoomHearingScript = null

## By place: its rectangle, whether it is a room, the stage drawn (0 lit ... the last), visited.
var _rects: Array[Rect2] = []
var _room: PackedByteArray = PackedByteArray()
var _stage: PackedInt32Array = PackedInt32Array()
var _visited: PackedByteArray = PackedByteArray()
## Rooms entered before the places were read (`room_entered` comes as a biome is laid).
var _entered: PackedInt32Array = PackedInt32Array()
var _textures: Array[ImageTexture] = []
var _laid_places: int = -1
var _laid_world: int = -1
var _clock: float = 0.0


func _ready() -> void:
	top_level = true
	z_index = Z
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for stage in DARK_STAGES.size():
		_textures.append(_dither_texture(DARK_STAGES[stage]))


func bind(events: EventsScript) -> void:
	if events != null:
		events.room_entered.connect(_on_room_entered)


## The dither of `dark` pixels of 16, as a 4×4 texture to tile (null for none).
static func _dither_texture(dark: int) -> ImageTexture:
	if dark <= 0:
		return null
	var image := Image.create(DITHER_SIDE, DITHER_SIDE, false, Image.FORMAT_RGBA8)
	for y in DITHER_SIDE:
		for x in DITHER_SIDE:
			image.set_pixel(x, y, DARK if DITHER[y * DITHER_SIDE + x] < dark else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)


## How many places it knows, and place `place`'s stage (0 lit ... DARK_STAGES.size() - 1; -1: none).
func places() -> int:
	return _rects.size()


func stage_of(place: int) -> int:
	return _stage[place] if place >= 0 and place < _stage.size() else -1


## The dark pixels of 16 drawn over place `place` now.
func dark_of(place: int) -> int:
	var stage: int = stage_of(place)
	return DARK_STAGES[stage] if stage >= 0 else 0


func _on_room_entered(_room_id: StringName, number: int) -> void:
	if number == EventsScript.FIRST_ROOM:
		_entered.resize(0)
		_laid_places = -1
	_entered.append(number)
	if number >= 0 and number < _visited.size():
		_visited[number] = 1


## Once a frame, `delta` real seconds on, from `grid` (null: no places) and the bodies of `table`:
## the places read again for a new biome, the rooms a wizard stands in visited, and each room's dark
## stepped toward what it wants at FPS.
func step(delta: float, table: ActorsScript, grid: RoomGrid) -> void:
	var places: int = grid.places() if grid != null else 0
	if places != _laid_places or _laid_world != _world_now():
		_lay(grid, places)
	if _rects.is_empty():
		return
	if table != null:
		for seat in ActorsScript.SEATS:
			var body := table.node_of(table.home_of_seat(seat)) as Node2D
			if body != null and is_instance_valid(body) and body.is_inside_tree():
				var place: int = grid.place_at(body.global_position)
				if place >= 0 and place < _visited.size():
					_visited[place] = 1
	if not is_moving():
		_clock = 0.0
		return
	_clock += delta
	var change: float = 1.0 / FPS
	while _clock >= change:
		_clock -= change
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
	return 0 if _room[place] == 0 or _visited[place] != 0 else DARK_STAGES.size() - 1


## A new biome's places, every room dark but those entered already (drawn as it stands: a new world
## is never played in).
func _lay(grid: RoomGrid, places: int) -> void:
	_laid_places = places
	_laid_world = _world_now()
	_rects.clear()
	_room.resize(places)
	_stage.resize(places)
	_visited.resize(places)
	_visited.fill(0)
	for number in _entered:
		if number >= 0 and number < places:
			_visited[number] = 1
	for place in places:
		_rects.append(grid.place_rect(place))
		_room[place] = 0 if pieces != null and pieces.is_walkway(place) else 1
		_stage[place] = _wanted(place)
	queue_redraw()


func _draw() -> void:
	for place in _rects.size():
		var texture: ImageTexture = _textures[_stage[place]] if _stage[place] < _textures.size() else null
		if texture != null:
			draw_texture_rect(texture, _rects[place], true)


## The world laid last (Feel's room hearing's count; 0 without it).
func _world_now() -> int:
	return pieces.world() if pieces != null else 0
