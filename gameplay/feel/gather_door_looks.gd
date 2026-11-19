extends Node2D
## A biome's gather doors as the view draws them (connected biomes CB7; the look is CB12's to make,
## so this is the least that reads): a shut door is stone bars across its mouth with a lamp for each
## standing wizard beside it, lit as one arrives; a held gate's lamps glow the fire's red; an opening
## door's bars sink into the floor; the portal home is a ring of void that opens out on its floor,
## with its lamps. It shows what the bus says and nothing else (`gather_door_shown`).
##
## **Smooth** (docs/STYLE.md): every change plays its frames, by whole pixels, at FPS: the bars sink
## over OPEN_FRAMES frames, the portal opens over the same, and a lamp steps through LAMP_STAGES shades
## each way (a lamp past the count shrinks out the same). A gate held or let go turns its lamps from
## the spark's shades to the fire's (or back) through their shared out shade (the outline): down, the
## palette changes there, up again. Nothing fades. After a restore (door -1 told with `open`), what
## is told next is drawn as it stands, never played in again.
##
## A child of Feel, top level (world space). View only: never state, nothing in the game reads it;
## it draws only while something moves (`_process` redraws then).

const EventsScript := preload("res://core/events/events.gd")

## Over the floor, under the labels (the exit signs' 22).
const Z: int = 2
## Frames a second the changes step at.
const FPS: float = 12.0
## The frames an opening door's bars sink over, and the portal opens over.
const OPEN_FRAMES: int = 6
## A lamp's shades from out to lit (0 out ... LAMP_STAGES lit).
const LAMP_STAGES: int = 3
## A bar's width and the gap between two, a lamp's side and the gap between two, in pixels.
const BAR: int = 2
const BAR_GAP: int = 4
const LAMP: int = 4
const LAMP_GAP: int = 2
## How far out of the mouth the lamps stand, in pixels.
const LAMP_OUT: int = 4
## The portal's ring: its outer radius and its thickness, in pixels.
const PORTAL_RADIUS: int = 20
const PORTAL_RING: int = 4

## The colours: the bars' stone (light, dark), a lamp's shades out to lit, a held lamp's, the ring's.
var bar_colours: PackedColorArray = Palette.shades_of(&"stone")
var lamp_colours: PackedColorArray = PackedColorArray([Palette.OUTLINE, Palette.shades_of(&"spark")[0], Palette.shades_of(&"spark")[1], Palette.shades_of(&"spark")[2]])
var held_colours: PackedColorArray = PackedColorArray([Palette.OUTLINE, Palette.shades_of(&"fire")[0], Palette.shades_of(&"fire")[1], Palette.shades_of(&"fire")[2]])
var ring_colours: PackedColorArray = Palette.shades_of(&"void")

## Each door told (by its number): its rule, area, how many are gathered of how many stand, held,
## open; and what is drawn now: the bars' or the ring's frame (0 shut ... OPEN_FRAMES gone or open),
## each lamp's shade.
var _rules: Array[StringName] = []
var _areas: Array[Rect2] = []
var _gathered: PackedInt32Array = PackedInt32Array()
var _standing: PackedInt32Array = PackedInt32Array()
var _held: PackedByteArray = PackedByteArray()
var _open: PackedByteArray = PackedByteArray()
var _frame: PackedInt32Array = PackedInt32Array()
var _lamps: Array[PackedInt32Array] = []
## Each door's lamps' palette as drawn now (1 the held one's): it follows `_held` once they are out.
var _drawn_held: PackedByteArray = PackedByteArray()
## True after a restore's forgetting, until the next step: a door told meanwhile is drawn as it stands.
var _as_it_stands: bool = false
var _clock: float = 0.0


func _ready() -> void:
	top_level = true
	z_index = Z


func bind(events: EventsScript) -> void:
	if events != null:
		events.gather_door_shown.connect(_on_door_shown)


## How many doors are drawn (for tests).
func doors() -> int:
	return _rules.size()


## Door `door`'s frame now (0 shut ... OPEN_FRAMES open) and its lamps' shades (for tests).
func frame_of(door: int) -> int:
	return _frame[door] if door >= 0 and door < _frame.size() else -1


func lamps_of(door: int) -> PackedInt32Array:
	return _lamps[door] if door >= 0 and door < _lamps.size() else PackedInt32Array()


## True while something still moves toward what it was told.
func is_moving() -> bool:
	for door in _rules.size():
		if _frame[door] != _frame_wanted(door):
			return true
		var lamps: PackedInt32Array = _lamps[door]
		if lamps.size() != _lamp_count(door) or _drawn_held[door] != _held[door]:
			return true
		for lamp in lamps.size():
			if lamps[lamp] != _lamp_wanted(door, lamp):
				return true
	return false


## One step of every change (a frame at FPS), toward what each door was told.
func advance() -> void:
	for door in _rules.size():
		_frame[door] += signi(_frame_wanted(door) - _frame[door])
		var lamps: PackedInt32Array = _lamps[door]
		var wanted: int = _lamp_count(door)
		while lamps.size() < wanted:
			lamps.append(0)
		for lamp in lamps.size():
			lamps[lamp] += signi(_lamp_wanted(door, lamp) - lamps[lamp])
		# A lamp past the standing that has gone out goes.
		while lamps.size() > wanted and lamps[lamps.size() - 1] == 0:
			lamps.resize(lamps.size() - 1)
		_lamps[door] = lamps
		if _drawn_held[door] != _held[door] and _all_out(lamps):
			_drawn_held[door] = _held[door]
	_as_it_stands = false
	queue_redraw()


static func _all_out(lamps: PackedInt32Array) -> bool:
	for shade in lamps:
		if shade != 0:
			return false
	return true


