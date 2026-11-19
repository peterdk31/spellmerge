extends Node2D
## A biome's gather doors as the view draws them (connected biomes CB7, its look CB12's, decision
## 30): a shut door is stone bars across its mouth with a lamp for each standing wizard beside it,
## each lit in its wizard's hat colour as that wizard arrives; a held gate's lamps glow the fire's
## red; an opening door's bars sink into the floor; the portal home is a ring of void that opens out
## on its floor, with its lamps. It shows what the bus says (`gather_door_shown`) and, for whose lamp
## is whose, the wizards Feel hands it each frame (`see`): lamp k is the k-th standing wizard in seat
## order, lit when that wizard is among the `gathered` standing nearest the door (the bus counts who
## is at it; the view only says which). With no wizards handed (a test of the bus alone) the first
## `gathered` lamps are lit, in the spark's shades.
##
## **Smooth** (docs/STYLE.md): every change plays its frames, by whole pixels, at FPS: the bars sink
## over OPEN_FRAMES frames, the portal opens over the same, and a lamp steps through LAMP_STAGES shades
## each way (a lamp past the count shrinks out the same). A gate held or let go turns its lamps from
## the spark's shades to the fire's (or back) through their shared out shade (the outline): down, the
## palette changes there, up again; a lamp whose wizard changes (one went down, the lamps after it
## move up a seat) goes out the same way before it lights in its new wizard's colour. Nothing fades. After a restore (door -1 told with `open`), what
## is told next is drawn as it stands, never played in again.
##
## A child of Feel, top level (world space). View only: never state, nothing in the game reads it;
## it draws only while something moves (`_process` redraws then).

