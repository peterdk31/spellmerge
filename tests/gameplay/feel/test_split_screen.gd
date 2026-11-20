extends "res://tests/support/suite.gd"
## The split screen drawn (connected biomes CB6, gameplay/feel/split_screen.gd; decisions 27, 28):
## while split, a view a group draws the world through its own transform and is shown in its cell;
## the root draws only what is on its canvas layers (the HUD's corner panels stay where they are,
## drawn once over the views); the views are published for what reads the picture by the screen;
## the spell light has a buffer a view and tells each reader every view's transform. Merged again,
## all of it is put back.
const SplitScreenScript := preload("res://gameplay/feel/split_screen.gd")
const SplitCameraScript := preload("res://gameplay/feel/split_camera.gd")
const PartyCameraScript := preload("res://gameplay/feel/party_camera.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const ActorsScript := preload("res://core/actors/actors.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const VoidBackdropScript := preload("res://gameplay/feel/void_backdrop.gd")
const ItemHintsScript := preload("res://hud/panels/item_hints.gd")

const FRAME: float = 1.0 / 60.0

var _table: ActorsScript
var _holder: SubViewport
var _camera: Camera2D
var _party: PartyCameraScript
var _split: SplitScreenScript
var _mask: int = 0


func before_each() -> void:
	_mask = root.canvas_cull_mask
	_table = own(ActorsScript.new()) as ActorsScript
	root.add_child(_table)
	_holder = own(SubViewport.new()) as SubViewport
	_holder.size = Vector2i(root.get_visible_rect().size)
	_holder.disable_3d = true
	root.add_child(_holder)
	_camera = Camera2D.new()
	_camera.limit_left = -4000
	_camera.limit_top = -4000
	_camera.limit_right = 8000
	_camera.limit_bottom = 4000
	_holder.add_child(_camera)
	_camera.make_current()
	_party = PartyCameraScript.new()
	_party.follow(_camera)
	_split = own(SplitScreenScript.new()) as SplitScreenScript
	root.add_child(_split)


func after_each() -> void:
	if is_instance_valid(_split) and _split.is_inside_tree():
		root.remove_child(_split)
	root.canvas_cull_mask = _mask


func _wizard(seat: int, at: Vector2) -> Node2D:
	var node := own(Node2D.new()) as Node2D
	root.add_child(node)
	node.global_position = at
	var id: int = _table.open(ActorsScript.TEAM_WIZARDS, seat, seat)
	_table.set_node(id, node)
	_table.set_home(id, seat)
	return node


func _frames(count: int) -> void:
	for i in count:
		_party.look(_table, 0)
		_party.step(FRAME)
		_split.step(FRAME, _table, 0, _camera)


func test_a_split_draws_the_world_in_views_and_the_hud_on_the_root() -> void:
	# A panel in the screen's corner before the split, and one made during it.
	var hud := own(CanvasLayer.new()) as CanvasLayer
	hud.layer = 10
	root.add_child(hud)
	var corner := Control.new()
	corner.position = Vector2(4.0, 4.0)
	hud.add_child(corner)
	_wizard(0, Vector2(0.0, 0.0))
	var far: Node2D = _wizard(1, Vector2(3000.0, 0.0))
	_frames(60)
	check(_split.is_drawing(), "split: the views draw the world")
	check_equal(_split.views().size(), 2, "two views")
	check(root.canvas_cull_mask & SplitScreenScript.WORLD_LAYER == 0, "the root draws no world")
	check(root.canvas_cull_mask & SplitScreenScript.SCREEN_LAYER != 0, "but the screen's layer")
	check(corner.visibility_layer & SplitScreenScript.SCREEN_LAYER != 0, "a panel made before is drawn by the root")
	var later := Control.new()
	hud.add_child(later)
	check(later.visibility_layer & SplitScreenScript.SCREEN_LAYER != 0, "and one made during the split")
	check_equal(corner.position, Vector2(4.0, 4.0), "the corner panel stays in its corner")
	var laid: ScreenViewsScript = _split.camera.views
	check(ScreenViewsScript.on(root) == laid, "the views are published on the root")
	for view in laid.count:
		var shown: SubViewport = _split.views()[view] as SubViewport
		check(shown.world_2d == root.world_2d, "view %d draws the root's world" % view)
		var cell := _split.get_node(NodePath("Views/Cell%d" % _split.camera.slot_of(view))) as TextureRect
		check_equal(shown.canvas_transform, laid.to_screen[view].translated(-cell.position), "view %d draws through its own transform, from its box's corner" % view)
		check_equal(Vector2(shown.size), cell.size, "view %d is its box's size" % view)
		check_equal(shown.canvas_cull_mask, SplitScreenScript.WORLD_LAYER, "view %d draws the world's layer" % view)
	# Merged again: everything put back.
	far.global_position = Vector2(60.0, 0.0)
	_frames(400)
	check(not _split.is_drawing(), "together again: the root draws the world")
	check_equal(root.canvas_cull_mask, _mask, "its cull mask as it was")
	check(ScreenViewsScript.on(root) == null, "nothing published")
	check(_split.views().is_empty(), "no view")


func test_the_light_has_a_buffer_a_view_and_tells_its_readers_each_view() -> void:
	var light := own(SpellLightScript.new(null, 0)) as SpellLightScript
	root.add_child(light)
	var reader := ShaderMaterial.new()
	reader.shader = preload("res://gameplay/feel/mote.gdshader")
	light.read_by(&"motes", reader)
	_wizard(0, Vector2(0.0, 0.0))
	_wizard(1, Vector2(3000.0, 0.0))
	_frames(60)
	light.use_views(_split.views())
	check_equal(light.view_count(), 2, "a buffer a view")
	check(light.view_buffer(1).world_2d == light.viewport.world_2d, "the second buffer draws the same lights")
	check(light.view_buffer(1).get_parent() == light, "it is the light's")
	var apply := light.apply.material as ShaderMaterial
	check_equal(int(apply.get_shader_parameter(&"light_view_count")), 2, "the apply rect reads two views")
	check_equal(int(reader.get_shader_parameter(&"light_view_count")), 2, "and so does a reader")
	check(reader.get_shader_parameter(&"light_buffer_1") == light.view_buffer(1).get_texture(), "the reader has the second view's buffer")
	var drawn: Transform2D = (_split.views()[1] as SubViewport).canvas_transform
	var named: Vector4 = apply.get_shader_parameter(&"light_view_1")
	check(named.is_equal_approx(Vector4(drawn.x.x, drawn.origin.x, drawn.origin.y, 0.0)), "the second view's transform is named (%s)" % named)
	var expected: Transform2D = Transform2D(0.0, Vector2.ONE / SpellLightScript.DOWNSCALE, 0.0, Vector2.ZERO) * drawn
	check(light.view_buffer(1).canvas_transform.is_equal_approx(expected), "the second buffer follows the second view, scaled down")
	light.use_views([] as Array[Viewport])
	check_equal(light.view_count(), 0, "one picture again")
	check_equal(int(apply.get_shader_parameter(&"light_view_count")), 0, "the apply rect reads the one buffer")
	light.release()


func test_each_players_item_hint_follows_its_own_view() -> void:
	var hints := own(ItemHintsScript.new()) as ItemHintsScript
	root.add_child(hints)
	var views := ScreenViewsScript.new()
	views.screen = Vector2(640.0, 360.0)
	views.count = 2
	views.set_view(0, 0b01, Transform2D(0.0, Vector2.ONE, 0.0, Vector2(160.0, 180.0)), Vector2(160.0, 180.0))
	views.set_view(1, 0b10, Transform2D(0.0, Vector2.ONE, 0.0, Vector2(480.0, 180.0) - Vector2(1000.0, 0.0)), Vector2(480.0, 180.0))
	preload("res://gameplay/feel/voronoi_cells.gd").new().fill(views)
	hints._on_item_near_changed(1, 7, Vector2(1010.0, 20.0), {"name": "Wild star"})
	hints._on_item_near_changed(0, 8, Vector2(1010.0, 20.0), {"name": "Wild star"})
	var menus: Array[bool] = [false, false, false, false]
	hints.step(0.0, menus, Transform2D.IDENTITY, views)
	check(hints.hint_of(1).visible, "player 1's item is in their own view: its hint shows")
	check(not hints.hint_of(0).visible, "player 0's view does not show that item: no hint")


## The divider is exactly as many whole pixels across as its width, wherever the line falls
## (split_cell.gdshader, mirrored by `SplitScreen.cell_pixel`).
func test_the_divider_is_its_width_in_whole_pixels_wherever_the_line_is() -> void:
	for middle: float in [320.0, 320.5, 320.25]:
		for width in range(0, 4):
			# Two views, anchors either side of a vertical line at x = `middle`, and a slanted pair.
			for slant: float in [0.0, 0.4]:
				var a := Vector2(middle - 100.0, 180.0 - 100.0 * slant)
				var b := Vector2(middle + 100.0, 180.0 + 100.0 * slant)
				var row: int = 0
				for x in range(200, 440):
					var p := Vector2(float(x) + 0.5, 180.5)
					var from_a: int = SplitScreenScript.cell_pixel(p, a, PackedVector2Array([b]), PackedFloat32Array([float(width)]), 0)
					var from_b: int = SplitScreenScript.cell_pixel(p, b, PackedVector2Array([a]), PackedFloat32Array([float(width)]), 1)
					check((from_a >= 0) != (from_b >= 0), "the pixel at %s is one view's" % p)
					if from_a == 1 or from_b == 1:
						row += 1
				check_equal(row, width, "a line at %.2f (slant %.1f) is %d pixels across" % [middle, slant, width])


## A view draws only its cell's box (the performance pass): no pixel its cell's shader keeps lies
## outside the box (the cells are convex, so none on the ring of pixels just outside it), in the
## Voronoi split and the equal one, with two, three and four views, the box is snapped to
## BOX_SNAP, the cell's rect covers it, and a quarter pane's box is about a quarter of the screen.
func test_a_view_draws_only_its_cells_box() -> void:
	var screen: Vector2 = root.get_visible_rect().size
	var places: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(3000.0, 0.0), Vector2(0.0, 2500.0), Vector2(3000.0, 2600.0)]
	for equal: bool in [false, true]:
		for count in range(2, 5):
			before_each_again()
			_split.camera.set_equal(equal)
			for seat in count:
				_wizard(seat, places[seat] + Vector2(37.0 * float(seat), 11.0 * float(seat)))
			_frames(200)
			var laid: ScreenViewsScript = _split.camera.views
			check_equal(laid.count, count, "%d views (equal %s)" % [count, equal])
			var twin: int = _split.camera.blank_owner_view() if _split.camera.blank_count() > 0 else -1
			for view in laid.count:
				var slot: int = _split.camera.slot_of(view)
				var shown: SubViewport = _split.view_in_slot(slot)
				var cell := _split.get_node(NodePath("Views/Cell%d" % slot)) as TextureRect
				var box := Rect2i(Vector2i(cell.position), shown.size)
				var what: String = "view %d of %d (equal %s)" % [view, count, equal]
				check_equal(Vector2i(cell.size), shown.size, "%s: its rect is its box" % what)
				check(box.position.x % SplitScreenScript.BOX_SNAP == 0 and box.position.y % SplitScreenScript.BOX_SNAP == 0, "%s: its box is snapped (%s)" % [what, box])
				if equal and count == 4:
					check(box.size.x * box.size.y * 2 < int(screen.x * screen.y), "%s: a quarter pane draws under half the screen's pixels (%s)" % [what, box])
				if view == twin:
					check_equal(box, Rect2i(Vector2i.ZERO, Vector2i(screen)), "%s: the twin's view draws the whole screen" % what)
					continue
				var material := cell.material as ShaderMaterial
				var others := PackedVector2Array()
				var widths := PackedFloat32Array()
				for k in int(material.get_shader_parameter(&"others")):
					others.append(material.get_shader_parameter(StringName("other_%d" % k)))
					widths.append(float(material.get_shader_parameter(StringName("divider_%d" % k))))
				var own_at: Vector2 = material.get_shader_parameter(&"own")
				var before: int = int(material.get_shader_parameter(&"before_mask"))
				var kept_outside: int = 0
				# The ring just outside the box less the light's pad: no kept pixel there or past it.
				# (Sides on the screen's edge have no pad: the screen ends there.)
				var pad: int = SplitScreenScript.BOX_PAD
				var left: int = box.position.x + (pad if box.position.x > 0 else 0)
				var top: int = box.position.y + (pad if box.position.y > 0 else 0)
				var right: int = box.end.x - (pad if box.end.x < int(screen.x) else 0)
				var bottom: int = box.end.y - (pad if box.end.y < int(screen.y) else 0)
				box = Rect2i(left, top, right - left, bottom - top)
				var ring := box.grow(1).intersection(Rect2i(Vector2i.ZERO, Vector2i(screen)))
				for x in range(ring.position.x, ring.end.x):
					for y: int in [ring.position.y, ring.end.y - 1]:
						if not box.has_point(Vector2i(x, y)) and SplitScreenScript.cell_pixel(Vector2(x, y) + Vector2(0.5, 0.5), own_at, others, widths, before) >= 0:
							kept_outside += 1
				for y in range(ring.position.y, ring.end.y):
					for x: int in [ring.position.x, ring.end.x - 1]:
						if not box.has_point(Vector2i(x, y)) and SplitScreenScript.cell_pixel(Vector2(x, y) + Vector2(0.5, 0.5), own_at, others, widths, before) >= 0:
							kept_outside += 1
				check_equal(kept_outside, 0, "%s: no pixel of its cell outside its box %s" % [what, box])


