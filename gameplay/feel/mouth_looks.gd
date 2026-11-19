extends Node2D
## A biome's bridge mouths as the view draws them (connected biomes CB12, decision 30): an open
## mouth's shimmer, flaring where a shot stops at it; a seal's bars dropping in over frames, then its
## rune lighting. View only: it reads the grid (the mouth cells, the places, their seals) and hears
## `projectile_impact`; nothing in the game reads it.
##
## **The mouths** are found on the grid once a biome is laid: the mouth cells (`RoomGrid.is_mouth`)
## on each walkway's place (a bridge's ends, where its mouths are laid), each run of them one mouth;
## the room a mouth leads into is the room place it touches. A mouth's light is that room's kind's
## (`RoomKind.light`, a palette material; the spark's by default).
##
## **The shimmer** is a dotted line along the mouth's middle with glints running along it (a loop of
## SHIMMER_FRAMES at SHIMMER_FPS, whole pixels); it shows while the mouth is open: not sealed and not
## shut (a gather or a key door's, `RoomGrid.is_shut_mouth`, whose own look stands there). It goes in
## and out through GLOW_STAGES shades, never at once. **A flare** where a shot stops at a mouth (an
## impact on no body within FLARE_REACH of it): a bright dash along the mouth that grows and shrinks
## through FLARE_STAGES (1, 2, 3, 2, 1), a second impact meanwhile climbing back from where it is.
##
## **A seal** (the room behind it sealed for a fight, `RoomGrid.is_sealed`): its bars drop in from
## above over SEAL_FRAMES, then its rune lights through RUNE_STAGES in the room's light; opening, the
## rune goes out and the bars rise again, the same frames back. Every change steps by whole pixels at
## FPS (docs/STYLE.md, "Smooth").
##
## A child of Feel, top level (world space), over the floor and under the bodies. Feel steps it once
## a frame (`step`); it redraws only while something moves or a mouth shimmers.

const EventsScript := preload("res://core/events/events.gd")
const RoomHearingScript := preload("res://gameplay/feel/room_hearing.gd")

## Over the floor and the cover's marks, under the bodies.
const Z: int = 1
## Frames a second the changes step at, and the shimmer's loop.
const FPS: float = 12.0
const SHIMMER_FPS: float = 8.0
## The shimmer's loop: its frames and how far apart its glints run (pixels).
const SHIMMER_FRAMES: int = 8
const GLINT_EVERY: int = 16
const GLINT: int = 3
## The shimmer's shades in and out (0 none ... GLOW_STAGES all of it).
const GLOW_STAGES: int = 3
## A flare's stages, frame by frame, and how near a mouth an impact must be (pixels).
const FLARE_STAGES: PackedInt32Array = [1, 2, 3, 2, 1]
const FLARE_PEAK: int = 2
const FLARE_REACH: float = 6.0
## The frames a seal's bars drop in over, then its rune's shades.
const SEAL_FRAMES: int = 5
const RUNE_STAGES: int = 3
## A bar's thickness and the gap between two (pixels).
const BAR: int = 2
const BAR_GAP: int = 4
## The rune, 5 by 5 (1: lit).
const RUNE: PackedByteArray = [0, 0, 1, 0, 0, 0, 1, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 1, 0, 0, 0, 1, 0, 0]
const RUNE_SIDE: int = 5
## The light when a room's kind names none.
const DEFAULT_LIGHT: StringName = &"spark"

## The pieces (Feel's room hearing: which places are walkways, each room's kind).
var pieces: RoomHearingScript = null

## The colours of the bars (stone: shadow, base, light).
var bar_colours: PackedColorArray = Palette.shades_of(&"stone")

