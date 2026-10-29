extends Node2D
## The trails of swings (melee I4; docs/milestones/M2-staffs.md, "Phase I: melee", "The look"),
## drawn by Feel: a brief line at the arc's reach that follows the staff's tip and sheds pixel
## sparks outward, cooling through the ramp, with the swing's card particles
## (`core/projectiles/shot_swing.gdshader`; the owner's pick A3 from the melee mockup). Feel
## calls `step` every frame with its clock; it reads `Spells`' live swings from their plain
## queries (`swing_slots`, `swing_on`, `swing_born`, `swing_age`, `swing_wind`, `swing_sweep`, ...)
## and keeps each trail on screen TRAIL_SECONDS past its sweep, after the swing itself is over.
##
## One pooled `MeshInstance2D` each (TRAILS_START made at once, more when more swing at once: no
## limit), the swing mesh Feel makes (`Feel.swing_mesh()`, from SWING_QUADS; its box is the whole
## world, so it is never culled). A trail
## follows its swing's hand while the swing lives, then stays where it ended. Nothing is
## allocated while playing, past a new trail node when every one is busy.

const SHADER: Shader = preload("res://core/projectiles/shot_swing.gdshader")
## Trails made at once.
const TRAILS_START: int = 16
## Seconds a trail stays after its sweep ends (its slowest spark's life, and a little).
const TRAIL_SECONDS: float = 0.6
## The quad kinds of a trail's mesh (Q_* in `shot_swing.gdshader`): the light round the line,
## its card particles, its sparks, the line. 12 particles (MAX_PARTICLES in the shot shaders),
## 28 sparks (SPARKS there).
const SWING_Q_LIGHT: int = 0
const SWING_Q_PARTICLE: int = 1
const SWING_Q_SPARK: int = 2
const SWING_Q_LINE: int = 3
const SWING_QUADS: Array[Vector3i] = [
	Vector3i(SWING_Q_LIGHT, 1, 0),
	Vector3i(SWING_Q_PARTICLE, 12, 0),
	Vector3i(SWING_Q_SPARK, 28, 1),
	Vector3i(SWING_Q_LINE, 1, 0),
]
## Swings draw where beams do: above the room, under the shots and the flashes.
const SWING_Z: int = 18

## The trail nodes, and for each: the swing it shows (`Spells.swing_born`; -1 for none) and the
## clock time it goes (its sweep's end plus TRAIL_SECONDS; it is off once the clock is past it).
var _nodes: Array[MeshInstance2D] = []
var _born: PackedInt64Array = PackedInt64Array()
var _until: PackedFloat32Array = PackedFloat32Array()


## The mesh every trail is drawn as.
var _mesh: ArrayMesh = null


func _init(mesh: ArrayMesh) -> void:
	_mesh = mesh
	top_level = true
	for i in TRAILS_START:
		_add_trail()


## Draws the live swings of `spells` at Feel's clock `now`: a new one takes a free trail, a live
## one moves its trail to its hand, and a trail past its time is hidden. `ramp_of` gives the
## shader's player for an actor (0-3 a hat ramp, -1 the enemy ramp); `glow` is how strongly it
## glows.
func step(spells: Node, now: float, ramp_of: Callable, glow: float) -> void:
	var count: int = 0
	if spells != null and spells.has_method("swing_slots"):
		count = int(spells.call("swing_slots"))
	for at in count:
		if not bool(spells.call("swing_on", at)):
			continue
		var born: int = int(spells.call("swing_born", at))
		var slot: int = _born.find(born)
		var fresh: bool = slot < 0
		if fresh:
			slot = _free_trail(now)
			_born[slot] = born
		_show(slot, spells, at, now, fresh, ramp_of, glow)
	for slot in _nodes.size():
		var node: MeshInstance2D = _nodes[slot]
		if not node.visible:
			continue
		if now > _until[slot]:
			node.visible = false
			_born[slot] = -1
			continue
		(node.material as ShaderMaterial).set_shader_parameter(&"sim_time", now)


## Trails on screen (for tests).
func live() -> int:
	var count: int = 0
	for node in _nodes:
		if node.visible:
			count += 1
	return count


## The shader parameter `name` of the trail showing swing `born` (`Spells.swing_born`), or null
## when none shows it (for tests).
func parameter_of(born: int, name: StringName) -> Variant:
	var slot: int = _born.find(born)
	if slot < 0 or not _nodes[slot].visible:
		return null
	return (_nodes[slot].material as ShaderMaterial).get_shader_parameter(name)


## Puts swing `at` of `spells` into trail `slot`: where its hand is and when its sweep starts on
## Feel's clock (kept in step with the swing every frame, so a local stop that holds it holds its
## trail); the rest once, when it is `fresh`.
func _show(slot: int, spells: Node, at: int, now: float, fresh: bool, ramp_of: Callable, glow: float) -> void:
	var node: MeshInstance2D = _nodes[slot]
	var material: ShaderMaterial = node.material as ShaderMaterial
	var sweep: float = float(spells.call("swing_sweep", at))
	var start: float = now - (float(spells.call("swing_age", at)) - float(spells.call("swing_wind", at)))
	material.set_shader_parameter(&"swing_origin", spells.call("swing_origin", at) as Vector2)
	material.set_shader_parameter(&"swing_start", start)
	material.set_shader_parameter(&"sim_time", now)
	_until[slot] = start + sweep + TRAIL_SECONDS
	if not fresh:
		return
	var half: float = deg_to_rad(float(spells.call("swing_arc", at))) * 0.5
	var tint: Color = spells.call("swing_tint", at) as Color
	material.set_shader_parameter(&"core_override", Color(tint.r, tint.g, tint.b, 1.0))
	material.set_shader_parameter(&"swing_player", int(ramp_of.call(int(spells.call("swing_actor", at)))))
	material.set_shader_parameter(&"swing_look", int(spells.call("swing_look", at)))
	material.set_shader_parameter(&"swing_dir", (spells.call("swing_dir", at) as Vector2).normalized())
	material.set_shader_parameter(&"swing_side", 1.0 if int(spells.call("swing_side", at)) >= 0 else -1.0)
	material.set_shader_parameter(&"swing_half", half)
	material.set_shader_parameter(&"swing_lean", half + deg_to_rad(SpellLimits.SWING_LEAN))
	material.set_shader_parameter(&"swing_reach", float(spells.call("swing_reach", at)))
	material.set_shader_parameter(&"swing_sweep", sweep)
	material.set_shader_parameter(&"swing_glow", glow)
	material.set_shader_parameter(&"swing_seed", float(int(spells.call("swing_born", at)) % 61) * 1.618)
	node.visible = true


## A trail that is off or past its time, else a new one: a swing never takes another's trail.
func _free_trail(now: float) -> int:
	for slot in _nodes.size():
		if not _nodes[slot].visible or now > _until[slot]:
			return slot
	_add_trail()
	return _nodes.size() - 1


func _add_trail() -> void:
	var node := MeshInstance2D.new()
	node.mesh = _mesh
	var material := ShaderMaterial.new()
	material.shader = SHADER
	node.material = material
	node.top_level = true
	node.visible = false
	node.z_index = SWING_Z
	add_child(node)
	_nodes.append(node)
	_born.append(-1)
	_until.append(0.0)
