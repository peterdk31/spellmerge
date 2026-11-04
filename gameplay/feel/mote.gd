extends Node2D
## Motes (docs/milestones/spell-spectacle.md, P1): up to tens of thousands of single-pixel
## particles with no game logic, drawn by Feel. A mote is thrown from a point with a velocity
## along the floor, a fake height and a velocity up; `gameplay/feel/mote.gdshader` works out its
## whole flight from its row and the time since its birth (it flies with drag, rises or falls,
## lands, bounces once, lies still and cools through its ramp's shades). The CPU writes a row once
## and never touches it again: there is no per-frame simulation.
##
## **Kinds are data** (`MoteKind`, `content/motes/`): how one flies and how many a burst throws.
## The pool takes them when it is made and hands their numbers to the shader (`kind_motion`,
## `kind_sway`, `kind_shape`) and their shapes' frames (`shape_atlas`, a texture of
## MoteKind.SHAPE_SIZE squares, a kind's frames along a row), so a new kind, or a new shape, is a
## new file. A spell's kinds come from its cards' looks
## (`kinds_of_look`): a shot sheds the kinds that name its look layers (`shed`).
##
## **Colours are never here.** A mote cools through a ramp of four shades (white-hot, light, base,
## shadow) named by its source (`spell_source`, `table_source`): a spell's motes take the shot's
## own ramp, picked in the shader by the shot shaders' rule (`look_of` in `shot_look.gdshaderinc`:
## the caster's hat ramp for a plain core, else the palette material nearest its core, or the
## exact colour); any other colours (a room's walls, `RoomBase.surface_colors`) go into the ramp
## table (`ramp_table`, a texture of RAMPS rows) and are named by their row.
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
## `flight` is the shader's `mote_flight` line for line; `mote_land` gives where and when a mote
## comes to rest, for the floor marks (P2b).

const SHADER: Shader = preload("res://gameplay/feel/mote.gdshader")
const BatchesScript := preload("res://core/projectiles/batches.gd")

## Rows in a chunk: one batch, uploaded whole when any of its rows is written.
const CHUNK: int = 1024
## Floats in a row: the transform (8), the colour (4) and the custom data (4).
const DRAW_STRIDE: int = 16
## The longest life a mote has (s); a chunk with nothing newer is hidden.
const LIFE_MAX: float = 4.0
## The most motes written between two steps (about 0.6 ms of a frame).
const FRAME_ROWS: int = 384
## The most kinds the shader holds (its `kind_motion` and `kind_sway` arrays).
const MAX_KINDS: int = 16
## Rows of the ramp table (colours other than a spell's), and its shades a row.
const RAMPS: int = 64
const SHADES: int = 4
## A source (a row's first colour channel): 0-3 a hat ramp, ENEMY_SOURCE the enemies', plus
## EXACT_SOURCE for a shot of an exact colour; from TABLE_SOURCE on, a row of the ramp table.
const ENEMY_SOURCE: int = 4
const EXACT_SOURCE: int = 8
const TABLE_SOURCE: int = 16
## A look's flags (core/projectiles: LOOK_ENEMY_RAMP, and Feel's EXACT), and its layers' bits.
const LOOK_ENEMY_RAMP: int = 1 << 22
const LOOK_EXACT: int = 1 << 23
const LOOK_LAYERS: int = 21
## What a row's colour channels are divided by, so every one is between 0 and 1 (the shader's
## SOURCE_CODE, KIND_CODE, HEIGHT_MAX; LIFE_MAX for the life; the second channel is the kind). The life and the height are
## written in steps of 1/255 of their most (the height in quarter pixels), so a renderer that
## keeps the colour as bytes reads the same numbers `flight` does.
const SOURCE_CODE: float = 128.0
const KIND_CODE: float = 16.0
const HEIGHT_MAX: float = 63.75
## A trail particle's speed (and its speed up), as a share of its kind's burst (`give_off`): given
## off, not thrown. And the floats of a birth (core/projectiles' SPARK_BIRTH_STRIDE).
const TRAIL_SPEED: float = 0.3
const BIRTH_STRIDE: int = 10

## Uploads of a chunk's buffer since this pool was made (for tests and the benchmarks).
var uploads: int = 0
## Every burst's count is times this (the "Particle amount" setting, `MoteDensity`; 0 throws
## none). A share of a mote is thrown that often, so the average holds.
var density: float = 1.0

