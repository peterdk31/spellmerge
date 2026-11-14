extends RefCounted
## The shared radial menu (items I5, docs/milestones/items.md): a ring of places round a hub,
## pointed at with the right stick or P1's mouse, with layers (enter a place, go back) and a hint
## row of button glyphs and verbs. The radial builder (`hud/builder/radial_builder.gd`) is built
## on it, and the inventory (I7) will be.
##
## It knows nothing of what the places hold: a host (a Control) owns the entries, says how the
## ring is laid out (`lay_out`: per place an entry number or NONE for a gap, and its width), and
## gets back which entry is pointed at. It draws into its host's canvas, from the host's `_draw`,
## so the host decides what lies over and under the ring; the hint glyphs are the host's children.
##
##     var menu := RadialMenu.new(self, index)       # in the host's _ready, before bind
##     menu.make_hints([&"staff_2", &"back"])
##     menu.bind(input)                              # the PlayerInput node, or null
##     menu.center = ...; menu.hints_at = ...        # where the host lays it out
##     menu.lay_out(entries, widths)                 # the first place sits at the top
##     menu.point_at(menu.pick_on_ring(menu.aim()), clock)
##
## Angles are ring angles: 0 is up, clockwise, 0 to TAU. Pointing holds the pointed entry a little
## past its border (`STICKY_ANGLE`), so a wobbling thumb does not flicker between two entries.
## Nothing here allocates per frame but `lay_out`, `set_hints` and the layers.

const InputManagerScript := preload("res://core/input/input_manager.gd")
const ActionGlyphScript := preload("res://hud/widgets/action_glyph.gd")

const NONE: int = -1
## The ring, the hub in its middle and the arcs outside it (px).
const RING_RADIUS: float = 56.0
const HUB_RADIUS: float = 38.0
const ARC_OUT: float = 12.0
## The right stick points past this push.
const POINT_THRESHOLD: float = 0.5
## Hysteresis: the pointed entry stays pointed until the aim is this far (radians) past its
## border, at most STICKY_SHARE of its width, so a neighbour's middle always picks the neighbour.
const STICKY_ANGLE: float = 0.07
const STICKY_SHARE: float = 0.4
## P1's mouse points when it is this far from the ring's middle, up to the arcs and a margin.
const MOUSE_INNER: float = 10.0
const MOUSE_OUTER: float = 90.0
## The pointer line moves when the aim moved more than this (squared length).
const AIM_MOVED: float = 0.002
const FONT_SIZE: int = 8
const HINT_HEIGHT: float = 10.0
## The hint row: a glyph, GLYPH_GAP, its verb, VERB_GAP, the next glyph; a button that does
## nothing now is dimmed to DIM_ALPHA (and its verb drawn in DIM), never hidden.
const GLYPH_GAP: float = 2.0
const VERB_GAP: float = 6.0
const DIM_ALPHA: float = 0.4
const LINE: Color = Color("#4a4663")
const OUTLINE: Color = Color("#14121f")
const TEXT: Color = Color("#f4f1ea")
const DIM: Color = Color("#7a7694")
const GOLD: Color = Color("#f2c230")

## The player 0-3 it is for.
var index: int = 0
## The ring's middle and the hint row's top left, in the host's pixels (set by the host's layout).
var center: Vector2 = Vector2.ZERO
var hints_at: Vector2 = Vector2.ZERO
## The entry pointed at, or NONE. A host that lays the ring out again keeps or drops it.
var pointed: int = NONE

var _host: Control = null
var _input: InputManagerScript = null
## The ring's places: per place its entry (NONE for a gap), its middle angle and its width.
var _entries: PackedInt32Array = PackedInt32Array()
var _angles: PackedFloat32Array = PackedFloat32Array()
var _widths: PackedFloat32Array = PackedFloat32Array()
## When `pointed` was last pointed at (the host's clock), for its pop.
var _pointed_at: float = -1.0
## The aim last drawn, so the pointer line follows the stick.
var _drawn_aim: Vector2 = Vector2.ZERO
## The entries entered, outermost first (`enter`, `back`).
var _path: PackedInt32Array = PackedInt32Array()
## The hint row: per button its glyph, verb, whether it does something now and where its verb sits.
var _hint_actions: Array[StringName] = []
var _hint_glyphs: Array[ActionGlyphScript] = []
var _hint_verbs: Array[String] = []
var _hint_live: Array[bool] = []
var _hint_text_x: PackedFloat32Array = PackedFloat32Array()


