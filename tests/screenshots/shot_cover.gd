extends "res://tests/support/screenshot.gd"
## Screenshots of ground cover (ground cover GC3 and GC8, docs/milestones/ground-cover.md): every room
## template a run's map can pick (content/rooms, found by folder, as `shot_rooms.gd`), each just after
## its run starts with four wizards in it, and the hub, under the game's own cover (content/cover:
## each biome's fill and the rooms' fields), a moment of its wind; then a fire lit in each, its
## embers and smoke rising (GC8). A new room or a new cover kind shows up here with no edit.
##
## Shots: `cover_<id>`, one a room; `cover_<id>_close`, its first player spawn's corner at 4×;
## `cover_<id>_fire`, a fire lit in the cover nearest that spawn, a moment later, at 4×.

const RoomScan := preload("res://tests/content/rooms/room_scan.gd")
const RegistryScript := preload("res://core/registry/registry.gd")
const FeelScript := preload("res://gameplay/feel/feel.gd")

## How far the fire reaches (px), and the frames it burns before its shot.
const FIRE_RADIUS: float = 20.0
const FIRE_FRAMES: int = 40

var _events: Node = null
var _feel: FeelScript = null


func take() -> void:
	if not need(["PlayerInput", "Flow", "Registry", "Feel", "Events"]):
		return
	settle_frames = 30
	var input: Node = root.get_node("PlayerInput")
	var flow: Node = root.get_node("Flow")
	var registry := root.get_node("Registry") as RegistryScript
	_feel = root.get_node("Feel") as FeelScript
	_events = root.get_node("Events")
	for index in 4:
		input.call("add_virtual_device", index)
	var templates: Array[RoomBase] = RoomScan.templates(registry)
	if templates.is_empty():
		fail("no room template was found")
		return
	for room: RoomBase in templates:
		flow.set("run_id_to_play", PinnedRun.pin(registry, room))
		if not flow.call("start_run", 0):
			fail("the run of %s did not start" % room.id)
			return
		if not await _shots(room):
			return
	flow.call("stop_run")
	await settle(3)
	_events.emit_signal("hub_requested", 0)
	if not await wait_for(func() -> bool: return flow.get("mode") == &"hub" and flow.call("get_wizard", 0) != null):
		fail("the hub did not start")
		return
	await _shots(registry.get_resource(&"rooms", &"hub") as RoomBase)
	flow.call("stop_run")


## The shots of `room`, laid: the whole room, its first spawn's corner, and a fire there. False
## when it was given no cover.
func _shots(room: RoomBase) -> bool:
	var layout: CoverLayout = _feel.cover().layout
	if layout == null or layout.count() == 0:
		fail("%s was given no cover" % room.id)
		return false
	await shot("cover_%s" % room.id)
	var spawns: PackedVector2Array = room.places().player_spawns
	if spawns.is_empty():
		return true
	await snap(spawns[0], "cover_%s_close" % room.id, Vector2i(64, 40))
	var fire: Vector2 = _burnable_near(layout, spawns[0])
	if fire.is_finite():
		_events.emit_signal("floor_touched", 0, &"fire", fire, FIRE_RADIUS)
		await settle(FIRE_FRAMES)
		await snap(fire, "cover_%s_fire" % room.id, Vector2i(64, 40))
	return true


## The middle of the covered cell nearest `at` whose kind fire moves on; INF for none.
func _burnable_near(layout: CoverLayout, at: Vector2) -> Vector2:
	var best: Vector2 = Vector2.INF
	for cell in layout.cells.size():
		var kind: CoverKind = layout.kind_at(cell)
		if kind == null or kind.states.is_empty() or kind.states[0].on_element(&"fire") == &"":
			continue
		var middle: Vector2 = layout.cell_rect(cell).get_center()
		if not best.is_finite() or middle.distance_squared_to(at) < best.distance_squared_to(at):
			best = middle
	return best
