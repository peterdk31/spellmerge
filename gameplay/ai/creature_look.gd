class_name CreatureLook
extends ActorLook
## How a creature looks (actors G6, docs/milestones/M2-actors.md, "The components"): the poses
## and the flash of an enemy actor (content/enemies/ember_imp/ember_imp.tscn). It
## reads the actor and the AI driving it and draws; it changes nothing the game plays by. All of
## an enemy's drawing is here, none in the AI (a straight port of what ai.gd drew before G6).
##
## It draws with two nodes of the actor's scene: `sprite` (the body, named "Sprite": Feel and
## Entities find it by that name) and `animation` (the idle animation). Left empty, each is the
## actor's child of that name ("Sprite", "AnimationPlayer"); neither is required.
##
## Telegraph: while the AI driving the actor winds up (`AIController.is_telegraphing`: an enemy's
## cast winding up), the sprite flashes (`modulate`), brighter for the last part. The lane along
## the aim is the cast card's `wind_cue`, which Feel plays (`lane` cue part; docs/milestones/
## cast-timing.md, T6b). An actor driven by a seat (possess, G9) shows none: a human casts when
## they like.
##
## Poses: with `windup_texture` set (a strip of 32 px frames), the sprite shows it from the start
## of the windup and flips between its frames faster and faster (WINDUP_FLASHES), and goes
## brighter still for the last stretch (TELEGRAPH_LAST_FROM). With `hurt_texture` set, a hit on
## the actor (its `Actor.damaged`, sent with each `damage_dealt` naming it; a burn tick that does
## not kill sends none, so a burning enemy does not flinch twice a second) shows it for HURT_TIME
## seconds, over the windup too. A hit never cancels the windup: the shot still comes, so the
## telegraph stays honest (knockback and Feel's flash and squash are Combat's and Feel's). The
## animation is paused while a pose other than the idle shows.
##
## Hop (living staffs H5, docs/milestones/M2-living-staffs.md, "The strays"): a stray moves on its
## tip, so while it walks (faster than HOP_SPEED) the sprite hops HOP_HEIGHT px HOP_RATE times a
## second, and while it stands it bobs HOP_IDLE px; players float, so the two sides read apart by
## motion alone. The hop is the sprite's `offset` only (the telegraph and the hurt circle stay).
## The actor's `Face` (its child of that kind, stepped after this look) is told the same lift
## (`Face.body_offset`), so its eyes and brows trail the hop.
##
## Poses from states and layered bodies (boss plan OB8, docs/milestones/boss-old-broom.md, "Poses and
## layered bodies"): every step it reads what the body is doing (`BodyPose`: TRANSITION through a
## boss's phase change (its AI's TRANSITION), WALL as its own move meets a wall, HURT, WINDUP while
## it telegraphs, MOVE while its own move carries it, CAST while its staff animation plays, else
## IDLE), from states the game already has, so the pose is the same on every machine; only a layered
## body reads it. A layered body is drawn in parts, the `BodyPart`s under its `Sprite` (which shows
## no art then: the strips and a phase's body sprite are a body of one sprite's): each
## step every part is drawn by that pose and motion (its lean, lag, swish, squash, sway, wall squash,
## shudder and pose frames), at `full_speed` px/s whole; the part that `carries_face` takes the
## actor's `Face` with it. A layered body's lift (the hop or the bob) moves its `Sprite`, and with it
## every part. `hops` false: it never hops, only bobs (a body that hovers).
##
## Phases (enemy AI AI7): a boss's phase look (`PhaseLook`) brings its body sprite, its parts' art by
## name (`parts`) and motes that follow the body (`motes`, from the part `motes_on`: a node it adds
## there, `MoteSource.put` with `follow`; a later phase's replace them, none keeps them). After a
## snapshot (`sync`) the look shows the phase the body is in.
##
## Nothing here allocates per frame, and a step sets nothing on the nodes that did not change:
## the sprite's pose only when it changes, the hop's lift only when it moves a whole pixel
## (performance pass, 2026-10-28).

enum Pose { IDLE, WINDUP, HURT }

