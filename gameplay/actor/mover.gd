class_name Mover
extends ActorComponent
## The mover (actors G4, docs/milestones/M2-actors.md, "The components"): everything that sets
## an actor's `velocity`. It walks where the intent says (`speed` × the intent's `move`), and it
## is the one caster kit: the moves an actor's own cards ask for (staffs B4 for wizards, F8c for
## enemies; one implementation since actors G4, docs/DECISIONS.md "The actor kit"):
##
## - `dash`: goes the way the intent walks (the way the actor aims when it stands), as far and as
##   long as the card asks (`to` is measured from the staff tip); it turns toward a target as it
##   goes when the card homes (`Spells.move_homing`).
## - `teleport`: jumps at once along the card's line (`to` measured from the staff tip), stopping
##   TELEPORT_CLEARANCE short of the first wall, then backing off until the body (`body_radius`)
##   is clear of walls and inside the room.
## - `hook` and `swap`: pull the actor to the world point `to` over the time asked.
## - `recoil`: a push back. The recoils asked in one step are added up first (so `mirror ·
##   recoil` cancels) and become one push over the longest time asked, which then runs on its
##   own time (up to MAX_RECOILS at once; a push past that is dropped).
##
## A dash, teleport, hook or swap replaces the move in progress, which is answered where the
## actor is. A dash, hook or teleport answers `caster_move_finished` where it ended (a swap sends
## nothing: its blast went off at the target): a teleport at once, the others the step after
## their last, once the body has walked it (the last step is shortened, so a move goes exactly
## its distance). A card's move is the actor's own when the card's tag names the actor's caster
## number (`Actor.caster_number`, its actor id), which is also the event's `caster`.
##
## Statuses (`Combat.pace`: chill slows, freeze stops) scale walking and dashing (the actor's
## own legs), not a hook, a swap or a recoil (the spell moves it). Combat's push on the actor
## (`Combat.consume_knockback`) is added every step. A swap card that names the actor as its
## target (`target_move_requested`) puts it there at once. While the actor is down it stands: a
## move in progress ends unanswered, the recoil is dropped and new requests are ignored.
##
## Nothing here allocates in `step`.

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## A teleport that meets a wall ends this many pixels short of it, and is then backed off in
## steps of TELEPORT_BACKOFF until the body is clear.
const TELEPORT_CLEARANCE: float = 8.0
const TELEPORT_BACKOFF: float = 4.0
## Most recoil pushes that run at once (a push past this is dropped).
const MAX_RECOILS: int = 8
## The shortest time a move or push takes.
const MIN_SECONDS: float = 0.01

## Walking speed in pixels per second at full tilt (an enemy's from `EnemyBase.move_speed`).
@export var speed: float = 90.0
## The body's radius for a teleport's landing (about the hurt circle's).
@export var body_radius: float = 6.0

## The move in progress: &"dash", &"hook", &"swap", or &"" for none. Its seconds left, its way
## (unit length), speed and the tag of its card.
var _mode: StringName = &""
var _left: float = 0.0
var _direction: Vector2 = Vector2.ZERO
var _speed: float = 0.0
## The homing of the dash in progress (`Spells.move_homing`), or null.
var _homing: Homing = null
var _tag: int = 0
## True when the move's time ran out in the last step: the next step answers it.
var _done: bool = false
## Recoil asked for since the last step (pixels, the longest time asked), and the pushes being
## applied, each with its own velocity and seconds left (the first `_recoil_count` count).
var _recoil_pending: Vector2 = Vector2.ZERO
var _recoil_pending_seconds: float = 0.0
var _recoil_velocities: PackedVector2Array = PackedVector2Array()
var _recoil_lefts: PackedFloat32Array = PackedFloat32Array()
var _recoil_count: int = 0


func _init() -> void:
	_recoil_velocities.resize(MAX_RECOILS)
	_recoil_lefts.resize(MAX_RECOILS)


func attach() -> void:
	if actor.events == null:
		return
	if not actor.events.caster_move_requested.is_connected(_on_caster_move_requested):
		actor.events.caster_move_requested.connect(_on_caster_move_requested)
	if not actor.events.target_move_requested.is_connected(_on_target_move_requested):
		actor.events.target_move_requested.connect(_on_target_move_requested)


func detach() -> void:
	if actor.events == null or not is_instance_valid(actor.events):
		return
	if actor.events.caster_move_requested.is_connected(_on_caster_move_requested):
		actor.events.caster_move_requested.disconnect(_on_caster_move_requested)
	if actor.events.target_move_requested.is_connected(_on_target_move_requested):
		actor.events.target_move_requested.disconnect(_on_target_move_requested)


## Set the actor's `velocity` for this step: the walk or the move in progress, the recoil
## pushes and Combat's push. The actor moves the body afterwards (`move_and_slide`).
func step(delta: float) -> void:
	if actor.is_down():
		_cancel()
		actor.velocity = Vector2.ZERO
		return
	if _done:
		# The last step of the move has been walked (the body moved after the last step).
		_finish()
	# Combat's pace (chill slows, freeze stops) and its push on the actor.
	var pace: float = actor.combat.pace(actor) if actor.combat != null else 1.0
	var velocity: Vector2 = Vector2.ZERO
	if _left > 0.0:
		var dash: bool = _mode == &"dash"
		if dash and _homing != null:
			# A homing dash turns toward a target as it goes, as a homing shot does.
			_direction = _homing.steer(actor.projectiles, _caster_number(), actor.global_position, _direction, delta)
		# The last step is shortened, so a move goes exactly its distance.
		velocity = _direction * _speed * minf(delta, _left) / maxf(delta, 0.0001)
		if dash:
			velocity *= pace
		_left = maxf(_left - delta, 0.0)
		_done = _left <= 0.0
	else:
		velocity = actor.intent.move.limit_length(1.0) * speed * pace
	velocity += _recoil_step(delta)
	if actor.combat != null:
		velocity += actor.combat.consume_knockback(actor, delta)
	actor.velocity = velocity


