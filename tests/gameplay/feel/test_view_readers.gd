extends "res://tests/support/suite.gd"
## The light's readers in each view (gameplay/feel/view_readers.gd): their copies for the third and
## fourth views follow their items, and the views' materials their items' materials, only where
## something changed (the perf plan's F2, 2026-11-28), and never miss a change: what an item shows,
## a uniform set, a view coming back with a uniform set while it was away, a reader gone between
## others.
const ViewReadersScript := preload("res://gameplay/feel/view_readers.gd")

var _readers: ViewReadersScript
var _material: ShaderMaterial
var _holder: Node2D
var _views: Array[Viewport] = []


func before_each() -> void:
	_readers = ViewReadersScript.new()
	_material = ShaderMaterial.new()
	_material.shader = preload("res://gameplay/feel/mote.gdshader")
	_holder = own(Node2D.new()) as Node2D
	root.add_child(_holder)
	_views.clear()
	for k in 4:
		var view := own(SubViewport.new()) as SubViewport
		view.size = Vector2i(320 + k, 180)
		view.disable_3d = true
		root.add_child(view)
		view.canvas_transform = Transform2D(0.0, Vector2(10.0 * float(k), 0.0))
		_views.append(view)
	_readers.watch(_material, null)


func after_each() -> void:
	_readers.clear()


func _item(z: int = 0) -> MultiMeshInstance2D:
	var item := MultiMeshInstance2D.new()
	item.material = _material
	item.z_index = z
	_holder.add_child(item)
	_readers.take(item)
	return item


func _follow(count: int) -> void:
	_readers.use(count)
	_readers.follow(_views.slice(0, count))


func test_nothing_changed_nothing_is_followed() -> void:
	_item(1)
	_item(2)
	_follow(4)
	check_equal(_readers.made, 4, "two copies a reader")
	var followed: int = _readers.followed
	_follow(4)
	_follow(4)
	check_equal(_readers.followed, followed, "a frame with nothing changed touches no copy")


func test_what_an_item_shows_reaches_its_copies() -> void:
	var item: MultiMeshInstance2D = _item(1)
	var other: MultiMeshInstance2D = _item(5)
	_follow(4)
	var followed: int = _readers.followed
	item.z_index = 7
	item.position = Vector2(3.0, 4.0)
	item.modulate = Color(0.5, 0.25, 1.0, 1.0)
	item.self_modulate = Color(1.0, 0.0, 0.0, 0.5)
	item.multimesh = MultiMesh.new()
	item.texture = PlaceholderTexture2D.new()
	_follow(4)
	check_equal(_readers.followed - followed, 2, "only the changed item's two copies followed")
	for view in [2, 3]:
		var copy := _readers.copy_of(item, view) as MultiMeshInstance2D
		check_equal(copy.z_index, 7, "view %d's copy at the item's z" % view)
		check_equal(copy.position, Vector2(3.0, 4.0), "and its place")
		check_equal(copy.modulate, item.modulate, "and its modulate")
		check_equal(copy.self_modulate, item.self_modulate, "and its self modulate")
		check(copy.multimesh == item.multimesh and copy.texture == item.texture, "and its MultiMesh and texture")
		check_equal((_readers.copy_of(other, view) as CanvasItem).z_index, 5, "the other's copy untouched")
	item.visible = false
	_follow(4)
	check(not (_readers.copy_of(item, 2) as CanvasItem).visible and not (_readers.copy_of(item, 3) as CanvasItem).visible, "a hidden item's copies are hidden")
	item.visible = true
	_follow(4)
	check((_readers.copy_of(item, 3) as CanvasItem).visible, "and shown again")


func test_fewer_views_hide_copies_and_more_show_them() -> void:
	var item: MultiMeshInstance2D = _item()
	_follow(4)
	_follow(3)
	check((_readers.copy_of(item, 2) as CanvasItem).visible, "three views: the third's copy shown")
	check(not (_readers.copy_of(item, 3) as CanvasItem).visible, "the fourth's hidden")
	_follow(2)
	check(not (_readers.copy_of(item, 2) as CanvasItem).visible, "two views: no copy shown")
	_follow(4)
	check((_readers.copy_of(item, 2) as CanvasItem).visible and (_readers.copy_of(item, 3) as CanvasItem).visible, "four again: both shown")


func test_a_uniform_set_reaches_every_view_material() -> void:
	var item: MultiMeshInstance2D = _item()
	_follow(4)
	_material.set_shader_parameter(&"sim_time", 12.5)
	_follow(4)
	for view in [2, 3]:
		var own := (_readers.copy_of(item, view) as CanvasItem).material as ShaderMaterial
		check_equal(own.get_shader_parameter(&"sim_time"), 12.5, "view %d's material has the uniform set" % view)
		check_equal(int(own.get_shader_parameter(ViewReadersScript.VIEW_ID)), view, "and still names its view")


