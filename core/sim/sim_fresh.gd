class_name SimFresh
extends RefCounted
## A run starts from a fresh game's state (online-ready N3b, docs/milestones/online-ready.md). When a
## run starts, `Tick.begin_run` calls each area's `begin_run`, which ends what the area holds (its
## `clear`) and then calls `SimFresh.renew(self)`: every state member takes the value a new object
## of the area's script has. Its clocks, counters, free lists, pools and the leftovers of its dead
## slots are then a fresh game's, so a run plays the same whatever ran before it, and a replay
## recorded in any run plays the same in any other. It is by construction, not by a list kept by
## hand: a member added later is reset too.
##
##     func begin_run() -> void:
##         clear()
##         SimFresh.renew(self)
##
## **The rules**, for each state member (what `StateWalk` walks: neither DERIVED nor VIEW):
## - **In `RUN_KEEPS`** (a setting of the session: the shot cap, a dev slider, a benchmark's budget):
##   kept. A list like DERIVED, read from the script and the scripts it extends, at every level.
## - **An object held by a member or in a dictionary** (a carrier, the kit, the AI board every brain
##   shares): the same object, taking the blank's object's members in turn, by these rules.
## - **An array:** the blank's, its objects too (a pool's items, which only the area holds). So never
##   keep an object in an array that something outside the area holds on to.
## - **What the blank shares, the area shares the same way:** each blank object stands for one object,
##   so a member that points into a pool (`Spells._ray`, the first of `_rays`) points into the pool
##   the area now has, and one back at the area (a kit's runtime) still points at the area.
## - **Anything else** (a value, a REFS member, a generator's seed and state): the blank's. A packed
##   array gets a buffer of its own: the native kernels write into the areas' arrays in place, past
##   copy-on-write.
## - **A node** is never taken from the blank (it is freed with it). One the area holds out of the
##   tree (a pool of bodies, as Entities' decoys) would be dropped and leak: `renew` fails with an
##   error naming it, and the area frees it first.
##
## DERIVED and VIEW are left alone: a cache that follows the state must be emptied by the area's
## `clear` (Combat's rows by node go as each row is freed). A blank that needs a setting before it is
## taken from (the projectile manager's cap: its arrays' size) gets it in `setup`. Making a blank
## changes no replay: nothing deals seeds behind the game's back (a run's seed is the frames
## service's to say, core/sim/frames.gd).

## Script to its REFS and RUN_KEEPS (cached: the lists are constants).
static var _refs: Dictionary[Script, PackedStringArray] = {}
static var _keeps: Dictionary[Script, PackedStringArray] = {}


## `area` (an object of a simulation script) as a fresh one of its script, but its RUN_KEEPS.
## `setup(blank)`, when given, readies the blank first. A problem (a node it would drop) is an error.
static func renew(area: Object, setup: Callable = Callable()) -> void:
	var blank: Object = blank_of(area.get_script() as Script)
	if setup.is_valid():
		setup.call(blank)
	var problems: PackedStringArray = take(area, blank)
	if blank is Node:
		(blank as Node).free()
	for problem in problems:
		push_error("SimFresh: %s" % problem)


## A new object of `script` to take from. `renew` makes, uses and frees it.
static func blank_of(script: Script) -> Object:
	return script.new()


## Every state member of `target` as in `blank` (a new object of the same script), by the rules
## above. Returns the problems: each node out of the tree it dropped (a leak), by member. `renew`
## is what an area calls; this is for a blank held on to (tests).
static func take(target: Object, blank: Object) -> PackedStringArray:
	var made: Dictionary[int, Object] = {}
	made[blank.get_instance_id()] = target
	var problems := PackedStringArray()
	_take(target, blank, made, {}, problems)
	return problems


## `target` takes `blank`'s members. `made`: each blank object to the object in its place; `taken`:
## the objects that took a blank's already.
static func _take(target: Object, blank: Object, made: Dictionary[int, Object], taken: Dictionary, problems: PackedStringArray) -> void:
	taken[target.get_instance_id()] = true
	var script: Script = target.get_script() as Script
	if not _refs.has(script):
		_refs[script] = StateWalk.listed(script, "REFS")
		_keeps[script] = StateWalk.listed(script, "RUN_KEEPS")
	var refs: PackedStringArray = _refs[script]
	var keeps: PackedStringArray = _keeps[script]
	for name: String in StateWalk.members(script):
		if keeps.has(name):
			continue
		var now: Variant = target.get(name)
		var fresh: Variant = blank.get(name)
		if refs.has(name):
			# Another's body: who the blank points at (no one), never entered.
			target.set(name, _copy(fresh, made))
			continue
		var result: Variant = _merged(now, fresh, made, taken, problems)
		if not is_same(result, now):
			_check_dropped(now, "%s: %s" % [_script_name(script), name], problems)
		target.set(name, result)


## `now` made like `fresh`: the same object or dictionary when it has the same shape, else a copy of
## `fresh`.
static func _merged(now: Variant, fresh: Variant, made: Dictionary[int, Object], taken: Dictionary, problems: PackedStringArray) -> Variant:
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
					_take(now, fresh, made, taken, problems)
				return now
		TYPE_DICTIONARY:
			var table: Dictionary = now
			var blank_table: Dictionary = fresh
			if table.size() == blank_table.size() and table.has_all(blank_table.keys()) and not table.is_read_only():
				for key: Variant in blank_table:
					table[key] = _merged(table[key], blank_table[key], made, taken, problems)
				return table
	return _copy(fresh, made)


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


## A problem for each node out of the tree in `now` (a node, or an array or dictionary of them) that
## is being replaced: nothing frees it after (a pool of bodies the area keeps out of the tree).
static func _check_dropped(now: Variant, where: String, problems: PackedStringArray) -> void:
	match typeof(now):
		TYPE_OBJECT:
			if now != null and is_instance_valid(now) and now is Node:
				var node: Node = now
				if node.get_parent() == null and not node.is_queued_for_deletion():
					problems.append("%s drops %s, a node out of the tree that nothing frees (it would leak); free it before `renew`" % [where, node.name])
		TYPE_ARRAY:
			var items: Array = now
			if not _may_hold_nodes(items):
				return
			for item: Variant in items:
				_check_dropped(item, where, problems)
		TYPE_DICTIONARY:
			for item: Variant in (now as Dictionary).values():
				_check_dropped(item, where, problems)


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


## True for an array that may hold nodes: untyped, of arrays or dictionaries, or typed to a node class.
static func _may_hold_nodes(items: Array) -> bool:
	if not items.is_typed():
		return true
	match items.get_typed_builtin():
		TYPE_ARRAY, TYPE_DICTIONARY:
			return true
		TYPE_OBJECT:
			return ClassDB.is_parent_class(items.get_typed_class_name(), &"Node")
	return false


static func _script_name(script: Script) -> String:
	return script.resource_path.get_file() if not script.resource_path.is_empty() else "an inner class"
