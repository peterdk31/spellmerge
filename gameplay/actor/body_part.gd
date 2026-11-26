class_name BodyPart
extends Sprite2D
## One part of a layered body (boss plan OB8, docs/milestones/boss-old-broom.md, "Poses and layered
## bodies"): a frame of any size (a strip or a sheet of them, `hframes` and `vframes`) that the
## body's look moves by what the body does (`BodyPose`). A layered body's parts are the `BodyPart`s
## under its `Sprite` (the body sprite Feel flashes, squashes and breaks: content/enemies/README.md),
## so a hit's flash and squash reach every part. A part may hold parts of its own: each moves in its
## parent's frame (a stick on a head rides the head's swish, and leans on top of it).
##
## Where it turns from is its node's `position` (its pivot: where it is bound to its parent); its
## `offset` puts its art round that point. Its numbers say how it moves, each at the body's full speed
## (the look's `full_speed`), and none of them changes the game:
##
## - `lean`: degrees it tilts into the way the body goes (its sideways part), following the pose's
##   drive, so it leans in, swings back past upright when the body brakes and settles; winding up,
##   the body rears back from its aim.
## - `lag`: pixels it trails behind the way the body goes.
## - `swish`: degrees it swings to and fro `swish_rate` times a second while the body goes.
## - `squash`: how much wider and lower it is while the body goes (a head dragged on the floor).
## - `sway`: degrees it sways `sway_rate` times a second while the body stands.
## - `tap`: pixels it lifts and drops, `taps` times in quick succession every `tap_every` seconds,
##   while the body stands idle (the IDLE pose; boss plan OB9: an impatient tap on the floor; a part
##   on the floor lifts the parts on it with it).
## - `wall_squash`: how much it squashes, then stretches, along the way the body met a wall.
## - `shudder`: pixels it shakes as the body meets a wall, and all through a phase change.
## - `fling`: how far it flies when the body dies (Feel's remnant: the parts fly apart where it
##   died; 0 stays where it fell, 2 flies twice as far).
## - `carries_face`: the actor's `Face` rides this part (the look moves the face's `body_offset`
##   with it).
## - `pose_frames`: with more than one frame, the frame each pose shows, by `BodyPose.Pose`
##   (IDLE, WINDUP, MOVE, WALL, HURT, CAST, TRANSITION); missing or below 0: frame 0. A few drawn
##   frames for the extreme poses (a wind-up, a wall hit).
##
## Drawn only: the part is the look's, and nothing in the game reads it. It sets nothing on itself
## that did not change.

const SHAKE_RATE: Vector2 = Vector2(97.0, 83.0)

@export var lean: float = 0.0
@export var lag: float = 0.0
@export var swish: float = 0.0
@export var swish_rate: float = 2.0
@export_range(0.0, 0.6, 0.01) var squash: float = 0.0
@export var sway: float = 0.0
@export var sway_rate: float = 0.5
@export var tap: float = 0.0
@export var taps: int = 2
@export var tap_every: float = 1.5
@export_range(0.0, 0.6, 0.01) var wall_squash: float = 0.0
@export var shudder: float = 0.0
@export_range(0.0, 4.0, 0.05) var fling: float = 1.0
@export var carries_face: bool = false
@export var pose_frames: PackedInt32Array = PackedInt32Array()

## View as a whole: the state walk never enters it (core/sim/README.md).
const VIEW_ONLY: bool = true

## How much harder it shudders through a phase change than at a wall hit's start.
const TRANSITION_SHUDDER: float = 1.5
## Seconds of one tap (up and down again).
const TAP_TIME: float = 0.14

## Its place, turn and scale as the scene made it (`take_rest`).
var rest_position: Vector2 = Vector2.ZERO
var rest_rotation: float = 0.0
var rest_scale: Vector2 = Vector2.ONE
## Art pixels a world unit of the part it hangs from (its `position` and moves are in them):
## ArtDetail of the parent's texture, 1 under a plain node.
var _parent_detail: float = 1.0
var _rested: bool = false


## Note the part as it stands now as its rest (the look calls it once, before it moves the part).
func take_rest() -> void:
	if _rested:
		return
	_rested = true
	rest_position = position
	rest_rotation = rotation
	# A part drawn at 2x detail (ArtDetail) is drawn at half its size: its node's scale is its
	# detail relative to the part it hangs from, whose art pixels its place and offset are in
	# (a 2x part under a 2x part: scale 1, its numbers in the parent's art pixels).
	var parent_sprite := get_parent() as Sprite2D
	_parent_detail = float(ArtDetail.of(parent_sprite.texture)) if parent_sprite != null and parent_sprite.texture != null else 1.0
	rest_scale = scale * _parent_detail / float(ArtDetail.of(texture))


## Every `BodyPart` under `root` (itself left out), parents before their parts, in the tree's order,
## added to `into`.
static func parts_of(root: Node, into: Array[BodyPart]) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child is BodyPart:
			into.append(child as BodyPart)
		parts_of(child, into)


## The frame `pose` shows (see `pose_frames`).
func frame_for(pose: int) -> int:
	var frames: int = hframes * vframes
	if frames <= 1 or pose < 0 or pose >= pose_frames.size() or pose_frames[pose] < 0:
		return 0
	return mini(pose_frames[pose], frames - 1)


## How far up a tap has it at `seconds` on the look's clock, 0 to 1: `taps` quick lifts at the start
## of every `tap_every` seconds, none between.
func tap_lift(seconds: float) -> float:
	var into: float = fmod(seconds, tap_every)
	if into >= TAP_TIME * float(taps):
		return 0.0
	return absf(sin(into / TAP_TIME * PI))


## Draw the part as `body` says the body moves now.
func show_pose(body: BodyPose) -> void:
	take_rest()
	var degrees: float = lean * body.drive.x
	degrees += swish * body.going * sin(body.swish_time * TAU * swish_rate)
	degrees += sway * (1.0 - body.going) * sin(body.time * TAU * sway_rate)
	var at: Vector2 = -body.drive * lag
	if tap > 0.0 and taps > 0 and tap_every > 0.0 and body.pose == BodyPose.Pose.IDLE:
		at.y -= tap * (1.0 - body.going) * tap_lift(body.time)
	var stretch: Vector2 = Vector2(1.0 + squash * body.going, 1.0 - squash * body.going)
	var wall: float = body.wall_share()
	if wall > 0.0 and wall_squash > 0.0:
		# Squashed along the way it hit, then stretched, dying away.
		var through: float = body.wall_through()
		var amount: float = wall_squash * sin(through * TAU) * wall
		if absf(body.wall_dir.x) >= absf(body.wall_dir.y):
			stretch *= Vector2(1.0 - amount, 1.0 + amount)
		else:
			stretch *= Vector2(1.0 + amount, 1.0 - amount)
	var shake: float = shudder * (wall + (TRANSITION_SHUDDER if body.pose == BodyPose.Pose.TRANSITION else 0.0))
	if shake > 0.0:
		at += Vector2(sin(body.time * SHAKE_RATE.x), cos(body.time * SHAKE_RATE.y)) * shake
	# Its moves are world units; its place is in its parent's art pixels.
	var place: Vector2 = rest_position + (at * _parent_detail).round()
	var turn: float = rest_rotation + deg_to_rad(degrees)
	var size: Vector2 = rest_scale * stretch
	if position != place:
		position = place
	if rotation != turn:
		rotation = turn
	if scale != size:
		scale = size
	var shown: int = frame_for(body.pose)
	if hframes * vframes > 1 and frame != shown:
		frame = shown
