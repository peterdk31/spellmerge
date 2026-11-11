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
##   entered (`identity`): an actor by its id (a reference is to a live body, so its id says which;
##   what a body keeps of one that may be gone is its key, `Actors.key_of`, N5), anything else by
##   what it is; a list of them that holds only bodies (and empty entries) is one leaf of their
##   actor ids (`_bodies_as_ids`, props W3b);
## - `SPARES` (free lists of spare records, each set whole when it is taken: Spells' spare launches),
##   walked as their size alone (N3c: their contents cannot change the game, and walking them was a
##   fifth of the spells area's hash);
## - `BY_ACTOR` (tables kept by actor id that grow with the actors: Spells' builds by caster): state,
##   walked with the rest unless a walk asks for the area without them (`without_by_actor`, props
##   W3). Who walks each actor's share of them, and how it is got, is `SimHash`'s (`ActorPart`): the
##   walker only walks the value it is handed (`walk_value`, `values_of`). A snapshot walks the area
##   whole.
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
## - an array (element by element; a typed array of plain values in one call; with empty slots, only
##   the filled ones, each after its index) or a dictionary (its keys in sorted order, StringNames by
##   their text (`sorted_keys`), each key then its value);
## - an object of a script (an actor's intent, a compiled spell, a brain), walked member by member;
##   one met twice is walked once, and later meetings are the number of its first (in walk order);
## - a node of a simulation script that is the holder's own descendant (an actor's components), walked
##   too, with its `position` (and a body's `velocity`); a body walked as an area is walked with
##   the simulation nodes added to it in play that no member holds (`added_in_play`);
## - a reference to a simulation node it does not own that has an int `id` (an actor: a brain's
##   typed target actor): that id, as "actor.gd#7";
## - a resource from a file (content: a card, enemy data) or a scene: its path, since data cannot
##   desync;
## - a `RandomNumberGenerator`: its seed and state.
## An object whose script says `const FROZEN: bool = true` (set whole when it is made and never
## changed after: a compiled staff, its casts and spells) is one leaf wherever it is met: the hash of
## its members, worked out the first time any walk meets it and kept (N3c: a build is met from many
## places, and was a third of the spells area's hash). `verify_frozen` works it out again each time
## and names one that changed; `tests/core/test_state_walked.gd` walks every card so.
## An object whose script has `func idle() -> bool` and is idle (its state is a fresh one's, waiting
## to be started: a dash's homing while no dash homes) is one leaf, `&"idle"`, not its members (N3c:
## a carrier keeps one per row, nearly all idle, and they were most of a hash).
## A body walked as an area that is at rest (`rest_leaf()` gives an array, not null: an actor that
## is still and as it was made, a standing prop; props W2) is that array's values, not its
## members. A snapshot does not use it: it saves every body whole.
## Anything else is a **problem**, named by its path and what it holds: a node that is not the
## holder's own (a service: DERIVED; another area's body: REFS), a node of a script outside the
## simulation, a Callable, a Signal, an RID or another engine object (a mesh, a material).
## `tests/core/test_state_walked.gd` fails on any in running games; `tests/core/test_state_declared.gd`
## on any a member's type already shows.
##
## It runs only in tests, tools, replays and later the netcode, never in a normal build's tick.
##
##     var walk := StateWalk.new()
##     walk.walk("combat", combat, func(path: String, value: Variant) -> void: print(path, " = ", value))
##     assert(walk.problems.is_empty())

