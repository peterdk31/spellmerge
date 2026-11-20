extends RefCounted
## What reads the light by the screen, drawn once in each view (connected biomes CB6; the
## performance pass, the owner's decision of 2026-11-20: a view's light buffer is named, never
## matched). The spell light's (`spell_light.gd`): it knows nothing of what the readers are.
##
## While the screen is split every view draws the world again, and what reads the light by its
## pixel's place on the screen (the apply rect, the lit-only motes, the mist: every canvas item drawn
## with a material handed to `watch`) must read its own view's buffer. A canvas item is drawn the
## same way in every viewport, so each reader is **one canvas item a view**: the item itself is view
## 0's, and each other view has a copy of it, a sibling just after it sharing its MultiMesh or rect,
## on that view's visibility layer only (`view_layer`), drawn with **a material a view**: a copy of
## the item's whose uniform `light_view_id` (VIEW_ID, `light_views.gdshaderinc`) names its view, every
## other uniform of the item's material copied over each frame (`follow`), so whoever sets the
## material's numbers sets every view's. (Not an instance uniform: the compatibility renderer holds
## few items with instance uniforms, 256, fewer than a split's motes chunks and their copies.) A
## view's SubViewport keeps the world's layer and its own (`view_mask`, set by the split screen), so
## it draws the world and its own copy of each reader, never another view's. The root viewport,
## drawing the one picture, keeps every layer: it draws the items themselves, and the copies are
## hidden while there is one view.
##
## The copies follow their item every frame (`follow`: shown, placed, z), are made the first frame
## a second view is drawn (`use`, from the light's `use_views`, while the game steps, so they draw
## that frame) and kept; an item that appears while split (a motes chunk made in a fight) has its
## copies from the next frame. Nothing is made a frame once every reader has its copies. A reader the
## light lets go (the light switched off, the item gone or drawn with another material) is drawn as
## any of the world's again.
##
## **Each view culls by its own box** (the performance pass, 2026-11-20): a material whose shader
## names the uniform CULL_BOX (the motes', `mote.gdshader`) is told, the item's and each view's, the
## box of the world its view shows (`use`'s boxes: the one picture's, or each view's own), and its
## vertex stage folds away a mote that cannot reach it before working out its flight. The equal
## split's void quarter is one more view (after the others: its own layer, and a light buffer that
## is none, black: the void has no light).

const ViewBoxesScript := preload("res://gameplay/feel/view_boxes.gd")

## The visibility layer of the world's canvas items (every canvas item's default), the one the root
## keeps for its canvas layers while split (the split screen's), and the first view's own.
const WORLD_LAYER: int = 1
const SCREEN_LAYER: int = 1 << 1
const VIEW_FIRST_BIT: int = 2
const VIEWS_MOST: int = 4
## The uniform naming the view a reader's material is drawn in (`light_views.gdshaderinc`), and the
## one telling a reader that culls the box of the world its view shows (x0, y0, x1, y1; all 0: none).
const VIEW_ID: StringName = &"light_view_id"
const CULL_BOX: StringName = &"view_cull_box"
## Every view's own layers together (the root drops them while split: its world is not drawn).
const ALL_VIEW_LAYERS: int = ((1 << VIEWS_MOST) - 1) << VIEW_FIRST_BIT

## The views drawn now (0 or 1: the one picture, no copy shown). Read only.
var views: int = 0
## Copies made, all told (for tests).
var made: int = 0
## By watched material: its views' materials (from view 1; null until needed), whether it culls,
## and the names of its uniforms copied to them each frame.
var _materials: Dictionary = {}
var _culls: Dictionary = {}
var _uniforms: Dictionary = {}
## The readers: each item and its copies (by view, from view 1; null until made).
var _items: Array[CanvasItem] = []
var _copies: Array[Array] = []
var _boxes: PackedVector4Array = PackedVector4Array()


func _init() -> void:
	_boxes.resize(VIEWS_MOST)


## The visibility layer of view `view`'s own readers (0 to VIEWS_MOST - 1).
static func view_layer(view: int) -> int:
	return 1 << (VIEW_FIRST_BIT + clampi(view, 0, VIEWS_MOST - 1))


## What view `view`'s SubViewport draws: the world, and its own readers.
static func view_mask(view: int) -> int:
	return WORLD_LAYER | view_layer(view)


