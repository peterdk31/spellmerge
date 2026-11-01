class_name CreatureLook
extends ActorLook
## How a creature looks (actors G6, docs/milestones/M2-actors.md, "The components"): the poses,
## the flash and the telegraph of an enemy actor (content/enemies/ember_imp/ember_imp.tscn). It
## reads the actor and the AI driving it and draws; it changes nothing the game plays by. All of
## an enemy's drawing is here, none in the AI (a straight port of what ai.gd drew before G6).
##
## It draws with three nodes of the actor's scene: `sprite` (the body, named "Sprite": Feel and
## Entities find it by that name), `telegraph` (a Sprite2D drawn by `telegraph.gdshader` in this
## folder, its material local to the scene) and `animation` (the idle animation). Left empty,
## each is the actor's child of that name ("Sprite", "Telegraph", "AnimationPlayer"); none is
## required.
##
## Telegraph: while the AI driving the actor winds up (`AIController.is_telegraphing`), the
## sprite flashes (`modulate`) and the telegraph turns toward the locked aim and shows. It runs
## from TELEGRAPH_START to the real reach of the next cast (`Caster.next_cast_reach`), its lane as
## wide as what is coming plus a margin, and its dashes march, its arrowhead grows and it
## brightens with `telegraph_progress()`. A cast that is not aimed (a nova, an orbit) shows only
## the pose and the flash. An actor driven by a seat (possess, G9) shows no telegraph: a human
## casts when they like.
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
## Nothing here allocates per frame, and a step sets nothing on the nodes that did not change:
## the sprite's pose only when it changes, the hop's lift only when it moves a whole pixel
## (performance pass, 2026-10-28).

enum Pose { IDLE, WINDUP, HURT }

## The telegraph line starts this far from the hand (where the cast leaves).
const TELEGRAPH_START: float = 10.0
## The telegraph's lane is the hit width of what is coming plus this margin.
const TELEGRAPH_LANE_MARGIN: float = 8.0
## The telegraph sprite's region height (its texture's), with the lane in its middle.
const TELEGRAPH_HEIGHT: float = 32.0
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
@export var telegraph: Sprite2D = null
@export var animation: AnimationPlayer = null

var _idle_texture: Texture2D = null
var _idle_hframes: int = 1
## Seconds the hurt pose still shows.
var _hurt_left: float = 0.0
## The pose now on the sprite.
var _pose: Pose = Pose.IDLE
## True while the telegraph (and the flash) is up.
var _showing: bool = false
## The sandbox's "AI view" (enemy AI AI8, `ai_view_changed`, set by Entities): every enemy shows
## its AI's behaviour and step over its head, for tuning a profile in the enemy arena.
static var ai_view: bool = false
## The words over its head while `ai_view` is on (made the first time), and what they said.
var _ai_label: Label = null
var _ai_words: String = ""
## The actor's Face (null without one), the sprite's own offset, and the time hopped.
var _face: Face = null
var _sprite_offset: Vector2 = Vector2.ZERO
var _hop_time: float = 0.0
var _lift: Vector2 = Vector2.ZERO
## The controller driving the actor at the last step, and the same as an AI (or null).
var _driver: ActorController = null
var _ai: AIController = null


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	if sprite == null:
		sprite = actor.get_node_or_null(^"Sprite") as Sprite2D
	if telegraph == null:
		telegraph = actor.get_node_or_null(^"Telegraph") as Sprite2D
	if animation == null:
		animation = actor.get_node_or_null(^"AnimationPlayer") as AnimationPlayer
	if sprite != null:
		_idle_texture = sprite.texture
		_idle_hframes = sprite.hframes
		_sprite_offset = sprite.offset
	for child in actor.get_children():
		if child is Face:
			_face = child as Face
			break
	if telegraph != null:
		telegraph.visible = false
		# Starts where the cast does (the hand; an imp's is its body), whatever the scene says.
		telegraph.position = actor.hand_offset
		telegraph.centered = false
		telegraph.region_enabled = true
	# Connected once, on its own actor (not the bus, where a listener per enemy was called for
	# every hit on anyone).
	if not actor.damaged.is_connected(_on_damaged):
		actor.damaged.connect(_on_damaged)
	# A boss's phase may bring another body sprite (enemy AI AI7).
	if actor.phases != null and not actor.phases.started.is_connected(_on_phase_started):
		actor.phases.started.connect(_on_phase_started)


## Draw the actor after this step: the telegraph and flash from its AI's windup, then the pose.
func step(delta: float) -> void:
	if actor.controller != _driver:
		_driver = actor.controller
		_ai = _driver as AIController
	if ai_view or _ai_label != null:
		_show_ai_view()
	var ai: AIController = _ai
	var telegraphing: bool = ai != null and ai.state == AIController.State.WINDUP
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
	_hop(delta)


## How high the body is off its rest this step (px, up is positive), for tests.
func lift() -> float:
	return -_lift.y


