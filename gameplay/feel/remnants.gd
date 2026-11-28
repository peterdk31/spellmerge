extends Node2D
## Death remnants (boss plan OB8, docs/milestones/boss-old-broom.md, "Poses and layered bodies"): a
## body at no health is freed at once (gameplay/combat), so its death pose is a remnant Feel leaves
## where it died. A layered body's parts (`BodyPart`, gameplay/actor) are copied as they were drawn
## at the death (art, frame, place, turn and scale) and fly apart: along the floor away from the
## body's middle, and up from their height over its feet and back down, spinning, each as far as its
## `fling` says; they bounce
## BOUNCES times, lie for LIE seconds and fade over FADE. Feel owns one and steps it once a frame.
##
## View only: nothing in the game reads it; its dice are its own and it runs on Feel's clock. A fixed
## pool of MOST pieces (one more takes the place of the oldest); nothing allocates after it is made.

## The most pieces at once.
const MOST: int = 32
## How fast a piece flies off at `fling` 1 (px/s along the floor, and up), how hard it falls (px/s²),
## its spin (radians a second at most) and the spread round the way out (radians either side).
const SPEED: float = 45.0
const UP: float = 120.0
const GRAVITY: float = 420.0
const SPIN: float = 9.0
const SPREAD: float = 0.5
## Bounces before it lies, and what a bounce keeps of its speed.
const BOUNCES: int = 2
const BOUNCE_KEEP: float = 0.4
## Seconds it lies, then fades.
const LIE: float = 1.6
const FADE: float = 0.6
## Flying, a piece draws over the bodies (z 0); lying, on the floor under them, over the floor marks
## (`RoomBase.FLOOR_Z` + 1): z 0 too, a tie with the bodies that Feel, an autoload before the world
## in the tree, loses, so a lying piece draws under every body.
const FLY_Z: int = 1
const LIE_Z: int = RoomBase.FLOOR_Z + 2

var _sprites: Array[Sprite2D] = []
## Each piece: where it is over the floor, its velocity along it, its height and how fast it rises,
## its spin, bounces left and seconds lying (below 0: still flying), and when it was left (the
## oldest goes first when the pool is full).
var _ground: PackedVector2Array = PackedVector2Array()
var _velocity: PackedVector2Array = PackedVector2Array()
var _height: PackedFloat32Array = PackedFloat32Array()
var _rise: PackedFloat32Array = PackedFloat32Array()
var _spin: PackedFloat32Array = PackedFloat32Array()
var _bounces: PackedInt32Array = PackedInt32Array()
var _lying: PackedFloat32Array = PackedFloat32Array()
var _born: PackedInt64Array = PackedInt64Array()
var _count: int = 0
## Its dice's seed: the same every run, so what it draws is the same picture every time a run is
## played (a new generator starts at a random seed; screenshots compare runs byte for byte).
const DICE_SEED: int = 0x4E77
var _rng := FeelDice.seeded(DICE_SEED)
## Pieces left, all told (for tests).
var left: int = 0


func _ready() -> void:
	_ground.resize(MOST)
	_velocity.resize(MOST)
	_height.resize(MOST)
	_rise.resize(MOST)
	_spin.resize(MOST)
	_bounces.resize(MOST)
	_lying.resize(MOST)
	_born.resize(MOST)
	for i in MOST:
		var sprite := Sprite2D.new()
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.visible = false
		add_child(sprite)
		_sprites.append(sprite)


## Leave the parts of the body whose `Sprite` is `body` (the `BodyPart`s under it) where they are
## drawn now (each world transform first put through `unsquash`: Feel's, to the body's rest scale),
## flying apart from `middle` down to the floor at `feet` (world y), drawn in the order the parts
## were (a part `show_behind_parent` under its parent). False when it has no parts (a body of one
## sprite breaks into motes only).
func leave(body: Sprite2D, middle: Vector2, feet: float, unsquash: Transform2D = Transform2D.IDENTITY) -> bool:
	if body == null:
		return false
	var parts: Array[BodyPart] = []
	_drawn_order_of(body, parts)
	if parts.is_empty():
		return false
	for part in parts:
		if part.texture == null or not part.is_visible_in_tree():
			continue
		_leave_part(part, middle, feet, unsquash)
	return true


## The `BodyPart`s under `node` (and `node`, if it is one) in the order they are drawn: a child
## `show_behind_parent` before its parent, the others after it.
static func _drawn_order_of(node: Node, into: Array[BodyPart]) -> void:
	for child in node.get_children():
		if child is CanvasItem and (child as CanvasItem).show_behind_parent:
			_drawn_order_of(child, into)
	if node is BodyPart:
		into.append(node as BodyPart)
	for child in node.get_children():
		if not (child is CanvasItem and (child as CanvasItem).show_behind_parent):
			_drawn_order_of(child, into)


