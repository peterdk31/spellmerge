extends "res://tests/support/suite.gd"
## The light at a fixed resolution (the owner's decision of 2026-11-21, docs/milestones/
## connected-biomes.md, "The light at a fixed resolution"; gameplay/feel/picture_grid.gd,
## light_passes.gd): at PictureGrid.SIZE nothing changes (no pass, the buffer a quarter of the view);
## in a picture twice as big each way the buffer keeps its size, the apply rect's factor and the mist's
## billows are drawn in a pass a view at PictureGrid.SIZE and read back by blocks, a split view's box
## stays on the blocks' grid, and the cameras draw the same world twice as fine. How it looks is checked
## by eye (tests/screenshots/shot_light_resolution.gd): headless runs draw nothing.

const PictureGridScript := preload("res://gameplay/feel/picture_grid.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const LightPassesScript := preload("res://gameplay/feel/light_passes.gd")
const MistScript := preload("res://gameplay/feel/mist.gd")
const SplitScreenScript := preload("res://gameplay/feel/split_screen.gd")
const ScreenViewsScript := preload("res://core/display/screen_views.gd")
const PartyCameraScript := preload("res://gameplay/feel/party_camera.gd")
const ShaderWarmupScript := preload("res://core/projectiles/shader_warmup.gd")
const SpectacleScript := preload("res://gameplay/feel/spectacle.gd")
const ViewReadersScript := preload("res://gameplay/feel/view_readers.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const EventsScript := preload("res://core/events/events.gd")
const ProjectilesScript := preload("res://core/projectiles/projectile_manager.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")
const FeelPresetScript := preload("res://gameplay/feel/presets/feel_preset.gd")
const ActorSeats := preload("res://tests/support/actor_seats.gd")

const BIG := Vector2i(1280, 720)

var _shipped: Vector2i = Vector2i.ZERO


func before_each() -> void:
	_shipped = root.content_scale_size


func after_each() -> void:
	root.content_scale_size = _shipped


## A uniform's int, 0 for one never set (its default).
func _int(value: Variant) -> int:
	return int(value) if value != null else 0


func test_the_grid_scale_is_the_whole_times_the_picture_holds_the_grid() -> void:
	check_equal(PictureGridScript.SIZE, Vector2i(640, 360), "the light's resolution is the game's picture")
	check_equal(PictureGridScript.scale_of(Vector2(640.0, 360.0)), 1, "the shipped picture: 1")
	check_equal(PictureGridScript.scale_of(Vector2(1280.0, 720.0)), 2, "1280 x 720: 2")
	check_equal(PictureGridScript.scale_of(Vector2(1920.0, 1080.0)), 3, "1920 x 1080: 3")
	check_equal(PictureGridScript.scale_of(Vector2(1280.0, 700.0)), 1, "both ways must hold it")
	check_equal(PictureGridScript.scale_of(Vector2(320.0, 180.0)), 1, "never under 1")


func test_at_the_shipped_picture_the_light_has_no_passes() -> void:
	var light := own(SpellLightScript.new(null, 0)) as SpellLightScript
	root.add_child(light)
	light.follow()
	var size: Vector2 = root.get_visible_rect().size
	check_equal(light.grid_scale, PictureGridScript.scale_of(size), "the light's scale is the picture's")
	if light.grid_scale != 1:
		return
	check(light.factor_passes == null and light.under_passes == null and light.under_holder() == null, "no pass at PictureGrid.SIZE")
	check_equal(Vector2i(light.grid.view_size[0], light.grid.view_size[1]), Vector2i(ceili(size.x / light.grid.cell), ceili(size.y / light.grid.cell)), "the grid covers the view in cells of its own size")
	var apply := light.apply.material as ShaderMaterial
	check_equal(_int(apply.get_shader_parameter(SpellLightScript.PASS_VIEWS)), 0, "the apply rect works its light out where it is drawn")
	light.release()


func test_a_bigger_picture_draws_the_light_at_its_resolution_and_back() -> void:
	var light := own(SpellLightScript.new(null, 0)) as SpellLightScript
	root.add_child(light)
	var reader := ShaderMaterial.new()
	reader.shader = MistScript.SHADER
	light.read_by(&"mist", reader)
	light.set_ambient(0.6, Color(0.8, 0.9, 1.0))
	root.content_scale_size = BIG
	var changed: Array[int] = [0]
	light.passes_changed.connect(func() -> void: changed[0] += 1)
	light.follow()
	if Vector2i(root.get_visible_rect().size) != BIG:
		check(false, "the root draws the picture asked (%s)" % root.get_visible_rect().size)
		return
	check_equal(light.grid_scale, 2, "a picture twice as big each way")
	check_equal(changed[0], 1, "the passes came, once")
	var shown: Rect2 = (root.global_canvas_transform * root.canvas_transform).affine_inverse() * root.get_visible_rect()
	check(light.grid.view_size[0] * light.grid.cell >= shown.size.x and light.grid.view_size[0] * light.grid.cell < shown.size.x + 2.0 * light.grid.cell, "the grid's cells are the world's, covering what the picture shows (%s cells over %s)" % [light.grid.view_size[0], shown.size.x])
	check(light.factor_passes != null and light.under_holder() != null, "a factor pass and a pass under the light")
	var factor: SubViewport = light.factor_passes.viewports[0]
	check_equal(factor.size, PictureGridScript.SIZE, "the factor pass is PictureGrid.SIZE")
	check_equal(light.under_passes.viewports[0].size, PictureGridScript.SIZE, "and so is the pass under the light")
	var world := Vector2(300.0, 200.0)
	var on_screen: Vector2 = root.global_canvas_transform * root.canvas_transform * world
	check((factor.canvas_transform * world).is_equal_approx(on_screen * 0.5), "a point lands in its block: %s against %s" % [factor.canvas_transform * world, on_screen * 0.5])
	check_equal(light.factor_rects.size(), 1, "a factor rect for the one picture")
	var rect: ColorRect = light.factor_rects[0]
	check(rect.get_parent() == light.factor_passes.holder(), "drawn in the factor pass")
	check_equal(rect.visibility_layer, LightPassesScript.view_layer(0), "on its view's layer alone")
	check(factor.canvas_cull_mask & rect.visibility_layer != 0, "which its pass draws")
	var drawn := rect.material as ShaderMaterial
	check(drawn.shader == SpellLightScript.FACTOR_SHADER, "with the factor shader")
	check(drawn.get_shader_parameter(&"light_grid") == light.grid.texture and int(drawn.get_shader_parameter(&"light_grid_view_id")) == 0, "reading the view's grid")
	check(is_equal_approx(float(drawn.get_shader_parameter(&"ambient")), 0.6), "with the apply rect's ambient")
	light.set_bands(0)
	light.set_ambient(0.7)
	check_equal(int(drawn.get_shader_parameter(&"bands")), 0, "the steps set reach it")
	check(is_equal_approx(float(drawn.get_shader_parameter(&"ambient")), 0.7), "and the ambient")
	var apply := light.apply.material as ShaderMaterial
	check_equal(_int(apply.get_shader_parameter(SpellLightScript.PASS_VIEWS)), 1, "the apply rect reads the one view's pass")
	check(apply.get_shader_parameter(&"light_pass_0") == light.factor_passes.texture(0), "its factor pass")
	check_equal(int(apply.get_shader_parameter(SpellLightScript.PASS_SCALE)), 2, "by blocks of 2")
	check(reader.get_shader_parameter(&"light_pass_0") == light.under_passes.texture(0), "a reader under the light reads the pass under it")
	check_equal(_int(reader.get_shader_parameter(SpellLightScript.PASS_VIEWS)), 1, "for the one view")
	root.content_scale_size = _shipped
	light.follow()
	if PictureGridScript.scale_of(root.get_visible_rect().size) == 1:
		check_equal(changed[0], 2, "the passes went")
		check(light.factor_passes == null and light.under_holder() == null and light.factor_rects.is_empty(), "no pass left")
		check_equal(_int(apply.get_shader_parameter(SpellLightScript.PASS_VIEWS)), 0, "the apply rect works it out where it is drawn again")
		check_equal(_int(reader.get_shader_parameter(SpellLightScript.PASS_VIEWS)), 0, "and so does the reader")
	light.release()


func test_the_mist_draws_its_billows_in_the_pass_with_its_numbers() -> void:
	var mist := own(MistScript.new(3)) as MistScript
	root.add_child(mist)
	var given := RoomMist.new()
	given.thickness = 0.4
	mist.use(given)
	mist.lay(Vector2(320.0, 192.0), [] as Array[Rect2], [] as Array[Rect2], Vector2(64.0, 32.0))
	check(mist.twin == null, "no twin with no pass")
	var holder := own(Node2D.new()) as Node2D
	root.add_child(holder)
	mist.use_passes(holder)
	var twin: ColorRect = mist.twin
	check(twin != null and twin.get_parent() == holder, "a twin in the pass")
	if twin == null:
		return
	check(twin.visible, "shown with the mist")
	check_equal(twin.position, mist.position, "where the mist lies")
	check_equal(twin.size, mist.size, "as big")
	var drawn := twin.material as ShaderMaterial
	check(drawn.shader == MistScript.PASS_SHADER, "drawn by the pass shader")
	var shading := mist.material as ShaderMaterial
	for uniform: StringName in [&"thickness", &"origin", &"mask", &"mask_size", &"parted", &"scale", &"drift"]:
		check(drawn.get_shader_parameter(uniform) == shading.get_shader_parameter(uniform), "%s is the mist's" % uniform)
	mist.set_share(0.5)
	check(is_equal_approx(float(drawn.get_shader_parameter(&"thickness")), 0.2), "a share set reaches the twin")
	mist.step(4.0, PackedVector2Array(), 0)
	check(is_equal_approx(float(drawn.get_shader_parameter(&"view_time")), 4.0), "and the clock")
	mist.use_passes(null)
	check(mist.twin == null and twin.is_queued_for_deletion(), "no pass: the twin goes")
	mist.use_passes(holder)
	var again: ColorRect = mist.twin
	root.remove_child(mist)
	check(mist.twin == null and again.is_queued_for_deletion(), "the mist gone takes its twin")


func test_the_spectacles_mist_follows_the_lights_passes() -> void:
	var registry := own(RegistryScript.new()) as RegistryScript
	registry.scan()
	var bus: EventsScript = own(EventsScript.new()) as EventsScript
	var table: Node = own(ActorSeats.table()) as Node
	var manager: ProjectilesScript = own(ProjectilesScript.new()) as ProjectilesScript
	manager.events = bus
	manager.actors = table
	root.add_child(manager)
	var feel: FeelScript = own(FeelScript.new()) as FeelScript
	var preset := FeelPresetScript.new()
	preset.hit_sound = &""
	feel.events = bus
	feel.registry = registry
	feel.actors = table
	feel.projectiles = manager
	feel.drive_engine = false
	feel.preset = preset
	root.add_child(feel)
	var room := registry.get_resource(&"rooms", &"arena_04") as RoomBase
	bus.spell_light_changed.emit(true)
	bus.room_built.emit(room.id, 0, own(room.build(null)) as Node)
	bus.room_entered.emit(room.id, 0)
	feel._process(1.0 / 60.0)
	var spectacle: SpectacleScript = feel.spectacle()
	var light: SpellLightScript = spectacle.light
	check(light != null and spectacle.mist != null and spectacle.mist.visible, "a lit room with its mist")
	if light == null or spectacle.mist == null:
		return
	light.follow()
	check(spectacle.mist.twin == null, "no twin at the shipped picture")
	root.content_scale_size = BIG
	light.follow()
	var twin: ColorRect = spectacle.mist.twin
	check(twin != null and twin.get_parent() == light.under_holder(), "the mist's twin is drawn in the light's pass")
	check(light.under_passes.viewports[0].render_target_update_mode == SubViewport.UPDATE_ALWAYS, "a pass with a twin in it is drawn")
	# The mist out of the tree and back (the spectacle moved): its twin goes and comes back.
	var parent: Node = spectacle.mist.get_parent()
	parent.remove_child(spectacle.mist)
	check(spectacle.mist.twin == null, "the twin goes with the mist")
	parent.add_child(spectacle.mist)
	check(spectacle.mist.twin != null and spectacle.mist.twin.get_parent() == light.under_holder(), "and comes back with it")
	root.content_scale_size = _shipped
	light.follow()
	check(spectacle.mist.twin == null, "the passes gone, the twin goes with them")


func test_the_third_and_fourth_views_copies_hold_their_own_pass() -> void:
	var readers := ViewReadersScript.new()
	var material := ShaderMaterial.new()
	material.shader = MistScript.SHADER
	var first := ImageTexture.new()
	var third := ImageTexture.new()
	material.set_shader_parameter(&"light_pass_0", first)
	readers.set_view_uniform(material, 2, &"light_pass_0", third)
	readers.watch(material, null)
	var holder := own(Node2D.new()) as Node2D
	root.add_child(holder)
	var item := ColorRect.new()
	item.material = material
	holder.add_child(item)
	readers.take(item)
	readers.use(3)
	readers.follow([] as Array[Viewport])
	var copy: CanvasItem = readers.copy_of(item, 2)
	check(copy != null, "a copy for the third view")
	if copy == null:
		return
	var own_material := copy.material as ShaderMaterial
	check(own_material.get_shader_parameter(&"light_pass_0") == third, "it holds its own view's pass")
	check(material.get_shader_parameter(&"light_pass_0") == first, "the item keeps the first view's")
	material.set_shader_parameter(&"light_pass_0", ImageTexture.new())
	readers.follow([] as Array[Viewport])
	check(own_material.get_shader_parameter(&"light_pass_0") == third, "never copied over from the item's")
	readers.clear()


func test_the_pass_shaders_are_warmed() -> void:
	var spectacle := own(SpectacleScript.new()) as SpectacleScript
	root.add_child(spectacle)
	var warmed: Array[Shader] = ShaderWarmupScript.shaders()
	check(warmed.has(SpellLightScript.FACTOR_SHADER), "the factor shader is warmed")
	check(warmed.has(MistScript.PASS_SHADER), "the mist's pass shader is warmed")


func test_a_split_views_box_stays_on_the_blocks_grid() -> void:
	var laid := ScreenViewsScript.new()
	laid.screen = Vector2(BIG)
	laid.count = 2
	laid.set_corners(0, 4)
	for at in 4:
		laid.set_corner(0, at, [Vector2(13.0, 7.0), Vector2(611.0, 9.0), Vector2(605.0, 713.0), Vector2(11.0, 701.0)][at])
	var box: Rect2i = SplitScreenScript.view_box(laid, 0, Vector2(BIG))
	var snap: int = SplitScreenScript.BOX_SNAP * 2
	check(box.position.x % snap == 0 and box.position.y % snap == 0 and box.end.x % snap == 0 and box.end.y % snap == 0, "snapped to %d px in a picture twice as big (%s)" % [snap, box])
	check(box.end.x >= 611 + SplitScreenScript.BOX_PAD * 2, "padded twice as far (%s)" % box)
	var kept: Rect2i = SplitScreenScript.kept_box(Rect2i(), Rect2i(Vector2i(48, 32), Vector2i(320, 320)), Vector2(BIG))
	check(kept.position.x % snap == 0 and kept.position.y % snap == 0 and kept.end.x % snap == 0 and kept.end.y % snap == 0, "a kept box stays on the grid (%s)" % kept)


func test_the_party_camera_draws_the_same_world_finer_in_a_bigger_picture() -> void:
	var holder := own(SubViewport.new()) as SubViewport
	holder.disable_3d = true
	holder.size = PictureGridScript.SIZE
	root.add_child(holder)
	var camera := Camera2D.new()
	holder.add_child(camera)
	camera.make_current()
	var party := PartyCameraScript.new()
	party.follow(camera)
	party.hold(Rect2(Vector2(100.0, 100.0), Vector2(20.0, 20.0)))
	party.snap()
	var small: Rect2 = party.visible_rect()
	check(is_equal_approx(camera.zoom.x, PartyCameraScript.MAX_ZOOM), "zoomed in fully at PictureGrid.SIZE")
	holder.size = PictureGridScript.SIZE * 2
	party.snap()
	check(is_equal_approx(camera.zoom.x, PartyCameraScript.MAX_ZOOM * 2.0), "twice the zoom in a picture twice as big")
	check(party.visible_rect().is_equal_approx(small), "showing the same world: %s against %s" % [party.visible_rect(), small])
