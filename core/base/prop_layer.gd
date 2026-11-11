class_name PropLayer
extends Resource
## One layer of a prop's art in a state (props W7, docs/milestones/props.md, "W7: the look"): a
## sprite, where it stands on the prop's feet, and the motes it gives off. A row of
## `PropStateLook.layers`. View only: nothing in the game reads it. It has no `id`, so the registry
## never takes it for content.
##
## Its picture's bottom middle stands on the prop's feet, moved by `offset`; whole pixels. Its
## frames, when it has several, are side by side, played `fps` a second on the view's clock.

## The picture (`.svg` or `.png`, palette colours; `tools/pixel_grid.py` writes one from a grid).
@export var texture: Texture2D = null
## Where its bottom middle stands from the prop's feet, in pixels.
@export var offset: Vector2 = Vector2.ZERO
## Its frames side by side in `texture`, and how many a second play (0: the first only).
@export_range(1, 32) var frames: int = 1
@export_range(0.0, 30.0, 0.5) var fps: float = 0.0
## Where it is drawn (`Drawn`): among the bodies, over them, on the floor, or not at all.
@export var drawn: Drawn = Drawn.AMONG_BODIES

## Where a layer is drawn: AMONG_BODIES (a barrel), OVER_BODIES (a tall prop's top: a wizard behind
## it is hidden by it), ON_FLOOR (under every body and the floor's marks, as the room's floor is: a
## slab walked on, the hub's teleporter stone), HIDDEN (not drawn: only its motes read it, a mask of
## mote points, `tools/pixel_grid.py`'s `_motes.svg`).
enum Drawn { AMONG_BODIES, OVER_BODIES, ON_FLOOR, HIDDEN }
## What it gives off (`MoteSource`): a mask reads this layer's lit pixels; any other source's
## places are from the prop's feet.
@export var motes: Array[MoteSource] = []


## True when one of its mote sources reads it as a mask.
func has_mask() -> bool:
	for source in motes:
		if source != null and source.from == MoteSource.From.MASK:
			return true
	return false


## The size of one frame (zero with no picture).
func frame_size() -> Vector2i:
	if texture == null:
		return Vector2i.ZERO
	return Vector2i(texture.get_width() / maxi(frames, 1), texture.get_height())


## Where its picture's middle is drawn from the prop's feet: its bottom middle on the feet moved
## by `offset`, an odd side's half pixel kept so the art lies on whole pixels. What `PropLook` draws
## and a prop's stand-in in a room scene shows (W8a).
func drawn_at() -> Vector2:
	var size: Vector2i = frame_size()
	return offset + Vector2(0.0, -float(size.y / 2)) + Vector2(size.x % 2, size.y % 2) * 0.5


## The z its picture is drawn at, from its `drawn` (hidden: as among the bodies).
func z_index() -> int:
	match drawn:
		Drawn.OVER_BODIES:
			return 1
		Drawn.ON_FLOOR:
			# As the room's floor: under every body and the floor's marks.
			return RoomBase.FLOOR_Z
	return 0


## What is wrong with it, one line each after `owner` (empty when nothing is).
func problems(owner: String) -> PackedStringArray:
	var found := PackedStringArray()
	if texture == null:
		found.append("%s has no texture." % owner)
	elif texture.get_width() % maxi(frames, 1) != 0:
		found.append("%s: its %d px are not %d frames of a width." % [owner, texture.get_width(), frames])
	if frames < 1:
		found.append("%s: frames is %d; at least 1." % [owner, frames])
	if fps < 0.0:
		found.append("%s: fps is %s; 0 or more." % [owner, fps])
	if offset != offset.round():
		found.append("%s: offset %s is not whole pixels." % [owner, offset])
	for i in motes.size():
		if motes[i] == null:
			found.append("%s: mote source %d is empty." % [owner, i])
			continue
		for line: String in motes[i].problems(texture != null):
			found.append("%s: mote source %d: %s" % [owner, i, line])
	return found
