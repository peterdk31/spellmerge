extends "res://tests/support/screenshot.gd"
## Screenshots of the crypt room's moving decals and the hit particles.
##
## Shots: the room with its lit torches and 2.5D pillars and a wizard behind and one in front
## of a pillar (`crypt_pillars_torches`), a crop of those pillars at 4x
## (`crypt_pillar_walk_behind`), a shot ending on a wall (`impact_wall`), an imp and then a
## wizard hit by a shot flying right (`impact_hit_enemy`, `impact_hit_wizard`).



func take() -> void:
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await settle()
	if not need(["PlayerInput", "Flow", "Feel", "Combat", "Projectiles", "Events"]):
		return
	# Feel ages its effects on the real clock, which a slow virtual display stretches past
	# their tenths of a second; on game time each frame is 1/60 s, as in play.
	if root.has_node("Feel"):
		root.get_node("Feel").set("drive_engine", false)
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var combat: Node = root.get_node("Combat")
	var shots: Node = root.get_node("Projectiles")
	var events: Node = root.get_node("Events")
	for index in 4:
		input.call("add_virtual_device", index)
	flow.call("start_run", 0)
	await settle()
	# The first pillar's footprint is (160, 128) to (192, 160). One wizard stands behind it
	# (its top draws over the wizard), one in front (it draws over the pillar).
	var behind: Node2D = flow.call("get_wizard", 0) as Node2D
	var front: Node2D = flow.call("get_wizard", 1) as Node2D
	if behind == null or front == null:
		fail("two wizards are needed")
		return
	# Shots, hits and impacts name their caster by actor id: the actor wizard 1 opened (actors G3b).
	var caster: int = int(behind.get("actor_id"))
	behind.global_position = Vector2(170.0, 118.0)
	front.global_position = Vector2(184.0, 172.0)
	await settle()
	var image: Image = await grab()
	save(image, "crypt_pillars_torches")
	save_crop(image, on_screen(Vector2(176.0, 135.0)), "crypt_pillar_walk_behind")
	# A shot that ends on the left wall.
	shots.call("spawn", caster, Vector2(60.0, 250.0), Vector2(-300.0, 0.0), 1.0)
	for i in 4:
		await physics_frame
	await snap(Vector2(40.0, 250.0), "impact_wall")
	await settle()
	# A shot that hits an imp, flying right, then one that hits a wizard, flying left.
	var imps: Array = flow.get("_enemies")
	var imp: Node2D = null
	for candidate: Variant in imps:
		if is_instance_valid(candidate):
			imp = candidate as Node2D
			break
	if imp == null:
		fail("there is no imp to hit")
		return
	var imp_at: Vector2 = imp.get_global_transform_with_canvas().origin
	events.call("emit_signal", "projectile_impact", caster, imp, imp.global_position + Vector2(-8.0, -12.0), Vector2.RIGHT)
	combat.call("hit", caster, imp, 5)
	await physics_frame
	save_crop(await grab(), imp_at + Vector2(0.0, -12.0), "impact_hit_enemy")
	await settle()
	front.global_position = Vector2(400.0, 300.0)
	var front_at: Vector2 = front.get_global_transform_with_canvas().origin
	events.call("emit_signal", "projectile_impact", -1, front, front.global_position + Vector2(8.0, -12.0), Vector2.LEFT)
	combat.call("hit", -1, front, 5)
	await physics_frame
	save_crop(await grab(), front_at + Vector2(0.0, -12.0), "impact_hit_wizard")
