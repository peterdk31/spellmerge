extends "res://tests/support/screenshot.gd"
## The poof (living staffs H4): four players in the arena each press another staff button; a shot
## of the arena before, then a 4x crop of player 2 every frame for 12 frames (0.2 s): the cloud
## swelling, the body and face changing at its biggest, the cloud dotting away.


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel"]):
		return
	settle_frames = 30
	# Feel ages its effects by the wall clock; a software-rendered frame is far longer than 1/60 s,
	# so the 0.18 s poof would be gone in a frame or two. Frame time instead (--fixed-fps 60).
	root.get_node("Feel").set("drive_engine", false)
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	for index in 4:
		input.call("add_virtual_device", index)
	flow.call("start_run", 0)
	var aims: Array[Vector2] = [Vector2.RIGHT, Vector2(1, -1).normalized(), Vector2.LEFT, Vector2.UP]
	for index in 4:
		input.call("send_virtual_aim", index, aims[index])
	await shot("poof_before")
	var wizard: Node2D = get_first_node_in_group(&"wizards") as Node2D
	if wizard == null:
		fail("no wizard in the arena")
		return
	var at: Vector2 = wizard.global_position + Vector2(0.0, -14.0)
	save_crop(await grab(), on_screen(at), "poof_before_crop", Vector2i(32, 24))
	# RT, LT, LB, RT: each player swaps to another staff at once.
	var buttons: Array[StringName] = [&"staff_2", &"staff_4", &"staff_3", &"staff_2"]
	for index in 4:
		tap(index, buttons[index])
	var second: Node2D = get_nodes_in_group(&"wizards")[1] as Node2D
	var where: Vector2 = on_screen(second.global_position + Vector2(0.0, -14.0))
	for i in 12:
		await physics_frame
		await process_frame
		save_crop(await grab(), where, "poof_frame_%02d" % i, Vector2i(24, 20))
