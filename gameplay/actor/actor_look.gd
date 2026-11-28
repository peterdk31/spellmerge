class_name ActorLook
extends Node2D
## The base of an actor's looks (actors G4, docs/milestones/M2-actors.md, "The components"): the
## wizard's (gameplay/player, G7) and a creature's (gameplay/ai, G6). A look reads the actor and
## draws it; it changes nothing the game plays by. The actor calls `setup` once in its `_ready`,
## `step` last in every step, after the body's velocity is set, and `sync` after a snapshot gave
## the body its state back; a look has no process callback of its own. A still body is never
## stepped (props W2), so the one exception is a look that animates on its own while its body is
## still (a prop's flickering layer, props W7): it may run `_process`, on the view's clock, only
## while it animates, and must say `VIEW_ONLY`.

## The staff animations (`Spells.poses().staff_pose` and the rest: the carrier card's `staff_pose`, played
## for the actor's own cast) every look shows the same way through `apply_pose` and `pose_offset`:
## the body lifted, pushed along the aim and shaking, stretched along the aim, glowing in the
## infusion's colour (else the ramp's) and the face's brows in the animation's mood. Only the turn
## and the land are the look's own (a wizard's head sheet has 16 directions and a tip to land; a
## creature's sprite has neither).
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
## The shots' sprite shader (core/README.md, "The shot shaders"): the body's glow keeps the
## sprite's own colours (`core_override` alpha 0) and adds light round it.
const SPRITE_SHADER: Shader = preload("res://core/projectiles/shot_sprite.gdshader")
## How bright the body's glow is at an animation's full glow (`Spells.poses().staff_glow` 1).
const POSE_GLOW: float = 1.6
## How fast a shaking body jitters (radians a second on each axis, out of step).
const SHAKE_RATE: Vector2 = Vector2(97.0, 83.0)
## The brows an animation's mood (`Spells.poses().staff_mood`) shows, by its name, renewed each step for
## this long while the animation says so (it fades right after).
const POSE_MOODS: Dictionary = {&"raised": Face.Mood.RAISED, &"angry": Face.Mood.ANGRY, &"furious": Face.Mood.FURIOUS, &"worried": Face.Mood.WORRIED}
const POSE_MOOD_SECONDS: float = 0.08
## `pose_offset`'s, `pose_scale`'s and `apply_pose`'s `dir` when the caller has not read `pose_dir()`.
const UNREAD: Vector2 = Vector2.INF

## View as a whole: the state walk never enters it (core/sim/README.md).
const VIEW_ONLY: bool = true

## The actor this look draws (set by `setup`).
var actor: Actor = null
## The body's material while its animation glows (made the first time), and whether the body is
## stretched by its animation (to put its scale back once when it ends).
var _glow_material: ShaderMaterial = null
var _pose_stretched: bool = false
## The Spells `pose_dir` last read its staff animations from, and its `StaffPoses` (asked once).
var _poses_of: Node = null
var _poses: StaffPoses = null
## The glow's colour and strength last set on `_glow_material` (NaN: none yet).
var _glow_colour_set: Color = Color(NAN, NAN, NAN, NAN)
var _glow_set: float = NAN
## The staff animation as `pose_dir` last read it (`StaffPoses.read_look`; `StaffPoses.Look`'s order).
var _pose_look: PackedFloat32Array = _new_pose_look()


func setup(owner_actor: Actor) -> void:
	actor = owner_actor


## Show the actor as it is now, after a snapshot gave it its state back: what the look follows from
## moments it was told of (a prop's state) is read again, and no moment plays. The base has none.
func sync() -> void:
	pass


## Draw the actor as it is after this step (`delta` seconds). The base draws nothing.
func step(_delta: float) -> void:
	pass


## The aim the actor's staff animation turns from, or zero while it plays none (or it is down).
##
## Asked by every look every drawn frame, so a body that plays none is answered from two reads
## (`StaffPoses.may_play`, through the poses kept from its Spells: `_poses_of`), and one that plays
## one has all of it read at once (`StaffPoses.read_look`, into `_pose_look`), which `pose_offset`,
## `pose_scale`, `apply_pose` and `pose_turn` show when handed this step's `dir` (performance,
## 2026-11-28: each read of a getter walked to the animation's memo again).
func pose_dir() -> Vector2:
	if actor == null or actor.spells == null:
		return Vector2.ZERO
	if actor.spells != _poses_of:
		_poses_of = actor.spells
		_poses = actor.spells.poses()
	if _poses == null or not _poses.may_play(actor.id) or actor.is_down() or not _poses.read_look(actor.id, _pose_look):
		return Vector2.ZERO
	return Vector2(_pose_look[StaffPoses.Look.DIR_X], _pose_look[StaffPoses.Look.DIR_Y])


## The turn (radians) of the animation `dir` (this step's `pose_dir()`, not zero) plays now: its
## `StaffPoses.staff_pose` x.
func pose_turn() -> float:
	return _pose_look[StaffPoses.Look.TURN]