## The items drawn with `material` read the light by the screen from now on: those in `tree` now
## (null: none) and those that come (`take`).
func watch(material: Material, tree: SceneTree) -> void:
	var shading := material as ShaderMaterial
	if shading == null or _materials.has(shading):
		return
	var by_view: Array = []
	by_view.resize(VIEWS_MOST - 1)
	_materials[shading] = by_view
	_culls[shading] = shading.shader != null and shading.shader.code.contains(String(CULL_BOX))
	var names := PackedStringArray()
	if shading.shader != null:
		for uniform: Dictionary in shading.shader.get_shader_uniform_list(true):
			var named: String = String(uniform.get("name", ""))
			if int(uniform.get("type", TYPE_NIL)) != TYPE_NIL and named != "" and named != String(VIEW_ID) and named != String(CULL_BOX):
				names.append(named)
	_uniforms[shading] = names
	if tree != null and tree.root != null:
		_scan(tree.root, shading)


## The items drawn with `material` read the light no more: they are drawn as any of the world's
## again, their copies go.
func forget(material: Material) -> void:
	if material == null or not _materials.has(material):
		return
	for i in range(_items.size() - 1, -1, -1):
		var item: CanvasItem = _items[i]
		if not is_instance_valid(item) or item.material == material:
			_drop_at(i)
	if bool(_culls[material]):
		(material as ShaderMaterial).set_shader_parameter(CULL_BOX, Vector4.ZERO)
	_materials.erase(material)
	_culls.erase(material)
	_uniforms.erase(material)


## `node`, just come into the tree: a reader when it is drawn with a watched material.
func take(node: Node) -> void:
	var item := node as CanvasItem
	if item == null or item.material == null or not _materials.has(item.material) or _is_copy(item) or _items.has(item):
		return
	item.visibility_layer = view_layer(0)
	_items.append(item)
	var copies: Array = []
	copies.resize(VIEWS_MOST - 1)
	_copies.append(copies)


## `node`, leaving the tree: a reader's copies go with it.
func release(node: Node) -> void:
	var item := node as CanvasItem
	if item == null:
		return
	var at: int = _items.find(item)
	if at >= 0:
		_drop_at(at)


## `count` views are drawn from now on (0 or 1: the one picture): each reader gets its copies for
## them (made now, while the game steps, so they draw this frame). `boxes` (null: none, nothing is
## culled) holds each view's part of the world, box `k` view `k`'s: what a reader that culls is told.
func use(count: int, boxes: ViewBoxesScript = null) -> void:
	views = clampi(count, 0, VIEWS_MOST)
	for k in VIEWS_MOST:
		var box: Rect2 = boxes.boxes[k] if boxes != null and k < boxes.count else Rect2()
		_boxes[k] = Vector4(box.position.x, box.position.y, box.end.x, box.end.y) if box.has_area() else Vector4.ZERO
	for i in range(_items.size() - 1, -1, -1):
		if not is_instance_valid(_items[i]):
			_drop_at(i)
			continue
		# An item drawn with a material no longer watched (a pool made anew): a reader no more.
		if not _materials.has(_items[i].material):
			_drop_at(i)
			continue
		for view in range(1, views):
			if _copies[i][view - 1] == null:
				_copies[i][view - 1] = _copy_of(_items[i], view)
	for material: ShaderMaterial in _materials:
		if bool(_culls[material]):
			material.set_shader_parameter(CULL_BOX, _boxes[0])
			for view in range(1, views):
				var own: ShaderMaterial = _material_of(material, view)
				own.set_shader_parameter(CULL_BOX, _boxes[view])
	follow()


## The box view `view` culls by now (x0, y0, x1, y1; zero: none; for tests).
func box_of(view: int) -> Vector4:
	return _boxes[view] if view >= 0 and view < VIEWS_MOST else Vector4.ZERO


## The copies set as their items are (shown only for the views drawn), and placed just after them;
## each view's material given its item material's uniforms. Run every frame before drawing.
func follow() -> void:
	for i in _items.size():
		var item: CanvasItem = _items[i]
		if not is_instance_valid(item):
			continue
		var copies: Array = _copies[i]
		for view in range(1, VIEWS_MOST):
			var copy: CanvasItem = copies[view - 1]
			if copy == null or not is_instance_valid(copy):
				continue
			var shown: bool = view < views and item.visible
			if copy.visible != shown:
				copy.visible = shown
			if shown:
				_follow(copy, item, view)
	if views < 2:
		return
	for material: ShaderMaterial in _materials:
		var by_view: Array = _materials[material]
		var names: PackedStringArray = _uniforms[material]
		for view in range(1, views):
			var own := by_view[view - 1] as ShaderMaterial
			if own == null:
				continue
			for named in names:
				var value: Variant = material.get_shader_parameter(named)
				if own.get_shader_parameter(named) != value:
					own.set_shader_parameter(named, value)


