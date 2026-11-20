extends RefCounted
## The sounds a spell card names, read from the registry once each (docs/milestones/sound.md,
## "Carrier sounds" and "Hits by carrier"): a carrier's `cast_sound`, `hit_sound` and `held_sound`,
## an infusion's `cast_hint` and `held_hint`. Feel's cast sounds (`cast_sounds.gd`), its hits and
## its beam sounds (`beam_sounds.gd`) share one, so each card is read from the registry once in
## all; a card that is not of the kind a sound is asked of names none (`&""`).
##
## A sound once read is kept, by its card and what it is: nothing is allocated after a card's first.

## What a card's sound is for: which of its fields is read.
enum Use { CAST, HIT, HELD }

## The registry folder the cards are in.
const SPELL_FOLDER: StringName = &"spells"

## The registry the cards are read from (anything with `get_resource(folder, id)`; null: every card
## names none). Setting it forgets what was read.
var registry: Object = null:
	set(value):
		registry = value
		for kept: Dictionary in _of:
			kept.clear()

## The sounds read so far, one dictionary a `Use` (a card's id to its sound).
var _of: Array[Dictionary] = [{}, {}, {}]


## The sound the card `card` names for `use`: a carrier's `cast_sound`, `hit_sound` or
## `held_sound`; an infusion's `cast_hint` (CAST) or `held_hint` (HELD); `&""` for none.
func sound_of(card: StringName, use: Use) -> StringName:
	if card == &"":
		return &""
	var kept: Dictionary = _of[use]
	var known: Variant = kept.get(card)
	if known != null:
		return known as StringName
	var sound: StringName = &""
	if registry != null and registry.has_method(&"get_resource"):
		var resource: Resource = registry.call(&"get_resource", SPELL_FOLDER, card) as Resource
		if resource is CarrierCard:
			var carrier: CarrierCard = resource as CarrierCard
			match use:
				Use.CAST:
					sound = carrier.cast_sound
				Use.HIT:
					sound = carrier.hit_sound
				Use.HELD:
					sound = carrier.held_sound
		elif resource is ElementBase:
			var element: ElementBase = resource as ElementBase
			match use:
				Use.CAST:
					sound = element.cast_hint
				Use.HELD:
					sound = element.held_hint
	kept[card] = sound
	return sound
