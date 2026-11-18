extends "res://tests/support/screenshot.gd"
## Screenshots of a world that notices (docs/milestones/atmosphere.md, E: the world's stirs,
## gameplay/feel/stirs.gd): filmstrips of FRAMES frames GAP apart, each a close crop at ZOOM.
##
## Shots: `reactions_candle`, a shot passing just under a crypt candle (its light ducks and leans
## away, then eases back) and `reactions_candle_still`, the same with the room's lights' stirs held
## at rest (what it adds); `reactions_shaft`, shots through a light shaft's falling dust (dragged
## along their way, drifting back); `reactions_grass` and `reactions_grass_still`, a blast in the
## hub's grass (the tufts pushed out as its wave passes and swaying back), and the same blast with
## the stirs held at rest. The HUD is hidden.

const RegistryScript := preload("res://core/registry/registry.gd")
const StirsScript := preload("res://gameplay/feel/stirs.gd")
const SpellLightScript := preload("res://gameplay/feel/spell_light.gd")
const SpotStirsScript := preload("res://gameplay/feel/spot_stirs.gd")

const ROOM: StringName = &"arena_02"
## Frames in a strip, frames between two, and the zoom of the crops.
const FRAMES: int = 6
const GAP: int = 3
const ZOOM: int = 4
## How far under the candle the shot passes (px) and from how far to its left it starts, its
## speed (px/s), and the crop round the candle (half its size).
const UNDER: float = 7.0
const FROM_LEFT: float = 70.0
const SPEED: float = 220.0
const CANDLE_CROP: Vector2i = Vector2i(40, 26)
## Where the shots cross the shaft (up from its foot), and the crop round it.
const SHAFT_UP: float = 60.0
const SHAFT_CROP: Vector2i = Vector2i(40, 40)
const GRASS_CROP: Vector2i = Vector2i(48, 30)
const BLAST_RADIUS: float = 16.0


