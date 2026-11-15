class_name DepthWords
extends RefCounted
## The words for a depth of the stone's run (run generation RG7): what the lectern's menu lists and
## the stone line says. `depth` of the `depths` the lectern offers (`start_depth_changed`): 0 is
## "Room 1", the map's first room, and the last of them "The boss", the map's last row; between, the
## room of that row ("Room 2", ...).

const BOSS_TEXT: String = "The boss"
const ROOM_TEXT: String = "Room %d"


## The words for `depth` of `depths`.
static func of(depth: int, depths: int) -> String:
	if depth > 0 and depth >= depths - 1:
		return BOSS_TEXT
	return ROOM_TEXT % (maxi(depth, 0) + 1)
