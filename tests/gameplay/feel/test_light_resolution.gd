extends "res://tests/support/suite.gd"
## The light in a bigger picture (the owner's decisions of 2026-11-21, docs/milestones/connected-biomes.md,
## "The light at a fixed resolution", and 2026-11-22, "One pass"; gameplay/feel/picture_grid.gd): the
## grid keeps the world's cells at any size of picture, nothing is drawn into a pass for the light or
## the mist (each works it out where it is drawn), a split view's box stays on the blocks' grid, and the
## cameras draw the same world twice as fine. How it looks is checked
## by eye (tests/screenshots/shot_light_resolution.gd): headless runs draw nothing.

const PictureGridScript := preload("res://gameplay/feel/picture_grid.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
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
	check_equal(PictureGridScript.SIZE, Vector2i(640, 360), "the game's picture, at which the cameras' zoom is 1")
	check_equal(PictureGridScript.scale_of(Vector2(640.0, 360.0)), 1, "the shipped picture: 1")
	check_equal(PictureGridScript.scale_of(Vector2(1280.0, 720.0)), 2, "1280 x 720: 2")
	check_equal(PictureGridScript.scale_of(Vector2(1920.0, 1080.0)), 3, "1920 x 1080: 3")
	check_equal(PictureGridScript.scale_of(Vector2(1280.0, 700.0)), 1, "both ways must hold it")
	check_equal(PictureGridScript.scale_of(Vector2(320.0, 180.0)), 1, "never under 1")


## The one pass (the owner's decision of 2026-11-22): at the shipped picture and twice as big the
## light draws no pass of its own, its grid keeps the world's cells over what the picture shows, and
## the apply rect and the mist work everything out where they are drawn.
func test_at_any_picture_the_light_draws_no_pass() -> void:
	var light := own(SpellLightScript.new(null, 0)) as SpellLightScript
	root.add_child(light)
	var reader := ShaderMaterial.new()
	reader.shader = MistScript.SHADER
	light.read_by(&"mist", reader)
	for picture: Vector2i in [_shipped, BIG]:
		root.content_scale_size = picture
		light.follow()
		check(light.find_children("*", "SubViewport", true, false).is_empty(), "no SubViewport at %s" % picture)
		var shown: Rect2 = (root.global_canvas_transform * root.canvas_transform).affine_inverse() * root.get_visible_rect()
		check(light.grid.view_size[0] * light.grid.cell >= shown.size.x and light.grid.view_size[0] * light.grid.cell < shown.size.x + 2.0 * light.grid.cell, "the grid's cells are the world's, covering what the picture shows at %s (%s cells over %s)" % [picture, light.grid.view_size[0], shown.size.x])
	check(reader.get_shader_parameter(&"light_grid") == light.grid.texture, "the reader reads the grid")
	light.release()


## The apply rect reads the screen once and nothing drawn before it; the mist works out how thick it is
## where it is drawn.
func test_the_readers_read_no_pass() -> void:
	var code: String = SpellLightScript.APPLY_SHADER.code
	check_equal(code.count("hint_screen_texture"), 1, "the apply rect reads the screen once")
	for shader: Shader in [SpellLightScript.APPLY_SHADER, MistScript.SHADER]:
		check(not shader.code.contains("light_pass") and not shader.code.contains("light_passes"), "%s reads no pass" % shader.resource_path)
	check(MistScript.SHADER.code.contains("mist_density(world)"), "the mist's thickness is worked out where it is drawn")


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