## A view's box keeps its size while its cell's needs move a little inside it, and is made again
## (with half BOX_SLACK of room each way) once they leave it or it has more than BOX_SLACK to spare.
func test_a_views_box_keeps_its_size_while_its_cell_moves_a_little() -> void:
	var screen := Vector2(640.0, 360.0)
	var needed := Rect2i(304, 0, 336, 360)
	var made: Rect2i = SplitScreenScript.kept_box(Rect2i(), needed, screen)
	check(made.encloses(needed), "a new box holds what its cell needs")
	check_equal(made, Rect2i(288, 0, 352, 360), "with half the slack of room, within the screen")
	check_equal(SplitScreenScript.kept_box(made, Rect2i(296, 0, 344, 360), screen), made, "a divider moved 8 px: the same box")
	check_equal(SplitScreenScript.kept_box(made, Rect2i(312, 0, 328, 360), screen), made, "and back the other way")
	check(SplitScreenScript.kept_box(made, Rect2i(280, 0, 360, 360), screen) != made, "past its edge: made again")
	check(SplitScreenScript.kept_box(made, Rect2i(400, 0, 240, 360), screen) != made, "with far more room than it needs: made again, smaller")
	check_equal(SplitScreenScript.kept_box(made, Rect2i(0, 0, 640, 360), screen), Rect2i(0, 0, 640, 360), "the whole screen is the whole screen")


