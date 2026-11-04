extends Node2D
## The trails of swings (melee I4; docs/milestones/M2-staffs.md, "Phase I: melee", "The look"),
## drawn by Feel: a brief line at the arc's reach that follows the staff's tip, cooling through the
## ramp (`core/projectiles/shot_swing.gdshader`; the owner's pick A3 from the melee mockup), and the
## sparks it sheds outward and its card particles as motes (spell spectacle 2, S6 item 10): as the
## tip passes a stretch of the arc, that stretch's share of SPARKS sparks (look kind 0, a quarter of
## them in the infusion's ramp, the rest in the player's, as the line) is given off outward from the
## tip, and its share of its cards' particles (4 and 2 a card kind, at most PARTICLES_MOST, as the
## shader had them) back along the way the tip came, as births (`gameplay/feel/births.gd`) of the
## swing's spell (`swing_tag`), so they take its cards' motes. Feel
## calls `step` every frame with its clock; it reads `Spells`' live swings from their plain
## queries (`swing_slots`, `swing_on`, `swing_born`, `swing_age`, `swing_wind`, `swing_sweep`,
## `swing_turned`, ...) and keeps each trail on screen TRAIL_SECONDS past its sweep, after the
## swing itself is over.
##
## One pooled `MeshInstance2D` each (TRAILS_START made at once, more when more swing at once: no
## limit), the swing mesh Feel makes (`Feel.swing_mesh()`, from SWING_QUADS; its box is the whole
## world, so it is never culled). A trail
## follows its swing's hand while the swing lives, then stays where it ended. Nothing is
## allocated while playing, past a new trail node when every one is busy.

const SHADER: Shader = preload("res://core/projectiles/shot_swing.gdshader")
const BirthsScript := preload("res://gameplay/feel/births.gd")
## Trails made at once.
const TRAILS_START: int = 16
## Seconds a trail stays after its sweep ends (its slowest spark's life, and a little).
const TRAIL_SECONDS: float = 0.6
## The quad kinds of a trail's mesh (Q_* in `shot_swing.gdshader`): the light round the line, then
## the line.
const SWING_Q_LIGHT: int = 0
const SWING_Q_LINE: int = 1
const SWING_QUADS: Array[Vector3i] = [
	Vector3i(SWING_Q_LIGHT, 1, 0),
	Vector3i(SWING_Q_LINE, 1, 0),
]
## The sparks a whole sweep sheds (the shader drew 28 one-pixel sparks until S6; a spark mote glows
## and starts white-hot, so 16 read as many without thickening the line into a band) and the share
## of them in the infusion's ramp (every fourth, as the line's pixels); its card particles: 4, and 2
## more a card kind, at most PARTICLES_MOST (the shot shaders' MAX_PARTICLES).
const SPARKS: float = 16.0
const INFUSED_SHARE: float = 0.25
const PARTICLES_MOST: int = 12
## The line runs this far inside the reach (LINE_IN in the shader): the sparks leave from it, a
## pixel either side.
const LINE_IN: float = 2.0
## Swings draw where beams do: above the room, under the shots and the flashes.
const SWING_Z: int = 18

## The trail nodes, and for each: the swing it shows (`CarrierSwing.swing_born`; -1 for none) and the
## clock time it goes (its sweep's end plus TRAIL_SECONDS; it is off once the clock is past it).
var _nodes: Array[MeshInstance2D] = []
var _born: PackedInt64Array = PackedInt64Array()
var _until: PackedFloat32Array = PackedFloat32Array()
## How far each trail's swing had turned at the last step (`swing_turned`): the stretch since is
## what its tip passed this frame.
var _turned: PackedFloat32Array = PackedFloat32Array()


## The mesh every trail is drawn as.
var _mesh: ArrayMesh = null


func _init(mesh: ArrayMesh) -> void:
	_mesh = mesh
	top_level = true
	for i in TRAILS_START:
		_add_trail()


## Draws the live swings of `swings` (`Spells.carrier(&"swing")`, a `CarrierSwing`; none when null) at Feel's
## clock `now`: a new one takes a free trail, a live one moves its trail to its hand and gives off
## the motes of the stretch its tip passed into `births` (none when null: motes off), and a trail
## past its time is hidden. `ramp_of` gives the shader's player for an actor (0-3 a hat ramp, -1
## the enemy ramp); `glow` is how strongly it glows.
func step(swings: Object, now: float, ramp_of: Callable, glow: float, births: BirthsScript = null) -> void:
	var count: int = 0
	if swings != null:
		count = int(swings.call("swing_slots"))
	for at in count:
		if not bool(swings.call("swing_on", at)):
			continue
		var born: int = int(swings.call("swing_born", at))
		var slot: int = _born.find(born)
		var fresh: bool = slot < 0
		if fresh:
			slot = _free_trail(now)
			_born[slot] = born
		_show(slot, swings, at, now, fresh, ramp_of, glow)
		var turned: float = float(swings.call("swing_turned", at))
		if births != null and not fresh:
			_give_off(swings, at, _turned[slot], turned, int(ramp_of.call(int(swings.call("swing_actor", at)))), births)
		_turned[slot] = turned
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


