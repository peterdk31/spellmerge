extends Node2D
## A biome's key doors and secret rocks as the view draws them (connected biomes CB12, decision 30;
## CB11 builds the doors and the rock and sends their events). It shows what the bus says
## (`key_door_shown`, `secret_rock_shown`) and the elements touching the floor (`floor_touched`), and
## nothing else; nothing in the game reads it.
##
## **A key door:** stone bars across its mouth with a brass padlock hung on them. Opened, the padlock
## turns (its shackle springs up, then it tilts: TURN_FRAMES), falls (FALL_FRAMES, dropping faster,
## smaller as it goes), then the bars sink into the floor (BAR_FRAMES): one chain of stages, each
## ending where the next begins.
##
## **A secret rock:** cracks across it in its element's tint (`ElementBase.tint`, the card's), dim
## until its element touches the floor within NEAR pixels of it (a blast, a pool, a shot ending:
## `floor_touched`), when they brighten a shade a frame up to the brightest, held NEAR_SECONDS after
## the last touch and then dimming again. Broken, it breaks in stages: its cracks spread and flash
## (frames 1 and 2), then its chunks are thrown apart, shrinking (BREAK_FRAMES in all).
##
## **Smooth** (docs/STYLE.md): every change steps by whole pixels at FPS. After a restore (-1 told
## with `open` or `broken` true) what is told next is drawn as it stands, never played in again.
## A child of Feel, top level (world space); it steps itself while something moves.

const EventsScript := preload("res://core/events/events.gd")

## Over the floor and the doors' bars (the gather doors' 2), under the labels.
const Z: int = 3
## Frames a second the changes step at.
const FPS: float = 12.0
## A key door's stages: the padlock turning, falling, then the bars sinking.
const TURN_FRAMES: int = 3
const FALL_FRAMES: int = 4
const BAR_FRAMES: int = 6
const DOOR_FRAMES: int = TURN_FRAMES + FALL_FRAMES + BAR_FRAMES
## How far the padlock has fallen at each of its falling frames (pixels), and its size then.
const FALL_DROP: PackedInt32Array = [2, 5, 9, 14]
const FALL_SIDE: PackedInt32Array = [7, 6, 4, 2]
## The padlock's body (pixels) and its shackle.
const LOCK_W: int = 7
const LOCK_H: int = 6
const SHACKLE_W: int = 5
const SHACKLE_H: int = 4
## A bar's width and the gap between two (as the gather doors').
const BAR: int = 2
const BAR_GAP: int = 4
## A rock's crack shades (0 out ... GLOW_MOST brightest; 1 dim, at rest), how near its element must
## touch (pixels past the touch's own radius), and how long it stays bright after.
const GLOW_MOST: int = 3
const GLOW_REST: int = 1
const NEAR: float = 96.0
const NEAR_SECONDS: float = 1.0
## A rock's breaking: its frames, the cracks spreading until SPREAD_FRAMES, then the chunks.
const BREAK_FRAMES: int = 6
const SPREAD_FRAMES: int = 2
## How many cracks a rock has, how many more as it breaks, and its chunks.
const CRACKS: int = 3
const CRACKS_SPREAD: int = 3
const CHUNKS: int = 6
## Where the elements are (their tints).
const SPELLS_FOLDER: StringName = &"spells"

## The registry the elements are read from (Feel's; null in a test: the spark's tint).
var registry: Node = null
## The colours: the bars' stone, the padlock's brass (spark) and its shackle's iron (stone).
var bar_colours: PackedColorArray = Palette.shades_of(&"stone")
var brass: PackedColorArray = Palette.shades_of(&"spark")

## Key doors by number: area, told open, the frame drawn (0 shut ... DOOR_FRAMES gone).
var _door_areas: Array[Rect2i] = []
var _door_open: PackedByteArray = PackedByteArray()
var _door_frame: PackedInt32Array = PackedInt32Array()
## Secret rocks by number: area, element, its tint's shades, broken, glow, break frame, bright until
## (its clock), its cracks' pixels (`_crack_from`, `_crack_count`, the first `_crack_rest` of them at
## rest, the rest spreading).
var _rock_areas: Array[Rect2i] = []
var _rock_elements: Array[StringName] = []
var _rock_tints: Array[PackedColorArray] = []
var _rock_broken: PackedByteArray = PackedByteArray()
var _rock_glow: PackedInt32Array = PackedInt32Array()
var _rock_frame: PackedInt32Array = PackedInt32Array()
var _rock_near_until: PackedFloat64Array = PackedFloat64Array()
var _cracks: Array[PackedVector2Array] = []
var _crack_rest: PackedInt32Array = PackedInt32Array()
## After a restore's forgetting, what is told next is drawn as it stands.
var _doors_as_they_stand: bool = false
var _rocks_as_they_stand: bool = false
var _clock: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	top_level = true
	z_index = Z


