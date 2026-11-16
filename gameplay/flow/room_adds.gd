class_name RoomAdds
extends RefCounted
## The adds standing in the room (boss plan OB13, docs/milestones/boss-old-broom.md, "Phase adds and
## player-count scaling"): each add Flow stood for a body's phase (`adds_requested`), with the body
## that called it and which of its entries it is (`Phases.adds_key`), so the entry's cap counts those
## alive (`alive`) and the adds crumble when their caller dies (`orphan`, then `orphans`). Where they
## stand is worked out here too (`ring`). Flow's state (it holds one); the adds are also among
## Flow's enemies, so the room is cleared only when they are down.

## Pixels between the caller's hurt shape and an add's body on the ring.
const RING_GAP: float = 10.0
## Radians each add stood before turns the next call's ring (about 137.5°, the golden angle: no two
## calls stand on the same spots).
const RING_TURN: float = 2.399963

## State as who they point at (core/sim/README.md).
const REFS: Array[StringName] = [&"adds", &"callers"]

## The adds standing, in the order they stood.
var adds: Array[Node] = []
## The body that called each (null once it died: the add crumbles).
var callers: Array[Node] = []
## Which of its caller's entries each is.
var keys: PackedInt32Array = PackedInt32Array()
## How many have stood in the room (the next to stand at the room's spawns takes the spawn after).
var stood: int = 0


## The add `add` stood for `caller`'s entry `key`.
func track(add: Node, caller: Node, key: int) -> void:
	adds.append(add)
	callers.append(caller)
	keys.append(key)
	stood += 1


## How many of `caller`'s entry `key` are alive (an add freed without a death told is not).
func alive(caller: Node, key: int) -> int:
	var found: int = 0
	for i in adds.size():
		if callers[i] == caller and keys[i] == key and is_instance_valid(adds[i]):
			found += 1
	return found


## True while an add has no caller (it is to crumble), or went without a death told (it is to be
## forgotten): Flow's step asks it first, so a room with no adds allocates nothing.
func has_orphans() -> bool:
	for i in adds.size():
		if callers[i] == null or not is_instance_valid(adds[i]):
			return true
	return false


## The body `body` is gone: forget it as an add, and every add it called has no caller now.
func orphan(body: Node) -> void:
	var at: int = adds.find(body)
	if at >= 0:
		adds.remove_at(at)
		callers.remove_at(at)
		keys.remove_at(at)
	for i in callers.size():
		if callers[i] == body:
			callers[i] = null


## The adds whose caller is gone, in the order they stood (they crumble), and those freed without a
## death told (null: Flow forgets them).
func orphans() -> Array[Node]:
	var found: Array[Node] = []
	for i in adds.size():
		if not is_instance_valid(adds[i]):
			found.append(null)
		elif callers[i] == null:
			found.append(adds[i])
	return found


## Forget every add freed without a death told; returns how many.
func forget_gone() -> int:
	var gone: int = 0
	for i in range(adds.size() - 1, -1, -1):
		if not is_instance_valid(adds[i]):
			adds.remove_at(i)
			callers.remove_at(i)
			keys.remove_at(i)
			gone += 1
	return gone


## Every add forgotten (the room's enemies went).
func clear() -> void:
	adds.clear()
	callers.clear()
	keys.clear()
	stood = 0


## Where the `n`-th of `of` adds stands on a ring round `centre`, a caller whose hurt shape reaches
## `caller_reach`, for an add of `radius`: evenly spaced, the first turned by `turn` from straight
## down (the adds stood before, so a wave does not stand on the burst), slid out from the
## middle against the walls (`slide`, the projectile manager's `slide_body`), so none stands in a
## wall or a blocking prop.
static func ring(centre: Vector2, caller_reach: float, radius: float, n: int, of: int, slide: Callable, turn: int = 0) -> Vector2:
	var angle: float = TAU * float(n) / float(maxi(of, 1)) + RING_TURN * float(turn)
	var out: Vector2 = DMath.rotated(Vector2.DOWN, angle) * (caller_reach + radius + RING_GAP)
	return slide.call(centre, out, radius) if slide.is_valid() else centre + out