func _leave_part(part: BodyPart, middle: Vector2, feet: float, unsquash: Transform2D) -> void:
	var at: int = _take()
	var sprite: Sprite2D = _sprites[at]
	# Drawn over the pieces left before it, as the parts were drawn over each other.
	move_child(sprite, -1)
	sprite.texture = part.texture
	sprite.hframes = part.hframes
	sprite.vframes = part.vframes
	sprite.frame = part.frame
	sprite.region_enabled = part.region_enabled
	sprite.region_rect = part.region_rect
	sprite.centered = part.centered
	sprite.offset = part.offset
	sprite.flip_h = part.flip_h
	sprite.flip_v = part.flip_v
	sprite.material = null
	sprite.modulate = Color.WHITE
	var shown: Transform2D = unsquash * part.global_transform
	sprite.rotation = shown.get_rotation()
	sprite.scale = shown.get_scale()
	sprite.z_index = FLY_Z
	sprite.visible = true
	# Its art's middle, from which way it flies out.
	var art_middle: Vector2 = shown * part.offset
	var out: Vector2 = art_middle - middle
	out = Vector2.RIGHT.rotated(_rng.randf() * TAU) if out.length_squared() < 1.0 else out.normalized()
	out = out.rotated(_rng.randf_range(-SPREAD, SPREAD))
	var fling: float = part.fling
	_ground[at] = Vector2(shown.origin.x, feet)
	_height[at] = maxf(feet - shown.origin.y, 0.0)
	_velocity[at] = out * SPEED * fling * _rng.randf_range(0.7, 1.2)
	_rise[at] = UP * fling * _rng.randf_range(0.7, 1.1)
	_spin[at] = _rng.randf_range(-SPIN, SPIN) * minf(fling, 1.5)
	_bounces[at] = BOUNCES
	_lying[at] = -1.0
	_born[at] = left
	left += 1
	sprite.global_position = _ground[at] - Vector2(0.0, _height[at])


## A free piece, else the oldest.
func _take() -> int:
	if _count < MOST:
		_count += 1
		return _count - 1
	var oldest: int = 0
	for i in MOST:
		if _born[i] < _born[oldest]:
			oldest = i
	return oldest


## Move every piece on by `delta` seconds of Feel's clock.
func step(delta: float) -> void:
	var at: int = _count - 1
	while at >= 0:
		_step_piece(at, delta)
		at -= 1


func _step_piece(at: int, delta: float) -> void:
	var sprite: Sprite2D = _sprites[at]
	if _lying[at] >= 0.0:
		_lying[at] += delta
		if _lying[at] >= LIE + FADE:
			_drop(at)
			return
		if _lying[at] > LIE:
			sprite.modulate.a = 1.0 - (_lying[at] - LIE) / FADE
		return
	_ground[at] += _velocity[at] * delta
	_rise[at] -= GRAVITY * delta
	_height[at] += _rise[at] * delta
	sprite.rotation += _spin[at] * delta
	if _height[at] <= 0.0 and _rise[at] < 0.0:
		_height[at] = 0.0
		if _bounces[at] > 0:
			_bounces[at] -= 1
			_rise[at] = -_rise[at] * BOUNCE_KEEP
			_velocity[at] *= BOUNCE_KEEP
			_spin[at] *= BOUNCE_KEEP
		else:
			_lying[at] = 0.0
			sprite.z_index = LIE_Z
	sprite.global_position = (_ground[at] - Vector2(0.0, _height[at])).round()


## Piece `at` is done: the last piece takes its place.
func _drop(at: int) -> void:
	var last: int = _count - 1
	_sprites[at].visible = false
	if at != last:
		var sprite: Sprite2D = _sprites[at]
		_sprites[at] = _sprites[last]
		_sprites[last] = sprite
		_ground[at] = _ground[last]
		_velocity[at] = _velocity[last]
		_height[at] = _height[last]
		_rise[at] = _rise[last]
		_spin[at] = _spin[last]
		_bounces[at] = _bounces[last]
		_lying[at] = _lying[last]
		_born[at] = _born[last]
	_count = last


## Clear every piece (a new room).
func clear() -> void:
	for sprite in _sprites:
		sprite.visible = false
	_count = 0


## Pieces showing now, and the sprite of piece `at` (for tests).
func count() -> int:
	return _count


func piece(at: int) -> Sprite2D:
	return _sprites[at]


## How high piece `at` is over the floor (px), and where on the floor it is.
func height_of(at: int) -> float:
	return _height[at]


func ground_of(at: int) -> Vector2:
	return _ground[at]


## True while piece `at` lies on the floor.
func is_lying(at: int) -> bool:
	return _lying[at] >= 0.0
