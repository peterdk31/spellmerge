extends Node
## A diagnostic profile of the whole frame (horde swarm S4, docs/milestones/horde-swarm.md): where a
## frame's time goes, by script, without Godot's debugger. The stress run adds it on `--profile`
## (`stress.gd -- --horde-swarm --profile`); it changes the order nodes process in, so it is never
## part of a normal measured run.
##
## How: every node that processes (`_process` or `_physics_process`) is put in a group by its script
## (or its class without one), each group gets its own processing priority, and a marker node runs
## between two groups and reads the clock. So a group's time is the clock between its marker and the
## next. Markers run first and last in each phase, so the frame splits into: the physics steps'
## scripts, the process scripts, and the engine's own time between them (the physics server's step
## and its queries, the message queue with deferred calls and frees, the renderer). Nodes added
## after a scan process at their own priority and are counted in the "(not scanned)" group until the
## next scan (every RESCAN seconds). `census()` counts the tree's nodes by script or class.
##
## Signal handlers: `time_signals(source, names)` puts a timing proxy between `source`'s signals
## and every listener (each listener's time and calls, per signal), for the hot events. It allocates
## per call (an argument array), so it is a diagnostic only.

const RESCAN: float = 0.5
## Each group's priority is BASE + 2 * its index + 1; its marker sits at BASE + 2 * index.
const BASE: int = 1000
const FIRST: int = -2000000000
const LAST: int = 2000000000
const NOT_SCANNED: String = "(not scanned)"

var _physics_groups: Dictionary[String, int] = {}
var _process_groups: Dictionary[String, int] = {}
var _physics_names: Array[String] = []
var _process_names: Array[String] = []
## Per group: microseconds summed, and the marker times of the current pass.
var _physics_usec: Array[int] = []
var _process_usec: Array[int] = []
var _physics_marks: Array[int] = []
var _process_marks: Array[int] = []
var _physics_markers: Array[Node] = []
var _process_markers: Array[Node] = []
var _scan_left: float = 0.0
## The frame: when the process phase began last, and the sums.
var _frame_start: int = -1
var _frames: int = 0
var _frame_usec: int = 0
var _physics_steps: int = 0
var _physics_script_usec: int = 0
var _physics_step_max_usec: int = 0
var _process_script_usec: int = 0
var _physics_begin: int = 0
var _process_begin: int = 0
## Engine time: the frame less the scripts of both phases.
var _peak_census: Dictionary[String, int] = {}
var _peak_nodes: int = 0
## Signal timing: "signal -> listener" to [usec, calls].
var _signal_usec: Dictionary[String, int] = {}
var _signal_calls: Dictionary[String, int] = {}
var _proxies: Array[RefCounted] = []


class Marker:
	extends Node
	var profile: Node
	var index: int
	var physics: bool

	func _ready() -> void:
		# Godot turns processing on at ready for a script with the callback: one phase only.
		set_process(not physics)
		set_physics_process(physics)

	func _physics_process(_delta: float) -> void:
		profile.call(&"mark", true, index)

	func _process(_delta: float) -> void:
		profile.call(&"mark", false, index)


class Proxy:
	extends RefCounted
	var profile: Node
	var key: String
	var target: Callable
	var source: Object
	var signal_name: StringName
	var arity: int

	func on0() -> void:
		_run([])

	func on1(a: Variant) -> void:
		_run([a])

	func on2(a: Variant, b: Variant) -> void:
		_run([a, b])

	func on3(a: Variant, b: Variant, c: Variant) -> void:
		_run([a, b, c])

	func on4(a: Variant, b: Variant, c: Variant, d: Variant) -> void:
		_run([a, b, c, d])

	func on5(a: Variant, b: Variant, c: Variant, d: Variant, e: Variant) -> void:
		_run([a, b, c, d, e])

	func on6(a: Variant, b: Variant, c: Variant, d: Variant, e: Variant, f: Variant) -> void:
		_run([a, b, c, d, e, f])

	func _run(args: Array) -> void:
		if not target.is_valid():
			return
		var start: int = Time.get_ticks_usec()
		target.callv(args)
		profile.call(&"count_signal", key, Time.get_ticks_usec() - start)