## `sprite` modulate while the telegraph shows, and for its last part.
const TELEGRAPH_COLOR: Color = Color(1.6, 1.3, 1.3)
const TELEGRAPH_COLOR_LAST: Color = Color(2.0, 1.8, 1.5)
## Where the last part of the windup starts (0..1 progress): from here the sprite is drawn in
## TELEGRAPH_COLOR_LAST and holds its bright frame instead of flipping.
const TELEGRAPH_LAST_FROM: float = 0.8
## Windup frame flips before the last part: frame = floor(progress² × this) mod frames, so it
## starts slow and speeds up, to about 5 bright-dark cycles a second at most.
const WINDUP_FLASHES: float = 5.0
## Seconds the hurt pose shows after a hit.
const HURT_TIME: float = 0.25
## The hop: pixels high, hops a second, the speed (px/s) from which it hops, and the bob standing.
const HOP_HEIGHT: float = 3.0
const HOP_RATE: float = 2.5
const HOP_SPEED: float = 5.0
const HOP_IDLE: float = 1.0

## Optional poses for the sprite: strips of square frames (width / height frames).
@export var windup_texture: Texture2D = null
@export var hurt_texture: Texture2D = null
## The nodes it draws with (see the class doc); empty: the actor's child of that name.
@export var sprite: Sprite2D = null
@export var animation: AnimationPlayer = null
## The speed (px/s) at which a layered body's parts move whole (a part's lean, lag, swish, squash).
@export var full_speed: float = 120.0
## False: it never hops, only bobs, walking or standing (a body that hovers).
@export var hops: bool = true

var _idle_texture: Texture2D = null
## The body sprite as the scene made it (a snapshot's phase is shown from it again).
var _scene_texture: Texture2D = null
var _idle_hframes: int = 1
## Seconds the hurt pose still shows.
var _hurt_left: float = 0.0
## The pose now on the sprite.
var _pose: Pose = Pose.IDLE
## True while the telegraph (and the flash) is up.
var _showing: bool = false
## The actor's Face (null without one), the sprite's own offset, and the time hopped.
var _face: Face = null
var _sprite_offset: Vector2 = Vector2.ZERO
var _hop_time: float = 0.0
var _lift: Vector2 = Vector2.ZERO
## The controller driving the actor at the last step, and the same as an AI (or null).
var _driver: ActorController = null
var _ai: AIController = null
## What the body is doing (OB8), its layered body's parts (empty: one sprite), the part the face
## rides and the inverse of its rest in the actor's frame, and the sprite's own place.
var _body: BodyPose = BodyPose.new()
var _parts: Array[BodyPart] = []
var _face_part: BodyPart = null
var _face_rest: Transform2D = Transform2D.IDENTITY
var _sprite_position: Vector2 = Vector2.ZERO
## The parts' art as the scene made it (by part), for a snapshot's phase to be shown again, and the
## node giving off the phase's motes (null for none).
var _part_art: Dictionary = {}
var _phase_motes: Node2D = null


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	if sprite == null:
		sprite = actor.get_node_or_null(^"Sprite") as Sprite2D
	if animation == null:
		animation = actor.get_node_or_null(^"AnimationPlayer") as AnimationPlayer
	if sprite != null:
		_idle_texture = sprite.texture
		_scene_texture = sprite.texture
		_idle_hframes = sprite.hframes
		_sprite_offset = sprite.offset
		_sprite_position = sprite.position
		_parts.clear()
		BodyPart.parts_of(sprite, _parts)
		# At its art's size in the world (a body drawn at 2x detail at half: ArtDetail); the
		# textures it swaps to are its own kind's, drawn as finely.
		ArtDetail.fit(sprite)
	for child in actor.get_children():
		if child is Face:
			_face = child as Face
			break
	for part in _parts:
		part.take_rest()
		_part_art[part] = part.texture
		if part.carries_face and _face_part == null:
			_face_part = part
	if _face_part != null:
		_face_rest = _in_actor(_face_part).affine_inverse()
	_put_on_page()
	# Connected once, on its own actor (not the bus, where a listener per enemy was called for
	# every hit on anyone).
	if not actor.damaged.is_connected(_on_damaged):
		actor.damaged.connect(_on_damaged)
	# A boss's phase may bring another body sprite (enemy AI AI7).
	if actor.phases != null and not actor.phases.started.is_connected(_on_phase_started):
		actor.phases.started.connect(_on_phase_started)


