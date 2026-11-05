extends Node2D
## Motes (docs/milestones/spell-spectacle.md, P1): up to tens of thousands of single-pixel
## particles with no game logic, drawn by Feel. A mote is thrown from a point with a velocity
## along the floor, a fake height and a velocity up; `gameplay/feel/mote.gdshader` works out its
## whole flight from its burst's row, its own number in the burst and the time since its birth (it
## flies with drag, rises or falls, lands, bounces once, lies still and cools through its ramp's
## shades). The CPU writes a burst's row once and never touches it again: there is no per-frame
## simulation, and no per-mote write (S4: a burst a row).
##
## **Kinds are data** (`MoteKind`, `content/motes/`): how one flies and how many a burst throws.
## The pool takes them when it is made and hands their numbers to the shader as a texture
## (`kind_table`: a row a kind, KIND_COLUMNS texels across; up to MAX_KINDS kinds, so content can
## grow with no shader edit) and their shapes' frames (`shape_atlas`, a texture of
## MoteKind.SHAPE_SIZE squares, a kind's frames along a row), so a new kind, or a new shape, is a
## new file. A spell's kinds come from its cards: those that name a card (`kinds_of_card`) and,
## for its other cards, those that name their look layers (`kinds_of_look`). The spectacle works
## a spell's out (`card_kinds.gd`, by the shot's tag) and hands them to `shed_kinds`; a shot with
## no spell sheds by its look (`shed`).
##
## **Colours are never here.** A mote cools through a ramp of four shades (white-hot, light, base,
## shadow) named by its source (`spell_source`, `table_source`): a spell's motes take the shot's
## own ramp, picked in the shader by the shot shaders' rule (`look_of` in `shot_look.gdshaderinc`:
## the caster's hat ramp for a plain core, else the palette material nearest its core, or the
## exact colour); any other colours (a room's walls, `RoomBase.surface_colors`) go into the ramp
## table (`ramp_table`, a texture of RAMPS rows, `ramp_table.gd`; Feel shares one with the floor
## marks) and are named by their row.
##
## The pool is three rings of rows (sized from `cap`, the "Particles" setting, `MoteCap` in
## core/settings), one for each size of row (1, QUAD_ROW, BURST_QUADS quads): a new burst takes
## the next rows of its ring and overwrites the oldest. Each ring is cut into chunks of CHUNK
## quads, one `MultiMeshInstance2D` each (made by `Batches.multimesh()`, so it is never culled;
## made the first time a row lands in it). `step` uploads only the chunks written since the last
## frame, never a whole ring; a chunk whose motes are all gone (by the longest life each of its
## bursts could give) is hidden and costs no vertices. Nothing is allocated while playing, past a
## chunk's first use. A burst's call costs the CPU about 2.5 us whatever its size (its row's numbers
## are packed once, a kind's own kept packed: `_kind_packs`), so at most FRAME_ROWS rows are
## written between two steps: a burst past that is cut short, and a shed once they are used up
## costs next to nothing (a storm's flood of hits stays within its budget).
##
## Every row is written by `_write` (`burst`, `shed`, `throw`, `throw_part`, `crumble` and the
## trails' `give_off` all end there), at the names ROW_*. `flight` is the shader's `mote_flight`
## line for line (a test holds the two to it); `mote_land` gives where and when a mote comes to
## rest. **Settled motes** (P2b): a kind that names a floor mark (`MoteKind.settles`) leaves it
## where each of its motes comes to rest, at that time (`settle_into` names the mark layer;
## `Marks.settle` keeps it until then; SETTLE_ROWS a frame in a flood): the CPU works the resting
## motes out from the same seed and hash (`_land`), only for those.

const SHADER: Shader = preload("res://gameplay/feel/mote.gdshader")
const BatchesScript := preload("res://core/projectiles/batches.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")
const MarksScript := preload("res://gameplay/feel/marks.gd")
const NativeScript := preload("res://core/native/native.gd")