## True while a dash, hook or swap moves the actor.
func is_moving() -> bool:
	return _left > 0.0


## The move in progress (&"dash", &"hook", &"swap"), or &"".
func move_mode() -> StringName:
	return _mode if _left > 0.0 else &""


## The way the move in progress goes (unit length), for the looks.
func move_direction() -> Vector2:
	return _direction


## End the move in progress now and answer it where the actor is (an overlay opened).
func stop() -> void:
	if _left > 0.0 or _done:
		_finish()


## A card of this actor asked to move it (see the class doc).
func _on_caster_move_requested(_player: int, mode: StringName, to: Vector2, seconds: float, tag: int) -> void:
	if not _owns(tag) or actor.is_down() or not to.is_finite():
		return
	if mode == &"recoil":
		_recoil_pending += to - actor.muzzle_position()
		_recoil_pending_seconds = maxf(_recoil_pending_seconds, maxf(seconds, MIN_SECONDS))
		return
	if mode != &"dash" and mode != &"teleport" and mode != &"hook" and mode != &"swap":
		return
	if _left > 0.0 or _done:
		_finish()
	if mode == &"teleport":
		_teleport(to, tag)
		return
	var time: float = maxf(seconds, MIN_SECONDS)
	_mode = mode
	_homing = null
	if mode == &"dash":
		var walk: Vector2 = actor.intent.move
		_direction = walk.normalized() if walk != Vector2.ZERO else actor.aim
		_speed = (to - actor.muzzle_position()).length() / time
		if actor.spells != null:
			_homing = actor.spells.move_homing(_caster_number())
	else:
		var pull: Vector2 = to - actor.global_position
		_direction = pull.normalized()
		_speed = pull.length() / time
	_left = time
	_tag = tag


## True when `tag` is a spell of this actor's caster number.
func _owns(tag: int) -> bool:
	var number: int = _caster_number()
	return number >= 0 and SpellTag.is_spell_tag(tag) and SpellTag.caster_of(tag) == number


func _caster_number() -> int:
	return actor.caster_number()


## Jump to where a teleport card aimed (`to` is measured from the staff tip), stopping short of
## the first wall, then backing off along the path until the whole body is clear of walls and
## inside the room (or staying put), and say where the actor landed.
func _teleport(to: Vector2, tag: int) -> void:
	var start: Vector2 = actor.global_position
	var goal: Vector2 = start + (to - actor.muzzle_position())
	if actor.projectiles != null:
		var reached: Vector2 = actor.projectiles.clip_to_walls(start, goal)
		if reached != goal:
			reached = reached.move_toward(start, TELEPORT_CLEARANCE)
		goal = reached
		while goal != start and actor.projectiles.circle_blocked(goal, body_radius):
			goal = goal.move_toward(start, TELEPORT_BACKOFF)
	actor.global_position = goal
	if actor.events != null:
		actor.events.caster_move_finished.emit(_caster_number(), &"teleport", goal, tag)


## The move ended: say where, so its card can go off there (blast, a trigger). A swap sends
## nothing (its blast goes off at the target).
func _finish() -> void:
	var mode: StringName = _mode
	_left = 0.0
	_done = false
	_mode = &""
	_homing = null
	if actor.events != null and mode != &"swap" and mode != &"":
		actor.events.caster_move_finished.emit(_caster_number(), mode, actor.global_position, _tag)


## The move and the pushes end unanswered (the actor went down).
func _cancel() -> void:
	_left = 0.0
	_done = false
	_mode = &""
	_homing = null
	_recoil_pending = Vector2.ZERO
	_recoil_pending_seconds = 0.0
	_recoil_count = 0


## The recoil asked for since the last step becomes a push of that distance over the time asked,
## which ends on its own time; returns the velocity of all pushes to add now (a push's last step
## is shortened, so each moves exactly its distance).
func _recoil_step(delta: float) -> Vector2:
	if _recoil_pending != Vector2.ZERO and _recoil_count < MAX_RECOILS:
		_recoil_velocities[_recoil_count] = _recoil_pending / _recoil_pending_seconds
		_recoil_lefts[_recoil_count] = _recoil_pending_seconds
		_recoil_count += 1
	_recoil_pending = Vector2.ZERO
	_recoil_pending_seconds = 0.0
	var total: Vector2 = Vector2.ZERO
	var at: int = 0
	while at < _recoil_count:
		var left: float = _recoil_lefts[at]
		total += _recoil_velocities[at] * minf(left, delta) / maxf(delta, 0.0001)
		left -= delta
		if left <= 0.0:
			# Done: the last push takes its place.
			_recoil_count -= 1
			_recoil_velocities[at] = _recoil_velocities[_recoil_count]
			_recoil_lefts[at] = _recoil_lefts[_recoil_count]
			continue
		_recoil_lefts[at] = left
		at += 1
	return total


## A swap card moved this actor (it was the target): it is there at once, its move and aim kept.
func _on_target_move_requested(_player: int, moved: Node, to: Vector2) -> void:
	if moved == actor and to.is_finite():
		actor.global_position = to
