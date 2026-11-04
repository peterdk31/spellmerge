extends Node2D
## Motes (docs/milestones/spell-spectacle.md, P1): up to tens of thousands of single-pixel
## particles with no game logic, drawn by Feel. A mote is thrown from a point with a velocity
## along the floor, a fake height and a velocity up; `gameplay/feel/mote.gdshader` works out its
## whole flight from its row and the time since its birth (it flies with drag, rises or falls,
## lands, bounces once, lies still and cools through its ramp's shades). The CPU writes a row once
## and never touches it again: there is no per-frame simulation.
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
## The pool is a ring of `cap` rows (the "Particles" setting, `MoteCap` in core/settings): a new
## mote takes the next row and overwrites the oldest. The ring is cut into CHUNK-row chunks, one
## `MultiMeshInstance2D` each (made by `Batches.multimesh()`, so it is never culled; made the first
## time a mote lands in it). `step` uploads only the chunks written since the last frame, so a
## burst of 300 motes uploads one or two chunks (64 KB each), never the whole ring; a chunk whose
## motes are all gone (by the longest life each of its bursts could give) is hidden and costs no
## vertices. Nothing is allocated while playing, past a chunk's first use. A mote costs the CPU
## about 2.3 us in a fight (its share of the shot's shed and its row; P1c, docs/DECISIONS.md), so
## at most FRAME_ROWS are written between two steps: a burst past that is cut short, and a shed
## once they are used up costs next to nothing (a storm's flood of hits stays within its budget).
##
## Every row is written by `burst` (`shed`, `throw`, `throw_part` and the trails' `give_off` all
## end there), at the names ROW_*. `flight` is the shader's `mote_flight` line for line (a test
## holds the two to it); `mote_land` gives where and when a mote comes to rest. **Settled motes**
## (P2b): a kind that names a floor mark (`MoteKind.settles`) leaves it where each of its motes
## comes to rest, at that time (`settle_into` names the mark layer; `Marks.settle` keeps it until
## then; SETTLE_ROWS a frame in a flood).

