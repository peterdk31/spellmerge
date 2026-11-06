extends Node2D
## Telegraph lanes: a cue's `lane` parts (`CueBase`, "part": "lane"; docs/milestones/cast-timing.md,
## T6b). While a cast winds up, a lane runs from its caster's staff tip along its live aim (the aim
## follows the caster until the cast leaves, owner 2026-11-06), as long as its carrier reaches and
## as wide as it hits, in the cast's tint: its dashes march toward the tip, its arrowhead grows and
## the lane brightens as the wind-up runs out (`telegraph.gdshader`). It ends the step the cast
## leaves or is cancelled (`Spells.is_winding`), so it always shows a cast that comes. A carrier
## that is not aimed (a nova, an orbit) shows none.
##
## It reads the runtime (`Spells`: where the caster holds its staff and aims, the carrier's reach,
## whether it still winds up) and keeps nothing the simulation reads. Feel owns one and steps it once
## a frame. Allocation-free after its sprites are made.

const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const TELEGRAPH_SHADER: Shader = preload("res://gameplay/feel/telegraph.gdshader")
const BEAM_TEXTURE: Texture2D = preload("res://art/vfx/beam.svg")

## The most lanes at once; one more takes the place of the oldest.
const MOST: int = 32
## The lane starts this far past the staff tip, so it never covers the caster's own hand.
const START: float = 4.0
## A sprite's region height (its texture's), with the lane in its middle.
const HEIGHT: float = 32.0
## The lane is the hit width of what is coming plus this margin, either side half of it.
const LANE_MARGIN: float = 8.0
## How much lighter than the tint the lane's light shade is.
const LIGHTER: float = 0.45

## The spell runtime (`Spells`), read only.
var spells: Node = null

## The lanes under way: the first `count` of each list.
var count: int = 0
var _sprites: Array[Sprite2D] = []
var _caster: PackedInt32Array = PackedInt32Array()
var _staff: PackedInt32Array = PackedInt32Array()
var _total: PackedFloat32Array = PackedFloat32Array()
var _reach: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	# Compiled before the first room, as every shader is (core/README.md, "The shot shaders").
	ShaderWarmupScript.want(TELEGRAPH_SHADER, ShaderWarmupScript.RECT)
	_caster.resize(MOST)
	_staff.resize(MOST)
	_total.resize(MOST)
	_reach.resize(MOST)
	for i in MOST:
		var sprite := Sprite2D.new()
		sprite.texture = BEAM_TEXTURE
		sprite.centered = false
		sprite.region_enabled = true
		sprite.visible = false
		var material := ShaderMaterial.new()
		material.shader = TELEGRAPH_SHADER
		sprite.material = material
		add_child(sprite)
		_sprites.append(sprite)


## A lane for the cast `tag` of `caster` winding up for `seconds`, in `tint`, `reach` times as long
## as its carrier reaches. A new lane of the same caster's staff takes over its old one.
func play(caster: int, tag: int, seconds: float, tint: Color, reach: float) -> void:
	if spells == null or seconds <= 0.0 or _sprites.is_empty():
		return
	var length: float = float(spells.call("carrier_reach", tag)) * maxf(reach, 0.0)
	if length <= START:
		return
	var staff: int = SpellTag.staff_of(tag)
	var at: int = -1
	for i in count:
		if _caster[i] == caster and _staff[i] == staff:
			at = i
			break
	if at < 0:
		if count < MOST:
			at = count
			count += 1
		else:
			at = 0
	_caster[at] = caster
	_staff[at] = staff
	_total[at] = seconds
	_reach[at] = length
	var sprite: Sprite2D = _sprites[at]
	var run: float = length - START
	sprite.offset = Vector2(START, -HEIGHT * 0.5)
	sprite.region_rect = Rect2(0.0, 0.0, run, HEIGHT)
	var material: ShaderMaterial = sprite.material as ShaderMaterial
	material.set_shader_parameter(&"ramp_base", tint)
	material.set_shader_parameter(&"ramp_light", tint.lerp(Color.WHITE, LIGHTER))
	material.set_shader_parameter(&"beam_length", run)
	material.set_shader_parameter(&"telegraph_lane", float(spells.call("carrier_radius", tag)) + LANE_MARGIN * 0.5)
	material.set_shader_parameter(&"telegraph_progress", 0.0)
	_place(at)


## Once a frame: each lane follows its caster's staff tip and aim and shows how far its wind-up has
## run; one whose cast left, or was cancelled, goes.
func step() -> void:
	var i: int = 0
	while i < count:
		if spells == null or not bool(spells.call("is_winding", _caster[i], _staff[i])) or not _place(i):
			_remove(i)
			continue
		i += 1


## How far the lane of `caster` reaches (0 for none), for tests.
func reach_of(caster: int) -> float:
	for i in count:
		if _caster[i] == caster:
			return _reach[i]
	return 0.0


## The lane's sprite of `caster`, or null (for tests).
func sprite_of(caster: int) -> Sprite2D:
	for i in count:
		if _caster[i] == caster:
			return _sprites[i]
	return null


## Lane `i` where its caster holds its staff and aims now, and its progress; false when its caster
## has no aim any more.
func _place(i: int) -> bool:
	var origin: Vector2 = spells.call("aim_origin_of", _caster[i])
	var way: Vector2 = spells.call("aim_of", _caster[i])
	if not origin.is_finite() or not way.is_finite():
		return false
	var sprite: Sprite2D = _sprites[i]
	sprite.global_position = origin
	sprite.rotation = way.angle()
	sprite.visible = true
	var left: float = float(spells.call("cooldown_left", _caster[i], _staff[i]))
	var progress: float = clampf(1.0 - left / _total[i], 0.0, 1.0) if _total[i] > 0.0 else 1.0
	(sprite.material as ShaderMaterial).set_shader_parameter(&"telegraph_progress", progress)
	return true


## Lane `i` goes; the last one takes its place.
func _remove(i: int) -> void:
	var last: int = count - 1
	var gone: Sprite2D = _sprites[i]
	gone.visible = false
	if i != last:
		_sprites[i] = _sprites[last]
		_sprites[last] = gone
		_caster[i] = _caster[last]
		_staff[i] = _staff[last]
		_total[i] = _total[last]
		_reach[i] = _reach[last]
	count = last