## A row is a burst (spell spectacle 2, S4): where, which way, the kind, how many, a seed, the
## source and the time. Its batch draws a quad per mote it can hold and the vertex shader works out
## each mote from the row, its quad's number and the seed (`mote_randoms`, the same integer hash on
## both sides), so a burst of 40 is three rows, not 40 writes. A quad past a row's count is still
## sent through the vertex stage (folded away), so there are three rings by a row's quads: SINGLES
## (one) for bursts of fewer than SPLIT motes (a trail's birth, a death's pixel), QUADS (QUAD_ROW)
## for those of fewer than BURST_QUADS, BURSTS (BURST_QUADS) for the rest.
const SINGLES: int = 0
const QUADS: int = 1
const BURSTS: int = 2
const RINGS: int = 3
const SPLIT: int = 3
const QUAD_ROW: int = 4
const BURST_QUADS: int = 16
## Quads in a chunk of each ring (one batch, uploaded whole when any of its rows is written).
const CHUNK: int = 1024
## Each ring's rows, as a share of the cap (the motes the setting names): SINGLES cap / 2, QUADS
## and BURSTS the cap's motes at a full row each.
const SINGLES_SHARE: int = 2
## Floats in a row: the transform (8), the colour (4) and the custom data (4).
const DRAW_STRIDE: int = 16
## Where a row's numbers are (mote.gdshader's header says where it reads each). The transform's
## eight floats are full floats; three of them hold two 12-bit numbers each (`_pair`), two a 24-bit
## seed and the birth. The colour and custom data are 0-1 in byte steps.
const ROW_AIM: int = 0
const ROW_BORN: int = 1
const ROW_SEED: int = 2
const ROW_X: int = 3
const ROW_SPEED: int = 4
const ROW_UP: int = 5
const ROW_LIFE: int = 6
const ROW_Y: int = 7
const ROW_SOURCE: int = 8
const ROW_KIND: int = 9
const ROW_COUNT: int = 10
const ROW_HEIGHT: int = 11
const ROW_CORE: int = 12
## A 12-bit number's steps: a way (a 4,096th of a turn), half a spread (a 4,095th of half a turn),
## a speed (a quarter px/s, 0 to 1,023.75), a speed up (a quarter px/s, -512 to 511.75), a life
## (a 4,095th of LIFE_MAX).
const AIM_STEP: float = TAU / 4096.0
const HALF_STEP: float = PI / 4095.0
const SPEED_STEP: float = 0.25
const UP_LOW: float = -512.0
const LIFE_STEP: float = MoteKind.LIFE_MAX / 4095.0
## A burst's numbers packed once (`_pack_into`): where each is.
const PACK_HALF: int = 0
const PACK_SPEED: int = 1
const PACK_UP: int = 2
const PACK_LIFE: int = 3
const PACK_LONGEST: int = 4
const PACK_SIZE: int = 5
## The longest life a mote has (s; MoteKind's, which checks the kinds against it).
const LIFE_MAX: float = MoteKind.LIFE_MAX
## The most rows written between two steps (a row is a burst: up to 1, QUAD_ROW or BURST_QUADS
## motes), and of them the rows a shot's hit, end or wall hit (`shed`, `throw`: hundreds a frame
## in a storm, a few motes each) leave for the moments (`throw_part`, `burst`: a cue's or a
## reaction's, tens or a hundred in one burst, so a blast in a storm still throws its motes). The
## sandbox storm (S4, docs/DECISIONS.md) writes 368 motes a frame at 256 rows for the CPU 156
## one-mote rows cost before, and 178 at 128 rows for about two thirds of it; a burst's call costs
## about 2.5 us whatever its size. Kept at 256: a dead body's crumble is a row a pixel (up to 160).
const FRAME_ROWS: int = 256
const MOMENT_ROWS: int = 128
## `frame_rows` is FRAME_ROWS unless a benchmark or the "Tailless motes" dev slider sets it (the
## moments keep the same share).
## The motes that leave a settled mark (`MoteKind.settles`): SETTLE_ROWS more may each frame, and
## what a frame leaves unused is kept, up to SETTLE_MOST. Working out where a mote rests and
## handing it to the mark layer costs about as much as writing a row (the integration of P1c, P1d
## and P2b; docs/DECISIONS.md), so each settle also takes one of the frame's rows (FRAME_ROWS
## bounds the motes' whole time), a storm's flood settles at most SETTLE_ROWS a frame (1,440 specks
## a second) and the rest only fade (`settles_skipped`), and a blast in a quiet room settles all of
## its chips.
const SETTLE_ROWS: int = 24
const SETTLE_MOST: int = 128
## The most kinds the shader holds (rows of its `kind_table`), and the table's texels a row: the
## motion (gravity, drag, bounce, glow), the sway (sway, its rate, first shade, reach) and the
## shape (frames, play, rate, turns).
const MAX_KINDS: int = 256
const KIND_COLUMNS: int = 3
## Rows of the ramp table (colours other than a spell's), and its shades a row.
const RAMPS: int = RampTableScript.ROWS
const SHADES: int = RampTableScript.SHADES
## A source (a row's first colour channel): 0-3 a hat ramp, ENEMY_SOURCE the enemies', plus
## EXACT_SOURCE for a shot of an exact colour; from TABLE_SOURCE on, a row of the ramp table.
const ENEMY_SOURCE: int = 4
const EXACT_SOURCE: int = 8
const TABLE_SOURCE: int = RampTableScript.TABLE_SOURCE
## A look's flags (core/projectiles: LOOK_ENEMY_RAMP, and Feel's EXACT, the bit past it), and its
## card layers (1 to LOOK_LAYERS; layer n is bit n - 1; 0 is a plain shot).
const LOOK_ENEMY_RAMP: int = ProjectilesScript.LOOK_ENEMY_RAMP
const LOOK_EXACT: int = ProjectilesScript.LOOK_ENEMY_RAMP << 1
const LOOK_LAYERS: int = MoteKind.LOOK_LAYERS
## What a row's colour channels are divided by, so every one is between 0 and 1 (the shader's
## SOURCE_CODE, KIND_CODE, HEIGHT_MAX; LIFE_MAX for the life; the second channel is the kind). The life and the height are
## written in steps of 1/255 of their most (the height in quarter pixels), so a renderer that
## keeps the colour as bytes reads the same numbers `flight` does.
const SOURCE_CODE: float = 128.0
const KIND_CODE: float = 255.0
const HEIGHT_MAX: float = 63.75
## A trail particle's speed (and its speed up), as a share of its kind's burst (`give_off`): given
## off, not thrown. A birth's floats and where its numbers are: core/projectiles' SPARK_*.
const TRAIL_SPEED: float = 0.3
const BIRTH_STRIDE: int = ProjectilesScript.SPARK_BIRTH_STRIDE
## The native births (`MoteKernel`, `give_off`): a pair's key is its spell's tag times PAIR_LAYERS
## plus its look kind plus one (the streak's kind is -1); a settle handed back is SETTLE_STRIDE
## numbers (the mark, the point x and y, the time, the source, the core r, g, b, the serial).
const PAIR_LAYERS: int = 64
const SETTLE_STRIDE: int = 9

## Uploads of a chunk's buffer since this pool was made, the motes written, the bursts the frame's
## FRAME_ROWS cut short or left out, the trail births given off, and the settling motes handed to
## the mark layer and those past the frame's SETTLE_ROWS (for tests and the benchmarks).
var uploads: int = 0
var written: int = 0
var cut: int = 0
var births: int = 0
var settles: int = 0
var settles_skipped: int = 0
## Every burst's count is times this (the "Particle amount" setting, `MoteDensity`; 0 throws
## none). A share of a mote is thrown that often, so the average holds.
var density: float = 1.0
var frame_rows: int = FRAME_ROWS:
	set(value):
		frame_rows = value
		_moment_rows = value * MOMENT_ROWS / FRAME_ROWS
var _moment_rows: int = MOMENT_ROWS

var _cap: int = 0
## The kinds, in the order the shader holds them, and for each look layer (0-21) the kinds that
## are its motes; the surface kinds.
var _kinds: Array[MoteKind] = []
## Each kind's index by its id (`kind_index`: a cue's named kind is looked up on every hit, S6 2).
var _kind_at: Dictionary = {}
var _layer_kinds: Array[PackedInt32Array] = []
var _surface_kinds: PackedInt32Array = PackedInt32Array()
## The kinds a dash gives off along its path (`MoteKind.dash_path`; its births of SPARK_STREAK).
var _dash_kinds: PackedInt32Array = PackedInt32Array()
## The kinds that name each card by id (`MoteKind.cards`).
var _card_kinds: Dictionary[StringName, PackedInt32Array] = {}
## The trails' births' kinds by their shot's spell (`card_kinds.gd`, the spectacle's: anything
## with `layer_motes(tag, layer)`), or null: by their look layer only.
var _cards: Object = null
## `kinds_of_look`'s answers, by a look's layer bits (a shot's hit or end asks it, hundreds of
## times a frame in a storm; there are few looks).
var _look_kinds: Dictionary[int, PackedInt32Array] = {}
## Per ring: its rows, rows a chunk, quads a row, its first chunk and the next row a burst takes.
var _ring_rows: PackedInt32Array = PackedInt32Array([0, 0, 0])
var _ring_chunk: PackedInt32Array = PackedInt32Array([CHUNK, CHUNK / QUAD_ROW, CHUNK / BURST_QUADS])
var _ring_quads: PackedInt32Array = PackedInt32Array([1, QUAD_ROW, BURST_QUADS])
var _ring_first: PackedInt32Array = PackedInt32Array([0, 0, 0])
var _ring_next: PackedInt32Array = PackedInt32Array([0, 0, 0])
## Rows written to each ring since the pool was made: a settling mote's serial is its row's (in
## the ring's serial space), so the mark layer forgets a settle whose row the ring overwrote
## before it came to rest.
var _ring_written: PackedInt32Array = PackedInt32Array([0, 0, 0])
## Per chunk (every ring's, in ring order): its batch (null until its first mote), its rows, written since the last upload, and
## the clock time its last mote is gone by (its birth plus the longest life its burst could give).
var _nodes: Array[MultiMeshInstance2D] = []
var _buffers: Array[PackedFloat32Array] = []
var _dirty: PackedByteArray = PackedByteArray()
var _until: PackedFloat32Array = PackedFloat32Array()
## The clock motes are born on (Feel's, from `step`).
var _now: float = 0.0
## Motes that may still be written before the next step (FRAME_ROWS), the rows of them a burst
## leaves (MOMENT_ROWS while a shed or a wall's throw writes), and the settles left (SETTLE_ROWS a
## frame, kept up to SETTLE_MOST).
var _rows_left: int = FRAME_ROWS
var _keep: int = 0
var _settles_left: int = SETTLE_MOST
## The ramp table (its own, or the one Feel shares with the floor marks).
var _table: RampTableScript = null
## The mark layer settled motes go to (null for none), and per kind the mark it leaves (-1 none).
var _marks: MarksScript = null
var _settle_marks: PackedInt32Array = PackedInt32Array()
## The shapes' frames: SHAPE_SIZE squares, a kind's along its row (`shape_value`).
var _shape_image: Image = null
var _kind_image: Image = null
var _material: ShaderMaterial = null
var _meshes: Array[ArrayMesh] = []
var _z: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Per kind its own numbers packed (a shed's and a throw's), and a trail's (TRAIL_SPEED of its
## speeds); a burst's own, packed for each call.
var _kind_packs: Array[PackedFloat32Array] = []
var _trail_packs: Array[PackedFloat32Array] = []
var _pack: PackedFloat32Array = PackedFloat32Array()
## The native kernel (`MoteKernel`, native/README.md): the trails' births written in C++, the same
## to the bit, or null to write them here. `native` switches it.
var native: bool = true:
	set = set_native
