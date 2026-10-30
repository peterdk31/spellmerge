class_name Mover
extends ActorComponent
## The mover (actors G4, docs/milestones/M2-actors.md, "The components"): everything that sets
## an actor's `velocity`. It walks where the intent says (`speed` × the intent's `move`), and it
## is the one caster kit: the moves an actor's own cards ask for (staffs B4 for wizards, F8c for
## enemies; one implementation since actors G4, docs/DECISIONS.md "The actor kit").
##
## Every move adds up (rules R4 F1, as shots' moves do, `Projectiles.move_shot`): each request
## carries its own `move` (the way and the distance) and its time, and runs on its own, so two
## dashes cast close together stack, two pulls add and a dash and its recoil add. A `teleport` is
## over at once: the actor jumps by its `move`, stopping TELEPORT_CLEARANCE short of the first
## wall, then backing off until the body (`body_radius`) is clear of walls and inside the room.
## Every other move (`dash`, `pull`, `swap`, `recoil`) is a velocity for its time; a `dash` turns
## toward a target as it goes when its card homes (`Spells.dashes().move_homing`). Each move answers
## `caster_move_finished` where it ended: a teleport at once, the others the step after their
## last, once the body has walked it (the last step is shortened, so a move goes exactly its
## distance). A card's move is the actor's own when the card's tag names the actor's caster
## number (`Actor.caster_number`, its actor id), which is also the event's `caster`.
##
## A dash is the actor's own legs: it walks instead of the intent while it runs, and statuses
## (`Combat.pace`: chill slows, freeze stops) scale it as they scale walking. The other moves are
## done to the actor (the spell moves it): added on top, not slowed. Combat's push on the actor
## (`Combat.consume_knockback`) is added every step. A swap card that names the actor as its
## target (`target_move_requested`) puts it there at once. While the actor is down it stands: its
## moves end unanswered and new requests are ignored.
##
## Nothing here allocates in `step` (but the list of moves growing when full).

const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")

## A teleport that meets a wall ends this many pixels short of it, and is then backed off in
## steps of TELEPORT_BACKOFF until the body is clear.
const TELEPORT_CLEARANCE: float = 8.0
const TELEPORT_BACKOFF: float = 4.0
## Room for this many running moves at first; the list doubles when it is full.
const MOVE_ROOM: int = 8
## The shortest time a move takes.
const MIN_SECONDS: float = 0.01

## Walking speed in pixels per second at full tilt (an enemy's from `EnemyBase.move_speed`).
@export var speed: float = 90.0
## The body's radius for a teleport's landing (about the hurt circle's).
@export var body_radius: float = 6.0

## The moves running (the first `_count`): each one's mode, velocity, seconds left (0 or less:
## done, answered next step), its card's tag and its homing (a dash's, or null).
var _modes: Array[StringName] = []
var _velocities: PackedVector2Array = PackedVector2Array()
var _lefts: PackedFloat32Array = PackedFloat32Array()
var _tags: PackedInt64Array = PackedInt64Array()
var _homings: Array[Homing] = []
var _count: int = 0
## What the moves added in the last step (pixels per second), for the looks.
var _moved: Vector2 = Vector2.ZERO


func _init() -> void:
	_grow(MOVE_ROOM)


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


## Set the actor's `velocity` for this step: the walk (or its dashes), every other move and
## Combat's push. The actor moves the body afterwards (`move_and_slide`).
func step(delta: float) -> void:
	if actor.is_down():
		_count = 0
		_homings.fill(null)
		_moved = Vector2.ZERO
		actor.velocity = Vector2.ZERO
		return
	# The moves whose last step has been walked (the body moved after it) say where they ended.
	_answer()
	# Combat's pace (chill slows, freeze stops) and its push on the actor, asked by its own id.
	var pace: float = actor.combat.own_pace(actor, actor.id) if actor.combat != null else 1.0
	var legs: bool = false
	_moved = Vector2.ZERO
	for at in _count:
		var velocity: Vector2 = _velocities[at]
		if _homings[at] != null:
			# A homing dash turns toward a target as it goes, as a homing shot does.
			velocity = _homings[at].steer(actor.projectiles, _caster_number(), actor.global_position, velocity, delta)
			_velocities[at] = velocity
		# The last step is shortened, so a move goes exactly its distance.
		var share: Vector2 = velocity * minf(delta, _lefts[at]) / maxf(delta, 0.0001)
		if _modes[at] == &"dash":
			legs = true
			share *= pace
		_moved += share
		_lefts[at] -= delta
	var velocity: Vector2 = _moved
	if not legs:
		velocity += actor.intent.move.limit_length(1.0) * speed * pace
	if actor.combat != null:
		velocity += actor.combat.own_knockback(actor, actor.id, delta)
	actor.velocity = velocity


## True while a move carries the actor.
func is_moving() -> bool:
	return _count > 0


## The way the moves went in the last step (unit length, or zero when they cancel), for the looks.
func move_direction() -> Vector2:
	return _moved.normalized()


## End every move now and answer each where the actor is (an overlay opened).
func stop() -> void:
	for at in _count:
		_lefts[at] = 0.0
	_answer()


## A card of this actor asked to move it by `move` over `seconds` (see the class doc).
func _on_caster_move_requested(_player: int, mode: StringName, move: Vector2, seconds: float, tag: int) -> void:
	if not _owns(tag) or actor.is_down() or not move.is_finite():
		return
	if mode == &"teleport":
		_teleport(move, tag)
		return
	if _count == _lefts.size():
		# Full: grow (rare; the steady state allocates nothing).
		_grow(_count * 2)
	var time: float = maxf(seconds, MIN_SECONDS)
	_modes[_count] = mode
	_velocities[_count] = move / time
	_lefts[_count] = time
	_tags[_count] = tag
	_homings[_count] = actor.spells.dashes().move_homing(_caster_number()) if mode == &"dash" and actor.spells != null else null
	_count += 1


func _grow(size: int) -> void:
	_modes.resize(size)
	_velocities.resize(size)
	_lefts.resize(size)
	_tags.resize(size)
	_homings.resize(size)


## True when `tag` is a spell of this actor's caster number.
func _owns(tag: int) -> bool:
	var number: int = _caster_number()
	return number >= 0 and SpellTag.is_spell_tag(tag) and SpellTag.caster_of(tag) == number


func _caster_number() -> int:
	return actor.caster_number()


## Jump by `move` at once, stopping short of the first wall, then backing off along the path
## until the whole body is clear of walls and inside the room (or staying put), and say where the
## actor landed.
func _teleport(move: Vector2, tag: int) -> void:
	var start: Vector2 = actor.global_position
	var goal: Vector2 = start + move
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


## Answers the moves that are done where the actor is, so their cards go off there (blast, a
## trigger), and takes them off the list. A move asked while answering (a payload that moves
## again) is added at the end and runs.
func _answer() -> void:
	var at: int = 0
	while at < _count:
		if _lefts[at] > 0.0:
			at += 1
			continue
		var mode: StringName = _modes[at]
		var tag: int = _tags[at]
		_count -= 1
		_modes[at] = _modes[_count]
		_velocities[at] = _velocities[_count]
		_lefts[at] = _lefts[_count]
		_tags[at] = _tags[_count]
		_homings[at] = _homings[_count]
		_homings[_count] = null
		if actor.events != null:
			actor.events.caster_move_finished.emit(_caster_number(), mode, actor.global_position, tag)


## A swap card moved this actor (it was the target): it is there at once, its move and aim kept.
func _on_target_move_requested(_player: int, moved: Node, to: Vector2) -> void:
	if moved == actor and to.is_finite():
		actor.global_position = to
