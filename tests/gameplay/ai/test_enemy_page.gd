extends "res://tests/support/suite.gd"
## An enemy's body and its face on one page a kind (gameplay/ai/creature_look.gd, `_put_on_page`;
## the owner's choice of 2026-11-21, after #900: "an enemy is 1 draw call instead of 2"): set up, a
## body of one sprite wearing the shared face draws its body, its eyes and its brows from one page,
## each a copy of its own art (so the same pixels on screen), every enemy of its kind from the same
## page; set up again it stays on that page; its poses' strips go on the page too. A boss (phases,
## layered body, a face of its own) keeps its art. Guards the win: every enemy kind of the game
## that has one body sprite and the shared face is drawn from one page.
const AiFixture := preload("res://tests/gameplay/ai/ai_fixture.gd")
const ImpData: EnemyBase = preload("res://content/enemies/ember_imp/ember_imp.tres")
const MaterializeScript := preload("res://gameplay/feel/spawn_motions/materialize.gd")

var _world: AiFixture


func before_each() -> void:
	_world = AiFixture.new(root)


func after_each() -> void:
	_world.free_all()


func _registry() -> Node:
	return root.get_node("/root/Registry")


## The body sprite's and the face's two layers' textures of `body`.
func _drawn(body: Actor) -> Array[Texture2D]:
	var face := body.get_node(^"Face") as Face
	var layers: Array[Texture2D] = [(body.get_node(^"Sprite") as Sprite2D).texture]
	layers.append_array(face.layer_textures())
	return layers


func _pixels(texture: Texture2D) -> PackedByteArray:
	var image: Image = texture.get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image.get_data()


func test_an_imp_s_body_and_face_are_one_page_of_their_own_pixels() -> void:
	var imp: Actor = _world.imp()
	var other: Actor = _world.imp(Vector2(64.0, 0.0))
	var drawn: Array[Texture2D] = _drawn(imp)
	check_equal(drawn.size(), 3, "a body and two face layers")
	var page: Texture2D = (drawn[0] as AtlasTexture).atlas if drawn[0] is AtlasTexture else null
	check(page != null, "the body is a region of a page")
	var fresh: Node = own(ImpData.scene.instantiate())
	var sources: Array[Texture2D] = [(fresh.get_node(^"Sprite") as Sprite2D).texture, Face.EYES_SHEET, Face.BROWS_SHEET]
	for i in drawn.size():
		var region := drawn[i] as AtlasTexture
		check(region != null and region.atlas == page, "layer %d on the body's page" % i)
		if region == null:
			continue
		check(TexturePage.source_of(region) == sources[i], "layer %d: a copy of its own art" % i)
		check_equal(region.get_size(), sources[i].get_size(), "layer %d: its own size" % i)
		check(TexturePage.pixels_of(region).get_data() == _pixels(sources[i]), "layer %d: its own pixels" % i)
	check(_drawn(other) == drawn, "another imp: the same page and regions")
	var look := imp.get_node(^"CreatureLook") as CreatureLook
	look.setup(imp)
	check(_drawn(imp) == drawn, "set up again: still the same regions")


func test_its_poses_go_on_the_page_too() -> void:
	var body: Actor = ImpData.scene.instantiate() as Actor
	var look := body.get_node(^"CreatureLook") as CreatureLook
	var strip := ImageTexture.create_from_image(Image.create(64, 32, false, Image.FORMAT_RGBA8))
	look.windup_texture = strip
	body.data = ImpData
	_world.wire(body)
	own(body)
	root.add_child(body)
	body.ticking = false
	var page: Texture2D = ((body.get_node(^"Sprite") as Sprite2D).texture as AtlasTexture).atlas
	check(look.windup_texture is AtlasTexture and (look.windup_texture as AtlasTexture).atlas == page, "the windup strip on the body's page")
	check_equal(look.windup_texture.get_size(), Vector2(64, 32), "its own size, so its frames are as many")
	check(look.hurt_texture == null, "no hurt pose: none")


func test_every_enemy_kind_of_one_body_and_the_shared_face_is_one_page() -> void:
	var checked: int = 0
	for item: Resource in _registry().get_all(&"enemies"):
		var data := item as EnemyBase
		if data == null or data.scene == null:
			continue
		var body: Actor = _world.enemy(data.scene, data, Vector2(-400.0 - 64.0 * checked, 0.0))
		var face := body.get_node_or_null(^"Face") as Face
		var look := body.get_node_or_null(^"CreatureLook") as CreatureLook
		if face == null or look == null or face.art != null or body.phases != null or not look.parts().is_empty():
			continue
		var drawn: Array[Texture2D] = _drawn(body)
		var page: Texture2D = (drawn[0] as AtlasTexture).atlas if drawn[0] is AtlasTexture else null
		check(page != null and drawn.all(func(t: Texture2D) -> bool: return t is AtlasTexture and (t as AtlasTexture).atlas == page), "%s: its body and face on one page" % data.id)
		checked += 1
	check(checked >= 5, "the game's enemy kinds were checked (%d)" % checked)


## Regression (the review of 2026-11-21): the materialize look's lit rows draw from the texture's
## RID, which for a region is its page's, so a region's cut is moved to where it lies on the page.
func test_a_lit_row_of_a_paged_body_is_cut_from_its_place_on_the_page() -> void:
	var strip := ImageTexture.create_from_image(Image.create(64, 32, false, Image.FORMAT_RGBA8))
	var body := ImageTexture.create_from_image(Image.create(32, 32, false, Image.FORMAT_RGBA8))
	var paged: Array[Texture2D] = TexturePage.regions_of([body, strip] as Array[Texture2D])
	var region := paged[1] as AtlasTexture
	var cut := Rect2(32.0, 10.0, 32.0, 1.0)
	check_equal(MaterializeScript.on_page(region, cut), Rect2(region.region.position + cut.position, cut.size), "the strip's frame cut where the strip lies on the page")
	check_equal(MaterializeScript.on_page(body, cut), cut, "a texture of its own: as it is")