var _kernel: Object = null
## Each kind's height and flight numbers, for the kernel (made with the kinds; its trail numbers are
## `_trail_packs`).
var _k_height: PackedFloat64Array = PackedFloat64Array()
var _k_gravity: PackedFloat64Array = PackedFloat64Array()
var _k_bounce: PackedFloat64Array = PackedFloat64Array()
var _k_drag: PackedFloat64Array = PackedFloat64Array()
var _k_wobble: PackedFloat64Array = PackedFloat64Array()
var _k_wobble_rate: PackedFloat64Array = PackedFloat64Array()
## The native births' pairs (`MoteKernel.key_births`): each birth's pair, the pairs' keys, and the
## kinds of each pair (from `_pair_from`, `_pair_size` of them, in `_pair_kinds`); the settles the
## kernel hands back (SETTLE_STRIDE numbers each).
var _birth_pair: PackedInt32Array = PackedInt32Array()
var _pair_key: PackedInt64Array = PackedInt64Array()
var _pair_from: PackedInt32Array = PackedInt32Array()
var _pair_size: PackedInt32Array = PackedInt32Array()
var _pair_kinds: PackedInt32Array = PackedInt32Array()
var _settle_out: PackedFloat64Array = PackedFloat64Array()


## A pool of `cap` rows (above 0) of the kinds `kinds` (at most MAX_KINDS; a kind with problems
## is left out), its batches drawn at `z`, its colours other than a spell's in `table` (a table
## of its own when null).
func _init(cap: int, z: int, kinds: Array[MoteKind], table: RampTableScript = null) -> void:
	top_level = true
	_cap = maxi(cap, 1)
	_z = z
	_rng.seed = 7
	var chunks: int = 0
	for ring in RINGS:
		_ring_rows[ring] = maxi(_cap / (SINGLES_SHARE if ring == SINGLES else _ring_quads[ring]), 1)
		_ring_first[ring] = chunks
		chunks += ceili(float(_ring_rows[ring]) / _ring_chunk[ring])
	_nodes.resize(chunks)
	_buffers.resize(chunks)
	_dirty.resize(chunks)
	_until.resize(chunks)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_meshes = [_quads(1), _quads(QUAD_ROW), _quads(BURST_QUADS)]
	_pack.resize(PACK_SIZE)
	_table = table if table != null else RampTableScript.new()
	_material.set_shader_parameter(&"ramp_table", _table.texture())
	_take_kinds(kinds)
	_birth_pair.resize(ProjectilesScript.SPARK_BIRTHS_MAX)
	_pair_key.resize(ProjectilesScript.SPARK_BIRTHS_MAX)
	_pair_from.resize(ProjectilesScript.SPARK_BIRTHS_MAX)
	_pair_size.resize(ProjectilesScript.SPARK_BIRTHS_MAX)
	_pair_kinds.resize(64)
	_settle_out.resize(SETTLE_MOST * SETTLE_STRIDE)
	set_native(native)


## Write the trails' births with the native kernel when `on` and the module is loaded (see
## `native`). The kernel is handed the numbers it needs and checks the members it reads.
func set_native(on: bool) -> void:
	native = on
	_kernel = NativeScript.mote_kernel() if on else null
	if _kernel == null:
		return
	var numbers: Dictionary = {
		"DRAW_STRIDE": DRAW_STRIDE, "BIRTH_STRIDE": BIRTH_STRIDE, "SETTLE_STRIDE": SETTLE_STRIDE,
		"SINGLES": SINGLES, "SERIAL_BITS": MarksScript.SERIAL_BITS,
		"ROW_AIM": ROW_AIM, "ROW_BORN": ROW_BORN, "ROW_SEED": ROW_SEED, "ROW_X": ROW_X, "ROW_SPEED": ROW_SPEED,
		"ROW_UP": ROW_UP, "ROW_LIFE": ROW_LIFE, "ROW_Y": ROW_Y, "ROW_SOURCE": ROW_SOURCE, "ROW_KIND": ROW_KIND,
		"ROW_COUNT": ROW_COUNT, "ROW_HEIGHT": ROW_HEIGHT, "ROW_CORE": ROW_CORE,
		"PACK_HALF": PACK_HALF, "PACK_SPEED": PACK_SPEED, "PACK_UP": PACK_UP, "PACK_LIFE": PACK_LIFE,
		"PACK_LONGEST": PACK_LONGEST, "PACK_SIZE": PACK_SIZE,
		"SPARK_X": ProjectilesScript.SPARK_X, "SPARK_Y": ProjectilesScript.SPARK_Y,
		"SPARK_BACK_X": ProjectilesScript.SPARK_BACK_X, "SPARK_BACK_Y": ProjectilesScript.SPARK_BACK_Y,
		"SPARK_KIND": ProjectilesScript.SPARK_KIND, "SPARK_RAMP": ProjectilesScript.SPARK_RAMP,
		"SPARK_LOOK": ProjectilesScript.SPARK_LOOK, "SPARK_CORE": ProjectilesScript.SPARK_CORE,
		"SPARK_TAG": ProjectilesScript.SPARK_TAG, "SPARK_TAG_BITS": ProjectilesScript.SPARK_TAG_BITS,
		"SPARK_STREAK": ProjectilesScript.SPARK_STREAK, "PAIR_LAYERS": PAIR_LAYERS,
		"ENEMY_SOURCE": ENEMY_SOURCE, "EXACT_SOURCE": EXACT_SOURCE, "LOOK_ENEMY_RAMP": LOOK_ENEMY_RAMP,
		"LOOK_EXACT": LOOK_EXACT, "HEIGHT_MAX": HEIGHT_MAX, "SOURCE_CODE": SOURCE_CODE, "KIND_CODE": KIND_CODE,
		"AIM_STEP": AIM_STEP, "HALF_STEP": HALF_STEP, "SPEED_STEP": SPEED_STEP, "UP_LOW": UP_LOW,
		"LIFE_STEP": LIFE_STEP,
	}
	var wrong: PackedStringArray = _kernel.call(&"check_fields", self)
	if not _kernel.call(&"configure", numbers):
		wrong.append("the motes' numbers")
	if not wrong.is_empty():
		push_error("Motes: the native MoteKernel does not match this script (%s); running the GDScript" % ", ".join(wrong))
		_kernel = null