## The simulation folders (core/sim/README.md lists the same, with why): every script under one is
## a simulation script, but those under VIEW_FOLDERS (online-ready N9: simulation by default, so a
## new gameplay folder is covered the day it gets its first script). `core/sim/` is not one: these
## tools read the simulation, they are not part of it.
const FOLDERS: Array[String] = [
	"res://core/actors/",
	"res://core/projectiles/",
	"res://core/spells/",
	"res://gameplay/",
]
## Folders inside FOLDERS that are view as a whole: they draw the game and only read it.
const VIEW_FOLDERS: Array[String] = [
	"res://gameplay/feel/",
]
## The kinds of list a simulation script may declare (see the class doc; RUN_KEEPS, the settings a
## new run keeps, is `SimFresh`'s).
const LISTS: Array[String] = ["DERIVED", "VIEW", "REFS", "SPARES", "BY_ACTOR", "RUN_KEEPS"]

## Each problem, as "path: what it holds; the fix".
var problems: PackedStringArray = PackedStringArray()
## Whether the sink is handed each leaf's path. Off for the hash, which needs only the values (and
## is several times faster without building a string per leaf); a problem then names its area only.
var with_paths: bool = true
## Work a frozen object's hash out again at every meeting and name one that changed since it was
## first worked out (a test's check that FROZEN is true; slow).
var verify_frozen: bool = false
## Scripts this walk counts as simulation besides FOLDERS' (a test's stand-in for a game script: the
## card test's scripted controller drives a wizard as a player's would).
var also_simulation: Array[Script] = []

var _sink: Callable
## The hash's walk (`values`): each leaf's value is appended here, as `SimHash.add_leaf` gives it, with no
## call of a sink per leaf (half a hash's time was the sink's calls).
var _values: Array = []
var _collecting: bool = false
## Instance id to the order an object was first walked in (this walk).
var _seen: Dictionary[int, int] = {}

## Script to its state members (cached: the property lists do not change while the game runs).
static var _members: Dictionary[Script, PackedStringArray] = {}
## Script to its state members as StringNames (`get` by a String makes a StringName each time).
static var _member_names: Dictionary[Script, Array] = {}
## Script to how each of its state members (as `_members` orders them) is walked: PLAIN (declared a
## plain value: one leaf, as it is), REF (in REFS), SPARE (in SPARES: its size) or 0 (by what it
## holds).
static var _how: Dictionary[Script, PackedByteArray] = {}
const PLAIN: int = 1
const REF: int = 2
const SPARE: int = 3
## Declared a packed array: one leaf, its type, size and hash (`SimHash.add_leaf`), without `_value`.
const PACKED: int = 4
## Script to what `identity` calls its objects (its file, or its class), and to its objects' names by
## id ("actor.gd#7").
static var _what: Dictionary[Script, String] = {}
static var _named: Dictionary[Script, Dictionary] = {}
## Script to whether its objects are plain objects of a script: no node, resource or generator
## (`_object`'s short way).
static var _plain: Dictionary[Script, bool] = {}
## Script to whether it is FROZEN, and each frozen object's hash by instance id (an id is never
## given to another object while the game runs: Godot's ids carry a counter).
static var _frozen: Dictionary[Script, bool] = {}
static var _frozen_hashes: Dictionary[int, int] = {}
## The leaf before a frozen object's hash.
const FROZEN_LEAF: StringName = &"frozen"
## Script to whether its objects say when they are idle (`func idle() -> bool`).
static var _idles: Dictionary[Script, bool] = {}
## Script to whether its bodies have `rest_leaf` (`_rests_of`).
static var _rests: Dictionary[Script, bool] = {}
## Script to its BY_ACTOR members, 1 each in `members` order (empty when it lists none).
static var _by_actor_mask: Dictionary[Script, PackedByteArray] = {}
## The one leaf of an idle object.
const IDLE: StringName = &"idle"
## An empty entry, and a freed one, of a REFS array of bodies walked as ids (`_bodies_as_ids`): no
## actor id is either.
const NO_BODY: int = -1
const FREED_BODY: int = -2
## Script to whether a node of it is walked when its holder owns it (`_walks_into`), for the scripts
## not in `also_simulation`.
static var _enters: Dictionary[Script, bool] = {}


