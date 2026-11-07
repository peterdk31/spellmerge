class_name SimFresh
extends RefCounted
## A run starts from a fresh game's state (online-ready N3b, docs/milestones/online-ready.md): when
## a run starts (`Tick.begin_run`), each area takes every state member from a new object of its own
## script (`blank`), so its clocks, counters, free lists, pools and the leftovers of its dead slots
## are what a fresh game's are, and a replay recorded in any run plays the same in any other. It
## is by construction, not by a list kept by hand: a member added later is reset too.
##
## What is taken: every member `StateWalk` walks (`StateWalk.members`: not `DERIVED` nor `VIEW`;
## `REFS` too, as the blank's: nothing). An object the area keeps (a carrier, the AI board that every
## brain shares, a compiled kit), held by a member or in a dictionary of the same keys (the
## carriers by id), stays the same object and takes its members from the blank's object in its
## place, in turn. A generator takes the blank's seed and state. Anything else is the blank's,
## copied: a value, a packed array (into a buffer of its own: the native kernels write into the
## areas' arrays in place, past copy-on-write), an array and its objects (a pool's items, which only
## the area holds). What the blank shares, the area shares the same way: each blank object stands
## for one object (`made`), so a member that points into a pool (`Spells._ray`, the first of
## `_rays`) points into the pool the area now has.
##
## What is kept: the area's settings for the session (the shot cap, a benchmark's step budget, a
## dev slider), named in `keep`; and what is not state (services, caches, drawing). A node is never
## taken from the blank (it is freed with it): a member pointing back at the area keeps doing so. A
## node the area keeps out of the tree (a pool of bodies: Entities' decoys) is the area's to free
## before: dropped here, it would leak.
## An area whose blank needs a setting first (the cap: its arrays' size) sets it on the blank before.
##
##     var blank: Object = SimFresh.blank_of(get_script() as Script)
##     blank.call(&"set_cap", _cap)
##     SimFresh.take(self, blank, [&"work_per_step"])
##     blank.free()


## A new object of `script` to take from (`take`; free it after if it is a node): made with the
## run's seeds set aside (`SimSeed.aside`), so a blank that seeds itself deals the run none.
static func blank_of(script: Script) -> Object:
	var dealer: RandomNumberGenerator = SimSeed.aside()
	var blank: Object = script.new()
	SimSeed.back(dealer)
	return blank


## Script to its REFS (cached: the lists are constants).
static var _refs: Dictionary[Script, PackedStringArray] = {}


## Every state member of `target` as in `blank` (a new object of the same script), but those in
## `keep`.
static func take(target: Object, blank: Object, keep: Array[StringName] = []) -> void:
	var made: Dictionary[int, Object] = {}
	made[blank.get_instance_id()] = target
	_take(target, blank, keep, made, {})


## `target` takes `blank`'s members. `made`: each blank object to the object in its place; `taken`:
## the objects that took a blank's already.
static func _take(target: Object, blank: Object, keep: Array[StringName], made: Dictionary[int, Object], taken: Dictionary) -> void:
	taken[target.get_instance_id()] = true
	var script: Script = target.get_script() as Script
	if not _refs.has(script):
		_refs[script] = StateWalk.listed(script, "REFS")
	var refs: PackedStringArray = _refs[script]
	for name: String in StateWalk.members(script):
		if keep.has(StringName(name)):
			continue
		var fresh: Variant = blank.get(name)
		if refs.has(name):
			target.set(name, _copy(fresh, made))
		else:
			target.set(name, _merged(target.get(name), fresh, made, taken))


## `now` made like `fresh`: the same object, array or dictionary when it has the same shape, else a
## copy of `fresh`.
static func _merged(now: Variant, fresh: Variant, made: Dictionary[int, Object], taken: Dictionary) -> Variant:
	if typeof(fresh) == TYPE_OBJECT and fresh != null and is_instance_valid(fresh):
		var blank_object: Object = fresh
		if made.has(blank_object.get_instance_id()):
			return made[blank_object.get_instance_id()]
		if blank_object is Node:
			return now
	var type: int = typeof(now)
	if type != typeof(fresh):
		return _copy(fresh, made)
	match type:
		TYPE_OBJECT:
			# One object takes one blank's: one the area shares where the blank does not becomes two.
			if _same_kind(now, fresh) and not taken.has((now as Object).get_instance_id()):
				made[(fresh as Object).get_instance_id()] = now
				if now is RandomNumberGenerator:
					taken[(now as Object).get_instance_id()] = true
					(now as RandomNumberGenerator).seed = (fresh as RandomNumberGenerator).seed
					(now as RandomNumberGenerator).state = (fresh as RandomNumberGenerator).state
				else:
					_take(now, fresh, [], made, taken)
				return now
		TYPE_ARRAY:
			# An array is the blank's, its objects too (a pool's items: plain data, held by the
			# area alone), as one object each wherever the blank shares one.
			return _copy(fresh, made)
		TYPE_DICTIONARY:
			var table: Dictionary = now
			var blank_table: Dictionary = fresh
			if table.size() == blank_table.size() and table.has_all(blank_table.keys()) and not table.is_read_only():
				for key: Variant in blank_table:
					table[key] = _merged(table[key], blank_table[key], made, taken)
				return table
	return _copy(fresh, made)


## True for an array typed to hold plain values only (numbers, names, vectors, packed arrays): it
## holds no object, and is copied in one call.
static func _plain(items: Array) -> bool:
	if not items.is_typed():
		return false
	var type: int = items.get_typed_builtin()
	return type != TYPE_NIL and type != TYPE_OBJECT and type != TYPE_ARRAY and type != TYPE_DICTIONARY


## True for an array that may hold objects (untyped, or typed to a class): only such holds null.
static func _holds_objects(items: Array) -> bool:
	return not items.is_typed() or items.get_typed_builtin() == TYPE_OBJECT


## True when `now` takes its members from `fresh` in place: two live objects of one script that is
## not content (a resource from a file is data, and the blank's is taken), or two generators.
static func _same_kind(now: Variant, fresh: Variant) -> bool:
	if now == null or fresh == null or not is_instance_valid(now) or not is_instance_valid(fresh):
		return false
	var a: Object = now
	var b: Object = fresh
	if a is RandomNumberGenerator and b is RandomNumberGenerator:
		return true
	if a is Node or a is Resource:
		return false
	var script: Script = a.get_script() as Script
	return script != null and script == b.get_script()


## `value` as an area may keep it: a packed array in a buffer of its own, an array or a dictionary
## made again item by item, a blank object as the object in its place (`made`), or itself, taken
## over (the blank's, which nothing else holds), and never a node.
static func _copy(value: Variant, made: Dictionary[int, Object]) -> Variant:
	match typeof(value):
		TYPE_OBJECT:
			if value == null or not is_instance_valid(value):
				return null
			var object: Object = value
			if made.has(object.get_instance_id()):
				return made[object.get_instance_id()]
			if object is Node:
				return null
			made[object.get_instance_id()] = object
			return object
		TYPE_ARRAY:
			var blanks: Array = value
			if _plain(blanks) or (_holds_objects(blanks) and blanks.count(null) == blanks.size()):
				return blanks.duplicate(true)
			var items: Array = blanks.duplicate(false)
			for i in items.size():
				items[i] = _copy(items[i], made)
			return items
		TYPE_DICTIONARY:
			var table: Dictionary = (value as Dictionary).duplicate(false)
			for key: Variant in table:
				table[key] = _copy(table[key], made)
			return table
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
				TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, \
				TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			return value.slice(0)
	return value