func bind(events: EventsScript) -> void:
	if events != null:
		events.key_door_shown.connect(_on_key_door_shown)
		events.secret_rock_shown.connect(_on_secret_rock_shown)
		events.floor_touched.connect(_on_floor_touched)


## How many key doors and rocks are drawn, and their frames and glow (for tests).
func doors() -> int:
	return _door_areas.size()


func door_frame_of(door: int) -> int:
	return _door_frame[door] if door >= 0 and door < _door_frame.size() else -1


func rocks() -> int:
	return _rock_areas.size()


func rock_glow_of(rock: int) -> int:
	return _rock_glow[rock] if rock >= 0 and rock < _rock_glow.size() else -1


func rock_frame_of(rock: int) -> int:
	return _rock_frame[rock] if rock >= 0 and rock < _rock_frame.size() else -1


## The tint's shades rock `rock` is drawn in (shadow, base, light).
func rock_tint_of(rock: int) -> PackedColorArray:
	return _rock_tints[rock] if rock >= 0 and rock < _rock_tints.size() else PackedColorArray()


## True while something still moves toward what it was told.
func is_moving() -> bool:
	for door in _door_areas.size():
		if _door_frame[door] != _door_wanted(door):
			return true
	for rock in _rock_areas.size():
		if _rock_frame[rock] != _rock_frame_wanted(rock) or _rock_glow[rock] != _glow_wanted(rock):
			return true
	return false


## One step of every change (a frame at FPS).
func advance() -> void:
	for door in _door_areas.size():
		_door_frame[door] += signi(_door_wanted(door) - _door_frame[door])
	for rock in _rock_areas.size():
		_rock_frame[rock] += signi(_rock_frame_wanted(rock) - _rock_frame[rock])
		_rock_glow[rock] += signi(_glow_wanted(rock) - _rock_glow[rock])
	queue_redraw()


func _process(delta: float) -> void:
	# A restore tells everything within the frame it happens in; what comes after is played.
	_doors_as_they_stand = false
	_rocks_as_they_stand = false
	_time += delta
	if not is_moving():
		_clock = 0.0
		return
	_clock += delta
	var step: float = 1.0 / FPS
	while _clock >= step:
		_clock -= step
		advance()


## Its own clock on by `seconds` (tests, which step it by hand with `advance`).
func pass_time(seconds: float) -> void:
	_time += seconds


func _on_key_door_shown(door: int, area: Rect2, open: bool) -> void:
	if door < 0:
		_door_areas.clear()
		_door_open.resize(0)
		_door_frame.resize(0)
		_doors_as_they_stand = open
		queue_redraw()
		return
	var fresh: bool = door >= _door_areas.size()
	while _door_areas.size() <= door:
		_door_areas.append(Rect2i())
		_door_open.append(0)
		_door_frame.append(0)
	_door_areas[door] = Rect2i(Vector2i(area.position.round()), Vector2i(area.size.round()))
	_door_open[door] = 1 if open else 0
	if _doors_as_they_stand or (fresh and open):
		_door_frame[door] = _door_wanted(door)
	queue_redraw()


func _on_secret_rock_shown(rock: int, area: Rect2, element: StringName, broken: bool) -> void:
	if rock < 0:
		_rock_areas.clear()
		_rock_elements.clear()
		_rock_tints.clear()
		_rock_broken.resize(0)
		_rock_glow.resize(0)
		_rock_frame.resize(0)
		_rock_near_until.resize(0)
		_cracks.clear()
		_crack_rest.resize(0)
		_rocks_as_they_stand = broken
		queue_redraw()
		return
	var fresh: bool = rock >= _rock_areas.size()
	while _rock_areas.size() <= rock:
		_rock_areas.append(Rect2i())
		_rock_elements.append(&"")
		_rock_tints.append(PackedColorArray())
		_rock_broken.append(0)
		_rock_glow.append(GLOW_REST)
		_rock_frame.append(0)
		_rock_near_until.append(-INF)
		_cracks.append(PackedVector2Array())
		_crack_rest.append(0)
	var whole := Rect2i(Vector2i(area.position.round()), Vector2i(area.size.round()))
	if whole != _rock_areas[rock] or _cracks[rock].is_empty():
		_rock_areas[rock] = whole
		_lay_cracks(rock)
	if element != _rock_elements[rock] or _rock_tints[rock].is_empty():
		_rock_elements[rock] = element
		_rock_tints[rock] = _tint_of(element)
	_rock_broken[rock] = 1 if broken else 0
	if _rocks_as_they_stand or (fresh and broken):
		_rock_frame[rock] = _rock_frame_wanted(rock)
		_rock_glow[rock] = _glow_wanted(rock)
	queue_redraw()