## How far the animation moves the body now: up by its lift, along the aim by its push and about by
## its shake (at `time`, the look's own clock), in whole pixels; zero while it plays none.
##
## `dir` is `pose_dir()` when the caller read it already this step (a look asks several of these a
## step: `UNREAD` reads it here).
func pose_offset(time: float, dir: Vector2 = UNREAD) -> Vector2:
	if dir == UNREAD:
		dir = pose_dir()
	if dir.is_zero_approx():
		return Vector2.ZERO
	var shake: float = _pose_look[StaffPoses.Look.SHAKE]
	var jitter: Vector2 = Vector2(sin(time * SHAKE_RATE.x), cos(time * SHAKE_RATE.y)) * shake
	return (Vector2(0.0, -_pose_look[StaffPoses.Look.LIFT]) + dir * _pose_look[StaffPoses.Look.PUSH] + jitter).round()


## The body's scale for the animation's stretch: longer along the axis its aim runs most along,
## thinner across (its area kept), squashed for a negative stretch; one while it plays none.
func pose_scale(dir: Vector2 = UNREAD) -> Vector2:
	if dir == UNREAD:
		dir = pose_dir()
	if dir.is_zero_approx():
		return Vector2.ONE
	var along: float = maxf(1.0 + _pose_look[StaffPoses.Look.STRETCH], 0.2)
	if absf(dir.x) >= absf(dir.y):
		return Vector2(along, 1.0 / along)
	return Vector2(1.0 / along, along)


## Shows the animation's stretch (unless `keep_scale`: another look owns the scale, a dash),
## glow and mood on `sprite` and `face` (either may be null). Feel's flash on a hit keeps the
## sprite while it shows; the glow takes it back after, and gives it up when it ends. `dir` as for
## `pose_offset`.
func apply_pose(sprite: Sprite2D, face: Face, keep_scale: bool, dir: Vector2 = UNREAD) -> void:
	if dir == UNREAD:
		dir = pose_dir()
	var posing: bool = not dir.is_zero_approx()
	# While it plays none the scale is one, so only a body it stretched has its scale put back.
	# (An animation with no stretch leaves an unstretched body as it is.)
	if sprite != null and not keep_scale and (posing or _pose_stretched) and (_pose_stretched or _pose_look[StaffPoses.Look.STRETCH] != 0.0):
		var scale_now: Vector2 = pose_scale(dir)
		if scale_now != Vector2.ONE or _pose_stretched:
			_pose_stretched = scale_now != Vector2.ONE
			# Times its art's detail: a 2x sprite is drawn at half its size (ArtDetail). Set only
			# when it changed (each set moves the body's children too).
			var drawn: Vector2 = scale_now * ArtDetail.draw_scale(sprite.texture)
			if sprite.scale != drawn:
				sprite.scale = drawn
	if sprite != null:
		_apply_glow(sprite, _pose_look[StaffPoses.Look.GLOW] if posing else 0.0)
	if face != null and posing:
		var mood: int = roundi(_pose_look[StaffPoses.Look.MOOD])
		if mood > 0:
			var mood_name: StringName = CarrierCard.POSE_MOODS[mood - 1]
			if POSE_MOODS.has(mood_name):
				face.show_mood(POSE_MOODS[mood_name] as Face.Mood, POSE_MOOD_SECONDS)


## `apply_pose` then `pose_offset`, for a look that shows both every step: at once while no
## animation plays (`dir`, `pose_dir()` read this step, is zero) and none is left on `sprite` to
## put back (its stretch, its glow).
func show_pose(sprite: Sprite2D, face: Face, keep_scale: bool, time: float, dir: Vector2) -> Vector2:
	if dir.is_zero_approx() and not _pose_stretched and not is_glowing(sprite):
		return Vector2.ZERO
	apply_pose(sprite, face, keep_scale, dir)
	return pose_offset(time, dir)


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
	# The infusion's colour when it has one, else the actor's ramp's (read with the glow: `pose_dir`).
	# Each set only when it changed (a glowing body is drawn every frame, each set a call to the
	# renderer).
	var tint: Color = Color(_pose_look[StaffPoses.Look.TINT_R], _pose_look[StaffPoses.Look.TINT_G], _pose_look[StaffPoses.Look.TINT_B], _pose_look[StaffPoses.Look.TINT_A])
	var colour: Color = ProjectilesScript.ramp_light(actor.ramp) if tint.is_equal_approx(Color.WHITE) else Color(tint.r, tint.g, tint.b, 1.0)
	if colour != _glow_colour_set:
		_glow_colour_set = colour
		_glow_material.set_shader_parameter(&"glow_color", colour)
	if glow * POSE_GLOW != _glow_set:
		_glow_set = glow * POSE_GLOW
		_glow_material.set_shader_parameter(&"sprite_glow", _glow_set)
	if sprite.material != _glow_material:
		sprite.material = _glow_material


static func _new_pose_look() -> PackedFloat32Array:
	var look := PackedFloat32Array()
	look.resize(StaffPoses.Look.SIZE)
	return look
