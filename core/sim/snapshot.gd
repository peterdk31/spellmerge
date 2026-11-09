class_name Snapshot
extends RefCounted
## The whole game's state at one tick, and the game made so again (online-ready N10,
## docs/milestones/online-ready.md): a player joining a run online takes the host's, a replay seeks
## by them, a run can be saved mid-room, and rollback (later) goes back to one. No area writes save
## code: a snapshot walks the state members `StateWalk` walks (core/sim/README.md, "Contract"), by
## the same plan, so a member added later is saved and loaded with no list kept by hand.
##
##     var snapshot := Snapshot.take(Tick.state_areas(), get_tree().root)
##     ...
##     var problems := snapshot.restore(Tick.state_areas(), get_tree().root)
##
## **What it holds** (data only: no live object of the game, so one snapshot restores into any
## world, any number of times):
## - every area's state members (`StateWalk.members`): values and packed arrays copied (a packed
##   array into a buffer of its own: the native kernels write past copy-on-write), arrays and
##   dictionaries with their types, objects of scripts member by member (one met twice is one
##   object, met again by its number), the nodes an object owns (an actor's components) by their
##   path under it, with their position;
## - **references** (REFS, and a node another holds): a node by the actor id the actor table keeps
##   it under, and its path under that node (a controller in a body: "actor 7", `AIController`);
##   an object of a script by its number, when the snapshot holds it elsewhere;
## - what never changes as itself: content (resources from files) and FROZEN objects (a compiled
##   staff, an AI behaviour every brain shares);
## - an idle object (`idle()`) as its script, a spare list (SPARES) as its size;
## - **the bodies** (each area holding an actor's body, `Tick.state_areas`' "actor 7"): how to make
##   it again (its scene, or its script for a body built in code; its parent, by path under the
##   world; the simulation nodes added to it in play, as a boss's phases or a possession's puppet,
##   by script and path, with their state as the walker walks it, `StateWalk.added_in_play`).
##
## **Restoring** into a world (the same, or a fresh one of the same kind) goes in this order:
## 1. **Bodies:** the world's bodies are matched by area name and scene; one the snapshot lacks (or
##    one on its way out, queued for deletion) is freed, one missing is made (its scene or script,
##    its nodes added in play, its state, then `prepare(body)` and into its parent), so each body's
##    own `_ready` wires it as when it was first made.
## 2. **State:** every area's and body's members are written back. An object of the same script
##    already there is written in place (what outside holds on to it still does), else one is made
##    (`new()`, no arguments).
## 3. **The actor table's nodes** are set again from the bodies (`Actors.set_node`); a node another
##    made (a plain body Combat registers: the swarm's rows) is its maker's to set (4).
## 4. **`restore_nodes()`** of every object restored that has one, the outermost first (the horde
##    sets up its swarm, then the swarm makes its rows): the nodes it makes from its state that are
##    no bodies (the swarm's bare rows), set in the actor table.
## 5. **References** are resolved: by actor id through the table, then the path under that node.
## 6. **`rebuild_derived()`** of every object restored that has one, the innermost first: the DERIVED
##    members that follow the state (a lookup by node, a cache).
## A problem (a member that cannot be saved, a reference to a node nothing names, a body missing)
## is named with its path and the fix, as the walker names them.
##
## It runs in tests, tools, replays and later the netcode, never in a normal build's tick. The
## bytes a join sends are the netcode's (a strict decoder; scripts and content checked by path).

const ActorsScript := preload("res://core/actors/actors.gd")


## An object of a script: its members' values in `StateWalk.members` order.
class Obj:
	extends RefCounted
	var of: Script = null
	var number: int = -1
	var values: Array = []
	## A node: its path under the object that holds it (empty for an area), and its position.
	var is_node: bool = false
	var path: NodePath = NodePath()
	var position: Vector2 = Vector2.ZERO
	## A body's: the nodes added to it in play that no member holds (`StateWalk.added_in_play`), as
	## the walker walks them after its members.
	var added: Array = []


## An object met before in this snapshot, by its number.
class Seen:
	extends RefCounted
	var number: int = -1


