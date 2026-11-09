class_name MoteKind
extends Resource
## A kind of mote (docs/milestones/spell-spectacle.md, P1): single-pixel particles with no game
## logic that Feel throws where things happen. One file per kind in `content/motes/<id>.tres`;
## the registry finds it by its `id`, so a new kind is a new file and no list is edited.
##
## A kind belongs to cards (docs/milestones/spell-spectacle-2.md, S2): it is the motes of every
## card it names by id (`cards`: a form, an element or a modifier), and of every card whose
## look it names (`look_ids`) that no kind names by id. So a card gets motes of its
## own with one new file naming it (the card's file is not touched), a card that no kind names
## sheds its look layer's, and a shot whose cards have none sheds the kinds of layer 0. A spell
## sheds every kind of its cards, its burst split between them. A `surface` kind belongs to no
## card: it is what a struck surface (a wall) sheds, in the colours of the room's art
## (`RoomBase.surface_colors`; a room may name its own, `RoomBase.surface_kinds`). A kind that
## names none of these is thrown only where something names it (a cue's `motes` part, a room's
## `surface_kinds`). Its colours are never here: a spell's motes cool through the shot's own
## ramp, a surface's through the room's.
##
## The numbers say how one flies (`gameplay/feel/mote.gdshader` works the flight out from them,
## `Motes.flight` the same on the CPU) and how many a burst throws, how fast and for how long.

## The longest life a mote has (s; the motes write a life as a 255th of it), and the cards' look
## layers a kind may name (1 to LOOK_LAYERS; 0 a shot with none): core/projectiles' look kinds.
const LIFE_MAX: float = 4.0
const LOOK_LAYERS: int = preload("res://core/projectiles/projectile_manager.gd").LOOK_COUNT - 1

## Unique name, also its file name.
@export var id: StringName = &""
## The cards (forms, elements, modifiers: their ids) this kind is the motes of, whatever their look
## layer.
@export var cards: Array[StringName] = []
## The cards' looks (`look_id` of an element or modifier, `LookNames`) this kind is the motes of,
## for the cards no kind names by id; `plain` for a shot with no look that has a kind.
@export var look_ids: Array[StringName] = []
## `look_ids` as their numbers, the LOOK_* kinds of core/projectiles (`plain` 0): what Feel reads.
var look_layers: PackedInt32Array:
	get:
		return LookNames.layers_of(look_ids)
	set(value):
		look_ids = LookNames.names_of(value)
## Thrown off a struck surface in the room's colours, not by a spell's cards.
@export var surface: bool = false
## Given off along every dash's path (its speed streaks; docs/milestones/spell-spectacle-2.md,
## S5), in the dashing actor's colours, whatever its cards (theirs are given off beside it).
@export var dash_path: bool = false
## A shot's tail (docs/milestones/spell-spectacle-2.md, S5 step 4: tails as motes): laid along
## every flying shot's path by distance, in the shot's own colours, whatever its cards (theirs are
## given off beside it). Each shot is laid in one of the tail kinds, picked by its sequence
## (`ProjectileManager.tail_code`; `Motes.tail_kind_of`: the kinds in id order, A, B, C).
@export var tail: bool = false
## The floor mark (a `MarkKind` id, content/marks) each of its motes leaves where it comes to
## rest, in its own colours, once it lies still (docs/milestones/spell-spectacle.md, P2b: settled
## motes); empty for none. Only a kind that falls (gravity above 0) comes to rest.
@export var settles: StringName = &""

@export_group("Flight")
## Down the fake height, in px/s/s; below 0 it rises (an ember), 0 it keeps its height.
@export_range(-200.0, 1000.0, 1.0) var gravity: float = 300.0
## Slowing along the floor, per second.
@export_range(0.0, 20.0, 0.1) var drag: float = 2.5
## The share of its falling speed a landing bounces back (once; then it lies still).
@export_range(0.0, 0.9, 0.05) var bounce: float = 0.3
## A sideways sway, in pixels, and its rate in radians a second.
@export_range(0.0, 16.0, 0.5) var wobble: float = 0.0
@export_range(0.0, 30.0, 0.5) var wobble_rate: float = 0.0
## How strongly it glows while it is hot (its first two shades); 0 for none.
@export_range(0.0, 2.0, 0.1) var glow: float = 0.0
## The shade it starts at: 0 white-hot, 1 light, 2 base, 3 shadow. It cools to shadow over its life.
@export_range(0, 3) var shade_from: int = 1

@export_group("Shape")
## What one looks like, drawn as text: one or more frames, each a picture of up to SHAPE_SIZE x
## SHAPE_SIZE pixels, one row a line, frames apart by a blank line. "#" is a pixel in its shade,
## "o" one in the shade hotter (a highlight), "." none. Rows start at the left as written; the
## picture is centred on the mote (its middle column and row; the left and upper of two). A frame
## of dots is a blink; not every frame may be one. A plus with a bright rim, then a pixel:
##
##     .o.
##     o#o
##     .o.
##
##     #
@export_multiline var shape: String = "#"
## How its frames play: `life` through them evenly over its life, `loop` round them
## `shape_rate` a second (each mote from its own frame), `pick` one at random for each mote,
## kept.
@export_enum("life", "loop", "pick") var shape_play: String = "life"
## Frames a second when they loop.
@export_range(0.0, 30.0, 0.5) var shape_rate: float = 8.0
## The shape turns with the way the mote flies (8 ways; +x of the shape is ahead). A mote at rest
## keeps the way it was thrown.
@export var shape_turns: bool = false

