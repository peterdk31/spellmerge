class_name SimHash
extends RefCounted
## The state hash (online-ready N1, docs/milestones/online-ready.md): one 64-bit hash per area and
## one for the whole game, from `StateWalk`. The caller hands it the areas by name (the tick does from
## N3; a test does now): areas never reach into each other. Two runs that agree hash the same, to
## the bit; every leaf is hashed by its bytes (`var_to_bytes`; a packed array by the engine's
## `hash()`, in one call), in the walker's fixed order.
##
## It runs only in tests, tools, replays and later the netcode (then once a second), never in a
## normal build's tick.
##
##     var hashes: Dictionary[String, int] = SimHash.areas({"combat": combat, "projectiles": shots})
##     var whole: int = SimHash.whole(hashes)

## The problems the last `areas` call met (StateWalk.problems).
static var problems: PackedStringArray = PackedStringArray()


## Each area's hash, by name, in the order given.
static func areas(named: Dictionary) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	var walk := StateWalk.new()
	walk.with_paths = false
	for name: Variant in named:
		var context := HashingContext.new()
		context.start(HashingContext.HASH_MD5)
		walk.walk(String(name), named[name] as Object, func(_path: String, value: Variant) -> void: feed(context, value))
		out[String(name)] = context.finish().decode_s64(0)
	problems = walk.problems
	return out


## The whole game's hash from the areas' (`areas`), in their order.
static func whole(hashes: Dictionary[String, int]) -> int:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_MD5)
	for name: String in hashes:
		context.update(name.to_utf8_buffer())
		context.update(var_to_bytes(hashes[name]))
	return context.finish().decode_s64(0)


## Feeds one leaf to `context`: a packed or typed array as the engine's `hash()` of it (one call, no
## copy of its bytes: 6,000 shots' arrays are megabytes), anything else by its bytes.
static func feed(context: HashingContext, value: Variant) -> void:
	var type: int = typeof(value)
	if type >= TYPE_PACKED_BYTE_ARRAY or type == TYPE_ARRAY:
		context.update(var_to_bytes(PackedInt64Array([type, (value as Variant).size(), hash(value)])))
	else:
		context.update(var_to_bytes(value))


## One object's hash (an area alone).
static func of(object: Object) -> int:
	return areas({"area": object})["area"]