## The hop while walking, the bob while standing, and its cast's staff animation, on the sprite and
## the face.
func _hop(delta: float) -> void:
	_hop_time += delta
	var walking: bool = actor.velocity.length_squared() > HOP_SPEED * HOP_SPEED
	var up: float = 0.0
	if walking:
		up = roundf(absf(sin(_hop_time * HOP_RATE * PI)) * HOP_HEIGHT)
	else:
		up = roundf((sin(_hop_time * HOP_RATE) * 0.5 + 0.5) * HOP_IDLE)
	# The staff animation of its cast (ActorLook's pose: lift, push, shake) on top.
	var at: Vector2 = Vector2(0.0, -up) + pose_offset(_hop_time)
	apply_pose(sprite, _face, false)
	if at == _lift:
		# Whole pixels: most steps the body is where it was.
		return
	_lift = at
	if sprite != null:
		sprite.offset = _sprite_offset + _lift
	if _face != null:
		_face.body_offset = _lift



## True while the hurt pose shows (a hit landed in the last HURT_TIME seconds).
func is_hurt() -> bool:
	return _hurt_left > 0.0


## How far the telegraph reaches now (0 when hidden), for tests.
func telegraph_reach() -> float:
	if telegraph == null or not telegraph.visible:
		return 0.0
	return TELEGRAPH_START + telegraph.region_rect.size.x


## The telegraph from TELEGRAPH_START to `reach` along +X, its lane `radius` plus half the margin
## either side (its sprite's region and the shader's length and lane).
func _fit_telegraph(reach: float, radius: float) -> void:
	var length: float = maxf(reach - TELEGRAPH_START, 1.0)
	telegraph.offset = Vector2(TELEGRAPH_START, -TELEGRAPH_HEIGHT * 0.5)
	telegraph.region_rect = Rect2(0.0, 0.0, length, TELEGRAPH_HEIGHT)
	var material: ShaderMaterial = telegraph.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter(&"beam_length", length)
		material.set_shader_parameter(&"telegraph_lane", radius + TELEGRAPH_LANE_MARGIN * 0.5)


func _show_telegraph(on: bool, ai: AIController) -> void:
	_showing = on
	if telegraph != null:
		var caster: Caster = actor.caster
		# The staff the AI winds up (enemy AI AI5: it may hold several).
		var at: int = ai.telegraph_staff() if ai != null else 0
		var reach: float = caster.next_cast_reach(at) if on and caster != null else 0.0
		if reach > TELEGRAPH_START:
			_fit_telegraph(reach, caster.next_cast_radius(at))
		# A cast that is not aimed (a nova, an orbit) shows no line: the pose and flash say it.
		telegraph.visible = on and reach > TELEGRAPH_START
		if on:
			telegraph.rotation = actor.aim.angle()
	if on:
		_update_telegraph(ai.telegraph_progress())
	elif sprite != null:
		sprite.modulate = Color.WHITE


## Make the telegraph brighter, its dashes march and its arrowhead grow as the cast gets closer.
func _update_telegraph(progress: float) -> void:
	if sprite != null:
		sprite.modulate = TELEGRAPH_COLOR_LAST if progress >= TELEGRAPH_LAST_FROM else TELEGRAPH_COLOR
	if telegraph == null:
		return
	# The aim is locked through the windup; a swap or a possession may still turn the actor.
	telegraph.rotation = actor.aim.angle()
	var material: ShaderMaterial = telegraph.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter(&"telegraph_progress", progress)


## Which pose the sprite shows: the hurt one over the windup one over the idle strip. A pose
## without its texture is skipped.
func _update_sprite() -> void:
	if sprite == null:
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


## The AI view: "<behaviour> · <step>" over its head while `ai_view` is on; text set only when it
## changed.
func _show_ai_view() -> void:
	if not ai_view:
		_ai_label.visible = false
		return
	if _ai_label == null:
		_ai_label = Label.new()
		_ai_label.name = "AIView"
		_ai_label.position = Vector2(-48.0, -44.0)
		_ai_label.size = Vector2(96.0, 12.0)
		_ai_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ai_label.add_theme_font_size_override(&"font_size", 8)
		add_child(_ai_label)
	_ai_label.visible = true
	var words: String = ""
	if _ai != null:
		var brain: AIBrain = _ai.brain
		words = "%s · %s" % [brain.behaviour.name() if brain.behaviour != null else "-", String(AIBrain.State.keys()[brain.state]).to_lower()]
	if words != _ai_words:
		_ai_words = words
		_ai_label.text = words


## Words the AI view shows now ("" while it is off or no AI drives the actor).
func ai_view_text() -> String:
	return _ai_words if ai_view else ""


## A boss's phase began: its look's body sprite, if it has one, becomes the idle one.
func _on_phase_started(_index: int, phase: EnemyPhase) -> void:
	if phase.look == null or phase.look.texture == null or sprite == null:
		return
	_idle_texture = phase.look.texture
	if _pose == Pose.IDLE:
		sprite.texture = _idle_texture


## A hit on the actor shows the hurt pose at once.
func _on_damaged(_by: int, _amount: float) -> void:
	_hurt_left = HURT_TIME
	_update_sprite()