## A fresh split screen and actor table, for a test that lays out several splits.
func before_each_again() -> void:
	if is_instance_valid(_split) and _split.is_inside_tree():
		root.remove_child(_split)
	root.canvas_cull_mask = _mask
	before_each()


## The equal split with three seats: each cell's shader is told of the blank quarter as one more
## other (its divider the view's), and the blank's black is shown under the cells only while there
## is one; the screen's whole picture: the blank quarter is no cell's pixel (the shader's rule).
func test_the_equal_splits_blank_quarter_is_black_and_no_views() -> void:
	_split.camera.set_equal(true)
	_wizard(0, Vector2(0.0, 0.0))
	_wizard(1, Vector2(3000.0, 0.0))
	var walker: Node2D = _wizard(3, Vector2(0.0, 2500.0))
	_frames(200)
	var laid: ScreenViewsScript = _split.camera.views
	check_equal(laid.count, 3, "three panes")
	check_equal(_split.camera.blank_count(), 1, "and a blank")
	var blank := _split.get_node_or_null(^"Views/Blank") as ColorRect
	check(blank != null and blank.visible, "the blank's black is shown")
	if blank != null:
		check_equal(blank.color, Color.BLACK, "the void's black")
	var screen: Vector2 = root.get_visible_rect().size
	var quarter_middle := Vector2(screen.x * 0.25, screen.y * 0.75)
	for view in laid.count:
		var others := PackedVector2Array()
		var widths := PackedFloat32Array()
		var before: int = 0
		for other in laid.count:
			if other != view:
				if other < view:
					before |= 1 << others.size()
				others.append(laid.anchor[other])
				widths.append(float(_split.camera.divider_between(view, other)))
		others.append(_split.camera.blank_anchor(0))
		widths.append(float(_split.camera.blank_divider(view)))
		check_equal(SplitScreenScript.cell_pixel(quarter_middle, laid.anchor[view], others, widths, before), -1, "view %d does not draw the blank quarter" % view)
		var material := (_split.get_node(NodePath("Views/Cell%d" % _split.camera.slot_of(view))) as TextureRect).material as ShaderMaterial
		check_equal(int(material.get_shader_parameter(&"others")), 3, "view %d's cell knows two views and the blank" % view)
	# Together again: no blank, nothing black.
	walker.global_position = Vector2(40.0, 0.0)
	_wizard_move_all_together()
	_frames(600)
	check(not _split.is_drawing(), "together: one picture")
	check(blank == null or not blank.visible, "and the blank hidden")


