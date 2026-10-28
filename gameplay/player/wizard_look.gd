class_name WizardLook
extends ActorLook
## The wizard's look (actors G7, docs/milestones/M2-actors.md, "The components"): everything a
## wizard draws, read from the actor and changing nothing the game plays by. All the wizard's
## drawing is here (another look may replace it later).
##
## The scene's `Sprite` (with a `Hat` under it) plays an idle, a walk or a dash strip (frames of
## FRAME_SIZE px side by side, see docs/STYLE.md), picked from what the body does: a dash, hook
## or swap (`Mover.is_moving`) plays the dash strip, a speed over WALK_THRESHOLD the walk. The body
## has no player colour; the hat is the only part in it, one picture per ramp (`hat_textures`,
## the actor's `ramp` 0-3), and moves with the body's bob. The idle blinks, glances and breathes
## (IDLE_SEQUENCE, BREATH_STEPS; each ramp starts IDLE_STEP_OFFSET steps further in, so a group
## does not blink on the same beat). The sprite turns toward the aim (FLIP_BAND against flicker).
##
## A dash, hook or swap stretches and leans the sprite along its way (`Mover.move_direction`; a
## standing actor dashes the way it aims) and leaves three ghosts where the wizard was: solid
## copies drawn by the shot shader (the glow look, 2026-10-27), turned to the ramp's light colour
## and falling apart pixel by pixel, the older the more (GHOST_DISSOLVE), never see-through.
##
## Drawn by this node, above the sprite (it comes after `Sprite` in the scene): the staff (the
## staff art from the hand along the aim, a gem at the tip), the aim reticle (a chevron), the
## closing ring while the actor cannot be hurt (`Health.protect`, with the sprite 55% opaque) and,
## while it is down, only the revive ring (`Downed.revive_progress`: an arc sweeping clockwise from
## the top, a cross in the middle). A soft shadow under the feet and the ghosts are nodes of their
## own, put under the sprite. Colours are the ramp's light shade (the projectile manager's
## `ramp_light`, docs/STYLE.md), as Feel's flashes in the player's colours.
##
## It redraws only when something drawn changed. Nothing here allocates per step (the ghosts are
## made the first time they are needed).

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## Sprite strips: every frame is FRAME_SIZE wide, the frame count is the strip's width divided by
## it. Idle and walk loop; the dash plays once and holds its last frame.
const FRAME_SIZE: int = 32
const IDLE_FPS: float = 6.0
const WALK_FPS: float = 8.0
const DASH_FPS: float = 16.0
## The idle strip has four poses: 0 eyes open, 1 eyes closed, 2 glance left, 3 glance right (on
## screen: the sprite is mirrored when the wizard faces left, so the two glances swap then).
## IDLE_SEQUENCE says which one shows at each idle step (8 s, then it loops).
const IDLE_SEQUENCE: Array[int] = [
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0,
	0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 3, 3, 3, 3,
]
const IDLE_STEP_OFFSET: int = 13
## Breathing: for the second half of every BREATH_STEPS idle steps the body sits 1 px lower.
const BREATH_STEPS: int = 12
## How many pixels the body (and the hat) sit lower on each frame of the walk, and of the dash
## (a crouch, then lifted off the ground; the shadow stays).
const WALK_BOB: Array[int] = [1, 0, 1, 0]
const DASH_BOB: Array[int] = [1, -2]
## Pixels per second above which the wizard counts as walking.
const WALK_THRESHOLD: float = 10.0
## Aim x beyond which the sprite turns (and turns back): a band against flicker.
const FLIP_BAND: float = 0.3
## Dash look: sprite stretch along the dash (a mostly vertical one swaps the axes), lean in
## radians, a ghost every GHOST_INTERVAL seconds, their dissolve (one per ghost) and glow.
const DASH_STRETCH: Vector2 = Vector2(1.2, 0.85)
const DASH_LEAN: float = 0.1
const GHOST_INTERVAL: float = 0.04
const GHOST_DISSOLVE: Array[float] = [0.2, 0.45, 0.7]
const GHOST_GLOW: float = 0.7
const CORE_SHADER: Shader = preload("res://core/projectiles/shot_core.gdshader")
## The reticle: its distance from the hand and its size, in pixels.
const RETICLE_DISTANCE: float = 38.0
const RETICLE_SIZE: float = 4.0
## Where the hand is on staff.svg (its pivot), in pixels from the corner.
const STAFF_PIVOT: Vector2 = Vector2(14.0, 16.0)
## The protect ring closes over this many seconds at most (it shows how much is left); the
## sprite's opacity and the ring's size while it shows.
const INVULNERABLE_TIME: float = 2.0
const INVULNERABLE_ALPHA: float = 0.55
const INVULNERABLE_RING_RADIUS: float = 15.0
const INVULNERABLE_RING_HEIGHT: float = 14.0
## The revive ring over a downed wizard: radius, the height of its centre above the feet (over the
## hat, so the body stays visible) and the colour of its empty track.
const REVIVE_RING_RADIUS: float = 7.0
const REVIVE_RING_HEIGHT: float = 34.0
const REVIVE_RING_BACK: Color = Color("5a5a6e")
const OUTLINE_COLOR: Color = Color("14121f")
## How far toward white the ghosts go from the ramp's light shade.
const GHOST_LIGHT: float = 0.4

