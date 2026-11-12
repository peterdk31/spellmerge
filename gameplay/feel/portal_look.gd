extends Node2D
## The portals' gates while they are open (docs/milestones/portal.md, "Looks and sound";
## docs/milestones/carrier-looks-fixes.md, phase 2): Feel's portal look (`Carrier.LOOK_PORTAL`), drawn
## every frame from one typed read of the open portals (`CarrierPortal.read_view`, a `PortalView`).
##
## Each gate is a mote rift (the owner's pick, 2026-11-09: "use motes for everything you can"):
##  - its lens is its card's look: one quad a gate in a batch drawn by the portal card's shader
##    (`CarrierCard.look_shader`, `content/spells/carriers/portal/portal.gdshader`: a dark lens, its stars
##    drifting through it), or the plain one (`core/projectiles/shot_portal.gdshader`), the quad
##    sized by how open it is (`shot_portal.gdshaderinc` says what a quad carries);
##  - its lips are two streams of real `ward` motes (placed each frame, `placed_motes.gd`, as a
##    shield's shell is), up one side and down the other, two deep: the first lip in its first
##    infusion, the second in its second (the first's with one);
##  - loose motes spiral into a mouth and are thrown out of an exit, each infusion in turn;
##  - a faint dotted line of motes joins a mouth to each of its exits, so anybody can read where a
##    shot will come out (pillar 4).
## It opens tall, then wide, and closes the other way (`opening`): the lens's quad and the lips are
## placed by the same numbers. With no infusion, everything is in its caster's colours (the core
## colour and the caster's ramp, as any of its spells' motes). Its opening and closing are its
## card's cues too (`portal_open`, `portal_close`). Drawn only: nothing here feeds back into the game.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const BatchesScript := preload("res://core/projectiles/batches.gd")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const PlacedMotesScript := preload("res://gameplay/feel/placed_motes.gd")
const ActorsScript := preload("res://core/actors/actors.gd")

## The lens of a portal whose card names no shader of its own.
const PLAIN_SHADER: Shader = preload("res://core/projectiles/shot_portal.gdshader")

## Seconds it takes to open tall, and to open wide after a beat; seconds before its end it starts to
## close (narrowing, then shrinking).
const OPEN_TALL: float = 0.3
const OPEN_WIDE_FROM: float = 0.2
const OPEN_WIDE: float = 0.3
const CLOSE: float = 0.65
const CLOSE_WIDE: float = 0.3
const CLOSE_TALL: float = 0.35
## A gate of radius RADIUS is a lens HALF_TALL pixels up and down and HALF_WIDE across (it scales).
const RADIUS: float = 12.0
const HALF_TALL: float = 12.0
const HALF_WIDE: float = 4.2
## Pixels round the lens inside its quad (GATE_PAD in shot_portal.gdshaderinc; test_portal_look
## compares them).
const GATE_PAD: float = 2.0
## The mote kind the lips, the loose motes and the line are made of (content/motes/ward.tres).
const KIND: StringName = &"ward"
## Each lip's motes: how many a stream, two streams deep, and how fast they run (lap a second).
const LIP_MOTES: int = 22
const LIP_ROWS: int = 2
const LIP_RUN: float = 0.45
## Loose motes round a gate, and how far out they start (a mouth) or end (an exit).
const LOOSE: int = 10
const LOOSE_REACH: float = 12.0
## Pixels between the line's motes.
const LINE_STEP: float = 6.0
## A placed mote's life (s), the ages it twinkles between (its shade by its age: white-hot or light
## while it twinkles), and a back row's or a loose mote's age (dimmer), and the line's (its base).
const ROW_LIFE: float = 1.0
const TWINKLE_FROM: float = 0.06
const TWINKLE_SPAN: float = 0.4
const DIM_AGE: float = 0.35
const LINE_AGE: float = 0.6
## Portals draw where beams do: above the room, under the shots and the flashes; the motes on them.
const PORTAL_Z: int = 17
## The lens quads room is made for at first (it doubles).
const FIRST_ROOM: int = 8
const SIDES: Array[int] = [-1, 1]

