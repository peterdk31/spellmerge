extends Node2D
## Motes (docs/milestones/spell-spectacle.md, P1): up to tens of thousands of single-pixel
## particles with no game logic, drawn by Feel. A mote is thrown from a point with a velocity
## along the floor, a fake height and a velocity up; `gameplay/feel/mote.gdshader` works out its
## whole flight from its row and the time since its birth (it flies with drag, rises or falls,
## lands, bounces once, lies still and cools through its ramp's shades). The CPU writes a row once
## and never touches it again: there is no per-frame simulation.
##
## The pool is a ring of `cap` rows (the "Particles" setting, `MoteCap` in core/settings): a new
## mote takes the next row and overwrites the oldest. The ring is cut into CHUNK-row chunks, one
## `MultiMeshInstance2D` each (made by `Batches.multimesh()`, so it is never culled; made the first
## time a mote lands in it). `step` uploads only the chunks written since the last frame, so a
## burst of 300 motes uploads one or two chunks (64 KB each), never the whole ring; a chunk whose
## newest mote is older than LIFE_MAX is hidden and costs no vertices. Nothing is allocated while
## playing, past a chunk's first use. Writing a mote costs the CPU about 1.5 us, so at most
## FRAME_ROWS are written between two steps: a burst past that is cut short (a flood of wall hits
## costs a bounded part of a frame; P1c measures the number).
##
## Kinds are rows of the tables below (GRAVITY, DRAG, ...), mirrored in the shader's K_* constants,
## and `flight` is the shader's `mote_flight` line for line (tests/gameplay/feel/test_motes.gd
## compares them). `mote_land` gives where and when a mote comes to rest, for the floor marks (P2b).

const SHADER: Shader = preload("res://gameplay/feel/mote.gdshader")
const BatchesScript := preload("res://core/projectiles/batches.gd")

## Rows in a chunk: one batch, uploaded whole when any of its rows is written.
const CHUNK: int = 1024
## Floats in a row: the transform (8), the colour (4) and the custom data (4).
const DRAW_STRIDE: int = 16
## The longest life a mote has (s); a chunk with nothing newer is hidden.
const LIFE_MAX: float = 4.0
## What a kind and a ramp are divided by in the row's colour (the shader's CODE).
const CODE: float = 16.0
## The most motes written between two steps (about 0.6 ms of a frame).
const FRAME_ROWS: int = 384

## The kinds, by their index in KIND_NAMES (a cue names a kind by its name).
const EMBER: int = 0
const SPARK: int = 1
const CHIP: int = 2
const SHARD: int = 3
const ASH: int = 4
const SPLINTER: int = 5
const KIND_NAMES: Array[StringName] = [&"ember", &"spark", &"chip", &"shard", &"ash", &"splinter"]
## Per kind (the shader's K_* constants): down the height (px/s/s; below 0 it rises), drag along
## the floor (1/s), the share of its fall's speed a landing bounces back, a sideways sway (px) and
## its rate (rad/s), the glow while it is hot (0 none), the shade it starts at (0 white-hot,
## 1 light, 2 base, 3 shadow).
## An ember rises, sways, glows and cools; a spark is fast, short and glows; a chip is stone that
## falls and lies; a shard is ice that falls and glints; ash drifts slowly and sinks; a splinter is
## wood (staff bodies).
const GRAVITY: Array[float] = [-12.0, 220.0, 320.0, 300.0, 18.0, 300.0]
const DRAG: Array[float] = [2.0, 3.5, 2.5, 2.5, 1.2, 2.5]
const BOUNCE: Array[float] = [0.0, 0.35, 0.3, 0.4, 0.0, 0.25]
const WOBBLE: Array[float] = [1.5, 0.0, 0.0, 0.0, 3.0, 0.0]
const WOBBLE_RATE: Array[float] = [7.0, 0.0, 0.0, 0.0, 3.0, 0.0]
const GLOW: Array[float] = [1.0, 1.0, 0.0, 0.4, 0.0, 0.0]
const SHADE_FROM: Array[float] = [0.0, 0.0, 1.0, 1.0, 2.0, 1.0]
## The share of a kind's motes that are a 2x2 chunk rather than one pixel (CPU only).
const BIG_SHARE: Array[float] = [0.0, 0.0, 0.3, 0.0, 0.0, 0.5]

