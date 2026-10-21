extends SceneTree
## Screenshots of the crypt room's moving decals and the hit particles, for people and for
## Claude to look at (it only checks that each staged state happened). Needs a display, so it
## runs only through `ci/build/build.sh --quick --screenshots`; each shot is saved as
## user://screenshots/<name>.png and copied to build/screenshots/.
##
## Shots: the room with its lit torches and 2.5D pillars and a wizard behind and one in front
## of a pillar (`crypt_pillars_torches`), a crop of those pillars at 4x
## (`crypt_pillar_walk_behind`), a shot ending on a wall (`impact_wall`), an imp and then a
## wizard hit by a shot flying right (`impact_hit_enemy`, `impact_hit_wizard`).

const SHOTS_DIR := "user://screenshots"
const SETTLE_FRAMES := 20


func _initialize() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS_DIR)
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await _settle()
	var input: Node = root.get_node_or_null("PlayerInput")
	var flow: Node = root.get_node_or_null("Flow")
	var feel: Node = root.get_node_or_null("Feel")
	var combat: Node = root.get_node_or_null("Combat")
	var shots: Node = root.get_node_or_null("Projectiles")
	var events: Node = root.get_node_or_null("Events")
	if input == null or flow == null or feel == null or combat == null or shots == null or events == null:
		_fail("the PlayerInput, Flow, Feel, Combat, Projectiles and Events autoloads must exist")
		return
	for index in 4:
		input.call("add_virtual_device", index)
	flow.call("start_run", 0)
	await _settle()
	# The first pillar's footprint is (160, 128) to (192, 160). One wizard stands behind it
	# (its top draws over the wizard), one in front (it draws over the pillar).
	var behind: Node2D = flow.call("get_wizard", 0) as Node2D
	var front: Node2D = flow.call("get_wizard", 1) as Node2D
	if behind == null or front == null:
		_fail("two wizards are needed")
		return
	behind.global_position = Vector2(170.0, 118.0)
	front.global_position = Vector2(184.0, 172.0)
	await _settle()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png("%s/crypt_pillars_torches.png" % SHOTS_DIR)
	print("SHOT: crypt_pillars_torches (%dx%d)" % [image.get_width(), image.get_height()])
	_save_crop_at(image, _on_screen(Vector2(176.0, 135.0)), "crypt_pillar_walk_behind")
	# A shot that ends on the left wall.
	shots.call("spawn", 0, Vector2(60.0, 250.0), Vector2(-300.0, 0.0), 1.0)
	for i in 4:
		await physics_frame
	await RenderingServer.frame_post_draw
	_save_crop_at(root.get_texture().get_image(), _on_screen(Vector2(40.0, 250.0)), "impact_wall")
	await _settle()
	# A shot that hits an imp, flying right, then one that hits a wizard, flying left.
	var imps: Array = flow.get("_enemies")
	var imp: Node2D = null
	for candidate: Variant in imps:
		if is_instance_valid(candidate):
			imp = candidate as Node2D
			break
	if imp == null:
		_fail("there is no imp to hit")
		return
	var imp_at: Vector2 = imp.get_global_transform_with_canvas().origin
	events.call("emit_signal", "projectile_impact", 0, imp, imp.global_position + Vector2(-8.0, -12.0), Vector2.RIGHT)
	combat.call("hit", 0, imp, 5)
	await physics_frame
	await RenderingServer.frame_post_draw
	_save_crop_at(root.get_texture().get_image(), imp_at + Vector2(0.0, -12.0), "impact_hit_enemy")
	await _settle()
	front.global_position = Vector2(400.0, 300.0)
	var front_at: Vector2 = front.get_global_transform_with_canvas().origin
	events.call("emit_signal", "projectile_impact", -1, front, front.global_position + Vector2(8.0, -12.0), Vector2.LEFT)
	combat.call("hit", -1, front, 5)
	await physics_frame
	await RenderingServer.frame_post_draw
	_save_crop_at(root.get_texture().get_image(), front_at + Vector2(0.0, -12.0), "impact_hit_wizard")
	quit(0)


## Where the world point `at` is on the screen (the camera moves the canvas).
func _on_screen(at: Vector2) -> Vector2:
	return root.get_canvas_transform() * at


## Save the 96x96 pixels of `image` around the screen position `at`, enlarged 4 times.
func _save_crop_at(image: Image, at: Vector2, name: String) -> void:
	var size: Vector2 = Vector2(image.get_size())
	var scale_to_image: Vector2 = size / Vector2(root.get_visible_rect().size)
	var centre: Vector2 = at * scale_to_image
	var half: int = 48
	var corner: Vector2i = Vector2i(centre) - Vector2i(half, half)
	corner = corner.clamp(Vector2i.ZERO, Vector2i(image.get_size()) - Vector2i(half * 2, half * 2))
	var crop: Image = image.get_region(Rect2i(corner, Vector2i(half * 2, half * 2)))
	crop.resize(half * 8, half * 8, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s.png" % [SHOTS_DIR, name])
	print("SHOT: %s" % name)


func _fail(message: String) -> void:
	printerr("SHOT FAILED: " + message)
	quit(1)


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame
