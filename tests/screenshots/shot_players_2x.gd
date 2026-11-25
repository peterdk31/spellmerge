extends "res://tests/support/screenshot.gd"
## The players' staffs at 2x detail (ART1, docs/STYLE.md, "The picture and the art's detail"): the
## four players in a run, in a row, each showing one head (its LT button given that staff), in
## turn every head (curl, star, moon, crystal, the dev cog) in all four player colours, aiming up
## and to the right with the shared face over it, at the resting zoom 1.
##
## Shots: `players_2x_<head>` (the room) and `players_2x_<head>_crop` (the four at 4x); then
## `players_2x_mixed` (seats 1 to 4 on curl, star, moon, crystal) with its crop, and its crop
## zoomed out to 0.8 as the camera holds a spread party (`players_2x_zoom_08_crop`).

const HEADS: Array[StaffBase] = [
	preload("res://content/wizard/staffs/curl/curl.tres"),
	preload("res://content/wizard/staffs/star/star.tres"),
	preload("res://content/wizard/staffs/moon/moon.tres"),
	preload("res://content/wizard/staffs/crystal/crystal.tres"),
	preload("res://content/wizard/staffs/dev/dev.tres"),
]
## The LT button (`staff_4`): the button each wizard is given the head on.
const BUTTON: int = 3
const GAP: float = 30.0


func take() -> void:
	if not need(["PlayerInput", "Flow", "Spells", "Feel"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	for index in 4:
		input.call("add_virtual_device", index)
	flow.call("start_run", 0)
	await settle()
	var wizards: Array[Actor] = []
	for seat in 4:
		var wizard: Actor = flow.call("get_wizard", seat) as Actor
		if wizard == null:
			fail("there is no wizard for player %d" % (seat + 1))
			return
		wizards.append(wizard)
	var middle: Vector2 = wizards[0].global_position
	for head in HEADS:
		await _show(wizards, [head, head, head, head] as Array[StaffBase], middle)
		await _shoot(middle, "players_2x_%s" % head.id)
	await _show(wizards, HEADS.slice(0, 4), middle)
	var image: Image = await _shoot(middle, "players_2x_mixed")
	var camera: Camera2D = root.get_viewport().get_camera_2d()
	if camera == null or image == null:
		fail("no camera for players_2x_zoom_08")
		return
	var feel: Node = root.get_node("Feel")
	feel.set_process(false)
	camera.zoom = Vector2.ONE * (0.8 * float(PictureGrid.scale_in(root)))
	camera.position = middle
	await settle(2)
	image = await grab()
	feel.set_process(true)
	save_crop(image, on_screen(middle + Vector2(0.0, -14.0)), "players_2x_zoom_08_crop", Vector2i(70, 24), 4)


## The four in a row about `middle`, seat `i` showing `heads[i]` on its LT button, aiming up-right.
func _show(wizards: Array[Actor], heads: Array[StaffBase], middle: Vector2) -> void:
	var spells: Node = root.get_node("Spells")
	var input: Node = root.get_node("PlayerInput")
	var cards: Array[StringName] = []
	for seat in wizards.size():
		var wizard: Actor = wizards[seat]
		spells.call("install_staff", wizard.id, BUTTON, spells.call("compile_staff", cards, heads[seat]))
		wizard.global_position = middle + Vector2((float(seat) - 1.5) * GAP, 0.0)
		tap(seat, &"staff_4")
		input.call("send_virtual_aim", seat, Vector2(1, -1).normalized())
	await settle()
	for seat in wizards.size():
		wizards[seat].global_position = middle + Vector2((float(seat) - 1.5) * GAP, 0.0)
	await settle(20)


func _shoot(middle: Vector2, shot_name: String) -> Image:
	var image: Image = await grab()
	save(image, shot_name)
	save_crop(image, on_screen(middle + Vector2(0.0, -14.0)), shot_name + "_crop", Vector2i(70, 24), 4)
	return image
