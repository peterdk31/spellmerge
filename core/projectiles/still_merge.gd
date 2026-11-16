class_name StillMerge
extends RefCounted
## What a merging card body's shader is told of its shots each frame (`CarrierCard.look_merges`,
## `ProjectileManager.set_body_ground`): where every one of the body's still shots is drawn, its hit
## size as drawn and its still clock, so the shader draws the shots that overlap as one (a pool's
## puddles run together: each pixel is drawn by the shot nearest it, from the outline of them all).
## One per batch of the body's pair, made once and refilled in place: a frame allocates nothing.
##
## The batch's own shots come first, in its row order, so its shader finds a shot's own entry at its
## `INSTANCE_ID`; the other batch's (the enemy ramp's, or the hats') follow, so a player's pool and
## an imp's run together too. MOST at most: a shot past them is drawn alone.
##
## The shader's uniforms (`pool.gdshader`): `merge_count`, `merge_place` (x, y the shot's middle in
## world pixels, z its hit size as drawn, w its still clock's code, `ProjectileManager.still_code`)
## and `merge_seed` (its wobble's seed: its row number's, as the shader seeds its own).

const ManagerScript := preload("res://core/projectiles/projectile_manager.gd")

## View only: the manager's drawing fills it, the simulation never reads it (core/sim/README.md).
const VIEW_ONLY: bool = true

## The most shots a merging body's shader is told of (the shader's MERGE_MOST: keep the two equal).
const MOST: int = 32

var count: int = 0
var places: PackedVector4Array = PackedVector4Array()
var seeds: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	places.resize(MOST)
	seeds.resize(MOST)


## The seed a still shot drawn as row `n` of its batch wobbles by (the shader's `row_seed`).
static func row_seed(n: int) -> float:
	return float(n % 61) * 1.618


## Its batch's own `shots` rows of `own`, then the `others` rows of the other batch.
func fill(own: PackedFloat32Array, shots: int, other: PackedFloat32Array, others: int) -> void:
	count = 0
	_add(own, shots)
	_add(other, others)


## Hands what it holds to `material` (the batch's shader).
func hand_to(material: ShaderMaterial) -> void:
	material.set_shader_parameter(&"merge_count", count)
	material.set_shader_parameter(&"merge_place", places)
	material.set_shader_parameter(&"merge_seed", seeds)


func _add(rows: PackedFloat32Array, shots: int) -> void:
	for n in mini(mini(shots, rows.size() / ManagerScript.DRAW_STRIDE), MOST - count):
		var at: Vector2 = ManagerScript.row_place(rows, n)
		places[count] = Vector4(at.x, at.y, ManagerScript.row_reach(rows, n), ManagerScript.row_code(rows, n))
		seeds[count] = row_seed(n)
		count += 1