enum Anim { IDLE, WALK, DASH }

## One idle, walk and dash strip per ramp 0-3 (the body has no player colour, so they can be the
## same file). An empty list (or a missing ramp) for walk or dash keeps the idle strip.
@export var textures: Array[Texture2D] = []
@export var walk_textures: Array[Texture2D] = []
@export var dash_textures: Array[Texture2D] = []
## The hat, one 32x32 picture per ramp: the only part in the player colour.
@export var hat_textures: Array[Texture2D] = []
## The staff, drawn from the hand along the aim; pointing right, hand at STAFF_PIVOT. Without it a
## plain line is drawn.
@export var staff_texture: Texture2D = null

## The `Sprite` node (null without one) and the `Hat` under it.
var _sprite: Sprite2D = null
var _hat: Sprite2D = null
## The actor's Downed component (null without one).
var _downed: Downed = null
## The shadow, drawn under the sprite.
var _shadow: Node2D = null
var _faces_left: bool = false
## Which strip the sprite shows and the seconds it has played.
var _anim: Anim = Anim.IDLE
var _anim_time: float = 0.0
## True while the dash look is applied (to reset it once when the move ends).
var _dash_look: bool = false
## Where the wizard was at the last ghost ticks of the dash (newest first; a fixed array, only
## overwritten), and the time to the next tick.
var _trail: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _trail_timer: float = 0.0
## The dash ghosts (sprites made the first time they are needed, each with its hat), newest first.
var _ghosts: Array[Sprite2D] = []
## True while the invulnerable look (translucent sprite and ring) is shown.
var _invulnerable_look: bool = false
## What the last draw showed, to redraw only on a change.
var _drawn_aim: Vector2 = Vector2.ZERO
var _drawn_down: bool = false
var _drawn_progress: float = 0.0


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_downed = Downed.of(actor)
	_sprite = actor.get_node_or_null(^"Sprite") as Sprite2D
	if _sprite != null:
		_hat = _sprite.get_node_or_null(^"Hat") as Sprite2D
	if _shadow == null:
		_shadow = Node2D.new()
		_shadow.name = "Shadow"
		_shadow.draw.connect(_draw_shadow)
		actor.add_child(_shadow)
		actor.move_child(_shadow, _sprite.get_index() if _sprite != null else 0)
	apply_texture()


## Show the idle strip and the hat of the actor's ramp on the `Sprite` node.
func apply_texture() -> void:
	if _sprite == null:
		return
	var ramp: int = actor.ramp
	if ramp < 0 or ramp >= textures.size():
		push_warning("WizardLook: no texture for ramp %d." % ramp)
		return
	_anim = Anim.IDLE
	_anim_time = 0.0
	_show_strip(textures[ramp])
	if _hat != null and ramp < hat_textures.size():
		_hat.texture = hat_textures[ramp]
	_set_bob(0)


func step(delta: float) -> void:
	var down: bool = actor.is_down()
	var moving: bool = not down and actor.mover != null and actor.mover.is_moving()
	if moving and not _dash_look:
		# The ghosts start on the wizard and grow out behind as the move goes on.
		_trail.fill(actor.global_position)
		_trail_timer = GHOST_INTERVAL
	elif _dash_look:
		_tick_trail(delta)
	if not down:
		_update_animation(delta, moving)
	_turn()
	if moving or _dash_look:
		_apply_dash_look(moving)
	_update_invulnerable_look(down)
	var progress: float = _downed.revive_progress() if _downed != null else 0.0
	if not actor.aim.is_equal_approx(_drawn_aim) or down != _drawn_down or progress != _drawn_progress:
		_drawn_aim = actor.aim
		_drawn_down = down
		_drawn_progress = progress
		queue_redraw()