## The ramps a mote cools through (the shader's `ramp_shade`): 0-3 the players' hat ramps,
## RAMP_ENEMY the enemies' (Blight), the materials of the shot shaders' SHADES from RAMP_FIRE on
## (Fire, Spark, Ice, Void, Arc, Bone), then Stone and Wood (docs/STYLE.md).
const RAMP_ENEMY: int = 4
const RAMP_FIRE: int = 5
const RAMP_SPARK: int = 6
const RAMP_ICE: int = 7
const RAMP_VOID: int = 8
const RAMP_ARC: int = 9
const RAMP_BONE: int = 10
const RAMP_STONE: int = 11
const RAMP_WOOD: int = 12
## The materials' shades (shadow, base, light each), as `shot_palette.gdshaderinc`'s SHADES has
## them: a core colour takes the ramp of the nearest (`ramp_of_core`).
const MATERIAL_SHADES: Array[Color] = [
	Color(0.561, 0.176, 0.165), Color(0.878, 0.349, 0.184), Color(1.0, 0.635, 0.235),
	Color(0.722, 0.502, 0.122), Color(0.949, 0.761, 0.188), Color(1.0, 0.953, 0.651),
	Color(0.122, 0.439, 0.502), Color(0.310, 0.839, 0.863), Color(0.769, 0.965, 0.949),
	Color(0.290, 0.078, 0.314), Color(0.627, 0.188, 0.604), Color(0.878, 0.541, 0.847),
	Color(0.247, 0.420, 0.063), Color(0.706, 0.910, 0.165), Color(0.933, 1.0, 0.651),
	Color(0.639, 0.624, 0.722), Color(0.831, 0.816, 0.878), Color(0.957, 0.945, 0.918),
]

## Uploads of a chunk's buffer since this pool was made (for tests and the benchmarks).
var uploads: int = 0

var _cap: int = 0
## The next row a mote takes.
var _next: int = 0
## Per chunk: its batch (null until its first mote), its rows, written since the last upload, and
## the clock time of its last upload.
var _nodes: Array[MultiMeshInstance2D] = []
var _buffers: Array[PackedFloat32Array] = []
var _dirty: PackedByteArray = PackedByteArray()
var _newest: PackedFloat32Array = PackedFloat32Array()
## The clock motes are born on (Feel's, from `step`).
var _now: float = 0.0
## Motes that may still be written before the next step (FRAME_ROWS).
var _rows_left: int = FRAME_ROWS
var _material: ShaderMaterial = null
var _mesh: ArrayMesh = null
var _z: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## A pool of `cap` rows (above 0), its batches drawn at `z`.
func _init(cap: int, z: int) -> void:
	top_level = true
	_cap = maxi(cap, 1)
	_z = z
	_rng.seed = 7
	var chunks: int = ceili(float(_cap) / CHUNK)
	_nodes.resize(chunks)
	_buffers.resize(chunks)
	_dirty.resize(chunks)
	_newest.resize(chunks)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_mesh = _quad()


## How many motes the ring holds.
func cap() -> int:
	return _cap


