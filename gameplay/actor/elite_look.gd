class_name EliteLook
extends ActorLook
## An elite's outline (connected biomes CB11, decision 24, docs/milestones/connected-biomes.md): a ring
## of whole pixels round its body sprite (the node named "Sprite") in the void's light, on every clear
## pixel beside an opaque one, so an elite reads at a glance in a crowd. The actor adds one itself
## when it is an elite (`Actor.elite_card`, `_apply_data`), as it adds a boss's presence.
##
## **Smooth** (docs/STYLE.md): it comes in by stages once the body has spawned in, at FPS: the
## pixels under the body, then those beside it, then the ring whole (3 frames); while the body is
## still spawning in, none. The ring follows the sprite's frame, flip and offset (its hop), worked out
## once a texture frame (`_rings`, shared by every elite) and redrawn only when what it follows
## changed. View only, as every look; it allocates nothing a step.

## The ring's colour: the void's light (docs/STYLE.md; no player's or Blight's).
const COLOUR: Color = Color("e08ad8")
## Frames a second it comes in at, and its stages (0 none ... STAGES whole).
const FPS: float = 12.0
const STAGES: int = 3

## Not state, as every look: the ring of each texture frame, by its key (shared by every elite).
static var _rings: Dictionary = {}

var _sprite: Sprite2D = null
var _stage: int = 0
var _stage_time: float = 0.0
## What it drew last: the ring's key, the sprite's corner and its flip (to redraw only on a change).
var _drawn_texture: int = 0
var _drawn_frame: Rect2 = Rect2()
var _drawn_corner: Vector2 = Vector2.INF
var _drawn_flip: bool = false
var _drawn_stage: int = -1
var _ring: PackedVector2Array = PackedVector2Array()
var _ring_stages: PackedByteArray = PackedByteArray()
var _size: Vector2 = Vector2.ZERO


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	_sprite = owner_actor.get_node_or_null(^"Sprite") as Sprite2D
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## After a snapshot: drawn as it stands (whole once the body is in), never played in again.
func sync() -> void:
	_stage = STAGES if actor != null and actor.spawn_left <= 0.0 else 0
	_drawn_texture = 0


## The stage it is drawn at (0 none ... STAGES whole; for tests).
func stage() -> int:
	return _stage


## How many pixels its ring has whole (for tests).
func ring_size() -> int:
	return _ring.size()


func step(delta: float) -> void:
	if actor == null or _sprite == null or _sprite.texture == null:
		return
	if actor.spawn_left > 0.0:
		_stage = 0
		_stage_time = 0.0
	elif _stage < STAGES:
		_stage_time += delta
		while _stage < STAGES and _stage_time >= 1.0 / FPS:
			_stage_time -= 1.0 / FPS
			_stage += 1
		if _stage == 0:
			_stage = 1
	var frame: Rect2 = _frame_rect()
	var texture: int = _sprite.texture.get_instance_id()
	var changed: bool = texture != _drawn_texture or frame != _drawn_frame
	if changed:
		# Only as the frame changes (a key made then, never each step).
		var found: Array = _ring_of("%d|%s" % [texture, frame], frame)
		_ring = found[0]
		_ring_stages = found[1]
		_size = frame.size
	var corner: Vector2 = _sprite.position + _sprite.offset - (frame.size * 0.5 if _sprite.centered else Vector2.ZERO)
	corner = corner.round()
	if changed or corner != _drawn_corner or _sprite.flip_h != _drawn_flip or _stage != _drawn_stage:
		_drawn_texture = texture
		_drawn_frame = frame
		_drawn_corner = corner
		_drawn_flip = _sprite.flip_h
		_drawn_stage = _stage
		queue_redraw()


func _draw() -> void:
	if _stage <= 0 or _sprite == null or not _sprite.visible:
		return
	for at in _ring.size():
		# Coming in: the pixels under the body first (stage 1), then beside it (2), then all (3).
		if int(_ring_stages[at]) >= _stage:
			continue
		var pixel: Vector2 = _ring[at]
		if _drawn_flip:
			pixel.x = _size.x - 1.0 - pixel.x
		draw_rect(Rect2(_drawn_corner + pixel, Vector2.ONE), COLOUR)


## The sprite's frame now, in its texture's pixels.
func _frame_rect() -> Rect2:
	var whole: Rect2 = _sprite.region_rect if _sprite.region_enabled else Rect2(Vector2.ZERO, _sprite.texture.get_size())
	var cells := Vector2(maxi(_sprite.hframes, 1), maxi(_sprite.vframes, 1))
	var size: Vector2 = (whole.size / cells).floor()
	var coords: Vector2i = _sprite.frame_coords
	return Rect2(whole.position + Vector2(coords) * size, size)


## The ring of the texture frame `frame` (worked out once, then shared): [each clear pixel beside an
## opaque one, in the frame's pixels; the stage before which it is not drawn, by the same index (0
## under the body, 1 beside it, 2 above it)].
func _ring_of(key: String, frame: Rect2) -> Array:
	if _rings.has(key):
		return _rings[key]
	var ring := PackedVector2Array()
	var stages := PackedByteArray()
	var image: Image = _sprite.texture.get_image()
	if image != null:
		if image.is_compressed():
			image.decompress()
		var w: int = int(frame.size.x)
		var h: int = int(frame.size.y)
		var left: int = int(frame.position.x)
		var top: int = int(frame.position.y)
		for y in range(-1, h + 1):
			for x in range(-1, w + 1):
				if _opaque(image, left, top, w, h, x, y):
					continue
				var side: int = -1
				if _opaque(image, left, top, w, h, x, y - 1):
					side = 0
				elif _opaque(image, left, top, w, h, x - 1, y) or _opaque(image, left, top, w, h, x + 1, y):
					side = 1
				elif _opaque(image, left, top, w, h, x, y + 1):
					side = 2
				if side >= 0:
					ring.append(Vector2(x, y))
					stages.append(side)
	_rings[key] = [ring, stages]
	return _rings[key]


static func _opaque(image: Image, left: int, top: int, w: int, h: int, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return image.get_pixel(left + x, top + y).a > 0.5