var _cap: int = 0
## The kinds, in the order the shader holds them, and for each look layer (0-21) the kinds that
## are its motes; the surface kinds.
var _kinds: Array[MoteKind] = []
var _layer_kinds: Array[PackedInt32Array] = []
var _surface_kinds: PackedInt32Array = PackedInt32Array()
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
## The ramp table: its image and texture, the row of each set of colours, and the next row a new
## set takes (the oldest when it is full).
var _ramp_image: Image = null
var _ramp_texture: ImageTexture = null
var _ramp_rows: Dictionary = {}
var _next_ramp: int = 0
## The shapes' frames: SHAPE_SIZE squares, a kind's along its row (`shape_value`).
var _shape_image: Image = null
var _material: ShaderMaterial = null
var _mesh: ArrayMesh = null
var _z: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## A pool of `cap` rows (above 0) of the kinds `kinds` (at most MAX_KINDS; a kind with problems
## is left out), its batches drawn at `z`.
func _init(cap: int, z: int, kinds: Array[MoteKind]) -> void:
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
	_ramp_image = Image.create_empty(SHADES, RAMPS, false, Image.FORMAT_RGBA8)
	_ramp_texture = ImageTexture.create_from_image(_ramp_image)
	_material.set_shader_parameter(&"ramp_table", _ramp_texture)
	_take_kinds(kinds)


## How many motes the ring holds.
func cap() -> int:
	return _cap


## The kinds, in the order the rows name them.
func kinds() -> Array[MoteKind]:
	return _kinds


## The index of the kind `id`, or -1.
func kind_index(id: StringName) -> int:
	for i in _kinds.size():
		if _kinds[i].id == id:
			return i
	return -1


## The kinds a shot of the look `look` sheds (its cards' layers; LOOK_* bits, layer n is bit
## n - 1): every kind that names one of them, else the kinds of layer 0.
func kinds_of_look(look: int) -> PackedInt32Array:
	var found := PackedInt32Array()
	for layer in range(1, LOOK_LAYERS + 1):
		if (look >> (layer - 1)) & 1 == 1:
			for k in _layer_kinds[layer]:
				if not found.has(k):
					found.append(k)
	if found.is_empty():
		found = _layer_kinds[0].duplicate()
	return found


## The surface kinds (what a struck wall sheds).
func surface_kinds() -> PackedInt32Array:
	return _surface_kinds


## The source of a spell's motes: the ramp of a shot of its caster's `ramp` (0-3 a hat ramp,
## anything else the enemies') with the look `look` (its flags: the enemy ramp, an exact colour).
static func spell_source(ramp: int, look: int) -> int:
	var who: int = ramp if ramp >= 0 and ramp < ENEMY_SOURCE and (look & LOOK_ENEMY_RAMP) == 0 else ENEMY_SOURCE
	return who + (EXACT_SOURCE if (look & LOOK_EXACT) != 0 else 0)


## The source of motes in `colours` (light, base, shadow; a fourth first is the white-hot, else
## the light): their row of the ramp table, written the first time.
func table_source(colours: PackedColorArray) -> int:
	if colours.is_empty():
		return -1
	var shades: PackedColorArray = colours if colours.size() >= SHADES else PackedColorArray([colours[0]]) + colours
	if _ramp_rows.has(shades):
		return TABLE_SOURCE + int(_ramp_rows[shades])
	var row: int = _next_ramp
	_next_ramp = (_next_ramp + 1) % RAMPS
	for key: Variant in _ramp_rows.keys():
		if int(_ramp_rows[key]) == row:
			_ramp_rows.erase(key)
	_ramp_rows[shades] = row
	for shade in SHADES:
		_ramp_image.set_pixel(shade, row, shades[mini(shade, shades.size() - 1)])
	_ramp_texture.update(_ramp_image)
	return TABLE_SOURCE + row


## The colour of shade `shade` (0 white-hot ... 3 shadow) of the ramp table's row for `source`
## (for tests).
func table_shade(source: int, shade: int) -> Color:
	return _ramp_image.get_pixel(shade, source - TABLE_SOURCE)


## A shot of the look `look` and core colour `core`, of an actor of `ramp`, sheds its motes at
## `at`: each kind of its cards (`kinds_of_look`) throws its share of its burst (`scale` of its
## count, split between them) along `dir`, in the shot's own ramp.
func shed(at: Vector2, dir: Vector2, core: Color, ramp: int, look: int, scale: float = 1.0) -> void:
	var found: PackedInt32Array = kinds_of_look(look)
	var source: int = spell_source(ramp, look)
	for k in found:
		throw(k, at, dir, source, core, scale / float(found.size()))


