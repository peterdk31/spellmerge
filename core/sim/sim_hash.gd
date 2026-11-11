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


## A part of an area that keeps state by actor id (props W3): an area whose script lists members in
## PARTED (`StateWalk.has_parted`; Spells, by caster) is hashed as the area less those members,
## under its own name, and one part for each actor id that has a share of them (`state_part(id)` not
## empty, ids 0 to `state_parts()` less one), named after the area and the id ("Spells 7"), which
## `slice` puts in the part of that actor's body. A caster's state then costs the tick its body is
## hashed in, and a check that parts names it. `parted`, `slice` and `areas` make the parts; `of`, a
## walk of the area itself and a snapshot take it whole.
class Part:
	extends RefCounted
	var area: Object = null
	## The area's own name ("Spells").
	var area_name: String = ""
	## The actor id, or `StateWalk.LESS_PARTED` for the area less its PARTED members.
	var id: int = StateWalk.LESS_PARTED

	func _init(of: Object, named: String, at: int) -> void:
		area = of
		area_name = named
		id = at

	## The name it is hashed under: the area's, or the area's and the id ("Spells 7").
	func name() -> String:
		return area_name if id < 0 else "%s %d" % [area_name, id]


## Whether `object` is an area hashed by parts (`Part`): its script lists PARTED. A body is not asked
## (it is one actor's already): `parted` and `slice` know the bodies by their names.
static func has_parts(object: Object) -> bool:
	return object != null and StateWalk.has_parted(object.get_script() as Script)


## `named` with each area that has parts as the area less them, then each of its parts ("Spells
## 7"), in the order given. An area already a `Part` stays as it is.
static func parted(named: Dictionary) -> Dictionary:
	var any: bool = false
	for name: Variant in named:
		if not String(name).begins_with(BODY_PREFIX) and has_parts(named[name] as Object):
			any = true
			break
	if not any:
		return named
	var out: Dictionary = {}
	for name: Variant in named:
		var object: Object = named[name]
		if String(name).begins_with(BODY_PREFIX) or not has_parts(object):
			out[name] = object
			continue
		out[name] = Part.new(object, String(name), StateWalk.LESS_PARTED)
		_add_parts(out, object, String(name), 0, 1)
	return out


## Part `slice` (0 to `slices` - 1) of the areas `named` (`Tick.state_areas`), so a check of the
## whole state can be spread over `slices` ticks (N3c: hashing it all in one tick took tens of
## milliseconds in a crowd; a netcode checking once a second hashes part `count % 60` each tick, and
## every machine hashes the same part at the same tick). The areas that are not bodies go one to a
## part, spread evenly in the order given; a body ("actor 7") goes to part `id % slices`, and so
## does each area's part for that id ("Spells 7", `Part`). Each area and part is in exactly one part.
static func slice(named: Dictionary, part: int, slices: int) -> Dictionary:
	if slices <= 1:
		return parted(named)
	var services: int = 0
	for name: Variant in named:
		if not String(name).begins_with(BODY_PREFIX) and not _is_id_part(named[name] as Object):
			services += 1
	var out: Dictionary = {}
	var index: int = 0
	for name: Variant in named:
		var text: String = String(name)
		var object: Object = named[name]
		var at: int
		var parts: bool = false
		if text.begins_with(BODY_PREFIX):
			at = posmod(int(text.trim_prefix(BODY_PREFIX)), slices)
		elif _is_id_part(object):
			at = posmod((object as Part).id, slices)
		else:
			at = floori(float(index) * float(slices) / float(services))
			index += 1
			parts = has_parts(object)
		if at == part:
			out[name] = Part.new(object, text, StateWalk.LESS_PARTED) if parts else object
		if parts:
			# Only this slice's parts are made: ids `part`, `part + slices` ...
			_add_parts(out, object, text, part, slices)
	return out


## Each area's hash, by name, in the order given (an area with parts as its parts, `parted`).
## Problems go to `walk.problems`: a walk of the caller's (with its own settings; paths off is
## several times faster), or one of its own without paths. With `also`, every leaf is handed to
## `also(area, path, value)` too (the desync report keeps a tick's leaves so).
static func areas(named: Dictionary, walk: StateWalk = null, also: Callable = Callable()) -> Dictionary[String, int]:
	if walk == null:
		walk = StateWalk.new()
		walk.with_paths = false
	var out: Dictionary[String, int] = {}
	var all: Dictionary = parted(named)
	for name: Variant in all:
		var text: String = String(name)
		var leaves: Callable = Callable()
		if also.is_valid():
			leaves = func(path: String, value: Variant) -> void: also.call(text, path, value)
		out[text] = area(walk, text, all[name] as Object, leaves)
	return out


## What a hashed area is reported as (the benchmarks' costliest areas): an area's parts together
## ("Spells parts"), anything else by its name.
static func label(name: String, object: Object) -> String:
	return "%s parts" % (object as Part).area_name if _is_id_part(object) else name


## Adds to `out` the parts of `object` (an area named `area`) for the ids `from`, `from + step` ...
## that have a share of its PARTED members: an id with an empty part is no area (both machines agree
## on that; one with a part where the other has none parts the check).
static func _add_parts(out: Dictionary, object: Object, area: String, from: int, step: int) -> void:
	for id in range(from, int(object.call(&"state_parts")), step):
		if not (object.call(&"state_part", id) as Array).is_empty():
			var part := Part.new(object, area, id)
			out[part.name()] = part


static func _is_id_part(object: Object) -> bool:
	return object is Part and (object as Part).id >= 0


## One area's hash by `walk` (an area, or one `Part` of one; an area with parts handed whole is
## hashed whole). With `also`, every leaf is handed to `also(path, value)` too (the
## desync report keeps a tick's leaves so); the walk's `with_paths` says whether paths are built.
## Without `also`, the walk appends the leaves' values itself (`StateWalk.values`), with no call per
## leaf: the hash of the whole is the same either way.
static func area(walk: StateWalk, name: String, object: Object, also: Callable = Callable()) -> int:
	var values: Array = []
	var of: Object = object
	var part: int = StateWalk.WHOLE
	if object is Part:
		of = (object as Part).area
		part = (object as Part).id
	if also.is_valid():
		walk.walk(name, of, func(path: String, value: Variant) -> void:
			add_leaf(values, value)
			also.call(path, value), part)
	else:
		walk.values(name, of, values, part)
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


## One object's hash (an area alone, whole: its parts too).
static func of(object: Object) -> int:
	var walk := StateWalk.new()
	walk.with_paths = false
	return area(walk, "area", object)
