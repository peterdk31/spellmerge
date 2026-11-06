class_name SimHash
extends RefCounted
## The state hash (online-ready N1, docs/milestones/online-ready.md): one 64-bit hash per area and
## one for the whole game, from `StateWalk`. The caller hands it the areas by name (the tick does from
## N3; a test does now): areas never reach into each other. Two runs that agree hash the same; every
## leaf is hashed by its bytes (`var_to_bytes`), a packed array or a typed array of plain values by
## the engine's `hash()` in one call, in the walker's fixed order.
##
## One thing the bytes tell apart and `hash()` does not: inside a packed or typed array the engine
## hashes -0.0 as 0.0 and every NaN alike. Two runs that part only by the sign of a zero in an array
## hash the same; the desync report (`Desync`), which compares leaves byte for byte, still tells
## them apart.
##
## It runs only in tests, tools, replays and later the netcode (then once a second), never in a
## normal build's tick.
##
##     var walk := StateWalk.new()
##     walk.with_paths = false
##     var hashes: Dictionary[String, int] = SimHash.areas({"combat": combat, "projectiles": shots}, walk)
##     var whole: int = SimHash.whole(hashes)
##     assert(walk.problems.is_empty())


## Each area's hash, by name, in the order given. Problems go to `walk.problems`: a walk of the
## caller's (with its own settings; paths off is several times faster), or one of its own without
## paths.
static func areas(named: Dictionary, walk: StateWalk = null) -> Dictionary[String, int]:
	if walk == null:
		walk = StateWalk.new()
		walk.with_paths = false
	var out: Dictionary[String, int] = {}
	for name: Variant in named:
		out[String(name)] = area(walk, String(name), named[name] as Object)
	return out


## One area's hash by `walk`. With `also`, every leaf is handed to `also(path, value)` too (the
## desync report keeps a tick's leaves so); the walk's `with_paths` says whether paths are built.
## Without `also`, the walk appends the leaves' values itself (`StateWalk.values`), with no call per
## leaf: the hash of the whole is the same either way.
static func area(walk: StateWalk, name: String, object: Object, also: Callable = Callable()) -> int:
	var values: Array = []
	if also.is_valid():
		walk.walk(name, object, func(path: String, value: Variant) -> void:
			values.append(leaf(value))
			also.call(path, value))
	else:
		walk.values(name, object, values)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_MD5)
	context.update(var_to_bytes(values))
	return context.finish().decode_s64(0)


## The whole game's hash from the areas' (`areas`), in their order.
static func whole(hashes: Dictionary[String, int]) -> int:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_MD5)
	for name: String in hashes:
		context.update(name.to_utf8_buffer())
		context.update(var_to_bytes(hashes[name]))
	return context.finish().decode_s64(0)


## One leaf as it is hashed: a packed or typed array as its type, size and the engine's `hash()` of it
## (one call, no copy of its bytes: 6,000 shots' arrays are megabytes), anything else as it is. An
## area's leaves are hashed together, by the bytes of the array of them (`var_to_bytes`).
static func leaf(value: Variant) -> Variant:
	var type: int = typeof(value)
	if type >= TYPE_PACKED_BYTE_ARRAY or type == TYPE_ARRAY:
		return PackedInt64Array([type, (value as Variant).size(), hash(value)])
	return value


## One object's hash (an area alone).
static func of(object: Object) -> int:
	return areas({"area": object})["area"]
