extends "res://tests/support/screenshot.gd"
## A wizard walking through ground cover (ground cover GC4, docs/milestones/ground-cover.md, rule 6,
## decision 4): the hub's own grass (content/cover/hub_grass, its art and trampled frames) where it
## grows in the hub, which has no enemies to fight over the pictures, the first wizard walked along
## a line through it, the tufts bending away from it and lying trampled behind it, then springing
## back. Feel's look only.
##
## Shots: `cover_trample_4x`, a strip of the same patch of floor as the wizard walks through it and
## after (FRAMES: the frame of each picture, from the walk's start), at 4×.

const FeelScript := preload("res://gameplay/feel/feel.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const CoverScript := preload("res://gameplay/feel/cover.gd")

## The walk: along `RUN` covered cells side by side (the run nearest the first player spawn), a
## pixel a frame.
const RUN: int = 6
const WALK := Vector2(96.0, 0.0)
## The frames pictured: through the walk, then while the trampled grass springs back.
const FRAMES: PackedInt32Array = [0, 24, 48, 72, 96, 240, 420, 560, 700]
## Half the patch pictured round the walk's middle, and the gap between pictures.
const HALF := Vector2i(64, 24)
const GAP: int = 2


func take() -> void:
	if not need(["PlayerInput", "Flow", "Feel", "Registry", "Events"]):
		return
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var feel := root.get_node("Feel") as FeelScript
	var hub := (root.get_node("Registry") as RegistryScript).get_resource(&"rooms", &"hub") as RoomBase
	if hub == null:
		fail("no hub room")
		return
	input.call("add_virtual_device", 0)
	root.get_node("Events").emit_signal("hub_requested", 0)
	if not await wait_for(func() -> bool: return flow.get("mode") == &"hub" and flow.call("get_wizard", 0) != null, 600):
		fail("the hub did not start")
		return
	var wizard := flow.call("get_wizard", 0) as Node2D
	var spawns: PackedVector2Array = hub.places().player_spawns
	var from: Vector2 = _walk_start(feel.cover().layout, spawns[0] if not spawns.is_empty() else Vector2(320, 180))
	if not from.is_finite():
		fail("the room has no %d covered cells side by side" % RUN)
		return
	var middle: Vector2 = from + WALK * 0.5
	wizard.global_position = from
	await settle()
	var cell: Vector2i = HALF * 2
	var strip := Image.create((cell.x + GAP) * FRAMES.size(), cell.y, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.05, 0.05, 0.07))
	var frame: int = 0
	for column in FRAMES.size():
		while frame < FRAMES[column]:
			frame += 1
			wizard.global_position = from + WALK * minf(float(frame) / WALK.length(), 1.0)
			await physics_frame
			await process_frame
		var image: Image = await grab()
		var crop: Image = crop_round(image, on_screen(middle), HALF)
		strip.blit_rect(crop, Rect2i(Vector2i.ZERO, cell), Vector2i(column * (cell.x + GAP), 0))
	var walked: float = feel.cover().walked_at(feel.cover().layout.cell_of(middle))
	if walked <= CoverScript.NEVER:
		fail("the wizard trampled nothing")
		return
	strip.resize(strip.get_width() * 4, strip.get_height() * 4, Image.INTERPOLATE_NEAREST)
	save(strip, "cover_trample_4x")


## The start of the run of `RUN` covered cells side by side nearest `near` (the middle of its
## first cell's left side); `Vector2.INF` for none.
func _walk_start(layout: CoverLayout, near: Vector2) -> Vector2:
	var best: Vector2 = Vector2.INF
	if layout == null:
		return best
	for row in layout.rows:
		for column in layout.columns - RUN + 1:
			var covered: bool = true
			for k in RUN:
				covered = covered and layout.cells[row * layout.columns + column + k] != 0
			if not covered:
				continue
			var start := Vector2(float(column * CoverLayout.CELL), (float(row) + 0.5) * float(CoverLayout.CELL))
			if not best.is_finite() or (start + WALK * 0.5).distance_to(near) < (best + WALK * 0.5).distance_to(near):
				best = start
	return best