## By mouth: its area (world pixels, whole cells), the room it leads into, whether it runs across
## (wider than deep), its light's shades; what is drawn now (glow, flare frame or -1, where along it,
## seal step 0 ... SEAL_FRAMES + RUNE_STAGES).
var _areas: Array[Rect2i] = []
var _rooms: PackedInt32Array = PackedInt32Array()
var _wide: PackedByteArray = PackedByteArray()
var _lights: Array[PackedColorArray] = []
var _glow: PackedInt32Array = PackedInt32Array()
var _flare: PackedInt32Array = PackedInt32Array()
var _flare_at: PackedInt32Array = PackedInt32Array()
var _seal: PackedInt32Array = PackedInt32Array()
## What each mouth wants this frame: shimmering (1), sealed (1).
var _open: PackedByteArray = PackedByteArray()
var _sealed: PackedByteArray = PackedByteArray()
## The grid the mouths were found on: its places and the world it was (`RoomHearing.world`).
var _found_places: int = -1
var _found_world: int = -1
## The pieces' versions read last (`RoomHearing.versions`, `relaid`): a room laid again alone (a
## room reroll's) gives its mouths its kind's light anew; nothing else is found again.
var _found_versions: PackedInt32Array = PackedInt32Array()
var _found_relaid: int = -1
var _clock: float = 0.0
var _shimmer_clock: float = 0.0
var _shimmer_frame: int = 0


func _ready() -> void:
	top_level = true
	z_index = Z


func bind(events: EventsScript) -> void:
	if events != null:
		events.projectile_impact.connect(_on_impact)


## How many mouths are drawn (for tests).
func mouths() -> int:
	return _areas.size()


## Mouth `mouth`'s area, the room it leads into, glow, flare stage (0: none), seal step (for tests).
func area_of(mouth: int) -> Rect2i:
	return _areas[mouth] if mouth >= 0 and mouth < _areas.size() else Rect2i()


func room_of(mouth: int) -> int:
	return _rooms[mouth] if mouth >= 0 and mouth < _rooms.size() else -1


func glow_of(mouth: int) -> int:
	return _glow[mouth] if mouth >= 0 and mouth < _glow.size() else -1


func flare_of(mouth: int) -> int:
	if mouth < 0 or mouth >= _flare.size() or _flare[mouth] < 0:
		return 0
	return FLARE_STAGES[_flare[mouth]]


func seal_of(mouth: int) -> int:
	return _seal[mouth] if mouth >= 0 and mouth < _seal.size() else -1


## The mouth whose area holds `at` grown by `reach` pixels (-1: none).
## Grown across the mouth's depth only, so a hit on the bridge's side beside it is not on it.
func mouth_at(at: Vector2, reach: float = 0.0) -> int:
	for mouth in _areas.size():
		var area := Rect2(_areas[mouth])
		area = area.grow_individual(0.0, reach, 0.0, reach) if _wide[mouth] != 0 else area.grow_individual(reach, 0.0, reach, 0.0)
		if area.has_point(at):
			return mouth
	return -1


## Once a frame, `delta` real seconds on, from `grid` (null: no mouths): the mouths found again for a
## new biome, what each wants read, and every change stepped at FPS.
func step(delta: float, grid: RoomGrid) -> void:
	var places: int = grid.places() if grid != null else 0
	if places != _found_places or _found_world != _world_now():
		_find(grid, places)
	elif pieces != null and pieces.relaid() != _found_relaid:
		var changed: PackedInt32Array = pieces.changed_since(_found_versions, places)
		_found_relaid = pieces.relaid()
		_found_versions = pieces.versions()
		for mouth in _areas.size():
			if changed.has(_rooms[mouth]):
				_lights[mouth] = _light_of(_rooms[mouth])
		queue_redraw()
	if _areas.is_empty():
		return
	read(grid)
	_shimmer_clock += delta
	var shimmer_step: float = 1.0 / SHIMMER_FPS
	var shimmering: bool = false
	while _shimmer_clock >= shimmer_step:
		_shimmer_clock -= shimmer_step
		_shimmer_frame = (_shimmer_frame + 1) % SHIMMER_FRAMES
		shimmering = true
	if not is_moving():
		_clock = 0.0
		if shimmering and _any_glow():
			queue_redraw()
		return
	_clock += delta
	var change: float = 1.0 / FPS
	while _clock >= change:
		_clock -= change
		advance()
	if shimmering:
		queue_redraw()


