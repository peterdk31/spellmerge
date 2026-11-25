class_name PictureGrid
extends RefCounted
## The picture the game is laid out for, and how much bigger the picture it is drawn in is. One place
## says it (the owner's decisions of 2026-11-21, docs/milestones/connected-biomes.md, "The light at a
## fixed resolution", and of 2026-11-21/25, docs/STYLE.md, "The picture and the art's detail"):
##
## - **The picture** is 1280 x 720 (project.godot), drawn to the window by whole numbers. It shows
##   what a 640 x 360 picture showed (SIZE), twice as fine: `scale_of(picture)` is 2 there.
## - **The cameras' zoom 1** shows SIZE of the world: a picture `scale_of` times bigger draws the same
##   world at that zoom times more (the party camera, the split's views), so a bigger picture is a
##   finer one, not a wider one. (The cameras rest at `PartyCamera.MAX_ZOOM`, 0.8, since
##   2026-11-23: 800 x 450 of the world in SIZE.)
## - **The screen's layers** (the HUD, the menus, the intro, the markers and dividers drawn in screen
##   pixels) are laid out in SIZE's pixels, *layout pixels*, and drawn `scale_of` times bigger:
##   `fit_layer` scales a CanvasLayer and sizes its full-screen Control to SIZE, so a layout made for
##   640 x 360 looks the same size in any picture, and art drawn at 2x detail for it
##   (`ArtDetail`, core/display/art_detail.gd) shows its finer pixels. A point in the picture is
##   `to_layout(point, picture)` in layout pixels.
##
## A benchmark draws another picture (bench/biome_frames_runner.gd, `--picture=`); everything here
## follows the root's size, so 640 x 360 draws as the game did before 2026-11-25.

## The picture's size at which the cameras' zoom is 1, and the layout's size (px; a view's share of
## it).
const SIZE: Vector2i = Vector2i(640, 360)
## How many times SIZE the shipped picture is each way (k; the owner's choice of 2026-11-25: 2, a
## 1280 x 720 picture). project.godot's viewport is SIZE times it (`tests/core/test_picture_grid.gd`
## holds the two together); everything else reads the picture's own size (`scale_of`), so a
## benchmark's other picture works too.
const PICTURE_SCALE: int = 2
## The metadata a layer `keep_fitted` keeps its refit under.
const FITTED_META: StringName = &"picture_grid_fitted"


## How many picture pixels each way one pixel of SIZE is in a picture of `picture` px: the largest
## whole number that fits both ways, at least 1.
static func scale_of(picture: Vector2) -> int:
	var across: int = floori(picture.x / float(SIZE.x) + 0.0001)
	var down: int = floori(picture.y / float(SIZE.y) + 0.0001)
	return maxi(mini(across, down), 1)


## The scale of the picture `viewport` draws (its visible rect's; the project's picture when null).
static func scale_in(viewport: Viewport) -> int:
	return scale_of(picture_of(viewport))


## The size of the picture `viewport` draws (px): its visible rect, or the project's picture when
## null (out of the tree).
static func picture_of(viewport: Viewport) -> Vector2:
	if viewport != null:
		return viewport.get_visible_rect().size
	return Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"), ProjectSettings.get_setting("display/window/size/viewport_height"))


## The size of the picture `viewport` draws in layout pixels: what a screen's layer laid out with
## `fit_layer` has room for (SIZE in the shipped picture).
static func layout_of(viewport: Viewport) -> Vector2:
	var picture: Vector2 = picture_of(viewport)
	return picture / float(scale_of(picture))


## A point of the picture (px) in layout pixels.
static func to_layout(point: Vector2, picture: Vector2) -> Vector2:
	return point / float(scale_of(picture))


## Draws `layer` (a screen's layer) `scale_of` times bigger, and lays `full` (its full-screen Control,
## or null) out over SIZE's share of the picture: the picture's size in layout pixels, from its top
## left. Call it again when the picture's size changes (`keep_fitted` does).
static func fit_layer(layer: CanvasLayer, full: Control = null) -> void:
	var viewport: Viewport = layer.get_viewport() if layer.is_inside_tree() else null
	var picture: Vector2 = picture_of(viewport)
	var by: int = scale_of(picture)
	layer.transform = Transform2D.IDENTITY.scaled(Vector2(by, by))
	if full != null:
		full.set_anchors_preset(Control.PRESET_TOP_LEFT)
		full.position = Vector2.ZERO
		full.size = picture / float(by)


## `fit_layer` now and whenever its viewport's size changes (a benchmark's picture, a test's), for as
## long as the layer is in the tree: connected as it enters and let go as it leaves, so a freed layer
## leaves nothing behind on the viewport. Once a layer, however often it is called.
static func keep_fitted(layer: CanvasLayer, full: Control = null) -> void:
	fit_layer(layer, full)
	if layer.has_meta(FITTED_META):
		return
	var refit := func() -> void: fit_layer(layer, full)
	var watch := func(on: bool) -> void:
		var viewport: Viewport = layer.get_viewport()
		if viewport == null:
			return
		if on and not viewport.size_changed.is_connected(refit):
			viewport.size_changed.connect(refit)
			fit_layer(layer, full)
		elif not on and viewport.size_changed.is_connected(refit):
			viewport.size_changed.disconnect(refit)
	layer.set_meta(FITTED_META, refit)
	layer.tree_entered.connect(watch.bind(true))
	layer.tree_exiting.connect(watch.bind(false))
	if layer.is_inside_tree():
		watch.call(true)


## Lays `control` (a full-screen Control with no CanvasLayer of its own: the main menu) out over the
## picture in layout pixels and draws it `scale_of` times bigger, as `fit_layer` does for a layer.
static func fit_control(control: Control) -> void:
	var viewport: Viewport = control.get_viewport() if control.is_inside_tree() else null
	var picture: Vector2 = picture_of(viewport)
	var by: int = scale_of(picture)
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = Vector2.ZERO
	control.scale = Vector2(by, by)
	control.size = picture / float(by)