## How many motes the ring holds.
func cap() -> int:
	return _cap


## The kinds, in the order the rows name them.
func kinds() -> Array[MoteKind]:
	return _kinds


## The index of the kind `id`, or -1.
func kind_index(id: StringName) -> int:
	return _kind_at.get(id, -1) as int


## The kinds that name the card `card` by id (`MoteKind.cards`); empty for none. Kept: read it,
## never change it.
func kinds_of_card(card: StringName) -> PackedInt32Array:
	var found: Variant = _card_kinds.get(card)
	return found if found != null else PackedInt32Array()


## Whether any kind names a card by id (when none does, every spell's kinds are its look's).
func has_card_kinds() -> bool:
	return not _card_kinds.is_empty()


## The kinds that name look layer `layer` (1 to LOOK_LAYERS; 0 a shot with none), with no
## fallback (`kinds_of_layer` falls back to layer 0's). Kept: read it, never change it.
func kinds_named_by_layer(layer: int) -> PackedInt32Array:
	return _layer_kinds[layer] if layer >= 0 and layer <= LOOK_LAYERS else PackedInt32Array()


## The trails' births take their shot's spell's kinds from `cards` (anything with
## `layer_motes(tag, layer) -> PackedInt32Array`; the spectacle's `card_kinds.gd`), null for their
## look layer's only.
func use_cards(cards: Object) -> void:
	_cards = cards


## The kinds a shot of the look `look` sheds (its cards' layers; LOOK_* bits, layer n is bit
## n - 1): every kind that names one of them, else the kinds of layer 0. The array is kept for
## the next ask: read it, never change it.
func kinds_of_look(look: int) -> PackedInt32Array:
	var layers: int = look & ((1 << LOOK_LAYERS) - 1)
	var known: Variant = _look_kinds.get(layers)
	if known != null:
		return known
	var found := PackedInt32Array()
	for layer in range(1, LOOK_LAYERS + 1):
		if (look >> (layer - 1)) & 1 == 1:
			for k in _layer_kinds[layer]:
				if not found.has(k):
					found.append(k)
	if found.is_empty():
		found = _layer_kinds[0].duplicate()
	_look_kinds[layers] = found
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
	return _table.source(colours)


## The colour of shade `shade` (0 white-hot ... 3 shadow) of the ramp table's row for `source`
## (for tests).
func table_shade(source: int, shade: int) -> Color:
	return _table.shade(source, shade)


## Settled motes go to the mark layer `marks` (null for none): each kind that names a mark
## (`MoteKind.settles`, a kind of `marks`) leaves it where each of its motes comes to rest.
func settle_into(marks: MarksScript) -> void:
	_marks = marks
	_settle_marks.resize(_kinds.size())
	for k in _kinds.size():
		var id: StringName = _kinds[k].settles
		# Only a kind that falls comes to rest (MoteKind's problems name one that cannot).
		_settle_marks[k] = marks.kind_index(id) if marks != null and id != &"" and _kinds[k].gravity > 0.0 else -1


## The mark kind of `marks` that kind `k`'s motes leave where they rest (-1 for none; for tests).
func settle_mark(k: int) -> int:
	return _settle_marks[k] if k >= 0 and k < _settle_marks.size() else -1


## A shot of the look `look` and core colour `core`, of an actor of `ramp`, sheds its motes at
## `at`: each kind of its cards (`kinds_of_look`) throws its share of its burst (`scale` of its
## count, split between them) along `dir`, in the shot's own ramp. It leaves the frame's last
## MOMENT_ROWS to the moments, and writes nothing once only they are left.
func shed(at: Vector2, dir: Vector2, core: Color, ramp: int, look: int, scale: float = 1.0) -> void:
	if _rows_left <= _moment_rows:
		cut += 1
		return
	shed_kinds(kinds_of_look(look), at, dir, core, ramp, look, scale)


## Whether a shed now writes nothing (only the frame's MOMENT_ROWS are left), counted as cut: ask it
## before working out a shed's kinds (`card_kinds.gd`), which costs more than a shed that is cut.
func shed_closed() -> bool:
	if _rows_left <= _moment_rows:
		cut += 1
		return true
	return false


## `shed` with the kinds `found` (a spell's, `card_kinds.gd`; never empty) in place of its look's.
func shed_kinds(found: PackedInt32Array, at: Vector2, dir: Vector2, core: Color, ramp: int, look: int, scale: float = 1.0) -> void:
	if _rows_left <= _moment_rows:
		cut += 1
		return
	if found.is_empty():
		return
	var source: int = spell_source(ramp, look)
	var share: float = scale / float(found.size())
	_keep = _moment_rows
	for k in found:
		_write(k, at, dir, maxi(roundi(float(_kinds[k].count) * share), 1), _kind_packs[k], source, core, _kinds[k].height)
	_keep = 0


## The shots' trail particles (spell spectacle P1d): the first `count` births of `births`
## (core/projectiles' `spark_births`, BIRTH_STRIDE floats each), one mote each (times `density`,
## as any burst): a kind of its look kind's layer (`kinds_of_layer`), given off back along the shot
## within its kind's spread at TRAIL_SPEED of its burst speed and speed up, in the shot's own ramp.
## A shot of a spell gives off its spell's kinds for that layer (`use_cards`); a dash's streak
## (SPARK_STREAK) is one of the dash path kinds (`MoteKind.dash_path`).
## Each is a one-mote burst (`_write`, its kind's numbers kept packed), so a trail's mote is
## written, counted and settled as every other.
func give_off(given: PackedFloat32Array, count: int) -> void:
	count = mini(count, given.size() / BIRTH_STRIDE)
	_ready_chunks()
	if _kernel != null:
		_give_off_native(given, count)
		return
	for n in count:
		if _rows_left <= 0:
			cut += count - n
			return
		var b: int = n * BIRTH_STRIDE
		var layer: int = int(given[b + ProjectilesScript.SPARK_KIND])
		var found: PackedInt32Array
		if layer == ProjectilesScript.SPARK_STREAK:
			found = _dash_kinds
		elif _cards != null:
			found = _cards.layer_motes(ProjectilesScript.spark_tag(given, b), layer)
		else:
			found = kinds_of_layer(layer)
		if found.is_empty():
			continue
		var k: int = found[0] if found.size() == 1 else found[_rng.randi_range(0, found.size() - 1)]
		births += 1
		_write(k, Vector2(given[b + ProjectilesScript.SPARK_X], given[b + ProjectilesScript.SPARK_Y]),
			Vector2(given[b + ProjectilesScript.SPARK_BACK_X], given[b + ProjectilesScript.SPARK_BACK_Y]),
			1, _trail_packs[k],
			spell_source(int(given[b + ProjectilesScript.SPARK_RAMP]), int(given[b + ProjectilesScript.SPARK_LOOK])),
			Color(given[b + ProjectilesScript.SPARK_CORE], given[b + ProjectilesScript.SPARK_CORE + 1], given[b + ProjectilesScript.SPARK_CORE + 2]),
			_kinds[k].height)


