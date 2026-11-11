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


## An area that keeps state by actor id, split for the hash (props W3). Its script lists those
## tables in BY_ACTOR (`StateWalk.has_by_actor`; Spells, by caster) and hands each actor's share of
## them over: `actor_parts() -> int` (ids 0 to it less one may have one) and `actor_part(id) -> Array`
## (empty for an id with none). The hash takes such an area as the area without them, under its own
## name, and one part for each actor id with a share, named after the area and the id ("Spells 7"),
## which `slice` puts with that actor's body ("actor 7"): a caster's state costs the tick its body
## is hashed in, and a check that differs names it. This class is the only caller of that protocol
## (`split_by_actor`, `slice`, `areas`); `of`, a walk of the area itself and a snapshot take it whole.
class ActorPart:
	extends RefCounted
	var area: Object = null
	## The area's own name ("Spells").
	var area_name: String = ""
	## The actor id, or -1 for the area without its BY_ACTOR members.
	var id: int = -1
	## The actor's share (`actor_part(id)`), as it was when this part was made: hash it straight
	## after (`areas(slice(...))`).
	var value: Array = []

	func _init(of: Object, named: String, at: int = -1, share: Array = []) -> void:
		area = of
		area_name = named
		id = at
		value = share

	## The name it is hashed under: the area's, or the area's and the id ("Spells 7").
	func name() -> String:
		return area_name if id < 0 else "%s %d" % [area_name, id]


## `named` with each area that keeps state by actor id as the area without it, then each actor's
## part ("Spells 7"), in the order given. Bodies (known by their names) and parts are left as they
## are.
static func split_by_actor(named: Dictionary) -> Dictionary:
	var any: bool = false
	for name: Variant in named:
		if _splits(String(name), named[name] as Object):
			any = true
			break
	if not any:
		return named
	var out: Dictionary = {}
	for name: Variant in named:
		var object: Object = named[name]
		if not _splits(String(name), object):
			out[name] = object
			continue
		out[name] = ActorPart.new(object, String(name))
		_add_actor_parts(out, object, String(name), 0, 1)
	return out


## Part `index` (0 to `slices` - 1) of the areas `named` (`Tick.state_areas`), so a check of the
## whole state can be spread over `slices` ticks (N3c: hashing it all in one tick took tens of
## milliseconds in a crowd; a netcode checking once a second hashes part `count % 60` each tick, and
## every machine hashes the same part at the same tick). The areas that are not bodies go one to a
## part, spread evenly in the order given; a body ("actor 7") goes to part `id % slices`, and so
## does each actor's part of an area ("Spells 7", `ActorPart`). Each is in exactly one part.
static func slice(named: Dictionary, index: int, slices: int) -> Dictionary:
	if slices <= 1:
		return split_by_actor(named)
	var services: int = 0
	for name: Variant in named:
		if not String(name).begins_with(BODY_PREFIX) and not _is_actor_part(named[name] as Object):
			services += 1
	var out: Dictionary = {}
	var spread: int = 0
	for name: Variant in named:
		var text: String = String(name)
		var object: Object = named[name]
		var at: int
		if text.begins_with(BODY_PREFIX):
			at = posmod(int(text.trim_prefix(BODY_PREFIX)), slices)
		elif _is_actor_part(object):
			at = posmod((object as ActorPart).id, slices)
		else:
			at = floori(float(spread) * float(slices) / float(services))
			spread += 1
		var splits: bool = _splits(text, object)
		if at == index:
			out[name] = ActorPart.new(object, text) if splits else object
		if splits:
			# Only this slice's actors: ids `index`, `index + slices` ...
			_add_actor_parts(out, object, text, index, slices)
	return out


## Each area's hash, by name, in the order given (an area that keeps state by actor id as its parts,
## `split_by_actor`). Problems go to `walk.problems`: a walk of the caller's (with its own settings;
## paths off is several times faster), or one of its own without paths. With `sink`, every leaf is
## handed to `sink(area, path, value)` too (the desync report keeps a tick's leaves so).
static func areas(named: Dictionary, walk: StateWalk = null, sink: Callable = Callable()) -> Dictionary[String, int]:
	if walk == null:
		walk = StateWalk.new()
		walk.with_paths = false
	var out: Dictionary[String, int] = {}
	var all: Dictionary = split_by_actor(named)
	for name: Variant in all:
		var text: String = String(name)
		var also: Callable = Callable()
		if sink.is_valid():
			also = func(path: String, value: Variant) -> void: sink.call(text, path, value)
		out[text] = area(walk, text, all[name] as Object, also)
	return out


## One area's hash by `walk`: an area (whole, even one that keeps state by actor id), or an
## `ActorPart` of one. With `also`, every leaf is handed to `also(path, value)` too; the walk's
## `with_paths` says whether paths are built. Without `also`, the walk appends the leaves' values
## itself (`StateWalk.values`), with no call per leaf: the hash is the same either way.
static func area(walk: StateWalk, name: String, object: Object, also: Callable = Callable()) -> int:
	var values: Array = []
	var sink: Callable = Callable()
	if also.is_valid():
		sink = func(path: String, value: Variant) -> void:
			add_leaf(values, value)
			also.call(path, value)
	if object is ActorPart and (object as ActorPart).id >= 0:
		# One actor's share: a value the area handed over, walked as its member would be.
		var part: ActorPart = object
		if sink.is_valid():
			walk.walk_value(name, part.value, part.area, sink)
		else:
			walk.values_of(name, part.value, part.area, values)
	elif object is ActorPart:
		var rest: Object = (object as ActorPart).area
		if sink.is_valid():
			walk.walk(name, rest, sink, true)
		else:
			walk.values(name, rest, values, true)
	elif sink.is_valid():
		walk.walk(name, object, sink)
	else:
		walk.values(name, object, values)
	return of_leaves(values)


## Whether the area `name` keeps state by actor id: its script lists BY_ACTOR. A body is never
## asked (it is one actor's already; known by its name), nor a part.
static func _splits(name: String, object: Object) -> bool:
	if name.begins_with(BODY_PREFIX) or object is ActorPart or not is_instance_valid(object):
		return false
	return StateWalk.has_by_actor(object.get_script() as Script)


## Adds to `out` the parts of `object` (the area `area`) for the actor ids `from`, `from + step` ...
## that have a share: an id with none is no area (both machines agree; one with a share where the
## other has none differs in the check).
static func _add_actor_parts(out: Dictionary, object: Object, area: String, from: int, step: int) -> void:
	for id in range(from, int(object.call(&"actor_parts")), step):
		var share: Array = object.call(&"actor_part", id)
		if not share.is_empty():
			var part := ActorPart.new(object, area, id, share)
			out[part.name()] = part


static func _is_actor_part(object: Object) -> bool:
	return object is ActorPart and (object as ActorPart).id >= 0


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


## One object's hash (an area alone, whole: its parts too).
static func of(object: Object) -> int:
	var walk := StateWalk.new()
	walk.with_paths = false
	return area(walk, "area", object)