## The equal split's blank quarter shows the void (the owner, 2026-11-20): in a biome (`void_bounds`)
## the void view draws under the cells, looking VOID_AWAY past the biome's corner at the world's
## size, and stops drawing once the blank is gone; outside a biome the blank is the black alone.
func test_the_blank_quarter_shows_the_void_view_in_a_biome() -> void:
	_split.camera.set_equal(true)
	_split.void_bounds = Rect2(-500.0, -500.0, 4000.0, 3500.0)
	_wizard(0, Vector2(0.0, 0.0))
	_wizard(1, Vector2(3000.0, 0.0))
	var walker: Node2D = _wizard(3, Vector2(0.0, 2500.0))
	_frames(200)
	check_equal(_split.camera.blank_count(), 1, "a blank")
	var view: SubViewport = _split.void_view()
	check(view != null, "the void view was made")
	if view == null:
		return
	check_equal(view.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "it draws")
	check_equal(view.world_2d, root.world_2d, "the same world")
	var shows: Rect2 = _split.void_rect()
	var screen: Vector2 = root.get_visible_rect().size
	var zoom: float = _split.camera.view_zoom()
	check(shows.size.distance_to((screen * 0.5).floor() / zoom) < 1.0, "the blank quarter's size at the views' zoom (%s)" % shows.size)
	check(not shows.intersects(_split.void_bounds), "past the biome (%s)" % shows)
	check(_split.void_bounds.grow(VoidBackdropScript.GROW).encloses(shows), "inside the void's black")
	var cell := _split.get_node(^"Views/VoidCell") as TextureRect
	check(cell.visible, "its rect is shown")
	check_equal(Rect2(cell.position, cell.size), Rect2(Vector2(0.0, (screen * 0.5).floor().y), (screen * 0.5).floor()), "over the blank quarter (P3's, bottom left)")
	var lowest_cell: int = 1 << 30
	for slot in ScreenViewsScript.VIEWS_MOST:
		var other := _split.get_node_or_null(NodePath("Views/Cell%d" % slot))
		if other != null:
			lowest_cell = mini(lowest_cell, other.get_index())
	check(cell.get_index() < lowest_cell, "under every view's cell")
	# The same view again as it splits again (no new one).
	walker.global_position = Vector2(40.0, 0.0)
	_wizard_move_all_together()
	_frames(600)
	check(not _split.is_drawing(), "together: one picture")
	check_equal(view.render_target_update_mode, SubViewport.UPDATE_DISABLED, "the void view stops drawing")
	check_equal(_split.void_rect(), Rect2(), "and shows nothing")
	_split.void_bounds = Rect2()