## What each mouth wants from `grid`: open (shimmering) unless sealed or shut, sealed while the room
## behind it is.
func read(grid: RoomGrid) -> void:
	for mouth in _areas.size():
		var middle: Vector2 = Rect2(_areas[mouth]).get_center()
		var shut: bool = grid != null and grid.is_shut_mouth(middle)
		var sealed: bool = grid != null and not shut and grid.is_sealed(_rooms[mouth])
		_sealed[mouth] = 1 if sealed else 0
		_open[mouth] = 0 if shut or sealed else 1


## True while something still moves toward what it wants.
func is_moving() -> bool:
	for mouth in _areas.size():
		if _glow[mouth] != _glow_wanted(mouth) or _seal[mouth] != _seal_wanted(mouth) or _flare[mouth] >= 0:
			return true
	return false


## One step of every change (a frame at FPS).
func advance() -> void:
	for mouth in _areas.size():
		_glow[mouth] += signi(_glow_wanted(mouth) - _glow[mouth])
		_seal[mouth] += signi(_seal_wanted(mouth) - _seal[mouth])
		if _flare[mouth] >= 0:
			_flare[mouth] += 1
			if _flare[mouth] >= FLARE_STAGES.size():
				_flare[mouth] = -1
	queue_redraw()


## A shot stopped at a mouth (an impact on no body there): that mouth flares where it struck, if it
## shimmers.
func _on_impact(_caster: int, target: Node, position: Vector2, _direction: Vector2) -> void:
	if target != null:
		return
	flare(position)


## A flare at `at` on the mouth there (for the impacts and tests); false when no open mouth is there.
func flare(at: Vector2) -> bool:
	var mouth: int = mouth_at(at, FLARE_REACH)
	if mouth < 0 or _glow[mouth] == 0:
		return false
	var area: Rect2i = _areas[mouth]
	if _flare[mouth] < 0:
		_flare[mouth] = 0
		_flare_at[mouth] = clampi(roundi(at.x), area.position.x, area.end.x - 1) if _wide[mouth] != 0 else clampi(roundi(at.y), area.position.y, area.end.y - 1)
	elif _flare[mouth] > FLARE_PEAK:
		# Past its peak: climb back from the stage it is at, one stage at a time.
		var stage: int = FLARE_STAGES[_flare[mouth]]
		_flare[mouth] = clampi(stage, 0, FLARE_PEAK)
	queue_redraw()
	return true


func _glow_wanted(mouth: int) -> int:
	return GLOW_STAGES if _open[mouth] != 0 else 0


func _seal_wanted(mouth: int) -> int:
	return SEAL_FRAMES + RUNE_STAGES if _sealed[mouth] != 0 else 0


func _any_glow() -> bool:
	for glow in _glow:
		if glow > 0:
			return true
	return false


## Every mouth on `grid`'s walkways, found once a biome (none in a world with no places).
func _find(grid: RoomGrid, places: int) -> void:
	_found_places = places
	_found_world = _world_now()
	_found_relaid = pieces.relaid() if pieces != null else 0
	_found_versions = pieces.versions() if pieces != null else PackedInt32Array()
	_areas.clear()
	_rooms.resize(0)
	_wide.resize(0)
	_lights.clear()
	if grid == null or not grid.has_mouths():
		_size_lists()
		return
	for place in places:
		if pieces != null and not pieces.is_walkway(place):
			continue
		_find_in(grid, place, places)
	_size_lists()
	# A world laid (a new biome, a restore's) is drawn as it stands, never played in.
	read(grid)
	for mouth in _areas.size():
		_glow[mouth] = _glow_wanted(mouth)
		_seal[mouth] = _seal_wanted(mouth)
	queue_redraw()


