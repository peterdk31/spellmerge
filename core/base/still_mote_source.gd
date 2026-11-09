class_name StillMoteSource
extends Resource
## One stream of motes a still carrier card's shots give off while they stand (the owner,
## 2026-11-09: "use motes for everything you can"; docs/milestones/carrier-looks-fixes.md, phase 3):
## a card lists as many as its look needs (`FormBase.look_motes`: a wall's stream off its seam, a
## pool's motes off its mire and the drops of its splash, a rune's drips and the motes rising off its
## ring once armed), and Feel
## gives each off (`gameplay/feel/still_motes.gd`) by these numbers alone: no case per carrier.
## Where they leave from is in the card's `look_shape` (its hit size as drawn), so its shader and its
## motes are shaped alike.

## Where its motes leave from: anywhere on the oval of the card's look shape (a pool's surface), on
## the oval's rim (a rune's ring), along its piece of the row below its middle (a wall's seam), or
## its middle.
const FROM_AREA: int = 0
const FROM_ROW: int = 1
const FROM_RIM: int = 2
const FROM_MIDDLE: int = 3

## The most a second a shot gives off of one stream.
const MOST_RATE: float = 120.0

## The mote kind (a `MoteKind` id, content/motes).
@export var kind: StringName = &""
## How many a second each shot gives off (each piece of a solid one, a wall's), in full.
@export var rate: float = 0.0
@export_enum("area", "row", "rim", "middle") var from: int = FROM_AREA
## How high over where it leaves from a mote shows, in the card's hit size as drawn (0 on the
## floor): a drip shows at the crystal's foot and falls by its kind's own gravity.
@export var height: float = 0.0
## Seconds after its shot is placed that it starts giving off (a rune's once armed, 1 s), and that
## it stops (a pool's splash, its first moments; 0 for never): both at most
## `ProjectileManager.STILL_START` (its still clock tells no more).
@export var start: float = 0.0
@export var stop: float = 0.0
## Pixels between the places along its row or rim a mote may leave from, on the world's grid so the
## pieces of a row line up (the shield's spacing, 3.4); 0 for anywhere.
@export var spacing: float = 0.0


## What is wrong with it for the card `card`, one line each (empty when nothing is).
func problems(card: StringName) -> PackedStringArray:
	var found := PackedStringArray()
	if kind == &"":
		found.append("%s: a look mote source names no mote kind" % card)
	if rate <= 0.0:
		found.append("%s: look motes '%s' at a rate of %s a second are never given off" % [card, kind, rate])
	elif rate > MOST_RATE:
		found.append("%s: look motes '%s' at %s a second: at most %s a shot" % [card, kind, rate, MOST_RATE])
	if height < 0.0 or start < 0.0 or stop < 0.0 or spacing < 0.0:
		found.append("%s: look motes '%s': height, start, stop and spacing are never below 0" % [card, kind])
	if stop > 0.0 and stop <= start:
		found.append("%s: look motes '%s' stop at %s s, before they start at %s s" % [card, kind, stop, start])
	return found