## Walks `object` (an area: a service, an actor table, a body) under the name `area`, handing every
## leaf to `sink(path, value)` in a fixed order; `without_by_actor` leaves its BY_ACTOR members out.
## Problems are added to `problems`.
func walk(area: String, object: Object, sink: Callable, without_by_actor: bool = false) -> void:
	_sink = sink
	_seen.clear()
	_root(area, object, without_by_actor)
	_sink = Callable()


## The hash's walk: as `walk`, with every leaf's value (as `SimHash.add_leaf` gives it: a packed or typed
## array as its type, size and engine hash) appended to `into`, in the same order. Paths are built
## only for the problems' sake (`with_paths`), and are best off.
func values(area: String, object: Object, into: Array, without_by_actor: bool = false) -> void:
	_collecting = true
	_values = into
	_seen.clear()
	_root(area, object, without_by_actor)
	_values = []
	_collecting = false


## Walks `value` (what an area hands over of itself: an actor's share of its BY_ACTOR members) under
## the name `area`, as a member of `owner` would be walked.
func walk_value(area: String, value: Variant, owner: Object, sink: Callable) -> void:
	_sink = sink
	_seen.clear()
	_value(area, value, owner)
	_sink = Callable()


## As `walk_value`, the hash's way (`values`).
func values_of(area: String, value: Variant, owner: Object, into: Array) -> void:
	_collecting = true
	_values = into
	_seen.clear()
	_value(area, value, owner)
	_values = []
	_collecting = false


## Whether `script` lists BY_ACTOR.
static func has_by_actor(script: Script) -> bool:
	if script == null:
		return false
	if not _members.has(script):
		_plan(script)
	return not _by_actor_mask[script].is_empty()


## The area itself, walked as its own holder (a body or a service is the root of its area), whole or
## without its BY_ACTOR members. A null or freed area is a leaf, as any object is.
func _root(area: String, object: Object, without_by_actor: bool) -> void:
	var script: Script = object.get_script() as Script if without_by_actor and is_instance_valid(object) else null
	if script != null and has_by_actor(script):
		_object(area, object, null, true, _by_actor_mask[script])
	else:
		_object(area, object, null, true)


## Whether `script` is a simulation script (in FOLDERS, not in VIEW_FOLDERS). An inner class has no path of its own and is
## told by the file that holds it, which the static checks know and the walk does not need.
static func is_simulation(script: Script) -> bool:
	if script == null:
		return false
	var path: String = script.resource_path
	for folder in VIEW_FOLDERS:
		if path.begins_with(folder):
			return false
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
## REFS): every constant `Array[StringName]` named `list` or `list` + "_" + a name (`VIEW_ONLY`, a
## bool, is no list).
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


## How `script`'s state members are walked, in `members` order: each a StringName and one of PLAIN,
## REF, SPARE, PACKED or 0 (by what it holds). For the snapshot (`Snapshot`), which walks the same
## members by the same plan.
static func plan(script: Script) -> Array:
	if not _members.has(script):
		_plan(script)
	return [_member_names[script], _how[script]]


## Whether objects of `script` are FROZEN (made whole, never changed after).
static func is_frozen(script: Script) -> bool:
	return _frozen_of(script)


## Whether objects of `script` say when they are idle (`func idle() -> bool`).
static func says_idle(script: Script) -> bool:
	return _idles_of(script)


## Whether a node of `script` is walked when its holder owns it: a simulation script that is not
## view as a whole (as a walk with no `also_simulation` decides).
static func enters(script: Script) -> bool:
	if script == null:
		return false
	if not _enters.has(script):
		_enters[script] = is_simulation(script) and not is_view_only(script)
	return _enters[script]


## True for a body: a node with an actor id (an `Actor`; `Tick.state_areas`' "actor 7").
static func is_body(object: Object) -> bool:
	return actor_id_of(object) >= 0


