extends "res://tests/support/suite.gd"
## The one rule for mixed art (ART0; core/display/art_detail.gd, docs/STYLE.md, "The picture and the
## art's detail"): a texture whose file is named `<name>@2x.<ext>` has two art pixels a world pixel and
## is drawn at half its size; a texture made in the game carries its source's detail (`mark`, a
## TexturePage region); an atlas region has its atlas's. Sprites, faces, the staff's head, a page and
## the baked floor take it; strips and frame counts are as they were.

const CURL_HEAD: Texture2D = preload("res://content/wizard/staffs/curl/head@2x.png")
const DOOR: Texture2D = preload("res://art/tilesets/crypt/door.svg")
const WizardScene := preload("res://content/wizard/base/wizard.tscn")


func _art(size: Vector2i) -> Texture2D:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	return ImageTexture.create_from_image(image)


func test_a_texture_says_its_detail_by_its_file_s_name() -> void:
	check_equal(ArtDetail.of(CURL_HEAD), 2, "head@2x.png: two art pixels a world pixel")
	check_equal(ArtDetail.of(DOOR), 1, "door.svg: one")
	check_equal(ArtDetail.of(null), 1, "none: one")
	check_equal(ArtDetail.of(_art(Vector2i(8, 8))), 1, "a texture made in the game, unmarked: one")
	check_equal(ArtDetail.size_of(CURL_HEAD), CURL_HEAD.get_size() * 0.5, "its size in the world: half its pixels")
	check_equal(ArtDetail.size_of(DOOR), DOOR.get_size(), "a 1x texture's: its pixels")
	check_equal(ArtDetail.draw_scale(CURL_HEAD), Vector2(0.5, 0.5), "drawn at half")
	check_equal(ArtDetail.quad_size(CURL_HEAD, Vector2(96.0, 96.0)), Vector2(48.0, 48.0), "a batch's quad: its frame in world units")
	check_equal(ArtDetail.to_art(CURL_HEAD, Vector2(24.0, 27.0)), Vector2(48.0, 54.0), "a grip in its art's pixels")


func test_a_made_texture_and_a_region_carry_their_detail() -> void:
	var made: Texture2D = ArtDetail.mark(_art(Vector2i(16, 16)), 2)
	check_equal(ArtDetail.of(made), 2, "marked: 2")
	var region := AtlasTexture.new()
	region.atlas = CURL_HEAD
	region.region = Rect2(0, 0, 96, 96)
	check_equal(ArtDetail.of(region), 2, "a region of a 2x sheet: its atlas's")
	ArtDetail.mark(region, 1)
	check_equal(ArtDetail.of(region), 1, "its mark wins")


func test_a_page_keeps_each_texture_s_detail() -> void:
	var regions: Array[Texture2D] = TexturePage.regions_of([CURL_HEAD, DOOR] as Array[Texture2D])
	check(regions[0] is AtlasTexture and regions[1] is AtlasTexture, "both on a page")
	check_equal(ArtDetail.of(regions[0]), 2, "the 2x head's copy is drawn at half")
	check_equal(ArtDetail.of(regions[1]), 1, "the 1x door's copy as it was")


func test_a_sprite_is_fitted_with_its_pose_and_snapped_to_its_art_s_pixels() -> void:
	var sprite: Sprite2D = own(Sprite2D.new()) as Sprite2D
	sprite.texture = CURL_HEAD
	ArtDetail.fit(sprite, Vector2(1.2, 0.85))
	check(sprite.scale.is_equal_approx(Vector2(0.6, 0.425)), "a 2x sheet at half, times its pose (%s)" % sprite.scale)
	sprite.texture = DOOR
	ArtDetail.fit(sprite)
	check_equal(sprite.scale, Vector2.ONE, "a 1x sheet at its size")
	check_equal(ArtDetail.snap(Vector2(10.3, 4.8), 2), Vector2(10.5, 5.0), "2x art on half world pixels")
	check_equal(ArtDetail.snap(Vector2(10.3, 4.8), 1), Vector2(10.0, 5.0), "1x art on whole ones")


## The curl drawn at half size, its frames and grip where the 48 px sheet's were: the shot leaves its
## tip whichever sheet is on show, and the face wears the staff's own sheets at half.
func test_the_wizard_draws_a_2x_head_and_face_where_a_1x_one_stands() -> void:
	var wizard: Node2D = own(WizardScene.instantiate()) as Node2D
	root.add_child(wizard)
	var sprite := wizard.get_node(^"Sprite") as Sprite2D
	var face := wizard.get_node(^"Face") as Face
	check(sprite.texture == CURL_HEAD, "the default head is the curl's, at 2x")
	check_equal(sprite.hframes, StaffLook.DIRECTIONS, "a frame a direction, as before")
	check_equal(sprite.vframes, StaffLook.RAMPS, "a row a ramp, as before")
	check_equal(sprite.scale, Vector2(0.5, 0.5), "drawn at half")
	check_equal(sprite.offset, (Vector2(StaffLook.FRAME_SIZE, StaffLook.FRAME_SIZE) * 0.5 - StaffLook.GRIP) * 2.0, "its grip on the hand, in its own pixels")
	check(sprite.get_rect().size * sprite.scale == Vector2(StaffLook.FRAME_SIZE, StaffLook.FRAME_SIZE), "a frame is 48 world pixels")
	var curl: StaffBase = load("res://content/wizard/staffs/curl/curl.tres") as StaffBase
	face.wear_art(curl.face)
	var layers: Array[Texture2D] = face.layer_textures()
	check(layers.size() == 2 and layers[0] == curl.face.eyes and layers[1] == curl.face.brows, "the face wears the curl's own sheets")
	for child: Node in face.get_children():
		var layer := child as Sprite2D
		if layer != null:
			check_equal(layer.scale, Vector2(0.5, 0.5), "a 2x face layer at half")
			check_equal(layer.hframes * layer.texture.get_width() / layer.hframes, layer.texture.get_width(), "whole frames")
	face.wear_art(null)
	layers = face.layer_textures()
	check(layers.size() == 2 and layers[0] != curl.face.eyes, "and the shared sheets again")
	for child: Node in face.get_children():
		var layer := child as Sprite2D
		if layer != null:
			check_equal(layer.scale, Vector2.ONE, "a 1x face layer at its size")
	wizard.get_parent().remove_child(wizard)