func _init(host: Control, player: int) -> void:
	_host = host
	index = player


## The hint row's buttons, in order: one glyph each, a child of the host named "Hint_<action>".
## Called once, before `bind`.
func make_hints(actions: Array[StringName]) -> void:
	for action in actions:
		var glyph: ActionGlyphScript = ActionGlyphScript.new()
		glyph.name = "Hint_%s" % action
		_host.add_child(glyph)
		_hint_actions.append(action)
		_hint_glyphs.append(glyph)
		_hint_verbs.append("")
		_hint_live.append(true)
		_hint_text_x.append(0.0)


## Connect the input manager (null: nothing points, and the glyphs use the autoload) and show the
## hint row's buttons for this player.
func bind(input: InputManagerScript) -> void:
	_input = input
	for at in _hint_glyphs.size():
		_hint_glyphs[at].bind(input)
		_hint_glyphs[at].show_action(index, _hint_actions[at])


# --- The ring ---------------------------------------------------------------------------

## Lay the ring out: per place its entry (NONE for a gap) and its share of the ring (any units:
## the shares are scaled to the whole ring). The first entry's middle sits at the top. With no
## width at all the ring is empty.
func lay_out(entries: PackedInt32Array, widths: PackedFloat32Array) -> void:
	_entries = entries.duplicate()
	_angles.clear()
	_widths.clear()
	var total: float = 0.0
	for width in widths:
		total += width
	if total <= 0.0:
		_entries.clear()
		return
	var angle: float = 0.0
	var first: float = NAN
	for at in widths.size():
		var width: float = widths[at] / total * TAU
		_widths.append(width)
		_angles.append(angle + width * 0.5)
		if is_nan(first) and _entries[at] != NONE:
			first = angle + width * 0.5
		angle += width
	if is_nan(first):
		first = 0.0
	for at in _angles.size():
		_angles[at] = fposmod(_angles[at] - first, TAU)


## True when the ring has no place.
func is_empty() -> bool:
	return _entries.is_empty()


## The ring's places (copies on write: reading them allocates nothing): their entries (NONE for a
## gap), middle angles and widths, in radians.
func place_entries() -> PackedInt32Array:
	return _entries


func place_angles() -> PackedFloat32Array:
	return _angles


func place_widths() -> PackedFloat32Array:
	return _widths


## How wide (px, on the ring) the first entry's place is; 0 with none.
func place_room() -> float:
	for at in _entries.size():
		if _entries[at] != NONE:
			return _widths[at] * RING_RADIUS
	return 0.0


## The middle angle of entry `entry`'s place (0 when it has none).
func angle_of_entry(entry: int) -> float:
	var at: int = _entries.find(entry) if entry != NONE else NONE
	return _angles[at] if at >= 0 else 0.0


## The direction the stick must point to land on entry `entry` (zero when it is not on the ring).
func direction_to(entry: int) -> Vector2:
	var at: int = _entries.find(entry) if entry != NONE else NONE
	return direction_of(_angles[at]) if at >= 0 else Vector2.ZERO


## The point at ring angle `angle`, `radius` from the middle.
func tile_center(angle: float, radius: float) -> Vector2:
	return center + direction_of(angle) * radius


## The ring angle of a direction: 0 is up, clockwise, 0 to TAU.
static func angle_of(aim: Vector2) -> float:
	return fposmod(atan2(aim.x, -aim.y), TAU)


## The direction of a ring angle (the inverse of `angle_of`).
static func direction_of(angle: float) -> Vector2:
	return Vector2(sin(angle), -cos(angle))


# --- Pointing ---------------------------------------------------------------------------

