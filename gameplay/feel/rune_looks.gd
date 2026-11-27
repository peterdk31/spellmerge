extends Node2D
## A biome's secret runes as the view draws them (the owner, 2026-11-20: a secret room reached by "a
## hidden rune or crack in a room, once found, teleports a player to the secret room and back"). It
## shows what the bus says (`secret_rune_shown`, Flow's `SecretRunes`) and nothing else; nothing in
## the game reads it.
##
## **Hidden:** a faint crack in the floor at the rune, in its element's tint (the palette material
## nearest the card's tint, as a secret rock's: `LockLooks.nearest_material`), at its darkest shade:
## the one hint a party has, as a rock's crack is. Nothing is drawn yet in the secret room.
## **Found:** the rune draws itself in round the crack by stages at FPS (`FOUND_FRAMES`): the crack
## brightens, then a ring closes round it a third at a time, each stage keeping what the one before
## drew (the crack is the rune's own stroke all through: docs/STYLE.md, "Smooth"); the rune leading
## back in the secret room comes in by the same stages, from nothing. Whole pixels, never a fade.
## After a restore (-1 told with `found` true) what is told next is drawn as it stands.
## **At the art's detail** (ART3; ArtDetail): drawn in art pixels, DETAIL a world pixel each way, at
## the same size: the crack is a jagged stroke an art pixel wide, two across its middle, with a dark
## lip under it once lit; the ring is an outer row in the base shade with a lit row inside it, and
## four notches pointing in, each drawn as the ring comes round to it.
## A child of Feel, top level (world space), on the floor under the bodies; it steps itself while a
## rune still moves.

const EventsScript := preload("res://core/events/events.gd")
const UnseenMaskScript := preload("res://gameplay/feel/unseen_mask.gd")
const LockLooksScript := preload("res://gameplay/feel/lock_looks.gd")

## On the floor, under the bodies and the doors' looks.
const Z: int = 2
## Frames a second the stages step at.
const FPS: float = 12.0
## The stages of a found rune: 1 the crack lit, 2 to 4 the ring a third more each.
const FOUND_FRAMES: int = 4
## The ring's radius and the crack's half length (world pixels).
const RING: int = 7
const CRACK: int = 5
## Art pixels a world pixel each way (ArtDetail), and how long a notch is (art pixels).
const DETAIL: int = ArtDetail.DETAIL
const NOTCH: int = 2
## Where the elements are (their tints).
const SPELLS_FOLDER: StringName = &"spells"

## Where nothing is drawn because nobody has seen it yet (Feel's `UnseenDark.mask`; null: drawn
## everywhere): what lies there is left out, and drawn as it stands from the room's reveal (Feel
## draws this again whenever the mask changes).
var unseen: UnseenMaskScript = null
## The registry the elements are read from (Feel's; null in a test: the spark's tint).
var registry: Node = null

## Runes by number: the hidden rune's middle and the one leading back, its tint's shades, found, the
## frame drawn (0 hidden ... FOUND_FRAMES).
var _at: PackedVector2Array = PackedVector2Array()
var _back: PackedVector2Array = PackedVector2Array()
var _tints: Array[PackedColorArray] = []
var _found: PackedByteArray = PackedByteArray()
var _frame: PackedInt32Array = PackedInt32Array()
var _as_they_stand: bool = false
var _clock: float = 0.0
## The crack's, its lip's, the ring's two rows' and the notches' art pixels from a rune's middle (the
## ring's and the notches' in order round from the top).
var _crack: PackedVector2Array = PackedVector2Array()
var _lip: PackedVector2Array = PackedVector2Array()
var _ring: PackedVector2Array = PackedVector2Array()
var _ring_in: PackedVector2Array = PackedVector2Array()
var _notches: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	_crack = crack_pixels()
	_lip = lip_pixels(_crack)
	_ring = ring_pixels()
	_ring_in = ring_pixels(RING * DETAIL - 1)
	_notches = notch_pixels()


func _ready() -> void:
	top_level = true
	z_index = Z


func bind(events: EventsScript) -> void:
	if events != null:
		events.secret_rune_shown.connect(_on_secret_rune_shown)


## How many runes are drawn, and rune `rune`'s frame (for tests).
func runes() -> int:
	return _at.size()


func frame_of(rune: int) -> int:
	return _frame[rune] if rune >= 0 and rune < _frame.size() else -1


## The tint's shades rune `rune` is drawn in (shadow, base, light).
func tint_of(rune: int) -> PackedColorArray:
	return _tints[rune] if rune >= 0 and rune < _tints.size() else PackedColorArray()


## True while a rune still moves toward what it was told.
func is_moving() -> bool:
	for rune in _at.size():
		if _frame[rune] != _wanted(rune):
			return true
	return false


## One stage of every rune that moves (a frame at FPS).
func advance() -> void:
	for rune in _at.size():
		_frame[rune] += signi(_wanted(rune) - _frame[rune])
	queue_redraw()


func _process(delta: float) -> void:
	# A restore tells everything within the frame it happens in; what comes after is played.
	_as_they_stand = false
	if not is_moving():
		_clock = 0.0
		return
	_clock += delta
	var step: float = 1.0 / FPS
	while _clock >= step:
		_clock -= step
		advance()


