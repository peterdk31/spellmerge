extends RefCounted
## One kind of spawn motion (spawn styles, docs/milestones/spawn-styles.md, "How it is built"):
## the code that draws a body through a spawn for every style that names it (`SpawnStyle.motion`),
## as a card's behaviour is a row of `ModifierBase.RULES` and its kit. `SpawnLook` holds one of each
## (`SpawnLook.MOTIONS`, keyed by the names of `SpawnStyle.MOTIONS`) and hands it each spawning body
## once a frame, just before the frame is drawn; what every style shares (walking the bodies, the
## marks, the cue and its spacing, putting back the bodies done) is the look's.
##
## A motion answers `apply(body, share, style)`: draw `body` at `share` of its spawn as `style` says
## (the look calls it every frame the body spawns in); and `put_back(key, body)`: the body spawns in no
## more, give it its own look back and forget it. It is drawn from the share alone, never from a
## moment it was told of, so a machine that joins mid-spawn draws it where it is. View only.
##
## The measures of a body every motion needs (how tall it is drawn, how far its art reaches under its
## feet) are here, with each body's `size_top` kept while it spawns in.

const VIEW_ONLY: bool = true

## The least height a body rises by, in pixels (so a rise is never fewer than this many frames).
const MIN_HEIGHT: float = 8.0
## Pixels added over a body's measured height, so nothing of it shows above the floor before it rises.
const HEIGHT_MARGIN: float = 2.0

## Each body's top from its body and its hurt shape (`size_top`) by instance id, worked out when it
## is first drawn and again only if its size changes mid-spawn (`Actor.set_size` is what moves
## them), and the size it was worked out at (apart: a Vector2 is float32, and the size is compared
## exactly); forgotten with the body (`forget`). Its sprite's terms are read every frame: its look's
## bob moves its art while it spawns in (`CreatureLook`, the sprite's offset).
var _size_top: Dictionary[int, float] = {}
var _size_top_measured_at: Dictionary[int, float] = {}


## Draw `body` at `share` (0 to 1) of its spawn as `style` says. Called every frame it spawns in.
func apply(_body: Actor, _share: float, _style: SpawnStyle) -> void:
	pass


## The body of instance id `key` spawns in no more: its own look back (`body` null: it is gone, so only
## forgotten).
func put_back(key: int, _body: Actor) -> void:
	forget(key)


## Forget what is kept of the body of instance id `key`.
func forget(key: int) -> void:
	_size_top.erase(key)
	_size_top_measured_at.erase(key)


## How tall `body` is drawn, in pixels from its feet (its size counted): the highest of its body
## sprite's top (`Sprite`, drawn at the body's scale), its hurt shape's top and twice its body's
## centre (both kept in pixels at its size, `Actor.set_size`), and a margin. (A layered body's art is
## in its `BodyPart`s, not its `Sprite`: only bosses are layered today, and they never spawn in.)
static func body_height(body: Actor) -> float:
	return height_from(body, size_top(body))


## The top of `body` from its body's centre and its hurt shape alone, in pixels from its feet: the
## part of `body_height` that, once it is in play, only its size moves (`Actor.set_size`; a prop's
## or a decoy's are set before it is added). A motion keeps it while the body spawns in, so anything
## that moved these mid-spawn without its size would have to be counted here (gameplay/feel/README.md).
static func size_top(body: Actor) -> float:
	var top: float = -2.0 * body.body_offset.y
	if body.hurtbox != null:
		top = maxf(top, -body.hurtbox.offset.y + body.hurtbox.outer_radius())
	return top


## `body_height` from its `size_top` and its body sprite as it is now.
static func height_from(body: Actor, top_of_size: float) -> float:
	var top: float = top_of_size
	var sprite := body.get_node_or_null(^"Sprite") as Sprite2D
	if sprite != null:
		top = maxf(top, -(sprite.position.y + sprite.get_rect().position.y * absf(sprite.scale.y)) * absf(body.size))
	return maxf(ceilf(top + HEIGHT_MARGIN), MIN_HEIGHT)


## How far below its feet `body`'s body sprite reaches, in whole pixels (0 for none above them): the
## rows a frame has under the feet's line (a spitter's).
static func body_bottom(body: Actor) -> float:
	var sprite := body.get_node_or_null(^"Sprite") as Sprite2D
	if sprite == null:
		return 0.0
	return maxf(ceilf((sprite.position.y + sprite.get_rect().end.y * absf(sprite.scale.y)) * absf(body.size)), 0.0)


## `body`'s `body_height`, its `size_top` as kept for `key` (its instance id): worked out the first
## time and whenever its size is not the one it was worked out at.
func height_of(body: Actor, key: int) -> float:
	return height_from(body, size_top_of(body, key))


func size_top_of(body: Actor, key: int) -> float:
	if _size_top_measured_at.get(key, NAN) == body.size:
		return _size_top[key]
	var top: float = size_top(body)
	_size_top[key] = top
	_size_top_measured_at[key] = body.size
	return top


## The `size_top` it keeps for `body` (NAN: none), and for how many bodies it keeps one (tests).
func size_top_kept(body: Actor) -> float:
	return _size_top.get(body.get_instance_id(), NAN)


func size_tops_kept() -> int:
	return _size_top.size()
