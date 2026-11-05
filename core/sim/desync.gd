class_name Desync
extends RefCounted
## The desync report (online-ready N1, docs/milestones/online-ready.md): given two runs, the first
## tick whose hashes part, which areas part, and each differing member by name with both values.
## Every determinism test uses it, and N2b, N8 and later the netcode will.
##
## A run is recorded tick by tick: `capture(areas)` after each tick, with the areas by name as
## `SimHash.areas` takes them. It keeps the hashes of every tick, and every leaf (path to value, as
## `StateWalk` hands them) of one tick only, `keep_tick`, since a whole run's leaves do not fit in
## memory. So a test records both runs with hashes only, and when they part (`first_parting`)
## records both again keeping that tick, and the report names the members.
##
##     var a := Desync.new()
##     var b := Desync.new()
##     ... run once, a.capture({"combat": combat, ...}) after each tick; again into b ...
##     var tick: int = Desync.first_parting(a, b)   # -1 when the runs agree at every tick
##     ... if tick >= 0: both runs again into Desync.new(tick) ...
##     var report: String = Desync.compare(a2, b2)

## How many differing members a report names at most.
const MAX_MEMBERS: int = 24

## The one tick whose leaves are kept, or -1 for none.
var keep_tick: int = -1
## Per tick: the areas' hashes, by name.
var hashes: Array[Dictionary] = []
## The kept tick's leaves, {area: {path: value}} (empty until it is captured).
var leaves: Dictionary = {}
## Every problem the walks met (StateWalk.problems), without repeats.
var problems: PackedStringArray = PackedStringArray()


func _init(keep: int = -1) -> void:
	keep_tick = keep


## Records one tick of `areas` ({name: object}).
func capture(areas: Dictionary) -> void:
	var keep: bool = hashes.size() == keep_tick
	var walk := StateWalk.new()
	# Paths only for the kept tick: building a string per leaf is most of a walk's time (a
	# determinism test took 101 s with them every tick, 28 s without).
	walk.with_paths = keep
	if not keep:
		hashes.append(SimHash.areas(areas, walk))
	else:
		var tick_hashes: Dictionary[String, int] = {}
		leaves = {}
		for name: Variant in areas:
			var kept: Dictionary = {}
			tick_hashes[String(name)] = SimHash.area(walk, String(name), areas[name] as Object, func(path: String, value: Variant) -> void: kept[path] = value)
			leaves[String(name)] = kept
		hashes.append(tick_hashes)
	for problem in walk.problems:
		if not problems.has(problem):
			problems.append(problem)


## The first tick at which `a` and `b` part (hashes differ, or one run is shorter), or -1.
static func first_parting(a: Desync, b: Desync) -> int:
	var ticks: int = mini(a.hashes.size(), b.hashes.size())
	for tick in ticks:
		if a.hashes[tick] != b.hashes[tick]:
			return tick
	return -1 if a.hashes.size() == b.hashes.size() else ticks


## The report: "" when the runs agree at every tick; else the first tick that parts, its areas and
## (when both kept that tick's leaves) each differing member with both values.
static func compare(a: Desync, b: Desync) -> String:
	var tick: int = first_parting(a, b)
	if tick < 0:
		return ""
	if tick >= a.hashes.size() or tick >= b.hashes.size():
		return "the runs agree for %d ticks, then one has %d ticks and the other %d" % [tick, a.hashes.size(), b.hashes.size()]
	var lines := PackedStringArray()
	var parted := PackedStringArray()
	var ha: Dictionary = a.hashes[tick]
	var hb: Dictionary = b.hashes[tick]
	for area: String in ha:
		if not hb.has(area) or ha[area] != hb[area]:
			parted.append(area)
	for area: String in hb:
		if not ha.has(area):
			parted.append(area)
	lines.append("the runs part at tick %d, in %s" % [tick, ", ".join(parted)])
	if a.keep_tick == tick and b.keep_tick == tick:
		var named: int = 0
		for area in parted:
			var la: Dictionary = a.leaves.get(area, {})
			var lb: Dictionary = b.leaves.get(area, {})
			for line in members_parting(la, lb):
				if named >= MAX_MEMBERS:
					lines.append("  ... and more")
					return "\n".join(lines)
				lines.append("  " + line)
				named += 1
	return "\n".join(lines)


## Each member that differs between two sets of leaves ({path: value}), as "path: a vs b", in the
## first set's order, then the paths only the second has.
static func members_parting(a: Dictionary, b: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for path: Variant in a:
		if not b.has(path):
			out.append("%s: %s vs (missing)" % [path, _shown(a[path])])
		elif not _same(a[path], b[path]):
			out.append("%s: %s" % [path, _difference(a[path], b[path])])
	for path: Variant in b:
		if not a.has(path):
			out.append("%s: (missing) vs %s" % [path, _shown(b[path])])
	return out


## Bit for bit: the same type and the same bytes, so -0.0 and 0.0, or two NaNs, are told apart
## (the hash tells them apart in a single value, not inside a packed array: see `SimHash`).
static func _same(x: Variant, y: Variant) -> bool:
	return typeof(x) == typeof(y) and var_to_bytes(x) == var_to_bytes(y)


static func _difference(x: Variant, y: Variant) -> String:
	if typeof(x) == typeof(y) and typeof(x) >= TYPE_PACKED_BYTE_ARRAY and typeof(x) <= TYPE_PACKED_VECTOR4_ARRAY:
		var xs: Variant = x
		var ys: Variant = y
		var n: int = mini(xs.size(), ys.size())
		for i in n:
			if not _same(xs[i], ys[i]):
				return "[%d] %s vs %s (size %d vs %d)" % [i, _shown(xs[i]), _shown(ys[i]), xs.size(), ys.size()]
		return "size %d vs %d" % [xs.size(), ys.size()]
	return "%s vs %s" % [_shown(x), _shown(y)]


static func _shown(value: Variant) -> String:
	if typeof(value) == TYPE_FLOAT:
		return "%.17g" % value
	var text: String = var_to_str(value)
	return text if text.length() <= 120 else text.substr(0, 117) + "..."
