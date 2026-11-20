extends RefCounted
## A live beam's sound (docs/milestones/sound.md, "Hits by carrier"): while a beam is on, its card's
## held sound (`CarrierCard.held_sound`: the beam's soft hum) loops from its caster, and each
## infusion on it adds its own quiet loop (`ElementBase.held_hint`, HINT_VOLUME under the hum, at
## most MOST_HINTS), so a fire beam hums with a low roar in it and a frost beam with a ring of glass.
## Feel calls `hold` once a frame for each live beam it draws; each hold lasts RENEW seconds and is
## taken over by the next frame's, so the sound goes on while the beam does and fades (Audio's
## fade) within RENEW of it ending, with no event of its own to wait for.
##
## Feel decides who is heard (`volume`: an enemy's beam is quieter, as its cast is). One held sound
## a caster and id (`HeldSounds`): two beams of one caster are one hum. Each card's sound is read
## from the registry once, then kept: a frame allocates nothing.

const HeldSoundsScript := preload("res://gameplay/feel/held_sounds.gd")

## How long one frame's hold lasts (seconds): a few frames, so a hitch does not cut the hum, and
## short, so it ends with its beam.
const RENEW: float = 0.2
## How far under the hum an infusion's loop plays (decibels): a colour on it, never a second hum.
const HINT_VOLUME: float = -8.0
## The most infusion loops one beam plays.
const MOST_HINTS: int = 2
## The registry folder the cards are in.
const SPELL_FOLDER: StringName = &"spells"

## The held sounds they play through, and the registry the cards are read from (anything with
## `get_resource(folder, id)`; null: no beam sounds).
var held: HeldSoundsScript = null
var registry: Object = null:
	set(value):
		registry = value
		_sound_of.clear()

## Each card's held sound by its id (a carrier's `held_sound`, an infusion's `held_hint`; `&""` for none).
var _sound_of: Dictionary[StringName, StringName] = {}


## Holds, for RENEW seconds, the sound of a beam of the carrier card `card` with the infusions
## `elements` (element card ids, in slot order) cast by `caster`, following `follow` (null: at
## `at`), `volume` decibels on top of its sounds' own. Returns how many sounds it holds.
func hold(card: StringName, elements: Array[StringName], caster: int, follow: Node2D, at: Vector2, volume: float = 0.0) -> int:
	if held == null:
		return 0
	var hum: StringName = _card_sound(card)
	if hum == &"":
		return 0
	var started: int = 0
	if held.hold(hum, HeldSoundsScript.Until.SECONDS, caster, 0, follow, at, RENEW, volume) != 0:
		started += 1
	var hints: int = 0
	for element: StringName in elements:
		if hints >= MOST_HINTS:
			break
		var hint: StringName = _card_sound(element)
		if hint == &"":
			continue
		hints += 1
		if held.hold(hint, HeldSoundsScript.Until.SECONDS, caster, 0, follow, at, RENEW, volume + HINT_VOLUME) != 0:
			started += 1
	return started


## The held sound the card `card` names (a carrier's `held_sound`, an infusion's `held_hint`), read once.
func _card_sound(card: StringName) -> StringName:
	if card == &"":
		return &""
	var known: Variant = _sound_of.get(card)
	if known != null:
		return known as StringName
	var sound: StringName = &""
	if registry != null and registry.has_method(&"get_resource"):
		var resource: Resource = registry.call(&"get_resource", SPELL_FOLDER, card) as Resource
		if resource is CarrierCard:
			sound = (resource as CarrierCard).held_sound
		elif resource is ElementBase:
			sound = (resource as ElementBase).held_hint
	_sound_of[card] = sound
	return sound