func take() -> void:
	if not need(["PlayerInput", "Flow", "Registry", "Feel", "Events", "Projectiles"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var feel: Node = root.get_node("Feel")
	var registry := root.get_node("Registry") as RegistryScript
	var room := registry.get_resource(&"rooms", ROOM) as RoomBase
	if room == null:
		fail("no room %s" % ROOM)
		return
	input.call("add_virtual_device", 0)
	flow.set("run_id_to_play", PinnedRun.pin(registry, room))
	if not flow.call("start_run", 0):
		fail("the run of %s did not start" % ROOM)
		return
	var hud := root.get_node_or_null("Hud") as CanvasLayer
	if hud != null:
		hud.visible = false
	feel.call("set_spell_light", true)
	await settle(40)
	var wizard := flow.call("get_wizard", 0) as Node2D
	if wizard == null:
		fail("no wizard")
		return
	var spectacle: Node = feel.call("spectacle")
	var candle: Node2D = _candle_nearest(wizard.global_position)
	if candle == null:
		fail("no candle in %s" % ROOM)
		return
	# The wizard out of the crop, below and to the left.
	wizard.global_position = candle.global_position + Vector2(-FROM_LEFT - 30.0, 50.0)
	await settle(30)
	await _candle_strip(candle, wizard, "reactions_candle")
	await settle(60)
	spectacle.set("spot_stirs", _Held.new())
	await _candle_strip(candle, wizard, "reactions_candle_still")
	spectacle.set("spot_stirs", SpotStirsScript.new())
	var beam: Node2D = _beam()
	if beam == null:
		fail("no light shaft in %s" % ROOM)
		return
	wizard.global_position = beam.global_position + Vector2(-110.0, 30.0)
	await settle(60)
	var through: Vector2 = beam.global_position + Vector2(0.0, -SHAFT_UP)
	var frames: Array[Image] = []
	for k in 4:
		_fire(wizard, through + Vector2(-36.0 - 12.0 * float(k), float(k % 2) * 6.0 - 3.0), Vector2.RIGHT)
	await settle(3)
	for frame in FRAMES:
		frames.append(crop_round(await grab(), on_screen(through), SHAFT_CROP))
		await settle(GAP - 1)
	_save_strip(frames, "reactions_shaft")
	await _hub(flow, feel, spectacle)


## A shot from left of `candle` passing UNDER px below it; FRAMES frames GAP apart from as it nears.
func _candle_strip(candle: Node2D, wizard: Node2D, shot_name: String) -> void:
	_fire(wizard, candle.global_position + Vector2(-FROM_LEFT, UNDER), Vector2.RIGHT)
	# Until it is a few frames from the candle.
	await settle(int((FROM_LEFT - 12.0) / SPEED * 60.0))
	var frames: Array[Image] = []
	for frame in FRAMES:
		frames.append(crop_round(await grab(), on_screen(candle.global_position + Vector2(0.0, 6.0)), CANDLE_CROP))
		await settle(GAP - 1)
	_save_strip(frames, shot_name)


func _fire(wizard: Node2D, from: Vector2, way: Vector2) -> void:
	var shots: Node = root.get_node("Projectiles")
	shots.call("spawn", int(wizard.get("id")), from, way * SPEED, 3.0, 4.0, 0)


## The hub's grass and a blast in it, with the stirs and with them held still.
func _hub(flow: Node, feel: Node, spectacle: Node) -> void:
	flow.call("stop_run")
	root.get_node("Events").emit_signal("hub_requested", 0)
	if not await wait_for(func() -> bool: return flow.get("mode") == &"hub" and flow.call("get_wizard", 0) != null, 600):
		fail("the hub did not start")
		return
	await settle(90)
	var hud := root.get_node_or_null("Hud") as CanvasLayer
	if hud != null:
		hud.visible = false
	var cover: Node = feel.call("cover")
	var at: Vector2 = _grass_near(cover, root.get_canvas_transform().affine_inverse() * (root.get_visible_rect().size * 0.5))
	if not at.is_finite():
		fail("no grass in view in the hub")
		return
	await _blast_strip(at, "reactions_grass")
	await settle(90)
	var real: StirsScript = spectacle.get("stirs")
	spectacle.set("stirs", StirsScript.new())
	await settle(2)
	var still: StirsScript = spectacle.get("stirs")
	await _blast_strip(at, "reactions_grass_still", still)
	spectacle.set("stirs", real)


func _blast_strip(at: Vector2, shot_name: String, held: StirsScript = null) -> void:
	var events: Node = root.get_node("Events")
	events.emit_signal(&"cue_shown", 0, &"blast", at, Vector2.ZERO, BLAST_RADIUS, Color.WHITE, 0)
	var frames: Array[Image] = []
	for frame in FRAMES:
		if held != null:
			held.clear()
		frames.append(crop_round(await grab(), on_screen(at), GRASS_CROP))
		await settle(GAP - 1)
	_save_strip(frames, shot_name)


## The frames side by side, a pixel of black between, at ZOOM.
func _save_strip(frames: Array[Image], shot_name: String) -> void:
	if frames.is_empty():
		return
	var w: int = frames[0].get_width()
	var h: int = frames[0].get_height()
	var strip := Image.create_empty((w + 1) * frames.size() - 1, h, false, frames[0].get_format())
	strip.fill(Color.BLACK)
	for k in frames.size():
		strip.blit_rect(frames[k], Rect2i(Vector2i.ZERO, Vector2i(w, h)), Vector2i(k * (w + 1), 0))
	strip.resize(strip.get_width() * ZOOM, strip.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	save(strip, shot_name)


## A covered spot of the hub's cover nearest `to` (INF: none).
func _grass_near(cover: Node, to: Vector2) -> Vector2:
	var layout: CoverLayout = cover.get("layout")
	if layout == null:
		return Vector2.INF
	var best: Vector2 = Vector2.INF
	for cell in layout.cells.size():
		if layout.cells[cell] == 0:
			continue
		var middle := (Vector2(cell % layout.columns, cell / layout.columns) + Vector2(0.5, 0.5)) * float(CoverLayout.CELL)
		if best == Vector2.INF or middle.distance_to(to) < best.distance_to(to):
			best = middle
	return best


## The room's candle (a light spot not a shaft's) nearest `to`, or null.
func _candle_nearest(to: Vector2) -> Node2D:
	var best: Node2D = null
	for node: Node in get_nodes_in_group(LightSpot.GROUP):
		var spot := node as Node2D
		if spot == null or spot.get_parent().name == &"Beam":
			continue
		if best == null or spot.global_position.distance_to(to) < best.global_position.distance_to(to):
			best = spot
	return best


func _beam() -> Node2D:
	for node: Node in get_nodes_in_group(LightSpot.GROUP):
		if node.get_parent() != null and node.get_parent().name == &"Beam":
			return node.get_parent() as Node2D
	return null


## The room's lights' stirs held at rest (for the comparison strip).
class _Held:
	extends "res://gameplay/feel/spot_stirs.gd"

	func step(_light: SpellLightScript, _stirs: StirsScript, _now: float) -> void:
		pass