## The actor id of `value` if it is a body (a live node with an int `id` of 0 or more: an actor's id
## in the actor table, which says which body it is), else -1. The one place that says what a body is.
static func actor_id_of(value: Variant) -> int:
	if typeof(value) != TYPE_OBJECT or not is_instance_valid(value) or not value is Node:
		return -1
	var id: Variant = (value as Node).get(&"id")
	return int(id) if typeof(id) == TYPE_INT and int(id) >= 0 else -1


## The simulation nodes (`enters`) added to `body` in play, which its scene does not make: the
## outermost node of each branch with no owner (a node of a scene has its scene's root as its
## owner; their own children are theirs to make), under the body or its scene's simulation nodes. A body built in code has no scene: each simulation
## node directly under it. A body walked as an area is walked with them, after its members (a
## possession's puppet, which no member of its body holds), and a snapshot makes them again.
static func added_in_play(body: Node) -> Array[Node]:
	var out: Array[Node] = []
	if body.scene_file_path == "":
		for child: Node in body.get_children():
			if enters(child.get_script() as Script):
				out.append(child)
		return out
	_added_under(body, out)
	return out


## Under the scene's simulation nodes only (a component may hold one): a body's looks and sprites
## are view, and a hash walks every body.
static func _added_under(at: Node, out: Array[Node]) -> void:
	for child: Node in at.get_children():
		if not enters(child.get_script() as Script):
			continue
		if child.owner == null:
			out.append(child)
		else:
			_added_under(child, out)


## Who `value` points at, for a REFS member: null, "<freed>", an actor as "actor.gd#7", a resource
## from a file by its path, anything else by its script's file or its class. Never entered.
static func identity(value: Variant) -> Variant:
	if value == null:
		return null
	if not is_instance_valid(value):
		return "<freed>"
	var object: Object = value
	var script: Script = object.get_script() as Script
	if script == null or object is Resource:
		if object is Resource and (object as Resource).resource_path.begins_with("res://"):
			return (object as Resource).resource_path
		if script == null:
			return object.get_class()
	if not _what.has(script):
		_what[script] = script.resource_path.get_file() if not script.resource_path.is_empty() else object.get_class()
		_named[script] = {}
	var id: Variant = object.get(&"id")
	if typeof(id) != TYPE_INT:
		return _what[script]
	# "actor.gd#7", made once per script and id (a body is pointed at from many places).
	var names: Dictionary = _named[script]
	if not names.has(id):
		names[id] = "%s#%d" % [_what[script], id]
	return names[id]