## The readers (for tests).
func items() -> Array[CanvasItem]:
	return _items


## The copy of `item` for view `view` (null for none; for tests).
func copy_of(item: CanvasItem, view: int) -> CanvasItem:
	var at: int = _items.find(item)
	if at < 0 or view < 1 or view >= VIEWS_MOST:
		return null
	return _copies[at][view - 1]


## Every reader let go (drawn as any of the world's again), its copies freed (the light freed).
func clear() -> void:
	for i in range(_items.size() - 1, -1, -1):
		_drop_at(i)
	for material: ShaderMaterial in _materials:
		if bool(_culls[material]):
			material.set_shader_parameter(CULL_BOX, Vector4.ZERO)
	_materials.clear()
	_culls.clear()
	_uniforms.clear()


## View `view`'s material for items drawn with `material` (made the first time: a copy naming it).
func _material_of(material: ShaderMaterial, view: int) -> ShaderMaterial:
	var by_view: Array = _materials[material]
	if by_view[view - 1] == null:
		var own := material.duplicate() as ShaderMaterial
		own.set_shader_parameter(VIEW_ID, view)
		by_view[view - 1] = own
	return by_view[view - 1]


func _scan(node: Node, material: Material) -> void:
	var item := node as CanvasItem
	if item != null and item.material == material:
		take(item)
	for child in node.get_children():
		_scan(child, material)


## Reader `at` let go: its copies freed, and the item on the world's layer again, so with the light
## gone every view draws it.
func _drop_at(at: int) -> void:
	for copy: Variant in _copies[at]:
		var node := copy as CanvasItem
		if node != null and is_instance_valid(node):
			node.queue_free()
	var item: CanvasItem = _items[at]
	if is_instance_valid(item):
		item.visibility_layer = WORLD_LAYER
	_items.remove_at(at)
	_copies.remove_at(at)


func _is_copy(item: CanvasItem) -> bool:
	return item.has_meta(VIEW_ID)


## A copy of `item` drawn in view `view` alone, a sibling just after it (its earlier views' copies
## between), with that view's material.
func _copy_of(item: CanvasItem, view: int) -> CanvasItem:
	if not item.is_inside_tree() or item.get_parent() == null or not _materials.has(item.material):
		return null
	var copy := item.duplicate(0) as CanvasItem
	if copy == null:
		return null
	copy.name = "%sView%d" % [item.name, view]
	copy.set_meta(VIEW_ID, view)
	copy.visibility_layer = view_layer(view)
	copy.material = _material_of(item.material as ShaderMaterial, view)
	copy.visible = false
	item.add_sibling(copy)
	made += 1
	_follow(copy, item, view)
	return copy


## `copy` (view `view`'s) drawn as `item` is: the same place, z and look, just after it (and its
## copies for the views before).
func _follow(copy: CanvasItem, item: CanvasItem, view: int) -> void:
	var shading := item.material as ShaderMaterial
	if shading != null and _materials.has(shading):
		var own: ShaderMaterial = _material_of(shading, view)
		if copy.material != own:
			copy.material = own
	if copy.z_index != item.z_index:
		copy.z_index = item.z_index
	if copy.top_level != item.top_level:
		copy.top_level = item.top_level
	if copy.modulate != item.modulate:
		copy.modulate = item.modulate
	if copy.self_modulate != item.self_modulate:
		copy.self_modulate = item.self_modulate
	var node := item as Node2D
	if node != null:
		var to := copy as Node2D
		if to.transform != node.transform:
			to.transform = node.transform
		var batch := item as MultiMeshInstance2D
		if batch != null:
			var into := copy as MultiMeshInstance2D
			if into.multimesh != batch.multimesh:
				into.multimesh = batch.multimesh
			if into.texture != batch.texture:
				into.texture = batch.texture
	var control := item as Control
	if control != null:
		var to := copy as Control
		if to.position != control.position:
			to.position = control.position
		if to.size != control.size:
			to.size = control.size
	var parent: Node = item.get_parent()
	if copy.get_parent() == parent:
		var want: int = mini(item.get_index() + view, parent.get_child_count() - 1)
		if copy.get_index() != want:
			parent.move_child(copy, want)