## `give_off` in the native kernel: it names each birth's (tag, kind) pair, the kinds of each pair
## are looked up here once (a script's lookup, `card_kinds.gd`), the kernel writes the rows, and
## the marks of the motes that settle are handed to the mark layer here.
func _give_off_native(given: PackedFloat32Array, count: int) -> void:
	count = mini(count, _birth_pair.size())
	var pairs: int = _kernel.call(&"key_births", self, given, count)
	var at: int = 0
	for p in pairs:
		var key: int = _pair_key[p]
		var layer: int = key % PAIR_LAYERS - 1
		var found: PackedInt32Array
		if layer == ProjectilesScript.SPARK_STREAK:
			found = _dash_kinds
		elif _cards != null:
			found = _cards.layer_motes(key / PAIR_LAYERS, layer)
		else:
			found = kinds_of_layer(layer)
		var size: int = found.size()
		_pair_from[p] = at
		_pair_size[p] = size
		if _pair_kinds.size() < at + size:
			_pair_kinds.resize(maxi(at + size, _pair_kinds.size() * 2))
		for i in size:
			_pair_kinds[at + i] = found[i]
		at += size
	var handed: int = _kernel.call(&"give_off", self, given, count, _marks != null)
	for s in handed:
		var o: int = s * SETTLE_STRIDE
		_marks.settle(int(_settle_out[o]), Vector2(_settle_out[o + 1], _settle_out[o + 2]), _settle_out[o + 3],
			int(_settle_out[o + 4]), Color(_settle_out[o + 5], _settle_out[o + 6], _settle_out[o + 7]), int(_settle_out[o + 8]))


## Make the SINGLES ring's chunks the frame's rows left may still reach from its next row (the
## native kernel writes the trails' one-mote rows there but makes no nodes).
func _ready_chunks() -> void:
	var rows: int = _ring_rows[SINGLES]
	var chunk_rows: int = _ring_chunk[SINGLES]
	var left: int = mini(_rows_left, rows)
	var row: int = _ring_next[SINGLES]
	while left > 0:
		var c: int = _ring_first[SINGLES] + row / chunk_rows
		if _nodes[c] == null:
			_chunk(c, SINGLES)
		var span: int = mini(chunk_rows - row % chunk_rows, mini(rows - row, left))
		left -= span
		row = (row + span) % rows


## The kinds a dash gives off along its path (`MoteKind.dash_path`). Kept: read it, never change it.
func dash_kinds() -> PackedInt32Array:
	return _dash_kinds


## The kinds of look layer `layer` (a look kind, LOOK_*), else those of layer 0.
func kinds_of_layer(layer: int) -> PackedInt32Array:
	if layer > 0 and layer <= LOOK_LAYERS and not _layer_kinds[layer].is_empty():
		return _layer_kinds[layer]
	return _layer_kinds[0]


## Throw a burst of kind `k` (its count times `scale`, at least one; its speed, spread, up, life
## and height) from `at` along `dir`, from `source` (`spell_source`, `table_source`) with the core
## colour `core` (a spell's; white for none). Like `shed`, it leaves the frame's last MOMENT_ROWS.
func throw(k: int, at: Vector2, dir: Vector2, source: int, core: Color, scale: float = 1.0) -> void:
	if _rows_left <= _moment_rows:
		cut += 1
		return
	if k < 0 or k >= _kinds.size() or source < 0:
		return
	var kind: MoteKind = _kinds[k]
	_keep = _moment_rows
	_write(k, at, dir, maxi(roundi(float(kind.count) * scale), 1), _kind_packs[k], source, core, kind.height)
	_keep = 0


## Throw kind `k`'s burst as a cue's part says (`CueBase`, a `motes` part): `count` motes (its
## own count when below 0), flying out to `reach` pixels at the most (its own speed when 0; the
## farthest a mote of its drag glides), within `spread` degrees (its own when below 0), `up` times
## its own speed up, all as fast as the fastest when `ring` (a ring going out). `often` for a source
## of many a frame (a hit's spray): it stops once only the frame's MOMENT_ROWS are left, as `shed`.
## With a `line`, each mote is thrown from a point of the line from `at` to `at + line` (a staff);
## `life` times the kind's own life (a quicker moment).
func throw_part(k: int, at: Vector2, dir: Vector2, source: int, core: Color, count: int, reach: float, spread: float, up: float, ring: bool, often: bool = false, line: Vector2 = Vector2.ZERO, life: float = 1.0) -> void:
	if k < 0 or k >= _kinds.size() or source < 0:
		return
	# One of many a frame (a hit's spray, S3): like `shed`, it leaves the moments' rows alone.
	if often and _rows_left <= _moment_rows:
		cut += 1
		return
	var kind: MoteKind = _kinds[k]
	var speed: Vector2 = kind.speed
	if reach > 0.0:
		# A mote slowed by drag d from speed v glides v / d; with no drag, v for its life.
		var top: float = reach * kind.drag if kind.drag > 0.0 else reach / maxf(kind.life.y, 0.05)
		speed = Vector2(top * (kind.speed.x / maxf(kind.speed.y, 0.001)), top)
	if ring:
		speed.x = speed.y * 0.9
	_keep = _moment_rows if often else 0
	burst(k, at, dir, kind.count if count < 0 else count, speed, kind.spread if spread < 0.0 else spread, kind.up * up, kind.life * life, source, core, kind.height, line)
	_keep = 0


## Throw `count` motes (times `density`) of kind `k` from `at` (where they show; their ground
## point is `height` pixels below it): along the floor within `spread` degrees round `dir` (all
## round with 360 or no `dir`), at a speed in `speed` (x to y, px/s), up at a speed in `up`, living
## a time in `life` (s, at most LIFE_MAX), cooling through the ramp of `source` with the core
## colour `core`; with a `line`, each from a point of the line from `at` to `at + line` at random
## (the native births never pass one, so `MoteKernel` mirrors this with none). Fewer when the
## frame's FRAME_ROWS run out. Every mote is written here: this is
## the one place a row is made. A kind that settles leaves its mark where each mote comes to rest
## (as many as SETTLE_ROWS allows).
func burst(k: int, at: Vector2, dir: Vector2, count: int, speed: Vector2, spread: float, up: Vector2, life: Vector2, source: int, core: Color, height: float = 0.0, line: Vector2 = Vector2.ZERO) -> void:
	if k < 0 or k >= _kinds.size():
		return
	_pack_into(_pack, speed, spread, up, life)
	_write(k, at, dir, count, _pack, source, core, height, line)


## A burst's numbers as its rows hold them, into `pack` (PACK_* floats): half its spread, its
## speeds, its speeds up and its lives as 12-bit pairs, and its longest life (s).
static func _pack_into(pack: PackedFloat32Array, speed: Vector2, spread: float, up: Vector2, life: Vector2) -> void:
	pack[PACK_HALF] = float(roundi(deg_to_rad(clampf(spread, 0.0, 360.0)) * 0.5 / HALF_STEP))
	pack[PACK_SPEED] = float((roundi(clampf(speed.x, 0.0, 1023.75) / SPEED_STEP) << 12) | roundi(clampf(speed.y, 0.0, 1023.75) / SPEED_STEP))
	pack[PACK_UP] = float((roundi((clampf(up.x, UP_LOW, -UP_LOW - SPEED_STEP) - UP_LOW) / SPEED_STEP) << 12) | roundi((clampf(up.y, UP_LOW, -UP_LOW - SPEED_STEP) - UP_LOW) / SPEED_STEP))
	pack[PACK_LIFE] = float((roundi(clampf(life.x, 0.02, LIFE_MAX) / LIFE_STEP) << 12) | roundi(clampf(life.y, 0.02, LIFE_MAX) / LIFE_STEP))
	pack[PACK_LONGEST] = clampf(life.y, 0.02, LIFE_MAX)