## An element touched the floor: each unbroken rock of that element within NEAR of it brightens.
func _on_floor_touched(_caster: int, element: StringName, at: Vector2, radius: float) -> void:
	for rock in _rock_areas.size():
		if _rock_broken[rock] != 0 or _rock_elements[rock] != element:
			continue
		var area := Rect2(_rock_areas[rock])
		var nearest: Vector2 = at.clamp(area.position, area.end)
		if nearest.distance_to(at) <= NEAR + radius:
			_rock_near_until[rock] = _time + NEAR_SECONDS


func _door_wanted(door: int) -> int:
	return DOOR_FRAMES if _door_open[door] != 0 else 0


func _rock_frame_wanted(rock: int) -> int:
	return BREAK_FRAMES if _rock_broken[rock] != 0 else 0


func _glow_wanted(rock: int) -> int:
	if _rock_broken[rock] != 0:
		return 0
	return GLOW_MOST if _time < _rock_near_until[rock] else GLOW_REST


## The shades of the element `element`'s tint (shadow, base, light), the spark's for none.
func _tint_of(element: StringName) -> PackedColorArray:
	var card: ElementBase = registry.call(&"get_resource", SPELLS_FOLDER, element) as ElementBase if registry != null and element != &"" else null
	if card == null:
		return Palette.shades_of(&"spark")
	var tint: Color = card.tint
	return PackedColorArray([tint.darkened(0.5), tint, tint.lightened(0.45)])


## Rock `rock`'s cracks: CRACKS at rest and CRACKS_SPREAD more as it breaks, each a walk of whole
## pixels from a point on its edge toward its middle, the same for the same area.
func _lay_cracks(rock: int) -> void:
	var area: Rect2i = _rock_areas[rock]
	var pixels := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(area)
	var rest: int = 0
	for crack in CRACKS + CRACKS_SPREAD:
		if crack == CRACKS:
			rest = pixels.size()
		var side: int = rng.randi_range(0, 3)
		var at := Vector2i(rng.randi_range(area.position.x, area.end.x - 1), rng.randi_range(area.position.y, area.end.y - 1))
		match side:
			0:
				at.y = area.position.y
			1:
				at.x = area.end.x - 1
			2:
				at.y = area.end.y - 1
			_:
				at.x = area.position.x
		var middle := Vector2i(Rect2(area).get_center())
		var steps: int = maxi(mini(area.size.x, area.size.y) / 2, 4)
		for i in steps:
			pixels.append(Vector2(at))
			var toward: Vector2i = (middle - at).sign()
			# A step toward the middle, now and then aside: a crack's jagged walk.
			if rng.randf() < 0.35:
				toward = Vector2i(toward.y, -toward.x) if rng.randf() < 0.5 else Vector2i(-toward.y, toward.x)
			at = (at + toward).clamp(area.position, area.end - Vector2i.ONE)
	_cracks[rock] = pixels
	_crack_rest[rock] = rest


func _draw() -> void:
	for door in _door_areas.size():
		_draw_key_door(door)
	for rock in _rock_areas.size():
		_draw_rock(rock)