## The mouths on place `place`: each run of mouth cells, by rows of whole cells.
func _find_in(grid: RoomGrid, place: int, places: int) -> void:
	var rect: Rect2 = grid.place_rect(place)
	var cell: float = RoomGrid.WALL_CELL
	var cols: int = ceili(rect.size.x / cell)
	var rows: int = ceili(rect.size.y / cell)
	var taken := PackedByteArray()
	taken.resize(cols * rows)
	for y in rows:
		for x in cols:
			if taken[y * cols + x] != 0 or not grid.is_mouth(rect.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell):
				continue
			# The run: as far right as mouth cells go, then as far down as every cell of it is one.
			var x1: int = x
			while x1 + 1 < cols and taken[y * cols + x1 + 1] == 0 and grid.is_mouth(rect.position + (Vector2(x1 + 1, y) + Vector2(0.5, 0.5)) * cell):
				x1 += 1
			var y1: int = y
			while y1 + 1 < rows and _row_is_mouth(grid, rect, x, x1, y1 + 1, cols, taken):
				y1 += 1
			for ty in range(y, y1 + 1):
				for tx in range(x, x1 + 1):
					taken[ty * cols + tx] = 1
			var area := Rect2i(Vector2i(rect.position + Vector2(x, y) * cell), Vector2i(Vector2(x1 - x + 1, y1 - y + 1) * cell))
			_areas.append(area)
			var room: int = _room_touching(grid, Rect2(area).get_center(), places)
			_rooms.append(room)
			_wide.append(1 if area.size.x > area.size.y else 0)
			_lights.append(_light_of(room))


func _row_is_mouth(grid: RoomGrid, rect: Rect2, x0: int, x1: int, y: int, cols: int, taken: PackedByteArray) -> bool:
	for x in range(x0, x1 + 1):
		if taken[y * cols + x] != 0 or not grid.is_mouth(rect.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * RoomGrid.WALL_CELL):
			return false
	return true


## The room (not a walkway) whose place is within TOUCH of `at` (-1: none).
func _room_touching(grid: RoomGrid, at: Vector2, places: int) -> int:
	for place in places:
		if pieces != null and pieces.is_walkway(place):
			continue
		if grid.place_rect(place).grow(RoomHearingScript.TOUCH).has_point(at):
			return place
	return -1


func _light_of(room: int) -> PackedColorArray:
	var kind: RoomKind = pieces.kind_of(room) if pieces != null else null
	var material: StringName = kind.light if kind != null and kind.light != &"" else DEFAULT_LIGHT
	var shades: PackedColorArray = Palette.shades_of(material)
	return shades if shades.size() == 3 else Palette.shades_of(DEFAULT_LIGHT)


func _size_lists() -> void:
	var n: int = _areas.size()
	_glow.resize(n)
	_glow.fill(0)
	_flare.resize(n)
	_flare.fill(-1)
	_flare_at.resize(n)
	_seal.resize(n)
	_seal.fill(0)
	_open.resize(n)
	_open.fill(0)
	_sealed.resize(n)
	_sealed.fill(0)


func _draw() -> void:
	for mouth in _areas.size():
		if _glow[mouth] > 0:
			_draw_shimmer(mouth)
		if _flare[mouth] >= 0:
			_draw_flare(mouth)
		if _seal[mouth] > 0:
			_draw_seal(mouth)


## The dotted line along the mouth's middle and its glints, in the shades its glow has come to.
func _draw_shimmer(mouth: int) -> void:
	var area: Rect2i = _areas[mouth]
	var wide: bool = _wide[mouth] != 0
	var length: int = area.size.x if wide else area.size.y
	var lights: PackedColorArray = _lights[mouth]
	var glow: int = _glow[mouth]
	var shift: int = _shimmer_frame * GLINT_EVERY / SHIMMER_FRAMES
	for along in range(0, length, 2):
		var glint: int = (along - shift + length * GLINT_EVERY) % GLINT_EVERY
		var colour: Color
		if glint < GLINT and glow >= 2:
			colour = lights[2] if glint == GLINT - 1 and glow >= GLOW_STAGES else lights[1]
		elif along % 4 == 0:
			colour = lights[0]
		else:
			continue
		draw_rect(Rect2(_point(area, wide, along, 0), Vector2.ONE), colour)