## The shots' trail particles (spell spectacle P1d): the births `births` holds (`count` of them,
## core/projectiles' `spark_births`, BIRTH_STRIDE floats each), one mote each: a kind of its look
## kind's layer (`kinds_of_layer`), given off back along the shot within its kind's spread at
## TRAIL_SPEED of its burst speed and speed up, in the shot's own ramp. The rows are written here
## rather than by a one-mote `burst` each (a birth costs about a third as much).
func give_off(births: PackedFloat32Array, count: int) -> void:
	count = mini(count, births.size() / BIRTH_STRIDE)
	if density != 1.0:
		count = floori(float(count) * density + _rng.randf())
	count = mini(count, _rows_left)
	if count <= 0:
		return
	_rows_left -= count
	var chunk: int = -1
	var buffer: PackedFloat32Array
	for n in count:
		var b: int = n * BIRTH_STRIDE
		var found: PackedInt32Array = kinds_of_layer(int(births[b + 4]))
		if found.is_empty():
			continue
		var k: int = found[0] if found.size() == 1 else found[_rng.randi_range(0, found.size() - 1)]
		var kind: MoteKind = _kinds[k]
		var row: int = _next
		_next = (_next + 1) % _cap
		var c: int = row / CHUNK
		if c != chunk:
			chunk = c
			buffer = _chunk(c)
			_dirty[c] = 1
		var half: float = deg_to_rad(kind.spread) * 0.5
		var v: Vector2 = Vector2(births[b + 2], births[b + 3]).rotated(_rng.randf_range(-half, half)) * (_rng.randf_range(kind.speed.x, kind.speed.y) * TRAIL_SPEED)
		var height: float = _step255(kind.height, HEIGHT_MAX)
		var i: int = (row - c * CHUNK) * DRAW_STRIDE
		buffer[i] = v.x
		buffer[i + 1] = _now
		buffer[i + 3] = births[b]
		buffer[i + 4] = v.y
		buffer[i + 5] = _rng.randf_range(kind.up.x, kind.up.y) * TRAIL_SPEED
		buffer[i + 7] = births[b + 1] + height
		buffer[i + 8] = float(spell_source(int(births[b + 5]), int(births[b + 6]))) / SOURCE_CODE
		buffer[i + 9] = float(k) / KIND_CODE
		buffer[i + 10] = _step255(clampf(_rng.randf_range(kind.life.x, kind.life.y), 0.02, LIFE_MAX), LIFE_MAX) / LIFE_MAX
		buffer[i + 11] = height / HEIGHT_MAX
		buffer[i + 12] = births[b + 7]
		buffer[i + 13] = births[b + 8]
		buffer[i + 14] = births[b + 9]
		buffer[i + 15] = _rng.randf()


## The kinds of look layer `layer` (a look kind, LOOK_*), else those of layer 0.
func kinds_of_layer(layer: int) -> PackedInt32Array:
	if layer > 0 and layer <= LOOK_LAYERS and not _layer_kinds[layer].is_empty():
		return _layer_kinds[layer]
	return _layer_kinds[0]


## Throw a burst of kind `k` (its count times `scale`, at least one; its speed, spread, up, life
## and height) from `at` along `dir`, from `source` (`spell_source`, `table_source`) with the core
## colour `core` (a spell's; white for none).
func throw(k: int, at: Vector2, dir: Vector2, source: int, core: Color, scale: float = 1.0) -> void:
	if k < 0 or k >= _kinds.size() or source < 0:
		return
	var kind: MoteKind = _kinds[k]
	burst(k, at, dir, maxi(roundi(float(kind.count) * scale), 1), kind.speed, kind.spread, kind.up, kind.life, source, core, kind.height)


## Throw kind `k`'s burst as a cue's part says (`CueBase`, a `motes` part): `count` motes (its
## own count when below 0), flying out to `reach` pixels at the most (its own speed when 0; the
## farthest a mote of its drag glides), within `spread` degrees (its own when below 0), `up` times
## its own speed up, all as fast as the fastest when `ring` (a ring going out).
func throw_part(k: int, at: Vector2, dir: Vector2, source: int, core: Color, count: int, reach: float, spread: float, up: float, ring: bool) -> void:
	if k < 0 or k >= _kinds.size() or source < 0:
		return
	var kind: MoteKind = _kinds[k]
	var speed: Vector2 = kind.speed
	if reach > 0.0:
		# A mote slowed by drag d from speed v glides v / d; with no drag, v for its life.
		var top: float = reach * kind.drag if kind.drag > 0.0 else reach / maxf(kind.life.y, 0.05)
		speed = Vector2(top * (kind.speed.x / maxf(kind.speed.y, 0.001)), top)
	if ring:
		speed.x = speed.y * 0.9
	burst(k, at, dir, kind.count if count < 0 else count, speed, kind.spread if spread < 0.0 else spread, kind.up * up, kind.life, source, core, kind.height)


