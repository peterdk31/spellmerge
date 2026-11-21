extends RefCounted
## A diagnostic count of what a frame draws, for finding draw calls and batch breaks (the owner,
## 2026-11-21: "find more ways to bring down the frame time ... reduce draw calls"). The biome
## frames' runner takes one at the middle of a scenario's measured window with `--census`.
##
## It prints:
##  - `census viewports`: each drawing viewport's 2D items, draw calls and primitives this frame
##    (`RenderingServer.viewport_get_render_info`, the canvas's own counts);
##  - `census nodes`: the tree's nodes, the ones that process or physics-process, and the canvas
##    items shown (visible in the tree), by kind;
##  - `census materials`: the shown canvas items by the shader they draw with (a batch breaks at
##    every change of shader, texture or kind of command between items drawn one after another);
##  - `census multimeshes`: the shown 2D MultiMesh nodes (a draw call each) and their instances.

const TOP: int = 24


## Prints the census of `tree`'s frame under `label`.
static func report(tree: SceneTree, label: String) -> void:
	var root: Viewport = tree.root
	var viewports: Array[Node] = root.find_children("*", "SubViewport", true, false)
	viewports.push_front(root)
	var parts := PackedStringArray()
	for node in viewports:
		var viewport := node as Viewport
		var rid: RID = viewport.get_viewport_rid()
		var items: int = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
		var calls: int = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var primitives: int = RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		if calls == 0 and items == 0:
			continue
		parts.append("%s: %d items, %d calls, %d prims" % [_short_path(viewport), items, calls, primitives])
	print("BENCH: census %s viewports: %s" % [label, "; ".join(parts)])
	var total: int = 0
	var processing: int = 0
	var physics: int = 0
	var shown: Dictionary[String, int] = {}
	var by_shader: Dictionary[String, int] = {}
	var multimeshes: Dictionary[String, int] = {}
	var instances: Dictionary[String, int] = {}
	var shown_total: int = 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		total += 1
		if node.is_processing() or node.is_processing_internal():
			processing += 1
		if node.is_physics_processing() or node.is_physics_processing_internal():
			physics += 1
		for child in node.get_children(true):
			stack.append(child)
		var item := node as CanvasItem
		if item == null or not item.is_visible_in_tree():
			continue
		shown_total += 1
		var kind: String = _kind(node)
		shown[kind] = shown.get(kind, 0) + 1
		var shader_name: String = _shader_of(item)
		by_shader[shader_name] = by_shader.get(shader_name, 0) + 1
		var batch := node as MultiMeshInstance2D
		if batch != null and batch.multimesh != null:
			var drawn: int = batch.multimesh.visible_instance_count
			if drawn < 0:
				drawn = batch.multimesh.instance_count
			if drawn > 0:
				var key: String = "%s [%s]" % [kind, shader_name]
				multimeshes[key] = multimeshes.get(key, 0) + 1
				instances[key] = instances.get(key, 0) + drawn
	print("BENCH: census %s nodes: %d in the tree, %d process, %d physics process, %d canvas items shown; by kind: %s" % [label, total, processing, physics, shown_total, _top(shown)])
	print("BENCH: census %s materials (shown items by shader): %s" % [label, _top(by_shader)])
	var batch_parts := PackedStringArray()
	var keys: Array = multimeshes.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return multimeshes[a] > multimeshes[b])
	for key: String in keys.slice(0, TOP):
		batch_parts.append("%s x%d (%d instances)" % [key, multimeshes[key], instances[key]])
	print("BENCH: census %s multimeshes drawing (%d): %s" % [label, keys.size(), "; ".join(batch_parts)])


static func _kind(node: Node) -> String:
	var script: Script = node.get_script() as Script
	if script != null and script.resource_path != "":
		return script.resource_path.get_file().get_basename()
	return node.get_class()


static func _shader_of(item: CanvasItem) -> String:
	var material: Material = item.material
	if material == null and item.use_parent_material:
		var parent := item.get_parent() as CanvasItem
		while parent != null and material == null:
			material = parent.material
			if not parent.use_parent_material:
				break
			parent = parent.get_parent() as CanvasItem
	var shader_material := material as ShaderMaterial
	if shader_material != null and shader_material.shader != null:
		var path: String = shader_material.shader.resource_path
		return path.get_file() if path != "" else "(inline shader)"
	if material != null:
		return material.get_class()
	return "(none)"


