extends RefCounted
## What reads the light by the screen, drawn in each view (connected biomes CB6; the performance
## pass, the owner's decisions of 2026-11-20). The spell light's (`spell_light.gd`): it knows nothing
## of what the readers are.
##
## While the screen is split every view draws the world again, and what reads the light by its
## pixel's place on the screen (the apply rect, the lit-only motes, the mist: every canvas item drawn
## with a material handed to `watch`) must read its own view's buffer. A canvas item is drawn the
## same way in every viewport, so:
##
## - **The first two views share the item** (SHARED; the owner, 2026-11-20, after #890: a copy a view
##   cost about 1.5 ms of CPU a split frame, and most splits are of two). It is on the first views'
##   layer (`view_layer(0)`, which views 0 and 1 both draw), and its shader tells the two apart by
##   what it is drawn through: each view's canvas transform and size are handed to its material each
##   frame (`follow`: SHARED_KEYS and SHARED_SIZES, and SHARED_ON while two views or more are drawn),
##   and `light_views.gdshaderinc`'s `light_view_of` picks the nearer of the two by `CANVAS_MATRIX`
##   and `SCREEN_MATRIX` (`view_of` here, line for line). Two views only draw through the same
##   transform at the same size when they draw the same picture, and then either buffer holds its
##   light.
## - **The third and fourth views each draw a copy of it** (a sibling just after it sharing its
##   MultiMesh or rect, on that view's visibility layer only, `view_layer`), drawn with **a material
##   a view**: a copy of the item's whose uniform `light_view_id` (VIEW_ID) names its view, every other
##   uniform of the item's material copied over each frame (`follow`), so whoever sets the material's
##   numbers sets every view's. (Not an instance uniform: the compatibility renderer holds few items
##   with instance uniforms, 256, fewer than a split's motes chunks and their copies.)
##
## A view's SubViewport keeps the world's layer and its own (`view_mask`, set by the split screen),
## so it draws the world and its own copy of each reader (or the shared item), never another view's.
## The root viewport, drawing the one picture, keeps every layer: it draws the items themselves, and
## the copies are hidden while there are fewer than three views.
##
## The copies follow their item every frame (`follow`, once, just before the draw: shown, placed, z),
## are made the first frame a third view is drawn (`use`, from the light's `use_views`, while the game
## steps, so they draw that frame) and kept; an item that appears while split in three (a motes chunk made in a fight) has its
## copies from the next frame. Nothing is made a frame once every reader has its copies. A reader the
## light lets go (the light switched off, the item gone or drawn with another material) is drawn as
## any of the world's again. The equal split's void quarter is one more view (after the others: its
## own layer, and a light buffer that is none, black: the void has no light).
##
## **Only what changed is followed** (the perf plan's F2, 2026-11-28: a 4-view frame spent 5.7 ms here,
## following each copy twice and copying every uniform of every material a view, nearly all of it
## unchanged): what each item showed when its copies last followed it (`_seen_*`) and each watched
## material's uniforms as last copied (`_seen_values`) are kept, and a copy, or a view's material, is
## touched only when its item's or material's differ, when the views drawn changed, or when it is
## new. Nothing but this script sets a copy or a view's material.

## The visibility layer of the world's canvas items (every canvas item's default), the one the root
## keeps for its canvas layers while split (the split screen's), and the first views' own.
const WORLD_LAYER: int = 1
const SCREEN_LAYER: int = 1 << 1
const VIEW_FIRST_BIT: int = 2
const VIEWS_MOST: int = 4
## The views that draw the reader itself (each told apart in its shader); a copy for each past them.
const SHARED: int = 2
## The uniform naming the view a copy's material is drawn in (`light_views.gdshaderinc`; 0 the item's
## own: the one picture or a shared view), and those telling the item's material the shared views'
## canvas transforms (scale, origin x, origin y, 0) and sizes (px), and whether they are drawn.
const VIEW_ID: StringName = &"light_view_id"
const SHARED_ON: StringName = &"light_views_shared"
const SHARED_KEYS: Array[StringName] = [&"light_view_0", &"light_view_1"]
const SHARED_SIZES: Array[StringName] = [&"light_view_size_0", &"light_view_size_1"]
## How much a pixel of size counts against a pixel of origin in telling two views apart (`view_of`;
## the shader's LIGHT_SIZE_WEIGHT): only where their transforms are the same.
const SIZE_WEIGHT: float = 0.001
## Every view's own layers together (the root drops them while split: its world is not drawn).
const ALL_VIEW_LAYERS: int = ((1 << (VIEWS_MOST - SHARED + 1)) - 1) << VIEW_FIRST_BIT