## Throw `count` motes (times `density`) of kind `k` from `at` (where they show; their ground
## point is `height` pixels below it): along the floor within `spread` degrees round `dir` (all
## round with 360 or no `dir`), at a speed in `speed` (x to y, px/s), up at a speed in `up`, living
## a time in `life` (s, at most LIFE_MAX), cooling through the ramp of `source` with the core
## colour `core`. Fewer when the frame's FRAME_ROWS run out.
func burst(k: int, at: Vector2, dir: Vector2, count: int, speed: Vector2, spread: float, up: Vector2, life: Vector2, source: int, core: Color, height: float = 0.0) -> void:
	if density != 1.0:
		count = floori(float(count) * density + _rng.randf())
	count = mini(count, _rows_left)
	if count <= 0 or not at.is_finite() or k < 0 or k >= _kinds.size() or source < 0:
		return
	_rows_left -= count
	var aim: float = dir.angle() if dir != Vector2.ZERO else 0.0
	var half: float = deg_to_rad(clampf(spread, 0.0, 360.0)) * 0.5
	height = _step255(height, HEIGHT_MAX)
	var ground: Vector2 = at + Vector2(0.0, height)
	var coded_source: float = float(source) / SOURCE_CODE
	var coded_height: float = height / HEIGHT_MAX
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
		buffer[i + 8] = coded_source
		buffer[i + 9] = float(k) / KIND_CODE
		buffer[i + 10] = _step255(clampf(_rng.randf_range(life.x, life.y), 0.02, LIFE_MAX), LIFE_MAX) / LIFE_MAX
		buffer[i + 11] = coded_height
		buffer[i + 12] = core.r
		buffer[i + 13] = core.g
		buffer[i + 14] = core.b
		buffer[i + 15] = _rng.randf()


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


## A shader parameter of the motes' material (for tests).
func shader_parameter(name: StringName) -> Variant:
	return _material.get_shader_parameter(name)


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
	return flight(Vector2(buffer[i + 3], buffer[i + 7]), Vector2(buffer[i], buffer[i + 4]), buffer[i + 11] * HEIGHT_MAX, buffer[i + 5], now - buffer[i + 1], _kind_of(buffer, i), buffer[i + 15])


## Where and when mote `row` comes to rest on the floor: its point (x, y) and the clock time (z);
## INF for z when it never does in its life (a kind that rises, or one gone before it lands).
func mote_land(row: int) -> Vector3:
	var buffer: PackedFloat32Array = _buffers[row / CHUNK]
	var i: int = (row % CHUNK) * DRAW_STRIDE
	var k: int = _kind_of(buffer, i)
	var h0: float = buffer[i + 11] * HEIGHT_MAX
	var rest: float = rest_time(k, h0, buffer[i + 5])
	if rest >= buffer[i + 10] * LIFE_MAX:
		return Vector3(INF, INF, INF)
	var at: Vector3 = flight(Vector2(buffer[i + 3], buffer[i + 7]), Vector2(buffer[i], buffer[i + 4]), h0, buffer[i + 5], rest, k, buffer[i + 15])
	return Vector3(at.x, at.y, buffer[i + 1] + rest)


## The row of mote `row` as the shader reads it (a copy, for tests).
func row_data(row: int) -> PackedFloat32Array:
	var i: int = (row % CHUNK) * DRAW_STRIDE
	return _buffers[row / CHUNK].slice(i, i + DRAW_STRIDE)


## Seconds after its birth a mote of kind `k` born `h0` above the floor, going up at `vz`, comes
## to rest (after its one bounce); INF for a kind that never falls.
func rest_time(k: int, h0: float, vz: float) -> float:
	var g: float = _kinds[k].gravity
	if g <= 0.0:
		return INF
	var land: float = (vz + sqrt(vz * vz + 2.0 * g * maxf(h0, 0.0))) / g
	var rebound: float = (g * land - vz) * _kinds[k].bounce
	return land + 2.0 * rebound / g