static func _plan(script: Script) -> void:
	var skip: PackedStringArray = listed(script, "DERIVED") + listed(script, "VIEW")
	var refs: PackedStringArray = listed(script, "REFS")
	var spares: PackedStringArray = listed(script, "SPARES")
	var parted: PackedStringArray = listed(script, "BY_ACTOR")
	var names := PackedStringArray()
	var how := PackedByteArray()
	var skips := PackedByteArray()
	var types: Dictionary[String, int] = {}
	for info: Dictionary in script.get_script_property_list():
		types[String(info["name"])] = int(info["type"])
	for name in declared(script):
		if not skip.has(name):
			names.append(name)
			skips.append(1 if parted.has(name) else 0)
			# A bool, a number, a string, a vector, a colour ... (TYPE_BOOL to TYPE_NODE_PATH): it can
			# hold nothing else.
			var type: int = int(types.get(name, TYPE_NIL))
			if spares.has(name):
				how.append(SPARE)
			elif not refs.has(name) and type >= TYPE_PACKED_BYTE_ARRAY:
				how.append(PACKED)
			else:
				how.append(REF if refs.has(name) else (PLAIN if type >= TYPE_BOOL and type <= TYPE_NODE_PATH else 0))
	_members[script] = names
	_how[script] = how
	_by_actor_mask[script] = skips if parted.size() > 0 else PackedByteArray()
	var named: Array[StringName] = []
	for name in names:
		named.append(StringName(name))
	_member_names[script] = named
	var idles: bool = false
	for method: Dictionary in script.get_script_method_list():
		if String(method["name"]) == "idle":
			idles = true
			break
	_idles[script] = idles
	var frozen: bool = false
	var at: Script = script
	while at != null and not frozen:
		frozen = bool(at.get_script_constant_map().get("FROZEN", false))
		at = at.get_base_script()
	_frozen[script] = frozen


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
				_leaf(path, items)
				return
			_leaf(path, items.size(), "#")
			# A slot-sized array (a pool's or a carrier's per-shot objects) is mostly empty: with
			# empty slots, only the filled ones are walked, each after its index, as `_ref` does (the
			# empty slots were most of a hash's leaves: 15,000 of the spells area's 20,000).
			var empty: int = 0 if items.is_typed() and element != TYPE_OBJECT else items.count(null)
			_leaf(path, empty, "~")
			if empty == items.size():
				return
			var rows: Script = items.get_typed_script() as Script
			if rows != null and _idles_of(rows):
				_idle_rows(path, items, empty > 0, holder)
				return
			for i in items.size():
				var item: Variant = items[i]
				if empty > 0:
					if item == null:
						continue
					_leaf_at(path, i, i, "@")
				var at: String = _index(path, i) if with_paths else path
				if typeof(item) == TYPE_OBJECT:
					_object(at, item, holder)
				else:
					_value(at, item, holder)
		TYPE_DICTIONARY:
			var table: Dictionary = value
			var keys: Array = sorted_keys(table)
			_leaf(path, keys.size(), "#")
			for key: Variant in keys:
				var at: String = _index(path, key)
				_key(at, key)
				_value(at, table[key], holder)
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			_problem(path, "holds a %s" % type_string(typeof(value)), "add it to DERIVED, it is set up again, not saved")
		_:
			if _collecting and typeof(value) < TYPE_PACKED_BYTE_ARRAY:
				# A plain value is its own leaf (`SimHash.add_leaf`): appended without the two calls.
				_values.append(value)
			else:
				_leaf(path, value)


## A typed array of objects that say when they are idle (a carrier's homing per row, nearly all
## idle): each idle one is one leaf without a visit of its own (it is a fresh one's state: never
## numbered among the objects met), the rest are walked as objects. As `_value`'s loop otherwise.
func _idle_rows(path: String, items: Array, has_empty: bool, holder: Object) -> void:
	for i in items.size():
		var item: Object = items[i]
		if item == null:
			continue
		if has_empty:
			_leaf_at(path, i, i, "@")
		if item.call(&"idle"):
			_leaf_at(path, i, IDLE, ".idle")
		else:
			_object(_index(path, i) if with_paths else path, item, holder)


## A frozen object's one leaf: its members' hash (see the class doc), worked out once.
func _frozen_leaf(path: String, object: Object, script: Script) -> void:
	var id: int = object.get_instance_id()
	var known: bool = _frozen_hashes.has(id)
	if not known or verify_frozen:
		var inner := StateWalk.new()
		inner.with_paths = false
		inner.also_simulation = also_simulation
		inner.verify_frozen = verify_frozen
		var leaves: Array = []
		inner._collecting = true
		inner._values = leaves
		inner._seen[id] = 0
		inner._members_of(path, object, script)
		problems.append_array(inner.problems)
		var worked: int = SimHash.of_leaves(leaves)
		if known and worked != _frozen_hashes[id]:
			_problem(path, "changed after it was made (%s is FROZEN)" % script.resource_path.get_file(), "take FROZEN off its script, or stop the change")
		_frozen_hashes[id] = worked
	_leaf(path, FROZEN_LEAF, ".frozen")
	_leaf(path, _frozen_hashes[id], ".frozen")