static func _top(counts: Dictionary[String, int]) -> String:
	var keys: Array = counts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return counts[a] > counts[b])
	var parts := PackedStringArray()
	for key: String in keys.slice(0, TOP):
		parts.append("%s %d" % [key, counts[key]])
	return ", ".join(parts)


static func _short_path(viewport: Viewport) -> String:
	if viewport.get_parent() == null:
		return "root"
	return "%s/%s" % [viewport.get_parent().name, viewport.name]


## Which parts of the tree the frame's draw calls come from (`--census-calls`): each shown canvas
## item near the top of its canvas (CANDIDATE_DEPTH levels below an item whose parent draws
## nothing) is hidden for a few frames and the frame's draw calls and primitives read before and
## after (`RenderingServer.get_rendering_info`, every viewport's). It changes what is drawn while
## it runs, so a scenario's times are off: a diagnostic only.
class CallProbe:
	extends Node

	const CANDIDATE_DEPTH: int = 3
	## Frames a state is held (the counts read are the last drawn frame's).
	const HOLD: int = 3
	var label: String = ""
	var _candidates: Array[CanvasItem] = []
	var _depths: PackedInt32Array = PackedInt32Array()
	var _index: int = -1
	var _wait: int = 0
	var _base_calls: int = 0
	var _base_prims: int = 0
	var _lines: PackedStringArray = PackedStringArray()
	var _hidden: bool = false

	## Pauses `tree` (the probe alone processes, so what is drawn holds still) and probes it.
	func start(tree: SceneTree, what: String) -> void:
		label = what
		process_mode = Node.PROCESS_MODE_ALWAYS
		tree.paused = true
		var stack: Array[Node] = [tree.root]
		var depth_of: Dictionary[Node, int] = {}
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			for child in node.get_children(true):
				stack.append(child)
			var item := node as CanvasItem
			if item == null or not item.is_visible_in_tree():
				continue
			var parent_item := node.get_parent() as CanvasItem
			var depth: int = depth_of.get(parent_item, -1) + 1 if parent_item != null else 0
			depth_of[node] = depth
			if depth <= CANDIDATE_DEPTH:
				_candidates.append(item)
				_depths.append(depth)
		_wait = HOLD
		print("BENCH: census %s calls: probing %d canvas items" % [label, _candidates.size()])

	func _process(_delta: float) -> void:
		_wait -= 1
		if _wait > 0:
			return
		_wait = HOLD
		var calls: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var prims: int = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		if _index >= 0 and _hidden:
			# The candidate was hidden for HOLD frames: what it saved, then shown again.
			var item: CanvasItem = _candidates[_index]
			if is_instance_valid(item):
				item.visible = true
			if _base_calls - calls != 0 or _base_prims - prims > 50:
				_lines.append("%s%s: %d calls, %d prims" % ["  ".repeat(_depths[_index]), _name_of(item) if is_instance_valid(item) else "(freed)", _base_calls - calls, _base_prims - prims])
			_hidden = false
			return
		if _index < 0:
			print("BENCH: census %s calls: %d draw calls, %d primitives before" % [label, calls, prims])
		_index += 1
		while _index < _candidates.size() and not (is_instance_valid(_candidates[_index]) and _candidates[_index].visible):
			_index += 1
		if _index >= _candidates.size():
			print("BENCH: census %s calls by part (hidden: calls and primitives saved):\n%s" % [label, "\n".join(_lines)])
			get_tree().paused = false
			queue_free()
			return
		_base_calls = calls
		_base_prims = prims
		_candidates[_index].visible = false
		_hidden = true

	static func _name_of(item: CanvasItem) -> String:
		var script: Script = item.get_script() as Script
		var kind: String = script.resource_path.get_file().get_basename() if script != null and script.resource_path != "" else item.get_class()
		return "%s (%s)" % [item.name, kind]