## The views drawn now (0 or 1: the one picture). Read only.
var views: int = 0
## Copies made, all told (for tests).
var made: int = 0
## By watched material: its copies' materials by view (from view SHARED; null until needed), and
## the names of its uniforms copied to them each frame (StringNames: a String name is looked up anew
## at every read).
var _materials: Dictionary = {}
var _uniforms: Dictionary = {}
## The readers: each item and its copies (by view, from view SHARED; null until made).
var _items: Array[CanvasItem] = []
var _copies: Array[Array] = []
## The shared views' keys as last handed to the materials (`follow`).
var _keys: PackedVector4Array = PackedVector4Array()
var _sizes: PackedVector2Array = PackedVector2Array()
var _shared_on: bool = false
## Whether the shared views' keys changed since they were last handed to every watched material.
var _keys_changed: bool = true
## Copies followed, all told (for tests: nothing is followed while nothing changes).
var followed: int = 0
## What each item showed when its copies last followed it (by item, as `_items`): visible, top
## level and its index among its siblings (bits), z, modulate and self modulate (2 a reader), transform (3 vectors a reader: its x, y
## and origin; a control's position, size and zero), material, MultiMesh and texture (3 a reader).
## `_seen_views`: the views drawn then (-1: not yet; a copy made since, or another count, follows all).
var _seen_bits: PackedInt32Array = PackedInt32Array()
var _seen_z: PackedInt32Array = PackedInt32Array()
var _seen_colors: PackedColorArray = PackedColorArray()
var _seen_vectors: PackedVector2Array = PackedVector2Array()
var _seen_refs: Array[Object] = []
var _seen_views: PackedInt32Array = PackedInt32Array()
## By watched material: its uniforms' values as last copied to its views' materials (as `_uniforms`),
## and the views drawn then (-1: none yet, or a view's material made since).
var _seen_values: Dictionary = {}
var _values_views: Dictionary = {}

func _init() -> void:
	_keys.resize(SHARED)
	_sizes.resize(SHARED)


## The visibility layer of view `view`'s own readers (0 to VIEWS_MOST - 1): the first SHARED views
## share the first.
static func view_layer(view: int) -> int:
	return 1 << (VIEW_FIRST_BIT + maxi(clampi(view, 0, VIEWS_MOST - 1) - SHARED + 1, 0))


## What view `view`'s SubViewport draws: the world, and its own readers.
static func view_mask(view: int) -> int:
	return WORLD_LAYER | view_layer(view)


## A view's key, as its shader reads it: the canvas transform `drawn` it draws the world through
## (its scale, its origin) (`CANVAS_MATRIX`).
static func key_of(drawn: Transform2D) -> Vector4:
	return Vector4(drawn.x.x, drawn.origin.x, drawn.origin.y, 0.0)


## The shared view (0 or 1) an item drawn through the canvas transform `drawn` into a viewport of
## `size` is in, the views' keys `keys` and sizes `sizes` (`key_of`, as handed to its material): the
## nearer of the two. `light_views.gdshaderinc`'s `light_view_of`, line for line (for tests).
static func view_of(drawn: Transform2D, size: Vector2, keys: PackedVector4Array, sizes: PackedVector2Array) -> int:
	var best: int = 0
	var nearest: float = 1e30
	for k in SHARED:
		var v: Vector4 = keys[k]
		var d: float = absf(drawn.x.x - v.x) * 4096.0 + absf(drawn.origin.x - v.y) + absf(drawn.origin.y - v.z)
		d += (absf(size.x - sizes[k].x) + absf(size.y - sizes[k].y)) * SIZE_WEIGHT
		if d < nearest:
			nearest = d
			best = k
	return best