## Where the player points now: the right stick past `POINT_THRESHOLD`, else P1's mouse on the
## ring (`mouse_aim`), else zero.
func aim() -> Vector2:
	var stick: Vector2 = _input.menu_aim(index) if _input != null else Vector2.ZERO
	return stick if stick.length() >= POINT_THRESHOLD else mouse_aim()


## The right stick with how far it is pushed (0 to 1 past the dead zone), for pickers that read
## the push.
func stick_tilt() -> Vector2:
	return _input.menu_tilt(index) if _input != null else Vector2.ZERO


## P1's mouse as a pointing direction, or zero (other players, the mouse off the ring).
func mouse_aim() -> Vector2:
	if not uses_mouse():
		return Vector2.ZERO
	var offset: Vector2 = _host.get_global_mouse_position() - center
	var length: float = offset.length()
	return offset / length if length > MOUSE_INNER and length < MOUSE_OUTER else Vector2.ZERO


## P1's mouse from the ring's middle, in ring radii (1 on the ring), or zero (other players, the
## mouse off the ring and its arcs). For pickers that read how far out it is.
func mouse_reach() -> Vector2:
	if not uses_mouse():
		return Vector2.ZERO
	var offset: Vector2 = _host.get_global_mouse_position() - center
	return offset / RING_RADIUS if offset.length() < MOUSE_OUTER else Vector2.ZERO


## True when this player is on the keyboard and mouse (P1), and the host is in the tree.
func uses_mouse() -> bool:
	return _input != null and _input.device_of(index) == InputManagerScript.KEYBOARD and _host.is_inside_tree()


## Follow `aim` with the pointer line; true when it moved enough to redraw.
func follow(aim_now: Vector2) -> bool:
	if aim_now.distance_squared_to(_drawn_aim) <= AIM_MOVED:
		return false
	_drawn_aim = aim_now
	return true


## The aim the pointer line shows.
func drawn_aim() -> Vector2:
	return _drawn_aim


## The entry the ring has in direction `aim_now`, or NONE (zero aims at nothing).
func pick_on_ring(aim_now: Vector2) -> int:
	if aim_now == Vector2.ZERO:
		return NONE
	return pick_among(_entries, _angles, _widths, angle_of(aim_now))


## The entry at `angle` among places (their entries, NONE for a gap, middles and widths, in
## radians), or NONE; the pointed entry holds `STICKY_ANGLE` past its border. Pickers that lay
## places out their own way pick with this too.
func pick_among(entries: PackedInt32Array, angles: PackedFloat32Array, widths: PackedFloat32Array, angle: float) -> int:
	var picked: int = NONE
	for at in entries.size():
		var off: float = absf(fposmod(angle - angles[at] + PI, TAU) - PI)
		var half: float = widths[at] * 0.5
		if entries[at] != NONE and entries[at] == pointed:
			half += minf(STICKY_ANGLE, widths[at] * STICKY_SHARE)
		if off <= half:
			picked = entries[at]
			if picked == pointed:
				break
	return picked


## Point at `entry` (NONE lets go) at the host's clock `now`; true when that changed what is
## pointed at.
func point_at(entry: int, now: float) -> bool:
	if entry == pointed:
		return false
	pointed = entry
	_pointed_at = now
	return true


## Seconds since the pointed entry was pointed at, by the host's clock `now`.
func pointed_for(now: float) -> float:
	return now - _pointed_at


# --- Layers -----------------------------------------------------------------------------

## Enter entry `entry` (a sector whose own ring the host lays out next): pointing starts afresh.
func enter(entry: int) -> void:
	_path.append(entry)
	pointed = NONE


## Go back out one layer, pointing at the entry that was entered; false at the first layer.
func back() -> bool:
	if _path.is_empty():
		return false
	pointed = _path[_path.size() - 1]
	_path.resize(_path.size() - 1)
	return true


## Back to the first layer, pointing at nothing.
func leave_layers() -> void:
	_path.clear()
	pointed = NONE


## How many layers in (0: the first ring).
func depth() -> int:
	return _path.size()