## Which strip the sprite shows now.
func anim() -> Anim:
	return _anim


## True while the dash look (stretch, lean, ghosts) is on.
func is_dash_look() -> bool:
	return _dash_look


## True while the invulnerable look (translucent sprite and ring) is on.
func is_invulnerable_look() -> bool:
	return _invulnerable_look


## True when the sprite is turned to face left.
func faces_left() -> bool:
	return _faces_left


## The ghost sprites (empty until the first dash), newest first.
func ghosts() -> Array[Sprite2D]:
	return _ghosts


## Where the reticle's point is drawn, on the line of the shot.
func reticle_position() -> Vector2:
	return actor.aim_pivot() + actor.aim * RETICLE_DISTANCE


## The light shade of the actor's ramp (the reticle, the gem, the rings).
func light_color() -> Color:
	return ProjectilesScript.ramp_light(actor.ramp)


## Show a strip on the sprite from its first frame.
func _show_strip(strip: Texture2D) -> void:
	_sprite.texture = strip
	_sprite.hframes = maxi(int(strip.get_width()) / FRAME_SIZE, 1)
	_sprite.frame = 0


## The strip for an animation: the walk or dash one when the scene has it for this ramp, else the
## idle one.
func _strip_for(which: Anim) -> Texture2D:
	var ramp: int = actor.ramp
	var list: Array[Texture2D] = textures
	if which == Anim.WALK:
		list = walk_textures
	elif which == Anim.DASH:
		list = dash_textures
	if ramp >= 0 and ramp < list.size() and list[ramp] != null:
		return list[ramp]
	return textures[ramp] if ramp >= 0 and ramp < textures.size() else null


## Choose the strip (idle, walk, dash) from what the body does, and the frame from the time since
## it started. Changes nothing if the strip is the same.
func _update_animation(delta: float, moving: bool) -> void:
	if _sprite == null:
		return
	var wanted: Anim = Anim.IDLE
	if moving:
		wanted = Anim.DASH
	elif actor.velocity.length() > WALK_THRESHOLD:
		wanted = Anim.WALK
	if wanted != _anim:
		_anim = wanted
		_anim_time = 0.0
		var strip: Texture2D = _strip_for(wanted)
		if strip != null:
			_show_strip(strip)
	else:
		_anim_time += delta
	var fps: float = IDLE_FPS
	if _anim == Anim.WALK:
		fps = WALK_FPS
	elif _anim == Anim.DASH:
		fps = DASH_FPS
	var step_index: int = int(_anim_time * fps)
	if _anim == Anim.DASH:
		_sprite.frame = mini(step_index, _sprite.hframes - 1)
		_set_bob(DASH_BOB[mini(_sprite.frame, DASH_BOB.size() - 1)])
	elif _anim == Anim.WALK:
		_sprite.frame = step_index % _sprite.hframes
		_set_bob(WALK_BOB[_sprite.frame % WALK_BOB.size()])
	else:
		step_index += maxi(actor.ramp, 0) * IDLE_STEP_OFFSET
		var pose: int = IDLE_SEQUENCE[step_index % IDLE_SEQUENCE.size()]
		if _faces_left and pose >= 2:
			pose = 5 - pose
		_sprite.frame = mini(pose, _sprite.hframes - 1)
		_set_bob(1 if step_index % BREATH_STEPS >= BREATH_STEPS / 2 else 0)


## Sit the body `pixels` lower than its place (the hat goes with it), or higher if negative.
func _set_bob(pixels: int) -> void:
	_sprite.offset = Vector2(0.0, float(pixels))
	if _hat != null:
		_hat.position = Vector2(0.0, float(pixels))


## Turn the sprite toward the aim. Flip below -FLIP_BAND, unflip above FLIP_BAND: no flicker
## while the aim wobbles.
func _turn() -> void:
	if actor.aim.x < -FLIP_BAND:
		_faces_left = true
	elif actor.aim.x > FLIP_BAND:
		_faces_left = false
	if _sprite != null:
		_sprite.flip_h = _faces_left
		if _hat != null:
			_hat.flip_h = _faces_left


