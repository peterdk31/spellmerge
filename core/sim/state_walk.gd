class_name StateWalk
extends RefCounted
## The one generic walker of the simulation's state (online-ready N1, docs/milestones/online-ready.md):
## the hash (`SimHash`), the desync report (`Desync`) and, from N10, save and load all walk the state
## through it, so no area writes hash or save code.
##
## **State by default.** Every member of a simulation script (a script in one of FOLDERS, or an inner
## class of one) is state, except the names it lists:
## - `DERIVED` (caches, references to services, scratch reused within a step, instance ids: anything
##   set up again or rebuilt from state), never walked;
## - `VIEW` (what only the drawing reads and writes: N9 draws the line), never walked;
## - `REFS` (references to bodies it does not own that are state all the same: an AI's target, the
##   body a shot is stuck to, the bodies a zap is due on): walked as **who** they point at and never
##   entered (`identity`): an actor by its id, anything else by what it is, until N5 gives every body
##   an identity of its own.
## A list is a constant `Array[StringName]` named after its kind, or after its kind and `_` and a
## name of the script's own (`DERIVED_BEAM`): a script that extends one with a list cannot declare
## the same constant again, so it names its own. The lists are read from the script and the scripts
## it extends. A script inside a simulation folder that is view as a whole (a look) says so with
## `const VIEW_ONLY: bool = true`: the walker never enters it, and a member holding one must be in
## VIEW.
##
## What a state member may hold, walked in turn:
## - a value (bool, int, float, a string, a vector, a colour, ...) or a packed array (one engine
##   call each, never element by element);
## - an array (element by element; a typed array of plain values in one call) or a dictionary (its
##   keys in sorted order, each key then its value);
## - an object of a script (an actor's intent, a compiled spell, a brain), walked member by member;
##   one met twice is walked once, and later meetings are the number of its first (in walk order);
## - a node of a simulation script that is the holder's own descendant (an actor's components), walked
##   too, with its `position` (and a body's `velocity`);
## - a reference to a simulation node it does not own that has an int `id` (an actor: a brain's
##   typed target actor): that id, as "actor.gd#7";
## - a resource from a file (content: a card, enemy data) or a scene: its path, since data cannot
##   desync;
## - a `RandomNumberGenerator`: its seed and state.
## Anything else is a **problem**, named by its path and what it holds: a node that is not the
## holder's own (a service: DERIVED; another area's body: REFS), a node of a script outside the
## simulation, a Callable, a Signal, an RID or another engine object (a mesh, a material).
## `tests/core/test_state_declared.gd` fails on any.
##
## It runs only in tests, tools, replays and later the netcode, never in a normal build's tick.
##
##     var walk := StateWalk.new()
##     walk.walk("combat", combat, func(path: String, value: Variant) -> void: print(path, " = ", value))
##     assert(walk.problems.is_empty())

## The simulation folders (core/sim/README.md lists the same, with why). `core/sim/` is not one:
## these tools read the simulation, they are not part of it.
const FOLDERS: Array[String] = [
	"res://core/actors/",
	"res://core/projectiles/",
	"res://core/spells/",
	"res://gameplay/actor/",
	"res://gameplay/ai/",
	"res://gameplay/combat/",
	"res://gameplay/coop/",
	"res://gameplay/flow/",
	"res://gameplay/horde/",
	"res://gameplay/player/",
]
## The kinds of list a simulation script may declare (see the class doc).
const LISTS: Array[String] = ["DERIVED", "VIEW", "REFS"]

## Each problem, as "path: what it holds; the fix".
var problems: PackedStringArray = PackedStringArray()
## Whether the sink is handed each leaf's path. Off for the hash, which needs only the values (and
## is several times faster without building a string per leaf); a problem then names its area only.
var with_paths: bool = true

var _sink: Callable
## Instance id to the order an object was first walked in (this walk).
var _seen: Dictionary[int, int] = {}

## Script to its state members (cached: the property lists do not change while the game runs).
static var _members: Dictionary[Script, PackedStringArray] = {}
## Script to which of its state members (as `_members` orders them) are REFS: 1, else 0.
static var _is_ref: Dictionary[Script, PackedByteArray] = {}


## Walks `object` (an area: a service, an actor table, a body) under the name `area`, handing every
## leaf to `sink(path, value)` in a fixed order. Problems are added to `problems`.
func walk(area: String, object: Object, sink: Callable) -> void:
	_sink = sink
	_seen.clear()
	# The area itself is walked as its own holder (a body or a service is the root of its area).
	_object(area, object, null, true)
	_sink = Callable()