func test_a_view_back_takes_what_was_set_while_it_was_away() -> void:
	# The fourth view's material is not copied to while three views are drawn: back at four, it takes
	# what was set meanwhile, though the material itself has not changed since the frame before.
	var item: MultiMeshInstance2D = _item()
	_follow(4)
	_follow(3)
	_material.set_shader_parameter(&"sim_time", 3.0)
	_follow(3)
	_follow(4)
	var fourth := (_readers.copy_of(item, 3) as CanvasItem).material as ShaderMaterial
	check_equal(fourth.get_shader_parameter(&"sim_time"), 3.0, "the fourth view's material caught up")
	# The same at two views (nothing copied at all) and back.
	_follow(2)
	_material.set_shader_parameter(&"sim_time", 4.0)
	_follow(2)
	_follow(4)
	for view in [2, 3]:
		var own := (_readers.copy_of(item, view) as CanvasItem).material as ShaderMaterial
		check_equal(own.get_shader_parameter(&"sim_time"), 4.0, "view %d's material caught up from two views" % view)


func test_a_reader_gone_between_others_keeps_the_rest_followed() -> void:
	var first: MultiMeshInstance2D = _item(1)
	var second: MultiMeshInstance2D = _item(2)
	var third: MultiMeshInstance2D = _item(3)
	var fourth: MultiMeshInstance2D = _item(4)
	_follow(4)
	# The second of four goes: what the others showed is kept in their own places.
	_readers.release(second)
	second.queue_free()
	first.z_index = 10
	third.position = Vector2(9.0, 0.0)
	fourth.modulate = Color(0.0, 1.0, 0.0, 1.0)
	_follow(4)
	check_equal(_readers.items().size(), 3, "three readers left")
	check_equal((_readers.copy_of(first, 3) as CanvasItem).z_index, 10, "the first's copies follow it")
	check_equal((_readers.copy_of(third, 2) as Node2D).position, Vector2(9.0, 0.0), "the third's too")
	check_equal((_readers.copy_of(fourth, 3) as CanvasItem).modulate, Color(0.0, 1.0, 0.0, 1.0), "and the fourth's")
	# Set back to what an item showed before: followed again, not mistaken for another's.
	third.position = Vector2.ZERO
	_follow(4)
	check_equal((_readers.copy_of(third, 3) as Node2D).position, Vector2.ZERO, "the third's back in place")
	var followed: int = _readers.followed
	_follow(4)
	check_equal(_readers.followed, followed, "and then rest")


func test_the_shared_views_keys_follow_the_views() -> void:
	_item()
	_follow(2)
	check(bool(_material.get_shader_parameter(ViewReadersScript.SHARED_ON)), "two views told apart")
	check_equal(_material.get_shader_parameter(ViewReadersScript.SHARED_SIZES[1]), Vector2(321.0, 180.0), "the second view's size")
	(_views[1] as SubViewport).canvas_transform = Transform2D(0.0, Vector2(77.0, 5.0))
	_follow(2)
	var shown: Viewport = _views[1]
	check_equal(_material.get_shader_parameter(ViewReadersScript.SHARED_KEYS[1]), ViewReadersScript.key_of(shown.global_canvas_transform * shown.canvas_transform), "a view moved: its key handed")
	var later := ShaderMaterial.new()
	later.shader = _material.shader
	_readers.watch(later, null)
	check_equal(later.get_shader_parameter(ViewReadersScript.SHARED_KEYS[1]), _material.get_shader_parameter(ViewReadersScript.SHARED_KEYS[1]), "a material watched later is handed the keys at once")
	_follow(0)
	check(not bool(_material.get_shader_parameter(ViewReadersScript.SHARED_ON)), "one picture: no view told apart")



func test_a_reader_gone_leaves_no_others_place_seen_in_its_own() -> void:
	_gone_between(true)


func test_a_reader_gone_leaves_no_others_colour_seen_in_its_own() -> void:
	_gone_between(false)


## Readers alike but for their place and colour, the second gone: the first moved onto the second's
## place (`place`) or given its colour, alone, must still be followed. Had the second's kept values
## stayed in the first's slot, the first would be taken for unchanged.
func _gone_between(place: bool) -> void:
	var places: Array[Vector2] = [Vector2(1.0, 0.0), Vector2(2.0, 0.0), Vector2(3.0, 0.0)]
	var colors: Array[Color] = [Color(1.0, 0.0, 0.0, 1.0), Color(0.0, 1.0, 0.0, 1.0), Color(0.0, 0.0, 1.0, 1.0)]
	var made: Array[MultiMeshInstance2D] = []
	for k in 3:
		var item: MultiMeshInstance2D = _item()
		item.position = places[k]
		item.modulate = colors[k]
		item.self_modulate = colors[k]
		made.append(item)
	_follow(4)
	_readers.release(made[1])
	made[1].queue_free()
	if place:
		made[0].position = places[1]
	else:
		made[0].modulate = colors[1]
		made[0].self_modulate = colors[1]
	_follow(4)
	var copy := _readers.copy_of(made[0], 3) as Node2D
	check_equal(copy.position, places[1] if place else places[0], "the first's copy at the first's place")
	check_equal(copy.modulate, colors[0] if place else colors[1], "in its colour")
	check_equal(copy.self_modulate, colors[0] if place else colors[1], "and self colour")
	check_equal((_readers.copy_of(made[2], 2) as Node2D).position, places[2], "the third's copy where it was")