func _draw_key_door(door: int) -> void:
	var area: Rect2i = _door_areas[door]
	var frame: int = _door_frame[door]
	if frame >= DOOR_FRAMES:
		return
	# The bars: up until the padlock is gone, then sinking.
	var sunk: int = maxi(frame - TURN_FRAMES - FALL_FRAMES, 0)
	_draw_bars(area, sunk)
	if frame >= TURN_FRAMES + FALL_FRAMES:
		return
	var middle := Vector2i(Rect2(area).get_center())
	var lift: int = mini(frame, 2)
	var width: int = LOCK_W
	var height: int = LOCK_H
	var drop: int = 0
	if frame == TURN_FRAMES:
		# Tilted: seen edge-on, narrower.
		width = LOCK_W - 2
	elif frame > TURN_FRAMES:
		var fall: int = frame - TURN_FRAMES - 1
		drop = FALL_DROP[fall]
		width = FALL_SIDE[fall]
		height = maxi(FALL_SIDE[fall] - 1, 1)
		lift = 2
	var body := Rect2i(middle.x - width / 2, middle.y - height / 2 + drop, width, height)
	# The shackle: an iron arch over the body, sprung up by `lift` as the key turns.
	if width >= SHACKLE_W:
		var shackle := Rect2i(middle.x - SHACKLE_W / 2, body.position.y - SHACKLE_H - lift + 1, SHACKLE_W, SHACKLE_H + lift)
		draw_rect(Rect2(shackle), Palette.OUTLINE)
		draw_rect(Rect2(shackle.grow(-1)), bar_colours[2])
		draw_rect(Rect2(Rect2i(shackle.position.x + 2, shackle.position.y + 2, SHACKLE_W - 4, shackle.size.y - 2)), Palette.OUTLINE)
	draw_rect(Rect2(body), Palette.OUTLINE)
	if width > 2 and height > 2:
		var inside: Rect2i = body.grow(-1)
		draw_rect(Rect2(inside), brass[1])
		draw_rect(Rect2(Rect2i(inside.position, Vector2i(inside.size.x, 1))), brass[2])
		draw_rect(Rect2(Rect2i(inside.position, Vector2i(1, inside.size.y))), brass[2])
		if width >= LOCK_W - 2:
			draw_rect(Rect2(Rect2i(middle.x, body.position.y + 2 + 0, 1, 2)), Palette.OUTLINE)


## A door's stone bars across its mouth, `sunk` of BAR_FRAMES into the floor.
func _draw_bars(area: Rect2i, sunk: int) -> void:
	var wide: bool = area.size.x >= area.size.y
	var length: int = area.size.y if wide else area.size.x
	var left: int = length - (length * sunk) / BAR_FRAMES
	if left <= 0:
		return
	var across: int = area.size.x if wide else area.size.y
	var at: int = BAR_GAP / 2
	while at + BAR <= across:
		var bar: Rect2i
		if wide:
			bar = Rect2i(area.position.x + at, area.position.y + length - left, BAR, left)
		else:
			bar = Rect2i(area.position.x + length - left, area.position.y + at, left, BAR)
		draw_rect(Rect2(bar), bar_colours[1])
		draw_rect(Rect2(Rect2i(bar.position, Vector2i(1, bar.size.y) if wide else Vector2i(bar.size.x, 1))), bar_colours[2])
		at += BAR + BAR_GAP


func _draw_rock(rock: int) -> void:
	var frame: int = _rock_frame[rock]
	if frame >= BREAK_FRAMES:
		return
	var tints: PackedColorArray = _rock_tints[rock]
	var pixels: PackedVector2Array = _cracks[rock]
	if frame <= SPREAD_FRAMES:
		# At rest its first cracks in its glow's shade; breaking, the rest spread out and flash.
		var shown: int = _crack_rest[rock] + ((pixels.size() - _crack_rest[rock]) * frame) / SPREAD_FRAMES
		var glow: int = _rock_glow[rock]
		var colour: Color = Palette.WHITE_HOT if frame == SPREAD_FRAMES else (tints[glow - 1] if glow > 0 else Palette.OUTLINE)
		for i in shown:
			draw_rect(Rect2(pixels[i], Vector2.ONE), colour if frame > 0 or glow > 0 else Palette.OUTLINE)
		return
	# Thrown apart: chunks of its stone flying out from its middle, shrinking each frame.
	var area: Rect2i = _rock_areas[rock]
	var middle := Vector2i(Rect2(area).get_center())
	var out: int = frame - SPREAD_FRAMES
	var side: int = maxi(4 - out, 1)
	for chunk in CHUNKS:
		var way := Vector2(DMath.cos(TAU * chunk / CHUNKS), DMath.sin(TAU * chunk / CHUNKS))
		var radius: float = float(mini(area.size.x, area.size.y)) * 0.25 + float(out * 4)
		var at: Vector2i = middle + Vector2i((way * radius).round())
		draw_rect(Rect2(Rect2i(at - Vector2i(side / 2, side / 2), Vector2i(side, side))), bar_colours[1])
		if side > 1:
			draw_rect(Rect2(Rect2i(at - Vector2i(side / 2, side / 2), Vector2i(side, 1))), bar_colours[2])
		draw_rect(Rect2(Rect2i(at + Vector2i(0, side - side / 2), Vector2i(1, 1))), tints[0])