## The flare: a dash along the mouth, as long and thick as its stage, its core white-hot at the peak.
func _draw_flare(mouth: int) -> void:
	var area: Rect2i = _areas[mouth]
	var wide: bool = _wide[mouth] != 0
	var stage: int = FLARE_STAGES[_flare[mouth]]
	var lights: PackedColorArray = _lights[mouth]
	var start: int = area.position.x if wide else area.position.y
	var middle: int = _flare_at[mouth] - start
	var length: int = area.size.x if wide else area.size.y
	for across in range(-(stage - 1), stage):
		var half: int = stage * 3 - absi(across) * 2
		for along in range(maxi(middle - half, 0), mini(middle + half + 1, length)):
			var colour: Color = lights[2] if absi(along - middle) < half - 1 else lights[1]
			if stage == FLARE_STAGES[FLARE_PEAK] and across == 0 and absi(along - middle) <= 1:
				colour = Palette.WHITE_HOT
			draw_rect(Rect2(_point(area, wide, along, across), Vector2.ONE), colour)


## The seal's bars, dropped in from above by its step, then its rune in the room's light.
func _draw_seal(mouth: int) -> void:
	var area: Rect2i = _areas[mouth]
	var wide: bool = _wide[mouth] != 0
	var bars: int = mini(_seal[mouth], SEAL_FRAMES)
	if wide:
		# A mouth across the screen: bars standing up its depth, growing down from its top edge.
		var down: int = (area.size.y * bars) / SEAL_FRAMES
		var at: int = BAR_GAP / 2
		while at + BAR <= area.size.x:
			var bar := Rect2i(area.position.x + at, area.position.y, BAR, down)
			draw_rect(Rect2(bar), bar_colours[1])
			draw_rect(Rect2(Rect2i(bar.position, Vector2i(1, bar.size.y))), bar_colours[2])
			at += BAR + BAR_GAP
	else:
		# A mouth up the screen: a portcullis of bars across its depth, slid down from above.
		var lowered: int = area.size.y - (area.size.y * bars) / SEAL_FRAMES
		var at: int = BAR_GAP / 2
		while at + BAR <= area.size.y:
			var y: int = at - lowered
			if y >= 0:
				var bar := Rect2i(area.position.x, area.position.y + y, area.size.x, BAR)
				draw_rect(Rect2(bar), bar_colours[1])
				draw_rect(Rect2(Rect2i(bar.position, Vector2i(bar.size.x, 1))), bar_colours[2])
			at += BAR + BAR_GAP
	var rune: int = _seal[mouth] - SEAL_FRAMES
	if rune <= 0:
		return
	var colour: Color = Palette.OUTLINE if rune == 1 else _lights[mouth][rune - 1]
	var corner: Vector2i = Vector2i(Rect2(area).get_center()) - Vector2i(RUNE_SIDE / 2, RUNE_SIDE / 2)
	for y in RUNE_SIDE:
		for x in RUNE_SIDE:
			if RUNE[y * RUNE_SIDE + x] != 0:
				draw_rect(Rect2(corner + Vector2i(x, y), Vector2i.ONE), colour)


## The pixel `along` the mouth's long side and `across` its middle line.
static func _point(area: Rect2i, wide: bool, along: int, across: int) -> Vector2:
	if wide:
		return Vector2(area.position.x + along, area.position.y + area.size.y / 2 + across)
	return Vector2(area.position.x + area.size.x / 2 + across, area.position.y + along)


## The world laid last (Feel's room hearing's count; 0 without it).
func _world_now() -> int:
	return pieces.world() if pieces != null else 0
