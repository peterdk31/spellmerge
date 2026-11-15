class_name BodyPose
extends RefCounted
## What a body is doing, for its look (boss plan OB8, docs/milestones/boss-old-broom.md, "Poses and
## layered bodies"): its pose, read from states the game already has, and how it moves, which the
## parts of a layered body (`BodyPart`) are drawn by. Any look may keep one and step it last in its
## step (`CreatureLook` does, for every enemy and boss): the look tells it what only the look knows
## (whether its AI telegraphs, stands through a phase change, was just hurt), and it reads the rest
## off the body.
##
## The poses, the first that holds winning (`choose`):
##
## | Pose | When |
## | --- | --- |
## | TRANSITION | a boss stands through a phase change (its AI's TRANSITION) |
## | WALL | its own move (a dash, `Mover.is_dashing`) met a wall: the body went less than WALL_SHARE of the way its move would have taken it, after a step that went freely; held WALL_TIME |
## | HURT | a hit landed on it within the look's hurt time |
## | WINDUP | its AI winds up a cast it telegraphs |
## | MOVE | its own move carries it (a dash; not a pull or a push done to it) |
## | CAST | its cast's staff animation plays (`Spells.poses()`, a swing's half turn) |
## | IDLE | anything else |
##
## How it moves: `going` (its speed as a share of the look's full speed, eased), `drive` (where the
## parts lean and trail to, a spring that follows the way it goes as a share of full speed, so a
## body that brakes swings back past upright before it settles; winding up it rears back from its
## aim, casting it leans into it), the swish's and the sway's turns, and the wall hit's way and how
## much of it is left. A pose is read from state alone (the body's place, velocity, moves, aim, its
## AI's state and the hits it heard), so it is the same on every machine; all of it is drawn only,
## and nothing in the game reads it.
##
## Nothing here allocates.

enum Pose { IDLE, WINDUP, MOVE, WALL, HURT, CAST, TRANSITION }

## The drive's spring: how hard it pulls toward where the body goes, and how much it is damped
## (below critical, about 0.55 of it, so a stop swings back once).
const SPRING: float = 90.0
const DAMPING: float = 10.0
## Winding up it rears back from its aim by this share; casting it leans into it by this one.
const REAR: float = 0.7
const LUNGE: float = 0.5
## How fast `going` follows the body's speed (shares a second).
const GOING_RATE: float = 5.0
## A wall hit: its own move, at least WALL_MIN_SPEED px/s, went less than WALL_SHARE of the way; the
## pose and the parts' squash and shudder last WALL_TIME seconds.
const WALL_MIN_SPEED: float = 40.0
const WALL_SHARE: float = 0.5
const WALL_TIME: float = 0.4

## View as a whole: the state walk never enters it (core/sim/README.md).
const VIEW_ONLY: bool = true

## The pose now.
var pose: Pose = Pose.IDLE
## The parts' lean and trail: a share of full speed along the way it goes (may overshoot).
var drive: Vector2 = Vector2.ZERO
## The body's speed as a share of full speed, eased (0-1).
var going: float = 0.0
## Seconds of the swish's turn (it runs while the body goes, as fast as it goes) and of the look's
## own clock (the sway and the shudder).
var swish_time: float = 0.0
var time: float = 0.0
## The wall hit: seconds left of it, and the way the body went into the wall.
var wall_left: float = 0.0
var wall_dir: Vector2 = Vector2.RIGHT

var _drive_speed: Vector2 = Vector2.ZERO
## The body at the last step: where it was, the velocity it was to move by, whether a dash carried
## it, and the step's length (a wall is found by comparing them with where the move left it).
var _last_at: Vector2 = Vector2.ZERO
var _last_velocity: Vector2 = Vector2.ZERO
var _last_dashing: bool = false
var _last_delta: float = 0.0
var _has_last: bool = false
## True while its move is held up by a wall (found, and not yet free of it): a move grinding along a
## wall hits it once.
var _against: bool = false


