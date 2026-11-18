extends RefCounted
## Feel's cast sounds (docs/milestones/sound.md, "Carrier sounds"): what a cast sounds as it leaves
## its staff. Each carrier has its own sound (`CarrierCard.cast_sound`; the shared `cast` for a card
## with none, or a cast of no carrier card), and each infusion the cast carries adds its faint hint
## over it (`ElementBase.cast_hint`, baked quiet and played HINT_VOLUME under it), so a fire bolt is a bolt with a breath of
## flame and a frost wall a wall with a ring of glass.
##
## Feel decides who is heard and how loud (`play`'s `volume`: an enemy's cast is quieter, a prop's
## and a staff's with a cast cue of its own are not played here); this plays one cast: its carriers'
## sounds, each once (a Triple's three bolts are one bolt's sound), then its infusions' hints, each
## once, at most MOST_HINTS. Each card's sound is read from the registry once, then kept: a cast
## allocates nothing.

const AudioScript := preload("res://core/audio/audio.gd")

## The sound of a cast of a carrier card that names none, or of no carrier card.
const FALLBACK: StringName = &"cast"
## How far under the cast its infusions' hints play (decibels): a hint, never a second cast.
const HINT_VOLUME: float = -6.0
## The most sounds one cast plays: its carriers' and its hints' together.
const MOST_SOUNDS: int = 5
## The most hints one cast plays.
const MOST_HINTS: int = 3
## The registry folder the cards are in.
const SPELL_FOLDER: StringName = &"spells"

## The Audio service they play on, and the registry the cards are read from (anything with
## `get_resource(folder, id)`; null: every cast is `FALLBACK` with no hints).
var audio: AudioScript = null
var registry: Object = null:
	set(value):
		registry = value
		_sound_of.clear()

## Each card's sound by its id (a carrier's cast sound, an infusion's hint; `&""` for none), read once.
var _sound_of: Dictionary[StringName, StringName] = {}
## The sounds the cast being played has played so far (the first `_played_count`).
var _played: Array[StringName] = []
var _played_count: int = 0


func _init() -> void:
	_played.resize(MOST_SOUNDS)


## Plays the cast `cast` (a `CompiledCast`) leaving from `at`, `volume` decibels on top of its
## sounds' own: its carriers' sounds, then its infusions' hints. Returns how many sounds it started.
func play(cast: CompiledCast, at: Vector2, volume: float = 0.0) -> int:
	if audio == null or cast == null or cast.group == null:
		return 0
	_played_count = 0
	var started: int = 0
	for spell: CompiledSpell in cast.group.spells:
		var sound: StringName = carrier_sound(spell.carrier_card_id)
		if _play_once(sound, at, volume):
			started += 1
	var hints: int = 0
	for spell: CompiledSpell in cast.group.spells:
		for element: StringName in spell.element_ids:
			if hints >= MOST_HINTS:
				return started
			if _play_once(hint_sound(element), at, volume + HINT_VOLUME):
				started += 1
				hints += 1
	return started


## The cast sound of the carrier card `card`: its own `cast_sound`, else FALLBACK.
func carrier_sound(card: StringName) -> StringName:
	var sound: StringName = _card_sound(card)
	return sound if sound != &"" else FALLBACK


## The hint of the infusion card `card` (`&""`: none).
func hint_sound(card: StringName) -> StringName:
	return _card_sound(card)


## Plays `sound` unless this cast has played it already or played MOST_SOUNDS; whether it started.
func _play_once(sound: StringName, at: Vector2, volume: float) -> bool:
	if sound == &"" or _played_count >= MOST_SOUNDS:
		return false
	for i in _played_count:
		if _played[i] == sound:
			return false
	_played[_played_count] = sound
	_played_count += 1
	return audio.play(sound, at, volume) >= 0


## The sound the card `card` names (a carrier's `cast_sound`, an infusion's `cast_hint`), read once.
func _card_sound(card: StringName) -> StringName:
	if card == &"":
		return &""
	var known: Variant = _sound_of.get(card)
	if known != null:
		return known as StringName
	if registry == null or not registry.has_method(&"get_resource"):
		return &""
	var resource: Resource = registry.call(&"get_resource", SPELL_FOLDER, card) as Resource
	var sound: StringName = &""
	if resource is CarrierCard:
		sound = (resource as CarrierCard).cast_sound
	elif resource is ElementBase:
		sound = (resource as ElementBase).cast_hint
	_sound_of[card] = sound
	return sound
