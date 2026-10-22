class_name SpellTag
extends RefCounted
## The int `tag` every shot carries, which is how a hit finds its spell. It packs the
## player (0-3), the slot (0 = A, 1 = B), the depth (0-2) and a generation (0-7, a ring
## that advances on each build change of that slot). A flag bit keeps every tag above 0,
## because 0 means "no tag" to `gameplay/combat`.
##
##     var tag: int = SpellTag.make(player, slot, depth, generation)
##     SpellTag.player_of(tag)  # the other fields read back the same way

const FLAG: int = 1 << 8
const PLAYER_SHIFT: int = 0
const SLOT_SHIFT: int = 2
const DEPTH_SHIFT: int = 3
const GENERATION_SHIFT: int = 5


## The tag of a shot. Arguments outside their range are wrapped into it, never an error.
static func make(player: int, slot: int, depth: int, generation: int) -> int:
	return FLAG \
		| ((player & 3) << PLAYER_SHIFT) \
		| ((slot & 1) << SLOT_SHIFT) \
		| ((depth & 3) << DEPTH_SHIFT) \
		| ((generation & 7) << GENERATION_SHIFT)


## True for a tag made by `make`.
static func is_spell_tag(tag: int) -> bool:
	return tag >= FLAG and tag < FLAG << 1


static func player_of(tag: int) -> int:
	return (tag >> PLAYER_SHIFT) & 3


static func slot_of(tag: int) -> int:
	return (tag >> SLOT_SHIFT) & 1


static func depth_of(tag: int) -> int:
	return (tag >> DEPTH_SHIFT) & 3


static func generation_of(tag: int) -> int:
	return (tag >> GENERATION_SHIFT) & 7