## Write `count` motes (times `density`) of kind `k` (valid) from `at` along `dir` with the numbers
## `pack` (`_pack_into`; a kind's own are kept, `_kind_packs`), `height` px above the floor: the one
## place rows are made. With a `line` each mote starts at its own point of the line from `at` to
## `at + line` (a row holds one ground point), so each is a row of its own, in SINGLES.
func _write(k: int, at: Vector2, dir: Vector2, count: int, pack: PackedFloat32Array, source: int, core: Color, height: float, line: Vector2 = Vector2.ZERO) -> void:
	if density != 1.0:
		count = floori(float(count) * density + _rng.randf())
	if count <= 0 or not at.is_finite() or source < 0:
		return
	var ring: int = SINGLES if count < SPLIT or line != Vector2.ZERO else (QUADS if count < BURST_QUADS else BURSTS)
	var quads: int = _ring_quads[ring]
	var rows: int = (count + quads - 1) / quads
	var room: int = _rows_left - _keep
	if rows > room:
		cut += 1
		rows = room
		if rows <= 0:
			return
		count = mini(count, rows * quads)
	# A settle costs about as much as a row, so it takes one of the frame's: the first `settling`
	# motes of a settling kind leave their marks while rows and SETTLE_ROWS last.
	var mark: int = _settle_marks[k] if _marks != null and k < _settle_marks.size() else -1
	var settling: int = 0
	if mark >= 0:
		settling = mini(mini(count, _settles_left), room - rows)
		_settles_left -= settling
		settles += settling
		settles_skipped += count - settling
	_rows_left -= rows + settling
	written += count
	# In steps of 1/255 of HEIGHT_MAX (a renderer may keep the row's colour as bytes).
	var coded_height: float = roundf(clampf(height, 0.0, HEIGHT_MAX) / HEIGHT_MAX * 255.0) / 255.0
	height = coded_height * HEIGHT_MAX
	var coded_aim: float = float(((roundi(dir.angle() / AIM_STEP) & 4095) << 12) | int(pack[PACK_HALF]))
	var coded_speed: float = pack[PACK_SPEED]
	var coded_up: float = pack[PACK_UP]
	var coded_life: float = pack[PACK_LIFE]
	var coded_source: float = float(source) / SOURCE_CODE
	var coded_kind: float = float(k) / KIND_CODE
	var until: float = _now + pack[PACK_LONGEST] + LIFE_STEP
	var per: int = count / rows
	var extra: int = count - per * rows
	var chunk_rows: int = _ring_chunk[ring]
	var first: int = _ring_first[ring]
	var ring_rows: int = _ring_rows[ring]
	var chunk: int = -1
	var buffer: PackedFloat32Array
	var settled: int = 0
	for r in rows:
		var row: int = _ring_next[ring]
		_ring_next[ring] = (row + 1) % ring_rows
		_ring_written[ring] += 1
		var c: int = first + row / chunk_rows
		if c != chunk:
			chunk = c
			if _nodes[c] == null:
				_chunk(c, ring)
			buffer = _buffers[c]
			_dirty[c] = 1
			_until[c] = maxf(_until[c], until)
		var i: int = (row % chunk_rows) * DRAW_STRIDE
		var n: int = per + (1 if r < extra else 0)
		var seed: int = _rng.randi() & 0xFFFFFF
		buffer[i + ROW_AIM] = coded_aim
		buffer[i + ROW_BORN] = _now
		buffer[i + ROW_SEED] = float(seed)
		var from: Vector2 = at if line == Vector2.ZERO else at + line * _rng.randf()
		buffer[i + ROW_X] = from.x
		buffer[i + ROW_SPEED] = coded_speed
		buffer[i + ROW_UP] = coded_up
		buffer[i + ROW_LIFE] = coded_life
		buffer[i + ROW_Y] = from.y + height
		buffer[i + ROW_SOURCE] = coded_source
		buffer[i + ROW_KIND] = coded_kind
		buffer[i + ROW_COUNT] = float(n) / 255.0
		buffer[i + ROW_HEIGHT] = coded_height
		buffer[i + ROW_CORE] = core.r
		buffer[i + ROW_CORE + 1] = core.g
		buffer[i + ROW_CORE + 2] = core.b
		# Where and when each settling mote rests (`mote_land`'s sum), for the mark it leaves there;
		# its serial lets the layer forget it if the ring writes over it first (`step`).
		var q: int = 0
		while settled < settling and q < n:
			var land: Vector3 = _land(buffer, i, k, q)
			if is_finite(land.z):
				_marks.settle(mark, Vector2(land.x, land.y).floor(), land.z, source, core, (ring << MarksScript.SERIAL_BITS) | (_ring_written[ring] - 1))
			settled += 1
			q += 1


## The hash both sides work a mote's randoms out with (`mote_hash` in mote.gdshader): 32-bit,
## its multipliers below 2^31 so a 64-bit int never overflows.
static func mote_hash(x: int) -> int:
	x &= 0xFFFFFFFF
	x ^= x >> 16
	x = (x * 2146121005) & 0xFFFFFFFF
	x ^= x >> 15
	x = (x * 739982445) & 0xFFFFFFFF
	x ^= x >> 12
	x = (x * 695872825) & 0xFFFFFFFF
	x ^= x >> 15
	return x


## Mote `q` of a row of seed `seed`: its way (-1 to 1 of the half spread), speed, speed up and life
## (0 to 1 between the row's two), and its own seed (0 to 1): the shader's `mote_randoms`.
static func mote_randoms(seed: int, q: int) -> PackedFloat32Array:
	var h1: int = mote_hash(seed * 16 + q)
	var h2: int = mote_hash(h1)
	return PackedFloat32Array([float(h1 >> 20) / 4096.0 * 2.0 - 1.0, float((h1 >> 8) & 4095) / 4096.0,
		float(h2 >> 20) / 4096.0, float((h2 >> 8) & 4095) / 4096.0, float(((h1 & 255) << 8) | (h2 & 255)) / 65536.0])


## Mote `q` of the row at `i` of `buffer` as the shader works it out: its velocity along the floor
## (x, y), its speed up (z), its life (w) and its seed (`mote_seed`).
func _mote(buffer: PackedFloat32Array, i: int, q: int) -> Array:
	var r: PackedFloat32Array = mote_randoms(int(buffer[i + ROW_SEED]), q)
	var aim: int = int(buffer[i + ROW_AIM])
	var way: float = float(aim >> 12) * AIM_STEP + r[0] * float(aim & 4095) * HALF_STEP
	var sp: int = int(buffer[i + ROW_SPEED])
	var speed: float = lerpf(float(sp >> 12) * SPEED_STEP, float(sp & 4095) * SPEED_STEP, r[1])
	var u: int = int(buffer[i + ROW_UP])
	var vz: float = lerpf(float(u >> 12) * SPEED_STEP + UP_LOW, float(u & 4095) * SPEED_STEP + UP_LOW, r[2])
	var l: int = int(buffer[i + ROW_LIFE])
	var life: float = lerpf(float(l >> 12) * LIFE_STEP, float(l & 4095) * LIFE_STEP, r[3])
	return [Vector4(cos(way) * speed, sin(way) * speed, vz, life), r[4]]