## The items drawn with `material` read the light by the screen from now on: those in `tree` now
## (null: none) and those that come (`take`).
func watch(material: Material, tree: SceneTree) -> void:
	var shading := material as ShaderMaterial
	if shading == null or _materials.has(shading):
		return
	var by_view: Array = []
	by_view.resize(VIEWS_MOST - SHARED)
	_materials[shading] = by_view
	var names: Array[StringName] = []
	var own: PackedStringArray = PackedStringArray([String(VIEW_ID), String(SHARED_ON)])
	for k in SHARED:
		own.append(String(SHARED_KEYS[k]))
		own.append(String(SHARED_SIZES[k]))
	if shading.shader != null:
		for uniform: Dictionary in shading.shader.get_shader_uniform_list(true):
			var named: String = String(uniform.get("name", ""))
			if int(uniform.get("type", TYPE_NIL)) != TYPE_NIL and named != "" and not own.has(named):
				names.append(StringName(named))
	_uniforms[shading] = names
	var values: Array = []
	values.resize(names.size())
	_seen_values[shading] = values
	_values_views[shading] = -1
	_hand_keys(shading)
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
	(material as ShaderMaterial).set_shader_parameter(SHARED_ON, false)
	_materials.erase(material)
	_uniforms.erase(material)
	_seen_values.erase(material)
	_values_views.erase(material)


## `node`, just come into the tree: a reader when it is drawn with a watched material.
func take(node: Node) -> void:
	var item := node as CanvasItem
	if item == null or item.material == null or not _materials.has(item.material) or _is_copy(item) or _items.has(item):
		return
	item.visibility_layer = view_layer(0)
	_items.append(item)
	var copies: Array = []
	copies.resize(VIEWS_MOST - SHARED)
	_copies.append(copies)
	_seen_bits.append(0)
	_seen_z.append(0)
	for k in 2:
		_seen_colors.append(Color())
	for k in 3:
		_seen_vectors.append(Vector2.ZERO)
		_seen_refs.append(null)
	_seen_views.append(-1)


## `node`, leaving the tree: a reader's copies go with it.
func release(node: Node) -> void:
	var item := node as CanvasItem
	if item == null:
		return
	var at: int = _items.find(item)
	if at >= 0:
		_drop_at(at)


## `count` views are drawn from now on (0 or 1: the one picture): each reader gets its copies for
## the views past SHARED (made now, while the game steps, so they draw this frame). The copies are
## shown, hidden and placed by `follow`, which runs before every draw.
func use(count: int) -> void:
	views = clampi(count, 0, VIEWS_MOST)
	for i in range(_items.size() - 1, -1, -1):
		if not is_instance_valid(_items[i]):
			_drop_at(i)
			continue
		# An item drawn with a material no longer watched (a pool made anew): a reader no more.
		if not _materials.has(_items[i].material):
			_drop_at(i)
			continue
		for view in range(SHARED, views):
			if _copies[i][view - SHARED] == null:
				_copies[i][view - SHARED] = _copy_of(_items[i], view)
				_seen_views[i] = -1