## Throw `count` motes of `kind` (EMBER to SPLINTER) from `at` (where they show; their ground point
## is `height` pixels below it): along the floor within `spread` degrees round `dir` (all round with
## 360 or no `dir`), at a speed in `speed` (x to y, px/s), up at a speed in `up`, living a time in
## `life` (s, at most LIFE_MAX), cooling through `ramp` (RAMP_*). Fewer when the frame's FRAME_ROWS
## run out.
func burst(kind: int, at: Vector2, dir: Vector2, count: int, speed: Vector2, spread: float, up: Vector2, life: Vector2, ramp: int, height: float = 0.0) -> void:
	count = mini(count, _rows_left)
	if count <= 0 or not at.is_finite() or kind < 0 or kind >= KIND_NAMES.size():
		return
	_rows_left -= count
	var aim: float = dir.angle() if dir != Vector2.ZERO else 0.0
	var half: float = deg_to_rad(clampf(spread, 0.0, 360.0)) * 0.5
	var ground: Vector2 = at + Vector2(0.0, height)
	var big: float = BIG_SHARE[kind]
	var shade: float = SHADE_FROM[kind]
	var coded_kind: float = float(kind) / CODE
	var coded_ramp: float = float(clampi(ramp, 0, RAMP_WOOD)) / CODE
	var chunk: int = -1
	var buffer: PackedFloat32Array
	for n in count:
		var row: int = _next
		_next = (_next + 1) % _cap
		var c: int = row / CHUNK
		if c != chunk:
			chunk = c
			buffer = _chunk(c)
			_dirty[c] = 1
		var v: Vector2 = Vector2.from_angle(aim + _rng.randf_range(-half, half)) * _rng.randf_range(speed.x, speed.y)
		var i: int = (row - c * CHUNK) * DRAW_STRIDE
		buffer[i] = v.x
		buffer[i + 1] = _now
		buffer[i + 3] = ground.x
		buffer[i + 4] = v.y
		buffer[i + 5] = _rng.randf_range(up.x, up.y)
		buffer[i + 7] = ground.y
		buffer[i + 8] = coded_kind
		buffer[i + 9] = coded_ramp
		buffer[i + 10] = clampf(_rng.randf_range(life.x, life.y), 0.02, LIFE_MAX) / LIFE_MAX
		buffer[i + 11] = _rng.randf()
		buffer[i + 12] = height
		buffer[i + 13] = 2.0 if big > 0.0 and _rng.randf() < big else 1.0
		buffer[i + 14] = shade


## Once a frame, at Feel's clock `now`: upload the chunks written since the last step, hide those
## with nothing alive, and move the shader's clock on.
func step(now: float) -> void:
	_now = now
	_rows_left = FRAME_ROWS
	_material.set_shader_parameter(&"sim_time", now)
	for c in _nodes.size():
		var node: MultiMeshInstance2D = _nodes[c]
		if node == null:
			continue
		if _dirty[c] == 1:
			_dirty[c] = 0
			node.multimesh.buffer = _buffers[c]
			uploads += 1
			_newest[c] = now
			node.visible = true
		elif node.visible and now - _newest[c] > LIFE_MAX:
			node.visible = false


## Chunks with a batch made, and those drawn now (for tests).
func chunks_made() -> int:
	var made: int = 0
	for node in _nodes:
		if node != null:
			made += 1
	return made


func chunks_shown() -> int:
	var shown: int = 0
	for node in _nodes:
		if node != null and node.visible:
			shown += 1
	return shown


## The row the next mote takes.
func next_row() -> int:
	return _next


## Where mote `row` is at the clock time `now`: its ground point (x, y) and its height (z); drawn
## at the ground point raised by its height. Its row is read as written (for tests and P2).
func mote_at(row: int, now: float) -> Vector3:
	var buffer: PackedFloat32Array = _buffers[row / CHUNK]
	var i: int = (row % CHUNK) * DRAW_STRIDE
	return flight(Vector2(buffer[i + 3], buffer[i + 7]), Vector2(buffer[i], buffer[i + 4]), buffer[i + 12], buffer[i + 5], now - buffer[i + 1], _kind_of(buffer, i), buffer[i + 11])


## Where and when mote `row` comes to rest on the floor: its point (x, y) and the clock time (z);
## INF for z when it never does in its life (a kind that rises, or one gone before it lands).
func mote_land(row: int) -> Vector3:
	var buffer: PackedFloat32Array = _buffers[row / CHUNK]
	var i: int = (row % CHUNK) * DRAW_STRIDE
	var kind: int = _kind_of(buffer, i)
	var rest: float = rest_time(kind, buffer[i + 12], buffer[i + 5])
	var life: float = buffer[i + 10] * LIFE_MAX
	if rest >= life:
		return Vector3(INF, INF, INF)
	var at: Vector3 = flight(Vector2(buffer[i + 3], buffer[i + 7]), Vector2(buffer[i], buffer[i + 4]), buffer[i + 12], buffer[i + 5], rest, kind, buffer[i + 11])
	return Vector3(at.x, at.y, buffer[i + 1] + rest)