## A body of one sprite wearing the shared face puts its art and its face's sheets on one page, its
## kind's (`TexturePage`), so the body and the face are one draw call and a crowd of its kind one too
## (the owner's choice of 2026-11-21, after #900). Its poses' strips go on the page as well; a
## layered body, a boss's phases or a face of its own keep their art.
func _put_on_page() -> void:
	if sprite == null or sprite.texture == null or not _parts.is_empty() or _face == null or _face.art != null or actor.phases != null:
		return
	var paged: Array[Texture2D] = TexturePage.regions_of([_scene_texture, windup_texture, hurt_texture, Face.EYES_SHEET, Face.BROWS_SHEET] as Array[Texture2D])
	if paged.size() != 5 or not (paged[0] is AtlasTexture):
		return
	if sprite.texture == _idle_texture:
		sprite.texture = paged[0]
	_idle_texture = paged[0]
	_scene_texture = paged[0]
	windup_texture = paged[1]
	hurt_texture = paged[2]
	_face.wear_sheets(paged[3], paged[4])


## Draw the actor after this step: the telegraph and flash from its AI's windup, then the pose.
func step(delta: float) -> void:
	if actor.controller != _driver:
		_driver = actor.controller
		_ai = _driver as AIController
	var ai: AIController = _ai
	var telegraphing: bool = ai != null and ai.is_telegraphing()
	if telegraphing != _showing:
		_show_telegraph(telegraphing, ai)
	elif telegraphing:
		_update_telegraph(ai.telegraph_progress())
	if _hurt_left > 0.0:
		_hurt_left = maxf(_hurt_left - delta, 0.0)
		# A hurt pose that goes on changes nothing on the sprite.
		if _hurt_left <= 0.0 or _pose != Pose.HURT:
			_update_sprite()
	elif _pose != Pose.IDLE or _showing:
		# Idle with nothing showing changes nothing either.
		_update_sprite()
	# The staff animation's aim, read once for the step (each read walks its table).
	var dir: Vector2 = pose_dir()
	if not _parts.is_empty():
		# Only a layered body draws its pose (a body of one sprite has its strips above).
		var transition: bool = ai != null and ai.brain.state == AIBrain.State.TRANSITION
		_body.step(actor, delta, full_speed, telegraphing, transition, is_hurt(), dir)
		for part in _parts:
			part.show_pose(_body)
	_hop(delta, dir)


## The pose a layered body shows now (`BodyPose.Pose`; IDLE for a body of one sprite, which reads
## none), and what it is doing (for tests).
func body_pose() -> BodyPose.Pose:
	return _body.pose


func body() -> BodyPose:
	return _body


## The parts of its layered body (empty: one sprite).
func parts() -> Array[BodyPart]:
	return _parts


## Show the phase the body is in after a snapshot gave it its state back (its looks and its face's,
## from the scene's on), and forget where the body was.
func sync() -> void:
	_body.forget()
	_idle_texture = _scene_texture
	if sprite != null and _pose == Pose.IDLE and _parts.is_empty():
		sprite.texture = _idle_texture
	for part in _parts:
		part.texture = _part_art.get(part, part.texture) as Texture2D
	_drop_phase_motes()
	if _face != null:
		_face.unstyle()
	if actor.phases == null:
		return
	for index in actor.phases.current + 1:
		if index >= 0 and index < actor.phases.list.size() and actor.phases.list[index] != null:
			var phase: EnemyPhase = actor.phases.list[index]
			_show_phase(phase)
			if _face != null and phase.look != null:
				_face.restyle(phase.look.face_style, phase.look.glow, phase.look.face_row)


## How high the body is off its rest this step (px, up is positive), for tests.
func lift() -> float:
	return -_lift.y


## The hop while walking, the bob while standing, and its cast's staff animation, on the sprite and
## the face; `dir` is the staff animation's aim this step (`pose_dir`).
func _hop(delta: float, dir: Vector2) -> void:
	_hop_time += delta
	var walking: bool = hops and actor.velocity.length_squared() > HOP_SPEED * HOP_SPEED
	var up: float = 0.0
	if walking:
		up = roundf(absf(sin(_hop_time * HOP_RATE * PI)) * HOP_HEIGHT)
	else:
		up = roundf((sin(_hop_time * HOP_RATE) * 0.5 + 0.5) * HOP_IDLE)
	# The staff animation of its cast (ActorLook's pose: lift, push, shake) on top.
	var at: Vector2 = Vector2(0.0, -up) + show_pose(sprite, _face, false, _hop_time, dir)
	if at != _lift:
		# Whole pixels: most steps the body is where it was.
		_lift = at
		if sprite != null and not _parts.is_empty():
			# A layered body lifts as a whole: its parts ride its sprite.
			sprite.position = _sprite_position + _lift
		elif sprite != null:
			sprite.offset = _sprite_offset + _lift
		if _face != null and _face_part == null:
			_face.body_offset = _lift
	if _face != null and _face_part != null:
		# The face rides its part (its lift too, through the sprite it hangs from).
		var anchor: Vector2 = _face.position + _face.anchor
		var shown: Vector2 = (_in_actor(_face_part) * (_face_rest * anchor) - anchor).round()
		if _face.body_offset != shown:
			_face.body_offset = shown