const EventsScript := preload("res://core/events/events.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

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
## Each door's lamps' wizard as drawn now (their hat ramp, 0-3; -1 none known: the spark's shades).
var _lamp_ramps: Array[PackedInt32Array] = []
## The standing wizards Feel handed this frame, in seat order: how many, their hat ramps and where
## they stand (the first `_seen` of each; sized once, nothing allocated a frame).
var _seen: int = 0
var _standing_ramps: PackedInt32Array = PackedInt32Array()
var _standing_at: PackedVector2Array = PackedVector2Array()
## Each hat ramp's lamp shades (out, then the ramp's shadow, base, light).
var _ramp_lamps: Array[PackedColorArray] = []
## True after a restore's forgetting, until the next drawn frame: a door told meanwhile is drawn as it stands.
var _as_it_stands: bool = false
var _clock: float = 0.0


func _ready() -> void:
	top_level = true
	z_index = Z
	_standing_ramps.resize(ActorsScript.SEATS)
	_standing_at.resize(ActorsScript.SEATS)
	for ramp in ActorsScript.SEATS:
		var shades: PackedColorArray = Palette.shades_of(StringName("player_%d" % (ramp + 1)))
		_ramp_lamps.append(PackedColorArray([Palette.OUTLINE, shades[0], shades[1], shades[2]]))


## The standing wizards now, from `table` (each seat's own body, not down; Feel's, once a frame):
## whose lamp is whose.
func see(table: ActorsScript) -> void:
	_seen = 0
	if table == null:
		return
	for seat in ActorsScript.SEATS:
		var id: int = table.home_of_seat(seat)
		var body := table.node_of(id) as Node2D
		if body == null or not is_instance_valid(body) or not body.is_inside_tree():
			continue
		if body is Actor and ((body as Actor).is_downed() or (body as Actor).is_dying()):
			continue
		_standing_ramps[_seen] = clampi(table.ramp_of(id), 0, ActorsScript.SEATS - 1)
		_standing_at[_seen] = body.global_position
		_seen += 1


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


## The hat ramp lamp `lamp` of door `door` is drawn in now (-1: none known, the spark's; for tests).
func lamp_ramp_of(door: int, lamp: int) -> int:
	if door < 0 or door >= _lamp_ramps.size() or lamp < 0 or lamp >= _lamp_ramps[door].size():
		return -1
	return _lamp_ramps[door][lamp]


## True while something still moves toward what it was told.
func is_moving() -> bool:
	for door in _rules.size():
		if _frame[door] != _frame_wanted(door):
			return true
		var lamps: PackedInt32Array = _lamps[door]
		if lamps.size() != _lamp_count(door) or _drawn_held[door] != _held[door]:
			return true
		var ramps: PackedInt32Array = _lamp_ramps[door]
		for lamp in lamps.size():
			if lamps[lamp] != _lamp_wanted(door, lamp) or ramps[lamp] != _ramp_wanted(door, lamp):
				return true
	return false


## One step of every change (a frame at FPS), toward what each door was told.
func advance() -> void:
	for door in _rules.size():
		_frame[door] += signi(_frame_wanted(door) - _frame[door])
		var lamps: PackedInt32Array = _lamps[door]
		var ramps: PackedInt32Array = _lamp_ramps[door]
		var wanted: int = _lamp_count(door)
		while lamps.size() < wanted:
			lamps.append(0)
			ramps.append(_ramp_wanted(door, lamps.size() - 1))
		for lamp in lamps.size():
			# Out, a lamp takes its new wizard's colour; then it lights as wanted.
			if lamps[lamp] == 0:
				ramps[lamp] = _ramp_wanted(door, lamp)
			lamps[lamp] += signi(_lamp_wanted(door, lamp) - lamps[lamp])
		# A lamp past the standing that has gone out goes.
		while lamps.size() > wanted and lamps[lamps.size() - 1] == 0:
			lamps.resize(lamps.size() - 1)
			ramps.resize(lamps.size())
		_lamps[door] = lamps
		_lamp_ramps[door] = ramps
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
	# A restore tells every door within the frame it happens in; what is told after is played in.
	_as_it_stands = false
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
		_lamp_ramps.append(PackedInt32Array())
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
		var ramps := PackedInt32Array()
		for lamp in _lamp_count(door):
			ramps.append(_ramp_wanted(door, lamp))
		_lamp_ramps[door] = ramps
		for lamp in _lamp_count(door):
			lamps.append(LAMP_STAGES if _is_gathered(door, lamp) else 1)
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
	_lamp_ramps.clear()
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
	var ramps: PackedInt32Array = _lamp_ramps[door]
	if lamp < ramps.size() and ramps[lamp] != _ramp_wanted(door, lamp):
		return 0
	return LAMP_STAGES if _is_gathered(door, lamp) else 1


## The hat ramp lamp `lamp` of door `door` wants: its standing wizard's (-1: none handed).
func _ramp_wanted(door: int, lamp: int) -> int:
	if lamp >= _seen or lamp >= _lamp_count(door):
		return -1
	return _standing_ramps[lamp]


## Whether lamp `lamp`'s wizard is at door `door`: among its `gathered` standing wizards nearest it
## (with none handed: the first `gathered` lamps).
func _is_gathered(door: int, lamp: int) -> bool:
	var gathered: int = _gathered[door]
	if lamp >= _seen:
		return lamp < gathered
	if gathered <= 0:
		return false
	var area: Rect2 = _areas[door]
	var mine: float = _gap_to(area, _standing_at[lamp])
	var nearer: int = 0
	for other in _seen:
		if other == lamp:
			continue
		var gap: float = _gap_to(area, _standing_at[other])
		if gap < mine or (gap == mine and other < lamp):
			nearer += 1
	return nearer < gathered


static func _gap_to(area: Rect2, at: Vector2) -> float:
	return at.clamp(area.position, area.end).distance_squared_to(at)


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
	var ramps: PackedInt32Array = _lamp_ramps[door]
	for lamp in lamps.size():
		var colours: PackedColorArray = lamp_colours
		if _drawn_held[door] != 0:
			colours = held_colours
		elif lamp < ramps.size() and ramps[lamp] >= 0 and ramps[lamp] < _ramp_lamps.size():
			colours = _ramp_lamps[ramps[lamp]]
		var shade: int = lamps[lamp]
		var side: int = LAMP if shade > 0 else LAMP - 2
		var inset: int = (LAMP - side) / 2
		draw_rect(Rect2(x + inset, y + inset, side, side), colours[clampi(shade, 0, colours.size() - 1)])
		x += LAMP + LAMP_GAP
