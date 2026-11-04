extends "res://tests/support/screenshot.gd"
## The staff swap's look (S6, item 9; docs/milestones/spell-spectacle-2.md): the wizard in the
## sandbox puts its fire staff on show once for each look (no cast), and each is shown as a
## filmstrip of the frames after it (FRAMES: the swap of the body and face at 35% of 0.18 s, then
## what lingers), a row a look, at 1x and at 4x: the old poof (living staffs H4, drawn as its code
## drew it), then the cue files `staff_swap` (the live one), `staff_swap_b` and `staff_swap_c`, for
## the owner to pick. Each look covers the whole staff, grip to tip (the cue's line). Each is put in
## Feel's place for `staff_swap` while it plays; nothing else changes. Rows top to bottom: ROWS.
## Two staff angles (AIMS): `staff_swap_{1x,4x}` aimed up and right, `staff_swap_upright_{1x,4x}`
## nearly straight up; also each row alone at 4x (`staff_swap[_upright]_<row>_4x`).

## The frames after the press each column shows (at 60 a second).
const FRAMES: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 20, 28]
const ROWS: Array[StringName] = [&"old", &"staff_swap", &"staff_swap_b", &"staff_swap_c"]
## Half the crop round the staff, in screen pixels.
const HALF: Vector2i = Vector2i(26, 22)
const GAP: int = 2
## Where the wizard stands (an empty patch of the sandbox's floor), and the staff each look puts on
## show (the fire bolt).
const SPOT: Vector2 = Vector2(96.0, 250.0)
const SHOWN: int = 1
## The aims the sheets are taken at, and their names' endings.
const AIMS: Array[Vector2] = [Vector2(1.0, -1.0), Vector2(0.12, -1.0)]
const ENDINGS: Array[String] = ["", "_upright"]


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel"]):
		return
	settle_frames = 30
	# Feel ages its effects by the wall clock; a software-rendered frame is far longer than 1/60 s,
	# so frame time instead (--fixed-fps 60), as shot_poof.gd does.
	var feel: Node = root.get_node("Feel")
	feel.set("drive_engine", false)
	var input: Node = root.get_node("PlayerInput")
	input.call("add_virtual_device", 0)
	# The sandbox: no waves (the arena's enemies' shots light the room), its staffs built
	# (Flow.SANDBOX_START_CARDS: staff 1 is the fire bolt, its embers the cards' motes).
	root.get_node("Events").emit_signal("sandbox_requested", 0)
	if not await wait_for(func() -> bool: return get_first_node_in_group(&"wizards") != null, 600):
		fail("the sandbox did not start")
		return
	var wizard: Node2D = get_first_node_in_group(&"wizards") as Node2D
	wizard.global_position = SPOT
	await settle()
	var cache: Dictionary = feel.get("_cue_cache") as Dictionary
	var looks: Dictionary = {}
	# The old poof is drawn as the old code drew it (below); the cue plays nothing meanwhile.
	var nothing := CueBase.new()
	nothing.id = &"staff_swap"
	looks[&"old"] = nothing
	for id: StringName in ROWS:
		if id != &"old":
			var cue: CueBase = feel.call("cue_of", id) as CueBase
			if cue == null:
				fail("no cue " + String(id))
				return
			looks[id] = cue
	var caster: Object = wizard.get("caster") as Object
	for a in AIMS.size():
		var ending: String = ENDINGS[a]
		input.call("send_virtual_aim", 0, AIMS[a].normalized())
		var cell: Vector2i = HALF * 2
		var sheet_1x := Image.create((cell.x + GAP) * FRAMES.size(), (cell.y + GAP) * ROWS.size(), false, Image.FORMAT_RGBA8)
		sheet_1x.fill(Color(0.05, 0.05, 0.07))
		for row in ROWS.size():
			# Back to the dash staff (the look playing then is the last one's), and let it fade.
			caster.call("_show", 0)
			for i in 60:
				await physics_frame
			cache[&"staff_swap"] = looks[ROWS[row]]
			# Put the staff on show as a press does (`Caster._show`: the body and face swap, `staff_shown`),
			# without the cast a press also makes, whose flash and light would hide the look.
			caster.call("_show", SHOWN)
			if ROWS[row] == &"old":
				_old_poof(feel, wizard as Actor)
			var strip := Image.create((cell.x + GAP) * FRAMES.size(), cell.y, false, Image.FORMAT_RGBA8)
			strip.fill(Color(0.05, 0.05, 0.07))
			var frame: int = 0
			for column in FRAMES.size():
				while frame <= FRAMES[column]:
					await physics_frame
					await process_frame
					frame += 1
				var image: Image = await grab()
				var crop: Image = _crop(image, on_screen(wizard.global_position + Vector2(4.0, -14.0)))
				strip.blit_rect(crop, Rect2i(Vector2i.ZERO, cell), Vector2i(column * (cell.x + GAP), 0))
				sheet_1x.blit_rect(crop, Rect2i(Vector2i.ZERO, cell), Vector2i(column * (cell.x + GAP), row * (cell.y + GAP)))
			strip.resize(strip.get_width() * 4, strip.get_height() * 4, Image.INTERPOLATE_NEAREST)
			save(strip, "staff_swap%s_%s_4x" % [ending, ROWS[row]])
		save(sheet_1x, "staff_swap%s_1x" % ending)
		var sheet_4x: Image = sheet_1x.duplicate() as Image
		sheet_4x.resize(sheet_4x.get_width() * 4, sheet_4x.get_height() * 4, Image.INTERPOLATE_NEAREST)
		save(sheet_4x, "staff_swap%s_4x" % ending)
	cache.erase(&"staff_swap")


## HALF x 2 screen pixels of `image` round the screen point `at`, at one image pixel a screen pixel.
func _crop(image: Image, at: Vector2) -> Image:
	var scale_to_image: Vector2 = Vector2(image.get_size()) / Vector2(root.get_visible_rect().size)
	var middle := Vector2i(at * scale_to_image)
	var half := Vector2i(Vector2(HALF) * scale_to_image)
	var corner: Vector2i = (middle - half).clamp(Vector2i.ZERO, image.get_size() - half * 2)
	var crop: Image = image.get_region(Rect2i(corner, half * 2))
	if crop.get_size() != HALF * 2:
		crop.resize(HALF.x * 2, HALF.y * 2, Image.INTERPOLATE_NEAREST)
	crop.convert(Image.FORMAT_RGBA8)
	return crop


## The poof as it was before S6 item 9 (living staffs H4, Feel's `_on_staff_shown`): a puff with the
## POOF look along the staff, its middle 4 px from the hand along the aim, 0.18 s, zoom 2, in the
## actor's ramp, following the body.
func _old_poof(feel: Node, body: Actor) -> void:
	var offset: Vector2 = body.hand_offset + body.aim * 4.0
	var ramp: int = int(feel.call("_ramp_of", body.id))
	var slot: int = int(feel.call("show_effect", feel.get("KIND_PUFF"), body.global_position + offset, body.aim, Color.WHITE, ramp, feel.get("POOF"), 2, 0.18, 0.0, body))
	if slot >= 0:
		var offsets: PackedVector2Array = feel.get("_effect_offset") as PackedVector2Array
		offsets[slot] = offset
		feel.set("_effect_offset", offsets)