## Gates drawn last frame and motes placed (for tests).
var gates_drawn: int = 0
var motes_placed: int = 0

var _lens: MultiMeshInstance2D = null
var _rows: PackedFloat32Array = PackedFloat32Array()
var _room: int = 0
var _placed: PlacedMotesScript = null


func _init() -> void:
	z_index = PORTAL_Z
	_lens = MultiMeshInstance2D.new()
	_lens.name = "Lenses"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh: MultiMesh = BatchesScript.multimesh()
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	_lens.multimesh = multimesh
	var material := ShaderMaterial.new()
	material.shader = PLAIN_SHADER
	_lens.material = material
	_lens.top_level = true
	_lens.z_index = PORTAL_Z
	_lens.visible = false
	add_child(_lens)
	_fit(FIRST_ROOM)
	_placed = PlacedMotesScript.new(PORTAL_Z, "PortalMotes", FIRST_ROOM * LIP_MOTES * LIP_ROWS * 2)
	add_child(_placed)


## Draws every lens by the shader of the card whose carrier opens portals, if it names one
## (`SpellRuntime.look_shaders(Carrier.LOOK_PORTAL)`), or by PLAIN_SHADER. Every lens is drawn in one
## batch, so by one shader: more than one card with a portal look of its own is warned of (the first
## is used). Once, when Feel knows Spells; no card id is named here.
func use_shaders(shaders: Array[Shader]) -> void:
	if shaders.size() > 1:
		push_warning("Feel: %d cards draw portals by shaders of their own, but every lens is drawn in one batch: only %s is used" % [shaders.size(), shaders[0].resource_path])
	var wanted: Shader = shaders[0] if not shaders.is_empty() else PLAIN_SHADER
	ShaderWarmupScript.want(wanted, ShaderWarmupScript.BATCH)
	var material := _lens.material as ShaderMaterial
	if material.shader != wanted:
		material.shader = wanted


## The shader every lens is drawn by now.
func lens_shader() -> Shader:
	return (_lens.material as ShaderMaterial).shader


## Feel's step: draw the open portals of `view` (filled this frame; null for none) at Feel's `clock`,
## their ramps from the actor `table`, their motes into `pool` (null: particles off, no motes).
func step(view: PortalView, table: ActorsScript, pool: MotesScript, clock: float) -> void:
	gates_drawn = 0
	motes_placed = 0
	(_lens.material as ShaderMaterial).set_shader_parameter(&"sim_time", clock)
	var placing: bool = _placed.begin(pool, clock)
	var kind: int = pool.kind_index(KIND) if placing else -1
	if view != null:
		_fit(view.gates)
		for p in view.portals:
			_portal(view, p, table, kind, clock)
	_placed.finish()
	motes_placed = _placed.rows
	_lens.multimesh.visible_instance_count = gates_drawn
	if gates_drawn > 0:
		_lens.multimesh.buffer = _rows
	_lens.visible = gates_drawn > 0


## How open a gate is `age` seconds after it opened with `left` seconds to go: (tall, wide), each 0
## to 1. It opens tall, then wide (a little past, settling back), and closes narrowing, then shrinking.
static func opening(age: float, left: float) -> Vector2:
	var tall: float = 1.0 - pow(1.0 - clampf(age / OPEN_TALL, 0.0, 1.0), 2.0)
	var k: float = clampf((age - OPEN_WIDE_FROM) / OPEN_WIDE, 0.0, 1.0) - 1.0
	var wide: float = 1.0 + 2.70158 * k * k * k + 1.70158 * k * k
	if left < CLOSE:
		var narrow: float = clampf((CLOSE - left) / CLOSE_WIDE, 0.0, 1.0)
		wide = minf(wide, 1.0 - narrow * narrow)
		tall = minf(tall, 1.0 - clampf((CLOSE - CLOSE_WIDE - left) / CLOSE_TALL, 0.0, 1.0))
	return Vector2(maxf(tall, 0.0), maxf(wide, 0.0))