## The row of mote `row` as the shader reads it (a copy, for tests).
func row_data(row: int) -> PackedFloat32Array:
	var i: int = (row % CHUNK) * DRAW_STRIDE
	return _buffers[row / CHUNK].slice(i, i + DRAW_STRIDE)


## Seconds after its birth a mote of `kind` born `h0` above the floor, going up at `vz`, comes to
## rest (after its one bounce); INF for a kind that never falls.
static func rest_time(kind: int, h0: float, vz: float) -> float:
	var g: float = GRAVITY[kind]
	if g <= 0.0:
		return INF
	var land: float = (vz + sqrt(vz * vz + 2.0 * g * maxf(h0, 0.0))) / g
	var rebound: float = (g * land - vz) * BOUNCE[kind]
	return land + 2.0 * rebound / g


## The shader's `mote_flight`: where a mote of `kind` is `t` seconds after its birth at the ground
## point `from` with the velocity `vel`, the height `h0` and the height's velocity `vz`: its ground
## point (x, y) and its height (z).
static func flight(from: Vector2, vel: Vector2, h0: float, vz: float, t: float, kind: int, seed: float) -> Vector3:
	var g: float = GRAVITY[kind]
	var land: float = 1.0e9
	var rest: float = 1.0e9
	var rebound: float = 0.0
	if g > 0.0:
		land = (vz + sqrt(vz * vz + 2.0 * g * maxf(h0, 0.0))) / g
		rebound = (g * land - vz) * BOUNCE[kind]
		rest = land + 2.0 * rebound / g
	var tm: float = minf(maxf(t, 0.0), rest)
	var h: float = 0.0
	if tm < land:
		h = h0 + vz * tm - 0.5 * g * tm * tm
	elif tm < rest:
		var s: float = tm - land
		h = rebound * s - 0.5 * g * s * s
	var drag: float = DRAG[kind]
	var along: float = (1.0 - exp(-drag * tm)) / drag if drag > 0.0 else tm
	var ground: Vector2 = from + vel * along
	var phase: float = seed * 6.2832
	ground.x += WOBBLE[kind] * (sin(tm * WOBBLE_RATE[kind] + phase) - sin(phase))
	return Vector3(ground.x, ground.y, maxf(h, 0.0))


## The ramp a shot of core colour `core` cools through: its caster's `ramp` (0-3 a hat ramp, else
## the enemies') for a plain (white) core, else the material whose shade is nearest, as the shot
## shaders pick it (`look_of` in `shot_look.gdshaderinc`).
static func ramp_of_core(core: Color, ramp: int) -> int:
	if core.r > 0.99 and core.g > 0.99 and core.b > 0.99:
		return ramp if ramp >= 0 and ramp < RAMP_ENEMY else RAMP_ENEMY
	var best: int = 0
	var near: float = INF
	for i in MATERIAL_SHADES.size():
		var shade: Color = MATERIAL_SHADES[i]
		var d: float = Vector3(core.r - shade.r, core.g - shade.g, core.b - shade.b).length()
		if d < near:
			near = d
			best = i / 3
	return RAMP_FIRE + best


func _kind_of(buffer: PackedFloat32Array, i: int) -> int:
	return clampi(roundi(buffer[i + 8] * CODE), 0, KIND_NAMES.size() - 1)


## Chunk `c`'s rows, making its batch the first time.
func _chunk(c: int) -> PackedFloat32Array:
	if _nodes[c] == null:
		var rows: int = mini(CHUNK, _cap - c * CHUNK)
		var multimesh: MultiMesh = BatchesScript.multimesh()
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = _mesh
		multimesh.instance_count = rows
		var buffer := PackedFloat32Array()
		# Every row starts with no life: folded away.
		buffer.resize(rows * DRAW_STRIDE)
		_buffers[c] = buffer
		var node := MultiMeshInstance2D.new()
		node.multimesh = multimesh
		node.material = _material
		node.top_level = true
		node.z_index = _z
		node.visible = false
		add_child(node)
		_nodes[c] = node
	return _buffers[c]


## One quad: the shader places its corners (a vertex's UV is its corner).
static func _quad() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
