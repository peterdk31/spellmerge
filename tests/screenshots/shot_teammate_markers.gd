extends "res://tests/support/screenshot.gd"
## The markers at the picture's edge for teammates out of it (gameplay/feel/teammate_markers.gd;
## owner, 2026-11-13): seat 0 is played here on the keyboard, seats 1-3 are virtual devices, as
## another machine's players are. The three are put far outside the picture (to the right, up and
## left, and down and left), the last one downed; the shot shows an arrow in each one's hat colour
## at the edge towards it, the downed one's with its ring, and a 4x crop of each.

const InputManagerScript := preload("res://core/input/input_manager.gd")


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var feel: Node = root.get_node("Feel")
	input.call("join_as", InputManagerScript.KEYBOARD, 0)
	for index in range(1, 4):
		input.call("add_virtual_device", index)
	flow.call("start_run", 0)
	await settle()
	var far: Array[Vector2] = [Vector2.ZERO, Vector2(4000.0, 200.0), Vector2(-2500.0, -1500.0), Vector2(-900.0, 2400.0)]
	for index in range(1, 4):
		var wizard: Node2D = flow.call("get_wizard", index) as Node2D
		if wizard == null:
			fail("no wizard for seat %d" % index)
			return
		wizard.global_position = far[index]
	var last: Node2D = flow.call("get_wizard", 3) as Node2D
	(last as Actor).health.take(9999)
	await settle(20)
	var markers: Node2D = feel.call("teammate_markers") as Node2D
	if markers == null or int(markers.get("count")) != 3:
		fail("three teammates are out of the picture, so three markers (%s)" % (markers.get("count") if markers != null else "none"))
		return
	await shot("teammate_markers")
	var image: Image = await grab()
	for at in 3:
		save_crop(image, on_screen(markers.call("position_of", at) as Vector2), "teammate_marker_seat_%d" % int(markers.call("seat_of", at)), Vector2i(24, 24))
