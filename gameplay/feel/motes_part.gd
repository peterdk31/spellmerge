extends RefCounted
## A cue's `motes` part as typed fields (`Spectacle.prepare_motes_part`; `CueBase` names each key): its kind
## (`spell`, `surface` or a kind's id), `colours`, `count` (-1: the kinds' own), `reach` (-1: none),
## `radius`, `spread` (-1: the kind's own), `up`, `ring`, `often`, `way`, `below`, and its exact
## `color` (alpha 0: none).
## Its `lasts` is its `for` (0: thrown at once; else a jet, `jets.gd`).

const MotesPartScript := preload("res://gameplay/feel/motes_part.gd")

var named: StringName = &"spell"
var colours: StringName = &""
var count: int = -1
var reach: float = -1.0
var radius: float = 0.0
var spread: float = -1.0
var up: float = 1.0
var ring: bool = false
var often: bool = false
## Its `share` (-1: none; a shed's, which is `often` too).
var share: float = -1.0
## In the body's own colour (`CueContext.body`), as a flash's `body`.
var body: bool = false
## In the caster's ramp without the cards, as a flash's `bare`.
var bare: bool = false
var way: StringName = &"aim"
var below: float = 0.0
var color: Color = Color(0.0, 0.0, 0.0, 0.0)
## Where on the cue's line it is thrown from (`along`, 0 to 1; -1: the cue's point), whether
## from all along the line (`line`), and its `life` (times its kinds' own lives) (S6 item 9).
var place: float = -1.0
var line: bool = false
var life: float = 1.0
## A named kind's index in the pool `pool_seen` (-1: none), whether it is a surface kind, and
## its own count, kept for that pool.
var pool_seen: Object = null
var kind_at: int = -1
var kind_surface: bool = false
var kind_count: int = 1
## Seconds it pours for (`for`; 0: all at once), and for a jet's copy, where the remainder of a
## frame's share starts among its spell's kinds (turning, so no kind is short in all).
var lasts: float = 0.0
var turn: int = 0
## How wide a cloud round the cue's point its motes leave from, each aimed at the end of the cue's
## line, there to meet (`gather`; 0: none).
var gather: float = 0.0


## Takes every field of `other` (a jet's own copy of the part it pours, `jets.gd`).
func copy_from(other: RefCounted) -> void:
	var from: MotesPartScript = other as MotesPartScript
	if from == null:
		push_error("MotesPart.copy_from: %s is no motes part" % other)
		return
	named = from.named
	colours = from.colours
	count = from.count
	reach = from.reach
	radius = from.radius
	spread = from.spread
	up = from.up
	ring = from.ring
	often = from.often
	share = from.share
	body = from.body
	bare = from.bare
	way = from.way
	below = from.below
	color = from.color
	place = from.place
	line = from.line
	life = from.life
	pool_seen = from.pool_seen
	kind_at = from.kind_at
	kind_surface = from.kind_surface
	kind_count = from.kind_count
	lasts = from.lasts
	turn = from.turn
	gather = from.gather
