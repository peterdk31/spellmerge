class_name SpellTag
extends RefCounted
## The int `tag` every shot carries, which is how a hit finds its spell (staffs A5,
## docs/milestones/M2-staffs.md, "Tags"). It packs the player (0-3), the staff (0-3: the A, X,
## Y and B buttons), the node (0-511: the compiled spell's index in its staff's cycle,
## `CompiledSpell.node`) and a
## generation (0-7, a ring that advances on each build change of that staff). `FLAG` sits above
## every enemy attack tag of gameplay/ai (1,000 to 101,000), so the two never meet, and keeps
## every tag above 0, which means "no tag" to `gameplay/combat`.
##
##     var tag: int = SpellTag.make(player, staff, node, generation)
##     SpellTag.player_of(tag)  # the other fields read back the same way

const FLAG: int = 1 << 20
const PLAYER_SHIFT: int = 0
const STAFF_SHIFT: int = 2
const GENERATION_SHIFT: int = 4
const NODE_SHIFT: int = 7
## The largest node a tag holds; a cycle never makes more spells than this plus one.
const NODE_MASK: int = 511


## The tag of a shot. Arguments outside their range are wrapped into it, never an error.
static func make(player: int, staff: int, node: int, generation: int) -> int:
	return FLAG \
		| ((player & 3) << PLAYER_SHIFT) \
		| ((staff & 3) << STAFF_SHIFT) \
		| ((generation & 7) << GENERATION_SHIFT) \
		| ((node & NODE_MASK) << NODE_SHIFT)


## True for a tag made by `make`.
static func is_spell_tag(tag: int) -> bool:
	return tag >= FLAG and tag < FLAG << 1


static func player_of(tag: int) -> int:
	return (tag >> PLAYER_SHIFT) & 3


static func staff_of(tag: int) -> int:
	return (tag >> STAFF_SHIFT) & 3


static func node_of(tag: int) -> int:
	return (tag >> NODE_SHIFT) & NODE_MASK


static func generation_of(tag: int) -> int:
	return (tag >> GENERATION_SHIFT) & 7


## The tag with its node cleared: one key for every spell of one generation of one staff.
static func generation_key(tag: int) -> int:
	return tag & ~(NODE_MASK << NODE_SHIFT)