## Once a frame, at Feel's clock `now`: upload the chunks written since the last step, hide those
## with nothing alive, and move the shader's clock on.
func step(now: float) -> void:
	_now = now
	_rows_left = frame_rows
	_settles_left = mini(_settles_left + SETTLE_ROWS, SETTLE_MOST)
	if _marks != null:
		for ring in RINGS:
			_marks.forget_settles_before(_ring_written[ring] - _ring_rows[ring], ring)
	_material.set_shader_parameter(&"sim_time", now)
	for c in _nodes.size():
		var node: MultiMeshInstance2D = _nodes[c]
		if node == null:
			continue
		if _dirty[c] == 1:
			_dirty[c] = 0
			node.multimesh.buffer = _buffers[c]
			uploads += 1
			node.visible = true
		elif node.visible and now > _until[c]:
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


## The row the next burst of ring `ring` takes.
func next_row(ring: int = BURSTS) -> int:
	return _ring_next[ring]


## The rows written to each ring since the pool was made (x SINGLES, y QUADS, z BURSTS): a mark to
## list the motes written after it (`motes_since`; for tests).
func mark() -> Vector3i:
	return Vector3i(_ring_written[SINGLES], _ring_written[QUADS], _ring_written[BURSTS])


## Every mote written since `since` (a `mark`; those the ring has written over since left out),
## ring by ring, each as the shader works it out: its `ring`, `row` and `q`, `kind`, `source`,
## `core`, `ground` (its ground point at birth), `height`, `vel` (along the floor), `vz`, `life`,
## `born` and `seed` (for tests; it allocates).
func motes_since(since: Vector3i = Vector3i.ZERO) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for ring in RINGS:
		var rows: int = mini(_ring_written[ring] - since[ring], _ring_rows[ring])
		for n in rows:
			var row: int = posmod(_ring_next[ring] - rows + n, _ring_rows[ring])
			var buffer: PackedFloat32Array = _buffers[_ring_first[ring] + row / _ring_chunk[ring]]
			var i: int = (row % _ring_chunk[ring]) * DRAW_STRIDE
			for q in roundi(buffer[i + ROW_COUNT] * 255.0):
				var m: Array = _mote(buffer, i, q)
				var v: Vector4 = m[0]
				found.append({"ring": ring, "row": row, "q": q, "kind": _kind_of(buffer, i),
					"source": roundi(buffer[i + ROW_SOURCE] * SOURCE_CODE),
					"core": Color(buffer[i + ROW_CORE], buffer[i + ROW_CORE + 1], buffer[i + ROW_CORE + 2]),
					"ground": Vector2(buffer[i + ROW_X], buffer[i + ROW_Y]), "height": buffer[i + ROW_HEIGHT] * HEIGHT_MAX,
					"vel": Vector2(v.x, v.y), "vz": v.z, "life": v.w, "born": buffer[i + ROW_BORN], "seed": float(m[1])})
	return found


## The rows of ring `ring` (for tests).
func ring_rows(ring: int) -> int:
	return _ring_rows[ring]


## Mote `q` of row `row` of ring `ring` where it is at the clock time `now`: its ground point
## (x, y) and its height (z); drawn at the ground point raised by its height (for tests and P2).
func mote_at(ring: int, row: int, q: int, now: float) -> Vector3:
	var buffer: PackedFloat32Array = _buffers[_ring_first[ring] + row / _ring_chunk[ring]]
	var i: int = (row % _ring_chunk[ring]) * DRAW_STRIDE
	var m: Array = _mote(buffer, i, q)
	var v: Vector4 = m[0]
	return flight(Vector2(buffer[i + ROW_X], buffer[i + ROW_Y]), Vector2(v.x, v.y), buffer[i + ROW_HEIGHT] * HEIGHT_MAX, v.z, now - buffer[i + ROW_BORN], _kind_of(buffer, i), m[1])


## Where and when mote `q` of row `row` of ring `ring` comes to rest on the floor: its point (x, y)
## and the clock time (z); INF for z when it never does in its life.
func mote_land(ring: int, row: int, q: int) -> Vector3:
	var buffer: PackedFloat32Array = _buffers[_ring_first[ring] + row / _ring_chunk[ring]]
	var i: int = (row % _ring_chunk[ring]) * DRAW_STRIDE
	return _land(buffer, i, _kind_of(buffer, i), q)


## `mote_land` of mote `q` of the row at `i` of `buffer`, of kind `k` (the settled marks' too, so
## the two are one sum): `flight` at the time it comes to rest, its sums written out here.
func _land(buffer: PackedFloat32Array, i: int, k: int, q: int) -> Vector3:
	var kind: MoteKind = _kinds[k]
	var g: float = kind.gravity
	if g <= 0.0:
		return Vector3(INF, INF, INF)
	# `mote_randoms` and `_mote` written out (no allocation: the settles call it in a fight).
	var h1: int = mote_hash(int(buffer[i + ROW_SEED]) * 16 + q)
	var h2: int = mote_hash(h1)
	var u: int = int(buffer[i + ROW_UP])
	var vz: float = lerpf(float(u >> 12) * SPEED_STEP + UP_LOW, float(u & 4095) * SPEED_STEP + UP_LOW, float(h2 >> 20) / 4096.0)
	var h0: float = buffer[i + ROW_HEIGHT] * HEIGHT_MAX
	var land: float = (vz + sqrt(vz * vz + 2.0 * g * maxf(h0, 0.0))) / g
	var rebound: float = (g * land - vz) * kind.bounce
	var rest: float = land + 2.0 * rebound / g
	var l: int = int(buffer[i + ROW_LIFE])
	if rest >= lerpf(float(l >> 12) * LIFE_STEP, float(l & 4095) * LIFE_STEP, float((h2 >> 8) & 4095) / 4096.0):
		return Vector3(INF, INF, INF)
	var aim: int = int(buffer[i + ROW_AIM])
	var way: float = float(aim >> 12) * AIM_STEP + (float(h1 >> 20) / 4096.0 * 2.0 - 1.0) * float(aim & 4095) * HALF_STEP
	var sp: int = int(buffer[i + ROW_SPEED])
	var speed: float = lerpf(float(sp >> 12) * SPEED_STEP, float(sp & 4095) * SPEED_STEP, float((h1 >> 8) & 4095) / 4096.0)
	var drag: float = kind.drag
	var along: float = ((1.0 - exp(-drag * rest)) / drag if drag > 0.0 else rest) * speed
	var phase: float = float(((h1 & 255) << 8) | (h2 & 255)) / 65536.0 * 6.2832
	return Vector3(buffer[i + ROW_X] + cos(way) * along + kind.wobble * (sin(rest * kind.wobble_rate + phase) - sin(phase)),
		buffer[i + ROW_Y] + sin(way) * along, buffer[i + ROW_BORN] + rest)


## Row `row` of ring `ring` as the shader reads it (a copy, for tests).
func row_data(ring: int, row: int) -> PackedFloat32Array:
	var i: int = (row % _ring_chunk[ring]) * DRAW_STRIDE
	return _buffers[_ring_first[ring] + row / _ring_chunk[ring]].slice(i, i + DRAW_STRIDE)


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
	return clampi(roundi(buffer[i + ROW_KIND] * KIND_CODE), 0, MAX_KINDS - 1)


