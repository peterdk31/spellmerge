extends "res://tests/support/suite.gd"
## A laid room's decals drawn from one page each (gameplay/feel/decal_pages.gd; the owner's choice of
## 2026-11-21, after #900: "a candle is 1 call instead of 2"): the candles' wax and their flame's
## frames are copies of their own art on one page (a torch's bracket and flame too), the light's
## glow and core left as they are; the flame's frames keep their order, durations, speed and loop,
## and a flame already playing plays on from its frame. Guards the win: every decal of every room
## template drawing two plain layers or more draws them from one page once laid.
const DecalPagesScript := preload("res://gameplay/feel/decal_pages.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const CANDLES: PackedScene = preload("res://content/rooms/crypt/decals/candles.tscn")
const TORCH: PackedScene = preload("res://content/rooms/crypt/decals/torch.tscn")


func _laid(scene: PackedScene) -> Node2D:
	var layout := Node2D.new()
	layout.add_child(scene.instantiate())
	return own(layout) as Node2D


func _pixels(texture: Texture2D) -> PackedByteArray:
	var image: Image = texture.get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image.get_data()


## The atlas every plain layer of `decal` reads (null when they read more than one, or none).
func _one_page(decal: Node) -> Texture2D:
	var page: Texture2D = null
	for item: CanvasItem in DecalPagesScript.plain_layers(decal):
		var textures: Array[Texture2D] = []
		if item is Sprite2D:
			textures.append((item as Sprite2D).texture)
		else:
			var frames: SpriteFrames = (item as AnimatedSprite2D).sprite_frames
			for animation: StringName in frames.get_animation_names():
				for k in frames.get_frame_count(animation):
					textures.append(frames.get_frame_texture(animation, k))
		for texture: Texture2D in textures:
			var atlas: Texture2D = (texture as AtlasTexture).atlas if texture is AtlasTexture else texture
			if page == null:
				page = atlas
			elif atlas != page:
				return null
	return page


func test_a_candle_s_wax_and_flame_are_one_page_of_their_own_pixels() -> void:
	var layout: Node2D = _laid(CANDLES)
	var candles: Node = layout.get_child(0)
	var wax := candles.get_node("Wax") as Sprite2D
	var flame := candles.get_node("Flame") as AnimatedSprite2D
	var wax_art: Texture2D = wax.texture
	var own_frames: SpriteFrames = flame.sprite_frames
	var glow_art: Texture2D = (candles.get_node("Glow") as Sprite2D).texture
	check_equal(DecalPagesScript.put_on_pages(layout), 1, "one decal put on a page")
	var page: Texture2D = _one_page(candles)
	check(page != null and wax.texture is AtlasTexture and (wax.texture as AtlasTexture).atlas == page, "the wax and every flame frame on one page")
	check(TexturePage.pixels_of(wax.texture).get_data() == _pixels(wax_art), "the wax's own pixels")
	var frames: SpriteFrames = flame.sprite_frames
	check(DecalPagesScript.own_frames_of(frames) == own_frames, "the flame's frames a copy of its own")
	for animation: StringName in own_frames.get_animation_names():
		check(frames.has_animation(animation), "%s kept" % animation)
		check_equal(frames.get_frame_count(animation), own_frames.get_frame_count(animation), "%s: its frames" % animation)
		check_equal(frames.get_animation_speed(animation), own_frames.get_animation_speed(animation), "%s: its speed" % animation)
		check_equal(frames.get_animation_loop(animation), own_frames.get_animation_loop(animation), "%s: its loop" % animation)
		for k in own_frames.get_frame_count(animation):
			check_equal(frames.get_frame_duration(animation, k), own_frames.get_frame_duration(animation, k), "%s %d: its duration" % [animation, k])
			check(TexturePage.pixels_of(frames.get_frame_texture(animation, k)).get_data() == _pixels(own_frames.get_frame_texture(animation, k)), "%s %d: its own pixels" % [animation, k])
	check((candles.get_node("Glow") as Sprite2D).texture == glow_art, "the light's glow left as it is")
	var other: Node2D = _laid(CANDLES)
	DecalPagesScript.put_on_pages(other)
	check(_one_page(other.get_child(0)) == page and (other.get_child(0).get_node("Flame") as AnimatedSprite2D).sprite_frames == frames, "another candle: the same page and frames")


func test_a_playing_flame_plays_on_from_its_frame() -> void:
	var layout: Node2D = _laid(TORCH)
	root.add_child(layout)
	var flame := layout.get_child(0).get_node("Flame") as AnimatedSprite2D
	check(flame.is_playing(), "the flame plays (autoplay)")
	flame.frame = 2
	flame.frame_progress = 0.5
	check_equal(DecalPagesScript.put_on_pages(layout), 1, "the torch put on a page")
	check(_one_page(layout.get_child(0)) != null, "its bracket and flame on one page")
	check(flame.is_playing() and flame.frame == 2 and is_equal_approx(flame.frame_progress, 0.5), "playing on from the frame it was at")
	root.remove_child(layout)


func test_every_room_template_s_decals_are_on_one_page_each_once_laid() -> void:
	var registry := root.get_node("/root/Registry") as RegistryScript
	var decals: int = 0
	for item: Resource in registry.get_all(&"rooms"):
		var room := item as RoomBase
		if room == null or room.scene == null:
			continue
		var layout: Node = own(room.build())
		DecalPagesScript.put_on_pages(layout)
		for node: Node in layout.find_children("*", "Node2D", true, false):
			if DecalPagesScript.is_decal(node) and DecalPagesScript.plain_layers(node).size() >= 2:
				decals += 1
				check(_one_page(node) != null, "%s, %s: its plain layers on one page" % [room.id, layout.get_path_to(node)])
	check(decals >= 20, "the rooms' candles and torches were checked (%d)" % decals)