## The pose the states give, the first that holds (see the class doc).
static func choose(transition: bool, wall: bool, hurt: bool, winding: bool, moving: bool, casting: bool) -> Pose:
	if transition:
		return Pose.TRANSITION
	if wall:
		return Pose.WALL
	if hurt:
		return Pose.HURT
	if winding:
		return Pose.WINDUP
	if moving:
		return Pose.MOVE
	if casting:
		return Pose.CAST
	return Pose.IDLE


## Read the body after its step (`delta` seconds): its pose and motion. A step of 0 (the one a local
## stop shows, its hit's moment) reads the pose only: nothing moves and no wall is looked for. The look says what only it knows: `winding` (its AI telegraphs a cast), `transition`
## (it stands through a phase change), `hurt` (a hit within its hurt time); `cast_dir` is the aim of
## its staff animation (`ActorLook.pose_dir`; zero for none) and `full_speed` the speed (px/s) at
## which its motion is whole.
func step(actor: Actor, delta: float, full_speed: float, winding: bool, transition: bool, hurt: bool, cast_dir: Vector2) -> void:
	if actor == null:
		return
	var dashing: bool = actor.mover != null and actor.mover.is_dashing() and not actor.is_down()
	if delta <= 0.0:
		pose = choose(transition, wall_left > 0.0, hurt, winding, dashing, not cast_dir.is_zero_approx())
		return
	time += delta
	wall_left = maxf(wall_left - delta, 0.0)
	_find_wall(actor)
	pose = choose(transition, wall_left > 0.0, hurt, winding, dashing, not cast_dir.is_zero_approx())
	var full: float = maxf(full_speed, 1.0)
	var speed: float = minf(actor.velocity.length() / full, 1.0)
	going = move_toward(going, speed, GOING_RATE * delta)
	swish_time += delta * going
	var target: Vector2 = (actor.velocity / full).limit_length(1.0)
	match pose:
		Pose.WINDUP:
			target = -actor.aim * REAR
		Pose.CAST:
			target = cast_dir.normalized() * LUNGE
		Pose.TRANSITION:
			target = Vector2.ZERO
	# The spring, stepped in parts no longer than 1/60 s, so a long frame does not blow it up.
	var left: float = delta
	while left > 0.0:
		var dt: float = minf(left, 1.0 / 60.0)
		_drive_speed += ((target - drive) * SPRING - _drive_speed * DAMPING) * dt
		drive += _drive_speed * dt
		left -= dt
	_last_at = actor.global_position
	_last_velocity = actor.velocity
	_last_dashing = dashing
	_last_delta = delta
	_has_last = true


## Forget the last step (after a snapshot gave the body its state back): nothing is found from
## where it was before.
func forget() -> void:
	_has_last = false
	_against = false
	wall_left = 0.0


## How much of the wall hit is left (1 as it hits, down to 0).
func wall_share() -> float:
	return wall_left / WALL_TIME


## How far through the wall hit it is (0 as it hits, 1 when it is over; 1 with none).
func wall_through() -> float:
	return 1.0 - wall_share()


## A wall met since the last step: its own move went less than WALL_SHARE of the way it would have,
## and the step before went freely (a move grinding along a wall hits it once). A step a local stop
## shortened only goes farther than its velocity says, so it never reads as a wall.
func _find_wall(actor: Actor) -> void:
	if not _has_last or not _last_dashing or _last_delta <= 0.0:
		_against = false
		return
	var speed: float = _last_velocity.length()
	if speed < WALL_MIN_SPEED:
		_against = false
		return
	var way: Vector2 = _last_velocity / speed
	var went: float = (actor.global_position - _last_at).dot(way) / _last_delta
	if went >= speed * WALL_SHARE:
		_against = false
		return
	if not _against:
		wall_left = WALL_TIME
		wall_dir = way
	_against = true