## Half the lens's width `n` (-1 to 1) of the way up it, for a lens `wide` across.
static func lens_width(n: float, wide: float) -> float:
	return wide * sqrt(maxf(0.0, 1.0 - n * n))


## A number in [0, 1) from three numbers: the same every frame for the same ones.
static func _hash(a: float, b: float, c: float) -> float:
	var s: float = sin(a * 127.1 + b * 311.7 + c * 74.7) * 43758.5453
	return s - floorf(s)


## Portal `p` of `view`: its gates' lenses, lips, loose motes and lines.
func _portal(view: PortalView, p: int, table: ActorsScript, kind: int, clock: float) -> void:
	var count: int = view.gate_count[p]
	if count == 0:
		return
	var first: int = view.first_gate[p]
	var ramp: int = table.ramp_of(view.caster[p]) if table != null else 0
	var look: int = view.look[p]
	var colour: Color = ProjectilesScript.look_color(ramp, 1, look)
	var source: int = MotesScript.spell_source(ramp, look)
	var infusions: PackedColorArray = view.infusions[p]
	var open: Vector2 = opening(view.since[p], view.left[p])
	var key: int = int(view.key[p] % 4096)
	var mouth: Vector2 = Vector2.INF
	for g in range(first, first + count):
		if view.mouth[g] == 1:
			mouth = view.centre[g]
	for n in count:
		var g: int = first + n
		var is_mouth: bool = view.mouth[g] == 1
		var size: float = view.radius[g] / RADIUS
		var tall: float = HALF_TALL * size * open.x
		var wide: float = HALF_WIDE * size * open.y
		if tall < 0.5:
			continue
		var across: Vector2 = view.face[g].normalized() if view.face[g].length_squared() > 0.0001 else Vector2.RIGHT
		var up := Vector2(-across.y, across.x)
		if up.y > 0.0:
			up = -up
		var seed: float = fposmod(float(key * 13 + n * 7) * 0.618, 1.0)
		_write_lens(view.centre[g], across, up, tall, wide, colour, view.core[p], is_mouth, seed)
		if kind < 0:
			continue
		if not is_mouth and mouth.is_finite():
			_line(mouth, view.centre[g], kind, source, _core_of(infusions, 0, view.core[p]), open.y)
		_lips(view.centre[g], across, up, tall, wide, is_mouth, kind, source, infusions, view.core[p], key * 97 + n * 13, clock)
		if open.y > 0.5:
			_loose(view.centre[g], across, up, size, is_mouth, kind, source, infusions, view.core[p], key * 97 + n * 13, clock)


## Gate quad: one row of the lens batch (`shot_portal.gdshaderinc` says what it carries).
func _write_lens(centre: Vector2, across: Vector2, up: Vector2, tall: float, wide: float, colour: Color, core: Color, is_mouth: bool, seed: float) -> void:
	var i: int = gates_drawn * ProjectilesScript.DRAW_STRIDE
	var x_axis: Vector2 = across * (2.0 * (wide + GATE_PAD))
	var y_axis: Vector2 = up * (2.0 * (tall + GATE_PAD))
	_rows[i] = x_axis.x
	_rows[i + 1] = y_axis.x
	_rows[i + 2] = 0.0
	_rows[i + 3] = centre.x
	_rows[i + 4] = x_axis.y
	_rows[i + 5] = y_axis.y
	_rows[i + 6] = 0.0
	_rows[i + 7] = centre.y
	_rows[i + 8] = colour.r
	_rows[i + 9] = colour.g
	_rows[i + 10] = colour.b
	_rows[i + 11] = colour.a
	_rows[i + 12] = core.r
	_rows[i + 13] = core.g
	_rows[i + 14] = core.b
	_rows[i + 15] = (0.5 if is_mouth else 0.0) + seed * 0.49
	gates_drawn += 1