## Whether a body of `script` sums itself up at rest (`rest_leaf`), asked once a script.
static func _rests_of(node: Node, script: Script) -> bool:
	if not _rests.has(script):
		_rests[script] = node.has_method(&"rest_leaf")
	return _rests[script]


## Whether objects of `script` are FROZEN.
static func _frozen_of(script: Script) -> bool:
	if not _members.has(script):
		_plan(script)
	return _frozen[script]


## Whether objects of `script` say when they are idle (`func idle() -> bool`).
static func _idles_of(script: Script) -> bool:
	if not _members.has(script):
		_plan(script)
	return _idles[script]


## A REFS member: who each reference points at (`identity`), through arrays and dictionaries.
func _ref(path: String, value: Variant) -> void:
	match typeof(value):
		TYPE_OBJECT:
			_leaf(path, identity(value))
		TYPE_ARRAY:
			# Only the filled entries, each with its index: a slot-sized array (a shot's stuck-to
			# body, 100,000 slots) is nearly all empty, and walking every slot in GDScript cost
			# 136 ms a hash at the 100,000 cap; an empty one costs one engine call.
			var items: Array = value
			_leaf(path, items.size(), "#")
			# (A typed array of arrays, as a carrier's struck lists, holds no null to count.)
			var may_hold_null: bool = not items.is_typed() or items.get_typed_builtin() == TYPE_OBJECT
			if may_hold_null and items.count(null) == items.size():
				return
			if may_hold_null and _bodies_as_ids(path, items):
				return
			for i in items.size():
				var item: Variant = items[i]
				if item == null:
					continue
				_leaf_at(path, i, i, "@")
				_ref(_index(path, i), item)
		TYPE_DICTIONARY:
			var table: Dictionary = value
			var keys: Array = sorted_keys(table)
			_leaf(path, keys.size(), "#")
			for key: Variant in keys:
				var at: String = _index(path, key)
				_key(at, key)
				_ref(at, table[key])
		_:
			_value(path, value, null)


## A REFS array whose filled entries are all bodies (`actor_id_of`: Combat's bodies by row, the
## bodies a zap is due on), or bodies freed since: one leaf, the actor id of each entry (NO_BODY for
## an empty one, FREED_BODY for a freed one), which a report names by its index (props W3b: a leaf
## and a name an entry cost 2.8 us). An actor id says which body; the kind of body is not hashed (a
## body's id is unique in the actor table). False, with nothing walked, when an entry is anything
## else (a node with no actor id, another object): then each entry is walked as before.
func _bodies_as_ids(path: String, items: Array) -> bool:
	var ids := PackedInt64Array()
	ids.resize(items.size())
	for i in items.size():
		var item: Variant = items[i]
		if item == null:
			ids[i] = NO_BODY
		elif not is_instance_valid(item):
			ids[i] = FREED_BODY
		else:
			var id: int = actor_id_of(item)
			if id < 0:
				return false
			ids[i] = id
	_leaf(path, ids, ".ids")
	return true


## `table`'s keys in an order that is the same on every machine. The engine's `sort` orders
## StringNames by where they are in memory, not by their text (so the web walked Spells' carriers in
## another order than Linux; found by N2b): a table with a StringName key is sorted by text (a
## StringName and a String of the same text are one key in a dictionary).
static func sorted_keys(table: Dictionary) -> Array:
	var keys: Array = table.keys()
	var named: bool = table.is_typed_key() and table.get_typed_key_builtin() == TYPE_STRING_NAME
	if not named and not table.is_typed_key():
		for key: Variant in keys:
			if typeof(key) == TYPE_STRING_NAME:
				named = true
				break
	if named:
		keys.sort_custom(_key_before)
	else:
		keys.sort()
	return keys