## The copies set as their items are (shown only for the views drawn), and placed just after them;
## each copy's material given its item material's uniforms; the shared views' keys handed to the
## items' materials, from `shown` (the views drawn, in order; view k's canvas transform and size).
## Run once every frame before drawing (the light's `follow`, after the game has set this frame's
## numbers).
func follow(shown: Array[Viewport]) -> void:
	var shared_on: bool = views >= SHARED
	if shared_on != _shared_on:
		_shared_on = shared_on
		_keys_changed = true
	for k in SHARED:
		var view: Viewport = shown[k] if _shared_on and k < shown.size() else null
		var key: Vector4 = Vector4.ZERO
		var size: Vector2 = Vector2.ZERO
		if view != null and is_instance_valid(view):
			key = key_of(view.global_canvas_transform * view.canvas_transform)
			size = view.get_visible_rect().size
		if key != _keys[k] or size != _sizes[k]:
			_keys[k] = key
			_sizes[k] = size
			_keys_changed = true
	if _keys_changed:
		_keys_changed = false
		for material: ShaderMaterial in _materials:
			_hand_keys(material)
	_follow_copies()
	if views <= SHARED:
		return
	for material: ShaderMaterial in _materials:
		_follow_uniforms(material)


## The uniforms of `material` that changed since they were last copied (all of them when the views
## drawn changed or a view's material was made since) copied to its views' materials.
func _follow_uniforms(material: ShaderMaterial) -> void:
	var by_view: Array = _materials[material]
	var copied: bool = false
	for view in range(SHARED, views):
		copied = copied or by_view[view - SHARED] != null
	if not copied:
		# No item drawn with it has a copy: nothing to copy to (a view's material made later is
		# a duplicate of it then, and marks it to copy in full).
		return
	var names: Array[StringName] = _uniforms[material]
	var seen: Array = _seen_values[material]
	var all: bool = int(_values_views[material]) != views
	_values_views[material] = views
	for j in names.size():
		var value: Variant = material.get_shader_parameter(names[j])
		if not all and typeof(seen[j]) == typeof(value) and seen[j] == value:
			continue
		seen[j] = value
		for view in range(SHARED, views):
			var own := by_view[view - SHARED] as ShaderMaterial
			if own != null and own.get_shader_parameter(names[j]) != value:
				own.set_shader_parameter(names[j], value)


## The shared views' keys (`view_of`'s, as handed to the materials; for tests).
func keys() -> PackedVector4Array:
	return _keys


func sizes() -> PackedVector2Array:
	return _sizes


## `material` told the shared views' keys (set only where they changed).
func _hand_keys(material: ShaderMaterial) -> void:
	if material.get_shader_parameter(SHARED_ON) != _shared_on:
		material.set_shader_parameter(SHARED_ON, _shared_on)
	for k in SHARED:
		if material.get_shader_parameter(SHARED_KEYS[k]) != _keys[k]:
			material.set_shader_parameter(SHARED_KEYS[k], _keys[k])
		if material.get_shader_parameter(SHARED_SIZES[k]) != _sizes[k]:
			material.set_shader_parameter(SHARED_SIZES[k], _sizes[k])


## The copies set as their items are (shown only for the views drawn), and placed just after them:
## only those of items that show something else than when their copies last followed them.
func _follow_copies() -> void:
	for i in _items.size():
		var item: CanvasItem = _items[i]
		if not is_instance_valid(item):
			continue
		# With no third view every copy is hidden once the views drawn last changed, whatever its item
		# shows (a third view back follows them all, `_seen_changed`).
		if views <= SHARED and _seen_views[i] == views:
			continue
		if not _seen_changed(i, item):
			continue
		var copies: Array = _copies[i]
		for view in range(SHARED, VIEWS_MOST):
			var copy: CanvasItem = copies[view - SHARED]
			if copy == null or not is_instance_valid(copy):
				continue
			var shown: bool = view < views and item.visible
			if copy.visible != shown:
				copy.visible = shown
			if shown:
				_follow(copy, item, view)