## Four players, a pair and two alone (the owner, 2026-11-20): the pair has a half, its bottom
## quarter its twin, which the twin rect shows with the pair's own view (no void view, no divider).
func test_a_pairs_twin_quarter_shows_the_pairs_own_picture() -> void:
	_split.camera.set_equal(true)
	_split.void_bounds = Rect2(-500.0, -500.0, 4000.0, 3500.0)
	_wizard(0, Vector2(0.0, 0.0))
	_wizard(1, Vector2(60.0, 0.0))
	_wizard(2, Vector2(3000.0, 0.0))
	_wizard(3, Vector2(3000.0, 2500.0))
	_frames(240)
	var laid: ScreenViewsScript = _split.camera.views
	check_equal(laid.count, 3, "three panes")
	var owner: int = _split.camera.blank_owner_view()
	check_equal(owner, laid.view_of_seat(0), "the blank is the pair's twin")
	var twin: TextureRect = _split.twin_cell()
	check(twin != null and twin.visible, "the twin rect is shown")
	if twin != null:
		check_equal(twin.texture, _split.view_in_slot(_split.camera.slot_of(owner)).get_texture(), "with the pair's view")
		check(twin.get_index() < _split.get_node(^"Views/Cell0").get_index(), "under the cells")
	check(_split.void_view() == null or _split.void_view().render_target_update_mode == SubViewport.UPDATE_DISABLED, "no void drawn")
	var material := (_split.get_node(NodePath("Views/Cell%d" % _split.camera.slot_of(owner))) as TextureRect).material as ShaderMaterial
	check_equal(int(material.get_shader_parameter(&"others")), 3, "the pair's cell knows the two others and its twin")
	check_equal(material.get_shader_parameter(&"divider_2"), 0.0, "no divider from the pair to its twin")
	_split.void_bounds = Rect2()


