class_name FeelFlashes
extends Object
## Feel's flashes (gameplay/feel/feel.gd, "Flashes"): the five batches (flares, arcs, statuses, the
## floor's, explosions), the flash kinds read from content/flashes into the flash shader's table,
## a slot shown (`show_flash`) or played by a cue's flash part (`_play_flash`), and each frame's
## ageing and writing into the batches (`_step_flashes`). Methods working on Feel (`feel`), whose
## members hold all of it.

const FeelScript := preload("res://gameplay/feel/feel.gd")
const BatchesScript := preload("res://core/projectiles/batches.gd")
const FLASH_SHADER: Shader = preload("res://core/projectiles/shot_flash.gdshader")
const ARC_SHADER: Shader = preload("res://core/projectiles/shot_arc.gdshader")
const STATUS_SHADER: Shader = preload("res://core/projectiles/shot_status.gdshader")
const BLAST_SHADER: Shader = preload("res://core/projectiles/shot_blast.gdshader")
const ProjectileManagerScript := preload("res://core/projectiles/projectile_manager.gd")
const MotesScript := preload("res://gameplay/feel/mote.gd")
const CueSizeScript := preload("res://gameplay/feel/cue_size.gd")
const CueContextScript := preload("res://gameplay/feel/cue_context.gd")
const CuePlanScript := preload("res://gameplay/feel/cue_plan.gd")
const FlashTableScript := preload("res://gameplay/feel/flash_table.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const NativeScript := preload("res://core/native/native.gd")

## Not Feel's own: Feel, the other jobs this one calls and Feel's containers it works on, each
## Feel's own (shared, never a copy), linked by `link`. `_flash_offset` is read through `feel`: tests
## and a screenshot put their own in its place (test_feel_poof.gd, shot_staff_swap.gd).
const LINKED: Array[StringName] = [&"feel", &"_cue_plans", &"_status_effect", &"_flash_buffer", &"_arc_buffer", &"_status_buffer", &"_floor_buffer", &"_blast_buffer", &"_flash_kind", &"_flash_at", &"_flash_dir", &"_flash_core", &"_flash_ramp", &"_flash_zoom", &"_flash_look", &"_flash_age", &"_flash_seconds", &"_flash_length", &"_flash_follow", &"_flash_light", &"_flash_tip", &"_flash_floor", &"_flash_wind", &"_flash_lasts_wind", &"_flash_kinds", &"_flash_codes", &"_flash_rows", &"_code_light", &"_table_floor", &"_flash_look_color", &"_flash_special", &"_flash_aged", &"_flash_special_slots", &"_flash_row_counts"]

static var _flash_mesh: ArrayMesh = null
static var _blast_mesh: ArrayMesh = null
var feel: FeelScript = null
var _cue_plans: Dictionary
var _status_effect: PackedInt32Array
var _flash_buffer: PackedFloat32Array
var _arc_buffer: PackedFloat32Array
var _status_buffer: PackedFloat32Array
var _floor_buffer: PackedFloat32Array
var _blast_buffer: PackedFloat32Array
var _flash_kind: PackedInt32Array
var _flash_at: PackedVector2Array
var _flash_dir: PackedVector2Array
var _flash_core: PackedColorArray
var _flash_ramp: PackedInt32Array
var _flash_zoom: PackedInt32Array
var _flash_look: PackedInt32Array
var _flash_age: PackedFloat32Array
var _flash_seconds: PackedFloat32Array
var _flash_length: PackedFloat32Array
var _flash_follow: Array[Node2D]
var _flash_light: PackedFloat32Array
var _flash_tip: PackedInt32Array
var _flash_floor: PackedByteArray
var _flash_wind: PackedInt32Array
var _flash_lasts_wind: PackedByteArray
var _flash_kinds: Array[FlashKind]
var _flash_codes: Dictionary
var _flash_rows: Dictionary
var _code_light: Dictionary
var _table_floor: PackedByteArray

var _flash_look_color: PackedColorArray
var _flash_special: PackedByteArray
var _flash_aged: PackedByteArray
var _flash_special_slots: PackedInt32Array
var _flash_row_counts: PackedInt32Array

## `_flash_row_counts`' places: the rows of the flares, arcs, statuses, the floor's and explosions.
const ROWS_FLARES: int = 0
const ROWS_ARCS: int = 1
const ROWS_STATUSES: int = 2
const ROWS_FLOORS: int = 3
const ROWS_BLASTS: int = 4


## Takes Feel and its containers and jobs, by the names in LINKED (`Feel._link_jobs`).
func link(owner: FeelScript) -> void:
	feel = owner
	for name: StringName in LINKED:
		if name != &"feel":
			set(name, owner.get(name))


## Find the special slots and write the rows with the native kernel (`Feel._flash_kernel`, a
## `MoteKernel`: native/src/feel_loops.cpp) when
## `on` and the module is loaded. The kernel is handed the numbers it needs and checks the members it
## reads (this job's aliases of Feel's).
func use_native(on: bool) -> void:
	feel._flash_kernel = null
	var kernel: Object = NativeScript.mote_kernel() if on else null
	if kernel == null:
		return
	var numbers: Dictionary = {
		"FLASH_STRIDE": FeelScript.FLASH_STRIDE, "FLASH_GRID": FeelScript.FLASH_GRID, "BLAST_SPAN": FeelScript.BLAST_SPAN,
		"ARC_ACROSS": FeelScript.ARC_ACROSS, "ARC_MARGIN": FeelScript.ARC_MARGIN, "FLASH_FROM": FeelScript.FLASH_FROM,
		"FLASH_SPAN": FeelScript.FLASH_SPAN, "KIND_ARC": FeelScript.KIND_ARC, "KIND_STATUS": FeelScript.KIND_STATUS,
		"KIND_SHELL": FeelScript.KIND_SHELL, "KIND_FIREBALL": FeelScript.KIND_FIREBALL, "FLASH_TABLE": FeelScript.FLASH_TABLE,
		"FLASH_TABLE_CODE": FeelScript.FLASH_TABLE_CODE,
	}
	var wrong: PackedStringArray = kernel.call(&"check_flash_fields", self)
	if not kernel.call(&"configure_flashes", numbers):
		wrong.append("its numbers")
	if not wrong.is_empty():
		push_error("FeelFlashes: the native MoteKernel does not match this script (%s); running the GDScript" % ", ".join(wrong))
		return
	feel._flash_kernel = kernel


## Discharge arcs showing right now (for tests).
func live_arcs() -> int:
	return _count_flashes(FeelScript.KIND_ARC)


## A cue's flash part (`CueBase`: a part with no `part`, or `"part": "flash"`) read into its typed
## fields once (`CuePlan.flash_of`; null for a flash Feel has not: the plan leaves it out).
func _prepare_flash(part: Dictionary) -> Variant:
	return CuePlanScript.flash_of(part, _flash_rows)


## A cue's flash (`CuePlan.Flash`, from its part) played with `cue`: its flash at the cue's point
## along its way, sized by its `zoom` or the cue's size times its `reach` (either times the cue's
## power), for its seconds (or the cue's size with `lasts_size`), in its exact `color`, plain, bare,
## the cue's own colour, or the cue's ramp and tint with its cards (without them for `no_cards`).
func _play_flash(flash: CuePlanScript.Flash, cue: CueContextScript) -> void:
	if flash.particles and not feel.particles_enabled:
		return
	if feel._hit_flash and _hit_flashes_full():
		feel._cue_flash = -1
		return
	if flash.gated:
		# Only for the cards it names: any card's layer, or one look layer (lightning's arc).
		var layers: int = cue.look & ((1 << MotesScript.LOOK_LAYERS) - 1)
		if flash.if_cards and layers == 0:
			return
		if flash.if_layer > 0 and (layers >> (flash.if_layer - 1)) & 1 == 0:
			return
		# Only at some sizes (a zap's short spark into the air against a zap at a body).
		if cue.size <= flash.size_over or cue.size > flash.size_upto:
			return
	# A cue played bigger than it is made lasts longer (`CueBase.size_ref`, `cue_size.gd`).
	var seconds: float = flash.seconds * CueSizeScript.seconds(cue.grow)
	if flash.lasts_size:
		if cue.size <= 0.0:
			return
		seconds = cue.size
	var zoom: int
	var length: float = 0.0
	var steps: float = flash.reach_steps
	if steps >= 0.0:
		# Sized from the cue's: its size times the part's reach, in steps of the flash's zoom.
		zoom = roundi(cue.size * steps * cue.power)
	else:
		zoom = roundi(flash.zoom * cue.power)
		if flash.along:
			# Drawn along its length (an arc): the cue's size times its reach, from the cue's point.
			length = cue.size * (flash.reach if flash.reach >= 0.0 else 1.0)
			if length <= 0.0:
				return
	var way: Vector2 = cue.aim
	var turn: int = flash.way
	if turn != CuePlanScript.WAY_AIM:
		if turn == CuePlanScript.WAY_BACK:
			way = -way
		elif turn == CuePlanScript.WAY_RIGHT:
			way = Vector2.RIGHT
		else:
			way = Vector2.UP
	# Where on the cue's line (`along`, S6 item 9), and the body it follows (a staff's swap).
	var at: Vector2 = cue.at
	if flash.place >= 0.0:
		at += cue.aim * cue.size * flash.place
	var follow: Node2D = cue.follow if cue.follow != null and is_instance_valid(cue.follow) else null
	var paint: int = flash.paint
	if paint == CuePlanScript.PAINT_COLOR:
		feel._cue_flash = _show_flash(flash.kind, at, way, flash.color, 0, FeelScript.EXACT, zoom, seconds, length, follow)
	elif paint == CuePlanScript.PAINT_PLAIN:
		feel._cue_flash = _show_flash(flash.kind, at, way, Color.WHITE, 0, 0, zoom, seconds, length, follow)
	elif paint == CuePlanScript.PAINT_BARE:
		feel._cue_flash = _show_flash(flash.kind, at, way, Color.WHITE, cue.ramp, 0, zoom, seconds, length, follow)
	elif paint == CuePlanScript.PAINT_BODY:
		feel._cue_flash = _show_flash(flash.kind, at, way, cue.body if cue.body.a > 0.0 else Color.WHITE, 0, 0, zoom, seconds, length, follow)
	elif cue.color.a > 0.0:
		feel._cue_flash = _show_flash(flash.kind, at, way, cue.color, 0, FeelScript.EXACT, zoom, seconds, length, follow)
	else:
		feel._cue_flash = _show_flash(flash.kind, at, way, cue.tint, cue.ramp, 0 if paint == CuePlanScript.PAINT_NO_CARDS else cue.look, zoom, seconds, length, follow)
	# A wind-up's flash as long as the wind-up follows it, held or stretched.
	if flash.lasts_size and feel._cue_flash >= 0 and _flash_wind[feel._cue_flash] >= 0:
		_flash_lasts_wind[feel._cue_flash] = 1
	# A ground strike's flash on the floor, under the bodies (its part's `floor`).
	if flash.floor and feel._cue_flash >= 0:
		_flash_floor[feel._cue_flash] = 1
	# A followed cue's flash sits where it was played from its body (S6, item 9).
	if follow != null and feel._cue_flash >= 0:
		feel._flash_offset[feel._cue_flash] = at - follow.global_position
	# One on a staff tip sits where it was played from the tip, along the aim, as the tip turns.
	if feel._cue_flash >= 0 and _flash_tip[feel._cue_flash] != ActorsScript.NONE:
		feel._flash_offset[feel._cue_flash] = (at - cue.at).rotated(-cue.aim.angle()) if cue.aim.is_finite() else Vector2.ZERO


## Make the flash batches (see "Flashes" above): a MultiMesh of `effect_slots` quads in world
## space for each of the flares, the arcs and the statuses, each drawn by its own shot shader,
## and the arrays behind them.
func _make_flashes() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	feel._status_node = _make_flash_batch(STATUS_SHADER, quad)
	feel._flash_node = _make_flash_batch(FLASH_SHADER, flash_mesh())
	feel._arc_node = _make_flash_batch(ARC_SHADER, quad)
	feel._floor_node = _make_flash_batch(FLASH_SHADER, flash_mesh())
	feel._floor_node.z_index = FeelScript.FLOOR_Z
	feel._blast_node = _make_flash_batch(BLAST_SHADER, blast_mesh())
	_size_flashes(feel.effect_slots)
	_read_flash_kinds()
	use_native(feel.flash_native)


## Read the flash kinds (content/flashes) from the registry: each id's code and its row for a
## cue's flash part, and the table the flash shader draws the table kinds from (`FlashTable`). A
## kind with problems (`FlashKind.problems`; the content test names them) is left out. The cues
## are read again, so their flash parts take the new codes.
func _read_flash_kinds() -> void:
	_flash_kinds.clear()
	_flash_codes.clear()
	_flash_rows.clear()
	_code_light.clear()
	if feel.registry != null:
		for found: Resource in feel.registry.get_all(FeelScript.FLASH_FOLDER):
			var kind: FlashKind = found as FlashKind
			if kind != null and kind.problems().is_empty():
				_flash_kinds.append(kind)
	_table_floor.resize(_flash_kinds.size())
	for row in _flash_kinds.size():
		var kind: FlashKind = _flash_kinds[row]
		var code: int = FeelScript.FLASH_TABLE + row if kind.in_table() else int(FeelScript.DRAW_KINDS[kind.draw])
		_table_floor[row] = 1 if kind.on_floor else 0
		_flash_codes[kind.id] = code
		_flash_rows[kind.id] = [code, kind.step, kind.seconds, kind.along()]
		_code_light[code] = kind.room_light
	var table := ImageTexture.create_from_image(FlashTableScript.image_of(_flash_kinds))
	for node: MultiMeshInstance2D in [feel._flash_node, feel._floor_node]:
		(node.material as ShaderMaterial).set_shader_parameter(&"flash_table", table)
	_cue_plans.clear()


## The flash kind `id` (content/flashes), or null.
func flash_kind(id: StringName) -> FlashKind:
	for kind: FlashKind in _flash_kinds:
		if kind.id == id:
			return kind
	return null


## The mesh a flash is drawn as (`shot_flash.gdshader`, PARTICLES ARE GEOMETRY there): small
## quads, each told in its UV which quad kind (FLASH_Q_*) and slot it is, in FLASH_QUADS'
## order. The shader places every quad in the flash's square, or folds it away; a vertex says
## which quad and corner it is in its UV: x the slot + 0.25 or 0.75, y the kind + 0.25 or 0.75.
## Made once.
static func flash_mesh() -> ArrayMesh:
	if _flash_mesh == null:
		_flash_mesh = _quads_mesh(FeelScript.FLASH_QUADS)
	return _flash_mesh


## The mesh an explosion's part is drawn as (`shot_blast.gdshader`): its light and BLAST_PIECES
## small quads, told their kind and slot in their UV as `flash_mesh`'s. Made once.
static func blast_mesh() -> ArrayMesh:
	if _blast_mesh == null:
		_blast_mesh = _quads_mesh(FeelScript.BLAST_QUADS)
	return _blast_mesh


## A mesh of small quads, (kind, slots, 1 when the slots run backwards) for each entry of `quads`
## in order: a vertex says which quad and corner it is in its UV, x the slot + 0.25 or 0.75, y
## the kind + 0.25 or 0.75 (its position is a unit square round the origin).
static func _quads_mesh(quads: Array[Vector3i]) -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var corners: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for entry: Vector3i in quads:
		for n in entry.y:
			var slot: int = entry.y - 1 - n if entry.z == 1 else n
			var base: int = verts.size()
			for corner: Vector2 in corners:
				verts.append(corner - Vector2(0.5, 0.5))
				uvs.append(Vector2(float(slot) + 0.25 + 0.5 * corner.x, float(entry.x) + 0.25 + 0.5 * corner.y))
				colors.append(Color.WHITE)
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_flash_batch(shader: Shader, mesh: Mesh) -> MultiMeshInstance2D:
	var node := MultiMeshInstance2D.new()
	# Flashes show anywhere in the world; there is no room to fit a box to.
	var multimesh: MultiMesh = BatchesScript.multimesh()
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.visible_instance_count = 0
	node.multimesh = multimesh
	var material := ShaderMaterial.new()
	material.shader = shader
	node.material = material
	node.top_level = true
	node.z_index = FeelScript.FLASH_Z
	feel.add_child(node)
	return node


## Make room for `slots` flashes: the MultiMesh, its buffer and the arrays behind it. The
## flashes showing end (a setting changed in a menu: nobody misses a tenth of a second of sparks).
func _size_flashes(slots: int) -> void:
	feel.effect_slots = slots
	for node: MultiMeshInstance2D in [feel._flash_node, feel._arc_node, feel._status_node, feel._floor_node, feel._blast_node]:
		node.multimesh.visible_instance_count = 0
		node.multimesh.instance_count = slots
	_flash_buffer.resize(slots * FeelScript.FLASH_STRIDE)
	_arc_buffer.resize(slots * FeelScript.FLASH_STRIDE)
	_floor_buffer.resize(slots * FeelScript.FLASH_STRIDE)
	_blast_buffer.resize(slots * FeelScript.FLASH_STRIDE)
	_status_buffer.resize(slots * FeelScript.FLASH_STRIDE)
	_flash_kind.resize(slots)
	_flash_at.resize(slots)
	_flash_dir.resize(slots)
	_flash_core.resize(slots)
	_flash_ramp.resize(slots)
	_flash_zoom.resize(slots)
	_flash_look.resize(slots)
	_flash_age.resize(slots)
	_flash_seconds.resize(slots)
	_flash_seconds.fill(0.0)
	_flash_length.resize(slots)
	_flash_follow.resize(slots)
	_flash_follow.fill(null)
	_flash_light.resize(slots)
	_flash_light.fill(0.0)
	feel._flash_offset.resize(slots)
	_flash_tip.resize(slots)
	_flash_floor.resize(slots)
	_flash_floor.fill(0)
	_flash_tip.fill(ActorsScript.NONE)
	_flash_wind.resize(slots)
	_flash_wind.fill(-1)
	_flash_lasts_wind.resize(slots)
	_flash_lasts_wind.fill(0)
	_flash_look_color.resize(slots)
	_flash_special.resize(slots)
	_flash_special.fill(0)
	_flash_aged.resize(slots)
	_flash_aged.fill(0)
	_flash_special_slots.resize(slots)
	feel._next_flash = 0
	# The statuses shown lost their flashes; the next step shows them again.
	_status_effect.fill(-1)


## The setting: how many flashes can show at once, snapped by `EffectSlots.snap`. Returns the
## number taken.
func set_effect_slots(slots: int) -> int:
	var snapped: int = EffectSlots.snap(slots)
	if feel._flash_node == null:
		feel.effect_slots = snapped
	elif snapped != feel.effect_slots:
		_size_flashes(snapped)
	return feel.effect_slots


## Show a flash of the kind `id` (content/flashes) at `at`, aimed along `dir`, in the ramp of
## `core` (white: the colours of `ramp`, a caster's `Actors.ramp_of`: 0-3 a hat ramp, anything else
## from NONE up the enemy ramp) with the particles of the packed `look`, at `zoom`, for
## `seconds`. An arc runs `length` pixels from `at` along `dir` (its zoom is then the length). A
## flash given a `follow` node moves with it, and ends when it is gone. It takes the next slot, the
## oldest flash when they are all busy, and returns it (-1 for none, or a kind there is not; a hit's
## own flash past its share of a frame's, `_hit_flashes_full`, is none).
func show_flash(id: StringName, at: Vector2, dir: Vector2, core: Color, ramp: int, look: int, zoom: int, seconds: float, length: float = 0.0, follow: Node2D = null) -> int:
	var code: int = int(_flash_codes.get(id, -1))
	return _show_flash(code, at, dir, core, ramp, look, zoom, seconds, length, follow) if code >= 0 else -1


## True when this frame's hit flashes have taken their share of the slots (`_flashes_shown`).
func _hit_flashes_full() -> bool:
	return feel._flashes_shown >= feel.effect_slots - feel.effect_slots / FeelScript.HIT_FLASH_RESERVE


## `show_flash` by Feel's code for the kind (`_flash_codes`; KIND_STATUS for a status's glow).
func _show_flash(kind: int, at: Vector2, dir: Vector2, core: Color, ramp: int, look: int, zoom: int, seconds: float, length: float = 0.0, follow: Node2D = null) -> int:
	if feel._flash_node == null or not at.is_finite() or ramp < ActorsScript.NONE or ramp > ActorsScript.RAMP_ENEMY:
		return -1
	if feel._hit_flash and _hit_flashes_full():
		return -1
	feel._flashes_shown += 1
	var slot: int = feel._next_flash
	feel._next_flash = (feel._next_flash + 1) % feel.effect_slots
	_flash_kind[slot] = kind
	_flash_at[slot] = at.round()
	_flash_dir[slot] = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	_flash_core[slot] = core
	_flash_ramp[slot] = ramp
	# As big as it is asked to be (the owner, 2026-11-09: no cue is capped in size): an explosion's
	# part takes its radius / 2 as its zoom. The shaders read the size from the row's transform, not
	# the look's red byte (which holds 63 at most).
	_flash_zoom[slot] = maxi(zoom, 1)
	_flash_look[slot] = look
	_flash_age[slot] = 0.0
	_flash_seconds[slot] = maxf(seconds, 0.01)
	_flash_length[slot] = 0.0
	_flash_follow[slot] = follow
	feel._flash_offset[slot] = Vector2(0.0, -FeelScript.STATUS_RISE) if follow != null else Vector2.ZERO
	_flash_tip[slot] = feel._cue_tip
	_flash_wind[slot] = feel._cue_wind
	_flash_lasts_wind[slot] = 0
	_flash_floor[slot] = 0
	_flash_light[slot] = 0.0 if feel._cue_unlit else float(_code_light.get(kind, 0.0))
	if (kind == FeelScript.KIND_SHELL or kind == FeelScript.KIND_FIREBALL) and feel._spectacle != null:
		# An explosion's part: the world's stirs push out from it (atmosphere E; its radius is its
		# zoom x 2).
		feel._spectacle.blast(_flash_at[slot], float(_flash_zoom[slot]) * 2.0, feel._clock)
	if kind == FeelScript.KIND_ARC:
		var steps: int = maxi(roundi(length / 4.0), 1)
		_flash_zoom[slot] = steps
		_flash_length[slot] = steps * 4.0
	# Worked out once here: a slot's ramp, zoom and look are written nowhere else (a new writer of
	# them works this out again), and so is whether it is special.
	_flash_look_color[slot] = ProjectileManagerScript.look_color(ramp, _flash_zoom[slot], look)
	_flash_special[slot] = 1 if follow != null or feel._cue_tip != ActorsScript.NONE or feel._cue_wind >= 0 else 0
	_flash_aged[slot] = 0
	return slot


## Flash `slot` on its actor's staff tip as it is now, turned with its live aim (a wind-up's ring
## follows the staff as the aim follows the stick, as its lane does: `lanes.gd`); where it was while
## the actor has no aim.
func _place_on_tip(slot: int) -> void:
	# Feel's numbers and services this reads, once (a read through `feel` is a lookup by name).
	var spells: Node = feel.spells
	if spells == null:
		return
	var actor: int = _flash_tip[slot]
	var tip: Vector2 = spells.call("aim_origin_of", actor)
	var way: Vector2 = spells.call("aim_of", actor)
	if not tip.is_finite() or not way.is_finite() or way.is_zero_approx():
		return
	_flash_at[slot] = (tip + feel._flash_offset[slot].rotated(way.angle())).round()
	_flash_dir[slot] = way.normalized()


## Age the flashes by `real_delta` and write the live ones into their batches, oldest first: the
## special slots (`_flash_special`: following a body, on a staff tip or lasting a wind-up) first, by
## what the game says (`_step_special`), then every slot's row (`_write_rows`, in the native kernel
## where it is loaded). A slot's row depends on its own slot alone, so the order is the old one loop's.
func _step_flashes(real_delta: float) -> void:
	if feel._flash_node == null:
		return
	# Feel's numbers this reads, once (a read through `feel` is a lookup by name).
	var effect_slots: int = feel.effect_slots
	var next_flash: int = feel._next_flash
	var clock: float = feel._clock
	(feel._flash_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", clock)
	(feel._arc_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", clock)
	(feel._status_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", clock)
	(feel._floor_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", clock)
	(feel._blast_node.material as ShaderMaterial).set_shader_parameter(&"sim_time", clock)
	var kernel: Object = feel._flash_kernel
	# No batch shows last frame's rows should a step write none (a kernel that refused its arrays).
	_flash_row_counts.fill(0)
	var special: int = int(kernel.call(&"find_special", self, effect_slots)) if kernel != null else _find_special(effect_slots)
	for k in special:
		_step_special(_flash_special_slots[k], real_delta)
	if kernel != null:
		kernel.call(&"write_rows", self, real_delta, next_flash, effect_slots)
	else:
		_write_rows(real_delta, next_flash, effect_slots)
	var out: int = _flash_row_counts[ROWS_FLARES]
	var arcs: int = _flash_row_counts[ROWS_ARCS]
	var statuses: int = _flash_row_counts[ROWS_STATUSES]
	var floors: int = _flash_row_counts[ROWS_FLOORS]
	var blasts: int = _flash_row_counts[ROWS_BLASTS]
	if out > 0:
		feel._flash_node.multimesh.buffer = _flash_buffer
	feel._flash_node.multimesh.visible_instance_count = out
	if arcs > 0:
		feel._arc_node.multimesh.buffer = _arc_buffer
	feel._arc_node.multimesh.visible_instance_count = arcs
	if statuses > 0:
		feel._status_node.multimesh.buffer = _status_buffer
	feel._status_node.multimesh.visible_instance_count = statuses
	if floors > 0:
		feel._floor_node.multimesh.buffer = _floor_buffer
	feel._floor_node.multimesh.visible_instance_count = floors
	if blasts > 0:
		feel._blast_node.multimesh.buffer = _blast_buffer
	feel._blast_node.multimesh.visible_instance_count = blasts
	# Spell light draws the same rows (P3b; through the spectacle, `SpellLight.light_flashes`).
	if feel._spectacle != null:
		feel._spectacle.light_flashes(_flash_buffer, out, _blast_buffer, blasts, _arc_buffer, arcs, effect_slots)


## The live special slots (`_flash_special`) listed in `_flash_special_slots`, in slot order;
## returns how many (`MoteKernel.find_special` does the same).
func _find_special(effect_slots: int) -> int:
	var found: int = 0
	for slot in effect_slots:
		if _flash_special[slot] != 0 and _flash_seconds[slot] > 0.0:
			_flash_special_slots[found] = slot
			found += 1
	return found


## A special slot aged by `real_delta`, ended when the body it follows is gone or its wind-up is
## over, its time stretched to a wind-up it lasts, and moved to its staff tip or the body it
## follows; marked aged (`_flash_aged`) so `_write_rows` does not age it again.
func _step_special(slot: int, real_delta: float) -> void:
	var spells: Node = feel.spells
	_flash_age[slot] += real_delta
	var through: float = _flash_age[slot] / _flash_seconds[slot]
	# Read untyped: a freed body put in a typed variable reads as null, and its flash would
	# stay on where it was instead of ending (S6, item 9's regression test).
	var followed: Variant = _flash_follow[slot]
	var follow: Node2D = null
	if typeof(followed) == TYPE_OBJECT:
		if is_instance_valid(followed):
			follow = followed as Node2D
		else:
			through = 1.0
	if _flash_wind[slot] >= 0 and spells != null and through < 1.0:
		if not bool(spells.call("is_winding", _flash_tip[slot], _flash_wind[slot])):
			# Its wind-up is over: the cast left, or was cancelled.
			through = 1.0
		elif _flash_lasts_wind[slot] == 1:
			# As long as its wind-up: what has run plus what the wind-up has left.
			var left: float = float(spells.call("cooldown_left", _flash_tip[slot], _flash_wind[slot]))
			_flash_seconds[slot] = maxf(_flash_age[slot] + left, 0.01)
			through = _flash_age[slot] / _flash_seconds[slot]
	if through >= 1.0:
		_flash_seconds[slot] = 0.0
		_flash_follow[slot] = null
		return
	_flash_aged[slot] = 1
	if _flash_tip[slot] != ActorsScript.NONE:
		_place_on_tip(slot)
	elif follow != null:
		_flash_at[slot] = (follow.global_position + feel._flash_offset[slot]).round()


## Every live slot from `next_flash` on (oldest first) aged by `real_delta` (but a special one
## `_step_special` aged: its mark cleared), ended at its time, and its row written into its batch;
## the rows of each batch counted in `_flash_row_counts`. `MoteKernel.write_rows` mirrors it to the
## bit. A slot's `through` is its age over its seconds, as stored.
func _write_rows(real_delta: float, next_flash: int, effect_slots: int) -> void:
	var out: int = 0
	var arcs: int = 0
	var floors: int = 0
	var blasts: int = 0
	var statuses: int = 0
	for n in effect_slots:
		var slot: int = (next_flash + n) % effect_slots
		if _flash_seconds[slot] <= 0.0:
			continue
		if _flash_aged[slot] != 0:
			_flash_aged[slot] = 0
		else:
			_flash_age[slot] += real_delta
			if _flash_age[slot] / _flash_seconds[slot] >= 1.0:
				_flash_seconds[slot] = 0.0
				continue
		var through: float = _flash_age[slot] / _flash_seconds[slot]
		var kind: int = _flash_kind[slot]
		var buffer: PackedFloat32Array = _flash_buffer
		var i: int = out * FeelScript.FLASH_STRIDE
		var blast: bool = kind == FeelScript.KIND_SHELL or kind == FeelScript.KIND_FIREBALL
		# A table kind's row, and the code beside its age (its code in the shader that draws it).
		var row: int = kind - FeelScript.FLASH_TABLE if kind >= FeelScript.FLASH_TABLE else 0
		var code: int = FeelScript.FLASH_TABLE_CODE if kind >= FeelScript.FLASH_TABLE else (kind - FeelScript.KIND_SHELL if blast else kind)
		if kind == FeelScript.KIND_ARC:
			buffer = _arc_buffer
			i = arcs * FeelScript.FLASH_STRIDE
			arcs += 1
		elif kind == FeelScript.KIND_STATUS:
			buffer = _status_buffer
			i = statuses * FeelScript.FLASH_STRIDE
			statuses += 1
		elif blast:
			buffer = _blast_buffer
			i = blasts * FeelScript.FLASH_STRIDE
			blasts += 1
		elif _table_floor[row] != 0 or _flash_floor[slot] != 0:
			buffer = _floor_buffer
			i = floors * FeelScript.FLASH_STRIDE
			floors += 1
		else:
			out += 1
		var d: float = FeelScript.FLASH_GRID * _flash_zoom[slot]
		var along: float = d
		var dir: Vector2 = _flash_dir[slot]
		var at: Vector2 = _flash_at[slot]
		if blast:
			# An explosion's part: BLAST_SPAN radii each way, its radius the zoom x 2.
			d = _flash_zoom[slot] * 4.0 * FeelScript.BLAST_SPAN
			along = d
		if _flash_length[slot] > 0.0:
			# An arc: from where it starts along its way, a margin past each end.
			d = FeelScript.ARC_ACROSS
			along = _flash_length[slot] + 2.0 * FeelScript.ARC_MARGIN
			at += dir * _flash_length[slot] * 0.5
		# The transform, its two unused floats its table row and its room light (full precision).
		buffer[i] = dir.x * along
		buffer[i + 1] = dir.y * d
		buffer[i + 2] = float(row)
		buffer[i + 3] = at.x
		buffer[i + 4] = dir.y * along
		buffer[i + 5] = -dir.x * d
		buffer[i + 6] = _flash_light[slot]
		buffer[i + 7] = at.y
		var data: Color = _flash_look_color[slot]
		buffer[i + 8] = data.r
		buffer[i + 9] = data.g
		buffer[i + 10] = data.b
		buffer[i + 11] = data.a
		var core: Color = _flash_core[slot]
		buffer[i + 12] = core.r
		buffer[i + 13] = core.g
		buffer[i + 14] = core.b
		# Its age beside its code (the flash shaders read it: `coded_age`).
		buffer[i + 15] = 1.0 - (float(code) + FeelScript.FLASH_FROM + FeelScript.FLASH_SPAN * through) / 16.0
	_flash_row_counts[ROWS_FLARES] = out
	_flash_row_counts[ROWS_ARCS] = arcs
	_flash_row_counts[ROWS_STATUSES] = statuses
	_flash_row_counts[ROWS_FLOORS] = floors
	_flash_row_counts[ROWS_BLASTS] = blasts


## How many flashes are showing (for tests and the sheets).
func live_flashes() -> int:
	# Feel's numbers this reads, once (a read through `feel` is a lookup by name).
	var effect_slots: int = feel.effect_slots
	var live: int = 0
	for slot in effect_slots:
		if _flash_seconds[slot] > 0.0:
			live += 1
	return live


## How many live flashes are of the kind `id`, and (with a `ramp` 0-4) in that ramp.
func flashes_of(id: StringName, ramp: int = -1) -> int:
	return _count_flashes(int(_flash_codes.get(id, -1)), ramp)


func _count_flashes(kind: int, ramp: int = -1) -> int:
	# Feel's numbers this reads, once (a read through `feel` is a lookup by name).
	var effect_slots: int = feel.effect_slots
	var found: int = 0
	for slot in effect_slots:
		if _flash_seconds[slot] > 0.0 and _flash_kind[slot] == kind and (ramp < 0 or _flash_ramp[slot] == ramp):
			found += 1
	return found


## The newest live flash of Feel's code `kind`'s slot, or -1.
func _newest_flash(kind: int) -> int:
	# Feel's numbers this reads, once (a read through `feel` is a lookup by name).
	var effect_slots: int = feel.effect_slots
	for n in effect_slots:
		var slot: int = (feel._next_flash - 1 - n + effect_slots) % effect_slots
		if kind >= 0 and _flash_seconds[slot] > 0.0 and _flash_kind[slot] == kind:
			return slot
	return -1


## The core colour and look of the newest live flash of the kind `id` (for tests): [core, look].
func flash_dress(id: StringName) -> Array:
	var slot: int = _newest_flash(int(_flash_codes.get(id, -1)))
	return [_flash_core[slot], _flash_look[slot]] if slot >= 0 else []


## The newest live flash of the kind `id` (for tests): its place, way, core colour, ramp, zoom,
## look, seconds and room light, or an empty dictionary when none shows.
func flash_info(id: StringName) -> Dictionary:
	return _flash_info_of(_newest_flash(int(_flash_codes.get(id, -1))))


## The newest status glow shown (for tests), as `flash_info`.
func status_info() -> Dictionary:
	return _flash_info_of(_newest_flash(FeelScript.KIND_STATUS))


func _flash_info_of(slot: int) -> Dictionary:
	if slot < 0:
		return {}
	return {"at": _flash_at[slot], "dir": _flash_dir[slot], "core": _flash_core[slot], "ramp": _flash_ramp[slot],
			"zoom": _flash_zoom[slot], "look": _flash_look[slot], "seconds": _flash_seconds[slot], "light": _flash_light[slot]}