## Whether item `i` (`item`) shows anything else than when its copies last followed it, or the views
## drawn changed, or a copy was made since; what it shows now is kept.
func _seen_changed(i: int, item: CanvasItem) -> bool:
	var changed: bool = _seen_views[i] != views
	_seen_views[i] = views
	# Its place among its siblings too: the copies are drawn just after it (`_follow`).
	var bits: int = (1 if item.visible else 0) | (2 if item.top_level else 0) | (item.get_index() << 2)
	if _seen_bits[i] != bits:
		_seen_bits[i] = bits
		changed = true
	if _seen_z[i] != item.z_index:
		_seen_z[i] = item.z_index
		changed = true
	if _seen_colors[i * 2] != item.modulate:
		_seen_colors[i * 2] = item.modulate
		changed = true
	if _seen_colors[i * 2 + 1] != item.self_modulate:
		_seen_colors[i * 2 + 1] = item.self_modulate
		changed = true
	var a: Vector2 = Vector2.ZERO
	var b: Vector2 = Vector2.ZERO
	var c: Vector2 = Vector2.ZERO
	var mesh: Object = null
	var texture: Object = null
	var node := item as Node2D
	if node != null:
		var to: Transform2D = node.transform
		a = to.x
		b = to.y
		c = to.origin
		var batch := item as MultiMeshInstance2D
		if batch != null:
			mesh = batch.multimesh
			texture = batch.texture
		var sprite := item as Sprite2D
		if sprite != null:
			texture = sprite.texture
	var control := item as Control
	if control != null:
		a = control.position
		b = control.size
	if _seen_vectors[i * 3] != a or _seen_vectors[i * 3 + 1] != b or _seen_vectors[i * 3 + 2] != c:
		_seen_vectors[i * 3] = a
		_seen_vectors[i * 3 + 1] = b
		_seen_vectors[i * 3 + 2] = c
		changed = true
	var material: Object = item.material
	if _seen_refs[i * 3] != material or _seen_refs[i * 3 + 1] != mesh or _seen_refs[i * 3 + 2] != texture:
		_seen_refs[i * 3] = material
		_seen_refs[i * 3 + 1] = mesh
		_seen_refs[i * 3 + 2] = texture
		changed = true
	return changed


## The readers (for tests).
func items() -> Array[CanvasItem]:
	return _items


## The copy of `item` for view `view` (null for none, and for a shared view; for tests).
func copy_of(item: CanvasItem, view: int) -> CanvasItem:
	var at: int = _items.find(item)
	if at < 0 or view < SHARED or view >= VIEWS_MOST:
		return null
	return _copies[at][view - SHARED]


## Every reader let go (drawn as any of the world's again), its copies freed (the light freed).
func clear() -> void:
	for i in range(_items.size() - 1, -1, -1):
		_drop_at(i)
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(SHARED_ON, false)
	_materials.clear()
	_uniforms.clear()
	_seen_values.clear()
	_values_views.clear()


## View `view`'s material for items drawn with `material` (made the first time: a copy naming it).
func _material_of(material: ShaderMaterial, view: int) -> ShaderMaterial:
	var by_view: Array = _materials[material]
	if by_view[view - SHARED] == null:
		var own := material.duplicate() as ShaderMaterial
		own.set_shader_parameter(VIEW_ID, view)
		own.set_shader_parameter(SHARED_ON, false)
		by_view[view - SHARED] = own
		_values_views[material] = -1
	return by_view[view - SHARED]


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
	_seen_bits.remove_at(at)
	_seen_z.remove_at(at)
	_seen_views.remove_at(at)
	for k in 2:
		_seen_colors.remove_at(at * 2)
	for k in 3:
		_seen_vectors.remove_at(at * 3)
		_seen_refs.remove_at(at * 3)


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
	followed += 1
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
		var sprite := item as Sprite2D
		if sprite != null:
			var onto := copy as Sprite2D
			if onto.texture != sprite.texture:
				onto.texture = sprite.texture
	var control := item as Control
	if control != null:
		var to := copy as Control
		if to.position != control.position:
			to.position = control.position
		if to.size != control.size:
			to.size = control.size
	var parent: Node = item.get_parent()
	if copy.get_parent() == parent:
		var want: int = mini(item.get_index() + view - SHARED + 1, parent.get_child_count() - 1)
		if copy.get_index() != want:
			parent.move_child(copy, want)
