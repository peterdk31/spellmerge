extends "res://tests/support/screenshot.gd"
## Enemies spawning as the game draws them (enemy spawning EA2, docs/milestones/enemy-spawning.md,
## "The look"; spawn styles AS3, docs/milestones/spawn-styles.md; gameplay/feel/spawn_look.gd): the
## pinned crypt arena started, and two bodies cropped at 3x as they spawn in, left to right.
##
## - `spawning`: the lowest of the room's enemies in `rise`: the mark growing on the floor, the body
##   rising out of it cut at its feet, the mark closing, the body standing.
## - `spawning_materialize`: a storm fork (its own style, `materialize`) stood beside the wizard, a
##   frame every `MATERIALIZE_EVERY` from the pad's first look to standing: the pad of light with its
##   rim running round, the scan line sweeping up with the rows interlaced behind it and the glitch,
##   the line going out and the body whole. Two rows of frames.
##
## Each frame's share of the spawn is printed.

## The shares of the spawn the `rise` strip shows (the last, past 1, standing).
const SHARES: Array[float] = [0.05, 0.15, 0.3, 0.45, 0.6, 0.75, 0.88, 0.95, 1.2]
## Every how many frames the materialize strip takes one, and how many frames a row of it holds.
const MATERIALIZE_EVERY: int = 3
const MATERIALIZE_ROW: int = 11
## Where the storm fork stands from the wizard.
const STORM_FORK_AT: Vector2 = Vector2(56.0, 8.0)
## Half the crop round the body's feet, in screen pixels, and how much bigger the strip is drawn.
const HALF: Vector2i = Vector2i(24, 32)
const ZOOM: int = 3


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel", "Registry"]):
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
	var frames: Array[Image] = []
	for share: float in SHARES:
		while is_instance_valid(body) and body.spawn_share() < share and body.is_spawning():
			await physics_frame
		if not is_instance_valid(body):
			fail("the enemy went before it stood")
			return
		frames.append(await _crop(body, "SPAWN"))
	save(_sheet(frames, frames.size()), "spawning")
	await _materialize(flow)


## A storm fork stood beside the wizard in the style Flow picks for it (its own: `materialize`), a
## frame every `MATERIALIZE_EVERY` from its pad's first look to a few frames after it stands.
func _materialize(flow: Node) -> void:
	var data := root.get_node("Registry").call("get_resource", &"enemies", &"storm_fork") as EnemyBase
	var wizards: Array = flow.get(&"_wizards")
	if data == null or wizards.is_empty():
		fail("no storm fork or no wizard")
		return
	var style: SpawnStyle = flow.call("spawn_style_for", data)
	if style.motion != &"materialize":
		fail("the storm fork spawns in %s, not materialize" % style.id)
		return
	var body := RoomContents.make_body(data) as Actor
	body.position = (wizards[0] as Node2D).global_position + STORM_FORK_AT
	body.spawn(style.seconds, style.id)
	(wizards[0] as Node2D).get_parent().add_child(body)
	var frames: Array[Image] = []
	var after: int = 0
	while after < 1:
		if not is_instance_valid(body):
			fail("the storm fork went before it stood")
			return
		if not body.is_spawning():
			after += 1
		frames.append(await _crop(body, "MATERIALIZE"))
		for n in MATERIALIZE_EVERY - 1:
			await physics_frame
	save(_sheet(frames, MATERIALIZE_ROW), "spawning_materialize")
	body.queue_free()


## The screen round `body`'s feet this frame, at `ZOOM`, its share printed.
func _crop(body: Actor, what: String) -> Image:
	var image: Image = await grab()
	print("%s: share %.2f" % [what, body.spawn_share()])
	var crop: Image = crop_round(image, on_screen(body.global_position + Vector2(0.0, -12.0)), HALF)
	crop.resize(crop.get_width() * ZOOM, crop.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	return crop


## `frames` side by side, `across` a row, 4 px apart on black.
static func _sheet(frames: Array[Image], across: int) -> Image:
	var width: int = frames[0].get_width()
	var height: int = frames[0].get_height()
	var columns: int = mini(across, frames.size())
	var rows: int = ceili(float(frames.size()) / float(columns))
	var sheet := Image.create(width * columns + 4 * (columns - 1), height * rows + 4 * (rows - 1), false, frames[0].get_format())
	sheet.fill(Color.BLACK)
	for n in frames.size():
		sheet.blit_rect(frames[n], Rect2i(Vector2i.ZERO, frames[n].get_size()), Vector2i((n % columns) * (width + 4), (n / columns) * (height + 4)))
	return sheet