## The shape atlas's pixel (MoteKind.PIXEL_*) of kind `k`'s frame `frame` at `x`, `y` of its
## square (the mote's own pixel in the middle) (for tests).
func shape_value(k: int, frame: int, x: int, y: int) -> int:
	var size: int = MoteKind.SHAPE_SIZE
	return roundi(_shape_image.get_pixel(frame * size + x, k * size + y).r * 2.0)


## How far from a mote's own pixel kind `kind`'s shape draws, in pixels (0 for one pixel), in any
## frame and turned any of its 8 ways (the shader turns a pixel back by its way and rounds, as
## here): the size of its quad when it does not glow, so it costs no fragments past its shape.
static func reach_of(kind: MoteKind) -> int:
	var size: int = MoteKind.SHAPE_SIZE
	var half: int = size / 2
	var turns: int = 8 if kind.shape_turns else 1
	var reach: int = 0
	for frame in kind.shape_frames().size():
		var pixels: PackedByteArray = kind.shape_pixels(frame)
		for way in turns:
			var angle: float = float(way) * 0.7854
			var turn := Vector2(cos(angle), sin(angle))
			# Every pixel a turned shape can reach (one more than the square's corner).
			for dy in range(-half - 1, half + 2):
				for dx in range(-half - 1, half + 2):
					var q := Vector2(turn.x * dx + turn.y * dy, -turn.y * dx + turn.x * dy).round()
					if absf(q.x) > half or absf(q.y) > half:
						continue
					if pixels[(int(q.y) + half) * size + int(q.x) + half] != MoteKind.PIXEL_NONE:
						reach = maxi(reach, maxi(absi(dx), absi(dy)))
	return reach


## Keep the kinds with no problems (MAX_KINDS at most), index them by look layer and by card and
## hand their numbers to the shader (`kind_table`, a row a kind).
func _take_kinds(kinds: Array[MoteKind]) -> void:
	_layer_kinds.resize(LOOK_LAYERS + 1)
	for layer in LOOK_LAYERS + 1:
		_layer_kinds[layer] = PackedInt32Array()
	var size: int = MoteKind.SHAPE_SIZE
	var rows: int = mini(maxi(kinds.size(), 1), MAX_KINDS)
	_kind_image = Image.create_empty(KIND_COLUMNS, rows, false, Image.FORMAT_RGBAF)
	_shape_image = Image.create_empty(size * MoteKind.SHAPE_FRAMES, size * rows, false, Image.FORMAT_RGBA8)
	for kind in kinds:
		if kind == null or not kind.problems().is_empty():
			continue
		if _kinds.size() >= MAX_KINDS:
			push_warning("Motes: more than %d mote kinds; '%s' is left out" % [MAX_KINDS, kind.id])
			continue
		var k: int = _kinds.size()
		_kinds.append(kind)
		var own := PackedFloat32Array()
		own.resize(PACK_SIZE)
		_pack_into(own, kind.speed, kind.spread, kind.up, kind.life)
		_kind_packs.append(own)
		var trail := PackedFloat32Array()
		trail.resize(PACK_SIZE)
		_pack_into(trail, kind.speed * TRAIL_SPEED, kind.spread, kind.up * TRAIL_SPEED, kind.life)
		_trail_packs.append(trail)
		if not _kind_at.has(kind.id):
			_kind_at[kind.id] = k
		_k_height.append(kind.height)
		_k_gravity.append(kind.gravity)
		_k_bounce.append(kind.bounce)
		_k_drag.append(kind.drag)
		_k_wobble.append(kind.wobble)
		_k_wobble_rate.append(kind.wobble_rate)
		var frames: int = kind.shape_frames().size()
		_kind_image.set_pixel(0, k, Color(kind.gravity, kind.drag, kind.bounce, kind.glow))
		_kind_image.set_pixel(1, k, Color(kind.wobble, kind.wobble_rate, float(kind.shade_from), float(reach_of(kind))))
		_kind_image.set_pixel(2, k, Color(float(frames), float(MoteKind.SHAPE_PLAYS.find(kind.shape_play)), kind.shape_rate, 1.0 if kind.shape_turns else 0.0))
		for frame in frames:
			var pixels: PackedByteArray = kind.shape_pixels(frame)
			for y in size:
				for x in size:
					var value: float = float(pixels[y * size + x]) * 0.5
					_shape_image.set_pixel(frame * size + x, k * size + y, Color(value, value, value, 1.0))
		if kind.surface:
			_surface_kinds.append(k)
		if kind.dash_path:
			_dash_kinds.append(k)
		for layer in kind.look_layers:
			_layer_kinds[layer].append(k)
		for card in kind.cards:
			if not _card_kinds.has(card):
				_card_kinds[card] = PackedInt32Array()
			_card_kinds[card].append(k)
	_material.set_shader_parameter(&"kind_table", ImageTexture.create_from_image(_kind_image))
	_material.set_shader_parameter(&"shape_atlas", ImageTexture.create_from_image(_shape_image))


## Kind `k`'s numbers as the shader reads them (`kind_table`): its motion, its sway and its shape
## (for tests).
func kind_numbers(k: int) -> Array[Vector4]:
	var numbers: Array[Vector4] = []
	for column in KIND_COLUMNS:
		var c: Color = _kind_image.get_pixel(column, k)
		numbers.append(Vector4(c.r, c.g, c.b, c.a))
	return numbers


## Chunk `c` (of ring `ring`)'s rows, making its batch the first time.
func _chunk(c: int, ring: int) -> PackedFloat32Array:
	if _nodes[c] == null:
		var chunk_rows: int = _ring_chunk[ring]
		var rows: int = mini(chunk_rows, _ring_rows[ring] - (c - _ring_first[ring]) * chunk_rows)
		var multimesh: MultiMesh = BatchesScript.multimesh()
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = _meshes[ring]
		multimesh.instance_count = rows
		var buffer := PackedFloat32Array()
		# Every row starts with no motes: folded away.
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


## `quads` quads: the shader places their corners (a vertex's UV is its corner, x plus twice its
## quad's number).
static func _quads(quads: int) -> ArrayMesh:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	for q in quads:
		var base: int = vertices.size()
		for corner: Vector2 in [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]:
			vertices.append(corner)
			uvs.append(corner + Vector2(2.0 * q, 0.0))
			colours.append(Color.WHITE)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A body breaking into motes of kind `k` (S3, a death; `Spectacle.break_body`): one mote shown at
## each of `points` (world positions of its art's pixels), as high above the floor at `feet` (its
## art's lowest pixel) as that pixel is, flung out from `centre` at `speed` (slowest,
## fastest) within `spread` degrees and `up` up, in the colours of `source`. A death is a moment,
## like a cue: it may take the frame's last rows (MOMENT_ROWS).
func crumble(k: int, points: PackedVector2Array, feet: float, centre: Vector2, speed: Vector2, spread: float, up: Vector2, source: int, core: Color) -> void:
	if k < 0 or k >= _kinds.size() or source < 0:
		return
	_pack_into(_pack, speed, spread, up, _kinds[k].life)
	for p in points:
		if _rows_left <= 0:
			cut += 1
			break
		var out: Vector2 = p - centre
		_write(k, p, out if out != Vector2.ZERO else Vector2.UP, 1, _pack, source, core, feet - p.y)