func _on_secret_rune_shown(rune: int, at: Vector2, back_at: Vector2, element: StringName, found: bool) -> void:
	if rune < 0:
		_at.resize(0)
		_back.resize(0)
		_tints.clear()
		_found.resize(0)
		_frame.resize(0)
		_as_they_stand = found
		queue_redraw()
		return
	var fresh: bool = rune >= _at.size()
	while _at.size() <= rune:
		_at.append(Vector2.ZERO)
		_back.append(Vector2.ZERO)
		_tints.append(PackedColorArray())
		_found.append(0)
		_frame.append(0)
	_at[rune] = at.round()
	_back[rune] = back_at.round()
	_tints[rune] = _tint_of(element)
	_found[rune] = 1 if found else 0
	if _as_they_stand or (fresh and found):
		_frame[rune] = _wanted(rune)
	queue_redraw()


func _wanted(rune: int) -> int:
	return FOUND_FRAMES if _found[rune] != 0 else 0


func _tint_of(element: StringName) -> PackedColorArray:
	var card := registry.call(&"get_resource", SPELLS_FOLDER, element) as ElementBase if registry != null and element != &"" else null
	return Palette.shades_of(LockLooksScript.nearest_material(card.tint) if card != null else &"spark")


## The crack's art pixels from a rune's middle: a jagged stroke from upper left to lower right through
## it, CRACK world pixels each way, an art pixel wide and two across its middle third.
static func crack_pixels() -> PackedVector2Array:
	var out := PackedVector2Array()
	var reach: int = CRACK * DETAIL
	for i in range(-reach, reach + 1):
		# It wanders an art pixel aside and back every few: a crack, not a ruled line.
		var aside: int = 1 if posmod(i, 5) >= 3 else 0
		var pixel := Vector2(i, i + aside)
		if not out.has(pixel):
			out.append(pixel)
		if absi(i) <= reach / 3 and not out.has(pixel + Vector2.RIGHT):
			out.append(pixel + Vector2.RIGHT)
	return out


## The lip under the crack `crack` (art pixels): each pixel just below one of it that is not its own.
static func lip_pixels(crack: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for pixel: Vector2 in crack:
		var under: Vector2 = pixel + Vector2.DOWN
		if not crack.has(under) and not out.has(under):
			out.append(under)
	return out


## A ring's art pixels from a rune's middle, `radius` art pixels round (RING world pixels by
## default), in order clockwise from the top (each once).
static func ring_pixels(radius: int = RING * DETAIL) -> PackedVector2Array:
	var found: Array[Vector2] = []
	for y in range(-radius - 1, radius + 2):
		for x in range(-radius - 1, radius + 2):
			if absf(Vector2(x, y).length() - float(radius)) < 0.5:
				found.append(Vector2(x, y))
	found.sort_custom(func(a: Vector2, b: Vector2) -> bool: return _round_from_top(a) < _round_from_top(b))
	return PackedVector2Array(found)


## The notches' art pixels: NOTCH pointing in from inside the ring at its four diagonals, in order
## clockwise from the top.
static func notch_pixels() -> PackedVector2Array:
	var found := PackedVector2Array()
	# The first diagonal pixel inside the ring's lit row (sqrt(1/2) of two art pixels less than it).
	var from: int = roundi(float(RING * DETAIL - 2) * sqrt(0.5))
	for corner: Vector2 in [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
		for n in NOTCH:
			found.append(corner * float(from - n))
	return found


## How far round from the top, clockwise, `point` lies (0 to TAU): the ring's drawing order.
static func _round_from_top(point: Vector2) -> float:
	return fposmod(atan2(point.x, -point.y), TAU)


func _draw() -> void:
	for rune in _at.size():
		var frame: int = _frame[rune]
		if unseen == null or not unseen.hides(_at[rune]):
			_draw_rune(_at[rune], frame, _tints[rune], true)
		if frame > 0 and (unseen == null or not unseen.hides(_back[rune])):
			_draw_rune(_back[rune], frame, _tints[rune], false)


## A rune at `at` at stage `frame` in `tint`'s shades; `hidden_crack`: its crack is drawn even while
## hidden (the hidden rune; the one leading back shows only once found).
func _draw_rune(at: Vector2, frame: int, tint: PackedColorArray, hidden_crack: bool) -> void:
	if tint.size() < 3 or (frame == 0 and not hidden_crack):
		return
	var crack_shade: Color = tint[0] if frame == 0 else (tint[1] if frame == 1 else tint[2])
	_draw_pixels(at, _crack, _crack.size(), crack_shade)
	if frame >= 1:
		_draw_pixels(at, _lip, _lip.size(), tint[0])
	if frame <= 1:
		return
	# The ring and its notches come round a third a stage, each where the ring has reached.
	_draw_pixels(at, _ring, _ring.size() * (frame - 1) / (FOUND_FRAMES - 1), tint[1])
	_draw_pixels(at, _ring_in, _ring_in.size() * (frame - 1) / (FOUND_FRAMES - 1), tint[2])
	_draw_pixels(at, _notches, _notches.size() * (frame - 1) / (FOUND_FRAMES - 1), tint[1])


## The first `count` of the art pixels `pixels` from `at` (world), in `colour`.
func _draw_pixels(at: Vector2, pixels: PackedVector2Array, count: int, colour: Color) -> void:
	var side: float = 1.0 / float(DETAIL)
	for i in count:
		draw_rect(Rect2(at + pixels[i] * side, Vector2(side, side)), colour)