## Show or hide the invulnerable look when the state changes; while it shows, the closing ring is
## redrawn every step.
func _update_invulnerable_look(down: bool) -> void:
	var now: bool = actor.health != null and actor.health.is_protected() and not down
	if not now and not _invulnerable_look:
		return
	_invulnerable_look = now
	if _sprite != null:
		_sprite.modulate = Color(1.0, 1.0, 1.0, INVULNERABLE_ALPHA if now else 1.0)
	queue_redraw()


## The way of the move in progress (unit length).
func _dash_direction() -> Vector2:
	return actor.mover.move_direction() if actor.mover != null else Vector2.ZERO


## The sprite scale of a dash: stretched along the dominant axis of the dash.
func _dash_scale() -> Vector2:
	var way: Vector2 = _dash_direction()
	if absf(way.x) >= absf(way.y):
		return DASH_STRETCH
	return Vector2(DASH_STRETCH.y, DASH_STRETCH.x)


## Lean in radians, into the dash. A node's rotation is not mirrored by flip_h, so the sign needs
## no care for a sprite that faces left.
func _dash_lean() -> float:
	return clampf(_dash_direction().x, -1.0, 1.0) * DASH_LEAN


## Stretch and lean the sprite along the dash, or put it back when it ends.
func _apply_dash_look(dashing: bool) -> void:
	_dash_look = dashing
	if _sprite != null:
		_sprite.scale = _dash_scale() if dashing else Vector2.ONE
		_sprite.rotation = _dash_lean() if dashing else 0.0
	_pose_ghosts()


## Put the dash ghosts where the wizard was (`_trail`), stretched and leaned like it, or hide them.
func _pose_ghosts() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	if _ghosts.is_empty():
		if not _dash_look:
			return
		_make_ghosts()
	var light: Color = ProjectilesScript.ramp_light(actor.ramp).lerp(Color.WHITE, GHOST_LIGHT)
	for i in _ghosts.size():
		var ghost: Sprite2D = _ghosts[i]
		ghost.visible = _dash_look
		if not _dash_look:
			continue
		ghost.texture = _sprite.texture
		ghost.hframes = _sprite.hframes
		ghost.vframes = _sprite.vframes
		ghost.frame = _sprite.frame
		ghost.offset = _sprite.offset
		ghost.centered = _sprite.centered
		ghost.flip_h = _faces_left
		ghost.position = _sprite.position + _trail[i] - actor.global_position
		ghost.scale = _sprite.scale
		ghost.rotation = _sprite.rotation
		(ghost.material as ShaderMaterial).set_shader_parameter(&"dissolve_color", light)
		var hat := ghost.get_child(0) as Sprite2D
		hat.visible = _hat != null and _hat.texture != null
		if hat.visible:
			hat.texture = _hat.texture
			hat.position = _hat.position
			hat.flip_h = _faces_left
			(hat.material as ShaderMaterial).set_shader_parameter(&"dissolve_color", light)


## The ghost sprites, each with a hat, drawn under the wizard's own sprite.
func _make_ghosts() -> void:
	for i in GHOST_DISSOLVE.size():
		var ghost := Sprite2D.new()
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ghost.material = _ghost_material(GHOST_DISSOLVE[i])
		var hat := Sprite2D.new()
		hat.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		hat.material = _ghost_material(GHOST_DISSOLVE[i])
		ghost.add_child(hat)
		actor.add_child(ghost)
		# Under the wizard: before its sprite among the actor's children.
		actor.move_child(ghost, _sprite.get_index())
		_ghosts.append(ghost)


