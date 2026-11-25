extends "res://tests/support/suite.gd"
## The 1280 x 720 picture (ART0; core/display/picture_grid.gd): the project draws a picture twice the
## layout's size each way, integer-scaled to the window; a screen's layer is laid out in layout pixels
## (640 x 360) and drawn at the picture's scale, its full-screen Control sized to the layout; the views
## a layer reads are measured in its own pixels (`ScreenViews.scaled_into`).


func test_the_project_draws_1280_by_720_at_whole_numbers() -> void:
	check_equal(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 1280, "1280 wide")
	check_equal(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 720, "720 tall")
	check_equal(Vector2i(int(ProjectSettings.get_setting("display/window/size/viewport_width")), int(ProjectSettings.get_setting("display/window/size/viewport_height"))), PictureGrid.SIZE * PictureGrid.PICTURE_SCALE, "the layout times PICTURE_SCALE")
	check_equal(ArtDetail.DETAIL, PictureGrid.PICTURE_SCALE, "redrawn art has a picture pixel an art pixel at zoom 1")
	check_equal(str(ProjectSettings.get_setting("display/window/stretch/mode")), "viewport", "drawn into a picture of its own")
	check_equal(str(ProjectSettings.get_setting("display/window/stretch/scale_mode")), "integer", "stretched by whole numbers (Display stretches by a fraction where they would leave the screen mostly empty)")
	check(bool(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel")), "every place on the picture's whole pixels")
	check_equal(PictureGrid.scale_of(Vector2(1280.0, 720.0)), 2, "twice the layout")
	check_equal(PictureGrid.scale_of(Vector2(640.0, 360.0)), 1, "a 640 x 360 picture (a benchmark's) once")
	check_equal(PictureGrid.layout_of(null), Vector2(PictureGrid.SIZE), "the layout's size")


func test_a_layer_is_laid_out_in_layout_pixels_at_the_picture_s_scale() -> void:
	var layer: CanvasLayer = own(CanvasLayer.new()) as CanvasLayer
	var full: Control = Control.new()
	full.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(full)
	root.add_child(layer)
	PictureGrid.keep_fitted(layer, full)
	var by: int = PictureGrid.scale_in(root)
	check_equal(layer.transform, Transform2D.IDENTITY.scaled(Vector2(by, by)), "drawn at the picture's scale")
	check_equal(full.size, root.get_visible_rect().size / float(by), "its full-screen Control the layout's size")
	check_equal(full.position, Vector2.ZERO, "from the top left")
	var connections: int = root.size_changed.get_connections().size()
	PictureGrid.keep_fitted(layer, full)
	check_equal(root.size_changed.get_connections().size(), connections, "kept fitted once")
	layer.get_parent().remove_child(layer)
	check_equal(root.size_changed.get_connections().size(), connections - 1, "let go as it leaves the tree")
	root.add_child(layer)
	check_equal(root.size_changed.get_connections().size(), connections, "and fitted again as it comes back")
	layer.get_parent().remove_child(layer)


func test_the_views_are_read_in_a_layer_s_pixels() -> void:
	var views := ScreenViews.new()
	views.set_single(Vector2(1280.0, 720.0), Transform2D(0.0, Vector2(1.6, 1.6), 0.0, Vector2(-100.0, -50.0)), 1)
	var layout: ScreenViews = views.scaled_into(ScreenViews.new(), 0.5)
	check_equal(layout.count, 1, "one view")
	check_equal(layout.screen, Vector2(640.0, 360.0), "the screen in layout pixels")
	check_equal(layout.anchor[0], views.anchor[0] * 0.5, "its anchor")
	check(layout.to_screen[0].is_equal_approx(Transform2D(0.0, Vector2(0.8, 0.8), 0.0, Vector2(-50.0, -25.0))), "the world drawn into layout pixels")
	for at in views.corners(0):
		check_equal(layout.corner(0, at), views.corner(0, at) * 0.5, "corner %d" % at)
	check_equal(layout.view_showing(Vector2(200.0, 100.0)), views.view_showing(Vector2(200.0, 100.0)), "the same world shown")
