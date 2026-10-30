extends "res://hud/builder/rings/ring_picker.gd"
## The kinds ring (owner, 2026-10-30): the ring first shows one big sector per kind of card
## (carriers, modifiers, ...), easy to hit; a kind, once entered, unwraps: its cards alone spread
## over the ring (`SPAN`, centred on the kind's direction, so the stick starts mid-kind) and the
## stick picks among them. Two ways in, chosen on the pause menu's Sandbox page:
##
## - **Hold:** rest the stick (at least half pushed) in a kind's sector for HOLD_TIME seconds;
##   the sector fills up as it waits. Letting go of the stick goes back to the kinds.
## - **Depth:** the first part of the push points at a kind (from KIND_TILT); pushing further
##   (OPEN_TILT) enters it, and easing back under CLOSE_TILT goes back to the kinds (the gap
##   between the two keeps it from flickering).
##
## P1's mouse works the same: its distance from the middle is the push (1 on the ring). Past
## either end of an unwrapped kind, the nearer end card is picked. The numbers are first guesses.

const RadialScript := preload("res://hud/builder/radial_builder.gd")

enum Enter { HOLD, DEPTH }

const HOLD_TILT: float = 0.5
const HOLD_TIME: float = 0.25
const KIND_TILT: float = 0.3
const OPEN_TILT: float = 0.65
const CLOSE_TILT: float = 0.55
## How much of the ring an unwrapped kind takes; the rest is a gap that marks its two ends.
const SPAN: float = TAU * 300.0 / 360.0
## The pointed kind's sector holds this far past its border (radians).
const KIND_STICKY: float = 0.1
## The space between two kind sectors, at each side (radians).
const SECTOR_GAP: float = 0.05

var enter: Enter = Enter.HOLD

## The kind entered (an index into the radial's kinds) or NONE; the kind pointed at, and how
## long the stick has rested on it (Hold).
var _open_kind: int = NONE
var _kind_pointed: int = NONE
var _held: float = 0.0
## The entered kind's cards as ring places: their entries, middles and widths.
var _entries: PackedInt32Array = PackedInt32Array()
var _angles: PackedFloat32Array = PackedFloat32Array()
var _widths: PackedFloat32Array = PackedFloat32Array()


func _init(how: Enter = Enter.HOLD) -> void:
	enter = how


func reset() -> void:
	_open_kind = NONE
	_kind_pointed = NONE
	_held = 0.0
	_entries.clear()
	_angles.clear()
	_widths.clear()


## The kind entered, or `&""` while the ring shows the kinds (for tests).
func open_kind(radial: Control) -> StringName:
	return (radial as RadialScript)._kinds[_open_kind] if _open_kind != NONE else &""


## The kind pointed at on the kinds ring, or `&""` (for tests).
func pointed_kind(radial: Control) -> StringName:
	return (radial as RadialScript)._kinds[_kind_pointed] if _kind_pointed != NONE else &""


## The direction of kind `kind`'s sector (zero if the bag has none).
func kind_direction(radial: Control, kind: StringName) -> Vector2:
	var kinds: Array[StringName] = (radial as RadialScript)._kinds
	var at: int = kinds.find(kind)
	return RadialScript.direction_of(_sector_middle(at, kinds.size())) if at >= 0 else Vector2.ZERO


## The direction of card `id` in the entered kind (zero if it is not there).
func card_direction(radial: Control, id: StringName) -> Vector2:
	var r: RadialScript = radial as RadialScript
	for at in _entries.size():
		if r._entries[_entries[at]]["id"] == id:
			return RadialScript.direction_of(_angles[at])
	return Vector2.ZERO


func pick(radial: Control, delta: float) -> int:
	var r: RadialScript = radial as RadialScript
	var aim: Vector2 = r.stick_tilt()
	if aim == Vector2.ZERO:
		aim = r.mouse_reach()
	var tilt: float = minf(aim.length(), 1.0)
	var count: int = r._kinds.size()
	if count == 0 or tilt <= 0.0:
		reset()
		return NONE
	var angle: float = RadialScript.angle_of(aim)
	if _open_kind != NONE:
		if enter == Enter.DEPTH and tilt < CLOSE_TILT:
			_close()
		else:
			return _pick_card(r, angle)
	var sector: int = _sector_at(angle, count)
	var pointed: int = sector if tilt >= (KIND_TILT if enter == Enter.DEPTH else HOLD_TILT) else NONE
	if pointed != _kind_pointed:
		_held = 0.0
		_kind_pointed = pointed
		r._changed()
	if pointed == NONE:
		return NONE
	if enter == Enter.HOLD:
		_held += delta
		if _held < HOLD_TIME:
			return NONE
	elif tilt < OPEN_TILT:
		return NONE
	_open(r, pointed)
	return _pick_card(r, angle)


func is_animating() -> bool:
	return enter == Enter.HOLD and _open_kind == NONE and _kind_pointed != NONE


func _sector_middle(at: int, count: int) -> float:
	return TAU * float(at) / float(count)


