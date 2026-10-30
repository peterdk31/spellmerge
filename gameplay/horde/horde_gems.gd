extends MultiMeshInstance2D
## The horde's experience gems (docs/milestones/horde.md, "Experience"): every gem in one draw
## node, as instances of one glowing quad (a soft additive glow round a tiny white-hot core, the
## glow style), never a node per gem. The gems are packed arrays sized MAX_GEMS, made once, so a
## kill, a pull or a pickup allocates nothing.
##
## `add(at, value)` drops a gem; `step(...)` pulls a gem towards the first standing wizard
## within the pickup radius and returns the experience of the gems that reached a wizard this
## step. A gem only moves while it is pulled, so only those instances are rewritten.

## The most gems on the floor at once; a gem dropped beyond it adds its value to the newest one.
const MAX_GEMS: int = 1024
## Pixels per second a pulled gem flies towards its wizard.
const PULL_SPEED: float = 300.0
## A pulled gem this close to its wizard (pixels) is picked up.
const COLLECT_DISTANCE: float = 10.0
## The quad a gem is drawn on, pixels (the glow; the core is its middle).
const GEM_SIZE: float = 14.0
## The glow's colours, from the white-hot core out to nothing.
const CORE_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const GLOW_COLOR: Color = Color(0.45, 1.0, 0.75, 0.85)
const EDGE_COLOR: Color = Color(0.2, 0.8, 0.6, 0.0)
## The glow breathes: its brightness swings this much, this many times a second.
const PULSE_DEPTH: float = 0.2
const PULSE_RATE: float = 1.5

## How many gems lie on the floor now (the first `count` rows).
var count: int = 0

var _at: PackedVector2Array = PackedVector2Array()
var _value: PackedInt32Array = PackedInt32Array()
## The wizard (an index into the step's wizard list) a gem flies to, or -1 while it lies still.
var _pulled_by: PackedInt32Array = PackedInt32Array()
var _clock: float = 0.0


func _init() -> void:
	name = "HordeGems"
	_at.resize(MAX_GEMS)
	_value.resize(MAX_GEMS)
	_pulled_by.resize(MAX_GEMS)
	var quad := QuadMesh.new()
	quad.size = Vector2(GEM_SIZE, GEM_SIZE)
	var gems := MultiMesh.new()
	gems.transform_format = MultiMesh.TRANSFORM_2D
	gems.mesh = quad
	gems.instance_count = MAX_GEMS
	gems.visible_instance_count = 0
	multimesh = gems
	var glow := Gradient.new()
	glow.offsets = PackedFloat32Array([0.0, 0.18, 0.4, 1.0])
	glow.colors = PackedColorArray([CORE_COLOR, GLOW_COLOR, GLOW_COLOR * Color(1.0, 1.0, 1.0, 0.35), EDGE_COLOR])
	var look := GradientTexture2D.new()
	look.gradient = glow
	look.fill = GradientTexture2D.FILL_RADIAL
	look.fill_from = Vector2(0.5, 0.5)
	look.fill_to = Vector2(1.0, 0.5)
	look.width = 16
	look.height = 16
	texture = look
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add


## Drops a gem worth `value` at `at` (this node's space).
func add(at: Vector2, value: int) -> void:
	if value <= 0:
		return
	if count >= MAX_GEMS:
		_value[count - 1] += value
		return
	_at[count] = at
	_value[count] = value
	_pulled_by[count] = -1
	multimesh.set_instance_transform_2d(count, Transform2D(0.0, at))
	count += 1
	multimesh.visible_instance_count = count


## Where gem `index` lies (0 to `count` - 1).
func gem_position(index: int) -> Vector2:
	return _at[index]


## Every gem's value added up.
func total_value() -> int:
	var total: int = 0
	for i in count:
		total += _value[i]
	return total


## Moves the gems by `delta` seconds: a lying gem within `radius` of a wizard in `wizards`
## whose `standing` entry is 1 is pulled towards it; a pulled gem flies to its wizard (or lies
## down where it is if that wizard is gone or down) and is picked up when it reaches it. Returns
## the experience picked up.
func step(delta: float, wizards: PackedVector2Array, standing: PackedByteArray, radius: float) -> int:
	_clock += delta
	self_modulate.a = 1.0 - PULSE_DEPTH * (0.5 + 0.5 * sin(_clock * TAU * PULSE_RATE))
	var picked: int = 0
	var reach: float = radius * radius
	var i: int = 0
	while i < count:
		var by: int = _pulled_by[i]
		if by >= 0 and (by >= standing.size() or standing[by] == 0):
			by = -1
			_pulled_by[i] = -1
		if by < 0:
			for w in wizards.size():
				if standing[w] != 0 and _at[i].distance_squared_to(wizards[w]) <= reach:
					by = w
					_pulled_by[i] = w
					break
		if by < 0:
			i += 1
			continue
		var to: Vector2 = wizards[by]
		var at: Vector2 = _at[i].move_toward(to, PULL_SPEED * delta)
		if at.distance_to(to) <= COLLECT_DISTANCE:
			picked += _value[i]
			_remove(i)
			continue
		_at[i] = at
		multimesh.set_instance_transform_2d(i, Transform2D(0.0, at))
		i += 1
	return picked


## Takes every gem off the floor.
func clear() -> void:
	count = 0
	multimesh.visible_instance_count = 0


## Gem `index` goes: the last gem takes its row.
func _remove(index: int) -> void:
	count -= 1
	if index != count:
		_at[index] = _at[count]
		_value[index] = _value[count]
		_pulled_by[index] = _pulled_by[count]
		multimesh.set_instance_transform_2d(index, Transform2D(0.0, _at[index]))
	multimesh.visible_instance_count = count
