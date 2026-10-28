class_name Face
extends ActorLook
## The face every living staff wears (living staffs H2, docs/milestones/M2-living-staffs.md, "The
## face layers"): two floating eyes and two floating brows, drawn over the body on two sprite
## layers it makes itself. Players and strays wear the same face; only the style differs.
##
## Inputs: a `style` (the eye shapes: a personality's, or a stray's), a mood (the brow shapes), a
## look direction (one of nine, from the actor's aim) and the body's motion (the actor's position
## plus `body_offset`, which the body's look sets before the face steps: the hover's bob, a
## stray's hop). The brows carry the mood and the eyes carry the style and the look.
##
## Mood, first that holds: down (eyes shut, worried), the controller winding up a cast
## (`ActorController.is_telegraphing`: furious, a telegraph on the face), a mood shown for a while
## (`show_mood`; a hit shows worried for HURT_TIME), an idle raised brow, then `resting_mood`.
##
## Follow-through: the eyes trail the body by LAG seconds and the brows trail the eyes the same
## way, at most MAX_LAG pixels each, so a hop or a stop shows in the layers for free; a jump of
## more than SNAP pixels (a teleport) is not trailed. A cast pops the eyes up POP_EYES pixels and
## the brows POP_BROWS more for POP_TIME seconds.
##
## Idle habits, from a generator seeded per actor so no two faces fidget together: blinks
## always; glances and raised brows only while the actor stands and has not cast for IDLE_AFTER
## seconds. How often each comes is the style's (BLINK_EVERY and the rest): the Dozer blinks slowly and never
## raises a brow, the Show-off fidgets, a stray only blinks.
##
## The sheets are art/faces/eyes.svg (one row per style; nine looks, then the blink) and
## art/faces/brows.svg (one column per mood; rows two brows and one). A stray's eyes are drawn
## white and tinted with `glow`. Nothing here allocates per step, and the layers are only set when
## their frame or place changed (every actor wears a face; performance pass, 2026-10-28).

enum Style { CHEER, EAGER, SLEEPY, STERN, STRAY, STRAY_ONE }
enum Mood { NEUTRAL, RAISED, ANGRY, FURIOUS, WORRIED }

const EYES_SHEET: Texture2D = preload("res://art/faces/eyes.svg")
const BROWS_SHEET: Texture2D = preload("res://art/faces/brows.svg")
## Every frame of both sheets.
const FRAME: Vector2i = Vector2i(16, 8)
## The eye sheet's columns: nine looks ((y + 1) × 3 + x + 1), then the blink.
const BLINK_COLUMN: int = 9
## Where, in a frame, the left eye's top-left pixel (the face's `anchor`) is: eyes and brows.
const EYES_ORIGIN: Vector2 = Vector2(1.0, 1.0)
const BROWS_ORIGIN: Vector2 = Vector2(1.0, 5.0)
## How far the aim must lean (per axis, of unit length) to move the pupils that way.
const LOOK_LEAN: float = 0.38

## Seconds the eyes trail the body, and the brows the eyes.
const LAG: float = 0.1
## The most each layer trails, in pixels, and a jump that is not trailed at all.
const MAX_LAG: float = 2.0
const SNAP: float = 16.0
## A cast: the eyes pop up this many pixels and the brows this many more, for POP_TIME seconds.
const POP_EYES: float = 2.0
const POP_BROWS: float = 1.0
const POP_TIME: float = 0.12
## Seconds a hit shows the worried brows.
const HURT_TIME: float = 0.25
## Standing still this long without a cast makes the actor idle (glances, raised brows).
const IDLE_AFTER: float = 1.0
const GLANCE_TIME: float = 0.6
const RAISE_TIME: float = 0.5

## The idle habits, one value per style (in Style's order): seconds between blinks, a blink's
## length, seconds between glances and between raised brows (0: never). Each wait is drawn from
## 0.7 to 1.3 times its value.
const BLINK_EVERY: PackedFloat32Array = [3.4, 2.8, 2.4, 4.0, 3.0, 3.0]
const BLINK_TIME: PackedFloat32Array = [0.12, 0.12, 0.4, 0.1, 0.1, 0.1]
const GLANCE_EVERY: PackedFloat32Array = [3.0, 1.8, 5.0, 4.0, 0.0, 0.0]
const RAISE_EVERY: PackedFloat32Array = [7.0, 4.0, 0.0, 0.0, 0.0, 0.0]

