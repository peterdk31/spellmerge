class_name RoomSocket
extends Node2D
## A socket on a template's lip (connected biomes CB2, docs/milestones/connected-biomes.md, decision
## 2): where a bridge (or another walkway) may meet the template in a biome. Add one to a room's scene
## (Add Child Node, "RoomSocket"; a room keeps them at its scene's top level, `SocketEast` and so on, so `tools/ground_shape.py`, which keeps cracks clear of every node under a group, draws its ground as before; the bridge keeps them under `Sockets`) at the middle of its
## mouth on the slab's lip, on the 32 px grid (`PieceShape.GRID`), and pick the way it faces: out of
## the slab, the way a bridge leaves it. Its mouth is MOUTH pixels wide across that way. A walkway
## (`RoomBase.walkway`) has its sockets on its own edge, at its ends.
##
## A socket a biome joins is cut open (`PieceShape.cut_rect`) and a mouth laid just outside it
## (`PieceShape.mouth_rect`, `RoomGrid.MOUTH_CELL`), where shots stop and wizards walk through; an
## unused socket stays lip. In the editor a `SocketPreview` (tools/) draws every socket's mouth, red
## where it breaks a rule. The game reads it (`RoomPlaces.sockets`) and never shows it: it is taken
## out before play as placements are (`RoomPlaces.strip`). A plain node, no editor script.

## The ways a socket faces, out of the slab.
enum Facing { NORTH, EAST, SOUTH, WEST }

## The width of a mouth, across the way it faces, in pixels.
const MOUTH: float = 64.0

## The way it faces, out of the slab.
@export var facing: Facing = Facing.EAST


## The way `facing` points, a whole unit vector (y grows down).
static func way(facing: int) -> Vector2:
	match facing:
		Facing.NORTH:
			return Vector2.UP
		Facing.EAST:
			return Vector2.RIGHT
		Facing.SOUTH:
			return Vector2.DOWN
	return Vector2.LEFT


## The facing opposite `facing` (a bridge's socket faces the room socket it meets).
static func opposite(facing: int) -> int:
	return (facing + 2) % 4


## The facing `facing` becomes when its piece is mirrored by `mirror` (`PieceShape.MIRROR_X`,
## `MIRROR_Y`): east and west swap across, north and south up and down.
static func mirrored(facing: int, mirror: int) -> int:
	if (mirror & PieceShape.MIRROR_X) != 0 and (facing == Facing.EAST or facing == Facing.WEST):
		return opposite(facing)
	if (mirror & PieceShape.MIRROR_Y) != 0 and (facing == Facing.NORTH or facing == Facing.SOUTH):
		return opposite(facing)
	return facing


## The facing's name, for a problem's line.
static func name_of(facing: int) -> String:
	return ["north", "east", "south", "west"][clampi(facing, 0, 3)]
