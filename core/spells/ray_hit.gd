class_name RayHit
extends RefCounted
## What a hit with no shot slot carries (a beam's ray, a swing's sweep, a slam's ring, a dash's
## pass, a rain's strike, a zap or a chain jump of any of them): the projectile manager sends such
## a hit with `event_slot` -1, so `Spells` reads what it is from the ray being sent instead. One
## record per nesting level (a hit handler may send another ray), kept in `Spells`' stack and
## reused, so sending a ray allocates nothing (`Spells._ray_begin`, `_ray_end`).

## The tag of the carrier whose ray is being sent (0 for none: no hit matches it).
var tag: int = 0
## The way the ray goes at the body being hit: a payload fired by the hit leaves along it.
var dir: Vector2 = Vector2.ZERO
## Chain jumps the hit still has, and the target it jumped from (instance id, 0 for none).
var chain: int = 0
var prev: int = 0
## What the hit does when it is not its spell's own `hit` (null): an echo's half, a zap's share,
## what the hit a jump came from hit with, or what `relay` took on while the ray is out.
var hit: HitProfile = null
## The slot of the shot whose zap this is (-1 for none): the zap is a hit of that shot.
var arc_slot: int = -1


func set_to(ray_tag: int, way: Vector2, jumps: int, from: int, with: HitProfile, zap_slot: int) -> void:
	tag = ray_tag
	dir = way
	chain = jumps
	prev = from
	hit = with
	arc_slot = zap_slot
