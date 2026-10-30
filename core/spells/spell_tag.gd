class_name SpellTag
extends RefCounted
## The int `tag` every shot carries, which is how a hit finds its spell (staffs A5,
## docs/milestones/M2-staffs.md, "Tags"; one caster field since actors G2,
## docs/milestones/M2-actors.md, "Tags"). It packs the staff (0-3: the A, X, Y and B buttons) in
## bits 0-1, a generation (0-7, a ring that advances on each build change of that staff) in bits
## 2-4, the node (0-511: the compiled spell's index in its staff's cycle, `CompiledSpell.node`)
## in bits 5-13 and the caster (0-1023, `caster_of`; 10 bits since Horde H1) in bits 14-23,
## under `FLAG` (bit 24). `FLAG` sits above every enemy attack tag of gameplay/ai (1,000 to
## 101,000), so the two never meet, and keeps every tag above 0, which means "no tag" to
## `gameplay/combat`. Every tag stays below `FLAG << 1` (1 << 25), well under `LIMIT` (1 << 29),
## so it fits the int32 arrays combat keeps shield tags in.
##
## The caster is the actor id (`core/actors`) of whoever cast it, the number the spell runtime
## and the projectile manager keep every caster under (actors G3b). Nothing reads a seat, a
## side or a colour out of it: those are the actor table's.
##
##     var tag: int = SpellTag.make(caster, staff, node, generation)
##     SpellTag.caster_of(tag)  # the other fields read back the same way

const FLAG: int = 1 << 24
const STAFF_SHIFT: int = 0
const GENERATION_SHIFT: int = 2
const NODE_SHIFT: int = 5
const CASTER_SHIFT: int = 14
## The largest node a tag holds; a cycle never makes more spells than this plus one.
const NODE_MASK: int = 511
## The largest caster a tag holds: every actor id (`Actors.ACTORS` is 1024).
const CASTER_MASK: int = 1023
## Every spell tag is below this.
const LIMIT: int = 1 << 29


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