## The entry entered last, or NONE on the first ring.
func entered() -> int:
	return _path[_path.size() - 1] if not _path.is_empty() else NONE


# --- The hint row -----------------------------------------------------------------------

## Lay the hint row out at `hints_at` for what the buttons do now: each button's verb and whether
## it does something (dimmed when not). Both as long as the row's buttons.
func set_hints(verbs: Array[String], live: Array[bool]) -> void:
	_hint_verbs.assign(verbs)
	_hint_live.assign(live)
	var x: float = hints_at.x
	for at in _hint_glyphs.size():
		var glyph: ActionGlyphScript = _hint_glyphs[at]
		glyph.position = Vector2(x, hints_at.y)
		glyph.modulate.a = 1.0 if _hint_live[at] else DIM_ALPHA
		x += glyph.custom_minimum_size.x + GLYPH_GAP
		_hint_text_x[at] = x
		x += text_width(_hint_verbs[at]) + VERB_GAP


## The hint row's verbs, as shown (copies).
func hint_verbs() -> Array[String]:
	return _hint_verbs.duplicate()


## The hint row's place, from its first glyph to the end of its last verb.
func hints_rect() -> Rect2:
	var width: float = 0.0
	if not _hint_verbs.is_empty():
		width = _hint_text_x[_hint_text_x.size() - 1] + text_width(_hint_verbs[_hint_verbs.size() - 1]) - hints_at.x
	return Rect2(hints_at, Vector2(width, HINT_HEIGHT))


# --- Drawing (from the host's _draw) ------------------------------------------------------

## The ring's line.
func draw_ring_line() -> void:
	_host.draw_arc(center, RING_RADIUS, 0.0, TAU, 64, LINE, 1.0)


## The pointer line, from the hub towards the ring, where the aim last drawn points.
func draw_pointer() -> void:
	if _drawn_aim != Vector2.ZERO:
		_host.draw_line(center + _drawn_aim * (HUB_RADIUS + 2.0), center + _drawn_aim * (RING_RADIUS - 11.0), Color(GOLD, 0.55), 1.0)


## An arc outside the ring round each run of neighbouring places whose entries share a group:
## `group_of(entry)` names an entry's group, `colors` holds each group's colour. A gap ends a run.
func draw_group_arcs(group_of: Callable, colors: Dictionary) -> void:
	var start: int = 0
	while start < _entries.size():
		if _entries[start] == NONE:
			start += 1
			continue
		var group: Variant = group_of.call(_entries[start])
		var end: int = start
		while end + 1 < _entries.size() and _entries[end + 1] != NONE and group_of.call(_entries[end + 1]) == group:
			end += 1
		var from: float = _angles[start] - _widths[start] * 0.5 + 0.03
		var to: float = _angles[end] + _widths[end] * 0.5 - 0.03
		if to < from:
			to += TAU
		_host.draw_arc(center, RING_RADIUS + ARC_OUT, from - PI * 0.5, to - PI * 0.5, 24, colors.get(group, LINE), 2.0)
		start = end + 1


## The hub: a dark disc with a line round it (the host writes in it).
func draw_hub() -> void:
	_host.draw_circle(center, HUB_RADIUS, OUTLINE)
	_host.draw_arc(center, HUB_RADIUS, 0.0, TAU, 48, LINE, 1.0)


## The hint row's verbs (the glyphs draw themselves).
func draw_hints() -> void:
	for at in _hint_verbs.size():
		draw_text(_hint_verbs[at], Vector2(_hint_text_x[at], hints_at.y + 1.0), TEXT if _hint_live[at] else DIM)


## The width of `text` in the host's font at `FONT_SIZE`.
func text_width(text: String) -> float:
	return _host.get_theme_default_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x


## Draw `text` with its top left at `at` (or centred on `at.x`), on the host.
func draw_text(text: String, at: Vector2, color: Color, centered: bool = false) -> void:
	var font: Font = _host.get_theme_default_font()
	var x: float = at.x - (text_width(text) * 0.5 if centered else 0.0)
	_host.draw_string(font, Vector2(x, at.y + font.get_ascent(FONT_SIZE)).round(), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