## The shader parameter `name` of the trail showing swing `born` (`CarrierSwing.swing_born`), or null
## when none shows it (for tests).
func parameter_of(born: int, name: StringName) -> Variant:
	var slot: int = _born.find(born)
	if slot < 0 or not _nodes[slot].visible:
		return null
	return (_nodes[slot].material as ShaderMaterial).get_shader_parameter(name)


## Puts swing `at` of `swings` into trail `slot`: where its hand is and when its sweep starts on
## Feel's clock (kept in step with the swing every frame, so a local stop that holds it holds its
## trail); the rest once, when it is `fresh`.
func _show(slot: int, swings: Object, at: int, now: float, fresh: bool, ramp_of: Callable, glow: float) -> void:
	var node: MeshInstance2D = _nodes[slot]
	var material: ShaderMaterial = node.material as ShaderMaterial
	var sweep: float = float(swings.call("swing_sweep", at))
	var start: float = now - (float(swings.call("swing_age", at)) - float(swings.call("swing_wind", at)))
	material.set_shader_parameter(&"swing_origin", swings.call("swing_origin", at) as Vector2)
	material.set_shader_parameter(&"swing_start", start)
	material.set_shader_parameter(&"sim_time", now)
	_until[slot] = start + sweep + TRAIL_SECONDS
	if not fresh:
		return
	var half: float = deg_to_rad(float(swings.call("swing_arc", at))) * 0.5
	var tint: Color = swings.call("swing_tint", at) as Color
	material.set_shader_parameter(&"core_override", Color(tint.r, tint.g, tint.b, 1.0))
	material.set_shader_parameter(&"swing_player", int(ramp_of.call(int(swings.call("swing_actor", at)))))
	material.set_shader_parameter(&"swing_look", int(swings.call("swing_look", at)))
	material.set_shader_parameter(&"swing_dir", (swings.call("swing_dir", at) as Vector2).normalized())
	material.set_shader_parameter(&"swing_side", 1.0 if int(swings.call("swing_side", at)) >= 0 else -1.0)
	material.set_shader_parameter(&"swing_half", half)
	material.set_shader_parameter(&"swing_lean", half + deg_to_rad(SpellLimits.SWING_LEAN))
	material.set_shader_parameter(&"swing_reach", float(swings.call("swing_reach", at)))
	material.set_shader_parameter(&"swing_sweep", sweep)
	material.set_shader_parameter(&"swing_glow", glow)
	material.set_shader_parameter(&"swing_seed", float(int(swings.call("swing_born", at)) % 61) * 1.618)
	node.visible = true


## The motes swing `at` of `swings` gives off as its tip turns from `from` to `to` radians (its own
## turning, `swing_turned`), of the ramp `ramp`: the stretch of its arc that hits (its `swing_arc`)
## it passed, that stretch's share of the sparks and of its card particles, into `births`.
func _give_off(swings: Object, at: int, from: float, to: float, ramp: int, births: BirthsScript) -> void:
	var half: float = deg_to_rad(float(swings.call("swing_arc", at))) * 0.5
	var lo: float = maxf(minf(from, to), -half)
	var hi: float = minf(maxf(from, to), half)
	if half <= 0.0 or hi <= lo:
		return
	var share: float = (hi - lo) / (2.0 * half)
	var origin: Vector2 = swings.call("swing_origin", at) as Vector2
	var dir: Vector2 = (swings.call("swing_dir", at) as Vector2).normalized()
	var side: float = 1.0 if int(swings.call("swing_side", at)) >= 0 else -1.0
	var reach: float = float(swings.call("swing_reach", at))
	var tint: Color = swings.call("swing_tint", at) as Color
	var look: int = int(swings.call("swing_look", at))
	var tag: int = int(swings.call("swing_tag", at))
	var core: Color = Color(tint.r, tint.g, tint.b, 1.0)
	# Sparks, flung outward from the line where the tip passed.
	for n in births.roll(SPARKS * share):
		var out: Vector2 = dir.rotated(lerpf(lo, hi, births.dice()) * side)
		var from_line: float = reach - LINE_IN - 1.0 + 2.0 * births.dice()
		var infused: bool = births.dice() < INFUSED_SHARE
		if not births.add(origin + out * from_line, out, 0, ramp, look, core if infused else Color.WHITE, tag):
			return
	# Its cards' particles, back along the way the tip came.
	var kinds: int = BirthsScript.emitting_count(look)
	if kinds == 0:
		return
	for n in births.roll(float(mini(4 + 2 * kinds, PARTICLES_MOST)) * share):
		var out: Vector2 = dir.rotated(lerpf(lo, hi, births.dice()) * side)
		var back: Vector2 = Vector2(out.y, -out.x) * side
		if not births.add(origin + out * (reach - LINE_IN), back, births.emitting_layer(look), ramp, look, core, tag):
			return


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
	_turned.append(0.0)