## An object that never changes (FROZEN), kept as itself.
class Keep:
	extends RefCounted
	var object: Object = null


## An idle object (`idle()`: its state is a fresh one's): its script.
class Idle:
	extends RefCounted
	var of: Script = null
	var number: int = -1


## A reference to a node: the actor id the actor table keeps it under, and its path under that node.
class Ref:
	extends RefCounted
	var id: int = -1
	var path: NodePath = NodePath()


## A reference to an object of a script the snapshot holds elsewhere: its number (worked out once
## the whole snapshot is taken, `instance` until then).
class ObjectRef:
	extends RefCounted
	var number: int = -1
	var instance: int = 0


## An array with its type; a spare list (SPARES) holds its size only (`spares`, else -1).
class List:
	extends RefCounted
	var builtin: int = TYPE_NIL
	var class_named: StringName = &""
	var of: Variant = null
	var items: Array = []
	var spares: int = -1


## A dictionary with its key and value types: its keys in their order (the order it was filled in,
## which a loop over it follows: Spells steps its carriers so; the hash sorts them, a restore must
## not) and their values.
class Table:
	extends RefCounted
	var key_builtin: int = TYPE_NIL
	var key_class: StringName = &""
	var key_of: Variant = null
	var value_builtin: int = TYPE_NIL
	var value_class: StringName = &""
	var value_of: Variant = null
	var keys: Array = []
	var values: Array = []


## How to make a body again.
class Body:
	extends RefCounted
	## Its area's name ("actor 7") and actor id.
	var area: String = ""
	var id: int = -1
	## Its scene's path, or empty for a body built in code (then `of`, its script).
	var scene: String = ""
	var of: Script = null
	var name: StringName = &""
	## Its parent's path under the world.
	var parent: NodePath = NodePath()
	## The simulation nodes added to it in play: [path of the parent under the body, name, script].
	var added: Array = []


## Each area's state by name, in the order taken (an `Obj`).
var areas: Dictionary[String, Variant] = {}
## How to make each body again, in the order taken.
var bodies: Array[Body] = []
## What could not be taken, as "path: what it holds; the fix".
var problems: PackedStringArray = PackedStringArray()


## The state of `areas` (name to object: `Tick.state_areas()`, or a test world's). `world` is the
## node the bodies' parents are named under (the tree's root in the game).
static func take(of_areas: Dictionary, world: Node = null) -> Snapshot:
	var snapshot := Snapshot.new()
	var taker := Taker.new(snapshot, of_areas, world)
	taker.take_all()
	return snapshot


## Makes `into` (name to object, the same kind of world: `Tick.state_areas()`, or a fresh test
## world's) as this snapshot says, in the order of the class doc. `world` is where the bodies'
## parents are found; `prepare(body)` readies a body made again before it enters the tree (a test
## world's services). Returns the problems (empty when all went well).
func restore(into: Dictionary, world: Node = null, prepare: Callable = Callable()) -> PackedStringArray:
	var restorer := Restorer.new(self, into, world, prepare)
	restorer.restore_all()
	return restorer.problems


## The actor table among `of_areas`, or null.
static func table_in(of_areas: Dictionary) -> ActorsScript:
	for value: Variant in of_areas.values():
		if value is ActorsScript:
			return value as ActorsScript
	return null


## Content, kept as itself: a resource from a file (`res://`), or an engine resource (a scene a
## test makes in code); a resource of a script made in code is state like any object of a script,
## as the walker walks it.
static func is_content(object: Object) -> bool:
	if not object is Resource:
		return false
	return (object as Resource).resource_path.begins_with("res://") or object.get_script() == null


## Whether `value` is an actor's body (`StateWalk.is_body`) the table keeps under its id.
static func is_body(value: Variant, table: ActorsScript) -> bool:
	if not value is Node or not is_instance_valid(value) or not StateWalk.is_body(value as Object):
		return false
	return table == null or table.node_of(int((value as Node).get(&"id"))) == value


static func _problem(into: PackedStringArray, path: String, what: String, fix: String) -> void:
	into.append("%s %s; %s (core/sim/README.md, \"Snapshots\")" % [path, what, fix])


