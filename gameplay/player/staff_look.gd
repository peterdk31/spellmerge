class_name StaffLook
extends ActorLook
## A player's look (living staffs H3, docs/milestones/M2-living-staffs.md, "The player"): the
## floating staff. It reads the actor and draws; it changes nothing the game plays by.
##
## The body is the scene's `Sprite` (Feel and Entities find it by that name): the head sheet of
## the staff on show (`Caster.current`, its `StaffBase.head`; `default_head` for a staff without
## one), a frame per direction (DIRECTIONS, clockwise from pointing right, the nearest to the aim)
## and a row per ramp (the player colour is on the head only). The frame's grip (GRIP) sits on the
## actor's hand (`Actor.hand_offset`), so the shot leaves where the drawn staff points; the head's
## tip is the staff's `tip` (`Actor.reach`). There are no walk frames: the staff hovers with a bob
## of HOVER_BOB px (each ramp a little further on, so a group does not bob together), and the
## shadow stays on the floor. Down, it lies flat on the floor (DOWN_LIFT above the feet, pointing
## the way it faced); a friend stands it back up.
##
## The face (`Face`, the actor's child of that kind) is told where the body is each step
## (`Face.body_offset`, before the face steps: this look comes first among the actor's children)
## and takes the personality of the staff on show (`face_style`, `resting_mood`).
##
## The poof (living staffs H4): when another staff goes on show (`Caster.current` changes; the
## cast has already left from the new tip), Feel draws a cloud over the staff (`staff_shown`) and
## the body and face stay as they were until SWAP_AT of POOF_TIME, when the cloud is biggest; then
## both change and the brows lift (`Face.show_mood`, RAISED for BROW_LIFT). Each press of another
## staff starts the poof again, so the change is at the newest cloud's biggest. The same staff
## again changes nothing.
##
## A dash, hook or swap stretches and leans the sprite along its way (`Mover.move_direction`; a
## standing actor dashes the way it aims) and leaves three ghosts where the staff was: solid copies
## drawn by the shot shader (the glow look, 2026-10-27), turned to the ramp's light colour and
## falling apart pixel by pixel, the older the more (GHOST_DISSOLVE), never see-through.
##
## Drawn by this node: the aim reticle (a chevron), the closing ring while the actor cannot be hurt
## (`Health.protect`, with the body and face 55% opaque) and, while it is down, only the revive
## ring (`Downed.revive_progress`: an arc sweeping clockwise from the top, a cross in the middle).
## Colours are the ramp's light shade (the projectile manager's `ramp_light`, docs/STYLE.md).
##
## It redraws only when something drawn changed. Nothing here allocates per step (the ghosts are
## made the first time they are needed).

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## The head sheets: 48x48 frames, DIRECTIONS columns, one row per ramp (0-3), the grip at GRIP.
const FRAME_SIZE: int = 48
const DIRECTIONS: int = 16
const RAMPS: int = 4
const GRIP: Vector2 = Vector2(24.0, 27.0)
## The hover: the body rises and sinks by up to HOVER_BOB px, HOVER_RATE radians a second; each
## ramp starts HOVER_PHASE radians further on.
const HOVER_BOB: float = 1.2
const HOVER_RATE: float = 2.5
const HOVER_PHASE: float = 1.7
## The poof: its seconds, the part of them at which body and face change, and how long the
## brows stay lifted after.
const POOF_TIME: float = 0.18
const SWAP_AT: float = 0.35
const BROW_LIFT: float = 0.25
## Down, the grip lies this many pixels above the feet.
const DOWN_LIFT: float = 3.0
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
## The protect ring closes over this many seconds at most (it shows how much is left); the
## body's opacity and the ring's size while it shows.
const INVULNERABLE_TIME: float = 2.0
const INVULNERABLE_ALPHA: float = 0.55
const INVULNERABLE_RING_RADIUS: float = 15.0
const INVULNERABLE_RING_HEIGHT: float = 14.0
## The revive ring over a downed staff: radius, the height of its centre above the feet and the
## colour of its empty track.
const REVIVE_RING_RADIUS: float = 7.0
const REVIVE_RING_HEIGHT: float = 24.0
const REVIVE_RING_BACK: Color = Color("5a5a6e")
const OUTLINE_COLOR: Color = Color("14121f")
## How far toward white the ghosts go from the ramp's light shade.
const GHOST_LIGHT: float = 0.4

## The head of a staff that has none (`StaffBase.head` empty), in the same sheet layout.
@export var default_head: Texture2D = null

