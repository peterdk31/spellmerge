extends RefCounted
## A cue read once for playing (`Feel.play_cue`; docs/milestones/spell-spectacle-2.md, S6 2): each
## part's player looked up by its type once, and each part prepared once by its type's `prepare`
## (`Feel.add_cue_part`), so a cue played hundreds of times a second (a shot's impact, a hit) reads
## no Dictionary key while it plays. A flash part (`effect`) is prepared into a `Flash`, its keys as
## typed fields. Feel keeps one plan a cue, made again when the cue or the part players change.

## A flash part (`CueBase`, an `effect`) as typed fields: the effect kind and its step in pixels,
## and every key the part may have.
class Flash:
	extends RefCounted
	var kind: int = 0
	## Pixels a step of its zoom is (CUE_EFFECTS' second column), and its own seconds.
	var step: float = 12.0
	var seconds: float = 0.0
	var lasts_size: bool = false
	var zoom: float = 1.0
	## Its `reach` (-1 for none), and whether it is drawn along a length (an arc).
	var reach: float = -1.0
	var along: bool = false
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
	## Whether any of the four gates above is set (most flashes have none: skipped in one test).
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


## The plan of `cue` with the players `types` (part type -> [player, prepare], `prepare` an empty
## Callable for a type whose player takes the part itself).
static func make(of: CueBase, types: Dictionary) -> RefCounted:
	var plan: RefCounted = new()
	plan.cue = of
	for part: Dictionary in of.parts:
		var type: StringName = StringName(part.get("part", "effect"))
		var row: Variant = types.get(type)
		if row == null:
			plan.unknown.append(type)
			continue
		var prepare: Callable = (row as Array)[1]
		plan.players.append((row as Array)[0] as Callable)
		plan.prepared.append(prepare.call(part) if prepare.is_valid() else part)
	plan.color = of.color
	plan.power = of.power
	plan.holds = of.hold > 0.0 or of.hold_target > 0.0
	plan.lights = of.lights()
	plan.every = of.every
	plan.weighted = of.hold > 0.0 or of.hold_target > 0.0 or of.stop_game > 0.0 or of.shake > 0.0 or of.kick > 0.0 or of.sound != &""
	return plan


## The flash part `part` as a `Flash`, with `effects` Feel's table of effect names (CUE_EFFECTS:
## kind, pixels a step, seconds, and a fourth column for one drawn along a length). Null for an
## effect not in it (`CueBase.problems` names it in content).
static func flash_of(part: Dictionary, effects: Dictionary) -> Flash:
	var row: Array = effects.get(StringName(part.get("effect", "")), []) as Array
	if row.is_empty():
		return null
	var flash := Flash.new()
	flash.kind = int(row[0])
	flash.step = float(row[1])
	flash.seconds = float(part.get("seconds", row[2]))
	flash.along = row.size() > 3
	flash.lasts_size = bool(part.get("lasts_size", false))
	flash.zoom = float(part.get("zoom", 1.0))
	flash.reach = float(part["reach"]) if part.has("reach") else -1.0
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
	flash.gated = flash.particles or flash.if_cards or flash.if_layer > 0 or part.has("if_size_over") or part.has("if_size_upto")
	return flash
