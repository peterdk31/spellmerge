extends Node
## A pass drawn at the light's resolution (gameplay/feel/picture_grid.gd; the owner's decision of
## 2026-11-21, docs/milestones/connected-biomes.md, "The light at a fixed resolution"): a SubViewport
## a view, each `scale` times smaller than its view each way and drawing the world through the
## view's canvas transform scaled down by exactly `scale`, so its pixel (i, j) covers the view's
## pixels (i * scale, j * scale) to ((i + 1) * scale - 1, (j + 1) * scale - 1). What reads it
## (`light_passes.gdshaderinc`) takes that block's pixel whole: whole blocks, never blurred.
## The spell light's (`spell_light.gd`), made only while the picture is at least twice PictureGrid.SIZE
## each way. A view's size should be a whole multiple of `scale` (the screen's is, and a split view's box
## is snapped to it): else its last blocks reach past it and its light drifts by up to a block.
##
## The passes share one world (the first's): an item put under `holder()` on the shared layer (every
## canvas item's default) is drawn in every view's pass; one on `view_layer(k)` alone only in view
## `k`'s. Nothing here knows what is drawn: it is told the views and draws them.

const VIEWS_MOST: int = 4
## The layer every pass draws (a canvas item's default), and the first of the views' own.
const SHARED_LAYER: int = 1
const VIEW_FIRST_BIT: int = 1

## How many times smaller than its view each way a pass is (PictureGrid.scale_of). Read only.
var scale: int = 1
## The passes, one a view (made as needed, kept; the first always). Read only.
var viewports: Array[SubViewport] = []
## How many are drawn now. Read only.
var count: int = 0


func _init(named: String) -> void:
	name = named
	_make()


## The layer of view `view`'s own items.
static func view_layer(view: int) -> int:
	return 1 << (VIEW_FIRST_BIT + clampi(view, 0, VIEWS_MOST - 1))


## Where the items every pass draws go: the first pass's own canvas (the others share its world).
func holder() -> Node:
	return viewports[0]


## Draw `views` passes from now on, each `by` times smaller than its view (at least 1).
func use(views: int, by: int) -> void:
	scale = maxi(by, 1)
	count = clampi(views, 1, VIEWS_MOST)
	while viewports.size() < count:
		_make()
	for k in viewports.size():
		viewports[k].render_target_update_mode = SubViewport.UPDATE_ALWAYS if k < count else SubViewport.UPDATE_DISABLED


## Pass `k` fitted to `view` (before every draw): its size the view's over `scale`, rounded up, and its
## canvas transform the view's scaled down by exactly `scale`, so its blocks start at the view's corner.
func fit(k: int, view: Viewport) -> void:
	var pass_view: SubViewport = viewports[k]
	var size: Vector2 = view.get_visible_rect().size
	var wanted := Vector2i(maxi(ceili(size.x / scale - 0.0001), 1), maxi(ceili(size.y / scale - 0.0001), 1))
	if pass_view.size != wanted:
		pass_view.size = wanted
	pass_view.canvas_transform = Transform2D(0.0, Vector2.ONE / float(scale), 0.0, Vector2.ZERO) * view.global_canvas_transform * view.canvas_transform


## Pass `k`'s picture (what a reader of view `k` samples).
func texture(k: int) -> Texture2D:
	return viewports[k].get_texture() if k < viewports.size() else null


## Pass `k` drawn before `reader` (Godot draws a viewport's children first): made after the views, it
## would be read a frame late.
func draw_before(k: int, reader: Viewport) -> void:
	RenderingServer.viewport_set_parent_viewport(viewports[k].get_viewport_rid(), reader.get_viewport_rid())


func _make() -> void:
	var pass_view := SubViewport.new()
	var k: int = viewports.size()
	pass_view.name = "%s%d" % [name, k]
	if k > 0:
		pass_view.world_2d = viewports[0].world_2d
	pass_view.transparent_bg = true
	pass_view.disable_3d = true
	pass_view.gui_disable_input = true
	pass_view.size = Vector2i(1, 1)
	pass_view.canvas_cull_mask = SHARED_LAYER | view_layer(k)
	pass_view.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	pass_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(pass_view)
	viewports.append(pass_view)
