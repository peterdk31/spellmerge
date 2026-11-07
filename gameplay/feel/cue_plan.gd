extends RefCounted
## A cue read once for playing (`Feel.play_cue`; docs/milestones/spell-spectacle-2.md, S6 2): each
## part's player looked up by its type once, and each part prepared once by its type's `prepare`
## (`Feel.add_cue_part`), so a cue played hundreds of times a second (a shot's impact, a hit) reads
## no Dictionary key while it plays. A flash part (`flash`) is prepared into a `Flash`, its keys as
## typed fields. Feel keeps one plan a cue, made again when the cue or the part players change.

## A flash part (`CueBase`, a `flash`) as typed fields: the flash kind and its step in pixels,
## and every key the part may have.
class Flash:
	extends RefCounted
	## Feel's code for its kind (`Feel._flash_codes`).
	var kind: int = 0
	## Pixels a step of its zoom is (its kind's `step`), and its own seconds.
	var step: float = 12.0
	var seconds: float = 0.0
	var lasts_size: bool = false
	var zoom: float = 1.0
	## Its `reach` (-1 for none), that in steps of its zoom for one sized by it (-1 for none: a
	## fixed zoom, or one drawn along a length), and whether it is drawn along a length (an arc).
	var reach: float = -1.0
	var reach_steps: float = -1.0
	var along: bool = false
	## Where on the cue's line it plays (its `along` key, 0 to 1; -1: the cue's point; S6 item 9).
	var place: float = -1.0
	## How it is coloured: PAINT_*, and its own `color` for PAINT_COLOR.
	var paint: int = PAINT_CUE
	var color: Color = Color.WHITE
	## Its `way` (WAY_*).
	var way: int = WAY_AIM
	var particles: bool = false
	var if_cards: bool = false
	## The look layer it needs (0 for none), and the sizes it plays at.
	var if_layer: int = 0
	var size_over: float = -INF
	var size_upto: float = INF
	## Whether any of the gates on its cards or size is set (most flashes have none: skipped in one
	## test).
	var gated: bool = false

## A flash's colours: the cue's (its tint and cards, or its own colour when it has one), its own
## exact `color`, `plain`, `bare`, the cue's without the cards (`no_cards`), and the body's own
## colour (`body`: `CueContext.body`, white without one).
const PAINT_CUE: int = 0
const PAINT_COLOR: int = 1
const PAINT_PLAIN: int = 2
const PAINT_BARE: int = 3
const PAINT_NO_CARDS: int = 4
const PAINT_BODY: int = 5
## A part's way (`CueBase.WAYS`).
const WAY_AIM: int = 0
const WAY_BACK: int = 1
const WAY_RIGHT: int = 2
const WAY_UP: int = 3

## The cue it was made from (Feel makes it again when `cue_of` answers another).
var cue: CueBase = null
## For each part that has a player: the player and what it plays (the part, or what its type's
## `prepare` made of it).
var players: Array[Callable] = []
var prepared: Array = []
## The part types no player plays, one entry a part (`Feel._unknown_cue_part`).
var unknown: Array[StringName] = []
## Whether it has any weight (a hold, the game-wide stop, shake, a punch or a sound), and its own
## colour and power (`CueBase`), read once.
var weighted: bool = false
## Whether it holds anyone (`hold`, `hold_target`), lights by a `light` part (its flashes then light
## nothing: `CueBase.lights`), and plays at most `every` seconds apart for an actor.
var holds: bool = false
var lights: bool = false
var every: float = 0.0
var color: Color = Color(0.0, 0.0, 0.0, 0.0)
var power: float = 1.0
## What it shows when played as a hit's look (`Feel.play_cue` while a hit is shown): a hit past the
## frame's share of hit flashes skips every flash, and one whose motes do not spray skips every part
## its type says needs a spray (`Feel.add_cue_part`'s `needs_spray`), so a cue of only those parts
## shows nothing for such a hit and Feel does not play it. `shows_always`: a part that plays whatever
## the hit (a mark, a light, an unknown part, counted when played); `has_flashes`, `has_spray_parts`:
## which of the two gates it has.
var shows_always: bool = false
var has_flashes: bool = false
var has_spray_parts: bool = false