## The order of `sorted_keys` for a table with StringName keys: by type (a StringName as a String),
## then by value, a StringName's by its text.
static func _key_before(a: Variant, b: Variant) -> bool:
	var type_a: int = TYPE_STRING if typeof(a) == TYPE_STRING_NAME else typeof(a)
	var type_b: int = TYPE_STRING if typeof(b) == TYPE_STRING_NAME else typeof(b)
	if type_a != type_b:
		return type_a < type_b
	if type_a == TYPE_STRING:
		return String(a) < String(b)
	return a < b


## A dictionary's key: a value, never an object (its order and bytes would be its address).
func _key(at: String, key: Variant) -> void:
	if typeof(key) == TYPE_OBJECT:
		_problem(at, "is keyed by an object", "key it by an id (an actor id, a slot), or add it to DERIVED")
		return
	_leaf(at, key, "{}")


## `skip` marks the root's members left out (`_members_of`): its BY_ACTOR ones when the area less them
## is walked.
func _object(path: String, value: Variant, holder: Object, root: bool = false, skip: PackedByteArray = PackedByteArray()) -> void:
	if value == null:
		_leaf(path, null)
		return
	if not is_instance_valid(value):
		_leaf(path, "<freed>")
		return
	var object: Object = value
	var id: int = object.get_instance_id()
	if _seen.has(id):
		_leaf(path, "@%d" % _seen[id])
		return
	var script: Script = object.get_script() as Script
	if script != null and _plain.get(script, false) and _frozen[script]:
		_frozen_leaf(path, object, script)
		return
	if script != null and _plain.get(script, false):
		# An object of a script met before that is no node, resource or generator (most are): none of
		# the checks below apply.
		_seen[id] = _seen.size()
		if _idles[script] and bool(object.call(&"idle")):
			_leaf(path, IDLE, ".idle")
			return
		_members_of(path, object, script, skip)
		return
	var node: Node = object as Node
	if node != null:
		if not root and not _walks_into(script):
			_problem(path, "holds a Node (%s)" % _describe(node), "add it to DERIVED (a service), REFS (another body) or VIEW (if only the drawing reads it)")
			return
		if not root and not (holder is Node and (holder as Node).is_ancestor_of(node)):
			# A reference to a body that has an id (an actor): its id is its identity (N5), the same
			# on every machine, so the hash keeps who it points at without walking another's body.
			if typeof(node.get(&"id")) == TYPE_INT:
				_leaf(path, identity(node))
				return
			_problem(path, "holds a reference to a node it does not own (%s)" % _describe(node), "add it to REFS (a body that is state) or DERIVED (one set up again)")
			return
	elif script == null or object is Resource or object is RandomNumberGenerator:
		if object is RandomNumberGenerator:
			var rng: RandomNumberGenerator = object
			_leaf(path, PackedInt64Array([rng.seed, rng.state]))
			return
		if object is PackedScene:
			# A scene is data, made in code only by tests (a made-up enemy's body).
			_leaf(path, (object as PackedScene).resource_path)
			return
		if object is Resource and (object as Resource).resource_path.begins_with("res://"):
			# Content from a file: data, the same on every machine.
			_leaf(path, (object as Resource).resource_path)
			return
	if script == null:
		# An engine object, or a node of no script handed as an area: nothing of the game's to walk.
		_problem(path, "holds a %s" % object.get_class(), "add it to DERIVED (or VIEW if only the drawing reads it)")
		return
	if not _plain.has(script):
		_plain[script] = node == null and not (object is Resource) and not (object is RandomNumberGenerator)
	if _plain[script] and _frozen_of(script):
		_frozen_leaf(path, object, script)
		return
	_seen[id] = _seen.size()
	if _idles_of(script) and bool(object.call(&"idle")):
		_leaf(path, IDLE, ".idle")
		return
	if root and node != null and _rests_of(node, script):
		# A body at rest, as it was made and with nothing to do (props W2: a standing prop): one
		# leaf of what may differ between two bodies made alike (`Actor.rest_leaf`).
		var rest: Variant = node.call(&"rest_leaf")
		if rest != null:
			# Each value a leaf of its own, hashed by its bytes as a member is (an array's `hash()`
			# would take -0.0 for 0.0).
			var values: Array = rest
			_leaf(path, values.size(), ".rest")
			for i in values.size():
				_leaf_at(path + ".rest" if with_paths else path, i, values[i])
			return
	if node is Node2D:
		_leaf(path, (node as Node2D).position, ".position")
	_members_of(path, object, script, skip)
	if root and is_body(node):
		# The simulation nodes added to it in play that no member holds (a possession's puppet).
		for added: Node in added_in_play(node):
			if not _seen.has(added.get_instance_id()):
				_object(_join(path, "/" + str(node.get_path_to(added))), added, node)