func _process(delta: float) -> void:
	if not is_moving():
		_clock = 0.0
		return
	_clock += delta
	var step: float = 1.0 / FPS
	while _clock >= step:
		_clock -= step
		advance()


func _on_door_shown(door: int, rule: StringName, area: Rect2, gathered: int, standing: int, held: bool, open: bool) -> void:
	if door < 0:
		_forget()
		_as_it_stands = open
		return
	var fresh: bool = door >= _rules.size()
	while _rules.size() <= door:
		_rules.append(&"")
		_areas.append(Rect2())
		_gathered.append(0)
		_standing.append(0)
		_held.append(0)
		_open.append(0)
		# A door is first drawn as it stands: a shut door's bars already up, a portal not yet open.
		_frame.append(0)
		_lamps.append(PackedInt32Array())
		_drawn_held.append(1 if held else 0)
	_rules[door] = rule
	_areas[door] = area
	_gathered[door] = gathered
	_standing[door] = standing
	_held[door] = 1 if held else 0
	_open[door] = 1 if open else 0
	if fresh and open and rule != RoomKind.DOOR_PORTAL_HOME:
		# Told open before it was ever drawn shut (a restore): drawn open.
		_frame[door] = OPEN_FRAMES
	if _as_it_stands:
		# After a restore: as it stands, its frame and lamps where they are wanted.
		_frame[door] = _frame_wanted(door)
		_drawn_held[door] = _held[door]
		var lamps := PackedInt32Array()
		for lamp in _lamp_count(door):
			lamps.append(_lamp_wanted(door, lamp))
		_lamps[door] = lamps
	queue_redraw()


## Every door forgotten (the biome left, a restore: each is told again).
func _forget() -> void:
	_rules.clear()
	_areas.clear()
	_gathered.resize(0)
	_standing.resize(0)
	_held.resize(0)
	_open.resize(0)
	_frame.resize(0)
	_lamps.clear()
	_drawn_held.resize(0)
	_clock = 0.0
	queue_redraw()


func _frame_wanted(door: int) -> int:
	return OPEN_FRAMES if _open[door] != 0 else 0


## How many lamps door `door` wants: one a standing wizard; none once a door opened (a portal keeps them).
func _lamp_count(door: int) -> int:
	if _rules[door] != RoomKind.DOOR_PORTAL_HOME and _open[door] != 0:
		return 0
	return maxi(_standing[door], 0)


func _lamp_wanted(door: int, lamp: int) -> int:
	if lamp >= _lamp_count(door) or _drawn_held[door] != _held[door]:
		return 0
	return LAMP_STAGES if lamp < _gathered[door] else 1


func _draw() -> void:
	for door in _rules.size():
		if _rules[door] == RoomKind.DOOR_PORTAL_HOME:
			_draw_portal(door)
		else:
			_draw_bars(door)
		_draw_lamps(door)


## The bars across a door's mouth, across its long side, each sunk by the frame it is at.
func _draw_bars(door: int) -> void:
	var area := Rect2i(Vector2i(_areas[door].position.round()), Vector2i(_areas[door].size.round()))
	var wide: bool = area.size.x >= area.size.y
	var length: int = area.size.y if wide else area.size.x
	var left: int = length - (length * _frame[door]) / OPEN_FRAMES
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
		# Its lit edge (upper left).
		draw_rect(Rect2(Rect2i(bar.position, Vector2i(1, bar.size.y) if wide else Vector2i(bar.size.x, 1))), bar_colours[2])
		at += BAR + BAR_GAP


## The portal home's ring, opening out by the frame it is at.
func _draw_portal(door: int) -> void:
	var middle := Vector2i(_areas[door].get_center().round())
	var outer: int = (PORTAL_RADIUS * _frame[door]) / OPEN_FRAMES
	if outer <= 0:
		return
	var inner: int = maxi(outer - PORTAL_RING, 0)
	# A ring of whole-pixel rows: each row's span between the inner and the outer circle.
	for y in range(-outer, outer + 1):
		var half_out: int = int(sqrt(float(outer * outer - y * y)))
		var half_in: int = int(sqrt(float(inner * inner - y * y))) if absi(y) < inner else -1
		var colour: Color = ring_colours[2] if y < 0 else ring_colours[1]
		if half_in < 0:
			draw_rect(Rect2(middle.x - half_out, middle.y + y, half_out * 2 + 1, 1), colour)
		else:
			draw_rect(Rect2(middle.x - half_out, middle.y + y, half_out - half_in, 1), colour)
			draw_rect(Rect2(middle.x + half_in + 1, middle.y + y, half_out - half_in, 1), colour)
			draw_rect(Rect2(middle.x - half_in, middle.y + y, half_in * 2 + 1, 1), ring_colours[0])


## A door's lamps in a row beside it (under a door, over the portal), each its shade, a shrinking one
## smaller.
func _draw_lamps(door: int) -> void:
	var lamps: PackedInt32Array = _lamps[door]
	if lamps.is_empty():
		return
	var area: Rect2 = _areas[door]
	var row: int = lamps.size() * LAMP + (lamps.size() - 1) * LAMP_GAP
	var x: int = roundi(area.get_center().x) - row / 2
	var y: int = roundi(area.position.y) - LAMP_OUT - LAMP if _rules[door] == RoomKind.DOOR_PORTAL_HOME else roundi(area.end.y) + LAMP_OUT
	var colours: PackedColorArray = held_colours if _drawn_held[door] != 0 else lamp_colours
	for lamp in lamps.size():
		var shade: int = lamps[lamp]
		var side: int = LAMP if shade > 0 else LAMP - 2
		var inset: int = (LAMP - side) / 2
		draw_rect(Rect2(x + inset, y + inset, side, side), colours[clampi(shade, 0, colours.size() - 1)])
		x += LAMP + LAMP_GAP