## Takes a snapshot: walks each area once, by the walker's plan.
class Taker:
	extends RefCounted
	var _snapshot: Snapshot
	var _areas: Dictionary
	var _world: Node
	var _table: ActorsScript = null
	## Instance id to the number of an object taken (its order).
	var _numbers: Dictionary[int, int] = {}
	## Instance id of a node the actor table keeps to its actor id.
	var _ids: Dictionary[int, int] = {}
	var _object_refs: Array[ObjectRef] = []

	func _init(snapshot: Snapshot, of_areas: Dictionary, world: Node) -> void:
		_snapshot = snapshot
		_areas = of_areas
		_world = world
		_table = Snapshot.table_in(of_areas)
		if _table != null:
			var open := PackedInt32Array()
			open.resize(ActorsScript.ACTORS)
			var n: int = _table.open_ids(open)
			for i in n:
				var node: Node = _table.node_of(open[i])
				if node != null:
					_ids[node.get_instance_id()] = open[i]

	func take_all() -> void:
		for name: Variant in _areas:
			var area: Object = _areas[name]
			if area == null or not is_instance_valid(area):
				continue
			if Snapshot.is_body(area, _table):
				_body(String(name), area as Node)
			_snapshot.areas[String(name)] = _object(String(name), area, null, true)
		for link in _object_refs:
			if _numbers.has(link.instance):
				link.number = _numbers[link.instance]
			else:
				Snapshot._problem(_snapshot.problems, "a reference", "points at an object of a script the snapshot holds nowhere", "keep that object in a state member, or add the reference to DERIVED")

	## How to make the body `node` (the area `area`) again.
	func _body(area: String, node: Node) -> void:
		var body := Body.new()
		body.area = area
		body.id = int(node.get(&"id"))
		body.scene = node.scene_file_path
		body.of = node.get_script() as Script
		body.name = node.name
		var parent: Node = node.get_parent()
		if parent == null or _world == null or not (parent == _world or _world.is_ancestor_of(parent)):
			Snapshot._problem(_snapshot.problems, area, "is a body outside the world", "hand Snapshot the world node its parent is under")
		else:
			body.parent = _world.get_path_to(parent)
		for added: Node in StateWalk.added_in_play(node):
			body.added.append([node.get_path_to(added.get_parent()), added.name, added.get_script()])
		_snapshot.bodies.append(body)

	## A value of a state member of `holder`.
	func _value(path: String, value: Variant, holder: Object) -> Variant:
		match typeof(value):
			TYPE_OBJECT:
				return _object(path, value, holder)
			TYPE_ARRAY:
				var items: Array = value
				var element: int = items.get_typed_builtin()
				if items.is_typed() and (element < TYPE_RID or element >= TYPE_PACKED_BYTE_ARRAY):
					# A typed array of plain values: copied whole.
					return items.duplicate(true)
				var list := _list_of(items)
				for i in items.size():
					list.items.append(_value("%s[%d]" % [path, i], items[i], holder))
				return list
			TYPE_DICTIONARY:
				var table := _table_of(value as Dictionary)
				for key: Variant in table.keys:
					table.values.append(_value("%s[%s]" % [path, str(key)], (value as Dictionary)[key], holder))
				return table
			TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
				Snapshot._problem(_snapshot.problems, path, "holds a %s" % type_string(typeof(value)), "add it to DERIVED, it is set up again, not saved")
				return null
		return _copy(value)

	## A REFS member's value: who each reference points at, through arrays and dictionaries.
	func _ref(path: String, value: Variant) -> Variant:
		match typeof(value):
			TYPE_OBJECT:
				if value == null or not is_instance_valid(value):
					return null
				if value is Node:
					return _node_ref(path, value as Node)
				if Snapshot.is_content(value as Object):
					return value
				if StateWalk.is_frozen((value as Object).get_script() as Script):
					var keep := Keep.new()
					keep.object = value as Object
					return keep
				var link := ObjectRef.new()
				link.instance = (value as Object).get_instance_id()
				_object_refs.append(link)
				return link
			TYPE_ARRAY:
				var items: Array = value
				var list := _list_of(items)
				for i in items.size():
					list.items.append(_ref("%s[%d]" % [path, i], items[i]))
				return list
			TYPE_DICTIONARY:
				var table := _table_of(value as Dictionary)
				for key: Variant in table.keys:
					table.values.append(_ref("%s[%s]" % [path, str(key)], (value as Dictionary)[key]))
				return table
		return _value(path, value, null)

	## A node by the actor id of it or of the nearest node above it the actor table keeps.
	func _node_ref(path: String, node: Node) -> Variant:
		var at: Node = node
		while at != null:
			if _ids.has(at.get_instance_id()):
				var ref := Ref.new()
				ref.id = _ids[at.get_instance_id()]
				ref.path = at.get_path_to(node)
				return ref
			at = at.get_parent()
		Snapshot._problem(_snapshot.problems, path, "points at a node no actor id names (%s)" % node.get_class(), "register its body in the actor table, or add it to DERIVED (set up again)")
		return null

	func _object(path: String, value: Variant, holder: Object, root: bool = false) -> Variant:
		if value == null or not is_instance_valid(value):
			return null
		var object: Object = value
		var id: int = object.get_instance_id()
		if _numbers.has(id):
			var seen := Seen.new()
			seen.number = _numbers[id]
			return seen
		if Snapshot.is_content(object):
			# Content: data, the same in every world.
			return object
		var script: Script = object.get_script() as Script
		var node: Node = object as Node
		if node != null and not root:
			if not StateWalk.enters(script):
				Snapshot._problem(_snapshot.problems, path, "holds a Node (%s)" % node.get_class(), "add it to DERIVED (a service), REFS (another body) or VIEW (if only the drawing reads it)")
				return null
			if not (holder is Node and (holder as Node).is_ancestor_of(node)):
				return _node_ref(path, node)
		if script == null:
			Snapshot._problem(_snapshot.problems, path, "holds a %s" % object.get_class(), "add it to DERIVED (or VIEW if only the drawing reads it)")
			return null
		if node == null and StateWalk.is_frozen(script):
			var keep := Keep.new()
			keep.object = object
			return keep
		var number: int = _numbers.size()
		_numbers[id] = number
		if StateWalk.says_idle(script) and bool(object.call(&"idle")):
			var idle := Idle.new()
			idle.of = script
			idle.number = number
			return idle
		var record := Obj.new()
		record.of = script
		record.number = number
		if node != null:
			record.is_node = true
			if not root:
				record.path = (holder as Node).get_path_to(node)
			if node is Node2D:
				record.position = (node as Node2D).position
		var plan: Array = StateWalk.plan(script)
		var names: Array = plan[0]
		var how: PackedByteArray = plan[1]
		for i in names.size():
			var name: StringName = names[i]
			var member: Variant = object.get(name)
			var at: String = "%s.%s" % [path, name]
			match how[i]:
				StateWalk.REF:
					record.values.append(_ref(at, member))
				StateWalk.SPARE:
					var spares := _list_of(member as Array)
					spares.spares = (member as Array).size()
					record.values.append(spares)
				StateWalk.PLAIN, StateWalk.PACKED:
					record.values.append(_copy(member))
				_:
					record.values.append(_value(at, member, object))
		if root and StateWalk.is_body(object):
			for added: Node in StateWalk.added_in_play(node):
				if not _numbers.has(added.get_instance_id()):
					record.added.append(_object("%s/%s" % [path, node.get_path_to(added)], added, node))
		return record

	## A value as the snapshot keeps it: a packed array in a buffer of its own.
	static func _copy(value: Variant) -> Variant:
		if typeof(value) >= TYPE_PACKED_BYTE_ARRAY:
			return value.slice(0)
		return value

	static func _list_of(items: Array) -> List:
		var list := List.new()
		list.builtin = items.get_typed_builtin()
		list.class_named = items.get_typed_class_name()
		list.of = items.get_typed_script()
		return list

	static func _table_of(table: Dictionary) -> Table:
		var out := Table.new()
		out.key_builtin = table.get_typed_key_builtin()
		out.key_class = table.get_typed_key_class_name()
		out.key_of = table.get_typed_key_script()
		out.value_builtin = table.get_typed_value_builtin()
		out.value_class = table.get_typed_value_class_name()
		out.value_of = table.get_typed_value_script()
		out.keys = table.keys()
		return out