func _ready() -> void:
	process_priority = FIRST
	process_physics_priority = FIRST
	_add_marker(true, LAST - 1, -2)
	_add_marker(false, LAST - 1, -2)
	_scan()


func _physics_process(delta: float) -> void:
	_physics_begin = Time.get_ticks_usec()
	_physics_marks.fill(-1)
	_scan_left -= delta


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	if _frame_start >= 0:
		_frames += 1
		_frame_usec += now - _frame_start
	_frame_start = now
	_process_marks.fill(-1)
	if _scan_left <= 0.0:
		_scan_left = RESCAN
		_scan()
	# The scan is the profile's own cost: the process scripts start after it.
	_process_begin = Time.get_ticks_usec()
	_frame_usec -= _process_begin - now


## A marker ran: `index` is its group's index (the group after it), -2 the phase's end.
func mark(physics: bool, index: int) -> void:
	var now: int = Time.get_ticks_usec()
	var marks: Array[int] = _physics_marks if physics else _process_marks
	if index >= 0:
		marks[index] = now
		return
	# The phase ended: each group runs from its marker to the next marker that ran (or the end).
	var sums: Array[int] = _physics_usec if physics else _process_usec
	var next: int = now
	for g in range(marks.size() - 1, -1, -1):
		if marks[g] >= 0:
			sums[g] += next - marks[g]
			next = marks[g]
	var begin: int = _physics_begin if physics else _process_begin
	# The not-scanned nodes (group 0, no marker) run at their own priority: from the phase's start
	# to the first marker.
	sums[0] += next - begin
	if physics:
		_physics_steps += 1
		_physics_script_usec += now - begin
		_physics_step_max_usec = maxi(_physics_step_max_usec, now - begin)
	else:
		_process_script_usec += now - begin


func count_signal(key: String, usec: int) -> void:
	_signal_usec[key] = _signal_usec.get(key, 0) + usec
	_signal_calls[key] = _signal_calls.get(key, 0) + 1


## Every processing node into its group's priority; new groups get a marker.
func _scan() -> void:
	_group(NOT_SCANNED, true)
	_group(NOT_SCANNED, false)
	var stack: Array[Node] = [get_tree().root]
	var census: Dictionary[String, int] = {}
	var nodes: int = 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		nodes += 1
		if node is Marker or node == self:
			continue
		var key: String = _key(node)
		census[key] = census.get(key, 0) + 1
		if node.is_physics_processing():
			node.process_physics_priority = BASE + 2 * _group(key, true) + 1
		if node.is_processing():
			node.process_priority = BASE + 2 * _group(key, false) + 1
	if nodes > _peak_nodes:
		_peak_nodes = nodes
		_peak_census = census


func _group(key: String, physics: bool) -> int:
	var groups: Dictionary[String, int] = _physics_groups if physics else _process_groups
	if groups.has(key):
		return groups[key]
	var index: int = groups.size()
	groups[key] = index
	if physics:
		_physics_names.append(key)
		_physics_usec.append(0)
		_physics_marks.append(-1)
	else:
		_process_names.append(key)
		_process_usec.append(0)
		_process_marks.append(-1)
	if key != NOT_SCANNED:
		_add_marker(physics, BASE + 2 * index, index)
	return index


func _add_marker(physics: bool, priority: int, index: int) -> void:
	var marker := Marker.new()
	marker.profile = self
	marker.index = index
	marker.physics = physics
	marker.set_process(not physics)
	marker.set_physics_process(physics)
	if physics:
		marker.process_physics_priority = priority
	else:
		marker.process_priority = priority
	add_child(marker)


func _key(node: Node) -> String:
	var script: Script = node.get_script() as Script
	if script != null:
		var path: String = script.resource_path
		if path.is_empty():
			return node.get_class() + " (inner script)"
		return path.get_file().get_basename()
	return node.get_class()