@export var style: Style = Style.CHEER
## The brows when nothing else holds: a personality's (the Show-off's raised, the Sergeant's
## angry) or a stray's (angry).
@export var resting_mood: Mood = Mood.NEUTRAL
## Where the left eye's top-left pixel sits on the body at rest, in the actor's space.
@export var anchor: Vector2 = Vector2(11.0, -5.0)
## The eyes' tint: white for a player, the element colour for a stray.
@export var glow: Color = Color.WHITE

## Where the body is drawn this step relative to rest (the bob, the hop), set by the body's look.
var body_offset: Vector2 = Vector2.ZERO

var _eyes: Sprite2D = null
var _brows: Sprite2D = null
var _rng: RandomNumberGenerator = null
## Where the eyes and the brows have got to, trailing the body (global).
var _eye_point: Vector2 = Vector2.ZERO
var _brow_point: Vector2 = Vector2.ZERO
var _placed: bool = false
var _pop_left: float = 0.0
var _shown_mood: Mood = Mood.NEUTRAL
var _shown_left: float = 0.0
var _still_for: float = 0.0
var _blink_in: float = 0.0
var _blink_left: float = 0.0
var _glance_in: float = 0.0
var _glance_left: float = 0.0
var _glance: Vector2i = Vector2i.ZERO
var _raise_in: float = 0.0
var _raise_left: float = 0.0
## What the layers were last set to (frames and places), so a step sets only what changed.
var _eyes_frame: Vector2i = Vector2i(-1, -1)
var _brows_frame: Vector2i = Vector2i(-1, -1)
var _eyes_at: Vector2 = Vector2.INF
var _brows_at: Vector2 = Vector2.INF
## How far the layers close on the body in one step of `_k_delta` seconds.
var _k_delta: float = -1.0
var _k: float = 0.0


func setup(owner_actor: Actor) -> void:
	super.setup(owner_actor)
	if _eyes == null:
		_eyes = _layer(EYES_SHEET, EYES_ORIGIN)
		_brows = _layer(BROWS_SHEET, BROWS_ORIGIN)
		_rng = RandomNumberGenerator.new()
	_rng.seed = hash(owner_actor.get_instance_id())
	_eyes.modulate = glow
	_blink_in = _wait(BLINK_EVERY)
	_glance_in = _wait(GLANCE_EVERY)
	_raise_in = _wait(RAISE_EVERY)
	if actor.caster != null and not actor.caster.cast_done.is_connected(_on_cast_done):
		actor.caster.cast_done.connect(_on_cast_done)
	# Connected once, on its own actor (not the bus, where a listener per actor was called for every
	# hit on anyone).
	if not actor.damaged.is_connected(_on_damaged):
		actor.damaged.connect(_on_damaged)


## Show `mood` for `seconds` (over the resting mood and the idle habits; down and a windup still
## win). A newer call replaces an older one.
func show_mood(mood: Mood, seconds: float) -> void:
	_shown_mood = mood
	_shown_left = seconds


## The brows now.
func mood() -> Mood:
	if actor.is_down():
		return Mood.WORRIED
	if actor.controller != null and actor.controller.is_telegraphing():
		return Mood.FURIOUS
	if _shown_left > 0.0:
		return _shown_mood
	if _raise_left > 0.0:
		return Mood.RAISED
	return resting_mood


## Where the pupils look now: -1, 0 or 1 on each axis.
func look() -> Vector2i:
	if _glance_left > 0.0:
		return _glance
	return Vector2i(_lean(actor.aim.x), _lean(actor.aim.y))


## True while an idle glance holds the pupils.
func is_glancing() -> bool:
	return _glance_left > 0.0


## True while the eyes are shut (a blink, or down).
func is_shut() -> bool:
	return _blink_left > 0.0 or actor.is_down()


## The frames the layers show (column, row of their sheets), for tests.
func eyes_frame() -> Vector2i:
	return _eyes.frame_coords


func brows_frame() -> Vector2i:
	return _brows.frame_coords


## The eye layer's and the brow layer's offsets from the face at rest (lag and pop), for tests.
func eye_offset() -> Vector2:
	return _eyes.position - anchor - body_offset


func brow_offset() -> Vector2:
	return _brows.position - _eyes.position