## The `Sprite` node (null without one) and the actor's Face (null without one).
var _sprite: Sprite2D = null
var _face: Face = null
## The actor's Downed component (null without one).
var _downed: Downed = null
## The shadow, drawn under the sprite.
var _shadow: Node2D = null
## The staff whose head and personality show (-1 before the first step), and the time hovered.
var _shown: int = -1
var _time: float = 0.0
## Seconds into the poof (-1: none), and the staff it swaps to (the staff on show).
var _poof_age: float = -1.0
var _target: int = -1
var _faces_left: bool = false
## True while the dash look is applied (to reset it once when the move ends).
var _dash_look: bool = false
## Where the staff was at the last ghost ticks of the dash (newest first; a fixed array, only
## overwritten), and the time to the next tick.
var _trail: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _trail_timer: float = 0.0
## The dash ghosts (sprites made the first time they are needed), newest first.
var _ghosts: Array[Sprite2D] = []
## True while the invulnerable look (translucent body and ring) is shown.
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
	for child in actor.get_children():
		if child is Face:
			_face = child as Face
			break
	if _sprite != null:
		_sprite.centered = true
		# The frame's grip on the node's origin.
		_sprite.offset = Vector2(FRAME_SIZE, FRAME_SIZE) * 0.5 - GRIP
	if _shadow == null:
		_shadow = Node2D.new()
		_shadow.name = "Shadow"
		_shadow.draw.connect(_draw_shadow)
		actor.add_child(_shadow)
		actor.move_child(_shadow, _sprite.get_index() if _sprite != null else 0)
	_shown = -1
	_poof_age = -1.0
	_target = actor.caster.current if actor.caster != null else 0
	_show_staff(_target)
	_place_body(0.0)


func step(delta: float) -> void:
	_time += delta
	var down: bool = actor.is_down()
	var moving: bool = not down and actor.mover != null and actor.mover.is_moving()
	if moving and not _dash_look:
		# The ghosts start on the staff and grow out behind as the move goes on.
		_trail.fill(actor.global_position)
		_trail_timer = GHOST_INTERVAL
	elif _dash_look:
		_tick_trail(delta)
	_step_poof(delta)
	_place_body(_time)
	if moving or _dash_look:
		_apply_dash_look(moving)
	_update_invulnerable_look(down)
	var progress: float = _downed.revive_progress() if _downed != null else 0.0
	if not actor.aim.is_equal_approx(_drawn_aim) or down != _drawn_down or progress != _drawn_progress:
		_drawn_aim = actor.aim
		_drawn_down = down
		_drawn_progress = progress
		queue_redraw()


## The staff (button) whose head shows, -1 before the first step.
func shown_staff() -> int:
	return _shown


## True while a poof is hiding a swap (before and after the body changes).
func is_poofing() -> bool:
	return _poof_age >= 0.0


## The column of the head sheet that shows: the direction nearest the aim (down: flat, the way
## the staff faced).
func direction() -> int:
	if actor.is_down():
		return DIRECTIONS / 2 if _faces_left else 0
	return direction_of(actor.aim)


## The column for a direction (0 pointing right, clockwise on screen).
static func direction_of(aim: Vector2) -> int:
	return posmod(roundi(aim.angle() / (TAU / DIRECTIONS)), DIRECTIONS)


## True while the dash look (stretch, lean, ghosts) is on.
func is_dash_look() -> bool:
	return _dash_look


## True while the invulnerable look (translucent body and ring) is on.
func is_invulnerable_look() -> bool:
	return _invulnerable_look


## The ghost sprites (empty until the first dash), newest first.
func ghosts() -> Array[Sprite2D]:
	return _ghosts


## Where the reticle's point is drawn, on the line of the shot.
func reticle_position() -> Vector2:
	return actor.aim_pivot() + actor.aim * RETICLE_DISTANCE


## The light shade of the actor's ramp (the reticle, the rings).
func light_color() -> Color:
	return ProjectilesScript.ramp_light(actor.ramp)


## A new staff on show starts a poof (each press of another staff its own, as Feel's clouds); at
## SWAP_AT of it the body and face change, at its end it is over.
func _step_poof(delta: float) -> void:
	var wanted: int = actor.caster.current if actor.caster != null else 0
	if wanted != _target:
		_target = wanted
		_poof_age = 0.0 if wanted != _shown else -1.0
	elif _poof_age >= 0.0:
		_poof_age += delta
	if _poof_age < 0.0:
		return
	if _poof_age >= POOF_TIME * SWAP_AT and _target != _shown:
		_show_staff(_target)
		if _face != null:
			_face.show_mood(Face.Mood.RAISED, BROW_LIFT)
	if _poof_age >= POOF_TIME:
		_poof_age = -1.0


