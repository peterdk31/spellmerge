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
## An enemy's spell (staffs F3, "Enemy staffs") has `ENEMY_BIT` set and its enemy row (0-255)
## above the flag instead of a player: `caster_of` gives the caster (a player 0-3, or
## `FIRST_ENEMY_CASTER` plus the row) and `player_of` gives `NO_PLAYER`. Every tag stays below
## `LIMIT` (1 << 29), so it fits the int32 arrays combat keeps shield tags in.
##
##     var tag: int = SpellTag.make(player, staff, node, generation)
##     SpellTag.player_of(tag)  # the other fields read back the same way
##     var enemy_tag: int = SpellTag.make_enemy(row, staff, node, generation)

const FLAG: int = 1 << 20
const PLAYER_SHIFT: int = 0
const STAFF_SHIFT: int = 2
const GENERATION_SHIFT: int = 4
const NODE_SHIFT: int = 7
## The largest node a tag holds; a cycle never makes more spells than this plus one.
const NODE_MASK: int = 511
## Set on an enemy's spell tag (bits 16-19 are otherwise free).
const ENEMY_BIT: int = 1 << 16
## An enemy's row sits above the flag, in bits 21-28.
const ROW_SHIFT: int = 21
## The largest enemy row; there are `ROW_MASK + 1` enemy casters.
const ROW_MASK: int = 255
## The caster number of enemy row 0 (`caster_of`); 0-3 are the players.
const FIRST_ENEMY_CASTER: int = 4
## Every spell tag is below this.
const LIMIT: int = 1 << 29
## `Events.NO_PLAYER`, the player of an enemy's spell.
const NO_PLAYER: int = -1


## The tag of a shot. Arguments outside their range are wrapped into it, never an error.
static func make(player: int, staff: int, node: int, generation: int) -> int:
	return FLAG \
		| ((player & 3) << PLAYER_SHIFT) \
		| ((staff & 3) << STAFF_SHIFT) \
		| ((generation & 7) << GENERATION_SHIFT) \
		| ((node & NODE_MASK) << NODE_SHIFT)


## The tag of an enemy's shot, from its enemy row. Arguments are wrapped as in `make`.
static func make_enemy(row: int, staff: int, node: int, generation: int) -> int:
	return make(0, staff, node, generation) | ENEMY_BIT | ((row & ROW_MASK) << ROW_SHIFT)


## True for a tag made by `make` or `make_enemy`.
static func is_spell_tag(tag: int) -> bool:
	return tag >= FLAG and tag < LIMIT


## True for a tag made by `make_enemy`.
static func is_enemy_tag(tag: int) -> bool:
	return is_spell_tag(tag) and tag & ENEMY_BIT != 0


## The player who cast it, or `NO_PLAYER` for an enemy's spell.
static func player_of(tag: int) -> int:
	return NO_PLAYER if tag & ENEMY_BIT != 0 else (tag >> PLAYER_SHIFT) & 3


## The enemy row of an enemy's spell, or -1 for a player's.
static func row_of(tag: int) -> int:
	return (tag >> ROW_SHIFT) & ROW_MASK if tag & ENEMY_BIT != 0 else -1


## Who cast it: the player (0-3), or `FIRST_ENEMY_CASTER` plus the enemy row.
static func caster_of(tag: int) -> int:
	return FIRST_ENEMY_CASTER + row_of(tag) if tag & ENEMY_BIT != 0 else (tag >> PLAYER_SHIFT) & 3


static func staff_of(tag: int) -> int:
	return (tag >> STAFF_SHIFT) & 3


static func node_of(tag: int) -> int:
	return (tag >> NODE_SHIFT) & NODE_MASK


static func generation_of(tag: int) -> int:
	return (tag >> GENERATION_SHIFT) & 7


## The tag with its node cleared: one key for every spell of one generation of one staff.
static func generation_key(tag: int) -> int:
	return tag & ~(NODE_MASK << NODE_SHIFT)
