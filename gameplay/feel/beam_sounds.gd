extends RefCounted
## A live beam's sound (docs/milestones/sound.md, "Hits by carrier"): while a beam is on, its card's
## held sound (`CarrierCard.held_sound`: the beam's soft hum) loops from its caster, and each
## infusion on it adds its own quiet loop (`ElementBase.held_hint`, HINT_VOLUME under the hum, at
## most MOST_HINTS a caster), so a fire beam hums with a low roar in it and a frost beam with a ring
## of glass. Feel calls `new_frame` once a frame, then `hold` for each live beam it draws; each hold
## lasts RENEW seconds and is taken over by the next frame's, so the sound goes on while the beam
## does and fades (Audio's fade) within RENEW of it ending, with no event of its own to wait for.
##
## A frame holds at most MOST_HOLDS sounds, half Audio's held slots: a beam's hold has the least
## time left of any held sound, so past its share it would take the slot of another beam not yet
## renewed this frame, and that one the next, every frame (the review's finding). The beams past it
## are silent for that frame instead, and a wind-up's or a phase's held sound keeps its slot.
##
## Feel decides who is heard and how loud (`volume`: an enemy's beam is quieter, as its cast is; a
## dissolving beam fades). One held sound a caster and id (`HeldSounds`): two beams of one caster
## are one hum. Each card's sound is read once (`cards`): a frame allocates nothing.

const HeldSoundsScript := preload("res://gameplay/feel/held_sounds.gd")
const CardSoundsScript := preload("res://gameplay/feel/card_sounds.gd")

## How long one frame's hold lasts (seconds): a few frames, so a hitch does not cut the hum, and
## short, so it ends with its beam.
const RENEW: float = 0.2
## How far under the hum an infusion's loop plays (decibels): a colour on it, never a second hum.
const HINT_VOLUME: float = -8.0
## The most infusion loops one caster's beams play in a frame.
const MOST_HINTS: int = 2
## The most sounds the beams hold in a frame: half Audio's held slots.
const MOST_HOLDS: int = HeldSoundsScript.SLOTS / 2

## The held sounds they play through.
var held: HeldSoundsScript = null
## The cards' sounds, read once (Feel hands its own, shared with its casts and hits).
var cards: CardSoundsScript = CardSoundsScript.new()
## The registry the cards are read from (anything with `get_resource(folder, id)`; null: no beam
## sounds): `cards`' registry.
var registry: Object:
	get:
		return cards.registry
	set(value):
		cards.registry = value

## The holds made this frame, and the casters whose beams held hints this frame with how many (the
## first `_casters` of each list).
var _holds: int = 0
var _casters: int = 0
var _hint_caster: PackedInt32Array = PackedInt32Array()
var _hint_count: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	_hint_caster.resize(MOST_HOLDS)
	_hint_count.resize(MOST_HOLDS)


## A new frame: its beams may hold MOST_HOLDS sounds again.
func new_frame() -> void:
	_holds = 0
	_casters = 0


## True when this frame's beams hold all the sounds they may (`hold` would refuse another): Feel
## then asks nothing more of a beam for its sound.
func full() -> bool:
	return held == null or _holds >= MOST_HOLDS


## Holds, for RENEW seconds, the sound of a beam of the carrier card `card` with the infusions
## `elements` (element card ids, in slot order) cast by `caster`, following `follow` (null: at
## `at`), `volume` decibels on top of its sounds' own. Returns how many sounds it holds.
func hold(card: StringName, elements: Array[StringName], caster: int, follow: Node2D, at: Vector2, volume: float = 0.0) -> int:
	if held == null or _holds >= MOST_HOLDS:
		return 0
	var hum: StringName = cards.sound_of(card, CardSoundsScript.Use.HELD)
	if hum == &"":
		return 0
	var started: int = 0
	_holds += 1
	if held.hold(hum, HeldSoundsScript.Until.SECONDS, caster, 0, follow, at, RENEW, volume) != 0:
		started += 1
	var row: int = _row_of(caster)
	for element: StringName in elements:
		if row < 0 or _hint_count[row] >= MOST_HINTS or _holds >= MOST_HOLDS:
			break
		var hint: StringName = cards.sound_of(element, CardSoundsScript.Use.HELD)
		if hint == &"":
			continue
		_hint_count[row] += 1
		_holds += 1
		if held.hold(hint, HeldSoundsScript.Until.SECONDS, caster, 0, follow, at, RENEW, volume + HINT_VOLUME) != 0:
			started += 1
	return started


## The row of `caster` in this frame's hint counts, made when it is new (-1: no room).
func _row_of(caster: int) -> int:
	for i in _casters:
		if _hint_caster[i] == caster:
			return i
	if _casters >= MOST_HOLDS:
		return -1
	_hint_caster[_casters] = caster
	_hint_count[_casters] = 0
	_casters += 1
	return _casters - 1
