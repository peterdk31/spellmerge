extends "res://tests/support/screenshot.gd"
## Screenshots of a four-player run in the crypt arena, and of the menus and HUD over it.
##
## Shots: the main menu; four wizards just after Play, each aiming its own way; shots in the
## air and a wizard mid-dash; the pause menu (P2 opened it); a cast and a hit (muzzle flash,
## squash, vignette) with 4x crops; an imp's death; enemy readability (an imp winding up, a
## hurt imp, an enemy shot beside a player's shot); player 4 down, and the revive ring half
## full; a protected wizard; the Coop camera at zoom 0.5 (wizards in the corners of an area
## twice the screen). Look at them for legible 12/14 px text over the translucent panels.


func take() -> void:
	if not need(["PlayerInput", "Flow", "Hud", "Combat", "Projectiles", "Coop"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var hud: Node = root.get_node("Hud")
	change_scene_to_file("res://hud/menus/main_menu/main_menu.tscn")
	await shot("main_menu")
	for index in 4:
		input.call("add_virtual_device", index)
	flow.call("start_run", 0)
	# Each wizard aims its own way, to see the aim reticle and the turned sprites. Every shot hits
	# every actor (no sides, actors G3c), so none of the three that fire below aims at a teammate.
	var aims: Array[Vector2] = [Vector2.UP, Vector2(1, -1).normalized(), Vector2(-1, -1).normalized(), Vector2.RIGHT]
	for index in 4:
		input.call("send_virtual_aim", index, aims[index])
	await shot("arena_four_wizards")
	# Shots above the floor, fired from the staff tips, and a wizard mid-dash.
	for index in 3:
		input.call("send_virtual", index, &"staff_2", 1.0)
	input.call("send_virtual", 3, &"move_right", 1.0)
	tap(3, &"staff_1")
	for i in 12:
		await physics_frame
	var action_image: Image = await grab()
	if int(root.get_node("Projectiles").get("drawn")) < 3:
		fail("the three shots are not in the draw batch in shots_and_dash")
		return
	save(action_image, "shots_and_dash")
	for index in 3:
		input.call("send_virtual", index, &"staff_2", 0.0)
	input.call("send_virtual", 3, &"move_right", 0.0)
	tap(1, &"pause")
	await settle()
	var pause_menu: Node = hud.call("get_pause_menu")
	if not pause_menu.call("is_open") or not paused:
		fail("the pause menu is not open, or the game is not paused, in hud_pause_menu")
		return
	await shot("hud_pause_menu")
	# The Settings page, with the Effect slots slider moved a step right and focused.
	var ui_focus: Node = root.get_node("UIFocus")
	ui_focus.call("focus", 1, pause_menu.call("button", "Settings"))
	tap(1, &"accept")
	await settle()
	ui_focus.call("focus", 1, pause_menu.call("button", "EffectSlots"))
	tap(1, &"move_right")
	await settle()
	await snap(Vector2(320.0, 180.0), "hud_pause_settings", Vector2i(110, 70), 3)
	tap(1, &"pause")
	await settle()
	if paused:
		fail("Start again did not close the pause menu")
		return
	var wizard4: Node = flow.call("get_wizard", 3)
	if wizard4 == null:
		fail("player 4 has no wizard")
		return
	# One frame after a cast and after a hit: the muzzle flash in the caster's colour
	# along the aim, the caster squash, and the red vignette toward player 4's corner.
	await settle()
	var wizard1: Node2D = flow.call("get_wizard", 0) as Node2D
	# The HUD stops fading the vignette for this shot: frames are slow on a software
	# renderer and the glow would be gone before it is drawn.
	hud.set_process(false)
	input.call("send_virtual", 0, &"staff_2", 1.0)
	(wizard4 as Actor).health.take(30)
	await physics_frame
	await physics_frame
	input.call("send_virtual", 0, &"staff_2", 0.0)
	var juice_image: Image = await grab()
	if not hud.call("get_vignette").visible:
		fail("the vignette does not show after player 4 is hit in juice_cast_and_hit")
		return
	save(juice_image, "juice_cast_and_hit")
	# The caster and its muzzle flash, cropped and enlarged 4 times (the flash and the
	# squash last a few frames, so two frames are taken after the cast).
	hud.set_process(true)
	_crop_round(juice_image, wizard1, "juice_muzzle_flash_a")
	await physics_frame
	_crop_round(await grab(), wizard1, "juice_muzzle_flash_b")
	await settle()
	# An imp 6 frames (0.1 s) after the killing blow: the death animation.
	var combat: Node = root.get_node("Combat")
	var imps: Array = flow.get("_enemies")
	var imp: Node2D = null
	for candidate: Variant in imps:
		if is_instance_valid(candidate):
			imp = candidate as Node2D
			break
	if imp == null:
		fail("there is no imp to kill in juice_death_animation")
		return
	var imp_at: Transform2D = imp.get_global_transform_with_canvas()
	# Hits name their caster by actor id: the actor wizard 1 opened (actors G3b).
	combat.call("hit", int(wizard1.get("id")), imp, 9999)
	await settle(6)
	save_crop(await grab(), imp_at.origin, "juice_death_animation")
	await settle()
	if not await _enemy_readability(flow, combat, wizard1):
		return
	(wizard4 as Actor).health.take(9999)
	await settle()
	if not (wizard4 as Actor).is_down():
		fail("player 4 is not down in hud_player_four_down")
		return
	await shot("hud_player_four_down")
	# Wizard 3 stands beside the body for a second: the ring shows about half the hold.
	var wizard3: Node2D = flow.call("get_wizard", 2) as Node2D
	wizard3.global_position = wizard4.global_position + Vector2(20.0, 0.0)
	await create_timer(1.0).timeout
	_crop_round(await grab(), wizard4, "revive_ring_half")
	Downed.of(wizard4).revive(0)
	_spread_wizards(flow)
	# Wizard 1 is protected (as on a mid-run join; a dash gives no invulnerability since staffs
	# A6a): translucent with a closing ring while it cannot be hurt.
	wizard1.global_position = Vector2(320.0, 200.0)
	await settle()
	Downed.of(wizard1).protect(1.0)
	await create_timer(0.05).timeout
	var protected_image: Image = await grab()
	if not (wizard1 as Actor).health.is_protected():
		fail("wizard 1 is not invulnerable in protected_invulnerable")
		return
	_crop_round(protected_image, wizard1, "protected_invulnerable")
	await settle()
	var camera: Camera2D = root.get_node("Coop").get("camera") as Camera2D
	if camera == null or camera.zoom.x > 0.51:
		fail("the Coop camera is not at zoom 0.5 in coop_camera_zoom_half")
		return
	print("SHOT: camera zoom %.2f" % camera.zoom.x)
	await shot("staged_zoom_half_wizards_placed_outside_room")
	flow.call("stop_run")
	await create_timer(0.3).timeout


## Enemy readability: an imp half-way through its windup (telegraph line, glowing pose), an
## imp one frame after a hit (hurt pose), and an enemy shot beside a player's shot.
## Returns false after a failure. The imps are held still so the poses can be framed.
func _enemy_readability(flow: Node, combat: Node, wizard: Node2D) -> bool:
	var spare: Array[Node2D] = []
	for candidate: Variant in flow.get("_enemies"):
		if is_instance_valid(candidate) and spare.size() < 2:
			spare.append(candidate as Node2D)
	if spare.size() < 2:
		fail("fewer than two imps are left for enemy_windup")
		return false
	for other: Variant in flow.get("_enemies"):
		if is_instance_valid(other) and not spare.has(other):
			(other as Node2D).process_mode = Node.PROCESS_MODE_DISABLED
	var winding: Node2D = spare[0]
	var hurt: Node2D = spare[1]
	winding.set_physics_process(false)
	hurt.set_physics_process(false)
	wizard.global_position = Vector2(200.0, 180.0)
	winding.global_position = Vector2(200.0, 130.0)
	hurt.global_position = Vector2(470.0, 130.0)
	# The imps are actors (actors G6): the AI and the look are their own nodes. The wizard is the
	# nearest of the other team, so it is the target.
	var winding_ai: Node = winding.get_node("AIController")
	# From chasing, whatever it was doing (a slow frame rate can leave it recovering from an
	# attack), so the 8 steps always end half-way through the windup.
	winding_ai.set("state", 0)
	for i in 8:
		winding.call("step", 0.0625)
	if not winding_ai.call("is_telegraphing"):
		fail("the imp is not winding up in enemy_windup")
		return false
	combat.call("hit", int(wizard.get("id")), hurt, 1)
	hurt.call("step", 0.0)
	if not hurt.get_node("CreatureLook").call("is_hurt"):
		fail("the imp is not hurt in enemy_hurt")
		return false
	# Past the white hit flash, the hurt pose is what is left (the imp is held still, so it stays).
	await settle()
	# Two shots side by side, away from the walls (a shot that starts in a wall is refused).
	var shots: Node = root.get_node("Projectiles")
	var beside: Vector2 = Vector2.INF
	for offset: Vector2 in [Vector2(120.0, 0.0), Vector2(-120.0, 0.0), Vector2(0.0, -70.0), Vector2(0.0, 70.0), Vector2(100.0, 60.0)]:
		var spot: Vector2 = wizard.global_position + offset
		var enemy_slot: int = int(shots.call("spawn", -1, spot + Vector2(0.0, 14.0), Vector2(1.0, 0.0), 5.0, 3.5, 2))
		var player_slot: int = int(shots.call("spawn", int(wizard.get("id")), spot + Vector2(0.0, -14.0), Vector2(1.0, 0.0), 5.0, 4.0))
		if enemy_slot >= 0 and player_slot >= 0:
			beside = offset
			break
	if beside == Vector2.INF:
		fail("no free spot for the two shots in enemy_shot_beside_player_shot")
		return false
	await process_frame
	var image: Image = await grab()
	_crop_round(image, winding, "enemy_windup")
	_crop_round(image, hurt, "enemy_hurt")
	save_crop(image, wizard.get_global_transform_with_canvas().origin + beside, "enemy_shot_beside_player_shot")
	return true


## Put the wizards in the four corners of an area twice the screen and snap the
## Coop camera to fit them, which zooms it out to its limit (0.5). The room is only
## one screen, so its camera limits are widened first, or the zoom would stay at 1.
## Most of the picture is then outside the room; the panels are what is looked at.
func _spread_wizards(flow: Node) -> void:
	var coop: Node = root.get_node("Coop")
	var corners: Array[Vector2] = [Vector2(24, 24), Vector2(1208, 24), Vector2(24, 648), Vector2(1208, 648)]
	for index in 4:
		var wizard: Node2D = flow.call("get_wizard", index) as Node2D
		if wizard != null:
			wizard.global_position = corners[index]
	var camera: Camera2D = coop.get("camera") as Camera2D
	if camera != null:
		camera.limit_left = -64
		camera.limit_top = -64
		camera.limit_right = 1344
		camera.limit_bottom = 784
	coop.call("snap")


## A 4x enlarged crop of `image` around `node` (see `save_crop`).
func _crop_round(image: Image, node: Node2D, name: String) -> void:
	save_crop(image, node.get_global_transform_with_canvas().origin, name)