## The plan of `cue` with the players `types` (part type -> [player, prepare, needs_spray], `prepare`
## an empty Callable for a type whose player takes the part itself, `needs_spray` one for a type
## whose parts all play whatever the hit).
static func make(of: CueBase, types: Dictionary) -> RefCounted:
	var plan: RefCounted = new()
	plan.cue = of
	for part: Dictionary in of.parts:
		var type: StringName = StringName(part.get("part", "flash"))
		var row: Variant = types.get(type)
		if row == null:
			plan.unknown.append(type)
			plan.shows_always = true
			continue
		var prepare: Callable = (row as Array)[1]
		var made: Variant = prepare.call(part) if prepare.is_valid() else part
		# A part its type could not prepare (a flash Feel has not) plays nothing.
		if made == null:
			continue
		plan.players.append((row as Array)[0] as Callable)
		plan.prepared.append(made)
		var needs_spray: Callable = (row as Array)[2]
		if made is Flash:
			plan.has_flashes = true
		elif needs_spray.is_valid() and needs_spray.call(made):
			plan.has_spray_parts = true
		else:
			plan.shows_always = true
	plan.color = of.color
	plan.power = of.power
	plan.holds = of.hold > 0.0 or of.hold_target > 0.0
	plan.lights = of.lights()
	plan.every = of.every
	plan.weighted = of.hold > 0.0 or of.hold_target > 0.0 or of.stop_game > 0.0 or of.shake > 0.0 or of.kick > 0.0 or of.sound != &""
	return plan


## The flash part `part` as a `Flash`, with `flashes` Feel's rows of the flash kinds by id
## (`Feel._flash_rows`: its code, pixels a step, seconds, and true for one drawn along a length).
## Null for a kind not in it (the content test names it).
static func flash_of(part: Dictionary, flashes: Dictionary) -> Flash:
	var row: Array = flashes.get(StringName(part.get("flash", "")), []) as Array
	if row.is_empty():
		return null
	var flash := Flash.new()
	flash.kind = int(row[0])
	flash.step = float(row[1])
	flash.seconds = float(part.get("seconds", row[2]))
	flash.along = bool(row[3])
	flash.place = clampf(float(part["along"]), 0.0, 1.0) if part.has("along") else -1.0
	flash.lasts_size = bool(part.get("lasts_size", false))
	flash.zoom = float(part.get("zoom", 1.0))
	flash.reach = float(part["reach"]) if part.has("reach") else -1.0
	flash.reach_steps = flash.reach / flash.step if flash.reach >= 0.0 and not flash.along else -1.0
	if part.has("color"):
		flash.paint = PAINT_COLOR
		flash.color = part["color"] as Color
	elif bool(part.get("plain", false)):
		flash.paint = PAINT_PLAIN
	elif bool(part.get("bare", false)):
		flash.paint = PAINT_BARE
	elif bool(part.get("body", false)):
		flash.paint = PAINT_BODY
	elif bool(part.get("no_cards", false)):
		flash.paint = PAINT_NO_CARDS
	match StringName(part.get("way", "aim")):
		&"back":
			flash.way = WAY_BACK
		&"right":
			flash.way = WAY_RIGHT
		&"up":
			flash.way = WAY_UP
	flash.particles = bool(part.get("particles", false))
	flash.if_cards = bool(part.get("if_cards", false))
	flash.if_layer = int(part.get("if_layer", 0))
	flash.size_over = float(part.get("if_size_over", -INF))
	flash.size_upto = float(part.get("if_size_upto", INF))
	flash.gated = flash.if_cards or flash.if_layer > 0 or part.has("if_size_over") or part.has("if_size_upto")
	return flash
