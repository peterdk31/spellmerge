extends "res://tests/support/screenshot.gd"
## An enemy spawning as the game draws it (enemy spawning EA2, docs/milestones/enemy-spawning.md,
## "The look"; gameplay/feel/spawn_look.gd): the pinned crypt arena started, and the lowest of its
## enemies cropped at 3x as it spawns in, left to right: the mark growing on the floor, the body rising
## out of it cut at its feet, the mark closing, the body standing. `spawning` is the filmstrip; each
## frame's share of the spawn is printed.

## The shares of the spawn the strip shows (the last, past 1, standing).
const SHARES: Array[float] = [0.05, 0.15, 0.3, 0.45, 0.6, 0.75, 0.88, 0.95, 1.2]
## Half the crop round the body's feet, in screen pixels, and how much bigger the strip is drawn.
const HALF: Vector2i = Vector2i(24, 32)
const ZOOM: int = 3


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	input.call("add_virtual_device", 0)
	flow.call("start_run", 0)
	var enemies: Array = flow.get(&"_enemies")
	if enemies.is_empty() or not (enemies[0] as Actor).is_spawning():
		fail("the room's first enemy does not spawn")
		return
	# The lowest on the screen: clear of the HUD's corner panel at the top.
	var body: Actor = enemies[0] as Actor
	for enemy: Node in enemies:
		if (enemy as Actor).global_position.y > body.global_position.y:
			body = enemy as Actor
	var at: Vector2 = body.global_position + Vector2(0.0, -12.0)
	var frames: Array[Image] = []
	for share: float in SHARES:
		while is_instance_valid(body) and body.spawn_share() < share and body.is_spawning():
			await physics_frame
		if not is_instance_valid(body):
			fail("the enemy went before it stood")
			return
		var image: Image = await grab()
		print("SPAWN: share %.2f (asked %.2f)" % [body.spawn_share(), share])
		var crop: Image = crop_round(image, on_screen(at), HALF)
		crop.resize(crop.get_width() * ZOOM, crop.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
		frames.append(crop)
	var width: int = frames[0].get_width()
	var sheet := Image.create(width * frames.size() + 4 * (frames.size() - 1), frames[0].get_height(), false, frames[0].get_format())
	sheet.fill(Color.BLACK)
	for n in frames.size():
		sheet.blit_rect(frames[n], Rect2i(Vector2i.ZERO, frames[n].get_size()), Vector2i(n * (width + 4), 0))
	save(sheet, "spawning")
