class_name StillMerge
extends RefCounted
## What a merging card body's shader is told of its shots each frame (`CarrierCard.look_merges`,
## `ProjectileManager.set_body_ground`): where every one of the body's still shots is drawn, its hit
## size as drawn and its still clock, so the shader draws the shots that overlap as one (a pool's
## spills run together: each pixel is drawn by the shot nearest it, from the outline of them all).
## One per merging body, made once.
##
## Both batches of the body's pair are told one list in one order, the hat ramps' shots then the
## enemy ramp's, each batch's in its row order, so the two agree on which shot is nearest a pixel
## (of two as near, the first listed) and a player's pool and an imp's run together too. Each batch
## is told where its own shots start (`merge_first`), so its shader finds a shot's own entry at
## `merge_first + INSTANCE_ID`. MOST at most: a shot past them is drawn alone.
##
## The shader's uniforms (`pool.gdshader`): `merge_count`, `merge_first` and `merge_place` (x, y the
## shot's middle in world pixels, z its hit size as drawn, w its still clock's code,
## `ProjectileManager.still_code`, plus the way its quad turns, its facing (`set_facing`), in whole
## steps of FACING_STEPS a turn: the code is below a half either way, so the two never mix).
##
## A frame allocates nothing: it fills one of two lists in turn, so the one a material was last
## handed is never written while the material holds it (a written array it shares would be copied).

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## View only: the manager's drawing fills it, the simulation never reads it (core/sim/README.md).
const VIEW_ONLY: bool = true

## The most shots a merging body's shader is told of (the shader's MERGE_MOST: test_projectile_bodies
## checks the two are equal).
const MOST: int = 64
## The steps of a turn a shot's facing is told in (the shader's FACING_STEPS).
const FACING_STEPS: int = 64

## How many shots the list holds, and where the enemy ramp's batch's start in it.
var count: int = 0
var enemy_first: int = 0

## The two lists, filled in turn (`_on_b`: the second is the one filled last). Members written in
## place: a packed array held in a local or another array is a copy once written.
var _a: PackedVector4Array = PackedVector4Array()
var _b: PackedVector4Array = PackedVector4Array()
var _on_b: bool = false


func _init() -> void:
	_a.resize(MOST)
	_b.resize(MOST)


## The list filled last (read only: it is a material's).
func places() -> PackedVector4Array:
	return _b if _on_b else _a


## The hat ramps' batch's `hats` rows of `hat_rows`, then the enemy ramp's `foes` of `foe_rows`.
func fill(hat_rows: PackedFloat32Array, hats: int, foe_rows: PackedFloat32Array, foes: int) -> void:
	_on_b = not _on_b
	count = 0
	_add(hat_rows, hats)
	enemy_first = count
	_add(foe_rows, foes)


## Hands the list to the batch `material` of the pair (the enemy ramp's with `enemy`).
func hand_to(material: ShaderMaterial, enemy: bool) -> void:
	material.set_shader_parameter(&"merge_count", count)
	material.set_shader_parameter(&"merge_first", enemy_first if enemy else 0)
	material.set_shader_parameter(&"merge_place", places())


## The step of a turn (0 to FACING_STEPS - 1) the way `across` points is told in.
static func facing_step(across: Vector2) -> int:
	return posmod(roundi(across.angle() / TAU * FACING_STEPS), FACING_STEPS)


## Tells `material` of no shots: its shots are drawn alone.
static func hand_none(material: ShaderMaterial) -> void:
	material.set_shader_parameter(&"merge_count", 0)


func _add(rows: PackedFloat32Array, shots: int) -> void:
	for n in mini(mini(shots, rows.size() / ManagerScript.DRAW_STRIDE), MOST - count):
		var at: Vector2 = ManagerScript.row_place(rows, n)
		var place := Vector4(at.x, at.y, ManagerScript.row_reach(rows, n), ManagerScript.row_code(rows, n) + float(facing_step(ManagerScript.row_across(rows, n))))
		if _on_b:
			_b[count] = place
		else:
			_a[count] = place
		count += 1