## Times every listener of `source`'s signals `names` (see the class doc). Only direct, persistent
## connections are proxied.
func time_signals(source: Object, names: Array[StringName]) -> void:
	for signal_name in names:
		var arity: int = 0
		for info: Dictionary in source.get_signal_list():
			if info["name"] == signal_name:
				arity = (info["args"] as Array).size()
		for connection: Dictionary in source.get_signal_connection_list(signal_name):
			var flags: int = connection["flags"]
			if flags & (CONNECT_DEFERRED | CONNECT_ONE_SHOT) != 0:
				continue
			var callable: Callable = connection["callable"]
			var object: Object = callable.get_object()
			var who: String = _key(object) if object is Node else (object.get_script().resource_path.get_file().get_basename() if object != null and object.get_script() != null else str(object))
			var proxy := Proxy.new()
			proxy.profile = self
			proxy.key = "%s -> %s.%s" % [signal_name, who, callable.get_method()]
			proxy.target = callable
			proxy.source = source
			proxy.signal_name = signal_name
			proxy.arity = arity
			source.disconnect(signal_name, callable)
			source.connect(signal_name, Callable(proxy, "on%d" % arity))
			_proxies.append(proxy)


## Puts every proxied listener back on its signal.
func untime_signals() -> void:
	for proxy: Proxy in _proxies:
		if not is_instance_valid(proxy.source):
			continue
		var through: Callable = Callable(proxy, "on%d" % proxy.arity)
		if proxy.source.is_connected(proxy.signal_name, through):
			proxy.source.disconnect(proxy.signal_name, through)
		if proxy.target.is_valid() and not proxy.source.is_connected(proxy.signal_name, proxy.target):
			proxy.source.connect(proxy.signal_name, proxy.target)
	_proxies.clear()


func report() -> void:
	untime_signals()
	var frames: float = maxf(1.0, float(_frames))
	var steps: float = maxf(1.0, float(_physics_steps))
	var physics_ms: float = float(_physics_script_usec) / frames / 1000.0
	var process_ms: float = float(_process_script_usec) / frames / 1000.0
	var frame_ms: float = float(_frame_usec) / frames / 1000.0
	print("PROFILE: %d frames, frame avg %.2f ms = physics scripts %.2f ms (%.2f steps a frame, %.2f ms a step, max %.2f) + process scripts %.2f ms + engine %.2f ms (physics server, message queue and frees, renderer)" % [_frames, frame_ms, physics_ms, float(_physics_steps) / frames, float(_physics_script_usec) / steps / 1000.0, float(_physics_step_max_usec) / 1000.0, process_ms, frame_ms - physics_ms - process_ms])
	_print_groups("physics, per step", _physics_names, _physics_usec, steps)
	_print_groups("process, per frame", _process_names, _process_usec, frames)
	var keys: Array[String] = []
	keys.assign(_signal_usec.keys())
	keys.sort_custom(func(a: String, b: String) -> bool: return _signal_usec[a] > _signal_usec[b])
	for key in keys:
		print("PROFILE: signal %s: %.3f ms a frame, %.1f calls a frame, %.1f us a call" % [key, float(_signal_usec[key]) / frames / 1000.0, float(_signal_calls[key]) / frames, float(_signal_usec[key]) / maxf(1.0, float(_signal_calls[key]))])
	var census: Array[String] = []
	census.assign(_peak_census.keys())
	census.sort_custom(func(a: String, b: String) -> bool: return _peak_census[a] > _peak_census[b])
	var line: PackedStringArray = PackedStringArray()
	for key in census:
		if _peak_census[key] >= 5:
			line.append("%s %d" % [key, _peak_census[key]])
	print("PROFILE: nodes at the peak scan %d: %s" % [_peak_nodes, ", ".join(line)])


func _print_groups(label: String, names: Array[String], usec: Array[int], per: float) -> void:
	var order: Array[int] = []
	for g in names.size():
		order.append(g)
	order.sort_custom(func(a: int, b: int) -> bool: return usec[a] > usec[b])
	for g in order:
		var ms: float = float(usec[g]) / per / 1000.0
		if ms >= 0.01:
			print("PROFILE: %s: %s %.3f ms" % [label, names[g], ms])
