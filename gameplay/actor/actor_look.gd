class_name ActorLook
extends Node2D
## The base of an actor's looks (actors G4, docs/milestones/M2-actors.md, "The components"): the
## wizard's (gameplay/player, G7) and a creature's (gameplay/ai, G6). A look reads the actor and
## draws it; it changes nothing the game plays by. The actor calls `setup` once in its `_ready`
## and `step` last in every step, after the body's velocity is set; a look has no process
## callback of its own.

## The staff animations (`Spells.staff_pose` and the rest: the carrier card's `staff_pose`, played
## for the actor's own cast) every look shows the same way through `apply_pose` and `pose_offset`:
## the body lifted, pushed along the aim and shaking, stretched along the aim, glowing in the
## infusion's colour (else the ramp's) and the face's brows in the animation's mood. Only the turn
## is the look's own (a wizard's head sheet has 16 directions; a creature's sprite has none).
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
## The shots' sprite shader (core/README.md, "The shot shaders"): the body's glow keeps the
## sprite's own colours (`core_override` alpha 0) and adds light round it.
const SPRITE_SHADER: Shader = preload("res://core/projectiles/shot_sprite.gdshader")
## How bright the body's glow is at an animation's full glow (`Spells.staff_glow` 1).
const POSE_GLOW: float = 1.6
## How fast a shaking body jitters (radians a second on each axis, out of step).
const SHAKE_RATE: Vector2 = Vector2(97.0, 83.0)
## The brows an animation's mood (`Spells.staff_mood`) shows, by its name, renewed each step for
## this long while the animation says so (it fades right after).
const POSE_MOODS: Dictionary = {&"raised": Face.Mood.RAISED, &"angry": Face.Mood.ANGRY, &"furious": Face.Mood.FURIOUS, &"worried": Face.Mood.WORRIED}
const POSE_MOOD_SECONDS: float = 0.08

## The actor this look draws (set by `setup`).
var actor: Actor = null
## The body's material while its animation glows (made the first time), and whether the body is
## stretched by its animation (to put its scale back once when it ends).
var _glow_material: ShaderMaterial = null
var _pose_stretched: bool = false


func setup(owner_actor: Actor) -> void:
	actor = owner_actor


## Draw the actor as it is after this step (`delta` seconds). The base draws nothing.
func step(_delta: float) -> void:
	pass


## The aim the actor's staff animation turns from, or zero while it plays none (or it is down).
func pose_dir() -> Vector2:
	if actor == null or actor.spells == null or actor.is_down():
		return Vector2.ZERO
	return actor.spells.staff_pose_dir(actor.id)


## How far the animation moves the body now: up by its lift, along the aim by its push and about by
## its shake (at `time`, the look's own clock), in whole pixels; zero while it plays none.
func pose_offset(time: float) -> Vector2:
	var dir: Vector2 = pose_dir()
	if dir.is_zero_approx():
		return Vector2.ZERO
	var pose: Vector3 = actor.spells.staff_pose(actor.id)
	var shake: float = actor.spells.staff_shake(actor.id)
	var jitter: Vector2 = Vector2(sin(time * SHAKE_RATE.x), cos(time * SHAKE_RATE.y)) * shake
	return (Vector2(0.0, -pose.y) + dir * pose.z + jitter).round()


## The body's scale for the animation's stretch: longer along the axis its aim runs most along,
## thinner across (its area kept), squashed for a negative stretch; one while it plays none.
func pose_scale() -> Vector2:
	var dir: Vector2 = pose_dir()
	if dir.is_zero_approx():
		return Vector2.ONE
	var along: float = maxf(1.0 + actor.spells.staff_stretch(actor.id), 0.2)
	if absf(dir.x) >= absf(dir.y):
		return Vector2(along, 1.0 / along)
	return Vector2(1.0 / along, along)


## Shows the animation's stretch (unless `keep_scale`: another look owns the scale, a dash),
## glow and mood on `sprite` and `face` (either may be null). Feel's flash on a hit keeps the
## sprite while it shows; the glow takes it back after, and gives it up when it ends.
func apply_pose(sprite: Sprite2D, face: Face, keep_scale: bool) -> void:
	var posing: bool = not pose_dir().is_zero_approx()
	if sprite != null and not keep_scale:
		var scale_now: Vector2 = pose_scale()
		if scale_now != Vector2.ONE or _pose_stretched:
			_pose_stretched = scale_now != Vector2.ONE
			sprite.scale = scale_now
	if sprite != null:
		_apply_glow(sprite, actor.spells.staff_glow(actor.id) if posing else 0.0)
	if face != null and posing:
		var mood: StringName = actor.spells.staff_mood(actor.id)
		if POSE_MOODS.has(mood):
			face.show_mood(POSE_MOODS[mood] as Face.Mood, POSE_MOOD_SECONDS)


## True while the body glows with its animation.
func is_glowing(sprite: Sprite2D) -> bool:
	return sprite != null and _glow_material != null and sprite.material == _glow_material


func _apply_glow(sprite: Sprite2D, glow: float) -> void:
	if glow <= 0.0:
		if _glow_material != null and sprite.material == _glow_material:
			sprite.material = null
		return
	if sprite.material != null and sprite.material != _glow_material:
		return
	if _glow_material == null:
		_glow_material = ShaderMaterial.new()
		_glow_material.shader = SPRITE_SHADER
		_glow_material.set_shader_parameter(&"core_override", Color(0.0, 0.0, 0.0, 0.0))
	# The infusion's colour when it has one, else the actor's ramp's.
	var tint: Color = actor.spells.staff_glow_tint(actor.id)
	var colour: Color = ProjectilesScript.ramp_light(actor.ramp) if tint.is_equal_approx(Color.WHITE) else Color(tint.r, tint.g, tint.b, 1.0)
	_glow_material.set_shader_parameter(&"glow_color", colour)
	_glow_material.set_shader_parameter(&"sprite_glow", glow * POSE_GLOW)
	sprite.material = _glow_material