## Whether `script` is a simulation script (in FOLDERS). An inner class has no path of its own and is
## told by the file that holds it, which the static checks know and the walk does not need.
static func is_simulation(script: Script) -> bool:
	if script == null:
		return false
	var path: String = script.resource_path
	for folder in FOLDERS:
		if path.begins_with(folder):
			return true
	return false


## Whether `script` (or a script it extends) says it is view as a whole (`VIEW_ONLY`).
static func is_view_only(script: Script) -> bool:
	var at: Script = script
	while at != null:
		if bool(at.get_script_constant_map().get("VIEW_ONLY", false)):
			return true
		at = at.get_base_script()
	return false


## The names `script` and the scripts it extends list in the lists of kind `list` (DERIVED, VIEW or
## REFS): every constant `Array[StringName]` named `list` or `list` + "_" + a name.
static func listed(script: Script, list: String) -> PackedStringArray:
	var out := PackedStringArray()
	var at: Script = script
	while at != null:
		var constants: Dictionary = at.get_script_constant_map()
		for constant: String in constants:
			if constant != list and not constant.begins_with(list + "_"):
				continue
			var names: Variant = constants[constant]
			if not (names is Array and (names as Array).get_typed_builtin() == TYPE_STRING_NAME):
				continue
			for item: Variant in names:
				if not out.has(String(item)):
					out.append(String(item))
		at = at.get_base_script()
	return out


## Every member `script` declares (and the scripts it extends), state or not, in declaration order.
## Static members are not in it: they belong to no object (the static checks of
## tests/core/test_state_declared.gd see them).
static func declared(script: Script) -> PackedStringArray:
	var out := PackedStringArray()
	for info: Dictionary in script.get_script_property_list():
		if int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			out.append(String(info["name"]))
	return out


## The state members of `script`: declared, less DERIVED and VIEW (REFS are state).
static func members(script: Script) -> PackedStringArray:
	if not _members.has(script):
		_plan(script)
	return _members[script]


## Who `value` points at, for a REFS member: null, "<freed>", an actor as "actor.gd#7", a resource
## from a file by its path, anything else by its script's file or its class. Never entered.
static func identity(value: Variant) -> Variant:
	if value == null:
		return null
	if not is_instance_valid(value):
		return "<freed>"
	var object: Object = value
	var script: Script = object.get_script() as Script
	var what: String = object.get_class()
	if script != null and not script.resource_path.is_empty():
		what = script.resource_path.get_file()
	if object is Resource and (object as Resource).resource_path.begins_with("res://"):
		return (object as Resource).resource_path
	var id: Variant = object.get(&"id")
	if typeof(id) == TYPE_INT:
		return "%s#%d" % [what, id]
	return what


static func _plan(script: Script) -> void:
	var skip: PackedStringArray = listed(script, "DERIVED") + listed(script, "VIEW")
	var refs: PackedStringArray = listed(script, "REFS")
	var names := PackedStringArray()
	var is_ref := PackedByteArray()
	for name in declared(script):
		if not skip.has(name):
			names.append(name)
			is_ref.append(1 if refs.has(name) else 0)
	_members[script] = names
	_is_ref[script] = is_ref


func _value(path: String, value: Variant, holder: Object) -> void:
	match typeof(value):
		TYPE_OBJECT:
			_object(path, value, holder)
		TYPE_ARRAY:
			var items: Array = value
			var element: int = items.get_typed_builtin()
			if items.is_typed() and (element < TYPE_RID or element >= TYPE_PACKED_BYTE_ARRAY):
				# A typed array of plain values (Array[StringName], Array[int]): one leaf, like a
				# packed array.
				_sink.call(path, items)
				return
			_sink.call(_join(path, "#"), items.size())
			for i in items.size():
				_value(_index(path, i), items[i], holder)
		TYPE_DICTIONARY:
			var table: Dictionary = value
			var keys: Array = table.keys()
			keys.sort()
			_sink.call(_join(path, "#"), keys.size())
			for key: Variant in keys:
				var at: String = _index(path, key)
				_key(at, key)
				_value(at, table[key], holder)
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			_problem(path, "holds a %s" % type_string(typeof(value)), "add it to DERIVED, it is set up again, not saved")
		_:
			_sink.call(path, value)