@export_group("Burst")
## How many one burst throws (a shot with several kinds splits this between them).
@export_range(1, 64) var count: int = 6
## Speed along the floor, px/s, from x to y.
@export var speed: Vector2 = Vector2(40.0, 120.0)
## The spread round the burst's way, in degrees (360 all round).
@export_range(0.0, 360.0, 1.0) var spread: float = 140.0
## Speed up the fake height, px/s, from x to y.
@export var up: Vector2 = Vector2(20.0, 60.0)
## Seconds it lives, from x to y (at most Motes.LIFE_MAX).
@export var life: Vector2 = Vector2(0.5, 1.5)
## How far above the floor it starts, in pixels: the burst's point is that high.
@export_range(0.0, 32.0, 1.0) var height: float = 4.0


## The most pixels a shape is across and down, and the most frames it has (the shader's
## SHAPE_SIZE and the room in `Motes`' shape atlas).
const SHAPE_SIZE: int = 5
const SHAPE_FRAMES: int = 8
## How `shape_play` is told to the shader.
const SHAPE_PLAYS: Array[String] = ["life", "loop", "pick"]
## A shape's pixel: none, in its shade, one shade hotter.
const PIXEL_NONE: int = 0
const PIXEL_BODY: int = 1
const PIXEL_HOT: int = 2


func kind() -> StringName:
	return &"mote"


## The shape's frames, each its rows (lines with no spaces round them).
func shape_frames() -> Array[PackedStringArray]:
	var frames: Array[PackedStringArray] = []
	var rows := PackedStringArray()
	for line in shape.replace("\r", "").split("\n"):
		var row: String = line.strip_edges()
		if row.is_empty():
			if not rows.is_empty():
				frames.append(rows)
				rows = PackedStringArray()
		else:
			rows.append(row)
	if not rows.is_empty():
		frames.append(rows)
	return frames


## Frame `frame` of the shape as SHAPE_SIZE x SHAPE_SIZE pixels (PIXEL_*), row by row, the
## mote's own pixel in the middle (row and column SHAPE_SIZE / 2).
func shape_pixels(frame: int) -> PackedByteArray:
	var pixels := PackedByteArray()
	pixels.resize(SHAPE_SIZE * SHAPE_SIZE)
	var frames: Array[PackedStringArray] = shape_frames()
	if frame < 0 or frame >= frames.size():
		return pixels
	var rows: PackedStringArray = frames[frame]
	var wide: int = 0
	for row in rows:
		wide = maxi(wide, row.length())
	var middle: int = SHAPE_SIZE / 2
	var top: int = middle - (rows.size() - 1) / 2
	var left: int = middle - (wide - 1) / 2
	for r in rows.size():
		var row: String = rows[r]
		for c in row.length():
			var x: int = left + c
			var y: int = top + r
			if x < 0 or y < 0 or x >= SHAPE_SIZE or y >= SHAPE_SIZE:
				continue
			var mark: String = row[c]
			pixels[y * SHAPE_SIZE + x] = PIXEL_BODY if mark == "#" else (PIXEL_HOT if mark == "o" else PIXEL_NONE)
	return pixels


## What is wrong with this kind, in words; empty when it is fine.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if id == &"":
		found.append("a mote kind needs an id")
	if surface and (not look_ids.is_empty() or not cards.is_empty()):
		found.append("%s: a surface kind belongs to no card, so it names no cards and no looks" % id)
	if dash_path and (surface or not look_ids.is_empty() or not cards.is_empty()):
		found.append("%s: a dash's path kind belongs to no card and no surface" % id)
	if tail and (surface or dash_path or not look_ids.is_empty() or not cards.is_empty()):
		found.append("%s: a tail kind belongs to no card, no surface and no dash" % id)
	for card in cards:
		if card == &"":
			found.append("%s: a card it names has no id" % id)
	for look in look_ids:
		if not LookNames.known(look):
			found.append("%s: %s is not a look (%s)" % [id, look, ", ".join(LookNames.NAMES)])
	if settles != &"" and gravity <= 0.0:
		found.append("%s: only a kind that falls comes to rest, so one that rises leaves no mark" % id)
	if speed.x > speed.y or up.x > up.y or life.x > life.y:
		found.append("%s: speed, up and life go from the least (x) to the most (y)" % id)
	if life.x <= 0.0 or life.y > LIFE_MAX:
		found.append("%s: life is above 0 and at most %d s" % [id, LIFE_MAX])
	found.append_array(_shape_problems())
	return found


func _shape_problems() -> PackedStringArray:
	var found := PackedStringArray()
	var frames: Array[PackedStringArray] = shape_frames()
	if frames.is_empty() or frames.size() > SHAPE_FRAMES:
		found.append("%s: a shape has 1 to %d frames, apart by a blank line" % [id, SHAPE_FRAMES])
	if not SHAPE_PLAYS.has(shape_play):
		found.append("%s: shape_play '%s' is not one of %s" % [id, shape_play, SHAPE_PLAYS])
	var drawn: bool = false
	for f in frames.size():
		var rows: PackedStringArray = frames[f]
		if rows.size() > SHAPE_SIZE:
			found.append("%s: shape frame %d is more than %d rows" % [id, f + 1, SHAPE_SIZE])
		for row in rows:
			if row.length() > SHAPE_SIZE:
				found.append("%s: shape row '%s' is more than %d pixels" % [id, row, SHAPE_SIZE])
			for mark in row:
				if not "#o.".contains(mark):
					found.append("%s: shape mark '%s' is not one of # o ." % [id, mark])
				drawn = drawn or mark == "#" or mark == "o"
	if not frames.is_empty() and not drawn:
		found.append("%s: its shape draws nothing" % id)
	return found
