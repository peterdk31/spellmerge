class_name SpellTag
extends RefCounted
## The int `tag` every shot carries, which is how a hit finds its spell (staffs A5,
## docs/milestones/M2-staffs.md, "Tags"; one caster field since actors G2,
## docs/milestones/M2-actors.md, "Tags"). It packs the staff (0-3: the A, X, Y and B buttons) in
## bits 0-1, a generation (0-7, a ring that advances on each build change of that staff) in bits
## 2-4, the node (0-511: the compiled spell's index in its staff's cycle, `CompiledSpell.node`)
## in bits 5-13 and the caster (0-511, `caster_of`) in bits 14-22, under `FLAG` (bit 23). `FLAG`
## sits above every enemy attack tag of gameplay/ai (1,000 to 101,000), so the two never meet,
## and keeps every tag above 0, which means "no tag" to `gameplay/combat`. Every tag stays below
## `LIMIT` (1 << 29), so it fits the int32 arrays combat keeps shield tags in.
##
## The caster is the number the spell runtime casts under. Until actors G3b that is still a
## player (0-3) or `FIRST_ENEMY_CASTER` plus an enemy row (4-259), and the deprecated helpers
## below read it that way; from G3b it is the actor id (`core/actors`).
##
##     var tag: int = SpellTag.make(caster, staff, node, generation)
##     SpellTag.caster_of(tag)  # the other fields read back the same way

const FLAG: int = 1 << 23
const STAFF_SHIFT: int = 0
const GENERATION_SHIFT: int = 2
const NODE_SHIFT: int = 5
const CASTER_SHIFT: int = 14
## The largest node a tag holds; a cycle never makes more spells than this plus one.
const NODE_MASK: int = 511
## The largest caster a tag holds: every actor id (`Actors.ACTORS` is 512).
const CASTER_MASK: int = 511
## Every spell tag is below this.
const LIMIT: int = 1 << 29
## Deprecated (actors G3): the caster number of enemy row 0; 0-3 are the players.
const FIRST_ENEMY_CASTER: int = 4
## Deprecated (actors G3): the largest enemy row; there are `ROW_MASK + 1` enemy casters.
const ROW_MASK: int = 255
## Deprecated (actors G3): `Events.NO_PLAYER`, the player of an enemy's spell.
const NO_PLAYER: int = -1


## The tag of a shot. Arguments outside their range are wrapped into it, never an error.
static func make(caster: int, staff: int, node: int, generation: int) -> int:
	return FLAG \
		| ((staff & 3) << STAFF_SHIFT) \
		| ((generation & 7) << GENERATION_SHIFT) \
		| ((node & NODE_MASK) << NODE_SHIFT) \
		| ((caster & CASTER_MASK) << CASTER_SHIFT)


## Who cast it: the caster given to `make`.
static func caster_of(tag: int) -> int:
	return (tag >> CASTER_SHIFT) & CASTER_MASK


## True for a tag made by `make`.
static func is_spell_tag(tag: int) -> bool:
	return tag >= FLAG and tag < LIMIT


static func staff_of(tag: int) -> int:
	return (tag >> STAFF_SHIFT) & 3


static func node_of(tag: int) -> int:
	return (tag >> NODE_SHIFT) & NODE_MASK


static func generation_of(tag: int) -> int:
	return (tag >> GENERATION_SHIFT) & 7


## The tag with its node cleared: one key for every spell of one generation of one staff.
static func generation_key(tag: int) -> int:
	return tag & ~(NODE_MASK << NODE_SHIFT)


## Deprecated (actors G3): the same as `make`, which takes every caster now.
static func make_for(caster: int, staff: int, node: int, generation: int) -> int:
	return make(caster, staff, node, generation)


## Deprecated (actors G3): the tag of an enemy row's shot, `make` of `FIRST_ENEMY_CASTER` plus
## the row (wrapped into 0-255).
static func make_enemy(row: int, staff: int, node: int, generation: int) -> int:
	return make(FIRST_ENEMY_CASTER + (row & ROW_MASK), staff, node, generation)


## Deprecated (actors G3): true for a spell tag whose caster is an enemy row (4 and up).
static func is_enemy_tag(tag: int) -> bool:
	return is_spell_tag(tag) and caster_of(tag) >= FIRST_ENEMY_CASTER


## Deprecated (actors G3): the player (0-3) who cast it, or `NO_PLAYER` for any other caster.
static func player_of(tag: int) -> int:
	var caster: int = caster_of(tag)
	return caster if caster < FIRST_ENEMY_CASTER else NO_PLAYER


## Deprecated (actors G3): the enemy row of an enemy's spell, or -1 for a player's.
static func row_of(tag: int) -> int:
	var caster: int = caster_of(tag)
	return caster - FIRST_ENEMY_CASTER if caster >= FIRST_ENEMY_CASTER else -1