## What the full follow of every frame (before F2) would leave: every copy as its item, shown only for
## the views drawn, and every view's material holding its item material's uniforms.
func _check_followed(count: int, step: int) -> int:
	var wrong: int = 0
	for item: CanvasItem in _readers.items():
		var batch := item as MultiMeshInstance2D
		for view in range(ViewReadersScript.SHARED, ViewReadersScript.VIEWS_MOST):
			var copy := _readers.copy_of(item, view) as MultiMeshInstance2D
			if copy == null:
				continue
			var shown: bool = view < count and item.visible
			if copy.visible != shown:
				wrong += 1
			if not shown:
				continue
			if copy.z_index != batch.z_index or copy.transform != batch.transform or copy.modulate != batch.modulate or copy.self_modulate != batch.self_modulate or copy.multimesh != batch.multimesh or copy.texture != batch.texture:
				wrong += 1
			var own := copy.material as ShaderMaterial
			for named: StringName in [&"sim_time", &"lit_hue", &"light_on"]:
				if own.get_shader_parameter(named) != _material.get_shader_parameter(named):
					wrong += 1
	if wrong > 0:
		check(false, "step %d: %d copies or uniforms not as the full follow leaves them" % [step, wrong])
	return wrong


func test_random_changes_leave_what_the_full_follow_leaves() -> void:
	var dice := RandomNumberGenerator.new()
	dice.seed = 20261128
	var meshes: Array[MultiMesh] = [MultiMesh.new(), MultiMesh.new()]
	var items: Array[MultiMeshInstance2D] = []
	for k in 6:
		items.append(_item(k))
	var count: int = 4
	var wrong: int = 0
	for step in 400:
		var roll: int = dice.randi_range(0, 11)
		var item: MultiMeshInstance2D = items[dice.randi_range(0, items.size() - 1)] if not items.is_empty() else null
		match roll:
			0:
				count = dice.randi_range(0, 4)
			1:
				if item != null:
					item.z_index = dice.randi_range(-3, 3)
			2:
				if item != null:
					item.position = Vector2(float(dice.randi_range(-2, 2)), 0.0)
			3:
				if item != null:
					item.modulate = Color(float(dice.randi_range(0, 1)), 1.0, 1.0, 1.0)
			4:
				if item != null:
					item.self_modulate = Color(1.0, float(dice.randi_range(0, 1)), 1.0, 1.0)
			5:
				if item != null:
					item.visible = not item.visible
			6:
				if item != null:
					item.multimesh = meshes[dice.randi_range(0, 1)]
			7:
				_material.set_shader_parameter(&"sim_time", float(dice.randi_range(0, 3)))
			8:
				_material.set_shader_parameter(&"lit_hue", float(dice.randi_range(0, 2)) * 0.25)
			9:
				_material.set_shader_parameter(&"light_on", dice.randi_range(0, 1) == 1)
			10:
				if item != null and items.size() > 2:
					items.erase(item)
					_readers.release(item)
					item.free()
			11:
				if items.size() < 8:
					items.append(_item(dice.randi_range(0, 3)))
		_follow(count)
		wrong += _check_followed(count, step)
		if wrong > 0:
			break
	check_equal(wrong, 0, "400 frames of random changes: the copies and their materials as the full follow leaves them")


func test_a_reader_moved_among_its_siblings_takes_its_copies_along() -> void:
	var first: MultiMeshInstance2D = _item()
	var second: MultiMeshInstance2D = _item()
	_follow(4)
	_holder.move_child(second, 0)
	_follow(4)
	check_equal((_readers.copy_of(second, 2) as Node).get_index(), second.get_index() + 1, "the third view's copy just after its moved reader")
	check_equal((_readers.copy_of(second, 3) as Node).get_index(), second.get_index() + 2, "the fourth's after it")
	check_equal((_readers.copy_of(first, 2) as Node).get_index(), first.get_index() + 1, "the other reader's copies still just after it")


func test_a_control_reader_s_copies_follow_its_place_and_size() -> void:
	var rect := ColorRect.new()
	rect.material = _material
	_holder.add_child(rect)
	_readers.take(rect)
	_follow(4)
	rect.position = Vector2(5.0, 6.0)
	rect.size = Vector2(40.0, 30.0)
	_follow(4)
	for view in [2, 3]:
		var copy := _readers.copy_of(rect, view) as Control
		check_equal(copy.position, Vector2(5.0, 6.0), "view %d's copy at the rect's place" % view)
		check_equal(copy.size, Vector2(40.0, 30.0), "and its size")
	var followed: int = _readers.followed
	_follow(4)
	check_equal(_readers.followed, followed, "then rests")