func _ghost_material(dissolve: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CORE_SHADER
	material.set_shader_parameter(&"core_override", Color.WHITE)
	material.set_shader_parameter(&"dissolve", dissolve)
	material.set_shader_parameter(&"sprite_glow", GHOST_GLOW)
	return material


## Note where the wizard is every GHOST_INTERVAL of the dash (shifts 3 values).
func _tick_trail(delta: float) -> void:
	_trail_timer -= delta
	if _trail_timer > 0.0:
		return
	_trail_timer = GHOST_INTERVAL
	for i in range(_trail.size() - 1, 0, -1):
		_trail[i] = _trail[i - 1]
	_trail[0] = actor.global_position


## A soft shadow under the feet, below the sprite.
func _draw_shadow() -> void:
	_shadow.draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.4))
	_shadow.draw_circle(Vector2.ZERO, 8.0, Color(0, 0, 0, 0.35))
	_shadow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The staff and the aim reticle (a chevron in the ramp's colour with an outline), the protect
## ring, or the revive ring while down. No arrays are made: lines only.
func _draw() -> void:
	if actor == null:
		return
	if actor.is_down():
		_draw_revive_ring()
		return
	if actor.aim == Vector2.ZERO:
		return
	_draw_invulnerable_ring()
	_draw_staff()
	var aim: Vector2 = actor.aim
	var tip: Vector2 = reticle_position() - actor.global_position
	var side: Vector2 = aim.orthogonal()
	var back: Vector2 = tip - aim * RETICLE_SIZE
	var color: Color = light_color()
	draw_line(back + side * RETICLE_SIZE, tip, OUTLINE_COLOR, 3.0)
	draw_line(back - side * RETICLE_SIZE, tip, OUTLINE_COLOR, 3.0)
	draw_line(back + side * RETICLE_SIZE, tip, color, 1.0)
	draw_line(back - side * RETICLE_SIZE, tip, color, 1.0)


## A ring round the body that closes as the protected time runs out.
func _draw_invulnerable_ring() -> void:
	if not _invulnerable_look:
		return
	var left: float = clampf(actor.health.protect_left() / INVULNERABLE_TIME, 0.0, 1.0)
	var centre: Vector2 = Vector2(0.0, -INVULNERABLE_RING_HEIGHT)
	var end: float = -PI * 0.5 + TAU * left
	draw_arc(centre, INVULNERABLE_RING_RADIUS, -PI * 0.5, end, 24, OUTLINE_COLOR, 4.0)
	draw_arc(centre, INVULNERABLE_RING_RADIUS, -PI * 0.5, end, 24, light_color(), 2.0)


## The revive ring over a downed wizard: a dark ring with an arc that sweeps round clockwise from
## the top as the hold goes on, so the progress reads from the length, not the colour. A small
## cross in the middle marks it as a revive.
func _draw_revive_ring() -> void:
	var centre := Vector2(0.0, -REVIVE_RING_HEIGHT)
	var progress: float = _downed.revive_progress() if _downed != null else 0.0
	draw_arc(centre, REVIVE_RING_RADIUS, 0.0, TAU, 24, OUTLINE_COLOR, 4.0)
	draw_arc(centre, REVIVE_RING_RADIUS, 0.0, TAU, 24, REVIVE_RING_BACK, 2.0)
	if progress > 0.0:
		draw_arc(centre, REVIVE_RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * progress, 24, light_color(), 2.0)
	draw_line(centre + Vector2(-2, 0), centre + Vector2(2, 0), OUTLINE_COLOR, 3.0)
	draw_line(centre + Vector2(0, -2), centre + Vector2(0, 2), OUTLINE_COLOR, 3.0)
	draw_line(centre + Vector2(-2, 0), centre + Vector2(2, 0), Color.WHITE, 1.0)
	draw_line(centre + Vector2(0, -2), centre + Vector2(0, 2), Color.WHITE, 1.0)


## The staff: the staff art turned along the aim with the hand on the wizard (a plain line without
## the art), and a gem in the ramp's colour at the tip.
func _draw_staff() -> void:
	# The same points the shot uses, in this node's space (the actor's).
	var aim: Vector2 = actor.aim
	var hand: Vector2 = actor.aim_pivot() - actor.global_position
	var tip: Vector2 = actor.muzzle_position() - actor.global_position
	if staff_texture != null:
		# Aiming left the art is also flipped, so its lit side stays on top.
		var flip: float = -1.0 if aim.x < 0.0 else 1.0
		draw_set_transform(hand, aim.angle(), Vector2(1.0, flip))
		draw_texture(staff_texture, -STAFF_PIVOT)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_line(hand, tip, OUTLINE_COLOR, 3.0)
		draw_line(hand, tip, Color("8a5a44"), 1.0)
		draw_circle(tip, 2.5, OUTLINE_COLOR)
	draw_circle(tip, 1.5, light_color())