func step(delta: float) -> void:
	_pop_left = maxf(_pop_left - delta, 0.0)
	_shown_left = maxf(_shown_left - delta, 0.0)
	_step_habits(delta)
	_follow(delta)
	# `is_shut`, `look` and `mood` written out (one `is_down` for all three): every actor wears a
	# face and steps it every frame.
	var down: bool = actor.is_down()
	var column: int = BLINK_COLUMN
	if _blink_left <= 0.0 and not down:
		var looking: Vector2i = _glance if _glance_left > 0.0 else Vector2i(_lean(actor.aim.x), _lean(actor.aim.y))
		column = (looking.y + 1) * 3 + looking.x + 1
	var eyes: Vector2i = Vector2i(column, style)
	if eyes != _eyes_frame:
		_eyes_frame = eyes
		_eyes.frame_coords = eyes
	var feeling: Mood = resting_mood
	if down:
		feeling = Mood.WORRIED
	elif actor.controller != null and actor.controller.is_telegraphing():
		feeling = Mood.FURIOUS
	elif _shown_left > 0.0:
		feeling = _shown_mood
	elif _raise_left > 0.0:
		feeling = Mood.RAISED
	var brows: Vector2i = Vector2i(feeling, 1 if style == Style.STRAY_ONE else 0)
	if brows != _brows_frame:
		_brows_frame = brows
		_brows.frame_coords = brows


## The layers trail the body (eyes after it, brows after the eyes) and pop on a cast.
func _follow(delta: float) -> void:
	var body: Vector2 = actor.global_position + body_offset
	if not _placed or _eye_point.distance_squared_to(body) > SNAP * SNAP:
		_eye_point = body
		_brow_point = body
		_placed = true
	if delta != _k_delta:
		# The same step length every physics step: worked out once.
		_k_delta = delta
		_k = 1.0 - exp(-delta / LAG)
	var k: float = _k
	_eye_point += (body - _eye_point) * k
	_brow_point += (_eye_point - _brow_point) * k
	# Each layer trails at most MAX_LAG whole pixels per axis.
	var eye_lag: Vector2 = (_eye_point - body).clampf(-MAX_LAG, MAX_LAG).round()
	var brow_lag: Vector2 = (_brow_point - _eye_point).clampf(-MAX_LAG, MAX_LAG).round()
	if _pop_left > 0.0:
		eye_lag.y -= POP_EYES
		brow_lag.y -= POP_BROWS
	var eyes_at: Vector2 = anchor + body_offset + eye_lag
	if eyes_at != _eyes_at:
		_eyes_at = eyes_at
		_eyes.position = eyes_at
	if eyes_at + brow_lag != _brows_at:
		_brows_at = eyes_at + brow_lag
		_brows.position = _brows_at


## Blinks always; glances and raised brows only while idle.
func _step_habits(delta: float) -> void:
	_blink_left = maxf(_blink_left - delta, 0.0)
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_left = BLINK_TIME[style]
		_blink_in = _wait(BLINK_EVERY)
	var standing: bool = actor.intent == null or actor.intent.move.length_squared() < 0.01
	_still_for = _still_for + delta if standing else 0.0
	var idle: bool = _still_for >= IDLE_AFTER
	_glance_left = maxf(_glance_left - delta, 0.0) if idle else 0.0
	_raise_left = maxf(_raise_left - delta, 0.0) if idle else 0.0
	if not idle:
		return
	_glance_in -= delta
	if _glance_in <= 0.0:
		_glance_left = GLANCE_TIME
		_glance = Vector2i(-1 if _rng.randf() < 0.5 else 1, 0)
		_glance_in = _wait(GLANCE_EVERY)
	_raise_in -= delta
	if _raise_in <= 0.0:
		_raise_left = RAISE_TIME
		_raise_in = _wait(RAISE_EVERY)


## The next wait for a habit (`every`, per style); forever for a habit the style lacks.
func _wait(every_by_style: PackedFloat32Array) -> float:
	var every: float = every_by_style[style]
	if every <= 0.0:
		return INF
	return every * _rng.randf_range(0.7, 1.3)


func _layer(sheet: Texture2D, origin: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = sheet
	sprite.centered = false
	sprite.offset = -origin
	sprite.hframes = sheet.get_width() / FRAME.x
	sprite.vframes = sheet.get_height() / FRAME.y
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	return sprite


static func _lean(value: float) -> int:
	if value > LOOK_LEAN:
		return 1
	if value < -LOOK_LEAN:
		return -1
	return 0


func _on_cast_done(_staff: int, _origin: Vector2, _direction: Vector2) -> void:
	_pop_left = POP_TIME


func _on_damaged(_by: int, _amount: int) -> void:
	show_mood(Mood.WORRIED, HURT_TIME)
