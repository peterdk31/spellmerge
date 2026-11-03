class_name MoteKind
extends Resource
## A kind of mote (docs/milestones/spell-spectacle.md, P1): single-pixel particles with no game
## logic that Feel throws where things happen. One file per kind in `content/motes/<id>.tres`;
## the registry finds it by its `id`, so a new kind is a new file and no list is edited.
##
## A kind belongs to the cards' looks: it is the motes of every card whose `look_layer` it names
## (`look_layers`), so a fire shot sheds the kind that names fire's layer and a new card brings
## its motes through the look it already has. A shot whose cards name no kind's layer sheds the
## kinds of layer 0. A `surface` kind belongs to no card: it is what a struck surface (a wall)
## sheds, in the colours of the room's art (`RoomBase.surface_colors`). Its colours are never
## here: a spell's motes cool through the shot's own ramp, a surface's through the room's.
##
## The numbers say how one flies (`gameplay/feel/mote.gdshader` works the flight out from them,
## `Motes.flight` the same on the CPU) and how many a burst throws, how fast and for how long.

## Unique name, also its file name.
@export var id: StringName = &""
## The cards' look layers (`look_layer` of an element or modifier; the LOOK_* kinds of
## core/projectiles) this kind is the motes of; 0 for a shot with no layer that has a kind.
@export var look_layers: PackedInt32Array = PackedInt32Array()
## Thrown off a struck surface in the room's colours, not by a spell's cards.
@export var surface: bool = false

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
## What one looks like: one or more frames of up to SHAPE_SIZE x SHAPE_SIZE pixels, centred on
## the mote (the middle column and row; the left and upper of two), rows split by "/". "#" is a
## pixel in its shade, "o" one in the shade hotter (a highlight), "." or " " none. A frame may be
## empty (a blink), not every frame. `".o./o#o/.o."` is a plus with a bright rim, `"##o"` a
## streak with a bright head.
@export var shape: PackedStringArray = PackedStringArray(["#"])
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


## Frame `frame` of the shape as SHAPE_SIZE x SHAPE_SIZE pixels (PIXEL_*), row by row, the
## mote's own pixel in the middle (row and column SHAPE_SIZE / 2).
func shape_pixels(frame: int) -> PackedByteArray:
	var pixels := PackedByteArray()
	pixels.resize(SHAPE_SIZE * SHAPE_SIZE)
	if frame < 0 or frame >= shape.size():
		return pixels
	var rows: PackedStringArray = shape[frame].split("/")
	var middle: int = SHAPE_SIZE / 2
	var top: int = middle - (rows.size() - 1) / 2
	for r in rows.size():
		var row: String = rows[r]
		var left: int = middle - (row.length() - 1) / 2
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
	if surface and not look_layers.is_empty():
		found.append("%s: a surface kind belongs to no card, so it names no look layers" % id)
	if not surface and look_layers.is_empty():
		found.append("%s: a spell's kind names the look layers it is the motes of (0 for a shot with none)" % id)
	for layer in look_layers:
		if layer < 0 or layer > 21:
			found.append("%s: look layer %d is not a LOOK_* kind (0-21)" % [id, layer])
	if speed.x > speed.y or up.x > up.y or life.x > life.y:
		found.append("%s: speed, up and life go from the least (x) to the most (y)" % id)
	if life.x <= 0.0 or life.y > 4.0:
		found.append("%s: life is above 0 and at most 4 s" % id)
	found.append_array(_shape_problems())
	return found


func _shape_problems() -> PackedStringArray:
	var found := PackedStringArray()
	if shape.is_empty() or shape.size() > SHAPE_FRAMES:
		found.append("%s: a shape has 1 to %d frames" % [id, SHAPE_FRAMES])
	if not SHAPE_PLAYS.has(shape_play):
		found.append("%s: shape_play '%s' is not one of %s" % [id, shape_play, SHAPE_PLAYS])
	var drawn: bool = false
	for frame in shape:
		var rows: PackedStringArray = frame.split("/")
		if rows.size() > SHAPE_SIZE:
			found.append("%s: shape frame '%s' is more than %d rows" % [id, frame, SHAPE_SIZE])
		for row in rows:
			if row.length() > SHAPE_SIZE:
				found.append("%s: shape row '%s' is more than %d pixels" % [id, row, SHAPE_SIZE])
			for mark in row:
				if not "#o. ".contains(mark):
					found.append("%s: shape mark '%s' is not one of # o . (space)" % [id, mark])
				drawn = drawn or mark == "#" or mark == "o"
	if not shape.is_empty() and not drawn:
		found.append("%s: its shape draws nothing" % id)
	return found
