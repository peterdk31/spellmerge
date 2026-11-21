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
## The ring's radius and the crack's half length (pixels).
const RING: int = 7
const CRACK: int = 5
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
## The crack's and the ring's pixels from a rune's middle (the ring in order round from the top).
var _crack: PackedVector2Array = PackedVector2Array()
var _ring: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	_crack = crack_pixels()
	_ring = ring_pixels()


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


## The crack's pixels from a rune's middle: a jagged stroke from upper left to lower right through it.
static func crack_pixels() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(-CRACK, CRACK + 1):
		# A step aside every third pixel: a crack, not a ruled line.
		out.append(Vector2(i, i + (1 if posmod(i, 3) == 0 else 0)))
	return out


## The ring's pixels from a rune's middle, RING round, in order clockwise from the top (each once).
static func ring_pixels() -> PackedVector2Array:
	var found: Array[Vector2] = []
	for y in range(-RING - 1, RING + 2):
		for x in range(-RING - 1, RING + 2):
			if absf(Vector2(x, y).length() - float(RING)) < 0.5:
				found.append(Vector2(x, y))
	found.sort_custom(func(a: Vector2, b: Vector2) -> bool: return _round_from_top(a) < _round_from_top(b))
	return PackedVector2Array(found)


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
	for pixel: Vector2 in _crack:
		draw_rect(Rect2(at + pixel, Vector2.ONE), crack_shade)
	var drawn: int = 0 if frame <= 1 else _ring.size() * (frame - 1) / (FOUND_FRAMES - 1)
	for i in drawn:
		draw_rect(Rect2(at + _ring[i], Vector2.ONE), tint[1])
