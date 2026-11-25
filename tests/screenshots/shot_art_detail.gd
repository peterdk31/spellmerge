extends "res://tests/support/screenshot.gd"
## The 1280 x 720 picture and mixed art (ART0, docs/STYLE.md, "The picture and the art's detail"):
## the curl, redrawn at 2x detail (its head and the Optimist's face, drawn at half size), beside the
## star, still 32-unit art drawn twice as big, in play; the room around them (enemies, props, floor:
## today's art) with the curl in it, at the cameras' resting zoom, 1; and zoomed out to 0.8, as the
## camera holds a spread party.
##
## Shots: `art_detail_wizards` (two wizards, the curl on seat 1's left and the star on seat 2's
## right, both aiming up and right) with a crop of the two at 4x (`art_detail_wizards_crop`) and of
## each; `art_detail_mixed_room` (a fight: the curl among the room's enemies and props) and its crop,
## at the resting zoom 1 (two picture pixels a world pixel, every 32-unit art pixel a 2x2 block,
## every 2x art pixel one); `art_detail_zoom_08` and its crop, zoomed out to 0.8 as for a spread party
## (1.6 picture pixels a world pixel; it was the resting zoom until 2026-11-25).


## The zoom shown zoomed out (PartyCamera's, between MIN_ZOOM and MAX_ZOOM).
const ZOOMED_OUT: float = 0.8


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	for index in 2:
		input.call("add_virtual_device", index)
	flow.call("start_run", 0)
	await settle()
	var wizards: Array[Node2D] = _wizards()
	if wizards.size() != 2:
		fail("two wizards were not in the run (%d)" % wizards.size())
		return
	# Seat 2 shows its RT staff, the star (32-unit art); seat 1 its RB staff, the curl (2x).
	tap(1, &"staff_2")
	for index in 2:
		input.call("send_virtual_aim", index, Vector2(1, -1).normalized())
	await settle()
	var curl := wizards[0].get_node(^"Sprite") as Sprite2D
	var star := wizards[1].get_node(^"Sprite") as Sprite2D
	if ArtDetail.of(curl.texture) != 2 or ArtDetail.of(star.texture) != 1:
		fail("the curl (2x) and the star (1x) are not on show (%d, %d)" % [ArtDetail.of(curl.texture), ArtDetail.of(star.texture)])
		return
	# Side by side, a little apart, in the room's middle.
	var middle: Vector2 = (wizards[0].global_position + wizards[1].global_position) * 0.5
	wizards[0].global_position = middle + Vector2(-18.0, 0.0)
	wizards[1].global_position = middle + Vector2(18.0, 0.0)
	await settle()
	var image: Image = await grab()
	save(image, "art_detail_wizards")
	save_crop(image, on_screen(middle + Vector2(0.0, -14.0)), "art_detail_wizards_crop", Vector2i(48, 28), 4)
	save_crop(image, on_screen(wizards[0].global_position + Vector2(0.0, -14.0)), "art_detail_curl_crop", Vector2i(20, 20), 6)
	save_crop(image, on_screen(wizards[1].global_position + Vector2(0.0, -14.0)), "art_detail_star_crop", Vector2i(20, 20), 6)
	# A fight: the room's first wave about the wizards.
	var came: bool = await wait_for(func() -> bool: return (flow.get("_enemies") as Array).size() > 0, 600)
	if not came:
		fail("no enemy came into the room for art_detail_mixed_room")
		return
	await settle(90)
	image = await grab()
	save(image, "art_detail_mixed_room")
	save_crop(image, on_screen(wizards[0].global_position + Vector2(0.0, -14.0)), "art_detail_mixed_room_crop", Vector2i(80, 45), 4)
	# Zoomed out to 0.8, as the camera holds a spread party (the resting zoom until 2026-11-25): Feel
	# held for the frame, as its party camera eases the zoom back every frame. 1.6 picture pixels a
	# world pixel: every 32-unit art pixel one or two, a 2x art pixel one in five left out.
	var camera: Camera2D = root.get_viewport().get_camera_2d()
	if camera == null:
		fail("no camera for art_detail_zoom_08")
		return
	print("SHOT: the camera rests at zoom %.2f of the picture here" % camera.zoom.x)
	var feel: Node = root.get_node("Feel")
	feel.set_process(false)
	camera.zoom = Vector2.ONE * (ZOOMED_OUT * float(PictureGrid.scale_in(root)))
	camera.position = wizards[0].global_position
	await settle(2)
	image = await grab()
	feel.set_process(true)
	save(image, "art_detail_zoom_08")
	save_crop(image, on_screen(wizards[0].global_position + Vector2(0.0, -14.0)), "art_detail_zoom_08_crop", Vector2i(40, 24), 4)

## The wizards, seat 1's first.
func _wizards() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for node: Node in root.get_tree().get_nodes_in_group(&"wizards"):
		if node is Node2D:
			out.append(node as Node2D)
	out.sort_custom(func(a: Node2D, b: Node2D) -> bool: return int(a.get_node(^"PlayerController").get("seat")) < int(b.get_node(^"PlayerController").get("seat")))
	return out
