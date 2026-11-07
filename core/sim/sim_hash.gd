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

## What a body's name starts with in a state's areas (`Tick.state_areas`: "actor 7").
const BODY_PREFIX: String = "actor "


## Part `slice` (0 to `slices` - 1) of the areas `named` (`Tick.state_areas`), so a check of the
## whole state can be spread over `slices` ticks (N3c: hashing it all in one tick took tens of
## milliseconds in a crowd; a netcode checking once a second hashes part `count % 60` each tick, and
## every machine hashes the same part at the same tick). The areas that are not bodies go one to a
## part, spread evenly in the order given; a body ("actor 7") goes to part `id % slices`. Each
## area is in exactly one part.
static func slice(named: Dictionary, part: int, slices: int) -> Dictionary:
	if slices <= 1:
		return named
	var services: int = 0
	for name: Variant in named:
		if not String(name).begins_with(BODY_PREFIX):
			services += 1
	var out: Dictionary = {}
	var index: int = 0
	for name: Variant in named:
		var text: String = String(name)
		var at: int
		if text.begins_with(BODY_PREFIX):
			at = posmod(int(text.trim_prefix(BODY_PREFIX)), slices)
		else:
			at = floori(float(index) * float(slices) / float(services))
			index += 1
		if at == part:
			out[name] = named[name]
	return out


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
			add_leaf(values, value)
			also.call(path, value))
	else:
		walk.values(name, object, values)
	return of_leaves(values)


## The 64-bit hash of a list of leaves (`add_leaf`): of its bytes.
static func of_leaves(values: Array) -> int:
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


## One leaf as it is hashed, appended to `into`: a packed or typed array as its type, size and the
## engine's `hash()` of it (one call, no copy of its bytes: 6,000 shots' arrays are megabytes; three
## values, no array made for them, N3c), anything else as it is. An area's leaves are hashed
## together, by the bytes of the array of them (`var_to_bytes`).
static func add_leaf(into: Array, value: Variant) -> void:
	var type: int = typeof(value)
	if type >= TYPE_PACKED_BYTE_ARRAY or type == TYPE_ARRAY:
		into.append(type)
		into.append((value as Variant).size())
		into.append(hash(value))
	else:
		into.append(value)


## One object's hash (an area alone).
static func of(object: Object) -> int:
	return areas({"area": object})["area"]