## A REFS member: who each reference points at (`identity`), through arrays and dictionaries.
func _ref(path: String, value: Variant) -> void:
	match typeof(value):
		TYPE_OBJECT:
			_sink.call(path, identity(value))
		TYPE_ARRAY:
			# Only the filled entries, each with its index: a slot-sized array (a shot's stuck-to
			# body, 100,000 slots) is nearly all empty, and walking every slot in GDScript cost
			# 136 ms a hash at the 100,000 cap; an empty one costs one engine call.
			var items: Array = value
			_sink.call(_join(path, "#"), items.size())
			if items.count(null) == items.size():
				return
			for i in items.size():
				var item: Variant = items[i]
				if item == null:
					continue
				_sink.call(_join(_index(path, i), "@"), i)
				_ref(_index(path, i), item)
		TYPE_DICTIONARY:
			var table: Dictionary = value
			var keys: Array = table.keys()
			keys.sort()
			_sink.call(_join(path, "#"), keys.size())
			for key: Variant in keys:
				var at: String = _index(path, key)
				_key(at, key)
				_ref(at, table[key])
		_:
			_value(path, value, null)


## A dictionary's key: a value, never an object (its order and bytes would be its address).
func _key(at: String, key: Variant) -> void:
	if typeof(key) == TYPE_OBJECT:
		_problem(at, "is keyed by an object", "key it by an id (an actor id, a slot), or add it to DERIVED")
		return
	_sink.call(_join(at, "{}"), key)


func _object(path: String, value: Variant, holder: Object, root: bool = false) -> void:
	if value == null:
		_sink.call(path, null)
		return
	if not is_instance_valid(value):
		_sink.call(path, "<freed>")
		return
	var object: Object = value
	var id: int = object.get_instance_id()
	if _seen.has(id):
		_sink.call(path, "@%d" % _seen[id])
		return
	if object is RandomNumberGenerator:
		var rng: RandomNumberGenerator = object
		_sink.call(path, PackedInt64Array([rng.seed, rng.state]))
		return
	var script: Script = object.get_script() as Script
	if object is PackedScene:
		# A scene is data, made in code only by tests (a made-up enemy's body).
		_sink.call(path, (object as PackedScene).resource_path)
		return
	if object is Resource and (object as Resource).resource_path.begins_with("res://"):
		# Content from a file: data, the same on every machine.
		_sink.call(path, (object as Resource).resource_path)
		return
	if object is Node:
		var node: Node = object
		var what: String = _describe(node)
		if not root and (script == null or not is_simulation(script) or is_view_only(script)):
			_problem(path, "holds a Node (%s)" % what, "add it to DERIVED (a service), REFS (another body) or VIEW (if only the drawing reads it)")
			return
		if not root and not (holder is Node and (holder as Node).is_ancestor_of(node)):
			# A reference to a body that has an id (an actor): its id is its identity (N5), the same
			# on every machine, so the hash keeps who it points at without walking another's body.
			var body_id: Variant = node.get(&"id")
			if typeof(body_id) == TYPE_INT:
				_sink.call(path, "%s#%d" % [script.resource_path.get_file(), body_id])
				return
			_problem(path, "holds a reference to a node it does not own (%s)" % what, "add it to REFS (a body that is state) or DERIVED (one set up again)")
			return
	elif script == null:
		_problem(path, "holds a %s" % object.get_class(), "add it to DERIVED (or VIEW if only the drawing reads it)")
		return
	_seen[id] = _seen.size()
	if object is Node2D:
		_sink.call(_join(path, ".position"), (object as Node2D).position)
	if object is CharacterBody2D:
		_sink.call(_join(path, ".velocity"), (object as CharacterBody2D).velocity)
	var names: PackedStringArray = members(script)
	var is_ref: PackedByteArray = _is_ref[script]
	for i in names.size():
		var at: String = _join(path, "." + names[i]) if with_paths else path
		if is_ref[i] != 0:
			_ref(at, object.get(names[i]))
		else:
			_value(at, object.get(names[i]), object)


func _problem(path: String, what: String, fix: String) -> void:
	problems.append("%s %s; %s" % [path, what, fix])


static func _describe(node: Node) -> String:
	var script: Script = node.get_script() as Script
	if script != null and not script.resource_path.is_empty():
		return "%s, %s" % [node.get_class(), script.resource_path.get_file()]
	return node.get_class()


func _join(path: String, suffix: String) -> String:
	return path + suffix if with_paths else path


func _index(path: String, key: Variant) -> String:
	return "%s[%s]" % [path, str(key)] if with_paths else path