## `node`'s transform in the actor's frame.
func _in_actor(node: Node2D) -> Transform2D:
	return actor.global_transform.affine_inverse() * node.global_transform



## True while the hurt pose shows (a hit landed in the last HURT_TIME seconds).
func is_hurt() -> bool:
	return _hurt_left > 0.0


func _show_telegraph(on: bool, ai: AIController) -> void:
	_showing = on
	if on:
		_update_telegraph(ai.telegraph_progress())
	elif sprite != null:
		sprite.modulate = Color.WHITE


## Make the sprite brighter as the cast gets closer (the lane is Feel's: the card's `wind_cue`).
func _update_telegraph(progress: float) -> void:
	if sprite != null:
		sprite.modulate = TELEGRAPH_COLOR_LAST if progress >= TELEGRAPH_LAST_FROM else TELEGRAPH_COLOR


## Which pose the sprite shows: the hurt one over the windup one over the idle strip. A pose
## without its texture is skipped.
func _update_sprite() -> void:
	# A layered body's sprite shows no art: its parts have the poses' frames.
	if sprite == null or not _parts.is_empty():
		return
	var pose: Pose = Pose.IDLE
	if _hurt_left > 0.0 and hurt_texture != null:
		pose = Pose.HURT
	elif _showing and windup_texture != null:
		pose = Pose.WINDUP
	if pose != _pose:
		_pose = pose
		match pose:
			Pose.HURT:
				_show_strip(hurt_texture)
			Pose.WINDUP:
				_show_strip(windup_texture)
			_:
				sprite.hframes = _idle_hframes
				sprite.texture = _idle_texture
				if animation != null and animation.is_inside_tree():
					animation.play()
	if pose == Pose.WINDUP:
		var ai: AIController = actor.controller as AIController
		var progress: float = ai.telegraph_progress() if ai != null else 0.0
		if progress >= TELEGRAPH_LAST_FROM:
			sprite.frame = sprite.hframes - 1
		else:
			sprite.frame = int(progress * progress * WINDUP_FLASHES) % sprite.hframes


## Show a strip of square frames on the sprite and stop the idle animation.
func _show_strip(strip: Texture2D) -> void:
	sprite.hframes = maxi(roundi(float(strip.get_width()) / maxf(float(strip.get_height()), 1.0)), 1)
	sprite.texture = strip
	sprite.frame = 0
	if animation != null and animation.is_inside_tree():
		animation.pause()


## A boss's phase began: its look's body sprite, parts' art and motes (see the class doc).
func _on_phase_started(_index: int, phase: EnemyPhase) -> void:
	_show_phase(phase)


func _show_phase(phase: EnemyPhase) -> void:
	var look: PhaseLook = phase.look
	if look == null or sprite == null:
		return
	if look.texture != null and _parts.is_empty():
		_idle_texture = look.texture
		if _pose == Pose.IDLE:
			sprite.texture = _idle_texture
	for part in _parts:
		var art: Texture2D = look.parts.get(StringName(part.name)) as Texture2D
		if art != null:
			part.texture = art
	if look.motes != null:
		_drop_phase_motes()
		var on: Sprite2D = sprite
		for part in _parts:
			if look.motes_on != &"" and StringName(part.name) == look.motes_on:
				on = part
				break
		_phase_motes = Node2D.new()
		_phase_motes.name = "PhaseMotes"
		# Its art (a mask's, else the colours it names none of) is the part it comes off.
		MoteSource.put(_phase_motes, look.motes, NodePath(".."), true)
		on.add_child(_phase_motes)


## The phase's motes stop: their node goes.
func _drop_phase_motes() -> void:
	if _phase_motes == null:
		return
	if is_instance_valid(_phase_motes):
		var parent: Node = _phase_motes.get_parent()
		if parent != null:
			parent.remove_child(_phase_motes)
		_phase_motes.free()
	_phase_motes = null


## The node giving off the phase's motes now (null for none), for tests.
func phase_motes() -> Node2D:
	return _phase_motes


## A hit on the actor shows the hurt pose at once.
func _on_damaged(_by: int, _amount: float, _element: StringName) -> void:
	_hurt_left = HURT_TIME
	_update_sprite()