## The sector under `angle`; the pointed one holds KIND_STICKY past its border.
func _sector_at(angle: float, count: int) -> int:
	var width: float = TAU / float(count)
	if _kind_pointed != NONE and _kind_pointed < count:
		if absf(angle_difference(_sector_middle(_kind_pointed, count), angle)) <= width * 0.5 + KIND_STICKY:
			return _kind_pointed
	return posmod(roundi(angle / width), count)


## Enter kind `at`: its cards spread over SPAN, centred on its sector.
func _open(r: RadialScript, at: int) -> void:
	_open_kind = at
	_entries.clear()
	_angles.clear()
	_widths.clear()
	var kind: StringName = r._kinds[at]
	for entry in r._entries.size():
		if r._entries[entry]["kind"] == kind:
			_entries.append(entry)
	var width: float = SPAN / float(maxi(_entries.size(), 1))
	var start: float = _sector_middle(at, r._kinds.size()) - SPAN * 0.5
	for place in _entries.size():
		_angles.append(fposmod(start + (float(place) + 0.5) * width, TAU))
		_widths.append(width)
	r._changed()


func _close() -> void:
	_open_kind = NONE
	_entries.clear()
	_angles.clear()
	_widths.clear()


## The entered kind's card under `angle`; in the gap past its ends, the nearer end.
func _pick_card(r: RadialScript, angle: float) -> int:
	if _entries.is_empty():
		return NONE
	var picked: int = r.pick_among(_entries, _angles, _widths, angle)
	if picked != NONE:
		return picked
	var last: int = _entries.size() - 1
	var to_first: float = absf(angle_difference(_angles[0], angle))
	var to_last: float = absf(angle_difference(_angles[last], angle))
	return _entries[0] if to_first <= to_last else _entries[last]


func draw(radial: Control) -> bool:
	var r: RadialScript = radial as RadialScript
	var radius: float = RadialScript.RING_RADIUS
	var center: Vector2 = r._center
	r.draw_arc(center, radius, 0.0, TAU, 64, RadialScript.LINE, 1.0)
	var aim: Vector2 = r._drawn_aim
	if aim != Vector2.ZERO:
		r.draw_line(center + aim * (RadialScript.HUB_RADIUS + 2.0), center + aim * (radius - 11.0), Color(RadialScript.GOLD, 0.55), 1.0)
	if _open_kind == NONE:
		_draw_kinds(r)
	else:
		_draw_cards(r)
	return true


## The kinds ring: a thick arc per kind with its name, the pointed one bright (and, with Hold,
## filling up while the stick rests on it).
func _draw_kinds(r: RadialScript) -> void:
	var count: int = r._kinds.size()
	var width: float = TAU / float(count)
	var radius: float = RadialScript.RING_RADIUS
	for at in count:
		var kind: StringName = r._kinds[at]
		var middle: float = _sector_middle(at, count)
		var from: float = middle - width * 0.5 + SECTOR_GAP - PI * 0.5
		var to: float = middle + width * 0.5 - SECTOR_GAP - PI * 0.5
		var on: bool = at == _kind_pointed
		var color: Color = RadialScript.KIND_COLORS[kind]
		r.draw_arc(r._center, radius, from, to, 24, color if on else Color(color, 0.45), 7.0 if on else 3.0)
		if on and enter == Enter.HOLD:
			var share: float = clampf(_held / HOLD_TIME, 0.0, 1.0)
			r.draw_arc(r._center, radius - 7.0, from, from + (to - from) * share, 24, RadialScript.GOLD, 2.0)
		var word: String = String(RadialScript.KIND_WORDS.get(kind, kind))
		# Pushed outward by half its width at the sides, so the word stays clear of the arc.
		var label: Vector2 = r._tile_center(middle, radius + RadialScript.ARC_OUT - 2.0)
		label.x += sin(middle) * r._text_width(word) * 0.5
		r._text(word, label - Vector2(0.0, 4.0), RadialScript.TEXT if on else RadialScript.MUTED, true)


## The entered kind: its cards on the ring, its arc outside them and its name in the gap.
func _draw_cards(r: RadialScript) -> void:
	var radius: float = RadialScript.RING_RADIUS
	var kind: StringName = r._kinds[_open_kind]
	var middle: float = _sector_middle(_open_kind, r._kinds.size())
	r.draw_arc(r._center, radius + RadialScript.ARC_OUT, middle - SPAN * 0.5 - PI * 0.5, middle + SPAN * 0.5 - PI * 0.5, 48, RadialScript.KIND_COLORS[kind], 2.0)
	var word: String = String(RadialScript.KIND_WORDS.get(kind, kind))
	r._text(word, r._tile_center(middle + PI, radius) - Vector2(0.0, 4.0), RadialScript.KIND_COLORS[kind], true)
	var size: float = clampf(floorf(_widths[0] * radius) - 1.0, RadialScript.ICON_MIN, RadialScript.TILE_MAX) if not _widths.is_empty() else 0.0
	var picked_at: float = NAN
	for at in _entries.size():
		if _entries[at] == r._pointed:
			picked_at = _angles[at]
			continue
		r._draw_ring_card(_entries[at], r._tile_center(_angles[at], radius), size, false)
	if not is_nan(picked_at):
		r._draw_ring_card(r._pointed, r._tile_center(picked_at, radius + 4.0), RadialScript.TILE_PICKED, true)