## Restores a snapshot into a world, in the order of the class doc.
class Restorer:
	extends RefCounted
	var problems: PackedStringArray = PackedStringArray()
	var _snapshot: Snapshot
	var _into: Dictionary
	var _world: Node
	var _prepare: Callable
	var _table: ActorsScript = null
	## The body of each body area, made or kept.
	var _bodies: Dictionary[String, Node] = {}
	## The object restored for each number.
	var _made: Dictionary[int, Object] = {}
	## Objects already written (one takes one snapshot object's members).
	var _claimed: Dictionary[int, bool] = {}
	## References to resolve: [container, key, Ref or ObjectRef].
	var _pending: Array = []
	## Every object written, the innermost first (for `rebuild_derived`), and the outermost first (for
	## `restore_nodes`: a holder sets up what it holds before that one makes its nodes).
	var _restored: Array[Object] = []
	var _entered: Array[Object] = []
	## False for the pass that readies a body before it enters the tree: it resolves and rebuilds
	## nothing.
	var _full: bool = true

	func _init(snapshot: Snapshot, into: Dictionary, world: Node, prepare: Callable) -> void:
		_snapshot = snapshot
		_into = into
		_world = world
		_prepare = prepare
		_table = Snapshot.table_in(into)

	func restore_all() -> void:
		_restore_bodies()
		# Each area is written as itself, never as a member another area held before.
		for name: String in _snapshot.areas:
			var area: Object = _bodies[name] if _bodies.has(name) else _into.get(name) as Object
			if area != null and is_instance_valid(area):
				_claimed[area.get_instance_id()] = true
		for name: String in _snapshot.areas:
			var target: Object = _bodies[name] if _bodies.has(name) else _into.get(name) as Object
			if target == null or not is_instance_valid(target):
				Snapshot._problem(problems, name, "is an area the world has not", "make the world of the same kind before restoring")
				continue
			_root(_snapshot.areas[name], target)
		if _table != null:
			for name: String in _bodies:
				var body: Node = _bodies[name]
				_table.set_node(int(body.get(&"id")), body)
		for object in _entered:
			if is_instance_valid(object) and object.has_method(&"restore_nodes"):
				object.call(&"restore_nodes")
		for entry: Array in _pending:
			_set_at(entry[0], entry[1], _resolve(entry[2]))
		for object in _restored:
			if is_instance_valid(object) and object.has_method(&"rebuild_derived"):
				object.call(&"rebuild_derived")

	## Step 1: the world's bodies matched, freed or made.
	func _restore_bodies() -> void:
		var wanted: Dictionary[String, Body] = {}
		for body in _snapshot.bodies:
			wanted[body.area] = body
		for name: Variant in _into:
			var node: Variant = _into[name]
			if not Snapshot.is_body(node, _table):
				continue
			var body: Body = wanted.get(String(name)) as Body
			# A body on its way out (it died this frame: `queue_free`) is gone already.
			var going: bool = (node as Node).is_queued_for_deletion()
			if body != null and not going and (node as Node).scene_file_path == body.scene and (node as Node).get_script() == body.of:
				_bodies[String(name)] = node as Node
				_sync_added(node as Node, body)
			else:
				(node as Node).free()
		for body in _snapshot.bodies:
			if not _bodies.has(body.area):
				var made: Node = _make_body(body)
				if made != null:
					_bodies[body.area] = made

	## A body made again: its scene (or script), its nodes added in play, its state, `prepare`, and
	## into its parent.
	func _make_body(body: Body) -> Node:
		var node: Node = null
		if body.scene != "":
			if not body.scene.begins_with("res://") or not (body.scene.ends_with(".tscn") or body.scene.ends_with(".scn")):
				Snapshot._problem(problems, body.area, "names a scene that is no scene file (%s)" % body.scene, "make bodies from scenes under res://")
				return null
			var scene: PackedScene = ResourceLoader.load(body.scene, "PackedScene") as PackedScene
			node = scene.instantiate() if scene != null else null
		elif body.of != null and body.of.can_instantiate():
			node = body.of.new() as Node
		if node == null:
			Snapshot._problem(problems, body.area, "cannot be made again (%s)" % body.scene, "make bodies from a scene, or from a script that takes no arguments")
			return null
		node.name = body.name
		_sync_added(node, body)
		var parent: Node = _world.get_node_or_null(body.parent) if _world != null else null
		if parent == null:
			Snapshot._problem(problems, body.area, "has no parent at %s in this world" % body.parent, "make the world of the same kind before restoring")
			node.free()
			return null
		# Its state before it enters the tree, so its `_ready` sets it up as it was (its data, its id).
		var ready := Restorer.new(_snapshot, _into, _world, Callable())
		ready._full = false
		ready._root(_snapshot.areas[body.area], node)
		if _prepare.is_valid():
			_prepare.call(node)
		parent.add_child(node)
		return node

	## The nodes `body` says were added in play, made in `node` where missing; any other simulation
	## node added in play is freed.
	func _sync_added(node: Node, body: Body) -> void:
		var want: Dictionary[String, Array] = {}
		for entry: Array in body.added:
			want[str(entry[0]) + "/" + str(entry[1])] = entry
		for entry: Array in body.added:
			var parent: Node = node.get_node_or_null(entry[0] as NodePath)
			if parent == null:
				Snapshot._problem(problems, body.area, "has no node at %s for %s" % [entry[0], entry[1]], "add nodes in play under the body or its scene's nodes")
				continue
			var there: Node = parent.get_node_or_null(NodePath(String(entry[1])))
			if there != null and there.get_script() == entry[2]:
				continue
			if there != null:
				there.free()
			var script: Script = entry[2]
			var made: Node = script.new() as Node if script.can_instantiate() else null
			if made == null:
				Snapshot._problem(problems, body.area, "cannot make %s again" % entry[1], "give its script an _init that takes no arguments")
				continue
			made.name = entry[1]
			parent.add_child(made)
		for child: Node in StateWalk.added_in_play(node):
			if not want.has(str(node.get_path_to(child.get_parent())) + "/" + str(child.name)):
				child.free()

	## An area (or a body): `target` takes `record`'s members. A body first met inside another area
	## (a decoy, which Entities holds) was written there.
	func _root(record: Variant, target: Object) -> void:
		if record is Seen:
			return
		if not record is Obj:
			Snapshot._problem(problems, str(target), "was not taken as an object", "hand areas as objects of scripts")
			return
		_claimed.erase(target.get_instance_id())
		_write(record as Obj, target)

	## `target` takes `record`'s members.
	func _write(record: Obj, target: Object) -> void:
		_made[record.number] = target
		_claimed[target.get_instance_id()] = true
		_entered.append(target)
		if record.is_node and target is Node2D:
			(target as Node2D).position = record.position
		var plan: Array = StateWalk.plan(record.of)
		var names: Array = plan[0]
		if names.size() != record.values.size():
			Snapshot._problem(problems, record.of.resource_path, "has other members than when it was taken", "restore a snapshot taken by this build")
			return
		for i in names.size():
			var name: StringName = names[i]
			var now: Variant = target.get(name)
			var value: Variant = _put(record.values[i], now, target, target, name)
			if typeof(value) == TYPE_OBJECT and value == null and typeof(now) == TYPE_OBJECT and now == null:
				continue
			target.set(name, value)
		for added: Variant in record.added:
			_put(added, null, target, null, null)
		_restored.append(target)

	## The value `saved` is, made from what is there now (`now`) where it can be: an object of the
	## same script, written in place. A reference is left null and resolved later, in `container` at
	## `key`.
	func _put(saved: Variant, now: Variant, holder: Object, container: Variant, key: Variant) -> Variant:
		if typeof(saved) != TYPE_OBJECT:
			if typeof(saved) == TYPE_ARRAY:
				return (saved as Array).duplicate(true)
			if typeof(saved) >= TYPE_PACKED_BYTE_ARRAY:
				return saved.slice(0)
			return saved
		if saved == null:
			return null
		if saved is Ref or saved is ObjectRef:
			if _full:
				_pending.append([container, key, saved])
			return null
		if saved is Seen:
			return _made.get((saved as Seen).number)
		if saved is Keep:
			return (saved as Keep).object
		if saved is Resource:
			# Content (only content is kept as itself).
			return saved
		if saved is Idle:
			var idle: Idle = saved
			var fresh: Object = null
			if _reusable(now, idle.of) and bool((now as Object).call(&"idle")):
				fresh = now
			else:
				fresh = idle.of.new()
			_made[idle.number] = fresh
			_claimed[fresh.get_instance_id()] = true
			return fresh
		if saved is List:
			return _list(saved as List, now, holder)
		if saved is Table:
			return _dictionary(saved as Table, now, holder)
		if saved is Obj:
			var record: Obj = saved
			var target: Object = null
			if record.is_node:
				target = (holder as Node).get_node_or_null(record.path) if holder is Node else null
				if target == null:
					Snapshot._problem(problems, str(record.path), "is a node the world has not under %s" % str(holder), "make the body again from its scene (Snapshot's bodies)")
					return null
			elif _reusable(now, record.of):
				target = now
			else:
				target = record.of.new()
			_write(record, target)
			return target
		return saved

	## True when `now` is an object of `script` not written yet: written in place.
	func _reusable(now: Variant, script: Script) -> bool:
		if typeof(now) != TYPE_OBJECT or now == null or not is_instance_valid(now):
			return false
		var object: Object = now
		return object.get_script() == script and not object is Resource and not object is Node and not _claimed.has(object.get_instance_id())

	func _list(saved: List, now: Variant, holder: Object) -> Array:
		var out: Array = Array([], saved.builtin, saved.class_named, saved.of) if saved.builtin != TYPE_NIL else []
		if saved.spares >= 0:
			var script: Script = saved.of as Script
			for i in saved.spares:
				out.append(script.new() if script != null else null)
			return out
		var before: Array = now if typeof(now) == TYPE_ARRAY else []
		out.resize(saved.items.size())
		for i in saved.items.size():
			var was: Variant = before[i] if i < before.size() else null
			out[i] = _put(saved.items[i], was, holder, out, i)
		return out

	func _dictionary(saved: Table, now: Variant, holder: Object) -> Dictionary:
		var out: Dictionary = Dictionary({}, saved.key_builtin, saved.key_class, saved.key_of, saved.value_builtin, saved.value_class, saved.value_of)
		var before: Dictionary = now if typeof(now) == TYPE_DICTIONARY else {}
		for i in saved.keys.size():
			var key: Variant = saved.keys[i]
			out[key] = _put(saved.values[i], before.get(key), holder, out, key)
		return out

	func _resolve(link: Variant) -> Variant:
		if link is ObjectRef:
			return _made.get((link as ObjectRef).number)
		var ref: Ref = link
		var node: Node = _table.node_of(ref.id) if _table != null else null
		if node == null:
			Snapshot._problem(problems, "actor %d" % ref.id, "is pointed at but has no node in the restored world", "make every body the snapshot names (its bodies, or the area's restore_nodes)")
			return null
		if ref.path.is_empty():
			return node
		var at: Node = node.get_node_or_null(ref.path)
		if at == null:
			Snapshot._problem(problems, "actor %d/%s" % [ref.id, ref.path], "is pointed at but is not in the restored world", "add nodes in play under the body (Snapshot's bodies)")
		return at

	static func _set_at(container: Variant, key: Variant, value: Variant) -> void:
		if container is Object:
			(container as Object).set(key, value)
		elif typeof(container) == TYPE_ARRAY:
			(container as Array)[key] = value
		elif typeof(container) == TYPE_DICTIONARY:
			(container as Dictionary)[key] = value