## The core colour of the `slot`th infusion in turn (`infusions` in slot order, rgb its tint), or
## `core` (the spell's) for none: a mote's core picks its ramp, as a shot's does.
static func _core_of(infusions: PackedColorArray, slot: int, core: Color) -> Color:
	if infusions.is_empty():
		return core
	var tint: Color = infusions[posmod(slot, infusions.size())]
	return Color(tint.r, tint.g, tint.b)


## A twinkling mote's age now (its shade: white-hot or light while it twinkles), by its `key`.
static func _twinkle(clock: float, key: float, dim: bool) -> float:
	var tw: float = fposmod(clock * (1.3 + _hash(key, 1.0, 0.0)) + _hash(key, 2.0, 0.0), 1.0)
	return (DIM_AGE if dim else 0.0) + TWINKLE_FROM + TWINKLE_SPAN * tw


## The lips: streams of motes up one side and down the other, two deep; the first lip in the first
## infusion, the second in the second.
func _lips(centre: Vector2, across: Vector2, up: Vector2, tall: float, wide: float, is_mouth: bool, kind: int, source: int, infusions: PackedColorArray, core: Color, key: int, clock: float) -> void:
	var dir: float = 1.0 if is_mouth else -1.0
	for side: int in SIDES:
		var lip: Color = _core_of(infusions, 0 if side < 0 else 1, core)
		for r in LIP_ROWS:
			for k in LIP_MOTES:
				var s: float = fposmod(float(k) / LIP_MOTES + clock * (LIP_RUN + r * 0.2) * side * dir + r * 0.5 / LIP_MOTES, 1.0)
				var n: float = s * 2.0 - 1.0
				var at: Vector2 = centre + across * (side * (lens_width(n, wide) + 0.6 + r * 1.3)) + up * (n * tall)
				var mote_key: float = float(k + r * 50 + (200 if side > 0 else 0) + key)
				_placed.put(at, kind, source, lip, _twinkle(clock, mote_key, r > 0), _hash(mote_key, 3.0, 0.0), ROW_LIFE)


## Loose motes: spiralling into a mouth, thrown out of an exit; each infusion in turn.
func _loose(centre: Vector2, across: Vector2, up: Vector2, size: float, is_mouth: bool, kind: int, source: int, infusions: PackedColorArray, core: Color, key: int, clock: float) -> void:
	var dir: float = 1.0 if is_mouth else -1.0
	for k in LOOSE:
		var v: float = clock * 0.7 + _hash(float(k), float(key), 0.0)
		var p: float = fposmod(v, 1.0)
		if not is_mouth and p > 0.85:
			continue
		var ang: float = _hash(float(k), floorf(v), float(key) + 1.0) * TAU + p * 1.5 * dir
		var d: float = (LOOSE_REACH * (1.0 - p) + 2.0 if is_mouth else 2.0 + LOOSE_REACH * p) * size
		var at: Vector2 = centre + across * (cos(ang) * d * 0.7) + up * (sin(ang) * d)
		_placed.put(at, kind, source, _core_of(infusions, k, core), _twinkle(clock, float(k + key), true), _hash(float(k), float(key), 5.0), ROW_LIFE)


## A dotted line of motes from `a` to `b`, its ends left clear of the gates, as it opens (`wide`).
func _line(a: Vector2, b: Vector2, kind: int, source: int, core: Color, wide: float) -> void:
	var length: float = a.distance_to(b)
	if length < 8.0 or wide < 0.5:
		return
	var way: Vector2 = (b - a) / length
	var dots: int = int(length / LINE_STEP)
	for k in range(2, dots - 1):
		_placed.put(a + way * (k * LINE_STEP), kind, source, core, LINE_AGE, 0.5, ROW_LIFE)


## Room for `wanted` lenses: doubles, never shrinks.
func _fit(wanted: int) -> void:
	if wanted <= _room:
		return
	_room = maxi(wanted, _room * 2)
	_rows.resize(_room * ProjectilesScript.DRAW_STRIDE)
	_lens.multimesh.instance_count = _room