## The shader's `mote_flight`: where a mote of kind `k` is `t` seconds after its birth at the
## ground point `from` with the velocity `vel`, the height `h0` and the height's velocity `vz`:
## its ground point (x, y) and its height (z).
func flight(from: Vector2, vel: Vector2, h0: float, vz: float, t: float, k: int, seed: float) -> Vector3:
	var kind: MoteKind = _kinds[k]
	var g: float = kind.gravity
	var land: float = 1.0e9
	var rest: float = 1.0e9
	var rebound: float = 0.0
	if g > 0.0:
		land = (vz + sqrt(vz * vz + 2.0 * g * maxf(h0, 0.0))) / g
		rebound = (g * land - vz) * kind.bounce
		rest = land + 2.0 * rebound / g
	var tm: float = minf(maxf(t, 0.0), rest)
	var h: float = 0.0
	if tm < land:
		h = h0 + vz * tm - 0.5 * g * tm * tm
	elif tm < rest:
		var s: float = tm - land
		h = rebound * s - 0.5 * g * s * s
	var drag: float = kind.drag
	var along: float = (1.0 - exp(-drag * tm)) / drag if drag > 0.0 else tm
	var ground: Vector2 = from + vel * along
	var phase: float = seed * 6.2832
	ground.x += kind.wobble * (sin(tm * kind.wobble_rate + phase) - sin(phase))
	return Vector3(ground.x, ground.y, maxf(h, 0.0))


func _kind_of(buffer: PackedFloat32Array, i: int) -> int:
	return clampi(roundi(buffer[i + 9] * KIND_CODE), 0, MAX_KINDS - 1)


## The shape atlas's pixel (MoteKind.PIXEL_*) of kind `k`'s frame `frame` at `x`, `y` of its
## square (the mote's own pixel in the middle) (for tests).
func shape_value(k: int, frame: int, x: int, y: int) -> int:
	var size: int = MoteKind.SHAPE_SIZE
	return roundi(_shape_image.get_pixel(frame * size + x, k * size + y).r * 2.0)


## `value` (0 to `most`) in steps of 1/255 of `most`.
static func _step255(value: float, most: float) -> float:
	return roundf(clampf(value, 0.0, most) / most * 255.0) / 255.0 * most


## Keep the kinds with no problems (MAX_KINDS at most), index them by look layer and hand their
## numbers to the shader.
func _take_kinds(kinds: Array[MoteKind]) -> void:
	_layer_kinds.resize(LOOK_LAYERS + 1)
	for layer in LOOK_LAYERS + 1:
		_layer_kinds[layer] = PackedInt32Array()
	var motion := PackedVector4Array()
	var sway := PackedVector4Array()
	var shapes := PackedVector4Array()
	motion.resize(MAX_KINDS)
	sway.resize(MAX_KINDS)
	shapes.resize(MAX_KINDS)
	var size: int = MoteKind.SHAPE_SIZE
	_shape_image = Image.create_empty(size * MoteKind.SHAPE_FRAMES, size * MAX_KINDS, false, Image.FORMAT_RGBA8)
	for kind in kinds:
		if kind == null or not kind.problems().is_empty():
			continue
		if _kinds.size() >= MAX_KINDS:
			push_warning("Motes: more than %d mote kinds; '%s' is left out" % [MAX_KINDS, kind.id])
			continue
		var k: int = _kinds.size()
		_kinds.append(kind)
		motion[k] = Vector4(kind.gravity, kind.drag, kind.bounce, kind.glow)
		sway[k] = Vector4(kind.wobble, kind.wobble_rate, float(kind.shade_from), 0.0)
		var frames: int = kind.shape_frames().size()
		shapes[k] = Vector4(float(frames), float(MoteKind.SHAPE_PLAYS.find(kind.shape_play)), kind.shape_rate, 1.0 if kind.shape_turns else 0.0)
		for frame in frames:
			var pixels: PackedByteArray = kind.shape_pixels(frame)
			for y in size:
				for x in size:
					var value: float = float(pixels[y * size + x]) * 0.5
					_shape_image.set_pixel(frame * size + x, k * size + y, Color(value, value, value, 1.0))
		if kind.surface:
			_surface_kinds.append(k)
		for layer in kind.look_layers:
			_layer_kinds[layer].append(k)
	_material.set_shader_parameter(&"kind_motion", motion)
	_material.set_shader_parameter(&"kind_sway", sway)
	_material.set_shader_parameter(&"kind_shape", shapes)
	_material.set_shader_parameter(&"shape_atlas", ImageTexture.create_from_image(_shape_image))


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