## What the cell rect `rect` draws at screen pixel `p` by its shader's own parameters (-1 not its,
## 0 its picture, 1 the divider), through `cell_pixel`.
static func _drawn_by(rect: TextureRect, p: Vector2) -> int:
	var material := rect.material as ShaderMaterial
	var others := PackedVector2Array()
	var widths := PackedFloat32Array()
	for k in int(material.get_shader_parameter(&"others")):
		others.append(material.get_shader_parameter(SplitScreenScript.OTHER_UNIFORMS[k]))
		widths.append(material.get_shader_parameter(SplitScreenScript.DIVIDER_UNIFORMS[k]))
	return SplitScreenScript.cell_pixel(p, material.get_shader_parameter(&"own"), others, widths, int(material.get_shader_parameter(&"before_mask")))


## Regression (review): the pair's half's outer edge stepped by 2 px at its middle row (the single
## beside the twin drew its whole line on its own side). Now the twin rect is cut as a pane of its
## own: the divider's columns are the same above and below, every pixel is drawn exactly once.
func test_a_pairs_half_has_a_straight_edge_beside_its_twin() -> void:
	_split.camera.set_equal(true)
	_wizard(0, Vector2(0.0, 0.0))
	_wizard(1, Vector2(60.0, 0.0))
	_wizard(2, Vector2(3000.0, 0.0))
	_wizard(3, Vector2(3000.0, 2500.0))
	_frames(240)
	var rects: Array[TextureRect] = [_split.twin_cell()]
	for view in _split.camera.views.count:
		rects.append(_split.get_node(NodePath("Views/Cell%d" % _split.camera.slot_of(view))) as TextureRect)
	var screen: Vector2 = root.get_visible_rect().size
	var columns: Array[PackedInt32Array] = []
	for y: float in [screen.y * 0.25 + 0.5, screen.y * 0.75 + 0.5]:
		var line := PackedInt32Array()
		for x in range(int(screen.x * 0.5) - 6, int(screen.x * 0.5) + 6):
			var drawn: int = 0
			var divider: bool = false
			for rect in rects:
				var got: int = _drawn_by(rect, Vector2(float(x) + 0.5, y))
				if got >= 0:
					drawn += 1
					divider = divider or got == 1
			check_equal(drawn, 1, "pixel (%d, %.1f) drawn by exactly one rect" % [x, y])
			if divider:
				line.append(x)
		columns.append(line)
	check_equal(columns[0].size(), SplitCameraScript.DIVIDER_WIDTH, "the line is its width beside the pair's top")
	check_equal(columns[1], columns[0], "and in the same columns beside its twin")


## Every seat's wizard moved beside the others.
func _wizard_move_all_together() -> void:
	for id in ActorsScript.SEATS:
		var home: int = _table.home_of_seat(id)
		if home >= 0 and _table.node_of(home) != null:
			(_table.node_of(home) as Node2D).global_position = Vector2(20.0 * float(id), 0.0)