const SHADER: Shader = preload("res://gameplay/feel/mote.gdshader")
const BatchesScript := preload("res://core/projectiles/batches.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const RampTableScript := preload("res://gameplay/feel/ramp_table.gd")
const MarksScript := preload("res://gameplay/feel/marks.gd")
const NativeScript := preload("res://core/native/native.gd")

## Rows in a chunk: one batch, uploaded whole when any of its rows is written.
const CHUNK: int = 1024
## Floats in a row: the transform (8), the colour (4) and the custom data (4).
const DRAW_STRIDE: int = 16
## Where a row's numbers are (mote.gdshader's header says where it reads each): the velocity
## along the floor (x, y), the birth on Feel's clock, the height's velocity, the ground point at
## birth (x, y), the source / SOURCE_CODE, the kind / KIND_CODE, the life / LIFE_MAX, the height
## at birth / HEIGHT_MAX, the core colour (r, g, b) and a seed. 2 and 6 are unused.
const ROW_VX: int = 0
const ROW_BORN: int = 1
const ROW_X: int = 3
const ROW_VY: int = 4
const ROW_VZ: int = 5
const ROW_Y: int = 7
const ROW_SOURCE: int = 8
const ROW_KIND: int = 9
const ROW_LIFE: int = 10
const ROW_HEIGHT: int = 11
const ROW_CORE: int = 12
const ROW_SEED: int = 15
## The longest life a mote has (s; MoteKind's, which checks the kinds against it).
const LIFE_MAX: float = MoteKind.LIFE_MAX
## The most motes written between two steps, and of them the rows a shot's hit, end or wall hit
## (`shed`, `throw`: hundreds a frame in a storm, a few motes each) leave for the moments
## (`throw_part`, `burst`: a cue's or a reaction's, tens or a hundred in one burst, so a blast in a
## storm still throws its motes). Set from the sandbox storm (P1c, docs/DECISIONS.md): the sheds'
## rows cost about 2.5 us each, a moment's about 0.5.
const FRAME_ROWS: int = 256
const MOMENT_ROWS: int = 128
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

var _cap: int = 0
## The kinds, in the order the shader holds them, and for each look layer (0-21) the kinds that
## are its motes; the surface kinds.
var _kinds: Array[MoteKind] = []
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
## The next row a mote takes.
var _next: int = 0
## Per chunk: its batch (null until its first mote), its rows, written since the last upload, and
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
## The rows a frame (FRAME_ROWS; the "Tailless motes" dev slider raises it, so a bigger tailless
## pool's births are written: `TaillessMotes.frame_rows_of`, set by the spectacle). The moments
## keep their MOMENT_ROWS of it.
var frame_rows: int = FRAME_ROWS
var _keep: int = 0
var _settles_left: int = SETTLE_MOST
## Rows written since the pool was made: a mote's serial (the mark layer forgets a settle whose
## mote the ring overwrote before it came to rest).
var _serial: int = 0
## The ramp table (its own, or the one Feel shares with the floor marks).
var _table: RampTableScript = null
## The mark layer settled motes go to (null for none), and per kind the mark it leaves (-1 none).
var _marks: MarksScript = null
var _settle_marks: PackedInt32Array = PackedInt32Array()
## The shapes' frames: SHAPE_SIZE squares, a kind's along its row (`shape_value`).
var _shape_image: Image = null
var _kind_image: Image = null
var _material: ShaderMaterial = null
var _mesh: ArrayMesh = null
var _z: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## The native kernel (`MoteKernel`, native/README.md): the trails' births written in C++, the same
## to the bit, or null to write them here. `native` switches it.
var native: bool = true:
	set = set_native
var _kernel: Object = null
## Each kind's burst and flight numbers, for the kernel (made with the kinds).
var _k_speed: PackedVector2Array = PackedVector2Array()
var _k_up: PackedVector2Array = PackedVector2Array()
var _k_life: PackedVector2Array = PackedVector2Array()
var _k_spread: PackedFloat64Array = PackedFloat64Array()
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
	var chunks: int = ceili(float(_cap) / CHUNK)
	_nodes.resize(chunks)
	_buffers.resize(chunks)
	_dirty.resize(chunks)
	_until.resize(chunks)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_mesh = _quad()
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
		"CHUNK": CHUNK, "DRAW_STRIDE": DRAW_STRIDE, "BIRTH_STRIDE": BIRTH_STRIDE, "SETTLE_STRIDE": SETTLE_STRIDE,
		"ROW_VX": ROW_VX, "ROW_BORN": ROW_BORN, "ROW_X": ROW_X, "ROW_VY": ROW_VY, "ROW_VZ": ROW_VZ, "ROW_Y": ROW_Y,
		"ROW_SOURCE": ROW_SOURCE, "ROW_KIND": ROW_KIND, "ROW_LIFE": ROW_LIFE, "ROW_HEIGHT": ROW_HEIGHT,
		"ROW_CORE": ROW_CORE, "ROW_SEED": ROW_SEED,
		"SPARK_X": ProjectilesScript.SPARK_X, "SPARK_Y": ProjectilesScript.SPARK_Y,
		"SPARK_BACK_X": ProjectilesScript.SPARK_BACK_X, "SPARK_BACK_Y": ProjectilesScript.SPARK_BACK_Y,
		"SPARK_KIND": ProjectilesScript.SPARK_KIND, "SPARK_RAMP": ProjectilesScript.SPARK_RAMP,
		"SPARK_LOOK": ProjectilesScript.SPARK_LOOK, "SPARK_CORE": ProjectilesScript.SPARK_CORE,
		"SPARK_TAG": ProjectilesScript.SPARK_TAG, "SPARK_TAG_BITS": ProjectilesScript.SPARK_TAG_BITS,
		"SPARK_STREAK": ProjectilesScript.SPARK_STREAK, "PAIR_LAYERS": PAIR_LAYERS,
		"ENEMY_SOURCE": ENEMY_SOURCE, "EXACT_SOURCE": EXACT_SOURCE, "LOOK_ENEMY_RAMP": LOOK_ENEMY_RAMP,
		"LOOK_EXACT": LOOK_EXACT, "LIFE_MAX": LIFE_MAX, "HEIGHT_MAX": HEIGHT_MAX, "SOURCE_CODE": SOURCE_CODE,
		"KIND_CODE": KIND_CODE, "TRAIL_SPEED": TRAIL_SPEED,
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
	for i in _kinds.size():
		if _kinds[i].id == id:
			return i
	return -1


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
	if _rows_left <= MOMENT_ROWS:
		cut += 1
		return
	shed_kinds(kinds_of_look(look), at, dir, core, ramp, look, scale)


## Whether a shed now writes nothing (only the frame's MOMENT_ROWS are left), counted as cut: ask it
## before working out a shed's kinds (`card_kinds.gd`), which costs more than a shed that is cut.
func shed_closed() -> bool:
	if _rows_left <= MOMENT_ROWS:
		cut += 1
		return true
	return false


## `shed` with the kinds `found` (a spell's, `card_kinds.gd`; never empty) in place of its look's.
func shed_kinds(found: PackedInt32Array, at: Vector2, dir: Vector2, core: Color, ramp: int, look: int, scale: float = 1.0) -> void:
	if _rows_left <= MOMENT_ROWS:
		cut += 1
		return
	if found.is_empty():
		return
	var source: int = spell_source(ramp, look)
	var share: float = scale / float(found.size())
	_keep = MOMENT_ROWS
	for k in found:
		var kind: MoteKind = _kinds[k]
		burst(k, at, dir, maxi(roundi(float(kind.count) * share), 1), kind.speed, kind.spread, kind.up, kind.life, source, core, kind.height)
	_keep = 0


## The shots' trail particles (spell spectacle P1d): the first `count` births of `births`
## (core/projectiles' `spark_births`, BIRTH_STRIDE floats each), one mote each (times `density`,
## as any burst): a kind of its look kind's layer (`kinds_of_layer`), given off back along the shot
## within its kind's spread at TRAIL_SPEED of its burst speed and speed up, in the shot's own ramp.
## A shot of a spell gives off its spell's kinds for that layer (`use_cards`); a dash's streak
## (SPARK_STREAK) is one of the dash path kinds (`MoteKind.dash_path`).
## Each is a one-mote `burst`, so a trail's mote is written, counted and settled as every other.
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
		var kind: MoteKind = _kinds[k]
		births += 1
		burst(k, Vector2(given[b + ProjectilesScript.SPARK_X], given[b + ProjectilesScript.SPARK_Y]),
			Vector2(given[b + ProjectilesScript.SPARK_BACK_X], given[b + ProjectilesScript.SPARK_BACK_Y]),
			1, kind.speed * TRAIL_SPEED, kind.spread, kind.up * TRAIL_SPEED, kind.life,
			spell_source(int(given[b + ProjectilesScript.SPARK_RAMP]), int(given[b + ProjectilesScript.SPARK_LOOK])),
			Color(given[b + ProjectilesScript.SPARK_CORE], given[b + ProjectilesScript.SPARK_CORE + 1], given[b + ProjectilesScript.SPARK_CORE + 2]),
			kind.height)


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


## Make the chunks the frame's rows left may still reach from the next row (the native kernel
## writes rows but makes no nodes).
func _ready_chunks() -> void:
	var left: int = mini(_rows_left, _cap)
	var row: int = _next
	while left > 0:
		var c: int = row / CHUNK
		if _nodes[c] == null:
			_chunk(c)
		var span: int = mini(mini(CHUNK, _cap - c * CHUNK) - (row - c * CHUNK), left)
		left -= span
		row = (row + span) % _cap


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
	if _rows_left <= MOMENT_ROWS:
		cut += 1
		return
	if k < 0 or k >= _kinds.size() or source < 0:
		return
	var kind: MoteKind = _kinds[k]
	_keep = MOMENT_ROWS
	burst(k, at, dir, maxi(roundi(float(kind.count) * scale), 1), kind.speed, kind.spread, kind.up, kind.life, source, core, kind.height)
	_keep = 0


## Throw kind `k`'s burst as a cue's part says (`CueBase`, a `motes` part): `count` motes (its
## own count when below 0), flying out to `reach` pixels at the most (its own speed when 0; the
## farthest a mote of its drag glides), within `spread` degrees (its own when below 0), `up` times
## its own speed up, all as fast as the fastest when `ring` (a ring going out). `often` for a source
## of many a frame (a hit's spray): it stops once only the frame's MOMENT_ROWS are left, as `shed`.
## With a `line`, each mote is thrown from a point of the line from `at` to `at + line` (a staff).
func throw_part(k: int, at: Vector2, dir: Vector2, source: int, core: Color, count: int, reach: float, spread: float, up: float, ring: bool, often: bool = false, line: Vector2 = Vector2.ZERO) -> void:
	if k < 0 or k >= _kinds.size() or source < 0:
		return
	# One of many a frame (a hit's spray, S3): like `shed`, it leaves the moments' rows alone.
	if often and _rows_left <= MOMENT_ROWS:
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
	_keep = MOMENT_ROWS if often else 0
	burst(k, at, dir, kind.count if count < 0 else count, speed, kind.spread if spread < 0.0 else spread, kind.up * up, kind.life, source, core, kind.height, line)
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
	if density != 1.0:
		count = floori(float(count) * density + _rng.randf())
	if count <= 0 or not at.is_finite() or k < 0 or k >= _kinds.size() or source < 0:
		return
	var room: int = _rows_left - _keep
	if count > room:
		cut += 1
		count = room
		if count <= 0:
			return
	# A settle costs about as much as a row, so it takes one of the frame's: the first `settling`
	# motes of a settling kind leave their marks while rows and SETTLE_ROWS last.
	var mark: int = _settle_marks[k] if _marks != null and k < _settle_marks.size() else -1
	var settling: int = 0
	if mark >= 0:
		settling = mini(mini(count, _settles_left), room - count)
		_settles_left -= settling
		settles += settling
		settles_skipped += count - settling
	_rows_left -= count + settling
	written += count
	var aim: float = dir.angle() if dir != Vector2.ZERO else 0.0
	var half: float = deg_to_rad(clampf(spread, 0.0, 360.0)) * 0.5
	# In steps of 1/255 of HEIGHT_MAX (a renderer may keep the row's colour as bytes).
	height = roundf(clampf(height, 0.0, HEIGHT_MAX) / HEIGHT_MAX * 255.0) / 255.0 * HEIGHT_MAX
	var ground: Vector2 = at + Vector2(0.0, height)
	var coded_source: float = float(source) / SOURCE_CODE
	var coded_kind: float = float(k) / KIND_CODE
	var coded_height: float = height / HEIGHT_MAX
	var shortest: float = clampf(life.x, 0.02, LIFE_MAX)
	var longest: float = clampf(life.y, 0.02, LIFE_MAX)
	var chunk: int = -1
	var buffer: PackedFloat32Array
	for n in count:
		var row: int = _next
		_next = (_next + 1) % _cap
		var c: int = row / CHUNK
		if c != chunk:
			chunk = c
			if _nodes[c] == null:
				_chunk(c)
			buffer = _buffers[c]
			_dirty[c] = 1
			# Shown until its last mote is gone (a life is written a 255th of LIFE_MAX up at most).
			_until[c] = maxf(_until[c], _now + longest + LIFE_MAX / 255.0)
		var v: Vector2 = Vector2.from_angle(aim + _rng.randf_range(-half, half)) * _rng.randf_range(speed.x, speed.y)
		var i: int = (row - c * CHUNK) * DRAW_STRIDE
		buffer[i + ROW_VX] = v.x
		buffer[i + ROW_BORN] = _now
		var from: Vector2 = ground if line == Vector2.ZERO else ground + line * _rng.randf()
		buffer[i + ROW_X] = from.x
		buffer[i + ROW_VY] = v.y
		buffer[i + ROW_VZ] = _rng.randf_range(up.x, up.y)
		buffer[i + ROW_Y] = from.y
		buffer[i + ROW_SOURCE] = coded_source
		buffer[i + ROW_KIND] = coded_kind
		# The life in 1/255 steps of LIFE_MAX.
		buffer[i + ROW_LIFE] = roundf(_rng.randf_range(shortest, longest) / LIFE_MAX * 255.0) / 255.0
		buffer[i + ROW_HEIGHT] = coded_height
		buffer[i + ROW_CORE] = core.r
		buffer[i + ROW_CORE + 1] = core.g
		buffer[i + ROW_CORE + 2] = core.b
		buffer[i + ROW_SEED] = _rng.randf()
		if n < settling:
			# Where and when it rests (`mote_land`'s sum), for the mark it leaves there; its serial
			# lets the layer forget it if the ring writes over it first (`step`).
			var land: Vector3 = _land(buffer, i, k)
			if is_finite(land.z):
				_marks.settle(mark, Vector2(land.x, land.y).floor(), land.z, source, core, _serial + n)
	_serial += count


## Once a frame, at Feel's clock `now`: upload the chunks written since the last step, hide those
## with nothing alive, and move the shader's clock on.
func step(now: float) -> void:
	_now = now
	_rows_left = frame_rows
	_settles_left = mini(_settles_left + SETTLE_ROWS, SETTLE_MOST)
	if _marks != null:
		_marks.forget_settles_before(_serial - _cap)
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


## The row the next mote takes.
func next_row() -> int:
	return _next


## Where mote `row` is at the clock time `now`: its ground point (x, y) and its height (z); drawn
## at the ground point raised by its height. Its row is read as written (for tests and P2).
func mote_at(row: int, now: float) -> Vector3:
	var buffer: PackedFloat32Array = _buffers[row / CHUNK]
	var i: int = (row % CHUNK) * DRAW_STRIDE
	return flight(Vector2(buffer[i + ROW_X], buffer[i + ROW_Y]), Vector2(buffer[i + ROW_VX], buffer[i + ROW_VY]), buffer[i + ROW_HEIGHT] * HEIGHT_MAX, buffer[i + ROW_VZ], now - buffer[i + ROW_BORN], _kind_of(buffer, i), buffer[i + ROW_SEED])


## Where and when mote `row` comes to rest on the floor: its point (x, y) and the clock time (z);
## INF for z when it never does in its life (a kind that rises, or one gone before it lands).
func mote_land(row: int) -> Vector3:
	var buffer: PackedFloat32Array = _buffers[row / CHUNK]
	var i: int = (row % CHUNK) * DRAW_STRIDE
	return _land(buffer, i, _kind_of(buffer, i))


## `mote_land` of the row at `i` of `buffer`, of kind `k` (the settled marks' too, so the two are
## one sum): `flight` at the time it comes to rest, its sums written out here (the settles call it
## in a fight; a test holds its lines to the shader's).
func _land(buffer: PackedFloat32Array, i: int, k: int) -> Vector3:
	var kind: MoteKind = _kinds[k]
	var g: float = kind.gravity
	if g <= 0.0:
		return Vector3(INF, INF, INF)
	var h0: float = buffer[i + ROW_HEIGHT] * HEIGHT_MAX
	var vz: float = buffer[i + ROW_VZ]
	var land: float = (vz + sqrt(vz * vz + 2.0 * g * maxf(h0, 0.0))) / g
	var rebound: float = (g * land - vz) * kind.bounce
	var rest: float = land + 2.0 * rebound / g
	if rest >= buffer[i + ROW_LIFE] * LIFE_MAX:
		return Vector3(INF, INF, INF)
	var drag: float = kind.drag
	var along: float = (1.0 - exp(-drag * rest)) / drag if drag > 0.0 else rest
	var phase: float = buffer[i + ROW_SEED] * 6.2832
	return Vector3(buffer[i + ROW_X] + buffer[i + ROW_VX] * along + kind.wobble * (sin(rest * kind.wobble_rate + phase) - sin(phase)),
		buffer[i + ROW_Y] + buffer[i + ROW_VY] * along, buffer[i + ROW_BORN] + rest)


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
		_k_speed.append(kind.speed)
		_k_up.append(kind.up)
		_k_life.append(kind.life)
		_k_spread.append(kind.spread)
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


## A body breaking into motes of kind `k` (S3, a death; `Spectacle.break_body`): one mote shown at
## each of `points` (world positions of its art's pixels), as high above the floor at `feet` (its
## art's lowest pixel) as that pixel is, flung out from `centre` at `speed` (slowest,
## fastest) within `spread` degrees and `up` up, in the colours of `source`. A death is a moment,
## like a cue: it may take the frame's last rows (MOMENT_ROWS).
func crumble(k: int, points: PackedVector2Array, feet: float, centre: Vector2, speed: Vector2, spread: float, up: Vector2, source: int, core: Color) -> void:
	if k < 0 or k >= _kinds.size() or source < 0:
		return
	var kind: MoteKind = _kinds[k]
	for p in points:
		if _rows_left <= 0:
			cut += 1
			break
		var out: Vector2 = p - centre
		burst(k, p, out if out != Vector2.ZERO else Vector2.UP, 1, speed, spread, up, kind.life, source, core, clampf(feet - p.y, 0.0, HEIGHT_MAX))

