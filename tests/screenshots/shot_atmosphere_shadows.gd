extends "res://tests/support/screenshot.gd"
## Screenshots of the crypt's shadows (docs/milestones/atmosphere.md, C): light stopped by the
## pillars and the standing walls (`light_blockers.gd`, the grid's blockers) and the bodies'
## short hard shadows cast away from the light near them (`body_shadows.gd`), in a crypt room in a
## fight: four wizards casting up into it among its pillars.
##
## Shots: `shadows_fight` with spell light on; `shadows_fight_plain` the same with spell light off
## (no blocking, no cast shadows: the staffs' own drawn shadows); `shadows_pillar` and
## `shadows_pillar_plain`, a close crop round a pillar with a candle at its foot and a wizard beside
## it, with spell light on and off, and `shadows_pillar_unblocked` the same frame with nothing
## blocking (as before phase C); `shadows_wizard`, a wizard's feet close (its shadow cast away from
## the candle); `shadows_crumble`
## and `shadows_crumble_pillar`, the room after its pillars are crumbled (their shadows eased away
## with them). The HUD is hidden, so the room's corners show.
##
## No room puts a candle by a pillar yet, and a candle's lit pool is small (about 25 px round: its
## light, 0.7 at 48 px reach, is below the floor's first step past that), smaller than a pillar's
## shadow needs to show. So the shot stands one there (the crypt's `candles` decal) with its light
## raised as a brazier's would be (STAGED_REACH, STAGED_STRENGTH), one wizard in the pillar's
## shadow from it (no shadow cast by it) and one in its light (its shadow cast away from it), to show
## what blocking does; the other two cast up the room.

const RegistryScript := preload("res://core/registry/registry.gd")
const CANDLES: PackedScene = preload("res://content/rooms/crypt/decals/candles.tscn")

## The crypt room shown and the pillar the close crops are of (the court's west one, its feet), where
## the candle stands from it (its decal's corner) with its raised light, and where the two wizards
## stand from it.
const ROOM: StringName = &"arena_03"
const PILLAR: Vector2 = Vector2(240, 256)
const CANDLE_FROM_PILLAR: Vector2 = Vector2(-52, -20)
const STAGED_REACH: float = 112.0
const STAGED_STRENGTH: float = 1.0
const IN_SHADOW_FROM_PILLAR: Vector2 = Vector2(34, -2)
const IN_LIGHT_FROM_PILLAR: Vector2 = Vector2(-20, 34)
## The close crops round the pillar (half their size, world px).
const CROP: Vector2i = Vector2i(64, 44)
## Frames: the party arriving before the staging, the staged crops after it (before the enemies'
## telegraphs cross them), and the fight after those before its shots.
const ARRIVE_FRAMES: int = 30
const STAGED_FRAMES: int = 8
const FIGHT_FRAMES: int = 120


func take() -> void:
	if not need(["PlayerInput", "Flow", "Registry", "Feel", "Events"]):
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
	for index in 4:
		input.call("add_virtual_device", index)
	flow.set("run_id_to_play", PinnedRun.pin(registry, room))
	if not flow.call("start_run", 0):
		fail("the run of %s did not start" % ROOM)
		return
	var hud := root.get_node_or_null("Hud") as CanvasLayer
	if hud != null:
		hud.visible = false
	feel.call("set_spell_light", true)
	await settle(ARRIVE_FRAMES)
	_stage(flow)
	# The staged two stand (a stick both aims and walks); the others cast up the room.
	for index in [2, 3]:
		input.call("send_virtual_aim", index, Vector2.UP)
		input.call("send_virtual", index, &"staff_1", 1.0)
	await settle(STAGED_FRAMES)
	# Held still, so the shot with nothing blocking is the same frame. Taken as the enemies arrive,
	# before their telegraphs cross the crop.
	paused = true
	await settle(2)
	var image: Image = await grab()
	save_crop(image, on_screen(PILLAR + Vector2(0, -16)), "shadows_pillar", CROP, 4)
	var wizard := flow.call("get_wizard", 1) as Node2D
	if wizard != null:
		save_crop(image, on_screen(wizard.global_position), "shadows_wizard", Vector2i(24, 18), 8)
	var light: Node = (feel.call("spectacle") as Node).get("light") as Node
	light.call("set_blockers", PackedVector4Array(), PackedVector4Array(), 0)
	await settle(1)
	save_crop(await grab(), on_screen(PILLAR + Vector2(0, -16)), "shadows_pillar_unblocked", CROP, 4)
	feel.call("set_spell_light", false)
	await settle(2)
	save_crop(await grab(), on_screen(PILLAR + Vector2(0, -16)), "shadows_pillar_plain", CROP, 4)
	feel.call("set_spell_light", true)
	paused = false
	# The fight under way, with spell light on and off.
	await settle(FIGHT_FRAMES)
	paused = true
	await settle(2)
	await shot("shadows_fight")
	feel.call("set_spell_light", false)
	await settle(2)
	await shot("shadows_fight_plain")
	feel.call("set_spell_light", true)
	paused = false
	_crumble_pillars()
	await settle(60)
	var crumbled: Image = await grab()
	save(crumbled, "shadows_crumble")
	save_crop(crumbled, on_screen(PILLAR + Vector2(0, -16)), "shadows_crumble_pillar", CROP, 4)
	for index in 4:
		input.call("send_virtual", index, &"staff_1", 0.0)


## A candle at the pillar's foot, its light raised, the first wizard in the pillar's shadow from it
## and the second in its light.
func _stage(flow: Node) -> void:
	var candle: Node2D = CANDLES.instantiate() as Node2D
	candle.position = PILLAR + CANDLE_FROM_PILLAR
	var light: Node = candle.get_node("Light")
	light.set_meta(LightSpot.REACH, STAGED_REACH)
	light.set_meta(LightSpot.STRENGTH, STAGED_STRENGTH)
	(current_scene if current_scene != null else root).add_child(candle)
	for seat in 2:
		var wizard := flow.call("get_wizard", seat) as Node2D
		if wizard != null:
			wizard.global_position = PILLAR + (IN_SHADOW_FROM_PILLAR if seat == 0 else IN_LIGHT_FROM_PILLAR)


## Every pillar in the room brought down (its health to nothing): their shadows ease out.
func _crumble_pillars() -> void:
	for node: Node in root.find_children("*", "Actor", true, false):
		var body := node as Actor
		if body != null and body.prop != null and body.prop.blocks_light and body.health != null:
			body.health.empty()


## The room's light spot (a candle's flame) nearest `to`, or null.
func _candle_nearest(to: Vector2) -> Node2D:
	var best: Node2D = null
	for node: Node in get_nodes_in_group(LightSpot.GROUP):
		var spot := node as Node2D
		if spot != null and (best == null or spot.global_position.distance_to(to) < best.global_position.distance_to(to)):
			best = spot
	return best
