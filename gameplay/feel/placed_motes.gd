extends Node2D
## Motes placed every frame: a batch of mote rows that its owner rewrites each frame where its motes
## are now, drawn by the motes' own shader and material (`Motes.draw_material`), so a shape made of
## motes (a shield's shell, `barriers.gd`; a portal's lips, `portal_look.gd`) is real motes, the
## world's magic building blocks (the owner, 2026-11-09), without each owner writing rows of its own.
## Each row is a mote just born there, standing still, its age (so its shade, white-hot to the base
## colour, and a ward's twinkle) the owner's. What flies off goes into the mote pool as ordinary
## moments (`Motes.burst`, `Motes.throw_part`), not here. Allocates nothing per frame: its rows grow
## only when a frame places more than ever before. With no pool (particles off) it draws nothing.
##
## A frame: `begin(pool, now)`, a `put` per mote, `finish()`.

const BatchesScript := preload("res://core/projectiles/batches.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")

## Rows placed this frame (for tests and the owner's counts).
var rows: int = 0

var _node: MultiMeshInstance2D = null
var _buffer: PackedFloat32Array = PackedFloat32Array()
var _room: int = 0
var _z: int = 0
var _now: float = 0.0


## A batch drawn at `z` (its node named `label`), with room for `room` motes at first.
func _init(z: int = 16, label: String = "PlacedMotes", room: int = 64) -> void:
	_z = z
	name = label
	_fit(room)


## Starts a frame at Feel's clock `now`: nothing placed yet. False with no `pool` (particles off):
## then nothing is drawn this frame and `put` must not be called.
func begin(pool: MotesScript, now: float) -> bool:
	rows = 0
	_now = now
	if pool == null:
		if _node != null:
			_node.visible = false
		return false
	_bind(pool)
	return true


## Room for `wanted` rows this frame at least (optional: `put` grows it too), so a frame that knows
## its count grows once.
func hold(wanted: int) -> void:
	_fit(wanted)


## A mote of kind `kind` (`Motes.kind_index`) standing at `at`, from `source` (`Motes.spell_source`,
## its ramp) in the core colour `core`, `age` seconds into a life of `life` (its shade by its age:
## 0 white-hot, its kind's ramp as it ages), its twinkle's own `seed` (0 to 1).
func put(at: Vector2, kind: int, source: int, core: Color, age: float, seed: float, life: float = 1.0) -> void:
	if rows >= _room:
		_fit(rows + 1)
	var i: int = rows * MotesScript.DRAW_STRIDE
	_buffer[i + MotesScript.ROW_VX] = 0.0
	_buffer[i + MotesScript.ROW_BORN] = _now - age
	_buffer[i + MotesScript.ROW_X] = roundf(at.x)
	_buffer[i + MotesScript.ROW_VY] = 0.0
	_buffer[i + MotesScript.ROW_VZ] = 0.0
	_buffer[i + MotesScript.ROW_Y] = roundf(at.y)
	_buffer[i + MotesScript.ROW_SOURCE] = float(source) / MotesScript.SOURCE_CODE
	_buffer[i + MotesScript.ROW_KIND] = float(kind) / MotesScript.KIND_CODE
	_buffer[i + MotesScript.ROW_LIFE] = life / MotesScript.LIFE_MAX
	_buffer[i + MotesScript.ROW_HEIGHT] = 0.0
	_buffer[i + MotesScript.ROW_CORE] = core.r
	_buffer[i + MotesScript.ROW_CORE + 1] = core.g
	_buffer[i + MotesScript.ROW_CORE + 2] = core.b
	_buffer[i + MotesScript.ROW_SEED] = seed
	rows += 1


## Ends the frame: the motes placed since `begin` are drawn, and only those.
func finish() -> void:
	if _node == null:
		return
	if rows == 0:
		_node.visible = false
		return
	_node.multimesh.visible_instance_count = rows
	_node.multimesh.buffer = _buffer
	_node.visible = true


## Row `row` as placed last frame (for tests; Motes.DRAW_STRIDE floats).
func row_data(row: int) -> PackedFloat32Array:
	var at: int = row * MotesScript.DRAW_STRIDE
	return _buffer.slice(at, at + MotesScript.DRAW_STRIDE)


## Room for `wanted` rows: doubles, never shrinks.
func _fit(wanted: int) -> void:
	if wanted <= _room:
		return
	_room = maxi(wanted, _room * 2)
	_buffer.resize(_room * MotesScript.DRAW_STRIDE)
	if _node != null:
		_node.multimesh.instance_count = _room


## The batch, drawn with `pool`'s material and quad (made the first time; a new pool, after the
## "Particles" setting changed, is taken up).
func _bind(pool: MotesScript) -> void:
	if _node == null:
		var multimesh: MultiMesh = BatchesScript.multimesh()
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = pool.draw_quad()
		multimesh.instance_count = _room
		multimesh.visible_instance_count = 0
		_node = MultiMeshInstance2D.new()
		_node.name = "Rows"
		_node.multimesh = multimesh
		_node.top_level = true
		_node.z_index = _z
		_node.visible = false
		add_child(_node)
	if _node.material != pool.draw_material():
		_node.material = pool.draw_material()
		_node.multimesh.mesh = pool.draw_quad()