## Every state member of `object` (of `script`), in order, by how its plan says; with `skip`, but
## those it marks (the area less its BY_ACTOR members).
func _members_of(path: String, object: Object, script: Script, skip: PackedByteArray = PackedByteArray()) -> void:
	var names: Array = _member_names[script]
	var how: PackedByteArray = _how[script]
	var skipping: bool = not skip.is_empty()
	for i in names.size():
		if skipping and skip[i] != 0:
			continue
		var name: StringName = names[i]
		if _collecting and how[i] == PLAIN:
			_values.append(object.get(name))
			continue
		if _collecting and how[i] == PACKED:
			var packed: Variant = object.get(name)
			_values.append(typeof(packed))
			_values.append(packed.size())
			_values.append(hash(packed))
			continue
		var at: String = _join(path, "." + name) if with_paths else path
		if how[i] == REF:
			_ref(at, object.get(name))
		elif how[i] == SPARE:
			_leaf(at, (object.get(name) as Array).size(), "#")
		elif how[i] == PLAIN or how[i] == PACKED:
			_leaf(at, object.get(name))
		else:
			_value(at, object.get(name), object)


## Whether a node of `script` is walked when the holder owns it: a simulation script (or one this
## walk counts as one) that is not view as a whole.
func _walks_into(script: Script) -> bool:
	if script == null:
		return false
	if not also_simulation.is_empty() and also_simulation.has(script):
		return not is_view_only(script)
	return enters(script)


## Hands one leaf to the sink at `path` and `suffix` (".position"), or, in the hash's walk
## (`values`), appends its value as `SimHash.add_leaf` gives it (a plain one as it is): the path is
## built only for a sink that wants paths (props W3b: the calls a leaf made were most of the
## walker's cost per leaf).
func _leaf(path: String, value: Variant, suffix: String = "") -> void:
	if _collecting:
		_append(value)
	elif with_paths:
		_sink.call(path + suffix, value)
	else:
		_sink.call(path, value)


## As `_leaf`, at `path[key]` and `suffix`.
func _leaf_at(path: String, key: Variant, value: Variant, suffix: String = "") -> void:
	if _collecting:
		_append(value)
	else:
		_sink.call(_index(path, key) + suffix if with_paths else path, value)


## A leaf's value in the hash's walk, as `SimHash.add_leaf` gives it (a plain one as it is, without
## the call).
func _append(value: Variant) -> void:
	if typeof(value) < TYPE_DICTIONARY:
		_values.append(value)
	else:
		SimHash.add_leaf(_values, value)


## A problem: where, what it holds, and the fix, with where the lists are explained.
func _problem(path: String, what: String, fix: String) -> void:
	problems.append("%s %s; %s (core/sim/README.md, \"Steps\")" % [path, what, fix])


static func _describe(node: Node) -> String:
	var script: Script = node.get_script() as Script
	if script != null and not script.resource_path.is_empty():
		return "%s, %s" % [node.get_class(), script.resource_path.get_file()]
	return node.get_class()


func _join(path: String, suffix: String) -> String:
	return path + suffix if with_paths else path


func _index(path: String, key: Variant) -> String:
	return "%s[%s]" % [path, str(key)] if with_paths else path