## Show staff `at`'s head and personality.
func _show_staff(at: int) -> void:
	_shown = at
	var staff: StaffBase = actor.caster.staff_of(at) if actor.caster != null else null
	var head: Texture2D = staff.head if staff != null and staff.head != null else default_head
	if _sprite != null and head != null:
		_sprite.texture = head
		_sprite.hframes = DIRECTIONS
		_sprite.vframes = RAMPS
	if _face != null and staff != null:
		_face.style = staff.face_style as Face.Style
		_face.resting_mood = staff.resting_mood as Face.Mood


## The body on the hand (hovering), or flat on the floor while down, with the frame for the aim;
## the face told where it went.
func _place_body(time: float) -> void:
	if actor.aim.x < -0.01:
		_faces_left = true
	elif actor.aim.x > 0.01:
		_faces_left = false
	var at: Vector2 = Vector2(0.0, -DOWN_LIFT)
	if not actor.is_down():
		var phase: float = time * HOVER_RATE + float(maxi(actor.ramp, 0)) * HOVER_PHASE
		at = actor.hand_offset + Vector2(0.0, roundf(sin(phase) * HOVER_BOB))
	if _sprite != null:
		_sprite.position = at
		if _sprite.texture != null:
			_sprite.frame_coords = Vector2i(direction(), clampi(actor.ramp, 0, RAMPS - 1))
	if _face != null:
		_face.body_offset = at - actor.hand_offset


## Show or hide the invulnerable look when the state changes; while it shows, the closing ring is
## redrawn every step.
func _update_invulnerable_look(down: bool) -> void:
	var now: bool = actor.health != null and actor.health.is_protected() and not down
	if not now and not _invulnerable_look:
		return
	_invulnerable_look = now
	var tint := Color(1.0, 1.0, 1.0, INVULNERABLE_ALPHA if now else 1.0)
	if _sprite != null:
		_sprite.modulate = tint
	if _face != null:
		_face.modulate = tint
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


## Lean in radians, into the dash.
func _dash_lean() -> float:
	return clampf(_dash_direction().x, -1.0, 1.0) * DASH_LEAN


## Stretch and lean the sprite along the dash, or put it back when it ends.
func _apply_dash_look(dashing: bool) -> void:
	_dash_look = dashing
	if _sprite != null:
		_sprite.scale = _dash_scale() if dashing else Vector2.ONE
		_sprite.rotation = _dash_lean() if dashing else 0.0
	_pose_ghosts()


## Put the dash ghosts where the staff was (`_trail`), stretched and leaned like it, or hide them.
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
		ghost.position = _sprite.position + _trail[i] - actor.global_position
		ghost.scale = _sprite.scale
		ghost.rotation = _sprite.rotation
		(ghost.material as ShaderMaterial).set_shader_parameter(&"dissolve_color", light)


## The ghost sprites, drawn under the staff's own sprite.
func _make_ghosts() -> void:
	for i in GHOST_DISSOLVE.size():
		var ghost := Sprite2D.new()
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ghost.material = _ghost_material(GHOST_DISSOLVE[i])
		actor.add_child(ghost)
		# Under the staff: before its sprite among the actor's children.
		actor.move_child(ghost, _sprite.get_index())
		_ghosts.append(ghost)


func _ghost_material(dissolve: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CORE_SHADER
	material.set_shader_parameter(&"core_override", Color.WHITE)
	material.set_shader_parameter(&"dissolve", dissolve)
	material.set_shader_parameter(&"sprite_glow", GHOST_GLOW)
	return material


## Note where the staff is every GHOST_INTERVAL of the dash (shifts 3 values).
func _tick_trail(delta: float) -> void:
	_trail_timer -= delta
	if _trail_timer > 0.0:
		return
	_trail_timer = GHOST_INTERVAL
	for i in range(_trail.size() - 1, 0, -1):
		_trail[i] = _trail[i - 1]
	_trail[0] = actor.global_position


## A soft shadow on the floor under the staff, below the sprite.
func _draw_shadow() -> void:
	_shadow.draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.4))
	_shadow.draw_circle(Vector2.ZERO, 7.0, Color(0, 0, 0, 0.35))
	_shadow.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The aim reticle (a chevron in the ramp's colour with an outline) and the protect ring, or the
## revive ring while down. No arrays are made: lines only.
func _draw() -> void:
	if actor == null:
		return
	if actor.is_down():
		_draw_revive_ring()
		return
	if actor.aim == Vector2.ZERO:
		return
	_draw_invulnerable_ring()
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


## The revive ring over a downed staff: a dark ring with an arc that sweeps round clockwise from
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
